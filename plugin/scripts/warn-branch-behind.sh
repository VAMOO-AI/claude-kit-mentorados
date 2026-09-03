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

# fetch leve só da branch atual (tolerante a offline), no máximo 1x a cada 10 min por
# repositório+branch. Custava ~1 s (965–1.300 ms medidos em 03/09/2026) em TODA sessão,
# inclusive nas várias que abrem no mesmo repo em poucos minutos; dentro da janela
# compara com o origin/<branch> que já está local. A chave é o git-common-dir: worktrees
# partilham as refs remotas, então o fetch de um vale para os outros.
gdir="$(git rev-parse --git-common-dir 2>/dev/null)" || gdir=".git"
gdir="$(cd "$gdir" 2>/dev/null && pwd -P)" || gdir="$DIR"
CACHE_DIR="$HOME/.claude/.cache/warn-branch-behind"
h="$(printf '%s' "$gdir" | shasum 2>/dev/null | awk '{print $1}')"
[ -z "$h" ] && h="$(printf '%s' "$gdir" | cksum | awk '{print $1}')"
marker="$CACHE_DIR/$h-$(printf '%s' "$br" | tr '/' '_')"
if [ -z "$(find "$marker" -mmin -10 2>/dev/null)" ]; then
  git fetch --quiet --no-tags origin "$br" 2>/dev/null || true
  mkdir -p "$CACHE_DIR" 2>/dev/null && touch "$marker" 2>/dev/null
  find "$CACHE_DIR" -type f -mtime +7 -delete 2>/dev/null   # branch que ninguém abre mais
fi

behind="$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null || echo 0)"
if [ "${behind:-0}" -gt 0 ]; then
  echo "⚠️ git: '$br' está $behind commit(s) atrás de $up. Faça 'git pull --ff-only' antes de copiar arquivos OU criar worktree. Em worktree a fonte de verdade é origin/<branch> — nunca o clone principal."
fi
exit 0
