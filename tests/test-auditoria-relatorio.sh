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
#      nenhum valor inteiro sai. Antes a redação só casava sk-/rk- com hífen, e as
#      chaves da Stripe (sk_live_, sk_test_, rk_live_, rk_test_) iam inteiras para o PDF.
#      A máscara segue a da A4: 4 caracteres + "…", e o tipo num rótulo separado.
#      Chaves montadas por concatenação: o prefixo inteiro num literal é o que a push
#      protection do GitHub reconhece.
rep() { printf "$1%.0s" $(seq 1 "$2"); }
export CH_SKP="sk-""proj-FALSO$(rep b 30)" CH_SKA="sk-""ant-api03-FALSO$(rep f 40)" \
       CH_SKL="sk_""live_FALSO$(rep c 24)" CH_SKT="sk_""test_FALSO$(rep d 24)" \
       CH_RKL="rk_""live_FALSO$(rep e 24)" CH_RKT="rk_""test_FALSO$(rep g 24)" \
       CH_SK="sk-FALSO$(rep a 30)" CH_WHS="wh""sec_FALSO$(rep h 24)" \
       CH_BSK="sk_""live_FALSO$(rep i 24)" CH_XSK="sk_""live_FALSO$(rep j 24)" \
       CH_URL="SenhaDaUrlFALSO$(rep k 6)" \
       CH_GHP="gh""p_FALSO$(rep l 31)" CH_GPAT="github""_pat_FALSO$(rep m 30)" \
       CH_XOXA="xo""xa-FALSO$(rep n 20)" CH_XOXR="xo""xr-FALSO$(rep o 20)" \
       CH_XOXS="xo""xs-FALSO$(rep p 20)" CH_BGH="gh""p_FALSO$(rep q 31)" \
       CH_XGH="gh""o_FALSO$(rep r 31)" CH_TGH="gh""p_FALSO$(rep s 31)" \
       CH_DEF="senhaFALSO$(rep t 6)" CH_DEFC="FALSOc12" \
       CH_ATD="minha.senha.x" CH_ATP="abc(123)" CH_NDEF="valor13caract" \
       CH_AWS="wJalrFALSO$(rep v 30)" \
       CH_SBS="sb_""secret_FALSO$(rep w 30)" CH_NPM="np""m_FALSO$(rep x 31)" \
       CH_HF="h""f_FALSO$(rep y 30)" CH_AIZA="AI""zaSyFALSO$(rep z 28)" \
       CH_SG="S""G.FALSO$(rep A 17).FALSO$(rep B 38)" CH_SVC="sk-""svcacct-FALSO$(rep C 30)" \
       CH_ADM="sk-""admin-FALSO$(rep D 30)" CH_BSVC="sk-""svcacct-FALSO$(rep E 30)" \
       CH_URLD="\$ecretFALSO$(rep F 6)" CH_DLOW="DefaultFALSO$(rep G 6)" CH_DNC="OutraFALSO$(rep H 6)" CH_DLNC="SemDoisFALSO$(rep L 6)" \
       CH_LIT1="LiteralFALSO$(rep I 6)" CH_LIT2="LiteralFALSO$(rep J 6)"
# CH_BSK e CH_XSK entram colados em "Bearer%20" e "x_": antes o \b antes de sk|rk não
# via fronteira ali (0 e _ são caractere de palavra) e a chave saía inteira. CH_URL é a senha de
# postgres://u:<senha>@h, que nenhum padrão cobria. Antes o mesmo \b valia para gh*_, e
# github_pat_ e xox[ars]- não tinham padrão: CH_GPAT, CH_XOX* e os gh colados saíam inteiros.
CHAVES="CH_SKP CH_SKA CH_SKL CH_SKT CH_RKL CH_RKT CH_SK CH_WHS CH_BSK CH_XSK CH_URL
        CH_GHP CH_GPAT CH_XOXA CH_XOXR CH_XOXS CH_BGH CH_XGH CH_TGH CH_DEF CH_DEFC CH_ATD CH_ATP CH_NDEF CH_AWS
        CH_SBS CH_NPM CH_HF CH_AIZA CH_SG CH_SVC CH_ADM CH_BSVC CH_URLD CH_DLOW CH_DNC CH_DLNC CH_LIT1 CH_LIT2"
