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
[ "$(grep -c 'chave de projeto OpenAI redigida' "$TMP/segredo.html")" -ge 2 ] \
  && ok "máscara vale também no corpo da issue" \
  || falha "issue saiu sem a máscara (o GitHub é mais público que o PDF)"

# 12c. cada tipo de chave, no trecho e no markdown da issue (que não tem escotilha):
#      nenhum valor inteiro sai. Até a 0.43.0 a redação só casava sk-/rk- com hífen, e as
#      chaves da Stripe (sk_live_, sk_test_, rk_live_, rk_test_) iam inteiras para o PDF.
#      A máscara segue a da A4: 4 caracteres + "…", e o tipo num rótulo separado.
#      Chaves montadas por concatenação: o prefixo inteiro num literal é o que a push
#      protection do GitHub reconhece.
rep() { printf "$1%.0s" $(seq 1 "$2"); }
export CH_SKP="sk-""proj-FALSO$(rep b 30)" CH_SKA="sk-""ant-api03-FALSO$(rep f 40)" \
       CH_SKL="sk_""live_FALSO$(rep c 24)" CH_SKT="sk_""test_FALSO$(rep d 24)" \
       CH_RKL="rk_""live_FALSO$(rep e 24)" CH_RKT="rk_""test_FALSO$(rep g 24)" \
       CH_SK="sk-FALSO$(rep a 30)"
CHAVES="CH_SKP CH_SKA CH_SKL CH_SKT CH_RKL CH_RKT CH_SK"
python3 - "$SKILL/references/exemplo-findings.json" "$TMP/chaves.json" <<'PYC'
import json, os, sys
d = json.load(open(sys.argv[1]))
nomes = "CH_SKP CH_SKA CH_SKL CH_SKT CH_RKL CH_RKT CH_SK".split()
linhas = [f'const k{i} = "{os.environ[n]}";' for i, n in enumerate(nomes)]
linhas.append(f'api_key = "{os.environ["CH_SKL"]}"')
d["achados"][0]["trecho"] = "\n".join(linhas)
d["issues"][0]["achados"] = ["F1"]
d["issues"][1]["markdown"] = "## Problema\n\n```\n" + "\n".join(linhas) + "\n```"
json.dump(d, open(sys.argv[2], "w"))
PYC
python3 "$SKILL/scripts/gerar-relatorio.py" "$TMP/chaves.json" --out "$TMP/chaves.pdf" \
  --html-only > "$TMP/chaves.log" 2>&1 || { falha "gerador falhou com as chaves"; cat "$TMP/chaves.log"; }
vazou=""
for n in $CHAVES; do grep -qF "${!n}" "$TMP/chaves.html" && vazou="$vazou ${!n:0:8}"; done
[ -z "$vazou" ] && ok "nenhuma chave sai inteira no HTML (trecho e markdown da issue)" \
  || falha "chave inteira no relatório:$vazou"
for rot in 'sk-p… [chave de projeto OpenAI redigida]' 'sk-a… [chave Anthropic redigida]' \
           'sk_l… [chave Stripe sk_live_ redigida]' 'sk_t… [chave Stripe sk_test_ redigida]' \
           'rk_l… [chave Stripe rk_live_ redigida]' 'rk_t… [chave Stripe rk_test_ redigida]' \
           'sk-F… [chave sk- redigida]'; do
  [ "$(grep -cF "$rot" "$TMP/chaves.html")" -ge 2 ] && ok "4 caracteres + tipo: $rot" \
    || falha "rótulo ausente do trecho ou da issue: $rot"
done
grep -qF 'api_key = &quot;sk_l… [chave Stripe sk_live_ redigida]&quot;' "$TMP/chaves.html" \
  && ok "atribuição com chave mantém o rótulo do tipo" \
  || falha "a redação da atribuição engoliu o rótulo do tipo"

