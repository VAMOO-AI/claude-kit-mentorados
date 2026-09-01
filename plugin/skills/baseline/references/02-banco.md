# 02 · Banco, RLS e estrutura de permissões

No Supabase o banco **é** a API. Toda tabela em schema exposto ao PostgREST está a
um `fetch` de distância de qualquer um com a anon key — que está no bundle, por
design. RLS não é uma camada extra: é a única camada.

## Contrato

- [ ] **Nenhuma materialized view do schema exposto é legível por `anon` ou
      `authenticated`.** Materialized view **não tem RLS** — não existe policy
      que a proteja. O Supabase concede `ALL ON ALL TABLES IN SCHEMA public` por
      padrão, o que está certo para tabela (a RLS decide a linha) e, para MV,
      **é** o acesso. Quem cria a primeira MV para um dashboard não tem como
      saber que acabou de publicar a tabela inteira.
- [ ] **100% das tabelas em schema exposto têm RLS habilitado.** Sem exceção
      silenciosa.
- [ ] **Toda tabela com RLS tem policy, ou é declarada deny-all intencional** no
      contrato do projeto. RLS ligado sem policy = ninguém lê exceto
      `service_role` — que é seguro, mas quebra no dia em que alguém precisar ler
      e não souber por quê.
- [ ] **Toda função `SECURITY DEFINER` tem `SET search_path`.** Sem isso é vetor
      de escalonamento de privilégio, e é pior quando a função é chamada de dentro
      de uma policy.
- [ ] **`USING (true)` e `security_invoker = false` exigem justificativa
      versionada.** Não são proibidos — são decisões, e decisão sem registro vira
      acidente.
- [ ] **Grants a `anon` inventariados.** Cada objeto legível sem login é uma
      escolha explícita.
- [ ] **Bucket com dado de usuário é privado**, acesso por URL assinada.
- [ ] Migration é a fonte de verdade: **SQL aplicado direto no banco vira
      migration no mesmo dia**, senão prod e repo divergem em silêncio.

## Como implementar

**Tabela nova — os dois statements andam juntos, no mesmo PR:**

```sql
create table public.pedidos (...);
alter table public.pedidos enable row level security;

-- e imediatamente a policy, ou o comentário dizendo que é deny-all de propósito
create policy "pedidos: dono lê"
  on public.pedidos for select to authenticated
  using (owner_id = (select auth.uid()));
```

`(select auth.uid())` em vez de `auth.uid()` puro: o planner avalia uma vez em
vez de por linha. Em tabela grande a diferença é de segundos. É o lint 0003.

**Função `SECURITY DEFINER` — o `set search_path` é parte da assinatura:**

```sql
create or replace function public.is_supervisor()
returns boolean
language sql
security definer
set search_path = ''            -- <- sem isso, a função é um vetor
stable
as $$ select exists (
  select 1 from public.user_profiles
  where id = (select auth.uid()) and role in ('ADMIN','DIRETOR','SUPERVISOR')
) $$;
```

Com `search_path = ''`, todo objeto precisa ser qualificado (`public.x`). É
chato e é o ponto: elimina a possibilidade de alguém plantar um `user_profiles`
num schema que venha antes no path.

**View que precisa furar RLS** — existe caso legítimo (agregação de BI sobre
tabelas que o usuário não lê linha a linha). O que não é legítimo é ela existir
sem registro:

```sql
create view public.v_faturamento_mensal
with (security_invoker = false)   -- roda com privilégio do dono
as select ...;

comment on view public.v_faturamento_mensal is
  'security_invoker=false intencional: agrega erp_faturamento, que o vendedor
   não lê linha a linha. Filtro por vendedor aplicado DENTRO da view.
   Aceito por Ruan em 2026-08-22. Revisar em 2027-02.';
```

O `comment on` é o melhor lugar: viaja com o objeto, aparece no `\d+`, e não
depende de alguém lembrar de abrir um markdown.

**Estrutura de permissões — o formato que funciona:**

| Camada | Onde | Papel |
|---|---|---|
| Papel do usuário | tabela `user_profiles.role` | fonte única |
| Permissão granular | tabela `role_permissions` (papel × chave) | editável sem deploy |
| Decisão de linha | policy RLS | **a que vale** |
| Decisão de tela | constante no front | cosmética — ver pilar 03 |

Papel em enum no código e permissão em tabela é a combinação que envelhece bem:
o enum dá autocomplete e o CHECK, a tabela permite mudar permissão sem release.

## Como provar

Os 28 lints do Supabase Security/Performance Advisor são SQL puro e open-source
(`github.com/supabase/splinter`). O script `scripts/splinter.sh` baixa em cache e
roda cada lint como **`select` puro — sem criar o schema `lint`, sem DDL no banco
auditado**:

```bash
bash ~/.claude/skills/baseline/scripts/splinter.sh          # todos
bash ~/.claude/skills/baseline/scripts/splinter.sh 0013 0010 0011   # só alguns
```

Os que mais importam:

| Lint | Nível | Pega |
|---|---|---|
| `0013_rls_disabled_in_public` | ERROR | tabela exposta sem RLS |
| `0010_security_definer_view` | ERROR | view que fura RLS |
| `0002_auth_users_exposed` | ERROR | `auth.users` legível pela API |
| `0015_rls_references_user_metadata` | ERROR | policy confiando em metadata que o usuário edita |
| `0023_sensitive_columns_exposed` | ERROR | coluna sensível na API |
| `0019_insecure_queue_exposed_in_api` | ERROR | fila pgmq exposta |
| `0021_fkey_to_auth_unique` | ERROR | FK pra `auth` sem unique |
| `0011_function_search_path_mutable` | WARN | `SECURITY DEFINER` sem `search_path` |
| `0024_rls_policy_always_true` | WARN | `USING (true)` |
| `0007_policy_exists_rls_disabled` | INFO | policy escrita mas RLS desligado — o pior dos mundos |
| `0008_rls_enabled_no_policy` | INFO | RLS ligado sem policy (deny-all) |
| `0003_auth_rls_initplan` | WARN | `auth.uid()` sem `select`, reavaliado por linha |
| `0001_unindexed_foreign_keys` / `0005_unused_index` | INFO | ver pilar 05 |

