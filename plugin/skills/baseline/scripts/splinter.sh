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
# Três travas, porque isto roda SQL de terceiro no banco de produção:
#   - o upstream é fixado num commit (SPLINTER_REF troca; revise o diff antes de subir o pin).
#     Antes era `git pull` a cada rodada: o que entrasse no upstream rodava no banco no dia;
#   - cada lint roda dentro de `begin transaction read only … rollback`, e o script só segue
#     se o executor provar que a transação está read only (sonda no início);
#   - o stderr do banco aparece no erro. Antes ia para /dev/null e o lint "falhava" sem motivo.
# SUPABASE_DB_URL_RO (papel só de leitura) tem preferência sobre SUPABASE_DB_URL.
#
#   splinter.sh                 todos os lints de segurança
#   splinter.sh 0013 0011       só os indicados
#   splinter.sh --all           inclui os de performance
#   splinter.sh --list          lista o catálogo e sai

set -uo pipefail

REPO="https://github.com/supabase/splinter.git"
# Commit revisado em 27/11/2026. Para atualizar: leia o diff de lints/ entre os dois commits.
REF="${SPLINTER_REF:-cc529aa9d3eeffd2e64576c7591e60b22abd205c}"
case "$REF" in *[!0-9a-f]*|"") echo "ERRO: SPLINTER_REF tem de ser um sha de commit (hex), não branch nem tag." >&2; exit 2 ;; esac
[ ${#REF} -eq 40 ] || { echo "ERRO: SPLINTER_REF tem de ser o sha completo (40 caracteres)." >&2; exit 2; }
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/baseline/splinter-$REF"
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
# Um diretório por commit, e nunca `pull`: o que está em cache é o commit pedido ou nada.
if [ "$(git -C "$CACHE" rev-parse HEAD 2>/dev/null)" != "$REF" ]; then
  echo "→ baixando lints no commit ${REF:0:12} (uma vez) em $CACHE" >&2
  rm -rf "$CACHE"; mkdir -p "$CACHE"
  { git -C "$CACHE" init -q && git -C "$CACHE" fetch -q --depth 1 "$REPO" "$REF" \
      && git -C "$CACHE" -c advice.detachedHead=false checkout -q FETCH_HEAD; } 2>"$CACHE.err" || {
    echo "ERRO: não consegui baixar $REPO no commit $REF. Sem rede? O pilar 02 fica nao_medido." >&2
    head -3 "$CACHE.err" >&2; rm -rf "$CACHE" "$CACHE.err"
    exit 3; }
  rm -f "$CACHE.err"
  [ "$(git -C "$CACHE" rev-parse HEAD 2>/dev/null)" = "$REF" ] || {
    echo "ERRO: o commit baixado não é $REF." >&2; rm -rf "$CACHE"; exit 3; }
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
TMPERR="$(mktemp "${TMPDIR:-/tmp}/splinter-XXXXXX.err")"
cleanup() { rm -f "$TMPSQL" "$TMPERR"; }
trap cleanup EXIT

# run_sql lê UM comando de stdin (sem `;` no fim) e o roda dentro de uma transação read only
# que termina em rollback. O `;` do meio do lote é nosso, não do lint: lint com mais de um
# comando não passa (ver `um_comando`). stderr fica em $TMPERR.
DBURL="${SUPABASE_DB_URL_RO:-${SUPABASE_DB_URL:-}}"
EXEC=""
run_sql() {
  { printf 'begin transaction read only;\n'; cat; printf '\n;\nrollback;\n'; } > "$TMPSQL"
  : > "$TMPERR"
  case "$EXEC" in
    psql)     psql "$DBURL" -X -q -t -A -F '|' -v ON_ERROR_STOP=1 -f "$TMPSQL" 2>"$TMPERR" ;;
    dbq-psql) ./scripts/db-query.sh --psql -f "$TMPSQL" 2>"$TMPERR" ;;
    dbq)      ./scripts/db-query.sh -f "$TMPSQL" 2>"$TMPERR" ;;
    *) return 97 ;;
  esac
}
# A sonda escolhe o executor: só serve o que devolve o SELECT do meio do lote E mostra a
# transação read only. Executor que só devolve o último comando (o rollback) não prova nada,
# e rodar sem a transação seria aplicar SQL de terceiro com permissão de escrita.
cand=""
[ -n "$DBURL" ] && command -v psql >/dev/null 2>&1 && cand="psql"
[ -x ./scripts/db-query.sh ] && cand="$cand dbq-psql dbq"
sonda_err=""
for e in $cand; do
  EXEC="$e"
  if printf "select 'splinter-ro-' || current_setting('transaction_read_only')" | run_sql 2>/dev/null \
       | grep -q 'splinter-ro-on'; then break; fi
  sonda_err="$sonda_err\n  $e: $(head -2 "$TMPERR" | tr '\n' ' ')"
  EXEC=""
