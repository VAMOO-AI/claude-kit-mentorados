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

echo
if [ "$falhas" -eq 0 ]; then echo "PASSOU"; else echo "$falhas FALHA(S)"; fi
exit $((falhas > 0))
