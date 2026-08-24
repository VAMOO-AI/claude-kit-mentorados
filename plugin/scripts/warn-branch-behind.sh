#!/usr/bin/env bash
# warn-branch-behind.sh — SessionStart hook.
# Avisa quando a branch atual está atrás do upstream, pra não reconciliar/copiar
# arquivos com base num clone desatualizado (ver ~/.claude/CLAUDE.md, seção worktrees).
# Não modifica o git — só lê e avisa. Silencioso quando está em dia.
set -uo pipefail

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$DIR" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

br="$(git branch --show-current 2>/dev/null)" || exit 0
[ -z "$br" ] && exit 0

# precisa de upstream configurado (branch já pushada com -u, ou main rastreando origin/main)
up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || exit 0
[ -z "$up" ] && exit 0

# fetch leve só da branch atual (tolerante a offline)
git fetch --quiet --no-tags origin "$br" 2>/dev/null || true

behind="$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null || echo 0)"
if [ "${behind:-0}" -gt 0 ]; then
  echo "⚠️ git: '$br' está $behind commit(s) atrás de $up. Faça 'git pull --ff-only' antes de copiar arquivos OU criar worktree. Em worktree a fonte de verdade é origin/<branch> — nunca o clone principal."
fi
exit 0
