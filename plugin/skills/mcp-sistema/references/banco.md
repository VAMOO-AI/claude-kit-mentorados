# Banco — liberação, trava do token OAuth, tabela de papel, auditoria

SQL avulso e migrations em prod rodam por script do projeto (nunca login
interativo da CLI). Toda prova de RLS roda em transação com `ROLLBACK`.

## 1. Liberação por pessoa (PR 1)

`code/sql/mcp-enabled.sql`: `mcp_enabled BOOLEAN NOT NULL DEFAULT false` na
tabela de usuários. Default `false` é o que contém o risco durante o rollout.

## 2. Tabela de papel sem escrita por sessão (ANTES do PR 1)

Audite a RLS da tabela de usuários e da tabela de negócio que liga a pessoa ao
time:

```sql
select tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename in ('app_users', '<tabela_de_negocio>');
```

Policy `FOR ALL TO authenticated USING (true)` nessas tabelas = qualquer logado
vira admin (muda `role`), se liga a outro registro (muda `auth_user_id`/time) ou
liga o próprio `mcp_enabled` pela API REST. Troque por: SELECT da própria linha
na tabela de usuários; SELECT na de negócio se o app lê com sessão; escrita só
por service role (rotas de admin). Modelo: `code/sql/tabela-papel-sem-escrita.sql`.
Antes, `grep` no app por escrita com sessão nessas tabelas — se existir, ela
tem que migrar para rota com service role no mesmo PR.

## 3. Trava "sem token oauth" (entre PR 1 e PR 2, antes da 2ª pessoa)

O access token do OAuth Server é um JWT `authenticated` com `client_id`. Sem
trava, o cliente MCP lê e grava direto no PostgREST, por fora das tools.

Liste as tabelas pelo catálogo (não de memória):

```sql
select distinct tablename
from pg_policies
where schemaname = 'public'
  and (roles && array['authenticated','public']::name[])
order by 1;
```

Aplique `code/sql/trava-token-oauth.sql` com essa lista + `storage.objects`.
RESTRICTIVE entra em AND com as policies existentes: só corta, nunca abre; a
sessão web não tem `client_id`, então nada muda no app.

Prova (em `BEGIN … ROLLBACK`):

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object(
  'sub', '<auth_user_id>', 'role', 'authenticated', 'email', '<email>')::text, true);
select count(*) from public.<tabela>;          -- sem client_id: igual ao app
select set_config('request.jwt.claims', json_build_object(
  'sub', '<auth_user_id>', 'role', 'authenticated', 'client_id', 'teste')::text, true);
select count(*) from public.<tabela>;          -- com client_id: 0
update public.<tabela> set <coluna> = <coluna>; -- com client_id: 0 linhas
rollback;
```

**Tabela nova aberta a `authenticated` entra na trava no mesmo PR que a cria.**
Registre isso na memória/AGENTS.md do projeto: é a regra que alguém vai esquecer.

## 4. Log de auditoria (PR 3)

`code/sql/mcp-audit-log.sql`: RLS ligada, nenhuma policy, `REVOKE` de anon e
authenticated — só service role lê e grava. A linha nasce com status `iniciado`
ANTES da gravação e fecha como `aplicado`/`falhou`.
