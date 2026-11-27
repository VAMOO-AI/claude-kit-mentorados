#!/usr/bin/env bash
# Reprova PR aberto contra o `stable`.
#
# O branch padrão do repo é o `stable` (é ele que o marketplace de quem instalou segue), então
# `gh pr create` sem `--base` e o botão do GitHub abrem o PR contra ele. Um merge direto no
# `stable` cria commit que a `main` não tem, e o promover-stable.sh, que só avança em
# fast-forward, passa a recusar a promoção seguinte.
#
# Uso: bash scripts/checar-base-pr.sh <branch base do PR>
set -uo pipefail
BASE="${1:-}"
[ -n "$BASE" ] || { echo "uso: bash scripts/checar-base-pr.sh <branch base do PR>" >&2; exit 2; }

if [ "$BASE" = "stable" ]; then
  echo "::error::Este PR está contra o stable, que só avança por promoção. Troque a base para a main (gh pr edit <n> --base main; ao abrir, gh pr create --base main). O stable recebe a mudança depois, com bash scripts/promover-stable.sh <versão> --push."
  exit 1
fi
echo "base $BASE: ok"