# Antes: sb_secret_ (Supabase novo), npm_, hf_, AIza (Google, 39 caracteres) e SG. (SendGrid,
# SG.<22>.<43>) não tinham padrão; sk-svcacct-/sk-admin- saíam como "chave sk-" genérica e, colados
# em Bearer%20, inteiros. CH_URLD é a senha de URL que começa com $ sem ser $NOME de env nem ${…}:
# as duas pontas isentavam qualquer $. CH_DLOW e CH_DNC são o default com nome minúsculo
# (${db_pass:-…}) e sem os dois-pontos (${PW-…}, ${lower_pw-…}). CH_LIT1/CH_LIT2 são o literal depois da } interna:
# ${A:-${B}Lit…} saía inteiro, e ${A:-${B:-x}Lit…} mascarava o x e deixava o Lit.
# CH_NDEF é o literal do default interno de ${A:-${B:-…}}: a referência pura fica intacta, o
# literal leva a máscara da A4. CH_AWS: a palavra-chave com sufixo no nome
# (AWS_SECRET_ACCESS_KEY) não casava, porque o [:=] tinha de vir logo depois de SECRET.
# CH_ATD e CH_ATP são atribuição sem aspas com ., $, ( ou { no valor: antes o _ATRIB_NUA
# excluía esses caracteres (para não mascarar req.body.password) e a senha saía em claro.
# CH_DEF e CH_DEFC são o default genérico do compose (${VAR:-valor}), que antes saía em
# claro como evidência. Agora segue a máscara da A4: acima de 12 caracteres, 4 + "…"; até 12, "…".
# Linhas que ficam intactas: referência em vez de valor (req., process.env, ${VAR}, default que
# é outra variável) e identificador comum que contém um prefixo de token sem \b.
export INTACTAS='password = req.body.password
SECRET=${OUTRA}
token: process.env.TOKEN
API_TOKEN: ${API_TOKEN:-${VAULT_TOKEN}}
JWT_SECRET: ${JWT_SECRET:-${FALLBACK_SECRET}}
fetch_sbp_connection_pool_settings()
load_sbs_credentials_from_vault_cache()
refresh_shpat_token_cache_for_store()
validate_github_pat_format_before_saving()
gitlab-gl''pat-rotation-interval-days
slack-xapp-socket-mode-handler
taskxoxb-queue-handler
DB=postgres://u:$DB_PASS@h/db
DB=postgres://u:${DB_PASS}@h/db
X: ${A:-${B:-${C}}}'
python3 - "$SKILL/references/exemplo-findings.json" "$TMP/chaves.json" <<'PY'
import json, os, sys
INTACTAS = os.environ["INTACTAS"].split("\n")
d = json.load(open(sys.argv[1]))
nomes = "CH_SKP CH_SKA CH_SKL CH_SKT CH_RKL CH_RKT CH_SK CH_WHS CH_GHP CH_GPAT CH_XOXA CH_XOXR CH_XOXS".split()
linhas = [f'const k{i} = "{os.environ[n]}";' for i, n in enumerate(nomes)]
linhas.append(f'api_key = "{os.environ["CH_SKL"]}"')
linhas.append(f'const h = "Bearer%20{os.environ["CH_BSK"]}";')
linhas.append(f'const x = "x_{os.environ["CH_XSK"]}";')
linhas.append(f'DATABASE_URL=postgres://u:{os.environ["CH_URL"]}@h/db')
linhas.append('const t = "risk-assessment-framework-v2";')
linhas.append(f'const g = "Bearer%20{os.environ["CH_BGH"]}";')
linhas.append(f'const y = "x_{os.environ["CH_XGH"]}";')
linhas.append(f'token = "{os.environ["CH_TGH"]}"')
linhas.append('const n = laughs_counter_total_value;')
linhas.append(f'DB_PASSWORD: ${{DB_PASSWORD:-{os.environ["CH_DEF"]}}}')
linhas.append(f'API_TOKEN: ${{API_TOKEN:-{os.environ["CH_DEFC"]}}}')
linhas.append(f'DB_PASSWORD={os.environ["CH_ATD"]}')
linhas.append(f'pwd={os.environ["CH_ATP"]}')
linhas.append(f'X: ${{A:-${{B:-{os.environ["CH_NDEF"]}}}}}')
linhas.append(f'AWS_SECRET_ACCESS_KEY={os.environ["CH_AWS"]}')
for i, n in enumerate("CH_SBS CH_NPM CH_HF CH_AIZA CH_SG CH_SVC CH_ADM".split()):
    linhas.append(f'const n{i} = "{os.environ[n]}";')
