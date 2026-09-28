#!/usr/bin/env bash
# A varredura de chaves expostas (A4 da auditoria-seguranca) não imprime o segredo nem roda build.
#
# O bloco da A4 é o que o modelo roda como está escrito, e a saída entra na conversa: vai para o
# transcript e costuma acabar colada no relatório e na issue. Até a 0.41 o `grep -rEo` do
# bundle devolvia a chave inteira, e os greps de atribuição e de default em config devolviam a
# linha com o valor. Agora cada achado sai como arquivo:linha e um prefixo curto: valor de até
# 12 caracteres sai só como `…`, valor maior com os 4 primeiros + `…`. O tipo vai em rótulo
# separado: o JWT do bundle sai com o `role` do payload, que separa a anon key da service_role.
# O default é procurado nos nomes do Compose v1 e v2 (docker-compose*.y*ml, compose.y*ml). O
# bundle reconhece sk-proj-, sk-ant- e as chaves da Stripe (sk_/rk_ live/test), cada uma com o
# tipo no rótulo. Byte fora de UTF-8 na linha não derruba nem cala a varredura.
#
# A Fase 6 mandava copiar o trecho com `sed -n`, e para achado de segredo a linha trazia o
# valor para a conversa. O bloco "# trecho de achado de segredo" corta a linha no valor, e o
# teste prova que o resultado passa no --verificar do gerador contra o arquivo real.
#
# E o bloco rodava `npm run build` quando faltava `dist/`: script do repo auditado executando na
# máquina de quem audita, gravando fora de docs/security-audit/. Sem build no disco, o bloco não
# chama npm: o build vira pergunta, com o comando pronto e o que ele grava, e o bundle que ficou
# sem varrer aparece na `cobertura[]` da A4.
#
# Porte de volta do formato do kit do time: defaults, role do JWT e binário no bundle.
# O teste roda o bloco do SKILL.md, sem cópia, contra repos de mentira com segredos falsos
# montados na hora, e sem gitleaks no PATH (a linha dele já usa --redact).
#
# Uso: bash tests/test-auditoria-a4-mascara.sh [caminho-do-SKILL.md]
set -uo pipefail
SKILL="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/auditoria-seguranca/SKILL.md}"
[ -f "$SKILL" ] || { echo "SKILL.md não encontrado: $SKILL"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/a4-mascara.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
ok()      { printf '  ok    %s\n' "$1"; }
falha()   { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
tem()     { case "$2" in *"$1"*) ok "$3" ;; *) falha "$3 (não achei '$1' em: $2)" ;; esac; }
nao_tem() { case "$2" in *"$1"*) falha "$3 (achei '$1')" ;; *) ok "$3" ;; esac; }

# O primeiro bloco ```bash depois do título da A4.
awk '/^## A4 /{a=1} a && /^```bash/{b=1; next} b && /^```/{exit} b' "$SKILL" > "$TMP/a4.sh"
[ -s "$TMP/a4.sh" ] || { echo "bloco bash da A4 não encontrado em $SKILL"; exit 2; }

# Segredos falsos montados aqui: literal de segredo no fonte faz scanner reprovar o próprio teste.
b64url() { printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '=\n'; }
SK="sk-FALSO$(printf 'a%.0s' $(seq 1 30))"
JWT="$(b64url '{"alg":"HS256","typ":"JWT"}').$(b64url '{"role":"service_role","iss":"supabase"}').$(printf 's%.0s' $(seq 1 30))"
CFG="valorFALSO$(printf '1%.0s' $(seq 1 10))"
DEF="padraoFALSO$(printf '2%.0s' $(seq 1 10))"
CURTO="s3cr$(printf 'e%.0s' 1)t"   # default de 6 caracteres: o corte dos "6 primeiros" o mostrava inteiro
# Os limites da política: 9 e 12 saem só como …, 13 sai com os 4 primeiros.
V9="n4pW$(printf 'y%.0s' $(seq 1 5))"
V12="r7tX$(printf 'w%.0s' $(seq 1 8))"
V13="k9mQ$(printf 'z%.0s' $(seq 1 9))"
VS3="q2wE$(printf 'x%.0s' $(seq 1 9))"   # nome de variável com dígito: ${S3_SECRET:-…}
# Chaves com prefixo de fornecedor, montadas por concatenação: o prefixo inteiro num literal
# é o que a push protection do GitHub reconhece.
rep() { printf "$1%.0s" $(seq 1 "$2"); }
SKP="sk-""proj-FALSO$(rep b 30)"
SKL="sk_""live_FALSO$(rep c 24)"
SKT="sk_""test_FALSO$(rep d 24)"
RKL="rk_""live_FALSO$(rep e 24)"
SKA="sk-""ant-api03-FALSO$(rep f 40)"

