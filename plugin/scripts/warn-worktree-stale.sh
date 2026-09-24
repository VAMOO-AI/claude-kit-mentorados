#!/usr/bin/env bash
# warn-worktree-stale.sh — SessionStart hook.
# (1) Avisa se a sessão começa num worktree cuja branch JÁ FOI MERGEADA (lixo — pode
#     remover com worktree-gc.sh --apply, ou ExitWorktree). Branch sem commit próprio
#     não conta como mergeada, e worktree com mudança não commitada nunca é lixo.
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

# Branch recém-criada de origin/main é ancestral dela sem ter commit nenhum, e o
# `--is-ancestor` sozinho a chamava de mergeada: em 24/09/2026, no CRM Multipedidos, o
# aviso mandou remover um worktree com o fix inteiro ainda sem commit. Sem commit próprio
# = o tip não passou do ponto de criação (a 1ª entrada do reflog), ou é commit da linha
# first-parent da main — a branch que só puxou a base, ou cujo reflog já expirou.
sem_commit_proprio() {
  local tip="$1" criacao ultimo
  criacao="$(git reflog show --format='%H %gs' "refs/heads/$br" 2>/dev/null | tail -n 1)"
  case "$criacao" in
    *" branch: Created from "*)
      [ "$(git rev-list --count "${criacao%% *}..$tip" 2>/dev/null)" = 0 ] && return 0 ;;
  esac
  # atalho: merge fast-forward na main fica sem aviso (parece base puxada); rever se o time mergear por ff fora do PR
  [ "$tip" = "$(git rev-parse --verify -q origin/main)" ] && return 0
  ultimo="$(git rev-list --first-parent origin/main "^$tip" 2>/dev/null | tail -n 1)"
  [ -n "$ultimo" ] && [ "$(git rev-parse --verify -q "$ultimo^1")" = "$tip" ]
}

# (1) Estou num worktree LINKADO (não o clone principal)?
if [ "$GIT_DIR" != "$COMMON" ] && [ -n "$br" ] && [ "$br" != "main" ] && [ "$br" != "master" ]; then
  merged=0
  tip="$(git rev-parse --verify -q "refs/heads/$br")"
  if [ -n "$tip" ] && ! sem_commit_proprio "$tip"; then
    if git merge-base --is-ancestor "$tip" origin/main 2>/dev/null; then
      merged=1
    elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      # Squash: o tip precisa estar contido no head do PR mergeado — commit feito depois
      # do merge, ou nome de branch reaproveitado, é trabalho (mesma regra do worktree-gc).
      oid="$(gh pr list --head "$br" --state merged --json headRefOid --jq '.[0].headRefOid // empty' 2>/dev/null)"
      [ -n "$oid" ] && git merge-base --is-ancestor "$tip" "$oid" 2>/dev/null && merged=1
    fi
  fi
  if [ "$merged" = 1 ]; then
    sujos="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${sujos:-0}" -gt 0 ]; then
      echo "⚠️ worktree: '$br' já foi mergeada, mas tem $sujos arquivo(s) com mudança não commitada — é trabalho, não remova este worktree."
    else
      echo "🧹 worktree: '$br' já foi MERGEADA — este worktree é lixo. Remova com 'ExitWorktree' (sessão) ou '~/.claude/scripts/worktree-gc.sh --apply'."
    fi
  fi
fi

# (2) Clone principal fora de main?
primary_br="$(git -C "$PRIMARY" branch --show-current 2>/dev/null)"
if [ -n "$primary_br" ] && [ "$primary_br" != "main" ] && [ "$primary_br" != "master" ]; then
  echo "⚠️ clone principal ($PRIMARY) está em '$primary_br', não em main. Sua regra: clone principal read-only em main. Volte pra main quando puder (cuidado com trabalho não-commitado)."
fi
exit 0