linhas.append(f'const b = "Bearer%20{os.environ["CH_BSVC"]}";')
linhas.append(f'u="postgres://u:{os.environ["CH_URLD"]}@h2/d"')
linhas.append(f'x=${{db_pass:-{os.environ["CH_DLOW"]}}} y=${{PW-{os.environ["CH_DNC"]}}} z=${{lower_pw-{os.environ["CH_DLNC"]}}}')
linhas.append(f'L1: ${{A:-${{B}}{os.environ["CH_LIT1"]}}}')
linhas.append(f'L2: ${{A:-${{B:-curto}}{os.environ["CH_LIT2"]}}}')
linhas += INTACTAS
d["achados"][0]["trecho"] = "\n".join(linhas)
d["issues"][0]["achados"] = ["F1"]
d["issues"][1]["markdown"] = "## Problema\n\n```\n" + "\n".join(linhas) + "\n```"
json.dump(d, open(sys.argv[2], "w"))
PY
python3 "$SKILL/scripts/gerar-relatorio.py" "$TMP/chaves.json" --out "$TMP/chaves.pdf" \
  --html-only > "$TMP/chaves.log" 2>&1 || { falha "gerador falhou com as chaves"; cat "$TMP/chaves.log"; }
vazou=""
for n in $CHAVES; do grep -qF "${!n}" "$TMP/chaves.html" && vazou="$vazou ${!n:0:8}"; done
[ -z "$vazou" ] && ok "nenhuma chave sai inteira no HTML (trecho e markdown da issue)" \
  || falha "chave inteira no relatório:$vazou"
for rot in 'sk-p… [chave de projeto OpenAI redigida]' 'sk-a… [chave Anthropic redigida]' \
           'sk_l… [chave Stripe sk_live_ redigida]' 'sk_t… [chave Stripe sk_test_ redigida]' \
           'rk_l… [chave Stripe rk_live_ redigida]' 'rk_t… [chave Stripe rk_test_ redigida]' \
           'sk-F… [chave sk- redigida]' 'whse… [chave de webhook Stripe redigida]' \
           'Bearer%20sk_l… [chave Stripe sk_live_ redigida]' 'x_sk_l… [chave Stripe sk_live_ redigida]' \
           'postgres://u:[SEGREDO REDIGIDO]@h/db' \
           'ghp_… [token do GitHub redigido]' 'gith… [token do GitHub redigido]' \
           'xoxa… [token do Slack redigido]' 'xoxr… [token do Slack redigido]' \
           'xoxs… [token do Slack redigido]' 'Bearer%20ghp_… [token do GitHub redigido]' \
           'x_gho_… [token do GitHub redigido]' \
           'DB_PASSWORD: ${DB_PASSWORD:-senh…}' 'API_TOKEN: ${API_TOKEN:-…}' \
           'sb_s… [token do Supabase redigido]' 'npm_… [token do npm redigido]' \
           'hf_F… [token do Hugging Face redigido]' 'AIza… [chave de API do Google redigida]' \
           'SG.F… [chave SendGrid redigida]' 'sk-s… [chave de conta de serviço OpenAI redigida]' \
           'sk-a… [chave admin OpenAI redigida]' 'Bearer%20sk-s… [chave de conta de serviço OpenAI redigida]' \
           'postgres://u:[SEGREDO REDIGIDO]@h2/d' 'x=${db_pass:-Defa…} y=${PW-Outr…} z=${lower_pw-SemD…}' \
           'L1: ${A:-${B}Lite…}' 'L2: ${A:-${B:-…}Lite…}'; do
  [ "$(grep -cF "$rot" "$TMP/chaves.html")" -ge 2 ] && ok "4 caracteres + tipo: $rot" \
    || falha "rótulo ausente do trecho ou da issue: $rot"