R="$TMP/com-build"; mkdir -p "$R/dist" "$R/.next/static"
printf 'const a=1;\nconst k="%s";\nconst j="%s";\n' "$SK" "$JWT" > "$R/dist/app.js"
# binário com a chave dentro (o .asar do Electron): o grep BSD imprimia "Binary file … matches"
# no stdout, e o python do bloco quebrava levando junto os achados dos outros arquivos
printf 'ASAR\000\000\000cabecalho\nconst k="%s";\n' "$SK" > "$R/dist/app.asar"
printf 'var t="%s";\n' "$JWT" > "$R/.next/static/chunk.js"
printf 'const p="%s";\nconst s="%s";\nconst t="%s";\nconst r="%s";\nconst a="%s";\n' "$SKP" "$SKL" "$SKT" "$RKL" "$SKA" > "$R/dist/chaves.js"
printf 'nome: app\napi_key: "%s"\nsecret: "%s"\npassword: "%s"\ntoken: "%s"\n' "$CFG" "$V9" "$V12" "$V13" > "$R/config.yml"
printf 'services:\n  api:\n    environment:\n      JWT_SECRET: ${JWT_SECRET:-%s}\n      DB_PASS: ${DB_PASS:-%s}\n      DNOVE: ${DNOVE:-%s}\n      DDOZE: ${DDOZE:-%s}\n      DTREZE: ${DTREZE:-%s}\n' \
  "$DEF" "$CURTO" "$V9" "$V12" "$V13" > "$R/docker-compose.yml"
# Compose v2: compose.yaml é o nome padrão, e o .yaml vale também para o docker-compose
printf 'services:\n  db:\n    environment:\n      ADMIN_PASS: ${ADMIN_PASS:-%s}\n' "$DEF" > "$R/compose.yaml"
printf 'services:\n  db:\n    environment:\n      PROD_PASS: ${PROD_PASS:-%s}\n      S3_SECRET: ${S3_SECRET:-%s}\n' "$DEF" "$VS3" > "$R/docker-compose.prod.yaml"

saida=$(cd "$R" && PATH=/usr/bin:/bin bash "$TMP/a4.sh" 2>&1)

echo "== o segredo não sai inteiro =="
nao_tem "$SK"  "$saida" "chave sk- do bundle mascarada"
nao_tem "$JWT" "$saida" "JWT do bundle mascarado"
nao_tem "$CFG" "$saida" "valor do api_key em config mascarado"
nao_tem "$DEF" "$saida" "default do compose mascarado"
nao_tem ":-$CURTO" "$saida" "default curto (6 caracteres) também mascarado"   # sem o }: "valor…}" também vaza

