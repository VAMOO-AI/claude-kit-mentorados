-- baseline · matriz-rls — o que um papel REAL lê, tabela por tabela, com o denominador ao lado.
--
-- Personifica um usuário que já existe, sem token e sem criar conta: as funções de policy leem
-- `auth.uid()` de `request.jwt.claims`. Tudo numa transação `read only` que termina em
-- `rollback`. Mede LEITURA. Escrita (insert, update, delete, RPC que grava) não se testa aqui:
-- só no Supabase local, porque trigger com efeito externo (fila HTTP, notificação) dispara
-- antes do rollback.
--
-- Por que existe: em três pentests de 11/2026 a prova que decidiu foi esta, e as skills não a
-- tinham. Dois falsos positivos vieram de "0 linhas" sem denominador (a conta de teste não
-- tinha dado nenhum), e para chegar na prova com JWT o pentest criou contas em produção.
--
--   psql "$SUPABASE_DB_URL_RO" -X -v ator=<uuid> -f matriz-rls.sql
--   psql "$SUPABASE_DB_URL_RO" -X -v ator=anon   -f matriz-rls.sql        (visitante sem login)
--   … -v alvos='^(crm_|v_)'        só objetos cujo nome casa a regex (padrão: todos de public)
--   … -v claims='{"aal":"aal2"}'   claims a mais no JWT simulado (MFA, app_metadata)
--
-- Regras:
--   · O ator é um usuário EXISTENTE do papel que se quer medir, achado por consulta de perfil.
--     O id não entra no relatório: em `fonte` vai "personificação de <papel>, transação read
--     only, contagem por objeto".
--   · Matriz mínima: o papel mais restrito, um papel intermediário com subordinado, o admin e
--     uma conta SEM vínculo (sem organização, sem carteira). É ela que pega o helper que falha
--     aberto e o papel global solto em OR.
--   · `existem = 0` não prova nada: a linha sai "sem denominador". `ator_le = 0` só vale quando
--     `existem > 0`. Para saber quanto DEVERIA ler, conte o que é do ator (como dono, por fora).
--   · `leitura` é o que a matriz enxerga, não o veredito: "lê tudo" numa tabela de catálogo é
--     o esperado, e numa tabela de inquilino é o achado.
--   · Objeto que o papel não tem grant para ler sai "sem grant" e não é consultado. View
--     invoker sobre tabela sem grant aborta a transação: restrinja com -v alvos.
--   · O executor tem de ser psql (usa \gset e \if). Saída colada no relatório com o comando.

\if :{?ator}
\else
  \echo 'ERRO: passe -v ator=<uuid de um usuário existente> ou -v ator=anon'
  \quit
\endif
\if :{?alvos}
\else
  \set alvos '.'
\endif
\if :{?claims}
\else
  \set claims '{}'
\endif

begin transaction read only;

-- 1. denominador: quantas linhas existem, contadas como o dono (antes de trocar de papel)
select coalesce(json_object_agg(c.relname,
         (xpath('/row/n/text()',
                query_to_xml(format('select count(*) as n from %I.%I', n.nspname, c.relname), false, true, '')
               ))[1]::text::bigint), '{}'::json)::text as totais
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm') and c.relname ~ :'alvos'
\gset

-- 2. vira o ator. Os dois formatos de claim: o `auth.uid()` atual lê `request.jwt.claims`
--    (JSON), o antigo lê `request.jwt.claim.sub`. Preencher só um deixa o uid nulo no outro, e
--    a matriz sai toda "nada" com cara de RLS funcionando.
select (:'ator' = 'anon') as eh_anon \gset
\if :eh_anon
  select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true) is not null
     and set_config('request.jwt.claim.role', 'anon', true) is not null
     and set_config('request.jwt.claim.sub', '', true) is not null as claims_simuladas \gset
  set local role anon;
\else
  select set_config('request.jwt.claims',
           (json_build_object('sub', :'ator', 'role', 'authenticated')::jsonb || :'claims'::jsonb)::text,
           true) is not null
     and set_config('request.jwt.claim.role', 'authenticated', true) is not null
     and set_config('request.jwt.claim.sub', :'ator', true) is not null as claims_simuladas \gset
  set local role authenticated;
\endif

-- 3. prova de identidade, pelo próprio auth.uid(). `identidade_ok = f` invalida a medição:
--    nada do que vem abaixo vale, e o resultado é nao_medido.
\echo
\echo '== quem está lendo (identidade_ok = f invalida tudo abaixo)'
select current_user as papel,
       case when :'ator' = 'anon' then current_user = 'anon' and auth.uid() is null
            else current_user = 'authenticated' and auth.uid()::text = :'ator' end as identidade_ok,
       current_setting('transaction_read_only') as read_only;

-- 4. a matriz
\echo
\echo '== o que o ator lê × o que existe'
with medido as (
  select c.relname as objeto,
         case c.relkind when 'r' then 'tabela' when 'p' then 'particionada' when 'v' then 'view'
              when 'm' then 'mat. view' end as tipo,
         (:'totais'::json ->> c.relname)::bigint as existem,
         case when has_table_privilege(current_user, c.oid, 'SELECT') then
           (xpath('/row/n/text()',
                  query_to_xml(format('select count(*) as n from %I.%I', n.nspname, c.relname), false, true, '')
                 ))[1]::text::bigint
         end as ator_le
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm') and c.relname ~ :'alvos'
)
select objeto, tipo, existem, ator_le,
       case when ator_le is null then 'sem grant'
            when ator_le > existem then 'lê ' || ator_le || ' (o objeto filtra pelo chamador: o dono vê menos)'
            when existem = 0 then 'sem denominador (vazia): 0 não prova'
            when ator_le = 0 then 'nada'
            when ator_le = existem then 'lê tudo'
            else 'parte (' || round(100.0 * ator_le / existem) || '%)' end as leitura
  from medido
 order by (ator_le is not null and existem > 0 and ator_le = existem) desc, ator_le desc nulls last, objeto;

rollback;
