# auditoria-seguranca — A1 (inquilino), A2 (permissão no navegador) e A3 (IDOR)

Lido antes de auditar as categorias A1, A2 e A3.

## A1 — Banco sem tranca (isolamento de inquilino/dono)

Alvo: **toda** query de listagem, busca, agregação, relatório e exportação.
Agregação e exportação são as que mais escapam, porque não devolvem "um
registro" e por isso ninguém pensa nelas como vazamento — e são as que devolvem
o negócio inteiro do concorrente.

- Stack Supabase → RLS desligada, policy `using (true)`, `SECURITY DEFINER` sem
  `search_path` e MV legível estão na **Fase 2 do `secscan`**; use de lá. View sem
  `security_invoker` e policy `PERMISSIVE` duplicada o `secscan` não sonda: rode os
  lints da `baseline`, que são `select` puro:
  `bash "${CLAUDE_PLUGIN_ROOT}/skills/baseline/scripts/splinter.sh" 0010 0006`.
  Sem acesso ao banco, a cobertura da A1 diz que essas duas não foram medidas.

**Antes de qualquer policy, pergunte o que a RLS não alcança.** RLS, policy e
`SECURITY DEFINER` só falam de objetos onde RLS existe. **Materialized view não
tem RLS. Nunca.** Não há policy
que a proteja, e o Supabase concede `ALL ON ALL TABLES` no schema `public` por
padrão (`GRANT`s que o `pg_dump` do baseline costuma omitir e alguém restaura
depois). Para tabela isso está certo — a RLS decide a linha. Para MV, o `GRANT`
**é** o acesso, e o PostgREST publica.

```sql
-- MV legível por quem vem do browser. Zero linha aqui, ou é achado.
SELECT c.relname,
       has_table_privilege('anon',          c.oid, 'SELECT') AS anon,
       has_table_privilege('authenticated', c.oid, 'SELECT') AS authenticated
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'm';

-- o ACL cru, que mostra o GRANT amplo que ninguém lembra de ter dado
SELECT relname, relacl::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND relkind IN ('m','v') AND relacl::text LIKE '%anon=%';
```

O mesmo vale para **view que lê de MV**: `security_invoker` faz a coisa certa e
ainda entrega o dado, porque a permissão que ele respeita é justamente a que
está aberta. Provado em 01/09/2026 num projeto real: 180 de 180 tabelas com
RLS, 170 funções `SECURITY DEFINER` sem uma falha — e 904 linhas de 16 clientes
saindo por uma MV, sem login. **A postura de RLS ser impecável não é evidência
sobre a MV; são superfícies diferentes.**

Consulte o **estado vivo**, não a migration. No mesmo repo, o `REVOKE` correto
estava versionado desde maio e um `GRANT ALL` de julho o desfez: ler a migration
dava o assunto como resolvido.
- Stack com ORM → ache toda chamada de leitura e cheque o filtro de tenant:

```bash
grep -rnE "\.(findMany|findFirst|groupBy|aggregate|count|raw)\(|\.query\(|\.select\(|session\.(query|execute)\(" \
  --include='*.ts' --include='*.js' --include='*.py' --include='*.rb' --include='*.go' . \
  | grep -v -e node_modules -e '\.test\.' -e '\.spec\.' -e __tests__
```

Depois, uma a uma: o `where` cita o tenant do **chamador autenticado** (não um
id que veio do request)? Um tenant vindo do body é a mesma falha com outro nome.

Não conclua "está protegido" porque o ORM tem middleware de tenant configurado:
confirme que o middleware cobre `raw`/`$queryRaw`/`groupBy` — quase sempre não
cobre.

**O que a query com filtro certo ainda vaza** — quatro superfícies que não
aparecem no grep de `where`, e cada uma é uma pergunta a responder por escrito
na cobertura da A1:

- **Oráculo de enumeração.** `count`, filtro, ordenação por campo oculto,
  `404` versus `403`, unique constraint que revela que o e-mail existe, tempo
  de resposta. O atacante não lê o registro; ele descobre que existe e o que
  contém. Exige predicado confidencial concreto ("existe cliente com este CNPJ")
  e distinção observável — variação genérica de resposta não é achado.
- **Chave sem tenant.** Cache, índice de busca, nome de arquivo no storage,
  chave de deduplicação, `upsert` por `slug`: dois tenants colidindo na mesma
  chave lógica leem ou sobrescrevem um ao outro mesmo com a tabela de origem
  correta.
- **Soft-delete ignorado.** Busca, `join`, restore, job em background e link
  direto que não aplicam o predicado de ciclo de vida devolvem o registro
  "apagado" — e identificador de soft-deleted que pode ser re-registrado antes
  de todas as referências sumirem.