# 12d. default de compose: a chave da Stripe escrita como default sai mascarada com o tipo, e o
#      default genérico ${VAR:-valor} também, com a régua da A4 (até 12 caracteres só "…",
#      acima os 4 primeiros + "…"), no trecho e no markdown da issue. O arquivo:linha continua
#      como evidência. Referência (${A:-${B}}) não é valor e fica.
python3 - "$SKILL/references/exemplo-findings.json" "$TMP/default.json" <<'PYC'
import json, os, sys
d = json.load(open(sys.argv[1]))
linhas = ("      STRIPE_KEY: ${STRIPE_KEY:-" + os.environ["CH_SKL"] + "}\n"
          "      DB_PASSWORD: ${DB_PASSWORD:-senhaQualquer1}\n"
          "      CURTA: ${CURTA:-s3nha12}\n"
          "      REF: ${REF:-${OUTRA}}")
d["achados"][0]["trecho"] = linhas
d["issues"][0]["achados"] = [d["achados"][0]["id"]]
d["issues"][1]["markdown"] = "```\n" + linhas + "\n```"
json.dump(d, open(sys.argv[2], "w"))
PYC
python3 "$SKILL/scripts/gerar-relatorio.py" "$TMP/default.json" --out "$TMP/default.pdf" \
  --html-only > "$TMP/default.log" 2>&1 || { falha "gerador falhou com o default"; cat "$TMP/default.log"; }
grep -qF "$CH_SKL" "$TMP/default.html" && falha "chave da Stripe no default saiu inteira" \
  || ok "chave da Stripe escrita como default sai mascarada"
grep -qF 'STRIPE_KEY:-sk_l… [chave Stripe sk_live_ redigida]}' "$TMP/default.html" \
  && ok "o default da Stripe leva 4 caracteres e o tipo" || falha "default da Stripe sem o rótulo do tipo"
grep -qF 'senhaQualquer1' "$TMP/default.html" && falha "default genérico saiu inteiro" \
  || ok "default genérico não sai inteiro (trecho e issue)"
[ "$(grep -cF 'DB_PASSWORD:-senh…}' "$TMP/default.html")" -ge 2 ] \
  && ok "default genérico de 14 caracteres: 4 + … no trecho e na issue" || falha "default genérico sem a régua da A4"
grep -qF 's3nha12' "$TMP/default.html" && falha "default curto saiu inteiro" || ok "default curto não sai"
[ "$(grep -cF 'CURTA:-…}' "$TMP/default.html")" -ge 2 ] && ok "default de até 12 caracteres: só …" \
  || falha "default curto sem a régua da A4"
[ "$(grep -cF 'REF:-${OUTRA}}' "$TMP/default.html")" -ge 2 ] && ok "referência no default fica como está" \
  || falha "a redação mexeu na referência \${OUTRA}"
# a escotilha vale só para o trecho: o markdown da issue é mascarado mesmo assim
python3 - "$TMP/default.json" "$TMP/default-esc.json" <<'PYC'
import json, sys
d = json.load(open(sys.argv[1]))
d["achados"][0]["redacao"] = False
json.dump(d, open(sys.argv[2], "w"))
PYC
python3 "$SKILL/scripts/gerar-relatorio.py" "$TMP/default-esc.json" --out "$TMP/default-esc.pdf" \
  --html-only > "$TMP/default-esc.log" 2>&1 || falha "gerador falhou com a escotilha"
n_esc="$(grep -cF 'senhaQualquer1' "$TMP/default-esc.html")"; n_md="$(grep -cF 'DB_PASSWORD:-senh…}' "$TMP/default-esc.html")"
[ "$n_esc" -ge 1 ] && [ "$n_md" -ge 1 ] && ok "redacao: false preserva o default no trecho, e o markdown continua mascarado" \
  || falha "escotilha: trecho com o valor $n_esc vez(es), markdown mascarado $n_md vez(es)"

