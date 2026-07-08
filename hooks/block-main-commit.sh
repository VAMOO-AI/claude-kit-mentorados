#!/usr/bin/env bash
# PreToolUse(Bash): bloqueia `git commit` que cairia em main/master.
# Mais robusto que a checagem por substring:
#   1) NÃO bloqueia quando "git commit" aparece dentro de string (grep/echo).
#   2) Checa a branch do REPO-ALVO real (git -C <path> ou primeiro `cd <path>`), não só o cwd.
# Override: prefixe o comando com HOTFIX_MAIN=1 (commit em main proposital).
# Lê o JSON do hook via node (sem depender de jq). Falha-aberta: erro => exit 0.
H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
j="$(cat)"
c="$(printf '%s' "$j" | node "$H" tool_input.command)"
cwd="$(printf '%s' "$j" | node "$H" cwd)"
[ -z "$c" ] && exit 0
case "$c" in *HOTFIX_MAIN=1*) exit 0 ;; esac

# Detecta `git commit` como COMANDO (posição de comando), não como argumento de string.
is_commit=0
if printf '%s\n' "$c" | grep -qE '(^|;|&&|\|\||\()[[:space:]]*git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$)'; then
  is_commit=1
fi
# Também pega commits embutidos em bash -c / sh -c.
if [ "$is_commit" = 0 ] \
   && printf '%s' "$c" | grep -qE '(bash|sh)[[:space:]]+-c' \
   && printf '%s\n' "$c" | grep -qE 'git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit'; then
  is_commit=1
fi
[ "$is_commit" = 0 ] && exit 0

# Resolve o repo-alvo: git -C <path>  >  primeiro cd <path>  >  cwd da sessão.
tgt="${cwd:-.}"
p=$(printf '%s' "$c" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
if [ -n "$p" ]; then
  tgt="$p"
else
  cdp=$(printf '%s' "$c" | sed -nE "s/.*cd[[:space:]]+([^[:space:]'\";&|]+).*/\1/p" | head -1)
  [ -n "$cdp" ] && tgt="$cdp"
fi

b=$(git -C "$tgt" branch --show-current 2>/dev/null)
case "$b" in
  main|master)
    echo "BLOQUEADO pelo hook: git commit cairia na branch '$b' (repo: $tgt). Crie uma feature branch antes (ex.: git checkout -b feat/minha-mudanca). Se foi proposital, rode o comando com HOTFIX_MAIN=1 na frente." >&2
    exit 2
    ;;
esac
exit 0