- **Autorização velha.** Membro removido do workspace, papel rebaixado,
  consentimento retirado, segredo rotacionado: sessão, cache, subscription
  realtime, job agendado e dado materializado continuam autorizando o que a
  tabela de membros já negou. Ache onde a remoção invalida cada cópia — e onde
  não invalida.

## A2 — Permissão definida no navegador

Método: **cruzamento**, não varredura. Liste os gates de papel do frontend,
depois abra o endpoint de cada um.

```bash
# 1. os gates do frontend
grep -rnE "isAdmin|canEdit|hasRole|useRole|role *[=!]==|permissions?\.(includes|has)" \
  --include='*.tsx' --include='*.jsx' --include='*.vue' --include='*.svelte' src/ app/ 2>/dev/null

# 2. o que o servidor exige (compare os dois conjuntos, um por um)
grep -rnE "requireAuth|requireRole|authorize|before_action|@login_required|middleware\(" \
  --include='*.ts' --include='*.js' --include='*.py' --include='*.rb' api/ src/ app/ 2>/dev/null
```

O achado é sempre a diferença: gate de papel no front **sem** verificação
equivalente no handler. A `baseline`, pilar `03-auth.md`, chama isso de
gate **cosmético** e exige que cada um declare sua contrapartida — quando o
projeto já tiver `.context/docs/baseline.md`, use o contrato de lá em vez de
recomeçar o inventário.

Autenticação não é autorização: `requireAuth` num endpoint de admin é achado,
não proteção.

**A permissão que mora na ordem dos passos.** O frontend também define a
sequência (pagou → liberou; pediu código → validou → agiu), e o servidor
precisa impô-la sozinho:

- **Máquina de estado.** Dá para pular etapa chamando o endpoint do passo 3 sem
  o passo 2? Voltar para um estado anterior? Repetir um fluxo concluído (replay
  de webhook de pagamento, reenvio de convite aceito)? Se o passo 2 de 3 falha,
  o passo 1 é desfeito?
- **Check-then-act não atômico.** Ler o saldo/código/vaga e agir em duas
  queries separadas é corrida: duas requisições concorrentes passam pelo mesmo
  check. A troca código→ação precisa ser **uma** operação no banco (`UPDATE ...
  WHERE codigo = $1 AND usado = false RETURNING`), nunca `SELECT` + `UPDATE`.
  Lição de um segundo fator real: três gates que chegavam na mesma requisição
  eram um gate só.
- **Valor que o cliente nunca mandaria.** Quantidade negativa, zero, acima do
  limite, string onde vai número. A UI constrange o usuário; a API não.

**O papel que o próprio usuário grava.** O caminho mais curto de conta comum a
admin não passa por bug nenhum: o usuário escreve o próprio papel, e o banco
acredita. Duas superfícies, ambas em Supabase.

*1. Autorização lida de `user_metadata`.* O `raw_user_meta_data` é do usuário:
ele edita com `auth.updateUser({ data })` e define no cadastro com
`signUp({ options: { data } })`. O que ele não edita é o `app_metadata`
(`raw_app_meta_data`), que só o servidor grava. Decisão de papel, plano ou
tenant lida do primeiro é decisão que o atacante toma.

Para policy, comece pelo lint que já existe:
`bash "${CLAUDE_PLUGIN_ROOT}/skills/baseline/scripts/splinter.sh" 0015`. Ele casa
por texto no `USING`/`WITH CHECK` (a própria fonte avisa que tem falso
positivo), então leia cada policy que ele acusar. Ele procura `user_metadata`
lido do JWT (`auth.jwt()` ou `request.jwt.claims`): policy que faz subquery em
`auth.users.raw_user_meta_data` não casa, e a primeira consulta abaixo cobre.
E ele **só lê policy**: não vê função `SECURITY DEFINER`, trigger nem o código
do app. O caso que mais
aparece fica justo nessa lacuna — a trigger de cadastro (`handle_new_user` e
afins) que copia `raw_user_meta_data->>'role'` para `profiles`. A conta nasce
admin num `signUp`, sem tocar em policy nenhuma.

