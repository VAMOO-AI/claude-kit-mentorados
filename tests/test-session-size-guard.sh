#!/usr/bin/env bash
# Prova do plugin/hooks/session-size-guard.sh: avisa uma vez por faixa (600/1200/2000
# linhas de transcript), nunca abaixo da primeira, nunca duas vezes na mesma faixa.
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

linhas 100;  check ""            "100 linhas: silêncio"                         "$(run s1)"
linhas 700;  check "~600 linhas" "700 linhas: aviso da faixa 600"               "$(run s1)"
linhas 900;  check ""            "900 linhas: mesma faixa, não repete"          "$(run s1)"
linhas 1300; check "1.200"       "1300 linhas: aviso da faixa 1200"             "$(run s1)"
linhas 2500; check "2.000"       "2500 linhas: aviso da faixa 2000"             "$(run s1)"
linhas 2600; check ""            "2600 linhas: já avisou o topo, silêncio"      "$(run s1)"
linhas 700;  check "~600 linhas" "outra sessão começa do zero"                  "$(run s2)"
rm -f "$TP";  check ""           "transcript inexistente: silêncio (falha-aberta)" "$(run s3)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
