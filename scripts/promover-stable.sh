#!/usr/bin/env bash
# Promove uma versão já lançada para o canal estável: avança o branch `stable` até a tag.
#
# O branch padrão do repo é `stable`, e é ele que o marketplace de quem instalou segue. A
# `main` recebe os releases; uma versão só chega aos mentorados quando alguém roda isto,
# depois de usá-la no time por alguns dias.
#
#   bash scripts/promover-stable.sh 0.91.0            # confere e mostra o que faria
#   bash scripts/promover-stable.sh 0.91.0 --push     # avança o stable no origin
#
# Só avança (fast-forward): a tag tem de conter o stable atual. Voltar o stable para uma
# versão anterior é decisão à parte, feita à mão.
# PROMOVER_REMOTE troca o remote (os testes usam um repo de mentira).
set -euo pipefail

V="${1:-}"; MODO="${2:-}"
REMOTE="${PROMOVER_REMOTE:-origin}"
case "$V" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "uso: bash scripts/promover-stable.sh <versão> [--push]   (ex.: 0.91.0)" >&2; exit 2 ;;
esac
case "$MODO" in ""|--push) ;; *) echo "segundo argumento desconhecido: $MODO (só --push)" >&2; exit 2 ;; esac

TOP="$(git rev-parse --show-toplevel)"
git -C "$TOP" fetch -q "$REMOTE" --tags
git -C "$TOP" fetch -q "$REMOTE" "+refs/heads/stable:refs/remotes/$REMOTE/stable" 2>/dev/null || true

ALVO="$(git -C "$TOP" rev-parse -q --verify "refs/tags/v$V^{commit}" 2>/dev/null || true)"
[ -n "$ALVO" ] || { echo "a tag v$V não existe: o release dessa versão já entrou na main?" >&2; exit 1; }

ATUAL="$(git -C "$TOP" rev-parse -q --verify "refs/remotes/$REMOTE/stable^{commit}" 2>/dev/null || true)"
if [ -z "$ATUAL" ]; then
  echo "o branch stable ainda não existe em $REMOTE: ele será criado em v$V ($(git -C "$TOP" rev-parse --short "$ALVO"))."
elif [ "$ATUAL" = "$ALVO" ]; then
  echo "o stable já está em v$V. Nada a fazer."; exit 0
elif git -C "$TOP" merge-base --is-ancestor "$ATUAL" "$ALVO"; then
  n="$(git -C "$TOP" rev-list --count "$ATUAL..$ALVO")"
  echo "stable: $(git -C "$TOP" rev-parse --short "$ATUAL") → v$V ($(git -C "$TOP" rev-parse --short "$ALVO")), $n commit(s) à frente."
else
  echo "v$V não contém o stable atual ($(git -C "$TOP" rev-parse --short "$ATUAL")): isso voltaria o canal, e este script só avança." >&2
  exit 1
fi

if [ "$MODO" != "--push" ]; then
  echo "Nada foi enviado. Para promover: bash scripts/promover-stable.sh $V --push"
  exit 0
fi
git -C "$TOP" push "$REMOTE" "$ALVO:refs/heads/stable"
echo "stable em v$V. Quem tem auto-update recebe na próxima sessão."