```sql
-- policy que lê metadata do usuário por qualquer caminho (inclui o que o 0015 não casa)
SELECT schemaname, tablename, policyname, cmd
  FROM pg_policies WHERE qual ~* 'user_meta' OR with_check ~* 'user_meta';

-- função e trigger que leem metadata do usuário (o 0015 não alcança). O CASE cobre a
-- função SQL com BEGIN ATOMIC, que tem o prosrc vazio, sem chamar pg_get_functiondef
-- em agregado (que dá erro)
SELECT n.nspname, p.proname, p.prosecdef AS security_definer
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname NOT IN ('pg_catalog','information_schema','auth','storage','extensions',
                         'graphql','graphql_public','realtime','supabase_functions','vault','pgsodium')
   AND CASE WHEN p.prokind IN ('f','p') THEN pg_get_functiondef(p.oid) ELSE p.prosrc END
       ~* 'user_meta';

-- o que roda quando uma conta nasce ou muda
SELECT tgname, tgfoid::regproc AS funcao
  FROM pg_trigger WHERE tgrelid = 'auth.users'::regclass AND NOT tgisinternal;
```

```bash
# no app: papel decidido a partir do metadata que o usuário edita. Pega .role, ?.role,
# ['role'] e a desestruturação ({ role } = user.user_metadata); leia cada linha.
# Padrão literal e --include um por um: no zsh, $VAR sem aspas não se divide e $K[...] é
# subscript, e o grep sai calado
grep -rniE 'user_metadata[^;]{0,20}(role|papel|admin|plan|plano|tier|tenant|org)' \
  --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' --include='*.mjs' --include='*.cjs' . \
  | grep -v node_modules
grep -rniE '\{[^}]*(role|papel|admin|plan|plano|tier|tenant|org)[^}]*\}[[:space:]]*=[^;]*user_metadata' \
  --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' --include='*.mjs' --include='*.cjs' . \
  | grep -v node_modules
# o que os dois acima não alcançam (desestruturação em várias linhas, alias
# const meta = user.user_metadata): quantas leituras por arquivo, para abrir e ler
grep -rnc 'user_metadata' \
  --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' --include='*.mjs' --include='*.cjs' . \
  | grep -v -e node_modules -e ':0$'
```

Achado: o valor lido de `user_metadata` decide acesso, papel, plano ou tenant
(policy, função, trigger que grava coluna de papel, middleware). Não é achado:
copiar `full_name` ou `avatar_url` para o perfil; ler `app_metadata`.

*2. Mass assignment pelo PostgREST.* O cliente Supabase faz `PATCH` e `upsert`
direto na tabela, com as colunas que quiser. RLS decide **linha**, não
**coluna**: `using (id = auth.uid())` deixa o dono gravar o próprio `is_admin`.
Faltar `WITH CHECK` não é o defeito em si — sem ele, o Postgres reaplica o
`USING` à linha nova, e o dono continua dono. O defeito é nada fixar a coluna.
Três controles fixam, e basta um funcionando:

- `WITH CHECK` que prende a coluna ao valor atual (subquery na própria linha)
  ou a uma fonte que o usuário não escreve (`app_metadata`, tabela de membros);
- privilégio por coluna. **Atenção:** `REVOKE UPDATE (is_admin)` não faz nada
  enquanto existir o `GRANT UPDATE` na tabela inteira, que o Supabase dá por
  padrão. O que vale é o privilégio efetivo, não o `REVOKE` na migration;
- trigger `BEFORE INSERT OR UPDATE` que recusa ou reseta a coluna quando quem
  grava não é o servidor.

Vale para `INSERT` também: perfil criado pelo próprio cliente já com
`is_admin = true`, e `upsert` que cai no `ON CONFLICT DO UPDATE`.

```sql
-- colunas de papel, plano, tenant e flag de aprovação que quem vem do browser consegue
-- gravar. Tabela (tipo r/p): rls = false com upd/ins = true é o pior caso. View (tipo v):
-- rls não se aplica e o GRANT padrão do Supabase deixa upd = true em quase todas; o que
-- pesa é atualizavel = true (a view aceita UPDATE na coluna) sem security_invoker=true
-- (ou =on, como foi escrito) em opcoes, porque aí ela grava como o dono, por cima da RLS
SELECT c.relname AS tabela, c.relkind AS tipo, a.attname AS coluna, c.relrowsecurity AS rls,
       has_column_privilege(r.papel, c.oid, a.attnum, 'UPDATE') AS upd,
       has_column_privilege(r.papel, c.oid, a.attnum, 'INSERT') AS ins, r.papel,
       pg_column_is_updatable(c.oid, a.attnum, false) AS atualizavel, c.reloptions AS opcoes
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
 CROSS JOIN (VALUES ('anon'), ('authenticated')) r(papel)
 WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','f')
   AND a.attname ~* '(role|papel|admin|plan|plano|tier|tenant|org_id|workspace|owner|credit|saldo|^is_|approved|verified|aprovad)';

-- as policies de escrita que alcançam quem vem do browser (`public` inclui os dois papéis)
SELECT tablename, policyname, cmd, roles, qual, with_check
  FROM pg_policies
 WHERE schemaname = 'public' AND cmd IN ('INSERT','UPDATE','ALL')
   AND roles && ARRAY['public','anon','authenticated']::name[];

-- as triggers que poderiam travar a coluna. pg_trigger, não information_schema.triggers:
-- a view esconde trigger de tabela em que o papel da auditoria só tem SELECT
-- (a definição mostra timing e evento; BEFORE pode reescrever NEW ou abortar, AFTER só
-- trava com RAISE. Leia a função antes de concluir)
SELECT t.tgrelid::regclass AS tabela, pg_get_triggerdef(t.oid) AS definicao
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND NOT t.tgisinternal;
```

