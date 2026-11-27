#!/usr/bin/env bash
# familias-rpc.py (A3 da auditoria-seguranca).
#
# Num pentest de 11/2026 o controle vertical segurou em tudo, e o horizontal caiu duas vezes
# pelo mesmo motivo: numa família de funções que escrevem na mesma tabela, uma não conferia o
# dono (transferir) ou o escopo (salvar/editar), enquanto a irmã do lado conferia. O grep de
# handlers da A3 não vê função Postgres, e a leitura uma a uma não compara irmãs.
#
# Fixtures:
#   vuln      transferir só checa papel e carimba auth.uid() no SET (não é checagem); editar
#             confere o dono; o registro_salvar não confere nada e o registro_apagar chama helper;
#             função revogada do browser não é acusada; definer órfã que escreve sem olhar quem
#             chamou.
#   corrigido a migration seguinte recria transferir com o dono no WHERE e salvar com helper
#             por objeto: os dois achados somem (estado efetivo, não grep cru).
#   vazio     sem migrations, a cobertura sai nao_medido, nunca calada.
#
# Uso: bash tests/test-auditoria-familias.sh [familias-rpc.py]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
FR="${1:-$RAIZ/plugin/skills/auditoria-seguranca/scripts/familias-rpc.py}"
[ -f "$FR" ] || { echo "script não encontrado: $FR"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 ausente"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/familias.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
grava() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
acha()  { grep -q "$(printf 'ACHADO\t[A-Z]*\t%s\t' "$2")" "$1" && grep "$(printf '\t%s\t' "$2")" "$1" | grep -q -- "$3"; }

V="$TMP/vuln"
grava "$V/supabase/migrations/0001_base.sql" <<'EOF'
create table cartoes (id uuid primary key, responsavel uuid, estado text, atualizado_por uuid);
create table registros (id uuid primary key, cliente bigint, estado text);
create table carteira (cliente bigint, analista uuid);

create or replace function public.eh_gestao() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfis where id = auth.uid() and papel = 'admin')
$$;

create or replace function public.pode_escrever() returns boolean
language sql stable as $$ select true $$;

create or replace function public.perfil_ativo(p_perfil uuid) returns boolean
language sql stable as $$ select exists (select 1 from perfis where id = p_perfil and ativo) $$;

-- família em que ninguém confere dono: o escopo (carteira) mora noutra tabela
create table metas (id uuid primary key, cliente bigint, valor numeric);
create or replace function public.meta_editar(p_cliente bigint, p_valor numeric) returns void
language plpgsql security definer as $$
begin
  if not pode_escrever() then raise exception 'sem permissão'; end if;
  update metas set valor = p_valor where cliente = p_cliente;
end $$;
create or replace function public.meta_marcar(p_cliente bigint) returns void
language plpgsql security definer as $$
begin
  if not pode_escrever() then raise exception 'sem permissão'; end if;
  update metas set valor = 0 where cliente = p_cliente;
end $$;

-- irmã correta: confere o dono numa condição
create or replace function public.cartao_editar(p_id uuid, p_estado text) returns void
language plpgsql security definer set search_path = public as $$
declare v_eu uuid := auth.uid();
begin
  if not pode_escrever() then raise exception 'sem permissão'; end if;
  if not exists (select 1 from cartoes where id = p_id and responsavel = v_eu) and not eh_gestao() then
    raise exception 'Só o responsável edita';
  end if;
  update cartoes set estado = p_estado where id = p_id;
end $$;

-- o furo: checa papel, valida destino e carimba auth.uid() no SET, mas nunca confere o dono
create or replace function public.cartao_transferir(p_id uuid, p_para uuid) returns json
language plpgsql security definer set search_path = public as $$
begin
  if not pode_escrever() then raise exception 'sem permissão'; end if;
  if p_para is null or not perfil_ativo(p_para) then raise exception 'destino inválido'; end if;
  update cartoes set responsavel = p_para, atualizado_por = auth.uid() where id = p_id;
  return json_build_object('ok', true);
end $$;

-- família 2: apagar é da gestão; salvar não confere nada
create or replace function public.registro_apagar(p_cliente bigint) returns void
language plpgsql security definer as $$
begin
  if not eh_gestao() then raise exception 'é da gestão'; end if;
  delete from registros where cliente = p_cliente;
end $$;

create or replace function public.registro_salvar(p_cliente bigint, p_estado text) returns void
language plpgsql security definer as $$
begin
  insert into registros (id, cliente, estado) values (gen_random_uuid(), p_cliente, p_estado)
  on conflict (id) do update set estado = excluded.estado;
end $$;

-- interna, sem checagem, mas revogada do browser: não é acusada
create or replace function public.registro_job(p_cliente bigint) returns void
language plpgsql security definer as $$
begin
  update registros set estado = 'x' where cliente = p_cliente;
end $$;
revoke execute on function public.registro_job(bigint) from public, anon, authenticated;

-- definer sozinha na tabela, escreve sem olhar quem chamou
create or replace function public.carteira_reset(p_cliente bigint) returns void
language plpgsql security definer as $$
begin
  delete from carteira where cliente = p_cliente;
end $$;
EOF

python3 -I "$FR" --root "$V" > "$TMP/v.out" 2>&1; rc=$?
[ $rc -eq 0 ] && ok "exit 0 no projeto vulnerável" || falha "exit $rc no vulnerável: $(cat "$TMP/v.out")"
acha "$TMP/v.out" familia_sem_dono cartao_transferir \
  && ok "transferir sem dono, com irmã que confere, é acusado" || falha "transferir não acusado: $(cat "$TMP/v.out")"
