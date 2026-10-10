#!/usr/bin/env bash
# PreToolUse(Bash): pede CONFIRMAÇÃO ("ask") antes de comandos irreversíveis.
# Mecaniza a regra "ops destrutivas exigem confirmação" — que como prosa pode ser
# ignorada no meio de um fluxo. Lê o JSON via node (sem jq). Fail-open: sem node /
# sem match => não interfere.
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
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
info="$(cat | node "$H" permission_mode cwd session_id tool_input.command)"
modo="$(printf '%s\n' "$info" | sed -n 1p)"
cwd="$(printf '%s\n' "$info"  | sed -n 2p)"
sid="$(printf '%s\n' "$info"  | sed -n 3p)"
c="$(printf '%s\n' "$info"    | sed '1,3d')"
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
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}' \
    "$(printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify(s)))')"
  exit 0
}
m()  { printf '%s' "$c" | grep -qiE "$1"; }   # case-insensitive: SQL, nomes de comando
ms() { printf '%s' "$c" | grep -qE  "$1"; }   # case-sensitive: flags (-f do force ≠ -F do heredoc)

# Segmentos do comando, sem o corpo de heredoc: `&&`, `||`, `;`, `|` e quebra de linha
# separam. Os blocos de rm, push, descarte local, segredo e variável de ambiente (0.48.0)
# decidem por segmento — testar no comando inteiro foi o defeito de 29/08 (o -F do heredoc
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
tem_mktemp=0; printf '%s' "$c_hd" | grep -qE '\bmktemp\b' && tem_mktemp=1
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

# git push (0.48.0). Normaliza `git -C <dir> push` e lê flag, refspec e o branch atual:
#   • force por flag agrupada (`-uf`), `--force` ou refspec com `+`; --force-with-lease e
#     --force-if-includes são isentos (recusam se o remoto andou);
#   • apagar por `--delete`/`-d` ou refspec `:branch`; `--mirror` e `--all`;
#   • destino main/master em qualquer forma (`main`, `HEAD:main`, `x:refs/heads/main`);
#   • `git push`/`git push origin` sem refspec (ou `HEAD`) estando na main/master.
alvo_main() { local d="${1#refs/heads/}"; [ "$d" = main ] || [ "$d" = master ]; }
push_segs=$(printf '%s\n' "$segs" | grep -E '(^|[[:space:]])git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)')
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  dir="${cwd:-.}"
  dir_c=$(printf '%s' "$seg" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+).*/\1/p')
  [ -n "$dir_c" ] && dir="$(desaspa "$dir_c")"
  args=$(printf '%s' "$seg" | sed -E 's/^(.*[[:space:]])?push([[:space:]]+|$)//')
  force=0; apaga=0; tudo=0; pos=(); pula=0; fim=0
  for w in $args; do
    if [ "$pula" = 1 ]; then pula=0; continue; fi
    if [ "$fim" = 0 ]; then
      case "$w" in
        --) fim=1; continue ;;
        --force-with-lease*|--force-if-includes|--no-force-if-includes) continue ;;
        --force|--force=*) force=1; continue ;;
        --delete) apaga=1; continue ;;
        --mirror|--all|--branches) tudo=1; continue ;;
        --push-option|--repo|--receive-pack|--exec) pula=1; continue ;;
        --*) continue ;;
        -[a-zA-Z]*)
          case "$w" in *f*) force=1 ;; esac
          case "$w" in *d*) apaga=1 ;; esac
          case "$w" in *o) pula=1 ;; esac
          continue ;;
      esac
    fi
    pos+=("$(desaspa "$w")")
  done
  refs=("${pos[@]:1}")
  main=0
  for r in "${refs[@]}"; do
    case "$r" in +*) force=1; r="${r#+}" ;; esac
    case "$r" in :*) apaga=1 ;; esac
    dst="${r##*:}"
    alvo_main "$dst" && main=1
    if [ "$dst" = HEAD ] || [ "$r" = HEAD ]; then
      atual=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)
      alvo_main "$atual" && main=1
    fi
  done
  if [ "${#refs[@]}" = 0 ]; then
    atual=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)
    alvo_main "$atual" && main=1
  fi
  [ "$force" = 1 ] && ask "[cuidado] git push --force (ou -f agrupado, ou refspec com +) reescreve a história remota sem checar se alguém empurrou antes. Confirme — ou use --force-with-lease."
  [ "$apaga" = 1 ] && ask "[cuidado] git push apagando branch remota (--delete, -d ou refspec :branch). Confirme."
  [ "$tudo" = 1 ] && ask "[cuidado] git push --mirror/--all empurra todas as branches, main incluída. Confirme."
  [ "$main" = 1 ] && ask "[cuidado] git push direto na main/master. O fluxo do kit é branch + PR. Confirme."
