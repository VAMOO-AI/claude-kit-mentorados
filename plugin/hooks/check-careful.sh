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

# rm recursivo — só quando não há undo (nem pasta descartável, nem git, nem temp da sessão)
if ms '\brm[[:space:]]+-[a-zA-Z]*[rR]'; then
  DESCARTAVEL='(node_modules|\.next|\.turbo|\.cache|__pycache__|coverage|playwright-report|/tmp/|/private/tmp/|/var/folders/|(^|[[:space:]/])(dist|build|out|tmp[-_a-zA-Z0-9]*|temp[-_a-zA-Z0-9]*)([[:space:]/]|$))'
  rm_ok=0
  ms "$DESCARTAVEL" && rm_ok=1
  ms '\bgit[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?rm\b' && rm_ok=1
  { ms 'mktemp' || ms '\btrap\b'; } && ms 'rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+"?\$' && rm_ok=1
  if [ "$rm_ok" = 0 ]; then
    ms 'rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)*["'"'"']?(~|/)' \
      && ask "[cuidado] rm recursivo em path absoluto (fora de repo, sem undo do git). Confirme o alvo."
    git -C "${cwd:-.}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
      || ask "[cuidado] rm recursivo fora de repo git (sem undo). Confirme o alvo."
  fi
fi

# git push --force. O flag TEM que estar no trecho do push (senão `git commit -F - && git push`
# dispara) e --force-with-lease é isento: ele já recusa se o remoto andou.
push_seg=$(printf '%s' "$c" | tr '\n' ';' | grep -oE 'git[[:space:]]+push[^;&|]*' 2>/dev/null)
if [ -n "$push_seg" ]; then
  sem_lease=$(printf '%s' "$push_seg" | sed 's/--force-with-lease[^[:space:]]*//g')
  printf '%s' "$sem_lease" | grep -qE '(^|[[:space:]])(--force|-f)([[:space:]]|=|$)' \
    && ask "[cuidado] git push --force (sem lease) reescreve a história remota sem checar se alguém empurrou antes. Confirme — ou use --force-with-lease."
fi

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

# Ler .env pelo terminal traz a credencial pro contexto — o deny de Read só cobre a
# ferramenta Read, o Bash passaria livre. `cat >> .env` é escrita e não conta.
if m '(\b(cat|head|tail|less|more|bat|strings|base64)\b|rtk[[:space:]]+read\b)[^|;&>]*\.env(\.[A-Za-z0-9_.-]+)?([[:space:]]|$)' \
   && ! m '\.env\.(example|1password|sample|template)' \
   && ! m 'grep[[:space:]]+-c'; then
  ask "[cuidado] ler .env/.env.local pelo terminal traz a credencial pro contexto. Pra saber só se a chave existe: grep -c '^CHAVE=' arquivo"
fi

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