# 12e. revisão da 0.43.1: senha em URL (scheme://usuario:senha@), chave com prefixo colado
#      em _ ou em %20 (o \b antes de sk|rk deixava passar) e o whsec_ do webhook da Stripe.
#      O sk- genérico continua com fronteira: "task-list-…" é texto, não chave.
export CH_URLPASS="SenhaFalsa$(rep 7 8)" CH_WHS="wh""sec_FALSO$(rep h 28)" \
       CH_SKL2="sk_""live_FALSO$(rep j 24)" CH_RKT2="rk_""test_FALSO$(rep k 24)" CH_SKP2="sk-""proj-FALSO$(rep m 30)"
python3 - "$SKILL/references/exemplo-findings.json" "$TMP/rev.json" <<'PYC'
import json, os, sys
d = json.load(open(sys.argv[1]))
e = os.environ
linhas = [f'DATABASE_URL=postgres://u:{e["CH_URLPASS"]}@h/db',
          f'curl -H "Authorization: Bearer%20{e["CH_SKL2"]}" x',
          f'const x_{e["CH_RKT2"]} = 1; y=_{e["CH_SKP2"]}',
          f'const w = "{e["CH_WHS"]}";',
          'const lista = "task-list-of-the-week-items";']
d["achados"][0]["trecho"] = "\n".join(linhas)
d["issues"][0]["achados"] = ["F1"]
d["issues"][1]["markdown"] = "## Problema\n\n```\n" + "\n".join(linhas) + "\n```"
json.dump(d, open(sys.argv[2], "w"))
PYC
python3 "$SKILL/scripts/gerar-relatorio.py" "$TMP/rev.json" --out "$TMP/rev.pdf" \
  --html-only > "$TMP/rev.log" 2>&1 || { falha "gerador falhou com os casos da revisão"; cat "$TMP/rev.log"; }
for n in CH_URLPASS CH_WHS CH_SKL2 CH_RKT2 CH_SKP2; do
  [ "$(grep -cF "${!n}" "$TMP/rev.html")" = 0 ] && ok "revisão: $n não sai inteiro (trecho e issue)" \
    || falha "revisão: $n inteiro no relatório"
done
[ "$(grep -cF 'postgres://u:' "$TMP/rev.html")" -ge 2 ] && ok "senha em URL: o usuário e o esquema continuam" \
  || falha "senha em URL: a redação levou o esquema ou o usuário junto"
[ "$(grep -cF 'task-list-of-the-week-items' "$TMP/rev.html")" -ge 2 ] && ok "sk- genérico mantém a fronteira: task-list-… intacto" \
  || falha "a redação comeu o task-list-…"
[ "$(grep -cF '[chave whsec_ do webhook Stripe redigida]' "$TMP/rev.html")" -ge 2 ] && ok "whsec_ sai com o tipo" \
  || falha "whsec_ sem o rótulo do tipo"

# Fatia o relatório por destino: "fora" é tudo menos as issues (o trecho do achado está ali),
# "issue1", "issue2"... é o corpo entre os delimitadores. O achado com "redacao": false mostra o
# valor no trecho de propósito, então contar no HTML inteiro não separa escotilha de vazamento.
destinos() {  # $1=arquivo (HTML ou texto do PDF)  $2=literal  → "fora=N issue1=N ..."
  python3 - "$1" "$2" <<'PYD'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
blocos = re.findall(r"--- ISSUE (\d+) ---(.*?)--- FIM ISSUE \1 ---", t, re.S)
fora = re.sub(r"--- ISSUE (\d+) ---.*?--- FIM ISSUE \1 ---", "", t, flags=re.S)
print(" ".join([f"fora={fora.count(sys.argv[2])}"] + [f"issue{i}={b.count(sys.argv[2])}" for i, b in blocos]))
PYD
}

