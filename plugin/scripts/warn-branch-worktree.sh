#!/usr/bin/env bash
# warn-branch-worktree.sh — aviso de SessionStart (chamado pelo hooks/session-start.sh):
# a branch atual está atrás do upstream.
#
# Até a 0.90 este script dava três avisos: branch atrás do upstream, worktree cuja branch já
# foi mergeada e clone principal fora da main. Os dois últimos saíram em 09/11/2026 (decisão
# D13): pediam `gh pr list` e um fetch de `refs/pull/<n>/head` na abertura de toda sessão em
# worktree, e a limpeza de worktree mergeado já tem dono (skill worktrees, seção "Limpeza no
# fim", e o `git-sync --cleanup-dry-run`). O nome do arquivo ficou para não quebrar quem o
# chama pelo caminho.
#
# O diretório vem do `.cwd` do payload: numa sessão de worktree do app desktop,
# `${CLAUDE_PROJECT_DIR:-$PWD}` pode ser a raiz do clone principal, e o aviso olharia a
# branch errada. Quem lê o payload é o session-start.sh, que entrega o cwd em
# KIT_SESSAO_CWD; chamado sozinho, o script lê por node (scripts/hookjson.js). O env e o
# $PWD ficam de reserva, para payload sem cwd.
#
# Precisa de upstream configurado (branch já pushada com -u, ou main rastreando
# origin/main). O fetch custava ~1 s (965–1.300 ms medidos em 03/09/2026) em TODA sessão;
# dentro da janela de 10 min compara com o origin/<branch> que já está local. A chave é o
# git-common-dir: worktrees partilham as refs remotas, então o fetch de um vale para os
# outros.
#
# Teto de tempo no fetch: rede lenta, VPN caída ou remote que pede credencial penduravam a
# abertura da sessão. `timeout` não existe no macOS sem o coreutils, então o teto é feito em
# bash (com_teto): passou de WARN_BRANCH_FETCH_TETO segundos (padrão 5), o fetch é morto e o
# aviso sai com o origin/<branch> que já está local. O marcador é gravado do mesmo jeito,
# para a sessão seguinte não esperar de novo.
#
# Não modifica o git: só lê e avisa (o fetch grava objetos e refs remotas, nunca branch nem
# HEAD). Silencioso quando está tudo em ordem. Falha-aberta.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
H="$AQUI/hookjson.js"
DIR="${KIT_SESSAO_CWD:-}"
if [ -z "$DIR" ] && [ -f "$H" ] && command -v node >/dev/null 2>&1 && [ ! -t 0 ]; then
  DIR="$(node "$H" cwd 2>/dev/null)"
fi
[ -n "$DIR" ] || DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$DIR" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

br="$(git branch --show-current 2>/dev/null)"
[ -n "$br" ] || exit 0
up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || exit 0
[ -n "$up" ] || exit 0

# com_teto <segundos> <comando>...: roda o comando e o mata se passar do teto. Devolve o
# código dele (143 quando foi morto). O vigia e o comando ficam sem o stdout do hook: um
# `sleep` órfão segurando o pipe faria o Claude Code esperar o teto inteiro mesmo com o
# fetch já terminado.
com_teto() {
  local teto="$1" pid vigia rc
  shift
  "$@" </dev/null >/dev/null 2>&1 &
  pid=$!
  ( sleep "$teto"; kill "$pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
  vigia=$!
  wait "$pid" 2>/dev/null; rc=$?
  kill "$vigia" 2>/dev/null
  wait "$vigia" 2>/dev/null
  return "$rc"
}
TETO="${WARN_BRANCH_FETCH_TETO:-5}"
case "$TETO" in ''|*[!0-9]*|0) TETO=5 ;; esac

gdir="$(git rev-parse --git-common-dir 2>/dev/null)" || gdir=".git"
gdir="$(cd "$gdir" 2>/dev/null && pwd -P)" || gdir="$DIR"
CACHE_DIR="$HOME/.claude/.cache/warn-branch-behind"
h="$(printf '%s' "$gdir" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | awk '{print $1}')"
[ -z "$h" ] && h="$(printf '%s' "$gdir" | cksum | awk '{print $1}')"
marker="$CACHE_DIR/$h-$(printf '%s' "$br" | tr '/' '_')"
if [ -z "$(find "$marker" -mmin -10 2>/dev/null)" ]; then
  # Sem prompt de credencial: remote que pede senha ficaria esperando até o teto.
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" \
    com_teto "$TETO" git fetch --quiet --no-tags origin "$br" || true
  mkdir -p "$CACHE_DIR" 2>/dev/null && touch "$marker" 2>/dev/null
  find "$CACHE_DIR" -type f -mtime +7 -delete 2>/dev/null   # branch que ninguém abre mais
fi
behind="$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null || echo 0)"
if [ "${behind:-0}" -gt 0 ]; then
  echo "⚠️ git: '$br' está $behind commit(s) atrás de $up. Faça 'git pull --ff-only' antes de copiar arquivos OU criar worktree. Em worktree a fonte de verdade é origin/<branch> — nunca o clone principal."
fi
exit 0