echo "== o achado continua achável: arquivo:linha, no máximo 4 caracteres e o tipo =="
tem "dist/app.js:2:sk-F…"             "$saida" "bundle: dist/app.js:2 e sk-F…"
nao_tem ":sk-FA"                      "$saida" "bundle: não passa dos 4 primeiros da chave"
tem "dist/app.js:3:eyJh…"             "$saida" "bundle: dist/app.js:3 e eyJh…"
tem ".next/static/chunk.js:1:eyJh…"   "$saida" "bundle: .next/static/chunk.js:1 e eyJh…"
nao_tem "eyJhb"                       "$saida" "bundle: não passa dos 4 primeiros do JWT"
tem "dist/app.asar:2:sk-F…"           "$saida" "bundle: a chave dentro do binário vira achado"
nao_tem "Traceback"                   "$saida" "bundle: binário não quebra o bloco"
tem "role=service_role"               "$saida" "bundle: o JWT sai com o role do payload"
tem "config.yml:2:api_key: \"valo…"   "$saida" "config: 20 caracteres saem com os 4 primeiros"
nao_tem "\"valor"                     "$saida" "config: não passa dos 4 primeiros"
tem "config.yml:3:secret: \"…"        "$saida" "config: 9 caracteres saem só como …"
tem "config.yml:4:password: \"…"      "$saida" "config: 12 caracteres saem só como …"
tem "config.yml:5:token: \"k9mQ…"     "$saida" "config: 13 caracteres saem com os 4 primeiros"
tem "docker-compose.yml:4:"           "$saida" "default: docker-compose.yml:4"
tem "JWT_SECRET:-padr…}"              "$saida" "default: 21 caracteres saem com os 4 primeiros"
nao_tem ":-padra"                     "$saida" "default: não passa dos 4 primeiros"
tem "DB_PASS:-…}"                     "$saida" "default curto: 6 caracteres saem só como …"
tem "DNOVE:-…}"                       "$saida" "default: 9 caracteres saem só como …"
tem "DDOZE:-…}"                       "$saida" "default: 12 caracteres saem só como …"
tem "DTREZE:-k9mQ…}"                  "$saida" "default: 13 caracteres saem com os 4 primeiros"
nao_tem "n4pW"                        "$saida" "9 caracteres: nenhum caractere do valor sai"
nao_tem "r7tX"                        "$saida" "12 caracteres: nenhum caractere do valor sai"
nao_tem "k9mQz"                       "$saida" "13 caracteres: não passa dos 4 primeiros"
tem "S3_SECRET:-q2wE…}"               "$saida" "default: nome de variável com dígito também é achado"
nao_tem "q2wEx"                       "$saida" "default com dígito no nome: não passa dos 4 primeiros"
tem "compose.yaml:4:      ADMIN_PASS: \${ADMIN_PASS:-padr…}" "$saida" "Compose v2: compose.yaml é varrido"
tem "docker-compose.prod.yaml:4:"     "$saida" "Compose: docker-compose*.yaml é varrido"

echo "== bundle: sk-proj-, sk-ant- e as chaves da Stripe viram achado, com o tipo certo =="
for v in "$SKP" "$SKL" "$SKT" "$RKL" "$SKA"; do nao_tem "$v" "$saida" "chave ${v:0:3}… do bundle mascarada"; done
linha() { printf '%s\n' "$saida" | grep -F "$1" | head -1; }
tem "chave de projeto OpenAI"         "$(linha 'dist/chaves.js:1:sk-p…')" "sk-proj-: dist/chaves.js:1, 4 caracteres e o tipo"
tem "Stripe sk_""live_"               "$(linha 'dist/chaves.js:2:sk_l…')" "sk_live_: dist/chaves.js:2, 4 caracteres e o tipo"
tem "Stripe sk_""test_"               "$(linha 'dist/chaves.js:3:sk_t…')" "sk_test_: dist/chaves.js:3, 4 caracteres e o tipo"
tem "Stripe rk_""live_"               "$(linha 'dist/chaves.js:4:rk_l…')" "rk_live_: dist/chaves.js:4, 4 caracteres e o tipo"
# sk-ant-api03-…: o hífen depois de "ant" quebrava o sk-[A-Za-z0-9]{16,}
tem "chave Anthropic"                 "$(linha 'dist/chaves.js:5:sk-a…')" "sk-ant-: dist/chaves.js:5, 4 caracteres e o tipo"
for n in 2 3 4; do nao_tem "JWT" "$(linha "dist/chaves.js:$n:")" "chave da Stripe na linha $n não sai como JWT"; done

