#!/usr/bin/env bash
# O pilar 02 da baseline diz o que mediu, o fallback do 02-banco.md acha o que promete, e os
# blocos de comando do SKILL.md rodam linha a linha.
#
# collect.sh: com supabase/migrations/ e migrations/ na mesma raiz só a primeira era lida, e a
# pasta sem nenhum .sql saía "medido" — relatório verde sem uma linha de SQL lida. Sem pasta de
# migration, o motivo não dizia que o RLS ficou sem medir (28/09/2026). A cobertura passa a
# nomear as pastas medidas, e o que não mediu sai "RLS não medido".
#
# 02-banco.md: o fallback de SECURITY DEFINER sem search_path era um `grep -L` sobre stdin, que
# nunca imprime nome de arquivo. O teste roda o bloco copiado da própria referência, então ele
# reprova se o texto voltar a prometer o que o comando não faz.
#
# SKILL.md e 02-banco.md: os blocos definiam `SK=` e `OUT=` numa linha e liam nas seguintes. O shell não
# guarda variável de uma chamada para a outra, e o modelo costuma rodar linha a linha: o
# `$SK/scripts/collect.sh` virava `/scripts/collect.sh`. Nenhuma linha de bloco lê `$SK`/`$OUT`
# que ela mesma não define.
#
# Uso: bash tests/test-baseline-banco.sh [collect.sh] [02-banco.md] [SKILL.md]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${1:-$RAIZ/plugin/skills/baseline/scripts/collect.sh}"
BANCO="${2:-$RAIZ/plugin/skills/baseline/references/02-banco.md}"
SKILL="${3:-$RAIZ/plugin/skills/baseline/SKILL.md}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }
[ -f "$BANCO" ]  || { echo "referência não encontrada: $BANCO"; exit 2; }
[ -f "$SKILL" ]  || { echo "SKILL.md não encontrado: $SKILL"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq ausente — o collect.sh depende dele"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/baseline-banco.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

repo() { # repo <nome> — projeto git com um commit; o caminho fica em $R
  R="$TMP/$1"
  git init -q -b main "$R"
  git -C "$R" config user.email t@t; git -C "$R" config user.name t
  git -C "$R" config commit.gpgsign false
  printf '{"name":"fixture"}\n' > "$R/package.json"
  git -C "$R" add package.json
  git -C "$R" commit -qm base
}
arquivo() { # arquivo <caminho> <conteúdo> — grava no repo $R e commita
  mkdir -p "$(dirname "$R/$1")"
  printf '%s\n' "$2" > "$R/$1"
  git -C "$R" add "$1"
  git -C "$R" commit -qm "$1"
}
roda() { # roda <n> [args do collect] — o 07 entra porque mede sempre: o 02 sozinho sai 3
  local n="$1"; shift
  bash "$SCRIPT" --root "$R" --out "$TMP/out-$n" --pilar 02,07 "$@" >"$TMP/stdout-$n" 2>"$TMP/stderr-$n"
  EXIT=$?
  COB="$(jq -r '.coverage[] | select(.pilar=="02" and .check=="rls_migrations") | "\(.status) | \(.reason)"' \
         "$TMP/out-$n/findings.json" 2>/dev/null)"
}

echo "== sem pasta de migration: RLS não medido, com essas palavras =="
repo sem-pasta
roda 1
case "$COB" in
  nao_medido*"RLS não medido"*) ok "rls_migrations: $COB" ;;
  *) falha "rls_migrations sem pasta: ${COB:-<ausente>} (esperado nao_medido com 'RLS não medido')" ;;
esac

echo "== pasta sem nenhum .sql não é medição =="
repo pasta-vazia
arquivo supabase/migrations/.gitkeep ''
roda 2
case "$COB" in
  nao_medido*"RLS não medido"*supabase/migrations*) ok "rls_migrations: $COB" ;;
  *) falha "pasta sem .sql: ${COB:-<ausente>} (esperado nao_medido, 'RLS não medido' e o nome da pasta)" ;;
esac