done
if [ -z "$EXEC" ]; then
  echo "ERRO: sem acesso read only ao banco." >&2
  if [ -z "$cand" ]; then
    echo "Faltam psql com \$SUPABASE_DB_URL_RO (ou \$SUPABASE_DB_URL) e ./scripts/db-query.sh." >&2
  else
    printf 'Nenhum executor devolveu o SELECT de dentro da transação read only:%b\n' "$sonda_err" >&2
    echo "Use psql com \$SUPABASE_DB_URL_RO: ele imprime cada comando do lote." >&2
  fi
  echo "Sem isto o pilar 02 é nao_medido — não é 'conforme'." >&2
  exit 97
fi

um_comando() { # o corpo do lint é um comando só? (ignora `;` dentro de aspas simples e de comentário)
  printf '%s' "$1" | sed -E "s/--.*$//; s/'[^']*'//g" | grep -q ';' && return 1
  return 0
}

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

echo "# splinter — ${#files[@]} lints · commit ${REF:0:12} · transação read only ($EXEC), sem DDL"
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
  if ! um_comando "$sql"; then
    printf '\n## %s — mais de um comando no arquivo: não roda (nao_medido)\n' "$name"; falhou=$((falhou+1)); continue
  fi

  # Projeta só nível e detalhe. A view do lint devolve 10 colunas — description e
  # remediation são parágrafos inteiros, repetidos em toda linha, e tornam a
  # saída ilegível justamente quando há muitos achados.
  out="$(printf 'with l as (\n%s\n) select level || %s || detail from l;\n' "$sql" "' · '" | run_sql)"
  rc=$?
  if [ $rc -ne 0 ]; then
    printf '\n## %s — ERRO ao executar (nao_medido): %s\n' "$name" "$(head -2 "$TMPERR" | tr '\n' ' ')"
    falhou=$((falhou+1)); continue
  fi

  # Contagem: psql fecha com "(N rows)". Se houver, ela é a verdade — as linhas
  # de cabeçalho do wrapper contaminariam um grep -c.
  n="$(printf '%s' "$out" | grep -oE '\(([0-9]+) rows?\)' | tail -1 | grep -oE '[0-9]+')"
  if [ -z "$n" ]; then
    n="$(printf '%s' "$out" | grep -vE '^(lint:|  ->|psql:|-+\+|.*\| *$|BEGIN$|ROLLBACK$)' | grep -c . 2>/dev/null; true)"
  fi
  if [ "${n:-0}" -gt 0 ]; then
    printf '\n## %s — %s ocorrência(s)\n' "$name" "$n"
    printf '%s\n' "$out" | grep -vE '^(lint:|  ->|psql:|BEGIN$|ROLLBACK$)' | head -25
    total=$((total + n))
  fi
done

echo
echo "# total: $total ocorrências em ${#files[@]} lints · $falhou falharam"
[ "$falhou" -eq "${#files[@]}" ] && { echo "# TODOS falharam — trate como nao_medido." >&2; exit 3; }
[ "$total" -gt 0 ] && exit 1
exit 0
