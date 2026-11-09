#!/usr/bin/env bash
# PreToolUse(Bash): pede CONFIRMAÇÃO ("ask") antes de comandos irreversíveis.
# Mecaniza a regra "ops destrutivas exigem confirmação" — que como prosa pode ser
# ignorada no meio de um fluxo. Lê o JSON via node (sem jq). Fail-open: sem node /
# sem match => não interfere.
#
# O QUE FICA AQUI (decisão D5 de 09/11/2026): só o que nenhuma regra declarativa expressa,
# porque depende de contexto que um glob não vê.
#   • `rm -rf` — o alvo decide (pasta descartável passa, o resto pergunta);
#   • SQL destrutivo/DDL — só quando há executor no comando, não em quem cita;
#   • `supabase db reset` — só o remoto;
#   • `git push` sem destino explícito — a branch ATUAL do repo-alvo decide; e o push que
#     apaga por refspec (`:branch`), que nenhum glob escreve: regra terminada em `:*` é lida
#     pelo Claude Code como o sufixo legado ` *`;
#   • `git add` amplo — só em clone, não em worktree;
#   • `.env` citado — quem imprime pergunta, quem só carrega ou escreve passa;
#   • rede + credencial no mesmo segmento (exfiltração).
# O QUE SAIU, e quem cobre: push --force/--delete/-d/--mirror/--all e destino main explícito,
# checkout/switch -f, restore ., stash drop/clear, listar o ambiente (env, printenv…) e
# chave/credencial fora do .env (.ssh, .pem, .aws, .netrc, .npmrc, gh, .claude.json) são das
# regras `ask`/`deny` de templates/settings.json. O hook as repetia, e pior: perguntava de
# novo o que a regra já tinha perguntado. Cada caso retirado tem asserção de regra em
# tests/test-merge-settings.sh ("o que saiu do check-careful").
#
# ATENÇÃO ao mexer: um "ask" daqui ATRAVESSA o modo bypass. Cada falso positivo vira
# uma interrupção real no meio do trabalho — e interrupção demais faz a pessoa desligar
# o hook inteiro, que é o pior desfecho possível. Duas recalibrações por medição:
#
#   29/08/2026 — 261 comandos reais, 139 interrupções indevidas eliminadas (o -F do
#   heredoc casava com o -f do force porque as duas metades da regra eram testadas no
#   comando inteiro, não no trecho do push).
#
#   30/08/2026 — corpus de 75.184 comandos Bash de 30 dias replayados contra o hook.
#   O que sobrava era quase todo operação COM undo. Por regra:
#     • --force-with-lease (48 de 56 disparos de push) recusa o push se o remoto andou:
#       é a variante segura, e é a que a skill ship manda usar. Isento.
#     • `git rm -r` é versionado — volta com git restore. Isento.
#     • `rm -rf` de path RELATIVO dentro de repo git tem o git como undo. Só pergunta
#       em path absoluto/~ ou fora de repo, que é onde a perda é definitiva.
#     • SQL destrutivo casava em quem CITA (`cat > x.sql <<SQL`, `grep "drop table"`,
#       `--dry-run`) e não em quem EXECUTA. Agora exige executor no comando.
#     • `supabase db reset` local é rotina de migration; só o remoto apaga dado real.
#     • `git add -A` só é risco em clone compartilhado — worktree tem index próprio.
#   (as duas primeiras regras, de push, hoje são das regras `ask` do template.)
#
# ESCOTILHA: prefixe o comando com CAREFUL_OFF=1 para o hook não opinar nele (mesmo
# idioma do HOTFIX_MAIN=1 do block-main-commit.sh).
# BYPASS: em permission_mode=bypassPermissions o hook se cala. Em bypass o `ask` não
# freia subagent nem workflow, então ele não é controle — é interrupção. Quem protege
# em bypass é `permissions.deny`, que a doc garante valer em TODO modo
# (https://code.claude.com/docs/en/permission-modes). CAREFUL_ON=1 traz o hook de volta.
#
# Todo caso tem teste em tests/test-check-careful.sh — rode antes de commitar.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
# Caminho do env-tem-chave.sh do próprio plugin, para a mensagem do segredo apontar o
# comando pronto (o `grep -c` de antes é negado pelo deny desde a 0.53.2).
ETC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/env-tem-chave.sh"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
# Dentro do pre-bash os campos já foram lidos (kit_campos, leitura única); fora dele,
# o próprio guard abre o node.
if [ "${KIT_CAMPOS_LIDOS:-}" = 1 ]; then info="$(kit_campos permission_mode cwd session_id tool_input.command)"; else info="$(cat | node "$H" permission_mode cwd session_id tool_input.command)"; fi
# Por expansão de parâmetro, sem `sed`: este hook roda em todo Bash, e cada processo a
# menos conta (F4 do núcleo único, #241: a cadeia tem teto de 120 ms).
modo="${info%%$'\n'*}"; info="${info#*$'\n'}"
cwd="${info%%$'\n'*}";  info="${info#*$'\n'}"
sid="${info%%$'\n'*}";  c="${info#*$'\n'}"
[ -z "$c" ] && exit 0
# A escotilha é lida do comando SEM o corpo de heredoc. Medido em 03/09/2026: um doc que
# apenas MENCIONA `CAREFUL_OFF=1` desligava o hook inteiro para o `rm -rf` real escrito
# depois do terminador. Mesmo parser do bloco SQL lá embaixo (duplicado porque lá ele tem
# a leniência do executor `ex`, que aqui não faz sentido).
c_hd=$(printf '%s\n' "$c" | awk '
    BEGIN { inhd=0; dash=0 }
    inhd {
      l=$0; if (dash) sub(/^\t+/, "", l)
      if (l == tag || l == tag";" || l == tag")" || l == tag")\"" || l == tag"\"") { inhd=0 }
      next
    }
    {
      print
      l=$0; gsub(/<<</, "", l)
      if (match(l, /<<-?[ \t]*[\047"]?[A-Za-z_][A-Za-z0-9_.-]*[\047"]?/)) {
        t = substr(l, RSTART, RLENGTH); dash = (t ~ /^<<-/)
        gsub(/^<<-?[ \t]*|[\047"]/, "", t); tag=t; inhd=1
      }
    }')
case "$c_hd" in *CAREFUL_OFF=1*) exit 0 ;; esac
if [ "${CAREFUL_ON:-}" != "1" ] && [ "$modo" = "bypassPermissions" ]; then
  # Este hook é a rede de proteção do kit, e em bypass ele fica MUDO. Quem liga o
  # bypass sem saber disso acha que continua protegido — então avisa uma vez por
  # sessão (marker), com o caminho pra ligar de volta. Silêncio virando falsa
  # sensação de segurança é o pior desfecho de um kit de ensino.
  aviso="${TMPDIR:-/tmp}/.careful-bypass-${sid:-sem-id}"
  if [ -n "$sid" ] && [ ! -f "$aviso" ]; then
    : > "$aviso" 2>/dev/null
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"modo bypassPermissions: o check-careful está DESLIGADO nesta sessão (ele não freia subagent em bypass, então vira só interrupção). O que ainda protege é o permissions.deny do settings.json. Para trazer as confirmações de volta nesta sessão, rode o Claude Code com CAREFUL_ON=1."}}'
  fi
  exit 0
