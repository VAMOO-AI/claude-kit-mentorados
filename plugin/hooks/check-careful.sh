#!/usr/bin/env bash
# PreToolUse(Bash): pede CONFIRMAÇÃO ("ask") antes de comandos irreversíveis.
# Mecaniza a regra "ops destrutivas exigem confirmação" — que como prosa pode ser
# ignorada no meio de um fluxo. Cobre só os IRREVERSÍVEIS de dado (não atrapalha o dia a dia).
# Lê o JSON via node (sem jq). Fail-open: sem node / sem match => não interfere.
#
# ATENÇÃO ao mexer: um "ask" daqui ATRAVESSA o modo bypass. Cada falso positivo vira
# uma interrupção real no meio do trabalho. Em 29/08/2026 três regras foram corrigidas
# por isso (medição em 261 comandos reais: 139 interrupções indevidas eliminadas).
# Todo caso tem teste em tests/test-check-careful.sh — rode antes de commitar.
# Resolve o helper ao lado do próprio script (funciona rodando do plugin) e,
# se não achar, cai pro ~/.claude de quem instalou pelo install.sh.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
c="$(cat | node "$H" tool_input.command)"
[ -z "$c" ] && exit 0

ask() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}' \
    "$(printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify(s)))')"
  exit 0
}
m()  { printf '%s' "$c" | grep -qiE "$1"; }   # case-insensitive: SQL, nomes de comando
ms() { printf '%s' "$c" | grep -qE  "$1"; }   # case-sensitive: flags (-f do force ≠ -F do heredoc)

# rm recursivo/forçado — exceto pastas descartáveis comuns
if ms '\brm[[:space:]]+-[a-zA-Z]*[rR]'; then
  DESCARTAVEL='(node_modules|\.next|\.turbo|\.cache|__pycache__|coverage|playwright-report|/tmp/|/private/tmp/|/var/folders/|(^|[[:space:]/])(dist|build|out|tmp[-_a-zA-Z0-9]*|temp[-_a-zA-Z0-9]*)([[:space:]/]|$))'
  ms "$DESCARTAVEL" || ask "[cuidado] rm recursivo fora de pasta descartável. Confirme o alvo antes."
fi
# git push --force reescreve história remota. O flag TEM que estar no trecho do push:
# senão `git commit -F - <<EOF && git push` dispara (o -F do heredoc casava com o -f).
push_seg=$(printf '%s' "$c" | tr '\n' ';' | grep -oE 'git[[:space:]]+push[^;&|]*' 2>/dev/null)
if [ -n "$push_seg" ] && printf '%s' "$push_seg" | grep -qE '(^|[[:space:]])(--force(-with-lease)?|-f)([[:space:]]|=|$)'; then
  ask "[cuidado] git push --force/-f reescreve a história remota. Confirme que NÃO é branch compartilhada."
fi
# SQL destrutivo
m '\b(DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE([[:space:]]+TABLE)?)\b' && ask "[cuidado] SQL destrutivo (DROP/TRUNCATE). É produção? Confirme."
m 'supabase[[:space:]]+db[[:space:]]+reset'       && ask "[cuidado] supabase db reset apaga o banco. Confirme."
# git add amplo — leva staged de outra sessão / arquivo indesejado de carona
if ms '(^|[;&|][[:space:]]*)git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?add[[:space:]]+(-[a-zA-Z]*[Au]\b|--all\b|\.)[[:space:]]*($|[;&|])'; then
  ask "[cuidado] git add amplo (-A/-u/--all/.). Prefira paths explícitos pra não commitar arquivo errado."
fi
# Ler .env pelo terminal traz a credencial pro contexto — o deny de Read só cobre a
# ferramenta Read, o Bash passaria livre. `cat >> .env` é escrita e não conta.
if m '(\b(cat|head|tail|less|more|bat|strings|base64)\b|rtk[[:space:]]+read\b)[^|;&>]*\.env(\.[A-Za-z0-9_.-]+)?([[:space:]]|$)' && ! m '\.env\.example'; then
  ask "[cuidado] ler .env/.env.local pelo terminal traz a credencial pro contexto. Pra saber só se a chave existe: grep -c '^CHAVE=' arquivo"
fi
exit 0