done
grep -qF 'api_key = &quot;sk_l… [chave Stripe sk_live_ redigida]&quot;' "$TMP/chaves.html" \
  && ok "atribuição com chave mantém o rótulo do tipo" \
  || falha "a redação da atribuição engoliu o rótulo do tipo"
grep -qF 'token = &quot;ghp_… [token do GitHub redigido]&quot;' "$TMP/chaves.html" \
  && ok "atribuição com token mantém o rótulo do tipo" \
  || falha "a redação da atribuição engoliu o rótulo do token"
for rot in 'DB_PASSWORD=[SEGREDO REDIGIDO]' 'pwd=[SEGREDO REDIGIDO]' \
           'AWS_SECRET_ACCESS_KEY=[SEGREDO REDIGIDO]' 'X: ${A:-${B:-valo…}}'; do
  [ "$(grep -cF "$rot" "$TMP/chaves.html")" -ge 2 ] && ok "atribuição sem aspas mascarada: $rot" \
    || falha "atribuição sem aspas saiu sem máscara no trecho ou na issue: $rot"
done
while IFS= read -r linha; do
  esc="$(printf '%s' "$linha" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
  [ "$(grep -cF -- "$esc" "$TMP/chaves.html")" -ge 2 ] && ok "intacta no trecho e na issue: $linha" \
    || falha "redigida (ou ausente) no trecho ou na issue: $linha"
done <<< "$INTACTAS"
grep -qF 'laughs_counter_total_value' "$TMP/chaves.html" \
  && ok "gh sem \\b não morde identificador snake_case (laughs_counter…)" \
  || falha "o padrão gh*_ redigiu laughs_counter_total_value"
# o marcador vem logo depois do prefixo: se ele aparece, sobrou valor além dos 4 caracteres
grep -q 'FALSO' "$TMP/chaves.html" && falha "sobra de valor no HTML: $(grep -o '[A-Za-z0-9_%-]*FALSO[A-Za-z0-9]*' "$TMP/chaves.html" | sort -u | tr '\n' ' ')" \
  || ok "nenhum resto de valor (FALSO) no HTML"
grep -qF 'risk-assessment-framework-v2' "$TMP/chaves.html" && ok "sk- genérico mantém a fronteira: risk-… não é chave" \
  || falha "o sk- genérico redigiu risk-assessment-framework-v2"
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
  # o pdftotext quebra linha longa, e o grep do valor inteiro passaria com vazamento
  grep -q 'FALSO' "$TMP/chaves.txt" && falha "sobra de valor no texto do PDF" \
    || ok "nenhum resto de valor (FALSO) no texto do PDF"
  intacta_pdf=""
  while IFS= read -r linha; do grep -qF -- "$linha" "$TMP/chaves.txt" || intacta_pdf="$intacta_pdf | $linha"; done <<< "$INTACTAS"
  [ -z "$intacta_pdf" ] && ok "linhas de referência e identificadores intactos no texto do PDF" \
    || falha "redigido (ou quebrado) no texto do PDF:$intacta_pdf"
else
  echo "  pulado PDF real: sem Chrome ou pdftotext nesta máquina (o HTML acima é a fonte do PDF)"
fi

# 12h. default de compose: a chave da Stripe escrita como default sai mascarada (o gerador
#      trata o default inteiro como literal e o rótulo do tipo não sobra: fica 4 + "…"), e o
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
[ "$(grep -cF 'STRIPE_KEY:-sk_l…}' "$TMP/default.html")" -ge 2 ] \
  && ok "o default da Stripe sai com 4 caracteres no trecho e na issue" || falha "default da Stripe sem a régua da A4"
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

# 12i. default aninhado: ${A:-${B:-valor}} saía inteiro no trecho, na issue automática e no
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