fi

# Cada `ask` fica registrado: data, sessão, modo e a regra — nunca o comando, que pode
# carregar segredo. Aprovação concedida não deixa rastro no transcript (medido em
# 03/09/2026), então "por que está pedindo aprovação?" só se responde com este arquivo.
# CHECK_CAREFUL_LOG aponta outro arquivo; vazio desliga (é o que a suíte usa).
LOG="${CHECK_CAREFUL_LOG-$HOME/.claude/.cache/check-careful/decisoes.tsv}"
registra() {
  [ -n "$LOG" ] || return 0
  mkdir -p "${LOG%/*}" 2>/dev/null || return 0
  printf '%s\t%s\t%s\task\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "${sid:-?}" "${modo:-?}" "$1" >> "$LOG" 2>/dev/null || true
}

ask() {
  registra "$1"
  # JSON em bash, sem um segundo node: a razão só tem texto nosso e o caminho do ETC.
  local r="$1"
  r="${r//\\/\\\\}"; r="${r//\"/\\\"}"; r="${r//$'\n'/\\n}"; r="${r//$'\t'/\\t}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}' "$r"
  exit 0
}
m()  { printf '%s' "$c" | grep -qiE "$1"; }   # case-insensitive: SQL, nomes de comando
ms() { printf '%s' "$c" | grep -qE  "$1"; }   # case-sensitive: flags (-f do force ≠ -F do heredoc)

