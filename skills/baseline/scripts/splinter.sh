#!/usr/bin/env bash
# baseline · splinter — os lints do Supabase Security/Performance Advisor,
# rodados como SELECT puro contra o banco do projeto.
#
# Por que não vendorizamos os .sql: o repo supabase/splinter não publica arquivo
# de licença, então redistribuir não está autorizado. Baixamos em cache local e
# rodamos de lá.
#
# Por que não usamos o splinter.sql inteiro: ele CRIA views num schema `lint`.
# Auditoria não faz DDL no banco auditado. Cada lint é convertido em SELECT.
#
#   splinter.sh                 todos os lints de segurança
#   splinter.sh 0013 0011       só os indicados
#   splinter.sh --all           inclui os de performance
#   splinter.sh --list          lista o catálogo e sai

set -uo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/baseline/splinter"
REPO="https://github.com/supabase/splinter.git"
SEC_ONLY=1 ; WANT=() ; LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --all)  SEC_ONLY=0; shift ;;
    --list) LIST=1; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) WANT+=("$1"); shift ;;
  esac
done

# ── cache
if [ ! -d "$CACHE/.git" ]; then
  echo "→ baixando lints (uma vez) em $CACHE" >&2
  mkdir -p "$(dirname "$CACHE")"
  git clone --depth 1 -q "$REPO" "$CACHE" 2>/dev/null || {
    echo "ERRO: não consegui baixar $REPO. Sem rede? O pilar 02 fica nao_medido." >&2
    exit 3; }
else
  git -C "$CACHE" pull -q --ff-only 2>/dev/null || true
fi

LINTS="$CACHE/lints"
[ -d "$LINTS" ] || { echo "ERRO: $LINTS não existe — layout do repo mudou." >&2; exit 3; }

if [ "$LIST" -eq 1 ]; then
  for f in "$LINTS"/*.sql; do
    n="$(basename "$f" .sql)"
    lvl="$(grep -oE "'(ERROR|WARN|INFO)' as level" "$f" 2>/dev/null | head -1 | cut -d\' -f2)"
    cat="$(grep -oE "array\['[A-Z]+'\] as categories" "$f" 2>/dev/null | head -1 | cut -d\' -f2)"
    printf '%-52s %-6s %s\n' "$n" "${lvl:-?}" "${cat:-?}"
  done
  exit 0
fi

# ── como falar com o banco
# Nem todo db-query.sh aceita stdin ('-f -') — vários só leem arquivo real.
# Gravamos o SQL num temporário e passamos o caminho — funciona nas duas
# interfaces. O arquivo vai para fora do repo e é apagado no fim.
TMPSQL="$(mktemp "${TMPDIR:-/tmp}/splinter-XXXXXX.sql")"
cleanup() { rm -f "$TMPSQL"; }
trap cleanup EXIT

run_sql() { # lê o SQL de stdin
  cat > "$TMPSQL"
  if [ -x ./scripts/db-query.sh ]; then
    ./scripts/db-query.sh --psql -f "$TMPSQL" 2>/dev/null \
      || ./scripts/db-query.sh -f "$TMPSQL" 2>/dev/null
  elif [ -n "${SUPABASE_DB_URL:-}" ]; then
    psql "$SUPABASE_DB_URL" -X -q -t -A -F '|' -f "$TMPSQL" 2>/dev/null
  else return 97; fi
}
if ! printf 'select 1;\n' | run_sql >/dev/null 2>&1; then
  echo "ERRO: sem acesso ao banco (./scripts/db-query.sh ou \$SUPABASE_DB_URL)." >&2
  echo "Sem isto o pilar 02 é nao_medido — não é 'conforme'." >&2
  exit 97
fi

# ── seleção
files=()
if [ ${#WANT[@]} -gt 0 ]; then
  for w in "${WANT[@]}"; do
    for f in "$LINTS"/${w}*.sql; do [ -f "$f" ] && files+=("$f"); done
  done
else
  for f in "$LINTS"/*.sql; do
    if [ "$SEC_ONLY" -eq 1 ]; then
      grep -q "'SECURITY'" "$f" 2>/dev/null && files+=("$f")
    else files+=("$f"); fi
  done
fi
[ ${#files[@]} -gt 0 ] || { echo "ERRO: nenhum lint casou com '${WANT[*]:-}'." >&2; exit 2; }

echo "# splinter — ${#files[@]} lints · SELECT puro, sem DDL"
total=0 ; falhou=0

for f in "${files[@]}"; do
  name="$(basename "$f" .sql)"
  # O arquivo é 'create view lint."NNNN_x" as' + SELECT. Queremos só o SELECT:
  # tudo da primeira linha que começa com 'select' em diante. Tentar remover o
  # cabeçalho por regex falha — o ' as' fica na mesma linha do create view.
  # Corta o cabeçalho 'create view lint."NNNN_x" as' e fica com o corpo INTEIRO.
  # Cortar a partir de /^select/ decapitaria os lints que declaram CTE antes
  # (0024 usa 'with permissive_patterns as (...)' e falhava com
  # 'relation "permissive_patterns" does not exist').
  # Remove só a linha do cabeçalho ('create view lint."NNNN_x" as') e mantém o
  # corpo inteiro. Duas armadilhas já pagas aqui:
  #   - cortar a partir de /^select/ decapita os lints que declaram CTE antes
  #     (0024 usa 'with permissive_patterns as (...)');
  #   - '1,/create view lint\./d' apaga o arquivo TODO, porque o padrão casa na
  #     linha 1 e o sed passa a procurar a próxima ocorrência a partir da 2.
  sql="$(sed -E '/create[[:space:]]+view[[:space:]]+lint\./d' "$f" 2>/dev/null | sed -E 's/;[[:space:]]*$//')"
  case "$sql" in *[!$' \t\n']*) : ;; *) printf '\n## %s — não consegui extrair o SELECT (nao_medido)\n' "$name"; falhou=$((falhou+1)); continue ;; esac

  # Projeta só nível e detalhe. A view do lint devolve 10 colunas — description e
  # remediation são parágrafos inteiros, repetidos em toda linha, e tornam a
  # saída ilegível justamente quando há muitos achados.
  out="$(printf 'with l as (\n%s\n) select level || %s || detail from l;\n' "$sql" "' · '" | run_sql)"
  rc=$?
  if [ $rc -ne 0 ]; then
    printf '\n## %s — ERRO ao executar (nao_medido)\n' "$name"
    falhou=$((falhou+1)); continue
  fi

  # Contagem: psql fecha com "(N rows)". Se houver, ela é a verdade — as linhas
  # de cabeçalho do wrapper contaminariam um grep -c.
  n="$(printf '%s' "$out" | grep -oE '\(([0-9]+) rows?\)' | tail -1 | grep -oE '[0-9]+')"
  if [ -z "$n" ]; then
    n="$(printf '%s' "$out" | grep -vE '^(lint:|  ->|psql:|-+\+|.*\| *$)' | grep -c . 2>/dev/null; true)"
  fi
  if [ "${n:-0}" -gt 0 ]; then
    printf '\n## %s — %s ocorrência(s)\n' "$name" "$n"
    printf '%s\n' "$out" | grep -vE '^(lint:|  ->|psql:)' | head -25
    total=$((total + n))
  fi
done

echo
echo "# total: $total ocorrências em ${#files[@]} lints · $falhou falharam"
[ "$falhou" -eq "${#files[@]}" ] && { echo "# TODOS falharam — trate como nao_medido." >&2; exit 3; }
[ "$total" -gt 0 ] && exit 1
exit 0