echo "== byte fora de UTF-8 na linha não derruba a varredura =="
# Um comentário em Latin-1 na mesma linha do default: o grep do Linux, sem -a, cala a linha
# com byte inválido, e o default dela nem chega à máscara. O sed do macOS em locale UTF-8
# aborta com "illegal byte sequence" e leva junto os achados seguintes. PYTHONIOENCODING
# fixa a leitura estrita do python em qualquer locale (o C.UTF-8 do CI a relaxa).
L="$TMP/latin1"; mkdir -p "$L/dist"
printf 'services:\n  a:\n    environment:\n      DB_PASSWORD: ${DB_PASSWORD:-senhaValida12345} # caf\351\n      Z: ${Z:-outroDefaultDepois1}\n' > "$L/compose.yaml"
printf 'password: "valor\351ruim12345"\ntoken: "tokenDepoisDoByte99" # caf\351\nsecret: "segredoDepoisDoByte"\n' > "$L/cfg.yml"
printf '/* caf\351 */ const k="%s";\n' "$SK" > "$L/dist/app.js"
# O locale UTF-8 que a máquina tem: sem ele a glibc cai para C e o cenário passa até no código antigo.
U=$(locale -a 2>/dev/null | grep -iE '^(en_US|C)\.utf-?8$' | head -1)
sl=$(cd "$L" && LC_ALL="${U:-en_US.UTF-8}" PYTHONIOENCODING=utf-8:strict PATH=/usr/bin:/bin bash "$TMP/a4.sh" 2>&1)
nao_tem "Traceback"                   "$sl" "byte fora de UTF-8: sem Traceback"
nao_tem "illegal byte sequence"       "$sl" "byte fora de UTF-8: o sed não aborta"
tem "compose.yaml:4:"                 "$sl" "byte fora de UTF-8: a linha do byte continua achada"
tem "compose.yaml:5:"                 "$sl" "byte fora de UTF-8: o default seguinte não some"
tem "cfg.yml:1:"                      "$sl" "byte fora de UTF-8 dentro do valor: a config continua achada"
nao_tem "ruim12345"                   "$sl" "byte fora de UTF-8 dentro do valor: o valor continua mascarado"
tem "cfg.yml:2:"                      "$sl" "byte fora de UTF-8: a config com byte continua achada"
tem "cfg.yml:3:"                      "$sl" "byte fora de UTF-8: a config seguinte não some"
tem "dist/app.js:1:sk-F…"             "$sl" "byte fora de UTF-8: a chave do bundle continua achada"
nao_tem "senhaValida12345"            "$sl" "byte fora de UTF-8: o default continua mascarado"
nao_tem "tokenDepoisDoByte99"         "$sl" "byte fora de UTF-8: a config continua mascarada"
nao_tem "$SK"                         "$sl" "byte fora de UTF-8: a chave do bundle continua mascarada"

echo "== Fase 6: o trecho de achado de segredo sai cortado no valor e passa no --verificar =="
# O bloco da Fase 6 marcado "# trecho de achado de segredo", com <linha> e <arquivo> trocados.
awk '/^## Fase 6 /{a=1} a && /^```bash/{b=1; buf=""; next} b && /^```/{if (buf ~ /# trecho de achado de segredo/) {printf "%s", buf; exit} b=0; next} b {buf = buf $0 "\n"}' \
  "$SKILL" > "$TMP/fase6.sh"
trecho() { # trecho <arquivo> <linha> — roda o bloco da Fase 6; deixa a saída em $T6 e o exit em $X6
  sed -e "s|<arquivo>|$1|g" -e "s|<linha>|$2|g" "$TMP/fase6.sh" > "$TMP/fase6-run.sh"
  T6=$(cd "$R" && PYTHONIOENCODING=utf-8:strict PATH=/usr/bin:/bin bash "$TMP/fase6-run.sh" 2>/dev/null); X6=$?
}
if [ ! -s "$TMP/fase6.sh" ]; then
  falha "bloco '# trecho de achado de segredo' não encontrado na Fase 6"
