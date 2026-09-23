#!/usr/bin/env bash
# Prova do plugin/hooks/session-size-guard.sh: avisa uma vez por faixa (600/1200/2000
# linhas de transcript), nunca abaixo da primeira, nunca duas vezes na mesma faixa.
#
# O aviso é para a pessoa, não para o modelo: cada linha sai com o prefixo `@usuario `, que
# o pre-prompt.sh troca por systemMessage (o test-pre-prompt.sh cobre esse caminho). E o
# texto diz quantos tokens cada pedido relê, sem prometer economia em dinheiro.
#
# Uso: bash tests/test-session-size-guard.sh [caminho-do-hook]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/session-size-guard.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }

falhas=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
TP="$TMP/transcript.jsonl"

linhas() { : > "$TP"; local i=0; while [ "$i" -lt "$1" ]; do echo '{"x":1}' >> "$TP"; i=$((i+1)); done; }
run() { # <sid>
  SID="$1" TP="$TP" node -e 'process.stdout.write(JSON.stringify({session_id:process.env.SID,transcript_path:process.env.TP}))' | bash "$HOOK" 2>/dev/null
}
check() { # <regex-ou-vazio> <descrição> <saída>
  local ok=0
  if [ -z "$1" ]; then [ -z "$3" ] && ok=1
  else printf '%s' "$3" | grep -q "$1" && ok=1; fi
  if [ "$ok" = 1 ]; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (veio: %s)\n' "$2" "${3:-<vazio>}"; falhas=$((falhas+1)); fi
}
# para_a_pessoa <faixa> <aviso>: tem aviso, toda linha começa com `@usuario ` e o texto fala
# em tokens, sem "barato" nem "custo".
para_a_pessoa() {
  local sem_prefixo; sem_prefixo=$(printf '%s\n' "$2" | sed -n '/^@usuario /!p')
  if [ -n "$2" ] && [ -z "$sem_prefixo" ]; then printf '  ok    faixa %s: toda linha sai com @usuario\n' "$1"
  else printf '  FALHA faixa %s: linha sem @usuario (veio: %s)\n' "$1" "${2:-<vazio>}"; falhas=$((falhas+1)); fi
  if printf '%s' "$2" | grep -q 'mil tokens' && ! printf '%s' "$2" | grep -qiE 'barat|custo'; then
    printf '  ok    faixa %s: fala em tokens, não em dinheiro\n' "$1"
  else printf '  FALHA faixa %s: sem tokens ou com promessa de dinheiro (veio: %s)\n' "$1" "${2:-<vazio>}"; falhas=$((falhas+1)); fi
}

linhas 100;  check ""            "100 linhas: silêncio"                         "$(run s1)"
linhas 700;  a600="$(run s1)"
check "~600 linhas"              "700 linhas: aviso da faixa 600"               "$a600"
linhas 900;  check ""            "900 linhas: mesma faixa, não repete"          "$(run s1)"
linhas 1300; a1200="$(run s1)"
check "1.200"                    "1300 linhas: aviso da faixa 1200"             "$a1200"
linhas 2500; a2000="$(run s1)"
check "2.000"                    "2500 linhas: aviso da faixa 2000"             "$a2000"
linhas 2600; check ""            "2600 linhas: já avisou o topo, silêncio"      "$(run s1)"
linhas 700;  check "~600 linhas" "outra sessão começa do zero"                  "$(run s2)"
rm -f "$TP";  check ""           "transcript inexistente: silêncio (falha-aberta)" "$(run s3)"

echo
echo "== o aviso vai para a pessoa, em tokens =="
para_a_pessoa 600  "$a600"
para_a_pessoa 1200 "$a1200"
para_a_pessoa 2000 "$a2000"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
