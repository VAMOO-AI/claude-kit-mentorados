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
grep -rnE "(fetch|axios|got|request|urllib|http\.get)\((req\.body|body\.|payload\.|config\.|settings\.|integration\.)[a-zA-Z_.]*(url|webhook|endpoint|callback)" --include='*.ts' --include='*.js' --include='*.py' . | grep -v node_modules
```

Para cada um: existe allowlist de host ou bloqueio de rede interna
(`10.`, `172.16-31.`, `192.168.`, `169.254.169.254`, `localhost`) **depois** de
resolver o DNS e **depois** de seguir redirect? Sem isso é SSRF, e o alvo
clássico é o metadata endpoint do provedor ou o Postgres interno. Reporte com o
alvo interno concreto que o código alcança, não "poderia alcançar algo".

Registre em `caminho[]` a trilha `entrada → propagacao → sink` de cada achado
de A1 e A3: é a forma que quem corrige consegue refazer, e é o que o revisor
fresco vai reler.