# 12j. a escotilha "redacao": false vale só para o trecho do PDF. A issue automática usava o
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

# O PDF de verdade dos casos 12i e 12j, quando a máquina tem Chrome e pdftotext: o que vem
# depois de "Issues para o GitHub" não traz valor nenhum; antes, o trecho com a escotilha traz,
# e o aninhado sem escotilha não.
if python3 -B -c 'import sys; import importlib.util as u
s = u.spec_from_file_location("g", sys.argv[1] + "/gerar-relatorio.py"); m = u.module_from_spec(s); s.loader.exec_module(m)
sys.exit(0 if m.achar_chrome() else 1)' "$SKILL/scripts" 2>/dev/null && command -v pdftotext >/dev/null; then
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
  echo "  pulado PDF real dos casos 12i e 12j: sem Chrome ou pdftotext nesta máquina"
fi

# 12d. paridade com a Fase 6: todo formato que a lista `pads` do SKILL.md reconhece sai
#      redigido do gerador. As amostras saem da própria lista, no comprimento mínimo de cada
#      alternativa, soltas e coladas em "Bearer%20" e "x_" (menos o sk- genérico, que mantém a
#      fronteira). Padrão novo na Fase 6 sem par no gerador, ou sem caso aqui, reprova.
paridade="$(python3 - "$SKILL/SKILL.md" "$SKILL/references/exemplo-findings.json" \
  "$SKILL/scripts/gerar-relatorio.py" "$TMP" <<'PY'
import ast, json, re, subprocess, sys
try:
    from re import _parser as sp, _constants as sc
except ImportError:
    import sre_parse as sp, sre_constants as sc

skill_md, exemplo, gerador, tmp = sys.argv[1:5]
m = re.search(r"^pads = (\[.*?\])\n", open(skill_md, encoding="utf-8").read(), re.S | re.M)
if not m:
    print("  FALHA lista pads da Fase 6 não encontrada no SKILL.md"); sys.exit(1)
pads = ast.literal_eval(m.group(1))

def classe(itens):
    out = []
    for op, av in itens:
        if op == sc.LITERAL: out.append(chr(av))
        elif op == sc.RANGE: out += [chr(c) for c in range(av[0], av[1] + 1)]
        else: raise ValueError(f"classe sem expansão ({op})")
    return out

