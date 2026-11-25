#!/usr/bin/env bash
# plugin/scripts/base-de-trabalho.sh e os diffs do ship.
#
# No kit, o origin/HEAD é o `stable` (o que o marketplace do mentorado segue) e todo PR entra
# na `main`. Os diffs do ship eram `origin/HEAD...HEAD`: com o stable atrás, o merge-base caía
# no stable, e TOCA_EDGE_FUNCTIONS, TEM_MIGRATION_NOVA e a lista de functions do §3c pegavam
# tudo o que a main andou desde ele. A ship mandava deployar function que o PR não tocou.
# O helper devolve a base de trabalho com a mesma regra do git-sync, do worktree-gc, do
# baseline e da limpeza-mac: git-sync.defaultBranch > origin/HEAD (a main, quando ele é um
# canal ancestral dela) > origin/main/master.
#
# Falham no base: o helper não existe, e os diffs do ship ainda usam origin/HEAD...HEAD.
#
# Uso: bash tests/test-base-de-trabalho.sh [caminho-do-helper]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
H="${1:-$RAIZ/plugin/scripts/base-de-trabalho.sh}"
case "$H" in /*) ;; *) H="$PWD/$H" ;; esac

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/base-trab.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando antes de tocar em /"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

igual() { # <esperado> <obtido> <descrição>
  if [ "$1" = "$2" ]; then printf '  ok    %s (%s)\n' "$3" "$2"
  else printf '  FALHA %s (obtido "%s", esperado "%s")\n' "$3" "$2" "$1"; falhas=$((falhas+1)); fi
}
base() { bash "$H" "$@" 2>/dev/null; }

ORIGIN="$TMP/origin.git"; R="$TMP/repo"
git init -q --bare -b main "$ORIGIN"
git init -q -b main "$R"
cd "$R" || exit 2
git config commit.gpgsign false
git commit -q --allow-empty -m base
git remote add origin "$ORIGIN"
git push -q origin main main:refs/heads/stable
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/stable
mkdir -p supabase/functions/velha; echo x > supabase/functions/velha/index.ts
git add supabase; git commit -qm "function da main, de outro PR"
git push -q origin main
git fetch -q origin
git remote set-head origin stable >/dev/null
git checkout -qb feat/x origin/main
mkdir -p supabase/functions/nova; echo y > supabase/functions/nova/index.ts
git add supabase; git commit -qm "function deste PR"

velho="$(git diff --name-only origin/HEAD...HEAD | sed -n 's#^supabase/functions/\([^/]*\)/.*#\1#p' | sort -u | tr '\n' ' ')"
[ "$velho" = "nova velha " ] || { echo "fixture inválida: origin/HEAD...HEAD deveria pegar a function da main ($velho)"; exit 2; }

echo "== helper =="
igual "origin/main" "$(base)" "origin/HEAD = stable atrás da main: a base é a main"
igual "origin/main" "$(base "$R")" "aceita o diretório do repo"
err="$(bash "$H" 2>&1 >/dev/null)"
case "$err" in *"origin/HEAD = stable"*) echo "  ok    stderr diz o porquê" ;; *) echo "  FALHA stderr sem o porquê: $err"; falhas=$((falhas+1)) ;; esac
fns="$(git diff --name-only "$(base)"...HEAD | sed -n 's#^supabase/functions/\([^/]*\)/.*#\1#p' | sort -u | tr '\n' ' ')"
igual "nova " "$fns" "o diff do §3c lista só a function deste PR"
git config git-sync.defaultBranch stable
igual "origin/stable" "$(base)" "git-sync.defaultBranch vence a detecção"
git config --unset git-sync.defaultBranch
DEV="$(git commit-tree -p origin/stable -m dev "origin/stable^{tree}")"
git push -q origin "$DEV":refs/heads/develop; git fetch -q origin
git remote set-head origin develop >/dev/null
igual "origin/develop" "$(base)" "origin/HEAD fora da linha da main continua a base"
git remote set-head origin main >/dev/null
igual "origin/main" "$(base)" "origin/HEAD = main: a main"
git remote set-head origin -d >/dev/null
igual "origin/main" "$(base)" "sem origin/HEAD: cai na origin/main"
bash "$H" "$TMP" >/dev/null 2>&1; rc=$?
igual 2 "$rc" "fora de um repo git sai 2"

echo "== ship não mede mais contra origin/HEAD =="
cd "$RAIZ" || exit 2
restos="$(grep -rn 'origin/HEAD\.\.\.HEAD' plugin/skills/ship 2>/dev/null)"
igual "" "$restos" "nenhum diff origin/HEAD...HEAD no ship"
usos="$(grep -rlF 'scripts/base-de-trabalho.sh' plugin/skills/ship | sort | tr '\n' ' ')"
igual "plugin/skills/ship/SKILL.md plugin/skills/ship/references/supabase-n8n.md " "$usos" "SKILL.md e supabase-n8n.md usam o helper"

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