else
  trecho config.yml 2
  nao_tem "$CFG" "$T6" "config.yml:2: o valor não sai"
  tem "api_key: \"valo  // valor mascarado" "$T6" "config.yml:2: cortado nos 4 caracteres, com a anotação"
  trecho config.yml 4
  nao_tem "$V12" "$T6" "valor de 12: não sai"
  tem "password: \"  // valor mascarado" "$T6" "valor de 12: nenhum caractere"
  trecho dist/chaves.js 1
  nao_tem "$SKP" "$T6" "sk-proj-: não sai"
  tem "sk-p  // valor mascarado" "$T6" "sk-proj-: 4 caracteres"
  trecho dist/chaves.js 2
  nao_tem "$SKL" "$T6" "sk_live_: não sai"
  tem "sk_l  // valor mascarado" "$T6" "sk_live_: 4 caracteres"
  trecho dist/chaves.js 5
  nao_tem "$SKA" "$T6" "sk-ant-: não sai"
  tem "sk-a  // valor mascarado" "$T6" "sk-ant-: 4 caracteres"
  trecho docker-compose.yml 4
  nao_tem ":-$DEF" "$T6" "default: nada do valor depois do :-"
  cp "$L/compose.yaml" "$R/latin1.yaml"
  trecho latin1.yaml 4
  [ "$X6" -eq 0 ] && ok "byte fora de UTF-8 na linha: o trecho sai (exit $X6)" || falha "byte fora de UTF-8 derrubou o bloco da Fase 6 (exit $X6)"
  nao_tem "senhaValida12345" "$T6" "byte fora de UTF-8: o valor não sai no trecho"
  trecho config.yml 1
  [ "$X6" -ne 0 ] && [ -z "$T6" ] && ok "linha sem segredo reconhecido: não imprime nada e sai ≠ 0" \
    || falha "linha sem segredo reconhecido saiu $X6 com: $T6"

  # Até 60 caracteres antes do corte saíam crus: um token que o bloco não reconhecia, na mesma
  # linha e antes da chave reconhecida, ia inteiro para o trecho (e daí para o PDF e a issue).
  # As três linhas da revisão da 0.43.1, mais os outros prefixos de fornecedor.
  GHP="gh""p_FALSO$(rep Z 32)"; GHO="gh""o_FALSO$(rep Y 32)"; GPAT="github""_pat_FALSO$(rep X 40)"
  XOX="xo""xb-FALSO$(rep W 26)"; GLP="gl""pat-FALSO$(rep V 20)"; AWS="AK""IAFALSO$(rep Q 11)"
  WHS="wh""sec_FALSO$(rep U 28)"; SENHA="SenhaFalsa$(rep 9 6)"
  printf 'const gh="%s", k="%s";\n' "$GHP" "$SKP" > "$R/dist/revisao.js"
  printf 'const a="%s"; const b="%s";\n' "$XOX" "$SKL" >> "$R/dist/revisao.js"
  printf 'DATABASE_URL=postgres://u:%s@h/db API_KEY=%s\n' "$SENHA" "$SKL" >> "$R/dist/revisao.js"
  printf 'x = ["%s", "%s", "%s", "%s", "%s", "%s"]\n' "$GHO" "$GPAT" "$GLP" "$AWS" "$WHS" "$SKL" >> "$R/dist/revisao.js"
  GER="$(dirname "$SKILL")/scripts/gerar-relatorio.py"
  EXE="$(dirname "$SKILL")/references/exemplo-findings.json"
  verifica_trecho() { # <arquivo> <linha> — o trecho em $T6 passa no --verificar contra o arquivo real
    T6="$T6" python3 - "$EXE" "$TMP/f6.json" "$1" "$2" <<'PYF'
import json, os, sys
d = json.load(open(sys.argv[1]))
a = d["achados"][0]
a.update(categoria="A4", arquivo=sys.argv[3], linhas=sys.argv[4], trecho=os.environ["T6"])
d["achados"] = [a]
d["issues"] = []
d["recomendacoes"] = []
json.dump(d, open(sys.argv[2], "w"), ensure_ascii=False)
PYF
    python3 "$GER" "$TMP/f6.json" --verificar --raiz "$R" >/dev/null 2>&1
  }
  for n in 1 2 3 4; do
    trecho dist/revisao.js "$n"
    [ "$X6" -eq 0 ] && [ -n "$T6" ] || falha "revisao.js:$n: o bloco não achou segredo (exit $X6)"
    vazou=""
    for v in "$GHP" "$SKP" "$XOX" "$SKL" "$SENHA" "$GHO" "$GPAT" "$GLP" "$AWS" "$WHS"; do
      case "$T6" in *"$v"*) vazou="$vazou ${v:0:6}";; esac
    done
    [ -z "$vazou" ] && ok "revisao.js:$n: nenhum valor sai inteiro" || falha "revisao.js:$n: valor inteiro no trecho:$vazou ($T6)"
    verifica_trecho dist/revisao.js "$n" && ok "revisao.js:$n: o --verificar aceita o trecho" \
      || falha "revisao.js:$n: o --verificar recusou: $T6"
  done
  trecho dist/revisao.js 3
  tem "postgres://u:" "$T6" "senha em URL: o corte fica na senha, depois do usuário"
  nao_tem "SenhaF" "$T6" "senha em URL: não passa dos 4 primeiros"
  printf 'u = "postgres://u:${DB_PASSWORD}@h/db"\n' > "$R/ref-url.txt"
  trecho ref-url.txt 1
  [ "$X6" -ne 0 ] && ok "senha em URL que é \${VAR}: referência, não achado" || falha "\${VAR} na URL virou achado: $T6"

  # Todo prefixo que a Fase 6 reconhece sai redigido pelo gerador, também colado em %20 e em _
  # (o \b dos prefixos específicos deixava passar Bearer%20ghp_… e x_xoxs-…). Cada amostra
  # passa antes pelo bloco da Fase 6: amostra que ele não reconhece não prova nada aqui.
  B64='{"alg":"HS256"}'; JWT2="$(b64url "$B64").$(b64url '{"role":"anon"}').$(rep t 30)"
  AMOSTRAS=("sk-""proj-FALSO$(rep b 30)" "sk-""ant-api03-FALSO$(rep f 30)" "sk-FALSO$(rep a 30)"
    "sk_""live_FALSO$(rep c 24)" "rk_""test_FALSO$(rep e 24)" "$JWT2" "sb""p_$(rep 0 30)" "AK""IAFALSO$(rep Q 11)"
    "gh""p_FALSO$(rep Z 32)" "gh""o_FALSO$(rep Z 32)" "gh""u_FALSO$(rep Z 32)" "gh""s_FALSO$(rep Z 32)"
    "gh""r_FALSO$(rep Z 32)" "github""_pat_FALSO$(rep X 40)" "xo""xa-FALSO$(rep W 26)" "xo""xb-FALSO$(rep W 26)"
    "xo""xp-FALSO$(rep W 26)" "xo""xr-FALSO$(rep W 26)" "xo""xs-FALSO$(rep W 26)" "gl""pat-FALSO$(rep V 20)"
    "wh""sec_FALSO$(rep U 28)")
  : > "$R/prefixos.txt"
  for v in "${AMOSTRAS[@]}"; do printf 'k = "%s"\n' "$v" >> "$R/prefixos.txt"; done
  n=0; fora=""
  for v in "${AMOSTRAS[@]}"; do n=$((n+1)); trecho prefixos.txt "$n"; [ "$X6" -eq 0 ] || fora="$fora ${v:0:6}"; done
  [ -z "$fora" ] && ok "as ${#AMOSTRAS[@]} amostras são prefixos que a Fase 6 reconhece" || falha "a Fase 6 não reconhece:$fora"
  AMOSTRAS+=("postgres://u:SenhaFalsa$(rep 8 6)@h/db")
  # o sk- genérico fica com a fronteira (senão "task-list-…" vira chave): só no contexto puro.
  # Função, e não o laço dentro do $(…): no bash 3.2 do macOS o ")" do case fecha a substituição.
  amostras_txt() {
    local v
    for v in "${AMOSTRAS[@]}"; do
      printf 'a = "%s"\n' "$v"
      case "$v" in
        sk-FALSO*) ;;
        *) printf 'b = "Bearer%%20%s"\nc = x_%s\n' "$v" "$v" ;;
      esac
    done
  }
  AMOSTRAS_TXT="$(amostras_txt)" \
  python3 - "$EXE" "$TMP/pref.json" <<'PYP'