contador = iter(range(10 ** 6))
def corpo(cs, n):
    """Corpo no comprimento mínimo, com marcador e etiqueta únicos: o vazamento de uma
    amostra não se confunde com o de outra que tenha o mesmo prefixo de corpo."""
    al = [c for c in cs if c.isalnum()]
    marca = next((mk for mk in ("FALSO", "falso", "0000") if set(mk) <= set(cs)), "")
    k = next(contador)
    v = marca + al[k % len(al)] + al[k // len(al) % len(al)]
    return v + al[0] * max(0, n - len(v))

corpos = []
def expandir(seq):
    """Todas as formas: classe pequena e (?:a|b) do prefixo abertas; o corpo fica marcado
    e só vira texto em materializar(), um por amostra."""
    formas = [""]
    for op, av in seq:
        if op == sc.LITERAL: ops = [chr(av)]
        elif op == sc.IN: ops = classe(av)
        elif op == sc.SUBPATTERN: ops = expandir(av[-1])
        elif op == sc.BRANCH: ops = [f for ramo in av[1] for f in expandir(ramo)]
        elif op == sc.MAX_REPEAT and av[:2] == (0, 1): ops = [""] + expandir(av[2])
        elif op == sc.MAX_REPEAT and av[0] >= 8 and len(av[2]) == 1 and av[2][0][0] == sc.IN:
            corpos.append((classe(av[2][0][1]), av[0]))
            ops = [f"\0{len(corpos) - 1}\0"]
        else: raise ValueError(f"operador sem expansão ({op})")
        formas = [f + o for f in formas for o in ops]
    return formas

def materializar(forma):
    return re.sub("\0(\\d+)\0", lambda g: corpo(*corpos[int(g.group(1))]), forma)

def alternativas(p):
    """Divide '(a|b|c)' no nível zero, sem quebrar dentro de [...] nem de (?:...)."""
    p, partes, prof, cls, atual = p[1:-1], [], 0, False, ""
    for i, c in enumerate(p):
        esc = i > 0 and p[i - 1] == "\\"
        if c == "[" and not esc: cls = True
        elif c == "]" and not esc: cls = False
        elif not cls and not esc and c == "(": prof += 1
        elif not cls and not esc and c == ")": prof -= 1
        if c == "|" and prof == 0 and not cls:
            partes.append(atual); atual = ""
        else:
            atual += c
    return partes + [atual]

# As entradas que não são lista de prefixos, pelo texto exato: mudou alguma, o caso daqui
# tem de mudar junto.
URL = r"[A-Za-z][A-Za-z0-9+.-]*://[^:/\s@]*:((?!\$\{|\$[A-Z_][A-Z0-9_]*@)[^\s@/{][^\s@/]*)@"
DEFAULT = r"\$\{[A-Za-z_][A-Za-z0-9_]*:?-([^}]+)\}"
CHAVE_PRIVADA = r"(-----BEGIN [A-Z ]*PRIVATE KEY-----)"
_KW = (r"(?i)(?:api[_-]?key|secret|token|passw(?:or)?d|pwd|senha|private[_-]?key)"
       r"[A-Za-z0-9_]*[\x27\"]?\s*[:=>]{1,2}\s*")
ATRIB_ASPAS = _KW + r"[\x27\"]([^\x27\"\n]{8,})[\x27\"]"
ATRIB = _KW + r"[\x27\"]?([^\x27\"\s,;]{8,})"
casos, falhas = [], []   # casos: (linha de código, valor que não pode sair)
for p in pads:
    if p == DEFAULT:
        for v in ("FALSOdefault" + "w" * 8, "FALSOc12"):   # acima e abaixo dos 12
            casos.append((f"JWT_SECRET: ${{JWT_SECRET:-{v}}}", v))
        v = "FALSOminusc" + "w" * 8
        casos.append((f"x: ${{db_pass:-{v}}}", v))          # nome minúsculo
        v = "FALSOsemdois" + "w" * 8
        casos.append((f"y: ${{PW-{v}}}", v))                # sem os dois-pontos
        v = "FALSOminsem" + "w" * 8
        casos.append((f"z: ${{lower_pw-{v}}}", v))          # minúsculo e sem os dois-pontos
        continue
    if p == CHAVE_PRIVADA:
        v = "MIIFALSO" + "p" * 40
        casos.append((f'k = "-----BEGIN RSA {"PRIV" + "ATE KEY"}-----{v}-----END RSA {"PRIV" + "ATE KEY"}-----"', v))
        continue
    if p == URL:
        v = "SenhaFALSO" + "u" * 8
        casos.append((f"REDIS_URL=redis://usr:{v}@host:6379/0", v)); continue
    if p in (ATRIB, ATRIB_ASPAS):
        grupo = re.match(r"\(\?i\)(\(\?:.*?\))\[", p).group(1)
        for i, kw in enumerate(expandir(sp.parse(grupo))):
            v = f"FALSO{i:02d}" + "q" * 10
            if p == ATRIB:
                casos.append((f"{kw}: {v}x", v + "x"))
                casos.append((f"{kw}_ACCESS_KEY={v}y", v + "y"))   # sufixo no nome
                continue
            casos.append((f'{kw} = "{v}"', v))
            w = f"FALSO{i:02d} com espaco " + "q" * 6              # aspas com espaço no valor
            casos.append((f"{kw} => '{w}'", w))
        continue
    if not (p.startswith("(") and p.endswith(")")) or p.startswith("(?"):
        falhas.append(f"padrão da Fase 6 sem caso no teste: {p[:60]}…"); continue
    try:
        for alt in alternativas(p):
            ctxs = ['const v = "{}";'] if alt.startswith(("sk-[", "[rs]k-[")) else \
                   ['const v = "{}";', "Authorization: Bearer%20{}", 'const x = "x_{}";']
            for forma in expandir(sp.parse(alt)):
                for ctx in ctxs:
                    s = materializar(forma)
                    if not re.fullmatch(alt, s):
                        falhas.append(f"amostra {s[:6]}… não casa a própria alternativa {alt}")
                        continue
                    casos.append((ctx.format(s), s))
    except (ValueError, IndexError) as e:
        falhas.append(f"padrão da Fase 6 sem caso no teste: {p[:60]}… ({e})")

d = json.load(open(exemplo))
linhas = [c for c, _ in casos]
d["achados"][0]["trecho"] = "\n".join(linhas)
d["issues"][0]["achados"] = ["F1"]
d["issues"][1]["markdown"] = "## Problema\n\n```\n" + "\n".join(linhas) + "\n```"
json.dump(d, open(f"{tmp}/paridade.json", "w"))
r = subprocess.run([sys.executable, gerador, f"{tmp}/paridade.json", "--out",
                    f"{tmp}/paridade.pdf", "--html-only"], capture_output=True, text=True)
if r.returncode:
    print("  FALHA gerador falhou na paridade:", r.stderr[-400:]); sys.exit(1)
html = open(f"{tmp}/paridade.html", encoding="utf-8").read()
for linha, v in casos:
    if v in html or v[4:] in html:
        falhas.append(f"sai sem redação: {linha.replace(v, v[:6] + '…')}")
for f in dict.fromkeys(falhas):
    print("  FALHA paridade Fase 6:", f)
if not falhas:
    print(f"  ok   paridade Fase 6: {len(casos)} amostras de {len(pads)} padrões saem redigidas")
PY
)"
echo "$paridade"
case "$paridade" in *"ok   paridade"*) ;; *) falhas=$((falhas + 1)) ;; esac