# 12f. default aninhado: ${A:-${B:-valor}} saía inteiro no trecho, na issue automática e no
#      markdown da issue, porque o valor começava com "$" e o default interno nunca era visitado.
#      Só a referência pura (${A:-${B}}, ${A:-${B:-${C}}}) fica como está.
export CH_NEST1="Aninhado""FALSO""12345" CH_NEST2="Fundo""FALSO""senha678"
python3 - "$SKILL/references/exemplo-findings.json" "$TMP/aninhado.json" <<'PYC'
import json, os, sys
d = json.load(open(sys.argv[1]))
e = os.environ
linhas = ("X: ${A:-${B:-" + e["CH_NEST1"] + "}}\n"
          "Y: ${A:-${B:-${C:-" + e["CH_NEST2"] + "}}}\n"
          "R1: ${A:-${B}}\n"
          "R2: ${A:-${B:-${C}}}")
d["achados"][0]["trecho"] = linhas
d["issues"][0]["achados"] = [d["achados"][0]["id"]]
d["issues"][0].pop("markdown", None)
d["issues"][1]["markdown"] = "```\n" + linhas + "\n```"
json.dump(d, open(sys.argv[2], "w"))
PYC
python3 "$SKILL/scripts/gerar-relatorio.py" "$TMP/aninhado.json" --out "$TMP/aninhado.pdf" \
  --html-only > "$TMP/aninhado.log" 2>&1 || { falha "gerador falhou com o default aninhado"; cat "$TMP/aninhado.log"; }
for n in CH_NEST1 CH_NEST2; do
  d="$(destinos "$TMP/aninhado.html" "${!n}")"
  [ "$d" = "fora=0 issue1=0 issue2=0 issue3=0" ] && ok "default aninhado: $n não sai no trecho nem nas issues" \
    || falha "default aninhado: $n inteiro ($d)"
done
for alvo in 'X: ${A:-${B:-Anin…}}' 'Y: ${A:-${B:-${C:-Fund…}}}' 'R1: ${A:-${B}}' 'R2: ${A:-${B:-${C}}}'; do
  d="$(destinos "$TMP/aninhado.html" "$alvo")"
  case "$d" in fora=[1-9]*' issue1='[1-9]*' issue2='[1-9]*) ok "trecho, issue automática e markdown: $alvo" ;;
    *) falha "esperado nos três destinos: $alvo ($d)" ;; esac
done

# 12g. a escotilha "redacao": false vale só para o trecho do PDF. A issue automática usava o
#      mesmo trecho_redigido, e o corpo saía cru no GitHub e na seção "Issues para o GitHub".
export CH_ESC_SKL="sk_""live_FALSO$(rep n 24)" CH_ESC_DEF="senha""Escotilha""F2x9"
python3 - "$SKILL/references/exemplo-findings.json" "$TMP/esc-issue.json" <<'PYC'
import json, os, sys
d = json.load(open(sys.argv[1]))
e = os.environ
a = d["achados"][0]
a["trecho"] = ("const s = \"" + e["CH_ESC_SKL"] + "\";\n"
               "DB_PASSWORD: ${DB_PASSWORD:-" + e["CH_ESC_DEF"] + "}\n"
               "X: ${A:-${B:-" + e["CH_NEST1"] + "}}")
a["redacao"] = False
d["issues"][0]["achados"] = [a["id"]]
d["issues"][0].pop("markdown", None)
json.dump(d, open(sys.argv[2], "w"))
PYC
python3 "$SKILL/scripts/gerar-relatorio.py" "$TMP/esc-issue.json" --out "$TMP/esc-issue.pdf" \
  --html-only > "$TMP/esc-issue.log" 2>&1 || { falha "gerador falhou com a escotilha na issue"; cat "$TMP/esc-issue.log"; }
for n in CH_ESC_SKL CH_ESC_DEF CH_NEST1; do
  d="$(destinos "$TMP/esc-issue.html" "${!n}")"
  case "$d" in fora=[1-9]*' issue1=0 issue2=0 issue3=0') ok "redacao: false: $n no trecho, fora de toda issue" ;;
    *) falha "redacao: false: $n ($d; esperado no trecho e em nenhuma issue)" ;; esac
