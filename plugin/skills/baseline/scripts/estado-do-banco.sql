-- baseline · estado-do-banco — o que o banco VIVO diz sobre quem lê, grava e executa.
--
-- Dona única destas consultas: secscan (Fase 2) e auditoria-seguranca (A1 a A3) apontam para
-- cá em vez de manter cópia. Nasceu de cinco pentests de 11/2026: cada classe abaixo passou por
-- uma skill que lia só as migrations, só o `anon` ou só a policy com `_read` no nome.
--
-- Só leitura. O arquivo abre uma transação `read only` e termina em `rollback`: qualquer
-- escrita falharia. Rode com psql, que imprime cada consulta do lote:
--
--   psql "$SUPABASE_DB_URL_RO" -X -f estado-do-banco.sql        (ou $SUPABASE_DB_URL)
--   ./scripts/db-query.sh --psql -f estado-do-banco.sql          (se o projeto tiver)
--
-- Executor que só devolve o último comando mostra só o `rollback`: isso é nao_medido.
-- Cada consulta LOCALIZA. A regra de leitura está no comentário dela, e quem decide é a
-- leitura da policy, da função ou da view apontada. Resultado vazio numa consulta é resposta
-- (anote "0 linhas"); consulta que deu erro é nao_medido.
--
-- Esquemas lidos: public (e storage.objects na Q8). Projeto com dado em outro esquema exposto
-- pela API: troque 'public' nas consultas e diga isso no relatório.

begin transaction read only;

-- ───────────────────────────────────────────────────────────────────────── Q1
-- Função SECURITY DEFINER que o navegador executa.
-- Toda função nova em public nasce com EXECUTE para anon e authenticated (default privileges
-- do Supabase). `revoke ... from public` NÃO tira esse grant: só `from anon, authenticated`.
-- Leitura: cada linha é decisão registrada (quem chama e por quê), não ruído aceito em bloco.
--   · chamada só pelo servidor (cofre, job, webhook): revogue dos dois e dê a service_role.
--   · usada_em_policy = true: revogue só de anon. Sem o EXECUTE do authenticated a policy
--     passa a falhar para todo mundo.
--   · dono com bypassrls e corpo sem auth.uid()/auth.jwt(): o argumento decide de quem é o dado.
\echo
\echo '== Q1 · funções SECURITY DEFINER executáveis por anon/authenticated'
select p.oid::regprocedure                                    as funcao,
       pg_get_userbyid(p.proowner)                            as dono,
       has_function_privilege('anon', p.oid, 'execute')       as anon,
       has_function_privilege('authenticated', p.oid, 'execute') as autenticado,
       pg_get_functiondef(p.oid) ~* 'auth\.(uid|jwt|role)\(\)|request\.jwt' as cita_chamador,
       exists (select 1 from pg_policies x
                where coalesce(x.qual, '') || ' ' || coalesce(x.with_check, '')
                      ~ ('\m' || p.proname || '\M'))           as usada_em_policy
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosecdef and p.prokind = 'f'
   and (has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('authenticated', p.oid, 'execute'))
 order by 3 desc, 5, 1::text;

\echo
\echo '== Q1b · default privileges (de onde o grant nasce)'
select defaclrole::regrole as de_quem_cria, defaclnamespace::regnamespace as esquema,
       case defaclobjtype when 'r' then 'tabela' when 'f' then 'função' when 'S' then 'sequência'
            else defaclobjtype::text end as objeto,
       defaclacl as acl
  from pg_default_acl
 where defaclnamespace = 'public'::regnamespace
 order by 1, 3;

