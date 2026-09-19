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

# 10. achado não acionável sai do cálculo, mas continua visível com selo e motivo.
#     (a hipótese a_validar F6 é crítica potencial: segura o veredito em REVISAR,
#     nunca em LIBERADO — ver caso 17)
gerar_variante 'for a in d["achados"]:
    if a.get("status") != "a_validar":
        a["status"], a["motivo"] = "risco_aceito", "Decisão do CTO em 02/09/2026: corrige no Q4."' aceito
grep -q 'BLOQUEADO' "$TMP/aceito.log" && falha "achado não acionável ainda pesa no veredito" \
  || ok "risco aceito sai do cálculo do veredito"
grep -q 'Risco aceito' "$TMP/aceito.html" && ok "achado suprimido continua no relatório" \
  || falha "achado não acionável sumiu do relatório"
grep -q 'Motivo do status' "$TMP/aceito.html" && ok "motivo do status aparece no achado" \
  || falha "motivo do risco aceito não foi impresso"

# 10b. tirar do veredito sem justificativa escrita é recusado: é assim que a mesma
#      discussão volta na auditoria seguinte
gerar_variante 'd["achados"][0]["status"] = "falso_positivo"' semmotivo
if [ -s "$TMP/semmotivo.html" ]; then
  falha "falso_positivo sem motivo foi aceito em silêncio"
else
  grep -q "exige 'motivo'" "$TMP/semmotivo.log" && ok "status sem motivo é recusado" \
    || falha "recusa sem a mensagem do motivo"
fi

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

# 12b. issue com markdown escrito à mão passa pela mesma máscara — é o mesmo
#      GitHub, e quem escreve markdown custom é quem colou o trecho na unha
gerar_variante 'd["issues"][0]["markdown"] = "## Problema\n\n```\nconst k = \"sk-proj-AbCdEf0123456789XyZq\";\n```"' md
grep -q 'sk-proj-AbCdEf0123456789XyZq' "$TMP/md.html" \
  && falha "markdown custom da issue escapou da máscara" \
  || ok "markdown custom da issue também é mascarado"

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

# 15. lead a_validar não é achado: fora da rosca (o exemplo tem 5 achados + F6 a
#     validar, e a rosca continua em 5), com seção própria que diz o que falta saber
grep -q '>5</text>' "$HTML" && ok "hipótese a validar não entra na rosca" \
  || falha "a_validar foi contada como achado"
grep -q '>A validar</h2>' "$HTML" && grep -q 'O que falta saber' "$HTML" \
  && ok "seção A validar com o bloqueio" || falha "seção A validar ausente ou sem bloqueio"
grep -q 'O que o dono do deploy confere' "$HTML" && ok "plano de validação do dono impresso" \
  || falha "plano_validacao.dono sumiu"
grep -q 'hipótese(s) a validar' "$HTML" && ok "resumo conta as hipóteses à parte" \
  || falha "resumo não menciona hipóteses a validar"
grep -q 'A validar: 1 hipotese' "$TMP/log.txt" && ok "stdout conta as hipóteses" \
  || falha "stdout silencioso sobre hipóteses a validar"

# 16. a_validar sem o fato exato que falta é recusado — "depende do deploy" sem
#     dizer o quê é a hipótese virando lixo
gerar_variante 'd["achados"][-1].pop("bloqueio")' sembloqueio
if [ -s "$TMP/sembloqueio.html" ]; then
  falha "a_validar sem bloqueio foi aceito"
else
  grep -q "exige 'bloqueio'" "$TMP/sembloqueio.log" && ok "a_validar sem bloqueio é recusado" \
    || falha "recusa sem a mensagem do bloqueio"
fi

# 17. crítica potencial pendente nunca sai LIBERADO: o bloqueio é para resolver.
#     Todos os outros achados aceitos com motivo; só a hipótese F6 (crítica) fica.
gerar_variante 'for a in d["achados"]:
    if a.get("status") != "a_validar":
        a["status"], a["motivo"] = "corrigido", "PR #12 mergeado em 03/09/2026."' pendente
grep -q 'REVISAR' "$TMP/pendente.log" && ok "crítica potencial a validar segura em REVISAR" \
  || falha "crítica a validar não segurou o veredito"
grep -q 'LIBERADO' "$TMP/pendente.log" && falha "crítica a validar saiu LIBERADO" \
  || ok "crítica a validar não é liberada"
# ...e uma hipótese de severidade menor não pesa nada
gerar_variante 'for a in d["achados"]:
    if a.get("status") != "a_validar":
        a["status"], a["motivo"] = "corrigido", "PR #12."
    else:
        a["severidade"] = "media"' pendmedia
grep -q 'LIBERADO' "$TMP/pendmedia.log" && ok "hipótese média a validar não pesa no veredito" \
  || falha "hipótese média a validar mudou o veredito"

# 18. notas de hardening têm seção própria e não entram na contagem
grep -q 'Notas de hardening' "$HTML" && grep -q 'SameSite' "$HTML" \
  && ok "hardening em seção própria" || falha "hardening sumiu do relatório"