done
d="$(destinos "$TMP/esc-issue.html" 'sk_l… [chave Stripe sk_live_ redigida]')"
case "$d" in *' issue1='[1-9]*) ok "issue automática de achado com escotilha sai mascarada" ;;
  *) falha "issue automática sem a máscara ($d)" ;; esac
d="$(destinos "$HTML" 'supersecret-change-me')"
case "$d" in fora=[1-9]*' issue1=0 issue2=0 issue3=0') ok "exemplo: F3 com escotilha no trecho e mascarado na issue 3" ;;
  *) falha "exemplo: default do F3 ($d)" ;; esac

# O PDF de verdade, quando a máquina tem Chrome e pdftotext (o CI não tem): texto extraído.
if python3 -B -c 'import sys; import importlib.util as u
s = u.spec_from_file_location("g", sys.argv[1] + "/gerar-relatorio.py"); m = u.module_from_spec(s); s.loader.exec_module(m)
sys.exit(0 if m.achar_chrome() else 1)' "$SKILL/scripts" 2>/dev/null && command -v pdftotext >/dev/null; then
  python3 "$SKILL/scripts/gerar-relatorio.py" "$TMP/chaves.json" --out "$TMP/chaves.pdf" > "$TMP/chaves-pdf.log" 2>&1 \
    && pdftotext "$TMP/chaves.pdf" "$TMP/chaves.txt" \
    || falha "PDF com as chaves não foi gerado"
  vazou=""
  for n in $CHAVES; do grep -qF "${!n}" "$TMP/chaves.txt" && vazou="$vazou ${!n:0:8}"; done
  [ -s "$TMP/chaves.txt" ] && [ -z "$vazou" ] && ok "nenhuma chave sai inteira no texto do PDF" \
    || falha "chave inteira no PDF (ou PDF vazio):$vazou"
  # default aninhado e escotilha no PDF: o que vem depois de "Issues para o GitHub" não traz
  # valor nenhum; antes, o trecho com a escotilha traz, e o aninhado sem escotilha não.
  for caso in aninhado esc-issue; do
    python3 "$SKILL/scripts/gerar-relatorio.py" "$TMP/$caso.json" --out "$TMP/$caso-real.pdf" > /dev/null 2>&1 \
      && pdftotext "$TMP/$caso-real.pdf" "$TMP/$caso.txt" || falha "PDF $caso não foi gerado"
  done
  pdf_issues() { python3 -c 'import sys; t = open(sys.argv[1]).read(); i = t.find("Issues para o GitHub"); print(t[i:] if i >= 0 else "SEM SECAO")' "$1"; }
  vazou=""
  for n in CH_NEST1 CH_NEST2; do grep -qF "${!n}" "$TMP/aninhado.txt" && vazou="$vazou $n"; done
  for n in CH_ESC_SKL CH_ESC_DEF CH_NEST1; do
    case "$(pdf_issues "$TMP/esc-issue.txt")" in *"${!n}"*|"SEM SECAO") vazou="$vazou $n(issue)";; esac
  done
  [ -s "$TMP/aninhado.txt" ] && [ -s "$TMP/esc-issue.txt" ] && [ -z "$vazou" ] \
    && ok "PDF: default aninhado e issue de achado com escotilha saem mascarados" \
    || falha "PDF: valor inteiro:$vazou"
  grep -qF "$CH_ESC_DEF" "$TMP/esc-issue.txt" && ok "PDF: a escotilha continua valendo no trecho" \
    || falha "PDF: a escotilha sumiu do trecho"
else
  echo "  pulado PDF real: sem Chrome ou pdftotext nesta máquina (o HTML acima é a fonte do PDF)"
fi

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

# 23. rastreabilidade de compliance: seção no PDF e linha na issue. A issue 1 (F1,
#     A1, sem 'compliance') herda o default da categoria; a issue 3 (F3) usa o
#     override declarado. Os dois juntos provam herança e override.
grep -qF 'Rastreabilidade de compliance</h2>' "$HTML" && ok "seção de compliance no relatório" \
  || falha "seção Rastreabilidade de compliance ausente"
