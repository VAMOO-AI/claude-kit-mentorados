#!/usr/bin/env bash
# Prova do plugin/hooks/branch-guard.sh: avisa só quando a branch mudou entre dois
# prompts da MESMA sessão — nunca no primeiro prompt, nunca para outra sessão, nunca
# fora de repo git.
#
# Uso: bash tests/test-branch-guard.sh [caminho-do-hook]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/branch-guard.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }

falhas=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
FORA="$TMP/fora"; mkdir -p "$FORA"

run() { # <sid> <cwd>
  SID="$1" CWD="$2" node -e 'process.stdout.write(JSON.stringify({session_id:process.env.SID,cwd:process.env.CWD}))' | bash "$HOOK" 2>/dev/null
}
check() { # <vazio|avisa> <descrição> <saída>
  local got="vazio"; [ -n "$3" ] && got="avisa"
  if [ "$got" = "$1" ]; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (esperado %s, veio %s: %s)\n' "$2" "$1" "$got" "$3"; falhas=$((falhas+1)); fi
}

check vazio "primeiro prompt da sessão não avisa (não tem com o que comparar)" "$(run s1 "$REPO")"
check vazio "mesma branch no prompt seguinte: silêncio"                        "$(run s1 "$REPO")"
git -C "$REPO" switch -q -c feat/outra
OUT="$(run s1 "$REPO")"
check avisa "branch mudou entre prompts: avisa"                                "$OUT"
printf '%s' "$OUT" | grep -q 'main → feat/outra' && printf '  ok    diz de onde para onde\n' || { printf '  FALHA aviso sem o de→para\n'; falhas=$((falhas+1)); }
check vazio "prompt seguinte na branch nova: silêncio de novo"                 "$(run s1 "$REPO")"
check vazio "outra sessão vendo a mesma branch pela primeira vez: silêncio"    "$(run s2 "$REPO")"
check vazio "fora de repo git: silêncio"                                       "$(run s1 "$FORA")"
[ -f "$HOME/.claude/.cache/branch-guard/s1" ] && printf '  ok    marker por sessão em ~/.claude/.cache/branch-guard\n' || { printf '  FALHA sem marker\n'; falhas=$((falhas+1)); }

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