# Segmentos do comando, sem o corpo de heredoc: `&&`, `||`, `;`, `|` e quebra de linha
# separam. Os blocos de rm, push e segredo decidem por segmento — testar no comando inteiro foi o defeito de 29/08 (o -F do heredoc
# casando com o -f do force). Vale para Bash e PowerShell: o pre-bash.sh entrega os dois.
segs=$(printf '%s\n' "$c_hd" | awk '{ gsub(/&&|\|\||;|\|/, "\n"); print }')
desaspa() { local a="$1"; a="${a#[\"\']}"; a="${a%[\"\']}"; printf '%s' "$a"; }

# rm recursivo (0.48.0): o `acceptEdits` aprova `rm` dentro do projeto sem perguntar, e o
# git não é undo de pasta ignorada — `rm -rf outputs` apagava mídia fora do git calado. Só
# passa sem pergunta quando TODO alvo é pasta descartável (regenerável) ou temporária.
# Vale para `rm -r` e para `Remove-Item -Recurse` (e os aliases ri/del/rd/rmdir/erase).
alvo_descartavel() {
  local a; a="$(desaspa "$1")"
  case "$a" in /tmp/*|/private/tmp/*|/var/folders/*|'$TMPDIR'*|'${TMPDIR'*) return 0 ;; esac
  if [ "$tem_mktemp" = 1 ]; then case "$a" in '$'*) return 0 ;; esac; fi
  a="${a%/\*}"; a="${a%\\\*}"; a="${a%/}"; a="${a%\\}"
  local b="${a##*/}"; b="${b##*\\}"
  case "$b" in
    node_modules|.next|dist|build|out|coverage|.turbo|.cache|.parcel-cache|__pycache__|.pytest_cache|tmp|.venv) return 0 ;;
    tmp[-_]*|temp|temp[-_]*) return 0 ;;
  esac
  return 1
}
tem_mktemp=0; [[ $c_hd == *mktemp* ]] && tem_mktemp=1
# Pré-filtro sem processo: sem um dos comandos de apagar, o laço nem abre.
shopt -s nocasematch
if [[ $c_hd =~ (^|[^A-Za-z0-9_-])(rm|remove-item|ri|del|erase|rd|rmdir)([[:space:]]|$) ]]; then
shopt -u nocasematch
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  case "$seg" in *[![:space:]]*) ;; *) continue ;; esac
  printf '%s' "$seg" | grep -qE '^[[:space:]]*trap[[:space:]]' && continue
  printf '%s' "$seg" | grep -qE '\bgit[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?rm\b' && continue
  resto=""
  if printf '%s' "$seg" | grep -qE '(^|[[:space:]])rm[[:space:]]+(-[^[:space:]]*[[:space:]]+)*-[a-zA-Z]*[rR]|(^|[[:space:]])rm[[:space:]].*--recursive' \
     && ! printf '%s' "$seg" | grep -qiE '(^|[[:space:]])(remove-item)'; then
    resto=$(printf '%s' "$seg" | sed -E 's/^(.*[[:space:]])?rm[[:space:]]+//')
    ps=0
  elif printf '%s' "$seg" | grep -qiE '(^|[[:space:]])(remove-item|ri|rm|del|erase|rd|rmdir)[[:space:]](.*[[:space:]])?-(recurse|r)([[:space:]]|$)'; then
    resto=$(printf '%s' "$seg" | sed -E 's/^(.*[[:space:]])?([Rr][Ee][Mm][Oo][Vv][Ee]-[Ii][Tt][Ee][Mm]|ri|rm|del|erase|rd|rmdir)[[:space:]]+//')
    ps=1
  else
    continue
  fi
  pula=0; fim_opcoes=0; alvos=0; ruim=""
  for w in $resto; do
    if [ "$pula" = 1 ]; then pula=0; continue; fi
    if [ "$fim_opcoes" = 0 ]; then
      case "$w" in
        --) fim_opcoes=1; continue ;;
        -[Ee]rror[Aa]ction|-ea|-[Ff]ilter|-[Ii]nclude|-[Ee]xclude|-[Cc]redential) [ "$ps" = 1 ] && pula=1; continue ;;
        -*) continue ;;
      esac
    fi
    alvos=$((alvos+1))
    alvo_descartavel "$w" || { ruim="$w"; break; }
  done
  if [ -n "$ruim" ]; then
    ask "[cuidado] apagar pasta inteira (rm -r / Remove-Item -Recurse) fora das descartáveis (node_modules, .next, dist, build…): $ruim. O git não devolve arquivo ignorado. Confirme o alvo."
  fi
