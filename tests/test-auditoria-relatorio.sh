#!/usr/bin/env bash
# O gerador de relatório da skill auditoria-seguranca produz um HTML íntegro a
# partir do findings.json de exemplo.
#
# Roda em --html-only de propósito: a etapa Chrome depende de navegador instalado
# e o que precisa de trava é o conteúdo (os números do resumo saem do JSON, os
# gráficos existem, as issues saem delimitadas). PDF quebrado por falta de Chrome
# é problema de máquina; número errado no resumo é bug do kit.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$RAIZ/plugin/skills/auditoria-seguranca"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

falhas=0
ok()   { echo "  ok   $1"; }
falha() { echo "  FALHA $1"; falhas=$((falhas + 1)); }

echo "== gerador de relatório da auditoria-seguranca"

python3 "$SKILL/scripts/gerar-relatorio.py" \
  "$SKILL/references/exemplo-findings.json" \
  --out "$TMP/relatorio.pdf" --html-only > "$TMP/log.txt" 2>&1 \
  || { echo "  FALHA gerador saiu com erro:"; cat "$TMP/log.txt"; exit 1; }

HTML="$TMP/relatorio.html"
[ -s "$HTML" ] && ok "HTML gerado" || { falha "HTML não foi gerado"; exit 1; }

# 1. o exemplo tem 5 achados: 2 críticas, 2 altas, 1 média. O total no centro da
#    rosca é calculado, não escrito — se divergir, a contagem quebrou.
grep -q '>5</text>' "$HTML" && ok "total da rosca = 5 achados" \
  || falha "total da rosca não bate com os achados do JSON"
grep -q 'Crítica <b>2</b>' "$HTML" && ok "legenda: 2 críticas" || falha "legenda de crítica errada"
grep -q 'Alta <b>2</b>'    "$HTML" && ok "legenda: 2 altas"    || falha "legenda de alta errada"

# 2. os dois gráficos existem (rosca por severidade + barras por categoria)
[ "$(grep -c '<svg' "$HTML")" -ge 2 ] && ok "rosca e barras presentes" \
  || falha "faltou gráfico no resumo executivo"

# 3. paleta do relatório (severidade → cor), o que prova que o chip foi pintado
for cor in B91C1C EA580C D97706 059669; do
  grep -q "#$cor" "$HTML" || falha "cor #$cor ausente da paleta"
done
ok "paleta de severidade aplicada"

# 4. as issues saem delimitadas e completas — é o que a pessoa copia e cola
grep -q -- '--- ISSUE 1 ---' "$HTML" && grep -q -- '--- FIM ISSUE 1 ---' "$HTML" \
  && ok "issues delimitadas" || falha "delimitador de issue ausente"
grep -q '\[Segurança\]' "$HTML" && ok "título de issue no formato certo" \
  || falha "issue sem o prefixo [Segurança]"
grep -q 'Critérios de aceite' "$HTML" && ok "issue traz critérios de aceite" \
  || falha "issue sem critérios de aceite"

# 5. categoria não aplicável nunca some em silêncio
python3 - "$SKILL/references/exemplo-findings.json" "$TMP/na.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["categorias"][-1].update({"aplicavel": False, "nota": "Projeto sem frontend."})
json.dump(d, open(sys.argv[2], "w"))
PY
python3 "$SKILL/scripts/gerar-relatorio.py" "$TMP/na.json" --out "$TMP/na.pdf" --html-only \
  > /dev/null 2>&1
grep -q 'não aplicável a esta stack' "$TMP/na.html" && ok "categoria não aplicável sai escrita" \
  || falha "categoria não aplicável sumiu do relatório"

# 6. campo obrigatório ausente falha alto, não gera relatório pela metade
echo '{"projeto":"x","data":"01/01/2026"}' > "$TMP/incompleto.json"
if python3 "$SKILL/scripts/gerar-relatorio.py" "$TMP/incompleto.json" \
     --out "$TMP/i.pdf" --html-only > /dev/null 2>&1; then
  falha "JSON sem 'categorias' gerou relatório em vez de falhar"
else
  ok "JSON incompleto é recusado"
fi

# 7. o veredito é derivado dos achados e aparece no relatório e na saída do comando.
#    O exemplo tem uma crítica lida com confiança 0,85 -> BLOQUEADO.
grep -q 'BLOQUEADO' "$TMP/log.txt" && ok "veredito impresso no stdout" \
  || falha "gerador não imprimiu o veredito"
grep -q 'Veredito da auditoria' "$HTML" && grep -qi '>Bloqueado<' "$HTML" \
  && ok "veredito no resumo executivo" || falha "bloco de veredito ausente do HTML"

