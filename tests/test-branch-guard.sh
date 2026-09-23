#!/usr/bin/env bash
# Prova do plugin/hooks/branch-guard.sh: avisa só quando a branch mudou entre dois
# prompts da MESMA sessão no MESMO repositório — nunca no primeiro prompt, nunca para outra
# sessão, nunca fora de repo git. Entrar ou sair de um worktree também não é troca de
# branch: clone e worktree têm raízes diferentes, e o marcador é por sessão e por raiz.
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
WT="$TMP/wt"

run() { # <sid> <cwd>
  SID="$1" CWD="$2" node -e 'process.stdout.write(JSON.stringify({session_id:process.env.SID,cwd:process.env.CWD}))' | bash "$HOOK" 2>/dev/null
}
check() { # <vazio|avisa> <descrição> <saída>
  local got="vazio"; [ -n "$3" ] && got="avisa"
  if [ "$got" = "$1" ]; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (esperado %s, veio %s: %s)\n' "$2" "$1" "$got" "$3"; falhas=$((falhas+1)); fi
}
de_para() { # <texto esperado> <saída>
  printf '%s' "$2" | grep -q "$1" && printf '  ok    diz de onde para onde (%s)\n' "$1" || { printf '  FALHA aviso sem o de→para %s (veio: %s)\n' "$1" "$2"; falhas=$((falhas+1)); }
}

check vazio "primeiro prompt da sessão não avisa (não tem com o que comparar)" "$(run s1 "$REPO")"
check vazio "mesma branch no prompt seguinte: silêncio"                        "$(run s1 "$REPO")"
git -C "$REPO" switch -q -c feat/outra
OUT="$(run s1 "$REPO")"
check avisa "branch mudou entre prompts: avisa"                                "$OUT"
de_para 'main → feat/outra' "$OUT"
check vazio "prompt seguinte na branch nova: silêncio de novo"                 "$(run s1 "$REPO")"
check vazio "outra sessão vendo a mesma branch pela primeira vez: silêncio"    "$(run s2 "$REPO")"
check vazio "fora de repo git: silêncio"                                       "$(run s1 "$FORA")"

echo
echo "== a própria sessão entrando e saindo de worktree: silêncio =="
git -C "$REPO" worktree add -q -b feat/wt "$WT"
check vazio "clone → worktree, mesma sessão: silêncio"                         "$(run s1 "$WT")"
check vazio "worktree → clone de volta: silêncio"                              "$(run s1 "$REPO")"
check vazio "clone → worktree de novo: silêncio"                               "$(run s1 "$WT")"

echo
echo "== checkout feito de fora continua avisando =="
git -C "$REPO" switch -q main
OUT="$(run s1 "$REPO")"
check avisa "checkout de fora no mesmo clone: avisa"                           "$OUT"
de_para 'feat/outra → main' "$OUT"
git -C "$WT" switch -q -c feat/wt2
check avisa "checkout de fora no worktree: avisa"                              "$(run s1 "$WT")"
mkdir -p "$REPO/sub"; git -C "$REPO" switch -q feat/outra
check avisa "subpasta do clone usa o marcador do clone: avisa"                 "$(run s1 "$REPO/sub")"

n=$(ls -1 "$HOME/.claude/.cache/branch-guard" 2>/dev/null | grep -c '^s1-')
[ "$n" = 2 ] && printf '  ok    um marcador por sessão e raiz (clone e worktree) em ~/.claude/.cache/branch-guard\n' || { printf '  FALHA esperava 2 marcadores s1-<raiz>, achei %s\n' "$n"; falhas=$((falhas+1)); }
# O hook faz o hash do caminho que o git devolve: no Mac o mktemp vive em /private/var.
H=$(printf '%s' "$(git -C "$REPO" rev-parse --show-toplevel)" | cksum | cut -d' ' -f1)
[ -f "$HOME/.claude/.cache/branch-guard/s1-$H" ] && printf '  ok    o marcador do clone é s1-<cksum da raiz>\n' || { printf '  FALHA sem o marcador s1-%s: %s\n' "$H" "$(ls "$HOME/.claude/.cache/branch-guard" 2>&1)"; falhas=$((falhas+1)); }

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