echo "== as duas pastas na raiz: as duas são lidas, e o relatório nomeia as duas =="
# O `ls -d ... | head -1` antigo ficava com migrations/ (ordem alfabética) e pulava a outra:
# uma tabela sem RLS em cada pasta, e o finding tem que citar as duas.
repo duas-pastas
arquivo supabase/migrations/20260901000000_exposta_a.sql 'create table public.exposta_a (id int);'
arquivo migrations/001_exposta_b.sql 'create table public.exposta_b (id int);
create table public.protegida (id int);
alter table public.protegida enable row level security;'
roda 3
[ "$EXIT" -eq 1 ] && ok "tabela sem RLS: exit 1" || falha "tabela sem RLS saiu $EXIT (esperado 1)"
for t in exposta_a exposta_b; do
  jq -e --arg t "$t" '[.findings[] | select(.pilar=="02" and .severity=="HIGH" and (.detail | test($t)))] | length > 0' \
       "$TMP/out-3/findings.json" >/dev/null 2>&1 \
    && ok "o finding cita $t" || falha "a tabela sem RLS $t não virou finding"
done
jq -e '[.findings[] | select(.pilar=="02" and (.detail | test("protegida")))] | length == 0' \
     "$TMP/out-3/findings.json" >/dev/null 2>&1 \
  && ok "a tabela com RLS não vira finding" || falha "a tabela com RLS virou finding"
case "$COB" in
  medido*supabase/migrations*) ok "o motivo nomeia supabase/migrations: $COB" ;;
  *) falha "o motivo não nomeia supabase/migrations: ${COB:-<ausente>}" ;;
esac
# "migrations" também está dentro de "supabase/migrations": a da raiz vem depois de espaço ou ':'
printf '%s' "$COB" | grep >/dev/null -E '(^|[ :(])migrations' \
  && ok "o motivo nomeia migrations/ da raiz" || falha "o motivo não nomeia migrations/ da raiz: ${COB:-<ausente>}"

echo "== --diff: a cobertura nomeia a pasta da migration medida =="
repo diff-com
BASE="$(git -C "$R" rev-parse HEAD)"
arquivo supabase/migrations/20260902000000_nova.sql 'create table public.nova (id int);
alter table public.nova enable row level security;'
roda 4 --diff "$BASE"
case "$COB" in
  medido*supabase/migrations*) ok "rls_migrations: $COB" ;;
  *) falha "--diff com migration: ${COB:-<ausente>} (esperado medido, com a pasta)" ;;
esac

echo "== --diff sem migration no diff: RLS não medido =="
repo diff-sem
arquivo supabase/migrations/20260903000000_velha.sql 'create table public.velha (id int);
alter table public.velha enable row level security;'
BASE="$(git -C "$R" rev-parse HEAD)"
arquivo src/a.ts 'export const x = 1;'
roda 5 --diff "$BASE"
case "$COB" in
  nao_medido*"RLS não medido"*) ok "rls_migrations: $COB" ;;
  *) falha "--diff sem migration: ${COB:-<ausente>} (esperado nao_medido com 'RLS não medido')" ;;
esac

echo "== 02-banco.md: o fallback de search_path acusa a migration que não tem =="
repo banco
arquivo supabase/migrations/001_com_sp.sql "create function public.a() returns int language sql
security definer set search_path = '' as \$\$ select 1 \$\$;"
arquivo supabase/migrations/002_sem_sp.sql 'create function public.b() returns int language sql
security definer as $$ select 1 $$;'
# o bloco da referência: do comentário do SECURITY DEFINER até o fim do trecho de código
BLOCO="$(awk '/^# SECURITY DEFINER sem search_path/{p=1} p && /^```/{exit} p' "$BANCO")"
if [ -z "$BLOCO" ]; then
  falha "não achei no 02-banco.md o bloco '# SECURITY DEFINER sem search_path'"
else
  SAIDA="$(cd "$R" && bash -c "$BLOCO" 2>&1)"
  case "$SAIDA" in
    *002_sem_sp.sql*) ok "acusa a migration sem search_path" ;;
    *) falha "o bloco não acusou 002_sem_sp.sql; saiu: ${SAIDA:-<vazio>}" ;;
  esac
  case "$SAIDA" in
    *001_com_sp.sql*) falha "acusou 001_com_sp.sql, que tem search_path" ;;
    *) ok "não acusa a que tem search_path" ;;
  esac
fi

echo "== SKILL.md e 02-banco.md: nenhuma linha de bloco lê \$SK ou \$OUT de outra linha =="
presas="$(awk '/^```bash/{b=1; next} b && /^```/{b=0} b' "$SKILL" "$BANCO" \
  | grep -E '\$\{?(SK|OUT)\b' | grep -vE '(^|[;[:space:]])(SK|OUT)=')"