import json, os, sys
d = json.load(open(sys.argv[1]))
d["achados"][0]["trecho"] = os.environ["AMOSTRAS_TXT"]
d["issues"][0]["achados"] = [d["achados"][0]["id"]]
d["issues"][1]["markdown"] = "```\n" + os.environ["AMOSTRAS_TXT"] + "\n```"
json.dump(d, open(sys.argv[2], "w"))
PYP
  python3 "$GER" "$TMP/pref.json" --out "$TMP/pref.pdf" --html-only >/dev/null 2>&1 || falha "gerador falhou com as amostras"
  [ "$(grep -c 'Bearer%20' "$TMP/pref.json")" -ge 1 ] && [ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["achados"][0]["trecho"].splitlines()))' "$TMP/pref.json")" -ge 60 ] \
    && ok "as amostras entram no trecho nos três contextos" || falha "as amostras não chegaram ao trecho do gerador"
  vazou=""
  for v in "${AMOSTRAS[@]}"; do
    s="${v#postgres://u:}"; s="${s%@h/db}"
    grep -qF "$s" "$TMP/pref.html" && vazou="$vazou ${v:0:6}"
  done
  [ -z "$vazou" ] && ok "gerador: todo prefixo da Fase 6 sai redigido, puro, depois de %20 e depois de _ (sk- genérico só puro)" \
    || falha "gerador deixou passar inteiro:$vazou"

  # o trecho mascarado passa no --verificar do gerador, contra o arquivo de verdade
  GER="$(dirname "$SKILL")/scripts/gerar-relatorio.py"
  EXE="$(dirname "$SKILL")/references/exemplo-findings.json"
  trecho config.yml 2
  T6="$T6" python3 - "$EXE" "$TMP/f6.json" <<'PYF'
