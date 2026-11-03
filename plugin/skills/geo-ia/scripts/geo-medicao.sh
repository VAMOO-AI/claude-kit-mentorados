#!/usr/bin/env bash
# Medição GEO: as perguntas do arquivo no ChatGPT (OpenAI) e no Perplexity, via Canonry.
# Feito para a Action geo-medicao.yml; imprime o relatório em Markdown no stdout e a saída bruta
# do `cnry run` no stderr (log da Action). Nada aqui imprime as chaves.
#
# Ambiente:
#   GEO_PROJETO    nome do projeto no Canonry (obrigatório)
#   GEO_DOMINIO    domínio do site, sem https:// (obrigatório)
#   GEO_PAIS       padrão BR
#   GEO_IDIOMA     padrão pt
#   GEO_PERGUNTAS  arquivo com uma pergunta por linha; padrão geo-perguntas.txt ao lado do script
#   OPENAI_API_KEY e PERPLEXITY_API_KEY
set -euo pipefail

export CANONRY_TELEMETRY_DISABLED=1 DO_NOT_TRACK=1
DIR="$(cd "$(dirname "$0")" && pwd)"
PROJETO="${GEO_PROJETO:?defina GEO_PROJETO}"
DOMINIO="${GEO_DOMINIO:?defina GEO_DOMINIO}"
ARQUIVO="${GEO_PERGUNTAS:-$DIR/geo-perguntas.txt}"
SAIDA="$(mktemp)"

cnry bootstrap >/dev/null 2>&1
cnry start >/dev/null 2>&1
cnry project create "$PROJETO" --domain "$DOMINIO" --country "${GEO_PAIS:-BR}" --language "${GEO_IDIOMA:-pt}" >/dev/null 2>&1 || true
PERGUNTAS=()
while IFS= read -r linha; do
  [ -n "${linha// /}" ] && PERGUNTAS+=("$linha")
done < "$ARQUIVO"
cnry query add "$PROJETO" "${PERGUNTAS[@]}" >/dev/null
cnry run "$PROJETO" --wait > "$SAIDA" 2>&1
cat "$SAIDA" >&2
FALTANDO=$(bash "$DIR/geo-provedores.sh" "$SAIDA" "${#PERGUNTAS[@]}")

echo "## Medição GEO de $(TZ=America/Sao_Paulo date +%d/%m/%Y)"
echo
echo "${#PERGUNTAS[@]} perguntas no ChatGPT (OpenAI) e no Perplexity. **Citada** = o link do site aparece nas fontes. **Mencionada** = o nome aparece no texto."
echo
if [ -n "$FALTANDO" ]; then
  echo "> [!WARNING]"
  echo "> Rodada incompleta, não compare com semanas cheias. Erro de cada IA no log da Action."
  while IFS= read -r linha; do
    echo "> - $linha"
    echo "::warning title=Medição GEO incompleta::$linha" >&2
  done <<< "$FALTANDO"
  echo
fi
echo '```'
cnry visibility-stats "$PROJETO" --by-provider 2>&1
echo '```'
echo
echo '<details><summary>Resposta por pergunta e por IA (C = citada, M = mencionada; minúscula = não)</summary>'
echo
echo '```'
grep -E '^\s+\[' "$SAIDA" || true
echo '```'
echo '</details>'
echo
echo '<details><summary>Fontes que as IAs mais citaram</summary>'
echo
echo '```'
cnry sources "$PROJETO" --rank --limit 20 2>&1
echo '```'
echo '</details>'
rm -f "$SAIDA"
