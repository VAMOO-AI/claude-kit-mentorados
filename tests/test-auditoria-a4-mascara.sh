#!/usr/bin/env bash
# A varredura de chaves expostas (A4 da auditoria-seguranca) não imprime o segredo nem roda build.
#
# O bloco da A4 é o que o modelo roda como está escrito, e a saída entra na conversa: vai para o
# transcript e costuma acabar colada no relatório e na issue. Até a 0.41 o `grep -rEo` do
# bundle devolvia a chave inteira, e os greps de atribuição e de default em config devolviam a
# linha com o valor. Agora cada achado sai como arquivo:linha e um prefixo curto: valor de até
# 12 caracteres sai só como `…`, valor maior com os 4 primeiros + `…`. O tipo vai em rótulo
# separado: o JWT do bundle sai com o `role` do payload, que separa a anon key da service_role.
# O default é procurado nos nomes do Compose v1 e v2 (docker-compose*.y*ml, compose.y*ml).
#
# E o bloco rodava `npm run build` quando faltava `dist/`: script do repo auditado executando na
# máquina de quem audita, gravando fora de docs/security-audit/. Sem build no disco, o bloco não
# chama npm.
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

R="$TMP/com-build"; mkdir -p "$R/dist" "$R/.next/static"
printf 'const a=1;\nconst k="%s";\nconst j="%s";\n' "$SK" "$JWT" > "$R/dist/app.js"
# binário com a chave dentro (o .asar do Electron): o grep BSD imprimia "Binary file … matches"
# no stdout, e o python do bloco quebrava levando junto os achados dos outros arquivos
printf 'ASAR\000\000\000cabecalho\nconst k="%s";\n' "$SK" > "$R/dist/app.asar"
printf 'var t="%s";\n' "$JWT" > "$R/.next/static/chunk.js"
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

echo "== sem build no disco, o bloco não roda o build do repo auditado =="
# npm falso no PATH: se o bloco chamar npm, a marca aparece na pasta do repo
S="$TMP/sem-build"; mkdir -p "$S" "$TMP/bin"
printf '{"name":"alvo","scripts":{"build":"echo build"}}\n' > "$S/package.json"
printf '#!/bin/sh\ntouch "$PWD/NPM_RODOU"\n' > "$TMP/bin/npm"; chmod +x "$TMP/bin/npm"
(cd "$S" && PATH="$TMP/bin:/usr/bin:/bin" bash "$TMP/a4.sh" >/dev/null 2>&1)
[ ! -e "$S/NPM_RODOU" ] && ok "npm não foi chamado" \
  || falha "o bloco chamou npm no repo auditado (build executa script dele e grava fora de docs/security-audit/)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
