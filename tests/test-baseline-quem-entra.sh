#!/usr/bin/env bash
# quem-entra.py (pilar 03 da baseline, também lido pelo secscan e pela auditoria-seguranca).
#
# Dois pentests de 11/2026 acharam o mesmo caminho em sistemas com RLS certa em todas as
# tabelas: cadastro do Auth aberto + autorização que confia em "estar autenticado" ou em
# user_metadata. Nenhuma skill do kit via o caminho inteiro:
#   - o bloco [auth] do config.toml não era lido, e sem config.toml a varredura calava;
#   - o grep de user_metadata era só de *.ts e não casava raw_user_meta_data do trigger em .sql;
#   - "auth.role() = 'authenticated'" e "<getter>() is not null" passavam como RLS correta;
#   - o trigger que cria a ficha de acesso com papel padrão não era cruzado com a policy.
# E o grep cru acusava o que a migration seguinte já tinha corrigido, ou lia o _apply_all.sql
# concatenado como se fosse a definição efetiva.
#
# Este teste monta três projetos sintéticos: vulnerável (cada check tem que disparar), o
# mesmo corrigido por migration posterior (os achados corrigidos têm que sumir) e um sem
# config.toml (o cadastro tem que sair "nao_medido", nunca calado). Também confere que o
# collect.sh leva os achados para o pilar 03 e sai 1 com HIGH.
#
# Uso: bash tests/test-baseline-quem-entra.sh [quem-entra.py] [collect.sh]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
QE="${1:-$RAIZ/plugin/skills/baseline/scripts/quem-entra.py}"
COLLECT="${2:-$RAIZ/plugin/skills/baseline/scripts/collect.sh}"
[ -f "$QE" ] || { echo "script não encontrado: $QE"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 ausente"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq ausente — o collect.sh depende dele"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/quem-entra.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
grava() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
tem()   { grep -q "$(printf 'ACHADO\t%s\t%s\t' "$2" "$3")" "$1"; }   # tem <saida> <sev> <check>
tem_check() { grep -q "$(printf '\t%s\t' "$2")" "$1"; }                 # qualquer severidade
cob()   { grep -q "$(printf 'COBERTURA\t%s\t%s\t' "$2" "$3")" "$1"; }

# ───────────── projeto vulnerável
V="$TMP/vuln"
printf '{"name":"fixture"}\n' | grava "$V/package.json"
grava "$V/supabase/config.toml" <<'EOF'
[auth]
enabled = true
site_url = "http://127.0.0.1:3000"
enable_signup = true
minimum_password_length = 6
password_requirements = ""

[auth.email]
enable_signup = true
enable_confirmations = false
EOF
grava "$V/supabase/migrations/0001_base.sql" <<'EOF'
create table profiles (id uuid primary key, role text, ativo boolean default true);
create table liberacoes (usuario_id uuid, modulo text);
create table fichas (id uuid primary key, papel text);
create table mensagens (id bigint, conversa_id bigint, criado_em timestamptz);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, role)
  values (new.id, coalesce((new.raw_user_meta_data->>'role'), 'membro'));
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_membro() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid());
$$;

create or replace function public.papel_ficha() returns text
language sql stable security definer set search_path = public as $$
  select papel from fichas where id = auth.uid();
$$;

create or replace function public.provisiona_ficha() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into fichas (id, papel)
  select new.usuario_id, case when new.modulo = 'fin' then 'financeiro' else 'coordenador' end;
  return new;
end;
$$;
create trigger trg_provisiona after insert on liberacoes
  for each row execute function public.provisiona_ficha();

create or replace function public.meu_email() returns text
language sql stable as $$ select lower(auth.jwt() ->> 'email'); $$;

alter table profiles enable row level security;
drop policy if exists "todos veem perfis" on profiles;
create policy "todos veem perfis" on profiles for select using (auth.role() = 'authenticated');
create policy "membro edita" on profiles for update to authenticated using (is_membro());

do $$ declare t text; begin
  foreach t in array array['contatos','eventos'] loop
    execute format('create policy "leitura com ficha" on public.%I for select to authenticated using (papel_ficha() is not null)', t);
  end loop;
end $$;

drop policy if exists mensagens_inserir on public.mensagens;
create policy mensagens_inserir on public.mensagens
  for insert to authenticated with check (true);
