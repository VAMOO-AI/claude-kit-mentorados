#!/usr/bin/env bash
# base-de-trabalho.sh — imprime a ref onde o trabalho do repo entra (origin/<branch>), a base
# certa para `git diff <base>...HEAD` de um PR.
#
# A default do GitHub nem sempre é essa base. No kit, o origin/HEAD é o `stable` (o canal do
# marketplace, que só anda por promoção) e todo PR vai para a main: `origin/HEAD...HEAD` tinha
# o merge-base no stable e pegava tudo o que a main andou desde ele (25/11/2026). A regra é a
# mesma do git-sync, do worktree-gc, do baseline e da limpeza-mac:
#   1. `git config git-sync.defaultBranch <b>` no repo fixa a base;
#   2. origin/HEAD = X ancestral de origin/main (ou master) → a main; X é um canal;
#   3. senão, o origin/HEAD;
#   4. sem origin/HEAD, origin/main ou origin/master (e o stderr pede o set-head).
# Deploy de produção não usa isto: ele segue a branch padrão do GitHub de propósito.
#
# Uso: base-de-trabalho.sh [diretório-do-repo]
#   stdout: a ref (origin/main); stderr: o porquê, quando não é o origin/HEAD.
#   exit 0 com a ref · 1 sem base nenhuma · 2 fora de um repo git
set -uo pipefail
[ -z "${1:-}" ] || cd "$1" 2>/dev/null || { echo "diretório inválido: $1" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "não é um repo git: $PWD" >&2; exit 2; }

existe() { git rev-parse --verify -q "refs/remotes/$1" >/dev/null; }

b="$(git config --get git-sync.defaultBranch 2>/dev/null)"
if [ -n "$b" ]; then
  existe "origin/$b" || { echo "git-sync.defaultBranch = $b, mas origin/$b não existe (git fetch origin?)" >&2; exit 1; }
  echo "origin/$b"; exit 0
fi

h="$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null)"
if [ -n "$h" ]; then
  # atalho: canal = ancestral da main ou master, sem ler a config do repo no GitHub; rever se um repo usar outro nome de base
  for w in origin/main origin/master; do
    [ "$h" = "$w" ] && break
    if existe "$w" && git merge-base --is-ancestor "$h" "$w" 2>/dev/null; then
      echo "base: $w (origin/HEAD = ${h#origin/}, ancestral de $w: o trabalho entra na ${w#origin/}; outra base: git config git-sync.defaultBranch <branch>)" >&2
      echo "$w"; exit 0
    fi
  done
  echo "$h"; exit 0
fi

for w in origin/main origin/master; do
  if existe "$w"; then
    echo "sem origin/HEAD: usando $w (git remote set-head origin --auto corrige)" >&2
    echo "$w"; exit 0
  fi
done
echo "sem base: nem origin/HEAD nem origin/main/master — git remote set-head origin --auto" >&2
exit 1
