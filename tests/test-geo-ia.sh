#!/usr/bin/env bash
# A medição da skill geo-ia avisa quando uma IA falta na rodada?
#
# Em 02/11/2026 o Perplexity sumiu de uma medição real sem nenhum aviso: a Agent API devolveu
# 403 e a saída do `cnry run` ficava só num arquivo temporário. A Action terminou verde e o
# comentário saiu com metade das respostas. Os casos: rodada completa não avisa, IA ausente e
# IA com resposta faltando avisam, placar e fontes só da rodada atual, e o geo-medicao.sh (com um `cnry` de mentira) põe o aviso no
# relatório, a saída bruta no stderr e o ::warning da Action.
#
# Uso: bash tests/test-geo-ia.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SCR="$RAIZ/plugin/skills/geo-ia/scripts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
contem()     { case "$1" in *"$2"*) echo ok ;; *) echo fail ;; esac; }
nao_contem() { case "$1" in *"$2"*) echo fail ;; *) echo ok ;; esac; }

echo "geo-provedores.sh"
printf '    [cm]  openai (gpt-5.4)  p1\n    [cm]  perplexity (fast)  p1\n    [CM]  openai (gpt-5.4)  p2\n    [cM]  perplexity (fast)  p2\n' > "$TMP/completa.txt"
out="$(bash "$SCR/geo-provedores.sh" "$TMP/completa.txt" 2)"
check "rodada completa não avisa" "$([ -z "$out" ] && echo ok || echo fail)"

printf '    [cm]  openai (gpt-5.4)  p1\n    [CM]  openai (gpt-5.4)  p2\n' > "$TMP/sem-pplx.txt"
out="$(bash "$SCR/geo-provedores.sh" "$TMP/sem-pplx.txt" 2)"
check "IA ausente vira aviso com a contagem" "$(contem "$out" 'perplexity: 0 de 2 respostas')"
check "IA completa não aparece no aviso" "$(nao_contem "$out" 'openai')"

printf '    [cm]  openai (gpt-5.4)  p1\n    [cm]  perplexity (fast)  p1\n    [cm]  openai (gpt-5.4)  p2\n' > "$TMP/faltando.txt"
out="$(bash "$SCR/geo-provedores.sh" "$TMP/faltando.txt" 2)"
check "IA com resposta faltando também avisa" "$(contem "$out" 'perplexity: 1 de 2 respostas')"

echo "geo-medicao.sh com cnry de mentira"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/cnry" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$(dirname "$0")/../chamadas.txt"
case "$1" in
  runs) echo '[{"id":"rodada-de-hoje"}]' ;;
  run) printf 'perplexity: 403 requires paid credits\n    [cm]  openai (gpt-5.4)  p1\n    [CM]  openai (gpt-5.4)  p2\n' ;;
  visibility-stats) echo 'TOTAL 1/2' ;;
  sources) echo 'exemplo.com.br 1' ;;
esac
STUB
chmod +x "$TMP/bin/cnry"
printf 'p1\np2\n' > "$TMP/perguntas.txt"
PATH="$TMP/bin:$PATH" GEO_PROJETO=teste GEO_DOMINIO=exemplo.com.br GEO_PERGUNTAS="$TMP/perguntas.txt" \
  bash "$SCR/geo-medicao.sh" > "$TMP/relatorio.md" 2> "$TMP/log.txt"
check "o script sai 0 mesmo com IA faltando" "$([ $? -eq 0 ] && echo ok || echo fail)"
rel="$(cat "$TMP/relatorio.md")"; log="$(cat "$TMP/log.txt")"
check "relatório abre com o aviso de rodada incompleta" "$(contem "$rel" 'Rodada incompleta')"
check "relatório nomeia a IA que faltou" "$(contem "$rel" 'perplexity: 0 de 2 respostas')"
check "log da Action tem o erro bruto do provedor" "$(contem "$log" '403 requires paid credits')"
check "log da Action tem o ::warning" "$(contem "$log" '::warning title=Medição GEO incompleta::perplexity')"
check "relatório traz as respostas por pergunta" "$(contem "$rel" '[CM]  openai (gpt-5.4)  p2')"
cham="$(cat "$TMP/chamadas.txt")"
check "placar só da última rodada (--last-runs 1)" "$(contem "$cham" 'visibility-stats teste --by-provider --last-runs 1')"
check "fontes só da rodada de hoje (--run-id)" "$(contem "$cham" '--run-id rodada-de-hoje')"

GEO_DOMINIO=exemplo.com.br bash "$SCR/geo-medicao.sh" >/dev/null 2>"$TMP/erro.txt"
check "sem GEO_PROJETO o script recusa" "$([ $? -ne 0 ] && echo ok || echo fail)"

[ "$falhas" -eq 0 ] && echo "tudo verde" || { echo "$falhas falha(s)"; exit 1; }