done <<< "$segs"
fi
shopt -u nocasematch

# git push sem destino explícito, estando na main/master. É o único caso de push que glob
# nenhum expressa: `git push`, `git push origin` e `git push -u origin HEAD` são o push de
# rotina numa feature branch e vão direto na main quando a branch atual é ela. Force,
# --delete, --mirror/--all e o destino main ESCRITO no comando são das regras `ask` do
# template (e o force na main, do `deny`). O refspec `:branch`, que apaga a branch remota,
# fica aqui pelo motivo do cabeçalho; pergunta sempre, como a regra do `--delete`.
# Só conta o push em posição de comando: o corpo de heredoc já saiu, e "git push" citado
# numa string do python, num doc ou num caso de teste não começa segmento. O branch é o do
# repo-alvo, seguindo o `cd` do próprio comando e o `git -C <dir>`; `cd` com variável deixa o
# branch desconhecido, e aí o hook não pergunta. HOTFIX_MAIN=1 (a escotilha do
# block-main-commit) cala a regra. Medido no time em 15/10/2026 (30 dias): 98 disparos sem a
# posição, a maioria texto; 48 com ela e sem seguir o `cd`.
case "$c_hd" in *push*)
alvo_main() { local d="${1#refs/heads/}"; [ "$d" = main ] || [ "$d" = master ]; }
branch_de() { [ -n "$1" ] && git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null; }
hotfix=0
[[ $c_hd =~ (^|[[:space:]\;\&\|\(])HOTFIX_MAIN=1([[:space:]]|\;|$) ]] && hotfix=1
# O começo de cada segmento sem `(`/`$(`, atribuição de variável e lançador (rtk, sudo,
# command, nice, time, timeout N): é o que fica antes do `git` sem mudar o que ele faz.
segs_cmd=$(printf '%s\n' "$segs" | sed -E 's/^[[:space:]]*(\(|\$\()?[[:space:]]*//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|(rtk|sudo|command|nice|time)[[:space:]]+|timeout[[:space:]]+[0-9]+[smhd]?[[:space:]]+)*//')
here="${cwd:-.}"
while IFS= read -r seg; do
  case "$seg" in
    cd|'cd '|cd$'\t') here="$HOME"; continue ;;
    'cd '*')'*) continue ;;   # `(cd x)`: o cd morre com o subshell
    'cd '*)
      alvo="${seg#cd }"; alvo="${alvo#"${alvo%%[![:space:]]*}"}"; alvo="${alvo%%[[:space:]]*}"
      alvo="$(desaspa "$alvo")"
      case "$alvo" in
        *'$'*|*'`'*|-*) here="" ;;
        '~'|'~/'*) here="$HOME${alvo#\~}" ;;
        /*) here="$alvo" ;;
        *) [ -n "$here" ] && here="$here/$alvo" ;;
      esac
      continue ;;
  esac
  [[ $seg =~ ^git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+push([[:space:]]|$) ]] || continue
  dir="$here"
  if [[ $seg =~ ^git[[:space:]]+-[Cc][[:space:]]+(\"[^\"]*\"|\'[^\']*\'|[^[:space:]]+) ]]; then
    dir_c="$(desaspa "${BASH_REMATCH[1]}")"
    case "$dir_c" in *'$'*|*'`'*) dir="" ;; /*) dir="$dir_c" ;; '~'*) dir="$HOME${dir_c#\~}" ;; *) [ -n "$dir" ] && dir="$dir/$dir_c" ;; esac
  fi
  args="${seg#*push}"
  pos=(); pula=0; fim=0
  for w in $args; do
    if [ "$pula" = 1 ]; then pula=0; continue; fi
    if [ "$fim" = 0 ]; then
      case "$w" in
        --) fim=1; continue ;;
        --push-option|--repo|--receive-pack|--exec) pula=1; continue ;;
        --*) continue ;;
        -[a-zA-Z]*) case "$w" in *o) pula=1 ;; esac; continue ;;
      esac
    fi
    pos+=("$(desaspa "$w")")
  done
  refs=(${pos[@]+"${pos[@]:1}"})
  main=0; apaga=""
  for r in ${refs[@]+"${refs[@]}"}; do
    r="${r#+}"
    case "$r" in :?*) apaga="$r" ;; esac
    if [ "${r##*:}" = HEAD ] || [ "$r" = HEAD ]; then alvo_main "$(branch_de "$dir")" && main=1; fi
  done
  [ -n "$apaga" ] && ask "[cuidado] git push apagando branch remota por refspec ($apaga). Confirme."
  if [ "${#refs[@]}" = 0 ]; then alvo_main "$(branch_de "$dir")" && main=1; fi
  [ "$hotfix" = 1 ] && main=0
  [ "$main" = 1 ] && ask "[cuidado] git push sem destino explícito com a branch atual na main/master: vai direto na main. O fluxo do kit é branch + PR. Confirme."
done <<< "$segs_cmd"
;; esac

# SQL destrutivo: só quando há EXECUTOR. Corpo de heredoc cuja linha de abertura não tem
# executor (`cat > x.sql <<SQL`, `python3 - <<PY`) é conteúdo sendo escrito, não comando.
# Tag que o parser não fecha engole o resto do comando — e aí o SQL destrutivo escrito
# DEPOIS do terminador some junto e o ask nunca dispara. Medido em 03/09/2026: um
# `cat > x.sql <<'END-OF-SQL' … END-OF-SQL` seguido de `psql -c "DROP TABLE users"`
# passava calado. Por isso o parser aceita tag com hífen/ponto, terminador indentado
# por tab do `<<-`, `EOF)` do `$(cat <<EOF` e ignora `<<<` (here-string, não heredoc).
shopt -s nocasematch; tem_sql=0; [[ $c =~ (psql|db-query\.sh|supabase[[:space:]]+db|PGPASSWORD|pgcli) ]] && tem_sql=1; shopt -u nocasematch
if [ "$tem_sql" = 1 ] && m '(psql|db-query\.sh|supabase[[:space:]]+db|PGPASSWORD|pgcli)' \
   && ! m '(--check|--dry-run)' && ! m 'docker[[:space:]]+exec'; then
  c_exec=$(printf '%s\n' "$c" | awk -v ex='psql|db-query\\.sh|supabase[ \t]+db|PGPASSWORD|pgcli' '
    BEGIN { inhd=0; dash=0 }
    inhd {
      l=$0; if (dash) sub(/^\t+/, "", l)
      if (l == tag || l == tag";" || l == tag")" || l == tag")\"" || l == tag"\"") { inhd=0 }
      next
    }
    {
      print
      l=$0; gsub(/<<</, "", l)
      if (match(l, /<<-?[ \t]*[\047"]?[A-Za-z_][A-Za-z0-9_.-]*[\047"]?/)) {
        t = substr(l, RSTART, RLENGTH); dash = (t ~ /^<<-/)
        gsub(/^<<-?[ \t]*|[\047"]/, "", t)
        if ($0 !~ ex) { tag=t; inhd=1 }
      }
    }')
  printf '%s' "$c_exec" | grep -qiE '\b(DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE([[:space:]]+TABLE)?)\b' \
    && ask "[cuidado] SQL destrutivo (DROP/TRUNCATE) sendo EXECUTADO. É produção? Confirme."
  # DDL também (do kit do time): CREATE/ALTER TABLE direto no banco muda o schema de quem
  # usa o banco, e em produção não tem desfazer simples.
  printf '%s' "$c_exec" | grep -qiE '\b(CREATE|ALTER)[[:space:]]+TABLE\b' \
    && ask "[cuidado] DDL (CREATE/ALTER TABLE) direto no banco. É produção? Confirme."
fi

# supabase db reset: o local é rotina de migration; só o remoto apaga dado que importa.
if [[ $c == *supabase* ]] && m 'supabase[[:space:]]+db[[:space:]]+reset' && m '(--linked|--db-url)' \
   && ! m '(localhost|127\.0\.0\.1|:54322|host\.docker\.internal)'; then
  ask "[cuidado] supabase db reset em banco REMOTO apaga o banco. Confirme."
fi

# git add amplo — o risco é o index compartilhado entre sessões no mesmo clone.
# Worktree tem index próprio, então lá não pergunta.
if [[ $c == *add* ]] && ms '(^|[;&|][[:space:]]*)git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?add[[:space:]]+(-[a-zA-Z]*[Au]\b|--all\b|\.)[[:space:]]*($|[;&|])'; then
  em_worktree=0
  case "$cwd" in *worktree*|*.worktrees*) em_worktree=1;; esac
  case "$c" in *worktree*) em_worktree=1;; esac
  [ -f "${cwd:-.}/.git" ] && em_worktree=1
  [ "$em_worktree" = 0 ] && ask "[cuidado] git add amplo (-A/-u/--all/.) em clone compartilhado. Prefira paths explícitos pra não commitar arquivo errado."
fi

# `.env` citado por QUALQUER comando (0.48.0). O deny de Read só cobre os comandos de
# arquivo que o Claude Code reconhece no Bash; `grep '' .env`, `awk 1 .env`, `git show
# HEAD:.env`, `ffmpeg -i .env` e os cmdlets do PowerShell passavam calados. Agora o texto do
# segmento basta. Fica no hook porque a decisão depende do que o comando FAZ com o arquivo, e
# um `ask` por glob (`*.env*`) perguntaria em `source .env.local`, `cp .env.example .env` e
# `grep -rn process.env src`. Chave SSH, .pem e credencial de nuvem/gh/npm saíram daqui em
# 09/11/2026: são das regras `ask` do template (`Bash(*.ssh/*)`, `Bash(*.pem*)`…). Isentos: .env.example/.sample/.template/.1password (públicos), escrita por
# redirecionamento (`>> .env.local`) e o que não imprime conteúdo (`grep -c/-q/-l`, test, ls,
# stat, echo/printf, mensagem de commit/PR — sem substituição de comando).
SEGREDO='(^|[^A-Za-z0-9_])\.env(\.[A-Za-z0-9_-]+)*($|[^A-Za-z0-9_.-])|[A-Za-z0-9_-]\.env($|[^A-Za-z0-9_.-])'
if [[ $c_hd =~ $SEGREDO ]]; then
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  limpo=$(printf '%s' "$seg" | sed -E 's/\.env(\.[A-Za-z0-9_-]+)*\.(example|sample|template|1password)//g; s/(process|import\.meta|Deno)\.env//g; s/>>?[[:space:]]*[^[:space:]]+//g')
  printf '%s' "$limpo" | grep -qE "$SEGREDO" || continue
  # Meio-termo (decisão do Ruan na F4 do núcleo único): quem só CARREGA o segredo no ambiente,
  # sem ele chegar ao contexto, passa. `source`/`.`, `--env-file`, a captura numa variável
  # (`export X=$(grep ^X= .env | cut …)`) e `env $(cat x.env) cmd`. O que imprime ou manda
  # continua perguntando: `echo $(cat .env)`, `cat`, `grep` sem -c, rede com credencial.
  [[ $limpo =~ ^[[:space:]]*(source|\.)[[:space:]] ]] && continue
  [[ $limpo == *--env-file* ]] && continue
  [[ $limpo =~ ^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=\$\( ]] && continue
  [[ $limpo =~ ^[[:space:]]*env[[:space:]]+\$\( ]] && continue
  # Operação de arquivo (copiar, mover, apagar, ligar) não imprime o conteúdo.
  [[ $limpo =~ ^[[:space:]]*(cp|mv|rm|ln|install|unlink)[[:space:]] ]] && continue
  case "$limpo" in *'$('*|*'`'*) ;; *)
    printf '%s' "$limpo" | grep -qE '^[[:space:]]*(grep|rg)[[:space:]]+(.*[[:space:]])?-[a-zA-Z]*[cqlL][a-zA-Z]*([[:space:]]|$)' && continue
    printf '%s' "$limpo" | grep -qE '^[[:space:]]*(test|\[|\[\[|ls|stat|echo|printf|touch|chmod|git[[:space:]]+(check-ignore|ls-files|commit|rm[[:space:]]+--cached)|gh[[:space:]]+(pr|issue)[[:space:]]+(create|comment|edit))([[:space:]]|$)' && continue
    printf '%s' "$limpo" | grep -qiE '^[[:space:]]*test-path([[:space:]]|$)' && continue
  ;; esac
  ask "[cuidado] o comando cita um arquivo .env e pode trazer a credencial pro contexto ou mandá-la pra fora. Pra saber só se a chave existe, sem ver o valor: bash $ETC arquivo CHAVE"
done <<< "$segs"
fi

# Exfiltração de credencial pra fora da máquina. Regra declarativa não expressa "comando de
# rede E credencial no mesmo segmento, para um destino que não é o dono dela"; o `ask` de
# hook não freia subagent, mas na sessão interativa esta é a última chance antes do segredo sair.
# A credencial tem que estar DENTRO do segmento do comando de rede: testar as duas
# metades no comando inteiro dispara em `source .env.tokens; ...; curl`, que é o padrão
# mais comum aqui — 3.407 disparos no corpus de 30 dias contra 118 da versão por
# segmento. E o destino "dono" da credencial (a própria API do Supabase/n8n/GitHub) é
# isento: mandar a service_role PRO Supabase é o uso correto dela. Sobram 13 em 30 dias.
net_seg=""
shopt -s nocasematch; [[ $c =~ (curl|wget|nc|ncat|scp|rsync) ]] && net_seg=$(printf '%s' "$c" | grep -oE '\b(curl|wget|nc|ncat|scp|rsync)\b[^;&|]*' 2>/dev/null); shopt -u nocasematch
if [ -n "$net_seg" ] \
   && printf '%s' "$net_seg" | grep -qiE '(\.env\b|\.env\.|id_rsa|id_ed25519|\.ssh/|SERVICE_ROLE|SERVICE_KEY|ANTHROPIC_API_KEY)' \
   && ! printf '%s' "$net_seg" | grep -qiE '\.env\.(example|sample|template)' \
   && ! printf '%s' "$net_seg" | grep -qiE '(supabase\.(co|com)|SUPABASE_URL|api\.github\.com|githubusercontent|api\.anthropic\.com|/rest/v1/|/auth/v1/|/functions/v1/|n8n|localhost|127\.0\.0\.1)'; then
  ask "[cuidado] comando de rede junto com arquivo/variável de credencial: isso pode estar MANDANDO segredo pra fora. Confirme o destino."
fi
exit 0
