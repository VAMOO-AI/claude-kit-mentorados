#!/usr/bin/env bash
# PreToolUse(Bash): pede CONFIRMAÇÃO ("ask") antes de comandos irreversíveis.
# Mecaniza a regra "ops destrutivas exigem confirmação" — que como prosa pode ser
# ignorada no meio de um fluxo. Cobre só os IRREVERSÍVEIS de dado (não atrapalha o dia a dia).
# Lê o JSON via node (sem jq). Fail-open: sem node / sem match => não interfere.
H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
c="$(cat | node "$H" tool_input.command)"
[ -z "$c" ] && exit 0

ask() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}' \
    "$(printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify(s)))')"
  exit 0
}
m() { printf '%s' "$c" | grep -qiE "$1"; }

# rm recursivo/forçado — exceto pastas descartáveis comuns
if printf '%s' "$c" | grep -qE '\brm[[:space:]]+-[a-zA-Z]*[rR]'; then
  printf '%s' "$c" | grep -qE '(node_modules|\.next/|/dist|/build|coverage|\.turbo|__pycache__|\.cache|/tmp/)' \
    || ask "[cuidado] rm recursivo fora de pasta descartável. Confirme o alvo antes."
fi
# git push --force reescreve história remota
if m 'git[[:space:]]+push([[:space:]]|$)' && m '(^|[[:space:]])(--force(-with-lease)?|-f)([[:space:]]|=|$)'; then
  ask "[cuidado] git push --force/-f reescreve a história remota. Confirme que NÃO é branch compartilhada."
fi
# SQL destrutivo
m '\b(DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE([[:space:]]+TABLE)?)\b' && ask "[cuidado] SQL destrutivo (DROP/TRUNCATE). É produção? Confirme."
m 'supabase[[:space:]]+db[[:space:]]+reset'       && ask "[cuidado] supabase db reset apaga o banco. Confirme."
# git add amplo — leva staged de outra sessão / arquivo indesejado de carona
if m '(^|[;&|][[:space:]]*)git[[:space:]]+add[[:space:]]+(-[a-zA-Z]*[Au]\b|--all\b|\.([[:space:]]|$))'; then
  ask "[cuidado] git add amplo (-A/-u/--all/.). Prefira paths explícitos pra não commitar arquivo errado."
fi
exit 0