[ -z "$presas" ] && ok "cada linha se basta" \
  || falha "linha que lê variável definida em outra linha: $(printf '%s' "$presas" | head -3)"

echo "== 02-banco.md: o fallback de tabelas criadas aceita tab e vários espaços =="
# Com um espaço literal no regex, `create<TAB>table` nem entrava na lista, e
# `alter table x<TAB>enable row level security` saía "nunca protegida" mesmo protegida.
repo banco-espacos
arquivo supabase/migrations/001_alinhada.sql "$(printf 'create\ttable public.aberta_tab (id int);\ncreate   table   if   not   exists   public.aberta_esp (id int);\ncreate table public.tab_tab (id int);\ncreate table public.espacos (id int);\nalter table public.tab_tab\tenable row level security;\nalter   table   public.espacos   enable   row   level   security;')"
BLOCO="$(awk '/^# tabelas criadas vs tabelas com RLS/{p=1} p{print} p && /^comm /{exit}' "$BANCO")"
if [ -z "$BLOCO" ]; then
  falha "não achei no 02-banco.md o bloco '# tabelas criadas vs tabelas com RLS'"
else
  SAIDA="$(cd "$R" && bash -c "$BLOCO" 2>&1)"
  for t in aberta_tab aberta_esp; do
    case "$SAIDA" in
      *"$t"*) ok "acusa $t, criada sem RLS com separador fora do padrão" ;;
      *) falha "o fallback não acusou $t; saiu: $(printf '%s' "${SAIDA:-<vazio>}" | tr '\n' ' ')" ;;
    esac
  done
  for t in tab_tab espacos; do
    case "$SAIDA" in
      *"$t"*) falha "acusou $t, que tem RLS (separador com tab ou vários espaços)" ;;
      *) ok "não acusa $t, protegida com separador fora do padrão" ;;
    esac
  done
fi

echo "== collect.sh: migration com espaço ou acento no nome é lida =="
# O `$MIG_FILES` sem aspas partia "001 init.sql" em dois caminhos que não existem, e o
# git citava "ação.sql" com escape octal: nos dois casos a tabela sem RLS sumia calada.
repo nomes
arquivo "supabase/migrations/001 init.sql" 'create table public.aberta_espaco (id int);
create policy p on public.aberta_espaco using (true);'
arquivo "supabase/migrations/002 ação.sql" 'create table public.aberta_acento (id int);'
roda 6
for t in aberta_espaco aberta_acento; do
  jq -e --arg t "$t" '[.findings[] | select(.pilar=="02" and .severity=="HIGH" and (.detail | test($t)))] | length > 0' \
       "$TMP/out-6/findings.json" >/dev/null 2>&1 \
    && ok "modo completo: o finding cita $t" || falha "modo completo: a tabela sem RLS $t não virou finding"
done
jq -e '[.findings[] | select(.pilar=="02" and (.title | test("USING \\(true\\)")))] | length > 0' \
     "$TMP/out-6/findings.json" >/dev/null 2>&1 \
  && ok "modo completo: o USING (true) do arquivo com espaço conta" || falha "o USING (true) de '001 init.sql' não contou"

BASE="$(git -C "$R" rev-parse HEAD)"
printf 'create table public.nova_espaco (id int);\n' > "$R/supabase/migrations/003 nova ação.sql"
roda 7 --diff "$BASE"
jq -e '[.findings[] | select(.pilar=="02" and .severity=="HIGH" and (.detail | test("nova_espaco")))] | length > 0' \
     "$TMP/out-7/findings.json" >/dev/null 2>&1 \
  && ok "--diff: a migration untracked com espaço e acento vira finding" \
  || falha "--diff: a tabela de '003 nova ação.sql' não virou finding ($COB)"