Sem acesso ao banco, a `cobertura[]` da A2 diz que papel gravado pelo usuário
não foi medido no estado vivo, e o que sobrou foi a leitura das migrations.

Achado: coluna sensível com `upd` ou `ins` verdadeiro, policy de escrita que
deixa o dono passar, e nenhum dos três controles. Em view, soma-se um caso:
`atualizavel` e `upd` verdadeiros sem `security_invoker` ligado em `opcoes`
(`=false` ou `=off` conta como ausente) grava como o dono, e a policy da tabela
de baixo não barra. A trigger `BEFORE` da tabela de baixo continua disparando e
segue valendo como controle; `atualizavel` mede só UPDATE, o INSERT pela view
se lê na definição dela. Escreva o caminho completo:
conta comum → `PATCH /rest/v1/profiles?id=eq.<próprio id>` com
`{"is_admin": true}` → passa a ver o que admin vê. Não é achado: coluna sem
privilégio efetivo; tabela **com RLS ligada** e nenhuma policy de escrita que
alcance `anon`, `authenticated` ou `public`; ou um dos três controles cobrindo
`INSERT` e `UPDATE`. Tabela com RLS desligada e privilégio de escrita é o
contrário: qualquer um grava qualquer coluna. Corroborar **não** é mandar o
`PATCH` no banco do cliente (escrever nunca, regra de ferro): é fixture local
com usuário dummy, ou `a_validar` com o plano.

## A3 — IDOR

**Percorra todos os handlers.** Enumere primeiro, audite depois, e reporte a
razão lidos/total.

```bash
grep -rnE "(app|router|fastify)\.(get|post|put|patch|delete)\(|@(Get|Post|Put|Patch|Delete)\(|def (get|post|put|patch|delete)|path\(" \
  --include='*.ts' --include='*.js' --include='*.py' --include='*.rb' --include='*.go' . \
  | grep -v -e node_modules -e '\.test\.' -e '\.spec\.' | tee /tmp/handlers.txt | wc -l
```

Para cada handler que recebe um id (path, query **ou body**), a pergunta é uma
só: **o objeto é carregado cruzando o id com o dono/tenant do chamador?**

- `findUnique({ where: { id } })` seguido de checagem posterior costuma estar ok;
  `delete/update({ where: { id } })` direto **não tem** checagem posterior possível
  — é o padrão que mais aparece.
- `deleteMany`/`updateMany` com `{ id, tenantId }` e resposta 404 quando
  `count === 0` é o formato certo do fix.
- Id sequencial aumenta severidade (enumerável sem vazamento prévio); UUID
  reduz explorabilidade mas **não** conserta — UUID vaza em log, e-mail, URL
  compartilhada e export.

**Id não é a única referência que vem do request: URL também.** Webhook, URL de
callback, "importar de link", avatar por URL, integração que o usuário
configura (n8n, Pipedrive, NotificaMe): o servidor **busca** um endereço que o
usuário escolheu.

```bash
# fetch(x.url), axios.post(x.url), got.get(x.url) e template literal `${x.url}/…`
grep -rniE '(fetch|axios|got|request|urllib|requests|httpx|http)(\.[a-z]+){0,2}\(`?(\$\{)?(req\.body|body\.|body\["|payload\.|config\.|settings\.|integration\.)[a-zA-Z_.]*(url|webhook|endpoint|callback)' \
  --include='*.ts' --include='*.js' --include='*.py' . | grep -v node_modules
```

Para cada um: existe allowlist de host ou bloqueio de rede interna
(`10.`, `172.16-31.`, `192.168.`, `169.254.169.254`, `localhost`) **depois** de
resolver o DNS e **depois** de seguir redirect? Sem isso é SSRF, e o alvo
clássico é o metadata endpoint do provedor ou o Postgres interno. Reporte com o
alvo interno concreto que o código alcança, não "poderia alcançar algo".

Registre em `caminho[]` a trilha `entrada → propagacao → sink` de cada achado
de A1 e A3: é a forma que quem corrige consegue refazer, e é o que o revisor
fresco vai reler.
