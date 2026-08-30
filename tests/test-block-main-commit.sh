#!/usr/bin/env bash
# Prova de regressão do plugin/hooks/block-main-commit.sh.
#
# O falso positivo que originou esta suíte (30/08/2026): `cd` com o path ENTRE ASPAS não
# era reconhecido — o char class do sed excluía `"`, o cdp saía vazio, o hook caía no cwd
# da SESSÃO e bloqueava commit legítimo dentro de worktree. E aspas é a prática correta
# aqui: há repo com espaço no nome ("WELD MENTORIA /"). O hook punia o jeito certo.
#
# `cd $VAR` sem aspas "passava" por acidente, não por acerto: o tgt virava a string
# literal `$VAR`, o git não resolvia, a branch saía vazia e o case não casava.
#
# Uso: bash tests/test-block-main-commit.sh [caminho-do-hook]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/block-main-commit.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq ausente"; exit 2; }

falhas=0
MAIN=$(mktemp -d);  git -C "$MAIN" init -q -b main 2>/dev/null
FEAT=$(mktemp -d);  git -C "$FEAT" init -q -b feat/x 2>/dev/null
COM_ESPACO=$(mktemp -d)/"pasta com espaço"; mkdir -p "$COM_ESPACO"; git -C "$COM_ESPACO" init -q -b feat/y 2>/dev/null
trap 'rm -rf "$MAIN" "$FEAT" "$(dirname "$COM_ESPACO")"' EXIT

decide() { # decide <comando> [cwd]
  jq -nc --arg c "$1" --arg d "${2:-$MAIN}" '{cwd:$d, tool_input:{command:$c}}' \
    | bash "$HOOK" >/dev/null 2>&1
  [ "$?" = 2 ] && echo bloqueia || echo passa
}
check() { # check <esperado> <descrição> <comando> [cwd]
  local got; got=$(decide "$3" "${4:-}")
  if [ "$got" = "$1" ]; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (esperado %s, veio %s)\n' "$2" "$1" "$got"; falhas=$((falhas+1)); fi
}

echo "== tem que bloquear (é pra isso que ele existe) =="
check bloqueia "commit direto com a sessão em main"        'git commit -q -m x'
check bloqueia "cd pra repo em main"                       "cd $MAIN && git commit -m x"
check bloqueia "cd pra repo em main, com aspas"            "cd \"$MAIN\" && git commit -m x"
check bloqueia "git -C apontando pra main"                 "git -C $MAIN commit -m x"
check bloqueia "git -C com aspas apontando pra main"       "git -C \"$MAIN\" commit -m x"
check bloqueia "commit embutido em bash -c"                "bash -c 'git commit -m x'"

echo
echo "== não pode bloquear =="
check passa "cd pra worktree em feature branch"            "cd $FEAT && git commit -m x"
check passa "cd COM ASPAS pra feature branch (o falso positivo de 30/08)" \
                                                           "cd \"$FEAT\" && git commit -m x"
check passa "path com espaço só funciona com aspas"        "cd \"$COM_ESPACO\" && git commit -m x"
check passa "git -C pra feature branch"                    "git -C $FEAT commit -m x"
check passa "HOTFIX_MAIN=1 é a escotilha"                  'HOTFIX_MAIN=1 git commit -m x'
check passa "'git commit' dentro de string não é comando"  'grep -n "git commit" plugin/hooks/*.sh'
check passa "echo mencionando git commit"                  'echo "rode git commit depois"'
check passa "comando que não é commit"                     "cd $MAIN && git status"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