done <<< "$push_segs"

# Descartar alteração local não commitada (0.48.0): não há undo nenhum, nem do git.
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  printf '%s' "$seg" | grep -qE '(^|[[:space:]])git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+(checkout|switch|restore|stash)([[:space:]]|$)' || continue
  sub=$(printf '%s' "$seg" | sed -nE 's/.*git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+(checkout|switch|restore|stash)([[:space:]].*)?$/\2/p')
  args=" $(printf '%s' "$seg" | sed -E 's/^.*[[:space:]](checkout|switch|restore|stash)([[:space:]]+|$)//') "
  case "$sub" in
    checkout)
      printf '%s' "$args" | grep -qE '[[:space:]](--force|-[a-zA-Z]*f[a-zA-Z]*)[[:space:]]' \
        && ask "[cuidado] git checkout --force/-f descarta as alterações locais. Confirme."
      printf '%s' "$args" | grep -qE '[[:space:]](\.|:/|\*)[[:space:]]' \
        && ask "[cuidado] git checkout -- . descarta as alterações locais de tudo. Confirme." ;;
    switch)
      printf '%s' "$args" | grep -qE '[[:space:]](--discard-changes|--force|-[a-zA-Z]*f[a-zA-Z]*)[[:space:]]' \
        && ask "[cuidado] git switch --discard-changes/-f descarta as alterações locais. Confirme." ;;
    restore)
      if printf '%s' "$args" | grep -qE '[[:space:]](\.|:/|\*)[[:space:]]'; then
        if printf '%s' "$args" | grep -qE '[[:space:]](--staged|-S)[[:space:]]' && ! printf '%s' "$args" | grep -qE '[[:space:]](--worktree|-W)[[:space:]]'; then :
        else ask "[cuidado] git restore . descarta as alterações locais. Confirme."; fi
      fi ;;
    stash)
      printf '%s' "$args" | grep -qE '^[[:space:]]+(drop|clear)([[:space:]]|$)' \
        && ask "[cuidado] git stash drop/clear apaga o que estava guardado no stash. Confirme." ;;
  esac
done <<< "$segs"

# SQL destrutivo: só quando há EXECUTOR. Corpo de heredoc cuja linha de abertura não tem
# executor (`cat > x.sql <<SQL`, `python3 - <<PY`) é conteúdo sendo escrito, não comando.
# Tag que o parser não fecha engole o resto do comando — e aí o SQL destrutivo escrito
# DEPOIS do terminador some junto e o ask nunca dispara. Medido em 03/09/2026: um
# `cat > x.sql <<'END-OF-SQL' … END-OF-SQL` seguido de `psql -c "DROP TABLE users"`
# passava calado. Por isso o parser aceita tag com hífen/ponto, terminador indentado
# por tab do `<<-`, `EOF)` do `$(cat <<EOF` e ignora `<<<` (here-string, não heredoc).
if m '(psql|db-query\.sh|supabase[[:space:]]+db|PGPASSWORD|pgcli)' \
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
fi

# supabase db reset: o local é rotina de migration; só o remoto apaga dado que importa.
if m 'supabase[[:space:]]+db[[:space:]]+reset' && m '(--linked|--db-url)' \
   && ! m '(localhost|127\.0\.0\.1|:54322|host\.docker\.internal)'; then
  ask "[cuidado] supabase db reset em banco REMOTO apaga o banco. Confirme."
fi

# git add amplo — o risco é o index compartilhado entre sessões no mesmo clone.
# Worktree tem index próprio, então lá não pergunta.
if ms '(^|[;&|][[:space:]]*)git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?add[[:space:]]+(-[a-zA-Z]*[Au]\b|--all\b|\.)[[:space:]]*($|[;&|])'; then
  em_worktree=0
  case "$cwd" in *worktree*|*.worktrees*) em_worktree=1;; esac
  case "$c" in *worktree*) em_worktree=1;; esac
  [ -f "${cwd:-.}/.git" ] && em_worktree=1
  [ "$em_worktree" = 0 ] && ask "[cuidado] git add amplo (-A/-u/--all/.) em clone compartilhado. Prefira paths explícitos pra não commitar arquivo errado."
fi