echo "== migrations fora de supabase/migrations: a pasta é descoberta, não fixa =="
# Em três pentests de 11/2026 as migrations moravam em src/db/migrations, src/sql e
# <app>/supabase/migrations. O pilar 02 saía nao_medido e a classe mais grave passava calada.
for pasta in src/db/migrations src/sql app/supabase/migrations; do
  nome="desc-$(printf '%s' "$pasta" | tr '/' '-')"
  repo "$nome"
  arquivo "$pasta/001_exposta.sql" 'create table public.exposta_desc (id int);'
  roda "$nome"
  case "$COB" in
    medido*"$pasta"*) ok "$pasta é lida: $COB" ;;
    *) falha "$pasta não foi lida: ${COB:-<ausente>}" ;;
  esac
  jq -e '[.findings[] | select(.pilar=="02" and .severity=="HIGH" and (.detail | test("exposta_desc")))] | length > 0' \
       "$TMP/out-$nome/findings.json" >/dev/null 2>&1 \
    && ok "$pasta: a tabela sem RLS vira finding" || falha "$pasta: a tabela sem RLS não virou finding"
done

echo "== .sql de teste e .sql solto não são migration =="
repo desc-ruido
arquivo src/sql/tests/001_caso.test.sql 'create table public.so_de_teste (id int);'
arquivo docs/consulta.sql 'create table public.so_de_doc (id int);'
roda desc-ruido
case "$COB" in
  nao_medido*"RLS não medido"*) ok "pasta de teste e .sql solto não contam: $COB" ;;
  *) falha "tomou .sql de teste ou de doc por migration: ${COB:-<ausente>}" ;;
esac

echo "== pilar 05: sem pasta de migration, índice é nao_medido, não 'medido: 0' =="
repo idx-sem-pasta
bash "$SCRIPT" --root "$R" --out "$TMP/out-idx" --pilar 05,07 >/dev/null 2>&1
I="$(jq -r '.coverage[] | select(.pilar=="05" and .check=="indices") | "\(.status) | \(.reason)"' "$TMP/out-idx/findings.json" 2>/dev/null)"
case "$I" in nao_medido*) ok "indices: $I" ;; *) falha "indices sem pasta: ${I:-<ausente>} (esperado nao_medido)" ;; esac
repo idx-src-sql
arquivo src/sql/001.sql 'create table public.t (id int); alter table public.t enable row level security;
create index t_id on public.t (id);'
bash "$SCRIPT" --root "$R" --out "$TMP/out-idx2" --pilar 05,07 >/dev/null 2>&1
I="$(jq -r '.coverage[] | select(.pilar=="05" and .check=="indices") | "\(.status) | \(.reason)"' "$TMP/out-idx2/findings.json" 2>/dev/null)"
case "$I" in medido*"1 CREATE INDEX"*src/sql*) ok "indices: $I" ;; *) falha "indices em src/sql: ${I:-<ausente>} (esperado medido, 1 CREATE INDEX, src/sql)" ;; esac

echo "== estado-do-banco.sql e matriz-rls.sql: só leitura, por construção =="
# O CI não tem banco: o que dá para travar aqui é que os dois arquivos abrem transação read
# only, terminam em rollback e não trazem comando que escreve. Eles rodam em produção.
for sql in estado-do-banco.sql matriz-rls.sql; do
  f="$(dirname "$SCRIPT")/$sql"
  [ -f "$f" ] || { falha "$sql não existe ao lado do collect.sh"; continue; }
  grep -qiE '^begin transaction read only;' "$f" && ok "$sql abre transação read only" || falha "$sql não abre 'begin transaction read only;'"
  [ "$(grep -vE '^[[:space:]]*(--|$)' "$f" | tail -1)" = "rollback;" ] && ok "$sql termina em rollback" || falha "$sql não termina em rollback;"
  escreve="$(grep -vE '^[[:space:]]*(--|\\)' "$f" | grep -inE '^[[:space:]]*(insert|update|delete|truncate|drop|alter|create|grant|revoke|copy|call|do|commit|merge)\b' | head -3)"
  [ -z "$escreve" ] && ok "$sql não tem comando que escreve" || falha "$sql tem comando que escreve: $escreve"
  grep -vE '^[[:space:]]*--' "$f" | grep -qiE 'set[[:space:]]+(local[[:space:]]+)?role[[:space:]]+(postgres|service_role|supabase_admin)' \
    && falha "$sql assume papel privilegiado" || ok "$sql não assume papel privilegiado"
done
grep -q 'estado-do-banco.sql' "$BANCO" && ok "02-banco.md aponta o estado-do-banco.sql" || falha "02-banco.md não cita o estado-do-banco.sql"

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