grep -qF "<td class='arq'>A.8.3</td>" "$HTML" && ok "controle default da categoria na tabela" \
  || falha "tabela de compliance sem o default da A1"
grep -qF '**Compliance:** `OWASP:A01:2025`, `OWASP-API:API1:2023`' "$HTML" \
  && ok "issue herda o compliance default da categoria" \
  || falha "issue sem a linha Compliance: do default da categoria"
# linha inteira, ancorada no fim: override somado ao default da A4 também traria A.8.9
grep -qE '\*\*Compliance:\*\* `OWASP:A02:2025`, `OWASP:A07:2025`, `ISO27001:A\.8\.9`, `PCI-DSS:2\.2\.2`$' "$HTML" \
  && ok "override de compliance substitui o default da categoria na issue" \
  || falha "override de compliance não substituiu o default da categoria na issue"

# 24. framework fora da lista aborta SEMPRE, não só no --verificar: sem isso o PDF
#     de cliente saía com control ID inventado etiquetado num achado provado
gerar_variante 'd["achados"][2]["compliance"] = ["HIPAA:164.312"]' fwdesconhecido
st=$?
if [ "$st" -ne 0 ] && [ ! -e "$TMP/fwdesconhecido.html" ] \
   && grep -q 'framework desconhecido' "$TMP/fwdesconhecido.log"; then
  ok "framework de compliance desconhecido aborta sem --verificar"
else
  falha "framework de compliance desconhecido passou sem --verificar (exit $st)"
fi
verificar 'd["achados"][2]["compliance"] = ["HIPAA:164.312"]' fwdesconhecidov
[ $? -ne 0 ] && grep -q 'framework desconhecido' "$TMP/fwdesconhecidov.log" \
  && ok "framework desconhecido aborta também com --verificar" \
  || falha "framework desconhecido passou no --verificar"
gerar_variante 'd["achados"][2]["compliance"] = "OWASP:A02:2025"' naolista
[ $? -ne 0 ] && grep -q 'deve ser lista' "$TMP/naolista.log" \
  && ok "compliance que não é lista aborta" \
  || falha "compliance em string passou calado"

# 25. prefixo certo, ID fora da norma vigente: OWASP 2021 foi substituído pelo
#     2025 (A03 hoje é supply chain, não injeção) e ISO 27001:2022 para em A.8.34
gerar_variante 'd["achados"][2]["compliance"] = ["OWASP:A03:2021"]' owasp2021
[ $? -ne 0 ] && grep -q 'OWASP:A03:2021' "$TMP/owasp2021.log" \
  && ok "control ID do OWASP 2021 é recusado" \
  || falha "control ID do OWASP 2021 passou"
gerar_variante 'd["achados"][2]["compliance"] = ["ISO27001:A.8.35"]' isoinexistente
[ $? -ne 0 ] && grep -q 'A.8.35' "$TMP/isoinexistente.log" \
  && ok "controle ISO 27001 inexistente é recusado" \
  || falha "controle ISO 27001 inexistente passou"

# 26. LGPD entra por override quando o dado alcançado é pessoal
gerar_variante 'd["achados"][1]["compliance"] = ["OWASP:A01:2025", "LGPD:Art.46"]' lgpd
if [ $? -eq 0 ] && grep -qF 'Lei 13.709/2018' "$TMP/lgpd.html" \
   && grep -qF "<td class='arq'>Art.46</td>" "$TMP/lgpd.html"; then
  ok "override com LGPD:Art.46 sai na rastreabilidade"
else
  falha "override com LGPD não saiu no relatório"; cat "$TMP/lgpd.log"
fi

echo
if [ "$falhas" -eq 0 ]; then echo "PASSOU"; else echo "$falhas FALHA(S)"; fi
exit $((falhas > 0))
