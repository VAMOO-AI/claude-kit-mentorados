#!/usr/bin/env bash
# A varredura de chaves expostas (A4 da skill auditoria-seguranca) não imprime o segredo.
#
# O bloco da A4 é o que o modelo roda como está escrito, e a saída dele entra na conversa:
# vai para o transcript e costuma acabar colada no relatório e na issue. Até a 0.41 o
# `grep -rEo` do bundle devolvia a chave inteira (`dist/app.js:sk-...`) e o grep de
# atribuição em config devolvia a linha com o valor. Agora cada achado sai como
# arquivo:linha e os 6 primeiros caracteres do valor, o suficiente para achar e julgar.
#
# O teste roda o bloco do SKILL.md, sem cópia, contra um repo de mentira com segredos
# falsos, e sem gitleaks no PATH (a linha dele já usa --redact).
#
# Uso: bash tests/test-auditoria-a4-mascara.sh [caminho-do-SKILL.md]
set -uo pipefail
SKILL="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/auditoria-seguranca/SKILL.md}"
[ -f "$SKILL" ] || { echo "SKILL.md não encontrado: $SKILL"; exit 2; }

falhas=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
tem()     { case "$2" in *"$1"*) ok "$3" ;; *) falha "$3 (não achei '$1' em: $2)" ;; esac; }
nao_tem() { case "$2" in *"$1"*) falha "$3 (achei '$1')" ;; *) ok "$3" ;; esac; }

# O primeiro bloco ```bash depois do título da A4.
awk '/^## A4 /{a=1} a && /^```bash/{b=1; next} b && /^```/{exit} b' "$SKILL" > "$TMP/a4.sh"
[ -s "$TMP/a4.sh" ] || { echo "bloco bash da A4 não encontrado em $SKILL"; exit 2; }

SK="sk-FALSOabcdefghijklmnopqrstuvwxyz0123"
JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJmYWxzbyJ9.assinaturafalsa1234567890"
CFG="valorFALSO1234567890"
R="$TMP/repo"; mkdir -p "$R/dist" "$R/.next/static"
printf 'const a=1;\nconst k="%s";\n' "$SK" > "$R/dist/app.js"
printf 'var t="%s";\n' "$JWT" > "$R/.next/static/chunk.js"
printf 'nome: app\napi_key: "%s"\n' "$CFG" > "$R/config.yml"
printf 'services:\n  api:\n    environment:\n      JWT_SECRET: ${JWT_SECRET:-trocar-depois}\n' > "$R/docker-compose.yml"

saida=$(cd "$R" && PATH=/usr/bin:/bin bash "$TMP/a4.sh" 2>&1)

echo "== o segredo não sai inteiro =="
nao_tem "$SK"  "$saida" "chave sk- do bundle mascarada"
nao_tem "$JWT" "$saida" "JWT do bundle mascarado"
nao_tem "$CFG" "$saida" "valor do api_key em config mascarado"

echo "== o achado continua achável: arquivo:linha e os 6 primeiros caracteres =="
tem "dist/app.js:2:sk-FAL"            "$saida" "bundle: dist/app.js:2 e sk-FAL"
tem ".next/static/chunk.js:1:eyJhbG"  "$saida" "bundle: .next/static/chunk.js:1 e eyJhbG"
tem "config.yml:2:"                   "$saida" "config: config.yml:2"
tem "\"valorF"                        "$saida" "config: os 6 primeiros caracteres do valor"

echo "== o resto do bloco segue rodando =="
tem "docker-compose.yml:4:" "$saida" "default público do compose continua listado"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