-- ───────────────────────────────────────────────────────────────────────── Q2
-- Privilégio de tabela e view para anon e authenticated, além do SELECT de authenticated.
-- "RLS ligada sem policy" (lint 0008) só é deny-all para o que a RLS cobre. TRUNCATE,
-- REFERENCES e TRIGGER não passam por RLS, e view definer não tem RLS nenhuma.
-- No Supabase o grant padrão é TUDO para os dois papéis em toda tabela nova: quem protege é a
-- RLS. Por isso a coluna que importa é `fora_da_rls`, o que o papel pode e a RLS não segura:
-- tudo, em tabela sem RLS, view e materialized view; TRUNCATE, REFERENCES e TRIGGER, sempre.
-- Leitura: primeiro as linhas de tabela sem RLS e de view (vêm no topo). Depois, TRUNCATE para
-- anon ou authenticated em qualquer objeto pede `revoke` ou motivo escrito: um TRUNCATE pelo
-- navegador apaga a tabela inteira sem passar por policy.
\echo
\echo '== Q2 · o que anon/authenticated podem e a RLS não segura'
select c.relname as objeto,
       case c.relkind when 'r' then 'tabela' when 'v' then 'view' when 'm' then 'mat. view'
            when 'p' then 'particionada' end as tipo,
       c.relrowsecurity as rls,
       r.rolname as papel,
       string_agg(p.priv, ', ' order by p.ord)
         filter (where not (c.relkind in ('r', 'p') and c.relrowsecurity) or p.ord >= 5) as fora_da_rls,
       string_agg(p.priv, ', ' order by p.ord) as todos
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
 cross join (values ('anon'), ('authenticated')) r(rolname)
 cross join (values ('SELECT', 1), ('INSERT', 2), ('UPDATE', 3), ('DELETE', 4),
                    ('TRUNCATE', 5), ('REFERENCES', 6), ('TRIGGER', 7)) p(priv, ord)
 where c.relkind in ('r', 'v', 'm', 'p')
   and has_table_privilege(r.rolname, c.oid, p.priv)
 group by c.relname, c.relkind, c.relrowsecurity, r.rolname
having count(*) filter (where not (c.relkind in ('r', 'p') and c.relrowsecurity) or p.ord >= 5) > 0
 order by (c.relkind in ('r', 'p') and c.relrowsecurity), c.relkind, (r.rolname = 'anon') desc, 1;