# 8. o teto de confiança do nível de evidência vence a declaração. Este é o
#    invariante central: convicção declarada não promove evidência fraca.
gerar_variante() {  # $1=script python  $2=nome
  python3 - "$SKILL/references/exemplo-findings.json" "$TMP/$2.json" <<PY
import json, sys
d = json.load(open(sys.argv[1]))
$1
json.dump(d, open(sys.argv[2], "w"))
PY
  python3 "$SKILL/scripts/gerar-relatorio.py" "$TMP/$2.json" --out "$TMP/$2.pdf" \
    --html-only > "$TMP/$2.log" 2>&1
}

gerar_variante 'for a in d["achados"]:
    a["evidencia"], a["confianca"] = "padrao", 0.99' teto
if grep -q '>0,99<' "$TMP/teto.html"; then
  falha "confiança declarada furou o teto do nível de evidência"
else
  grep -q '>0,60<' "$TMP/teto.html" && ok "teto de confiança do nível aplicado (0,99 -> 0,60)" \
    || falha "teto não aplicado: 0,60 não apareceu na tabela"
fi

# 9. sem confiança declarada, 'padrao' vale 0,45: abaixo do limiar da crítica.
#    O veredito não bloqueia (não há leitura que sustente) e também não libera --
#    crítica não confirmada é motivo para ir confirmar, não para encerrar.
gerar_variante 'for a in d["achados"]:
    a["evidencia"] = "padrao"
    a.pop("confianca", None)' naoconf
grep -q 'REVISAR' "$TMP/naoconf.log" && ok "crítica não confirmada vai para REVISAR" \
  || falha "crítica só com padrão não deveria bloquear nem liberar"
grep -q 'LIBERADO' "$TMP/naoconf.log" && falha "crítica não confirmada saiu LIBERADO" \
  || ok "crítica não confirmada não é liberada"

# 10. achado não acionável sai do cálculo, mas continua visível com selo
gerar_variante 'for a in d["achados"]:
    a["status"] = "risco_aceito"' aceito
grep -q 'LIBERADO' "$TMP/aceito.log" && ok "risco aceito sai do cálculo do veredito" \
  || falha "achado não acionável ainda pesa no veredito"
grep -q 'Risco aceito' "$TMP/aceito.html" && ok "achado suprimido continua no relatório" \
  || falha "achado não acionável sumiu do relatório"

# 11. ferramenta que não rodou vira aviso de superfície não medida
gerar_variante 'd["ferramentas"].append({"nome": "trivy", "estado": "nao_instalado"})' semtool
grep -q 'Superfície não medida' "$TMP/semtool.html" && ok "ferramenta ausente vira aviso no PDF" \
  || falha "ferramenta não instalada não gerou aviso"
grep -q 'ATENCAO' "$TMP/semtool.log" && ok "ferramenta ausente avisada no stdout" \
  || falha "stdout silencioso sobre superfície não medida"

# 12. segredo no trecho é mascarado antes de virar PDF e issue
gerar_variante 'd["achados"][0]["trecho"] = "const k = \"sk-proj-AbCdEf0123456789XyZq\";"
d["issues"][0]["achados"] = ["F1"]' segredo
grep -q 'sk-proj-AbCdEf0123456789XyZq' "$TMP/segredo.html" \
  && falha "segredo foi para o relatório sem máscara" \
  || ok "segredo mascarado no trecho"
[ "$(grep -c 'CHAVE REDIGIDA' "$TMP/segredo.html")" -ge 2 ] \
  && ok "máscara vale também no corpo da issue" \
  || falha "issue saiu sem a máscara (o GitHub é mais público que o PDF)"

# 13. o default público versionado precisa sobreviver: é a evidência do achado
grep -q 'supersecret-change-me' "$HTML" && ok 'escotilha "redacao": false preserva a evidência' \
  || falha "redação comeu o default público que é a própria evidência"

# 14. valor desconhecido em evidencia/status aborta, não vira default em silêncio
#     (rebaixar em silêncio mudaria o veredito sem ninguém notar)
for par in 'evidencia:conferido' 'status:resolvido'; do
  campo="${par%%:*}"; valor="${par##*:}"
  gerar_variante "d[\"achados\"][0][\"$campo\"] = \"$valor\"" "inv_$campo" && :
  if [ -s "$TMP/inv_$campo.html" ] && ! grep -qi 'invalid' "$TMP/inv_$campo.log"; then
    falha "$campo inválido foi aceito em silêncio"
  else
    ok "$campo inválido é recusado"
  fi
done

echo
if [ "$falhas" -eq 0 ]; then echo "PASSOU"; else echo "$falhas FALHA(S)"; fi
exit $((falhas > 0))
