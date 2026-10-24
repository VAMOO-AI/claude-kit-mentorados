# Dados e rede: lista inteira, N+1, realtime, banco, região

As queries de diagnóstico ficam na `baseline`: top 10 do `pg_stat_statements`,
`seq_scan` × `idx_scan`, `explain (analyze, buffers)`, lints de índice do Advisor e a
ordem de escalar. Leia `${CLAUDE_PLUGIN_ROOT}/skills/baseline/references/05-carga.md` e
`02-banco.md`. Aqui ficam os padrões que se repetiram em apps reais.

## A lista inteira indo pro cliente (o padrão mais repetido)

- **Buscar tudo e filtrar ou agregar no browser.** Troque por:
  - busca no servidor, com teto e debounce;
  - agregação no banco com `COUNT(*) FILTER` e `GROUP BY`;
  - RPC de KPI.
- **Teto silencioso de 1000 linhas do PostgREST.** Pagine com `.range` e desempate por id.
  Isso apareceu em 7 repos.
- **`select('*')` com jsonb pesado a cada volta de foco da janela.** Selecione só as
  colunas usadas.
- **Primeira pintura progressiva:** uma janela curta primeiro e a completa depois. Num
  dashboard, 3 meses de dado passaram a carregar em ~3 s com o banco frio e a escapar do
  timeout 57014.
- **Trocar o algoritmo de uma query:** use um harness que roda o código antigo e o novo
  sobre dados de produção e exige 0 divergências.

## Requests demais (egress, Disk IO, pool)

- **Egress é contado em requests, não em tamanho.** O diagnóstico é o delta de
  `pg_stat_statements`: cada `set_config` corresponde a uma request REST. Já apareceram
  milhões de requests num banco abaixo de 50 MB.
- **Realtime com `invalidateQueries`** refaz a lista inteira em toda aba conectada. Troque
  por `setQueryData` com um reducer da linha que mudou e `backfillOnReconnect`.
- `refetchInterval` curto somado a realtime é trabalho em dobro. Tire um dos dois.
- **N+1** vira lote com `.in()`. Queries independentes em série viram `Promise.all`.
- **Sync evento a evento** vira lote. Num fluxo n8n, isso cortou as requests por minuto
  em mais de 10×.
- **`RAISE ... 40001`** dispara o retry interno do PostgREST: 7 tentativas por chamada.
  Use um SQLSTATE próprio (`PT409`); isso já virou incidente.
- **Cache na frente de dado global ou de API com rate-limit:** com TTL e **sem cachear o
  vazio**. Num caso, as leituras em 10 min caíram de centenas para dezenas.

## Banco

- **Busca fuzzy que dá timeout só em prod:** índice GIN com `gin_trgm_ops`.
- **Trigger que varre a tabela a cada linha inserida:** índice funcional parcial que
  **repete o WHERE** da trigger.
- **`IN (SELECT f())` materializando a tabela:** troque por `= ANY (ARRAY(SELECT f()))`,
  que vira InitPlan.
- **RLS chamando helper por linha:** embrulhe em `(select auth.uid())` / `(select helper())`.
  Num app, foram dezenas de policies de uma vez.
- **Helper de RLS virando InitPlan pede `grant execute`.** Função `stable` sem argumento
  é avaliada uma vez por statement e vira condição de índice, mas o InitPlan roda no
  contexto do executor. Sem `grant execute … to authenticated`, a mesma função dá 42501
  numa tabela e passa em outra, conforme o plano. Aí um índice novo ou uma estatística
  diferente derruba uma tela que funcionava. Depois de mexer em índice ou policy, teste
  com o papel `authenticated`, não com service role.
- **Index Only Scan que ainda vai ao heap:** `VACUUM` e autovacuum mais agressivo nas
  tabelas quentes. Num Postgres self-hosted, a query caiu a menos de um quarto do tempo.
  Confira se a CPU está ociosa antes de culpar parâmetro do planner.
- **Índice em prod:** `CREATE INDEX CONCURRENTLY` (ver `02-banco.md`).

## Rede e servidor

- **Função longe do banco:** `x-vercel-id: gru1::iad1` se resolve com `"regions": ["gru1"]`
  no `vercel.json` (ou a região do seu banco). Num caso, a rota principal caiu para menos
  da metade do tempo. É o maior ganho por linha de config que já apareceu.
- **Fetch do servidor sem `AbortSignal`/timeout e sem `maxDuration`** pendura o login.
- **Consulta ao banco em toda request no middleware ou proxy:** mova para onde ela é
  necessária. Com chave assimétrica, use `getClaims()` em vez de `getUser()`.
- **Sessão ou ator recalculados várias vezes por request:** `React cache()`, `loading.tsx`
  e queries em paralelo. Num caso, o TTFB local caiu quase pela metade.
- **App mostrado ao cliente em `next dev`:** rode `build` + `start`.