-- ───────────────────────────────────────────────────────────────────────── Q3
-- Papel global decidindo linha de inquilino.
-- Helper de papel sem organização (has_role, is_admin, user_roles, o papel do JWT) dentro de
-- USING/WITH CHECK de tabela com coluna de inquilino tem de estar num AND com o predicado de
-- inquilino. Num ramo OR próprio vira passe livre entre inquilinos.
-- Leitura: para cada linha, ache o OR mais externo que contém o helper. Se nesse ramo não há
-- predicado de inquilino, é bypass de RLS entre inquilinos (CRITICAL). Depois pergunte quem
-- ganha o papel global: se o provisionamento de inquilino o concede a todo mundo, todo
-- inquilino é "gestor global".
\echo
\echo '== Q3 · policies que citam papel global (leia o OR)'
select schemaname as esquema, tablename as tabela, policyname as policy, cmd,
       (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ~* '\mor\M' as tem_or,
       left(coalesce(qual, ''), 200) as using_, left(coalesce(with_check, ''), 200) as with_check_
  from pg_policies
 where schemaname in ('public', 'storage')
   and (coalesce(qual, '') || ' ' || coalesce(with_check, ''))
       ~* 'has_role\(|is_admin\(|user_roles|app_metadata|->>\s*''role''|\mrole\M\s*='
 order by 5 desc, 2, 3;

-- ───────────────────────────────────────────────────────────────────────── Q4
-- O SELECT efetivo de uma tabela é o OR de TODAS as policies permissivas com cmd SELECT ou ALL.
-- Policy `FOR ALL` de escrita também vale para leitura: quem audita a `_read`, acha certa e
-- para de olhar perde o vazamento que vem da `_write`.
-- Leitura: toda tabela listada tem mais de uma policy liberando SELECT. Leia o USING de cada
-- uma; a mais frouxa vence. Vale igual para UPDATE e DELETE.
\echo
\echo '== Q4 · tabelas com mais de uma policy liberando SELECT'
select tablename as tabela,
       string_agg(policyname || ' [' || cmd || case when permissive = 'RESTRICTIVE' then ', restritiva' else '' end || ']',
                  ' · ' order by policyname) as quem_libera_select
  from pg_policies
 where schemaname = 'public' and cmd in ('SELECT', 'ALL')
 group by 1 having count(*) filter (where permissive = 'PERMISSIVE') > 1
 order by 1;

-- ───────────────────────────────────────────────────────────────────────── Q5
-- Cobertura por comando. Tabela com RLS e sem policy para um comando nega o comando calada:
-- o PostgREST responde 204 e o cliente trata como sucesso.
-- Leitura: `false` em coluna de comando que o app expõe ("apagar", "editar") é bug funcional
-- (o usuário vê sucesso e o dado continua lá); como segurança é LOW. Tabela com as quatro em
-- `false` é deny-all: confira com a Q2 se o grant também está fechado.
\echo
\echo '== Q5 · tabelas com RLS sem policy para algum comando'
select c.relname as tabela,
       coalesce(bool_or(p.cmd in ('SELECT', 'ALL')), false) as sel,
       coalesce(bool_or(p.cmd in ('INSERT', 'ALL')), false) as ins,
       coalesce(bool_or(p.cmd in ('UPDATE', 'ALL')), false) as upd,
       coalesce(bool_or(p.cmd in ('DELETE', 'ALL')), false) as del
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_policies p on p.schemaname = n.nspname and p.tablename = c.relname
 where n.nspname = 'public' and c.relkind in ('r', 'p') and c.relrowsecurity
 group by 1
having not (coalesce(bool_or(p.cmd in ('SELECT', 'ALL')), false)
        and coalesce(bool_or(p.cmd in ('INSERT', 'ALL')), false)
        and coalesce(bool_or(p.cmd in ('UPDATE', 'ALL')), false)
        and coalesce(bool_or(p.cmd in ('DELETE', 'ALL')), false))
 order by 1;

-- ───────────────────────────────────────────────────────────────────────── Q6
-- View que roda como o dono (sem security_invoker) e é legível pelo navegador.
-- Rodar como dono é legítimo quando a view expõe parte de uma tabela que o usuário não lê
-- (status sem o segredo, agregado de BI): trocar para invoker nesse caso ZERA a view para
-- todos. O achado é a view definer sem predicado de porta ao lado de irmãs que têm.
-- Leitura: `tem_porta = nao` com anon_le ou auth_le = true é o candidato. A justificativa em
-- `comment on view` explica o definer, não quem lê. Antes de propor invoker, meça o que a view
-- devolve por papel hoje (matriz-rls.sql). `tem_porta` é heurística: procura auth.uid(),
-- auth.jwt() ou uma função de public que os cite; predicado por outro caminho sai `nao`.
\echo
\echo '== Q6 · views que rodam como dono, e se a definição olha o chamador'
with portoes as (
  select p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f'
     and pg_get_functiondef(p.oid) ~* 'auth\.(uid|jwt|role)\(\)|request\.jwt'
)
select c.relname as view_,
       pg_get_userbyid(c.relowner) as dono,
       coalesce(array_to_string(c.reloptions, ','), '(nenhuma)') as opcoes,
       has_table_privilege('anon', c.oid, 'SELECT') as anon_le,
       has_table_privilege('authenticated', c.oid, 'SELECT') as auth_le,
       case when pg_get_viewdef(c.oid) ~* 'auth\.(uid|jwt|role)\(\)|request\.jwt'
              or exists (select 1 from portoes g
                          where pg_get_viewdef(c.oid) ~* ('\m' || g.proname || '\s*\('))
            then 'sim' else 'nao' end as tem_porta
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'v'
   and not coalesce(c.reloptions::text[] && array['security_invoker=true', 'security_invoker=on',
                                                   'security_invoker=1', 'security_invoker=yes'], false)
 order by 6, 1;

-- ───────────────────────────────────────────────────────────────────────── Q7
-- Escrita que só tem policy PERMISSIVE: candidata a "papel imposto só na aplicação".
-- Se o app exige papel (admin, gestor) na server action e a policy só confere inquilino,
-- qualquer usuário do inquilino grava direto pelo PostgREST.
-- Leitura: cruze com o mapa de papéis do app, tabela por tabela. É achado só onde TODO caminho
-- de escrita do app exige papel fixo. Se um papel comum grava pela regra do app, a tabela não
-- tem o que restringir. Testar com admin não mede papel.
\echo
\echo '== Q7 · tabelas cuja escrita só tem policy permissiva'
select tablename as tabela, cmd, count(*) as policies
  from pg_policies
 where schemaname = 'public' and cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
 group by 1, 2 having bool_and(permissive = 'PERMISSIVE')
 order by 1, 2;

-- ───────────────────────────────────────────────────────────────────────── Q8
-- Posse em storage.objects. Policy de UPDATE/DELETE (ou ALL) que só exige "estar logado"
-- deixa um usuário trocar ou apagar o arquivo do outro.
-- Leitura: `cita_posse = false` em UPDATE, DELETE ou ALL é o candidato. Posse aceita:
-- owner/owner_id = auth.uid(), (storage.foldername(name))[1] = auth.uid()::text, ou o id do
-- perfil no nome do arquivo. Policy de SELECT que faz EXISTS em outra tabela herda a RLS
-- daquela tabela: meça o raio pela matriz.
\echo
\echo '== Q8 · policies de storage.objects e se citam posse'
select policyname as policy, cmd, roles::text as papeis,
       (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ~* 'auth\.uid\(\)|owner' as cita_posse,
       left(coalesce(qual, with_check, ''), 200) as predicado
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects'
 order by 4, 2, 1;

-- ───────────────────────────────────────────────────────────────────────── Q9
-- Auto-inscrição na tabela de vínculo. Quem consegue INSERIR a própria linha em membros,
-- papéis ou vínculos vira membro (ou admin) da organização que escolher.
-- Leitura: a policy de INSERT ou ALL só pode aceitar a linha se o chamador JÁ for admin da
-- mesma organização da linha nova, ou for a plataforma. `user_id = auth.uid()` sozinho,
-- `auth.uid() is not null` e papel global em OR são o achado (CRITICAL). Tabela candidata:
-- tem coluna de usuário e coluna de organização ou de papel. Tabela de dado com as duas
-- colunas (lançamento, tarefa) também aparece: descarte na leitura. Linha sem policy quer
-- dizer que ninguém insere pelo navegador.
\echo
\echo '== Q9 · quem insere em tabela de vínculo (membros, papéis)'
with vinculo as (
  select c.table_name
    from information_schema.columns c
   where c.table_schema = 'public'
   group by 1
  having bool_or(c.column_name ~* '^(user_id|usuario_id|profile_id|member_id|auth_user_id)$')
     and bool_or(c.column_name ~* '^(org(anization)?_id|tenant_id|workspace_id|empresa_id|contractor_org_id|role|papel)$')
)
select v.table_name as tabela, p.policyname as policy, p.cmd,
       left(coalesce(p.with_check, p.qual, '(sem predicado)'), 220) as aceita_linha_quando
  from vinculo v
  left join pg_policies p on p.schemaname = 'public' and p.tablename = v.table_name
                         and p.cmd in ('INSERT', 'ALL')
 order by 1, 2;

-- ───────────────────────────────────────────────────────────────────────── Q10
-- "Inquilino nulo = global" na leitura. Policy de leitura com `<coluna de inquilino> IS NULL`
-- torna pública toda linha gravada sem inquilino, e o insert que esquece a coluna cria linha
-- global por omissão.
-- Leitura: para cada tabela listada, conte as linhas nulas (como dono) e procure no código os
-- inserts que não mandam a coluna. As duas coisas juntas são o achado (HIGH). Ao fechar a
-- escrita, conte e corrija as linhas nulas antigas antes: elas ficam só leitura para a dona.
\echo
\echo '== Q10 · policies de leitura com "inquilino IS NULL"'
select tablename as tabela, policyname as policy, cmd, left(qual, 220) as using_
  from pg_policies
 where schemaname = 'public' and cmd in ('SELECT', 'ALL')
   and qual ~* '(org|tenant|workspace|empresa|organization)\w*\s+is\s+null'
 order by 1, 2;

rollback;
