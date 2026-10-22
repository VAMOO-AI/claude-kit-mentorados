#!/usr/bin/env bash
# A fila de pendentes do núcleo (tests/esperado-falhar.txt, F1 do #241) não mente.
#
# Duas metades:
#   1. o arquivo real: cada linha aponta uma suíte que existe e que carrega a lib, a
#      descrição aparece literal nessa suíte, nada se repete; a contagem por suíte sai aqui;
#   2. a lib (tests/lib-esperado-falhar.sh): caso listado que falha vira PENDENTE e não
#      reprova; caso listado que passou reprova como ÓRFÃ; caso fora da lista segue como
#      sempre; o modo --codex tem fila própria.
#
# Uso: bash tests/test-esperado-falhar.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
ARQ="$RAIZ/tests/esperado-falhar.txt"
falhas=0
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

echo "== o arquivo real =="
[ -f "$ARQ" ] && ok "tests/esperado-falhar.txt existe" || falha "tests/esperado-falhar.txt não existe"
n=0; vistas=""
while IFS= read -r linha || [ -n "$linha" ]; do
  case "$linha" in ''|'#'*) continue ;; esac
  n=$((n+1))
  case "$linha" in *"	"*) ;; *) falha "linha sem TAB: $linha"; continue ;; esac
  suite="${linha%%	*}"; desc="${linha#*	}"
  arq="${suite% --codex}"
  if [ ! -f "$RAIZ/tests/$arq" ]; then falha "suíte inexistente: $suite"; continue; fi
  grep -q 'lib-esperado-falhar.sh' "$RAIZ/tests/$arq" || falha "$arq não carrega a lib: a linha nunca seria lida"
  grep -qF -- "\"$desc\"" "$RAIZ/tests/$arq" || falha "descrição não está em $arq: $desc"
  case "$vistas" in *"|$linha|"*) falha "linha repetida: $linha" ;; esac
  vistas="$vistas|$linha|"
done < "$ARQ"
echo "  pendentes na fila: $n"
if [ "$n" -gt 0 ]; then
  grep -v '^#' "$ARQ" | grep -v '^$' | cut -f1 | sort | uniq -c | sed 's/^/    /'
fi

echo
echo "== a lib =="
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test-falsa.sh" <<'EOF'
CODEX=0; [ "${1:-}" = --codex ] && CODEX=1
falhas=0
. "$LIB"
ef_check passa bloqueia "listado e ainda falha"
ef_check passa passa    "listado e já passa"
ef_check passa passa    "fora da lista e passa"
ef_check passa bloqueia "fora da lista e falha"
ef_check passa bloqueia "listado só no codex"
ef_resumo
echo "falhas=$falhas pendentes=$pendentes"
EOF
printf 'test-falsa.sh\tlistado e ainda falha\ntest-falsa.sh\tlistado e já passa\ntest-falsa.sh --codex\tlistado só no codex\n' > "$TMP/fila.txt"
out="$(LIB="$RAIZ/tests/lib-esperado-falhar.sh" ESPERADO_FALHAR="$TMP/fila.txt" bash "$TMP/test-falsa.sh")"
tem() { printf '%s\n' "$out" | grep -qF -- "$2" && ok "$1" || falha "$1 (faltou: $2)"; }
tem "listado que falha sai como pendente"       "PEND. listado e ainda falha"
tem "listado que passa reprova como órfã"       "ÓRFÃ  listado e já passa"
tem "fora da lista e passa é ok"                "ok    fora da lista e passa"
tem "fora da lista e falha reprova"             "FALHA fora da lista e falha"
tem "fila do --codex não vale no modo normal"   "FALHA listado só no codex"
tem "contagem: 3 falhas e 1 pendente"           "falhas=3 pendentes=1"
tem "o resumo mostra a contagem de pendentes"   "pendentes (tests/esperado-falhar.txt): 1"
out="$(LIB="$RAIZ/tests/lib-esperado-falhar.sh" ESPERADO_FALHAR="$TMP/fila.txt" bash "$TMP/test-falsa.sh" --codex)"
tem "no --codex vale a fila do --codex"         "PEND. listado só no codex"
tem "no --codex a fila do modo normal não vale" "FALHA listado e ainda falha"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