# 12b. issue com markdown escrito à mão passa pela mesma máscara — é o mesmo
#      GitHub, e quem escreve markdown custom é quem colou o trecho na unha
gerar_variante 'd["issues"][0]["markdown"] = "## Problema\n\n```\nconst k = \"sk-proj-AbCdEf0123456789XyZq\";\n```"' md
grep -q 'sk-proj-AbCdEf0123456789XyZq' "$TMP/md.html" \
  && falha "markdown custom da issue escapou da máscara" \
  || ok "markdown custom da issue também é mascarado"

# 12f. valor colado pelo auditor em qualquer campo de texto do achado ou da issue sai redigido.
#      Antes só o trecho e o markdown passavam pela máscara: titulo, por_que, impacto,
#      correcao, bloqueio, plano_validacao, condicoes, caminho, problema e criterios_aceite iam em
#      claro para o PDF e para a issue. Sem escotilha: o "redacao": false (ligado aqui em todos os
#      achados) vale só para o trecho.
gerar_variante 'tk = lambda c: "gh" + "p_FALSO" + c.replace("_", "") + "Z" * 24
for a in d["achados"]:
    a["redacao"] = False
    for c in ("titulo", "por_que", "impacto", "correcao", "bloqueio", "motivo", "fonte"):
        a[c] = f"{c} com o valor {tk(c)} colado"
    a["condicoes"] = [{"tipo": "rede", "descricao": "cond " + tk("cond")}]
    a["plano_validacao"] = {"local": "loc " + tk("local"), "dono": "dono " + tk("dono")}
    a["caminho"] = [{"tipo": "entrada", "arquivo": "x.ts", "linha": 1, "descricao": "passo " + tk("passo")}]
for i in d["issues"]:
    i.pop("markdown", None)
    for c in ("titulo", "problema", "impacto", "correcao"):
        i[c] = f"{c} {tk(c)}"
    i["criterios_aceite"] = ["crit " + tk("crit")]' campos
[ -s "$TMP/campos.html" ] || { falha "gerador falhou com segredo nos campos de texto: $(tail -3 "$TMP/campos.log")"; }
grep -q 'FALSO' "$TMP/campos.html" \
  && falha "campo de texto em claro: $(grep -o '[a-z]*FALSO[A-Za-z]*' "$TMP/campos.html" | sort -u | tr '\n' ' ')" \
  || ok "nenhum campo de texto do achado ou da issue sai com o valor"