Sem acesso ao banco, o fallback é estático sobre `supabase/migrations/`:

```bash
# tabelas criadas vs tabelas com RLS
grep -rhoiE 'create table (if not exists )?(public\.)?[a-z0-9_]+' supabase/migrations | \
  grep -oE '[a-z0-9_]+$' | sort -u > /tmp/t.txt
grep -rhoiE 'alter table (public\.)?[a-z0-9_]+ enable row level security' supabase/migrations | \
  grep -oiE '[a-z0-9_]+ enable' | cut -d' ' -f1 | sort -u > /tmp/r.txt
comm -23 /tmp/t.txt /tmp/r.txt        # criadas e nunca protegidas

# SECURITY DEFINER sem search_path
grep -rn -A6 'security definer' supabase/migrations | \
  grep -B6 -L 'search_path' | head
```

**O fallback estático mente em dois sentidos** e o report tem que dizer isso:
policy aplicada pelo dashboard não está no repo, e migration revertida à mão
ainda está. Estático é `nao_medido` com ressalva, nunca `conforme`.

## Armadilhas

| Sintoma | Causa real |
|---|---|
| Query volta 200 com array vazio, sem erro | RLS negou. PostgREST não distingue "não existe" de "não pode ver" — é por design |
| "Object not found" no Storage | Bucket privado + sem URL assinada. Parece 404, é RLS |
| Vendedor via a base inteira | Hook de filtro retornava cedo, e a tabela tinha `USING (true) TO authenticated`. O gate era da UI; a policy autorizava tudo |
| Policy correta, comportamento errado | A função no banco não é a da migration. `select prosrc from pg_proc where proname = '...'` antes de qualquer diagnóstico |
| Migration nova quebrou prod na hora | Deploy do front é automático e foi junto. Migration que muda contrato de coluna entra **antes** do merge |
| Lint acusa `0007` | Alguém escreveu policy e esqueceu do `enable row level security`. A policy existe e não vale nada — pior que não ter |
| Cliente diz que "está tudo com RLS" | Confirme com `0013` no banco real. Migration é intenção, `pg_tables.rowsecurity` é fato |

## Migration que não derruba produção

RLS protege o dado de quem não devia ler. Esta seção protege o dado de quem
devia escrever: a migration certa, aplicada na ordem errada, derruba o app sem
tocar em nenhuma policy. No Supabase o deploy do front é automático e sai junto
com o merge, então "código velho rodando com schema novo" e "código novo
rodando com schema velho" são estados reais, não hipótese.

Checklist antes de aplicar qualquer migration em banco com dado:

- [ ] **Reversível.** Existe o caminho de volta e ele desfaz de verdade — não um
      arquivo `down` vazio. Se a volta perde dado (DROP, TRUNCATE, type que
      trunca), isso está escrito na migration, com o dono que aceitou.
- [ ] **NOT NULL só depois do backfill.** `ALTER TABLE … ADD COLUMN x NOT NULL`
      sem `DEFAULT` falha em tabela com linhas; com `DEFAULT` funciona e esconde
      o problema: toda linha antiga recebe um valor que ninguém escolheu. A
      ordem é ADD COLUMN nullable → backfill em lotes → `SET NOT NULL`. Três
      migrations, não uma.
- [ ] **Índice em tabela viva é `CREATE INDEX CONCURRENTLY`.** Sem o
      CONCURRENTLY o Postgres tranca a tabela pra escrita até o índice
      terminar. Em tabela de 100 mil linhas isso é segundos de app parado; em
      um milhão, minutos. CONCURRENTLY não roda dentro de transação, então a
      migration precisa de uma marcação que o runner respeite (no Supabase CLI,
      um arquivo só com esse statement).
- [ ] **Um ALTER por lock, não cinco.** Vários `ALTER TABLE` na mesma tabela
      viram um só statement com cláusulas separadas por vírgula. Cada ALTER
      separado adquire e solta o lock exclusivo, e cada aquisição espera as
      queries em voo terminarem.
- [ ] **Coluna que some passa por depreciação.** DROP COLUMN só depois que
      nenhum código lê a coluna em produção há pelo menos um deploy. Renomear é
      o mesmo caso com outro nome: o código antigo continua rodando com o nome
      antigo até o próximo deploy terminar. Renomeie criando a nova, copiando,
      trocando o código, e só então dropando a velha.
- [ ] **Foreign key nova tem índice.** O Postgres não cria índice na coluna que
      referencia. Sem ele, todo DELETE ou UPDATE na tabela referenciada faz
      seq scan na referenciadora pra checar a constraint.
- [ ] **A ordem entre schema e código está decidida.** Migration que ADICIONA
      (coluna, tabela, índice) vai antes do merge, porque o código novo
      depende dela e o código velho a ignora. Migration que REMOVE ou RENOMEIA
      vai depois de o código que parou de usar estar em produção. Migration que
      muda contrato de coluna que o front lê (tipo, nome, semântica) é a que
      mais quebra, e é a que o `ship` já exige antes do merge.

O `data-migration` do gstack (garrytan/gstack, MIT) é a origem desta lista; o
que mudou foi tirar Rails e pôr o cenário Supabase.