# 19. o caminho entrada → sink sai no achado, e a condição tipada também
grep -q '<b>Entrada</b>' "$HTML" && grep -q '<b>Sink</b>' "$HTML" \
  && ok "caminho entrada → sink impresso" || falha "caminho do achado não foi impresso"
grep -q 'Nível de autenticação:' "$HTML" && ok "condição tipada com rótulo" \
  || falha "condição tipada saiu sem rótulo"

# 20. primeira auditoria diz que é a primeira; a seguinte cita a anterior
grep -q 'primeira auditoria registrada' "$HTML" && ok "sem auditoria anterior: dito na capa" \
  || falha "capa silenciosa sobre auditoria anterior"
gerar_variante 'd["auditoria_anterior"] = {"data": "01/06/2026", "arquivo": "docs/security-audit/findings.json@abc123", "nota": "3 achados reverificados"}
d["achados"][0]["desde"] = "01/06/2026"' anterior
grep -q '3 achados reverificados' "$TMP/anterior.html" && grep -q 'desde 01/06/2026' "$TMP/anterior.html" \
  && ok "auditoria anterior e 'desde' impressos" || falha "auditoria anterior não apareceu"

# 21. --verificar: referências cruzadas e caminho, sem repo
verificar() {  # $1=script python  $2=nome  $3=raiz opcional
  python3 - "$SKILL/references/exemplo-findings.json" "$TMP/$2.json" <<PY
import json, sys
d = json.load(open(sys.argv[1]))
$1
json.dump(d, open(sys.argv[2], "w"))
PY
  python3 "$SKILL/scripts/gerar-relatorio.py" "$TMP/$2.json" --verificar ${3:+--raiz "$3"} \
    > "$TMP/$2.log" 2>&1
}
verificar '' limpo
grep -q 'NAO conferido' "$TMP/limpo.log" && ok "sem --raiz o código é declarado NÃO conferido" \
  || falha "sem --raiz o gerador fingiu ter conferido o código"
verificar 'd["issues"][0]["achados"] = ["F99"]' refquebrada
grep -q 'achado inexistente F99' "$TMP/refquebrada.log" && ok "issue citando achado inexistente é recusada" \
  || falha "referência quebrada passou"
verificar 'd["achados"][1]["fonte"] = ""' semfonte
grep -q 'corroborado sem' "$TMP/semfonte.log" && ok "corroborado sem fonte é recusado" \
  || falha "corroborado sem fonte passou (autodeclaração)"
verificar 'd["achados"][1]["caminho"][0]["tipo"] = "sink"' caminhoerrado
grep -q "não começa em 'entrada'" "$TMP/caminhoerrado.log" && ok "caminho sem entrada é recusado" \
  || falha "caminho que não começa na entrada passou"

# 22. --verificar --raiz: o trecho tem que estar no arquivo, nas linhas ditas.
#     Repo mínimo com o que os achados F1..F6 citam.
REPO="$TMP/repo"; mkdir -p "$REPO/api/routes" "$REPO/api/plugins" "$REPO/api/mail"
python3 - "$SKILL/references/exemplo-findings.json" "$REPO" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1])); raiz = sys.argv[2]
arquivos, fins = {}, {}
def alvo(arq, linha):
    partes = str(linha).split("-")
    fins[arq] = max(fins.get(arq, 0), int(partes[-1]))
    return arquivos.setdefault(arq, {}), int(partes[0])
for a in d["achados"]:
    mapa, ini = alvo(a["arquivo"], a["linhas"])
    for i, l in enumerate(a["trecho"].split("\n")):
        mapa[ini + i] = l.replace("   // sem organizationId", "")
    for p in a.get("caminho", []):
        mapa, ini = alvo(p["arquivo"], p["linha"])
        mapa.setdefault(ini, "// passo do caminho")
for arq, mapa in arquivos.items():
    n = max(max(mapa), fins[arq])
    with open(os.path.join(raiz, arq), "w") as f:
        f.write("\n".join(mapa.get(i, f"// linha {i}") for i in range(1, n + 1)) + "\n")
PY
verificar '' repook "$REPO"
grep -q 'Verificacao: ok' "$TMP/repook.log" && ok "trecho copiado do arquivo passa no --raiz" \
  || { falha "trecho fiel foi recusado"; cat "$TMP/repook.log"; }
verificar 'd["achados"][0]["trecho"] = "const rows = await prisma.sale.findMany({ where: {} });"' reescrito "$REPO"
grep -q 'linha do trecho não está em' "$TMP/reescrito.log" && ok "trecho reescrito de memória é recusado" \
  || falha "trecho que não existe no arquivo passou"
verificar 'd["achados"][0]["linhas"] = "9000-9010"' foradofim "$REPO"
grep -q 'fora de' "$TMP/foradofim.log" && ok "linhas fora do arquivo são recusadas" \
  || falha "linhas inexistentes passaram"
verificar 'd["achados"][0]["arquivo"] = "api/routes/nao-existe.ts"' semarquivo "$REPO"
grep -q 'arquivo não existe' "$TMP/semarquivo.log" && ok "arquivo inexistente é recusado" \
  || falha "arquivo que não existe passou"

echo
if [ "$falhas" -eq 0 ]; then echo "PASSOU"; else echo "$falhas FALHA(S)"; fi
exit $((falhas > 0))