acha "$TMP/v.out" familia_toda_sem_dono metas \
  && ok "família em que nenhuma função confere dono sai como aviso" || falha "família toda sem dono calou"
grep "$(printf '\tcartao_transferir\t')" "$TMP/v.out" | grep -q 'dono=nao' \
  && ok "helper do destino (perfil_ativo(p_para)) não conta como dono" || falha "helper do destino contou como dono"
acha "$TMP/v.out" familia_sem_checagem registro_salvar \
  && ok "salvar sem checagem nenhuma, com irmã que checa, é acusado" || falha "salvar não acusado"
grep -q "$(printf 'ACHADO.*\tcartao_editar escreve')" "$TMP/v.out" && falha "editar (correto) foi acusado" || ok "irmã correta não é acusada"
grep "$(printf '\tcartao_transferir\t')" "$TMP/v.out" | grep -q 'dono=nao' \
  && ok "auth.uid() no SET não conta como conferir o dono" || falha "carimbo no SET contou como checagem"
grep "$(printf '\tcartao_editar\t')" "$TMP/v.out" | grep -q 'dono=sim' \
  && ok "variável tirada de auth.uid() numa condição conta como dono" || falha "v_eu não reconhecido"
grep -q "ACHADO.*registro_job" "$TMP/v.out" && falha "função revogada do browser acusada" || ok "função revogada não é acusada"
grep "$(printf '\tregistro_job\t')" "$TMP/v.out" | grep -q 'exposto=nao' \
  && ok "revoke do browser marca exposto=nao" || falha "revoke não lido"
acha "$TMP/v.out" definer_escreve_sem_chamador carteira_reset \
  && ok "definer que escreve sem olhar o chamador é acusada" || falha "definer órfã não acusada"
grep -q "$(printf 'COBERTURA\tfamilias_rpc\tmedido_migrations')" "$TMP/v.out" \
  && ok "cobertura diz que mediu as migrations" || falha "sem linha de cobertura"

C="$TMP/corrigido"
cp -R "$V" "$C"
grava "$C/supabase/migrations/0002_fix.sql" <<'EOF'
create or replace function public.pode_mexer_registro(p_cliente bigint) returns boolean
language sql stable security definer as $$
  select exists (select 1 from carteira where cliente = p_cliente and analista = auth.uid())
$$;

create or replace function public.cartao_transferir(p_id uuid, p_para uuid) returns json
language plpgsql security definer set search_path = public as $$
begin
  update cartoes set responsavel = p_para, atualizado_por = auth.uid()
   where id = p_id and (responsavel = auth.uid() or eh_gestao());
  if not found then raise exception 'Essa atividade é de outro responsável'; end if;
  return json_build_object('ok', true);
end $$;

create or replace function public.registro_salvar(p_cliente bigint, p_estado text) returns void
language plpgsql security definer as $$
begin
  if not pode_mexer_registro(p_cliente) then raise exception 'não é da sua carteira'; end if;
  insert into registros (id, cliente, estado) values (gen_random_uuid(), p_cliente, p_estado);
end $$;

drop function if exists public.carteira_reset(bigint);
EOF
python3 -I "$FR" --root "$C" > "$TMP/c.out" 2>&1
# sem isto, um script quebrado passaria nos "some" abaixo por não imprimir nada
grep -q "$(printf 'MATRIZ\tcartoes\tcartao_transferir\t')" "$TMP/c.out" \
  && ok "corrigido: a matriz ainda lista transferir" || falha "corrigido não rodou: $(cat "$TMP/c.out")"
grep -q "ACHADO.*cartao_transferir" "$TMP/c.out" && falha "transferir corrigido segue acusado: $(cat "$TMP/c.out")" \
  || ok "transferir recriado com dono no WHERE some (última definição vence)"
grep -q "ACHADO.*registro_salvar" "$TMP/c.out" && falha "salvar corrigido segue acusado" \
  || ok "helper por objeto (pode_mexer_registro(p_cliente)) conta como dono"
grep -q "carteira_reset" "$TMP/c.out" && falha "função dropada ainda aparece" || ok "drop function tira a função do estado efetivo"

E="$TMP/vazio"; mkdir -p "$E"
python3 -I "$FR" --root "$E" > "$TMP/e.out" 2>&1
grep -q "$(printf 'COBERTURA\tfamilias_rpc\tnao_medido')" "$TMP/e.out" \
  && ok "sem migrations sai nao_medido" || falha "sem migrations calou: $(cat "$TMP/e.out")"

# migrations fora das quatro pastas fixas: num pentest de 11/2026 elas moravam em
# src/db/migrations e o script lia zero função, calado atrás de um nao_medido
for pasta in src/db/migrations src/sql; do
  D="$TMP/desc-$(printf '%s' "$pasta" | tr '/' '-')"
  mkdir -p "$D/$pasta"; cp "$V/supabase/migrations/"*.sql "$D/$pasta/"
  python3 -I "$FR" --root "$D" > "$TMP/d.out" 2>&1
  grep -q "$(printf 'COBERTURA\tfamilias_rpc\tmedido')" "$TMP/d.out" \
    && ok "$pasta é lida" || falha "$pasta não foi lida: $(grep COBERTURA "$TMP/d.out")"
  grep -q '^ACHADO' "$TMP/d.out" && ok "$pasta: os achados do projeto vulnerável aparecem" || falha "$pasta: nenhum achado"
done

echo
[ $falhas -eq 0 ] && echo "test-auditoria-familias: tudo ok" || echo "test-auditoria-familias: $falhas falha(s)"
exit $falhas