EOF
grava "$V/src/lib/hmac.ts" <<'EOF'
import { createHmac, timingSafeEqual } from "node:crypto";
export function confere(corpo: string, assinatura: string, segredo: string) {
  const esperado = createHmac("sha256", segredo).update(corpo).digest("hex");
  return timingSafeEqual(Buffer.from(esperado), Buffer.from(assinatura));
}
EOF
grava "$V/src/app/api/feed/route.ts" <<'EOF'
export async function GET(req: Request) {
  const url = new URL(req.url);
  if (url.searchParams.get("secret") !== process.env.FEED_SECRET) return new Response(null, { status: 401 });
  return new Response("ok");
}
EOF
grava "$V/src/app/(painel)/loading.tsx" <<'EOF'
export default function Loading() { return null; }
EOF
grava "$V/src/app/(painel)/admin/page.tsx" <<'EOF'
import { redirect } from "next/navigation";
export default async function Admin() {
  const ok = await souAdmin();
  if (!ok) redirect("/");
  return null;
}
EOF
grava "$V/src/app/api/chat/route.ts" <<'EOF'
const LIMITE_DIARIO = 20;
export async function POST() {
  const { count } = await supabase
    .from("mensagens")
    .select("id", { count: "exact", head: true })
    .gte("criado_em", inicio);
  if ((count ?? 0) >= LIMITE_DIARIO) return new Response(null, { status: 429 });
  await supabase.from("perfis").update({ nome: "x" }).eq("id", id);
}
EOF
grava "$V/src/lib/cookies.ts" <<'EOF'
export const opcoesCookie = { domain: ".exemplo.com", maxAge: 34560000 }; // cookie de sessão
EOF
grava "$V/src/lib/papel.ts" <<'EOF'
export const papelDe = (user: any) => user.user_metadata?.role ?? "membro";
EOF

python3 -I "$QE" --root "$V" > "$TMP/v.tsv" 2>"$TMP/v.err"; rc=$?
echo "· projeto vulnerável (exit $rc)"
[ $rc -eq 0 ] && ok "sai 0" || falha "saiu $rc: $(head -3 "$TMP/v.err")"
for par in "MEDIUM auth_signup_aberto" "MEDIUM auth_sem_confirmacao" "MEDIUM auth_senha_curta" \
           "LOW auth_senha_sem_requisito" "HIGH papel_do_metadata" "HIGH papel_do_metadata_app" \
           "MEDIUM autoprovisao_acesso" "MEDIUM papel_sem_conta_ativa" "MEDIUM identidade_por_email" \
           "MEDIUM hmac_sem_janela" "LOW segredo_na_query" "LOW guard_depois_do_stream" \
           "MEDIUM cota_em_tabela_do_usuario" "LOW escrita_sem_conferir" "LOW cookie_longo" \
           "INFO cookie_dominio_mae"; do
  set -- $par
  tem "$TMP/v.tsv" "$1" "$2" && ok "$2 ($1)" || falha "$2 ($1) não disparou"
done
# auth.role() = 'authenticated' (leitura) é MEDIUM; update com is_membro() não entra como
# predicado de existência, mas o helper sem ativo sim. O laço format('... on public.%I ...')
# precisa ser lido como policy.
grep "autenticado_e_membro" "$TMP/v.tsv" | grep -q "todos veem perfis" \
  && ok "auth.role() = 'authenticated' acusado" || falha "auth.role() = 'authenticated' passou calado"
grep "autenticado_e_membro" "$TMP/v.tsv" | grep -q "leitura com ficha" \
  && ok "policy em laço format(... on public.%I) lida" || falha "policy em laço não foi lida"
grep -P 'ACHADO\tHIGH\tpapel_do_metadata_app' "$TMP/v.tsv" 2>/dev/null | grep -q "papel.ts" \
  || grep "papel_do_metadata_app" "$TMP/v.tsv" | grep -q "papel.ts" \
  && ok "user_metadata?.role no app acusado" || falha "user_metadata?.role no app passou"

# ───────────── o mesmo projeto, corrigido por migration posterior
F="$TMP/fix"
cp -R "$V" "$F"
grava "$F/supabase/migrations/0002_corrige.sql" <<'EOF'
-- o papel do cadastro é ignorado: toda conta nasce membro inativo
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, role, ativo) values (new.id, 'membro', false);
  return new;
end;
$$;
create or replace function public.is_membro() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and ativo);
$$;
drop policy if exists "todos veem perfis" on profiles;
create policy "todos veem perfis" on profiles for select using (is_membro());
EOF
grava "$F/supabase/migrations/_apply_all.sql" <<'EOF'
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer as $$
begin
  insert into profiles (id, role) values (new.id, coalesce(new.raw_user_meta_data->>'role', 'membro'));
  return new;
