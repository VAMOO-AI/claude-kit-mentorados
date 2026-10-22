#!/usr/bin/env bash
# warn-branch-worktree.sh — SessionStart hook. Um aviso só sobre o estado do git da sessão.
#
# Até a 0.64 eram dois hooks (warn-branch-behind.sh e warn-worktree-stale.sh), cada um um
# processo a mais em toda sessão, e os dois decidiam o repositório por
# `${CLAUDE_PROJECT_DIR:-$PWD}`. Numa sessão de worktree do app desktop, esse diretório
# pode ser a raiz do clone principal: o aviso de worktree mergeado nunca disparava, e o de
# branch atrasada olhava a branch do clone. Agora o diretório vem do `.cwd` do payload
# (lido por node, scripts/hookjson.js); o env e o $PWD ficam só de reserva, para payload
# sem cwd.
#
# O que avisa, nesta ordem:
#   (1) a branch atual está atrás do upstream (fetch leve, no máximo 1x a cada 10 min por
#       repositório+branch);
#   (2) a sessão está num worktree cuja branch JÁ FOI MERGEADA. Branch sem commit próprio
#       não conta como mergeada, e worktree com mudança não commitada nunca é lixo;
#   (3) numa sessão em worktree, o CLONE PRINCIPAL não está em main.
# Não modifica o git: só lê e avisa. Silencioso quando está tudo em ordem. Falha-aberta.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
H="$AQUI/hookjson.js"
DIR=""
if [ -f "$H" ] && command -v node >/dev/null 2>&1 && [ ! -t 0 ]; then
  DIR="$(node "$H" cwd 2>/dev/null)"
fi
[ -n "$DIR" ] || DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$DIR" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

br="$(git branch --show-current 2>/dev/null)"

# ── (1) atrás do upstream ────────────────────────────────────────────────────────────
# Precisa de upstream configurado (branch já pushada com -u, ou main rastreando
# origin/main). O fetch custava ~1 s (965–1.300 ms medidos em 03/09/2026) em TODA sessão;
# dentro da janela de 10 min compara com o origin/<branch> que já está local. A chave é o
# git-common-dir: worktrees partilham as refs remotas, então o fetch de um vale para os
# outros.
atras() {
  [ -n "$br" ] || return 0
  local up gdir h marker behind
  up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || return 0
  [ -n "$up" ] || return 0
  gdir="$(git rev-parse --git-common-dir 2>/dev/null)" || gdir=".git"
  gdir="$(cd "$gdir" 2>/dev/null && pwd -P)" || gdir="$DIR"
  local CACHE_DIR="$HOME/.claude/.cache/warn-branch-behind"
  h="$(printf '%s' "$gdir" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | awk '{print $1}')"
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
}
atras

GIT_DIR="$(cd "$(git rev-parse --git-dir 2>/dev/null)" 2>/dev/null && pwd -P)" || exit 0
COMMON="$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)" || exit 0
PRIMARY="$(dirname "$COMMON")"
# Clone principal: nada de worktree para avisar.
[ "$GIT_DIR" != "$COMMON" ] || exit 0

# Branch recém-criada de origin/main é ancestral dela sem ter commit nenhum, e o
# `--is-ancestor` sozinho a chamava de mergeada: em 24/09/2026, num projeto real, o
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

# ── (2) worktree cuja branch já foi mergeada ─────────────────────────────────────────
if [ -n "$br" ] && [ "$br" != "main" ] && [ "$br" != "master" ]; then
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
      # O --verificar só lê: diz se o worktree pode sair ou o que o segura (env diferente do
      # clone, repo aninhado, ignorado de valor como outputs/), que o `status` não mostra.
      gc="$AQUI/worktree-gc.sh"
      wt="$(git rev-parse --show-toplevel 2>/dev/null)"
      echo "🧹 worktree: '$br' já foi mergeada e está limpo. Se o usuário não for mais usá-lo, diga que ele pode pedir a limpeza; ela segue a seção 'Limpeza no fim' da skill worktrees (prova completa; antes de remover, bash $gc --verificar '$wt' diz o que ainda segura o worktree: env diferente do clone, repo aninhado ou ignorado de valor como outputs/). Para vários de uma vez, 'git-sync --cleanup-dry-run' primeiro, e o '--cleanup-apply' só com o pedido dele."
    fi
  fi
fi

# ── (3) clone principal fora de main ─────────────────────────────────────────────────
primary_br="$(git -C "$PRIMARY" branch --show-current 2>/dev/null)"
if [ -n "$primary_br" ] && [ "$primary_br" != "main" ] && [ "$primary_br" != "master" ]; then
  echo "⚠️ clone principal ($PRIMARY) está em '$primary_br', não em main. Com worktrees, o clone principal fica na main, só pra leitura (skill worktrees); se não houver trabalho não commitado nele, ofereça ao usuário voltar pra main."
fi
exit 0