import json, os, sys
d = json.load(open(sys.argv[1]))
a = d["achados"][0]
a.update(categoria="A4", arquivo="config.yml", linhas="2", trecho=os.environ["T6"])
d["achados"] = [a]
d["issues"] = []
d["recomendacoes"] = []
json.dump(d, open(sys.argv[2], "w"), ensure_ascii=False)
PYF
  v=$(python3 "$GER" "$TMP/f6.json" --verificar --raiz "$R" 2>&1); xv=$?
  [ "$xv" -eq 0 ] && ok "--verificar aceita o trecho mascarado" || falha "--verificar recusou o trecho mascarado: $v"
fi
# Nenhum `sed -n` da skill copia linha para a conversa sem passar pela máscara.
sem=$(grep -n 'sed -n' "$SKILL" | grep -v '| python3' | grep -vi 'segredo')
[ -z "$sem" ] && ok "todo sed -n da skill passa pela máscara ou exclui segredo" \
  || falha "sed -n que copia linha sem máscara: $sem"

echo "== sem build no disco, o bloco não roda o build do repo auditado =="
# npm falso no PATH: se o bloco chamar npm, a marca aparece na pasta do repo
S="$TMP/sem-build"; mkdir -p "$S" "$TMP/bin"
printf '{"name":"alvo","scripts":{"build":"echo build"}}\n' > "$S/package.json"
printf '#!/bin/sh\ntouch "$PWD/NPM_RODOU"\n' > "$TMP/bin/npm"; chmod +x "$TMP/bin/npm"
(cd "$S" && PATH="$TMP/bin:/usr/bin:/bin" bash "$TMP/a4.sh" >/dev/null 2>&1)
[ ! -e "$S/NPM_RODOU" ] && ok "npm não foi chamado" \
  || falha "o bloco chamou npm no repo auditado (build executa script dele e grava fora de docs/security-audit/)"

echo "== sem build, a A4 pergunta com o comando pronto e declara a cobertura =="
secao=$(awk '/^## A4 /{a=1; next} a && /^## /{exit} a' "$SKILL")
tem 'Posso rodar `npm run build`'   "$secao" "o build é pergunta, com o comando pronto"
tem 'grava `dist/`'                  "$secao" "a pergunta diz o que o build grava"
tem '`npm ci`'                       "$secao" "sem node_modules, a pergunta cita o npm ci e o que ele roda"
tem '"categoria": "A4"'              "$secao" "o bundle sem varrer entra na cobertura[] da A4"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
