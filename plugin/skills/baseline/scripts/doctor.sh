#!/usr/bin/env bash
# baseline · doctor — o que dá pra medir neste ambiente, ANTES de medir.
#
# Descobrir que falta jq no meio do collect é caro. Descobrir antes custa 200ms.
# Escreve tools.json, que vira a tabela de cobertura do report.
# Sai 0 sempre (é informativo); sinaliza degradação em tools.json.

set -uo pipefail

OUT="" ; ROOT="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --out)  OUT="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done
[ -n "$OUT" ] || OUT="/tmp/baseline-$(basename "$ROOT")"
mkdir -p "$OUT"

rows=""       # nome|estado|versao|para_que|instalar
degraded=0

check() { # nome  cmd  essencial(0|1)  para_que  instalar
  local name="$1" cmd="$2" essential="$3" purpose="$4" install="$5" ver="" state=""
  if command -v "$cmd" >/dev/null 2>&1; then
    ver="$("$cmd" --version 2>/dev/null | head -1 | tr -d '\r' | cut -c1-40)"
    [ -n "$ver" ] || ver="presente"
    state="ok"
  else
    state="ausente"
    [ "$essential" = "1" ] && degraded=1
  fi
  rows="${rows}${name}|${state}|${ver}|${purpose}|${install}"$'\n'
}

check git         git         1 "base de tudo"                 "xcode-select --install"
check jq          jq          1 "montar findings.json"          "brew install jq"
check node        node        1 "render.mjs"                    "brew install node"
check curl        curl        1 "headers servidos (pilar 01)"   "já vem no macOS"
check gitleaks    gitleaks    0 "segredos: HEAD + histórico (07)" "brew install gitleaks"
check semgrep     semgrep     0 "SAST (código)"                 "pipx install semgrep"
check osv-scanner osv-scanner 0 "CVE de dependência"            "brew install osv-scanner"
check trufflehog  trufflehog  0 "confirmar se o segredo AINDA vive (07)" "brew install trufflehog"
check psql        psql        0 "lints do banco (pilar 02)"     "brew install libpq"
check gh          gh          0 "PRs abertos, CI"               "brew install gh"

# acesso ao banco: o script do projeto vale mais que psql solto
db_access="ausente"; db_how="-"
if [ -x "$ROOT/scripts/db-query.sh" ]; then
  db_access="ok"; db_how="scripts/db-query.sh"
elif [ -n "${SUPABASE_DB_URL:-}" ]; then
  db_access="ok"; db_how="\$SUPABASE_DB_URL"
fi
rows="${rows}db-access|${db_access}|${db_how}|pilar 02 (RLS, policies, lints)|exportar SUPABASE_DB_URL ou usar scripts/db-query.sh"$'\n'

# contrato do projeto
contract="$ROOT/.context/docs/baseline.md"
if [ -f "$contract" ]; then c_state="ok"; else c_state="ausente"; fi
rows="${rows}contrato|${c_state}|${contract}|exceções aceitas e alvo por pilar|gerar de references/contrato-template.md"$'\n'

printf '%-13s %-8s %s\n' "FERRAMENTA" "ESTADO" "PARA QUE"
printf '%s\n' "-------------------------------------------------------------"
printf '%s' "$rows" | while IFS='|' read -r n s v p i; do
  [ -n "$n" ] || continue
  if [ "$s" = "ok" ]; then printf '%-13s %-8s %s\n' "$n" "ok" "$p"
  else printf '%-13s %-8s %s  → %s\n' "$n" "AUSENTE" "$p" "$i"; fi
done

# tools.json — uma linha JSON por ferramenta, juntadas com vírgula no fim.
# Sem contador dentro de pipe (subshell) e sem depender de jq, que pode faltar.
tmp_rows="$(mktemp)"
printf '%s' "$rows" | while IFS='|' read -r n s v p i; do
  [ -n "$n" ] || continue
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  printf '    {"name":"%s","state":"%s","version":"%s","purpose":"%s","install":"%s"}\n' \
    "$(esc "$n")" "$(esc "$s")" "$(esc "$v")" "$(esc "$p")" "$(esc "$i")"
done > "$tmp_rows"

{
  printf '{\n  "generated_at": "%s",\n  "root": "%s",\n  "degraded": %s,\n  "tools": [\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ROOT" "$([ $degraded -eq 1 ] && echo true || echo false)"
  sed '$!s/$/,/' "$tmp_rows"
  printf '  ]\n}\n'
} > "$OUT/tools.json"
rm -f "$tmp_rows"

echo
echo "→ $OUT/tools.json"
if [ $degraded -eq 1 ]; then
  echo "AVISO: falta ferramenta essencial — collect.sh vai medir menos e a cobertura vai dizer isso."
fi
exit 0
