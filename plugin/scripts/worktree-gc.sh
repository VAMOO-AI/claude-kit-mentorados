#!/usr/bin/env bash
# worktree-gc.sh — coleta-de-lixo de git worktrees.
#
# Remove worktrees em .claude/worktrees/ cuja branch JÁ FOI MERGEADA (ancestral de
# origin/main OU squash-merge detectado via `gh pr`), e que estejam LIMPOS (sem
# mudança não-commitada). Nunca toca: clone principal, branch main/master, worktree
# sujo, ou o worktree de onde o script roda (use ExitWorktree pra esse).
#
# Uso:
#   worktree-gc.sh            # dry-run (só mostra o que faria) — PADRÃO
#   worktree-gc.sh --apply    # remove de fato (worktree + branch local mergeada)
#   worktree-gc.sh --apply --prune-remote   # também deleta a branch remota mergeada
#
# Seguro por padrão: dry-run, e só remove o que passa em TODAS as travas.
set -uo pipefail

APPLY=0
PRUNE_REMOTE=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --prune-remote) PRUNE_REMOTE=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "arg desconhecido: $arg" >&2; exit 2 ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "não é um repo git" >&2; exit 1; }

COMMON="$(git rev-parse --git-common-dir 2>/dev/null)"
COMMON="$(cd "$COMMON" && pwd -P)"
PRIMARY="$(dirname "$COMMON")"                 # raiz do clone principal (contém .git/)
SELF="$(git rev-parse --show-toplevel 2>/dev/null && :)"; SELF="$(cd "$SELF" && pwd -P)"

echo "🧹 worktree-gc  (modo: $([ "$APPLY" = 1 ] && echo APLICAR || echo dry-run))"
git -C "$PRIMARY" fetch --prune --quiet origin 2>/dev/null || echo "  (fetch falhou — seguindo com o que há local)"

have_gh=0; command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && have_gh=1

# É mergeada? ancestral de origin/main OU PR MERGED (squash).
is_merged() {
  local br="$1"
  git -C "$PRIMARY" merge-base --is-ancestor "refs/heads/$br" origin/main 2>/dev/null && return 0
  if [ "$have_gh" = 1 ]; then
    local n
    n="$(gh pr list --head "$br" --state merged --json number --jq 'length' 2>/dev/null || echo 0)"
    [ "${n:-0}" -gt 0 ] && return 0
  fi
  return 1
}

removed=0; kept=0; skipped=0
# Percorre os worktrees (path + branch) do porcelain.
path=""; branch=""
while IFS= read -r line; do
  case "$line" in
    worktree\ *) path="${line#worktree }" ;;
    branch\ *)   branch="${line#branch refs/heads/}" ;;
    "")  # fim de um bloco → avalia
      [ -z "$path" ] && { path=""; branch=""; continue; }
      p="$(cd "$path" 2>/dev/null && pwd -P || echo "$path")"

      # trava 1: nunca o clone principal
      if [ "$p" = "$PRIMARY" ]; then path=""; branch=""; continue; fi
      # trava 2: nunca main/master, nem detached sem branch
      if [ -z "$branch" ] || [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
        echo "  ⏭️  $p  → branch '${branch:-detached}' (mantido)"; skipped=$((skipped+1)); path=""; branch=""; continue
      fi
      # trava 3: nunca o worktree atual
      if [ "$p" = "$SELF" ]; then
        echo "  ⏭️  $p  → é o worktree ATUAL (use ExitWorktree pra remover)"; skipped=$((skipped+1)); path=""; branch=""; continue
      fi
      # trava 4: nunca se estiver sujo
      if [ -n "$(git -C "$p" status --porcelain 2>/dev/null)" ]; then
        echo "  ✋ $p  → SUJO (mudança não-commitada) — mantido"; kept=$((kept+1)); path=""; branch=""; continue
      fi
      # trava 5: só se mergeada
      if ! is_merged "$branch"; then
        echo "  🔒 $p  → branch '$branch' NÃO mergeada — mantido"; kept=$((kept+1)); path=""; branch=""; continue
      fi

      if [ "$APPLY" = 1 ]; then
        if git -C "$PRIMARY" worktree remove "$p" 2>/dev/null; then
          git -C "$PRIMARY" branch -D "$branch" >/dev/null 2>&1 || true
          [ "$PRUNE_REMOTE" = 1 ] && git -C "$PRIMARY" push origin --delete "$branch" >/dev/null 2>&1 || true
          echo "  ✅ removido: $p  (branch '$branch' mergeada, deletada)"; removed=$((removed+1))
        else
          echo "  ⚠️  falhou remover: $p (rode manualmente 'git worktree remove --force' se apropriado)"; kept=$((kept+1))
        fi
      else
        echo "  🗑️  [dry-run] removeria: $p  (branch '$branch' mergeada + limpa)"; removed=$((removed+1))
      fi
      path=""; branch=""
      ;;
  esac
done < <(git -C "$PRIMARY" worktree list --porcelain; echo "")

git -C "$PRIMARY" worktree prune 2>/dev/null || true
echo "—"
if [ "$APPLY" = 1 ]; then
  echo "resumo: $removed removido(s), $kept mantido(s), $skipped pulado(s)."
else
  echo "resumo (dry-run): $removed candidato(s) a remoção, $kept mantido(s), $skipped pulado(s).  Rode com --apply pra remover."
fi
