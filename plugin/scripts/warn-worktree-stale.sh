#!/usr/bin/env bash
# warn-worktree-stale.sh — SessionStart hook.
# (1) Avisa se a sessão começa num worktree cuja branch JÁ FOI MERGEADA (lixo — pode
#     remover com worktree-gc.sh --apply, ou ExitWorktree).
# (2) Avisa se o CLONE PRINCIPAL não está em main (sua regra: clone principal read-only
#     em main). Não modifica o git — só lê e avisa. Silencioso quando está tudo ok.
set -uo pipefail

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$DIR" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

GIT_DIR="$(cd "$(git rev-parse --git-dir 2>/dev/null)" 2>/dev/null && pwd -P)" || exit 0
COMMON="$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)" || exit 0
PRIMARY="$(dirname "$COMMON")"
br="$(git branch --show-current 2>/dev/null)"

# (1) Estou num worktree LINKADO (não o clone principal)?
if [ "$GIT_DIR" != "$COMMON" ] && [ -n "$br" ] && [ "$br" != "main" ] && [ "$br" != "master" ]; then
  merged=0
  if git merge-base --is-ancestor "refs/heads/$br" origin/main 2>/dev/null; then
    merged=1
  elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    n="$(gh pr list --head "$br" --state merged --json number --jq 'length' 2>/dev/null || echo 0)"
    [ "${n:-0}" -gt 0 ] && merged=1
  fi
  if [ "$merged" = 1 ]; then
    echo "🧹 worktree: '$br' já foi MERGEADA — este worktree é lixo. Remova com 'ExitWorktree' (sessão) ou '~/.claude/scripts/worktree-gc.sh --apply'."
  fi
fi

# (2) Clone principal fora de main?
primary_br="$(git -C "$PRIMARY" branch --show-current 2>/dev/null)"
if [ -n "$primary_br" ] && [ "$primary_br" != "main" ] && [ "$primary_br" != "master" ]; then
  echo "⚠️ clone principal ($PRIMARY) está em '$primary_br', não em main. Sua regra: clone principal read-only em main. Volte pra main quando puder (cuidado com trabalho não-commitado)."
fi
exit 0
