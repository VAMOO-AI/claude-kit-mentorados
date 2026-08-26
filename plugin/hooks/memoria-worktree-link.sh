#!/usr/bin/env bash
# Liga a memória do worktree assim que a sessão entra nele.
#
# `memoria-link.sh` roda na instalação/atualização do kit — cedo demais: o worktree
# nasce NO MEIO da sessão. Sem este hook, o diretório de projeto do worktree (que o
# Claude Code cria a partir do cwd) fica sem link, e a sessão isolada não tem onde
# gravar: escrever no `.context/memoria` do clone é escrever fora da árvore da
# branch, e o Claude recusa. O resultado prático é a memória ficar "pra depois",
# que é nunca.
#
# Roda a cada prompt de propósito: dois testes de arquivo quando já está ligado.
# O `ln -s` acontece uma vez por worktree.
set -eu

case "$PWD" in
  */.claude/worktrees/*) ;;
  *) exit 0 ;;
esac

# A raiz do worktree, não uma subpasta dele.
RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$RAIZ" ] || exit 0

MEM="$RAIZ/.context/memoria"
[ -d "$MEM" ] || exit 0

# Mesma regra do Claude Code: tudo fora de [a-zA-Z0-9] vira '-'. Trocar só '/' e
# espaço erra em TODO worktree — o caminho tem `.claude`, e o ponto ficaria intacto.
SLUG="$(printf '%s' "$RAIZ" | LC_ALL=C tr -c 'a-zA-Z0-9' '-' | sed 's/-$//')"
DIR="$HOME/.claude/projects/$SLUG/memory"

# Já ligado no lugar certo: caminho quente, sai sem tocar em nada.
[ -L "$DIR" ] && [ "$(readlink "$DIR")" = "$MEM" ] && exit 0

# Link pra outro lugar, ou diretório de verdade com fatos dentro: não é decisão de
# hook desfazer. `memoria-link.sh` trata isso, com backup e relatório.
[ -e "$DIR" ] && exit 0

mkdir -p "$(dirname "$DIR")"
ln -s "$MEM" "$DIR"
echo "🧠 memória do worktree ligada em .context/memoria — o que a sessão registrar entra no commit."
