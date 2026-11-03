#!/usr/bin/env bash
# Confere se cada IA respondeu todas as perguntas na saída do `cnry run`.
# Uso: geo-provedores.sh <saida-do-cnry-run> <numero-de-perguntas>
# Imprime uma linha por IA com resposta faltando; nada quando a rodada veio completa.
set -euo pipefail

ARQUIVO="$1"
ESPERADO="$2"

for provedor in openai perplexity; do
  n=$(/usr/bin/grep -cE "^\s+\[[cCmM]{2}\]\s+${provedor} " "$ARQUIVO" || true)
  if [ "$n" -lt "$ESPERADO" ]; then
    echo "${provedor}: ${n} de ${ESPERADO} respostas"
  fi
done