# Segredo citado por QUALQUER comando (0.48.0). O deny de Read só cobre os comandos de
# arquivo que o Claude Code reconhece no Bash; `grep '' .env`, `awk 1 .env`, `git show
# HEAD:.env`, `ffmpeg -i .env` e os cmdlets do PowerShell passavam calados. Agora o texto do
# segmento basta. Isentos: .env.example/.sample/.template/.1password (públicos), escrita por
# redirecionamento (`>> .env.local`) e o que não imprime conteúdo (`grep -c/-q/-l`, test, ls,
# stat, echo/printf, mensagem de commit/PR — sem substituição de comando).
SEGREDO='(^|[^A-Za-z0-9_])\.env(\.[A-Za-z0-9_-]+)*($|[^A-Za-z0-9_.-])|\.ssh[/\\]|id_rsa|id_ed25519|id_ecdsa|\.pem($|[^A-Za-z0-9_])|\.aws[/\\]credentials|\.netrc|\.npmrc|\.claude\.json|\.config[/\\]gh[/\\]hosts\.yml|serviceAccountKey\.json'
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  limpo=$(printf '%s' "$seg" | sed -E 's/\.env(\.[A-Za-z0-9_-]+)*\.(example|sample|template|1password)//g; s/>>?[[:space:]]*[^[:space:]]+//g')
  printf '%s' "$limpo" | grep -qE "$SEGREDO" || continue
  case "$limpo" in *'$('*|*'`'*) ;; *)
    printf '%s' "$limpo" | grep -qE '^[[:space:]]*(grep|rg)[[:space:]]+(.*[[:space:]])?-[a-zA-Z]*[cqlL][a-zA-Z]*([[:space:]]|$)' && continue
    printf '%s' "$limpo" | grep -qE '^[[:space:]]*(test|\[|\[\[|ls|stat|echo|printf|touch|chmod|git[[:space:]]+(check-ignore|ls-files|commit|rm[[:space:]]+--cached)|gh[[:space:]]+(pr|issue)[[:space:]]+(create|comment|edit))([[:space:]]|$)' && continue
    printf '%s' "$limpo" | grep -qiE '^[[:space:]]*test-path([[:space:]]|$)' && continue
  ;; esac
  ask "[cuidado] o comando cita arquivo de segredo (.env, chave SSH, .pem, credencial de nuvem/gh/npm) e pode trazer a credencial pro contexto ou mandá-la pra fora. Pra saber só se a chave existe: grep -c '^CHAVE=' arquivo"
done <<< "$segs"

# Variáveis de ambiente inteiras (0.48.0): `env`, `printenv`, `export -p`, `set` e, no
# PowerShell, `Get-ChildItem Env:` mostram todos os tokens carregados de uma vez.
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  if printf '%s' "$seg" | grep -qE '^[[:space:]]*(env|printenv|set|export[[:space:]]+-p|export|declare[[:space:]]+-[a-zA-Z]*[xp][a-zA-Z]*)([[:space:]]+-0)?[[:space:]]*$|^[[:space:]]*printenv([[:space:]]|$)' \
     || printf '%s' "$seg" | grep -qiE '(^|[[:space:](])(get-childitem|gci|ls|dir|get-item|gi|get-content|gc)[[:space:]]+(-path[[:space:]]+|-literalpath[[:space:]]+)?["'"'"']?env:|\[(system\.)?environment\]::getenvironmentvariables'; then
    ask "[cuidado] listar as variáveis de ambiente mostra todos os tokens carregados. Pra uma só: echo \"\${NOME:+definida}\" (Bash) ou [bool]\$env:NOME (PowerShell)."
  fi
done <<< "$segs"

# Exfiltração de credencial pra fora da máquina. Nada mais no harness barra isso:
# permissions.deny só cobre o tool Read, e o `ask` de hook não freia subagent — mas na
# sessão interativa esta é a última chance antes do segredo sair.
# A credencial tem que estar DENTRO do segmento do comando de rede: testar as duas
# metades no comando inteiro dispara em `source .env.tokens; ...; curl`, que é o padrão
# mais comum aqui — 3.407 disparos no corpus de 30 dias contra 118 da versão por
# segmento. E o destino "dono" da credencial (a própria API do Supabase/n8n/GitHub) é
# isento: mandar a service_role PRO Supabase é o uso correto dela. Sobram 13 em 30 dias.
net_seg=$(printf '%s' "$c" | grep -oE '\b(curl|wget|nc|ncat|scp|rsync)\b[^;&|]*' 2>/dev/null)
if [ -n "$net_seg" ] \
   && printf '%s' "$net_seg" | grep -qiE '(\.env\b|\.env\.|id_rsa|id_ed25519|\.ssh/|SERVICE_ROLE|SERVICE_KEY|ANTHROPIC_API_KEY)' \
   && ! printf '%s' "$net_seg" | grep -qiE '\.env\.(example|sample|template)' \
   && ! printf '%s' "$net_seg" | grep -qiE '(supabase\.(co|com)|SUPABASE_URL|api\.github\.com|githubusercontent|api\.anthropic\.com|/rest/v1/|/auth/v1/|/functions/v1/|n8n|localhost|127\.0\.0\.1)'; then
  ask "[cuidado] comando de rede junto com arquivo/variável de credencial: isso pode estar MANDANDO segredo pra fora. Confirme o destino."
fi
exit 0