for rot in 'titulo com o valor ghp_… [token do GitHub redigido] colado' \
           'por_que com o valor ghp_… [token do GitHub redigido] colado' \
           'bloqueio com o valor ghp_… [token do GitHub redigido] colado' \
           'passo ghp_… [token do GitHub redigido]' 'crit ghp_… [token do GitHub redigido]' \
           'problema ghp_… [token do GitHub redigido]'; do
  grep -qF "$rot" "$TMP/campos.html" && ok "campo mascarado e ainda impresso: ${rot%% *}" \
    || falha "campo sumiu ou saiu sem o rótulo: $rot"
done
grep -q 'Redacao: ' "$TMP/campos.log" && ok "a contagem de redação inclui os campos de texto" \
  || falha "stdout não contou a redação dos campos"

# 12g. as listas de texto livre fora de achados e issues: pontos_fortes (inclusive a evidencia,
#      que ali é texto e não o nível), pontos_fracos, hardening (string solta e objeto) e
#      recomendacoes. Antes iam em claro para o PDF.
gerar_variante 'tk = lambda c: "gh" + "p_FALSO" + c + "Z" * 24
d["pontos_fortes"] = [{"categoria": "A3", "titulo": "forte " + tk("forte"),
                       "descricao": "fdesc " + tk("fdesc"), "evidencia": "fevid " + tk("fevid")}]
d["pontos_fracos"] = [{"titulo": "fraco " + tk("fraco"), "descricao": "wdesc " + tk("wdesc")}]
d["hardening"] = ["hsolto " + tk("hsolto"),
                  {"titulo": "htit " + tk("htit"), "descricao": "hdesc " + tk("hdesc"), "arquivo": "x.ts:1"}]
d["recomendacoes"] = [{"prioridade": "P1", "texto": "rec " + tk("rec"), "achados": ["F1"]}]' livres
[ -s "$TMP/livres.html" ] || falha "gerador falhou com segredo nas listas livres: $(tail -3 "$TMP/livres.log")"
grep -q 'FALSO' "$TMP/livres.html" \
  && falha "lista livre em claro: $(grep -o '[a-z]*FALSO[A-Za-z]*' "$TMP/livres.html" | sort -u | tr '\n' ' ')" \
  || ok "nenhuma lista livre sai com o valor"
for rot in forte fdesc fevid fraco wdesc hsolto htit hdesc rec; do
  grep -qF "$rot ghp_… [token do GitHub redigido]" "$TMP/livres.html" \
    && ok "lista livre mascarada e ainda impressa: $rot" || falha "campo $rot sumiu ou saiu sem o rótulo"
done
base=$(sed -n 's/^Redacao: \([0-9]*\) .*/\1/p' "$TMP/log.txt"); base=${base:-0}
grep -q "Redacao: $((base + 9)) " "$TMP/livres.log" \
  && ok "a contagem de redação inclui as 9 das listas livres ($base do exemplo + 9)" \
  || falha "contagem de redação das listas livres (esperado $((base + 9))): $(grep Redacao "$TMP/livres.log")"
grep -q 'x.ts:1' "$TMP/livres.html" && ok "arquivo do hardening continua intacto" \
  || falha "arquivo do hardening sumiu"

# 13. a escotilha "redacao": false é decisão de quem escreveu o achado e vale só para o
#     trecho do PDF. A issue vai para o GitHub e não tem escotilha: o default sai mascarado.
[ "$(grep -c 'supersecret-change-me' "$HTML")" -eq 1 ] \
  && grep -qF '<pre class="codigo">JWT_SECRET: ${JWT_SECRET:-supersecret-change-me}</pre>' "$HTML" \
  && ok 'escotilha "redacao": false preserva a evidência no trecho, e só nele' \
  || falha "o default com escotilha saiu fora do trecho, ou sumiu dele: $(grep -c 'supersecret-change-me' "$HTML") ocorrência(s)"
grep -qF 'JWT_SECRET: ${JWT_SECRET:-supe…}' "$HTML" \
  && ok "a issue do achado com escotilha sai com o default mascarado" \
  || falha "a issue herdou a escotilha do trecho e levou o default em claro"

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