end;
$$;
EOF
python3 -I "$QE" --root "$F" > "$TMP/f.tsv" 2>"$TMP/f.err"; rc=$?
echo "· projeto corrigido por migration posterior (exit $rc)"
tem_check "$TMP/f.tsv" papel_do_metadata && grep "papel_do_metadata" "$TMP/f.tsv" | grep -v "papel.ts" | grep -q ACHADO \
  && falha "papel_do_metadata ainda acusado depois da correção (lido o _apply_all ou a 1ª definição?)" \
  || ok "papel_do_metadata some quando a função efetiva não lê o metadata"
grep "autenticado_e_membro" "$TMP/f.tsv" | grep -q "todos veem perfis" \
  && falha "policy recriada (drop + create) ainda acusada" || ok "drop + create na ordem do arquivo vale o create"
grep "papel_sem_conta_ativa" "$TMP/f.tsv" | grep -q "is_membro" \
  && falha "is_membro com ativo ainda acusado" || ok "helper com ativo não é acusado"
grep "autoprovisao_cadastro" "$TMP/f.tsv" | grep -q "^ACHADO	INFO" \
  && ok "conta que nasce inativa vira INFO" || falha "conta que nasce inativa não virou INFO"
cob "$TMP/f.tsv" sql_fora_do_padrao nao_medido \
  && ok "_apply_all.sql fora do padrão é ignorado e dito na cobertura" || falha "_apply_all.sql não foi para a cobertura"

# ───────────── sem config.toml: o cadastro é não medido, nunca calado
N="$TMP/semcfg"
cp -R "$V" "$N"; rm -f "$N/supabase/config.toml"
python3 -I "$QE" --root "$N" > "$TMP/n.tsv" 2>&1
echo "· projeto sem config.toml"
cob "$TMP/n.tsv" auth_config nao_medido && ok "auth_config sai nao_medido" || falha "sem config.toml o cadastro calou"
grep "autenticado_e_membro" "$TMP/n.tsv" | grep -q "não foi medido" \
  && ok "o achado de predicado diz que o cadastro não foi medido" || falha "o achado de predicado não cita o cadastro não medido"

# ───────────── integração no collect.sh (pilar 03)
if [ -f "$COLLECT" ]; then
  echo "· collect.sh --pilar 03"
  ( cd "$V" && git init -q -b main . && git config user.email t@t && git config user.name t \
      && git config commit.gpgsign false && git add -A && git commit -qm base ) >/dev/null 2>&1
  bash "$COLLECT" --root "$V" --out "$TMP/col" --pilar 03 >/dev/null 2>"$TMP/col.err"; rc=$?
  [ $rc -eq 1 ] && ok "collect sai 1 com HIGH do pilar 03" || falha "collect saiu $rc (esperado 1): $(head -2 "$TMP/col.err")"
  n="$(jq '[.findings[] | select(.pilar=="03" and (.ref|test("quem vira membro")))] | length' "$TMP/col/findings.json" 2>/dev/null)"
  [ "${n:-0}" -ge 10 ] && ok "$n achados do quem-entra no findings.json" || falha "só ${n:-0} achados do quem-entra no findings.json"
  jq -e '.coverage[] | select(.pilar=="03" and .check=="auth_config" and .status=="medido")' "$TMP/col/findings.json" >/dev/null 2>&1 \
    && ok "cobertura auth_config no findings.json" || falha "cobertura auth_config ausente no findings.json"
fi

# migrations em src/db/migrations: a pasta é descoberta (num pentest de 11/2026 ficou de fora)
D="$TMP/desc"; mkdir -p "$D/src/db/migrations"
printf '{"name":"fixture"}\n' > "$D/package.json"
cp "$V/supabase/migrations/"*.sql "$D/src/db/migrations/"
python3 -I "$QE" --root "$D" > "$TMP/desc.tsv" 2>&1
grep -qE '[1-9][0-9]* funções efetivas lidas' "$TMP/desc.tsv" \
  && ok "src/db/migrations é lida: $(grep -oE '[0-9]+ funções efetivas lidas' "$TMP/desc.tsv" | head -1)" \
  || falha "src/db/migrations não foi lida: $(grep -iE 'migrations|funções' "$TMP/desc.tsv" | head -2)"

echo
if [ $falhas -eq 0 ]; then echo "tudo verde"; exit 0; fi
echo "$falhas falha(s)"; exit 1
