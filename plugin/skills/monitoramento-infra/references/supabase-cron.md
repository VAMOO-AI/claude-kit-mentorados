# Sonda no Supabase: pg_cron + pg_net + edge function

O jeito barato de rodar sonda sem servidor: o `pg_cron` agenda, o `pg_net` chama
a edge function, a função sonda e grava. Funciona — e tem quatro jeitos de
**parar calado**, com o painel mostrando tudo verde. Este arquivo é sobre eles.

## O agendamento

```sql
select cron.schedule('sonda-http', '*/10 * * * *', $$
  select net.http_post(
    url     := 'https://<ref>.supabase.co/functions/v1/sonda-http',
    headers := jsonb_build_object(
      'content-type',  'application/json',
      'authorization', 'Bearer ' || private.segredo_cron()),
    body    := '{}'::jsonb,
    timeout_milliseconds := 30000);
$$);
```

**O segredo não entra no SQL versionado.** Um segredo de cron escrito numa
migration commitada vazou e precisou de rotação. O padrão que dura:

- uma função `private.segredo_cron()` (`security definer`, `search_path = ''`)
  que lê o valor do Vault, sem `grant` para `anon`/`authenticated`;
- uma função `setup_crons(url text, segredo text)` **commitada**, que grava o
  segredo e (re)cria todos os jobs; quem roda passa o valor real **fora** do git;
- confira que a role que agenda enxerga o segredo:
  `select count(*) from vault.decrypted_secrets where name = '<nome>'` rodado como
  ela. Em pelo menos um projeto voltou vazio para a role `postgres`, e o cron
  passou a mandar `Bearer ` sem nada.

**Agenda e função de setup mudam na mesma migration.** Mudou o `*/5` para
`*/10` só no `cron.schedule`? O próximo `setup_crons()` reverte e ainda apaga os
jobs novos que não estavam nele.

## Calado nº 1: guarda de JWT numa função chamada pelo cron

Um cron falhou **100% das execuções por 44 dias** — 288 falhas por dia — sem
ninguém ver. A função tinha uma guarda baseada em `auth.uid()` / claims do JWT.
O pg_cron roda como `postgres`, sem JWT: a guarda é **sempre** falsa.

```sql
create or replace function private.chamada_local_do_cron()
returns boolean language sql stable as $$
  select coalesce(current_setting('request.jwt.claims', true), '') in ('', 'null')
     and session_user in ('postgres', 'supabase_admin');
$$;
```

Use `session_user`, não `current_user`: dentro de `security definer`, o
`current_user` é o dono da função e a checagem passa para qualquer um.

E o pior é que ninguém olha o lugar onde isso aparece:

```sql
select j.jobname, d.status, left(d.return_message, 120) as erro, d.start_time
from cron.job_run_details d join cron.job j using (jobid)
where d.status <> 'succeeded' and d.start_time > now() - interval '1 day'
order by d.start_time desc limit 20;
```

Ponha essa consulta numa sonda. Job falhando é alerta.

## Calado nº 2: o deploy religa o `verify_jwt`

O cron passa a receber `401 UNAUTHORIZED_INVALID_JWT_FORMAT` do gateway e para.
O `cron.job_run_details` mostra **succeeded** — porque o pg_net é assíncrono e
o job só enfileirou a requisição. Aconteceu mesmo com a função declarada no
`config.toml`.

- Declare **e** passe a flag em todo deploy:
  ```toml
  [functions.sonda-http]
  verify_jwt = false
  ```
  ```bash
  supabase functions deploy sonda-http --no-verify-jwt
  ```
- **Diagnóstico em 10 segundos:** mande um token que não é JWT e leia o corpo.
  ```bash
  FALSO=nao-e-jwt   # de propósito: não é um JWT
  curl -s -X POST https://<ref>.supabase.co/functions/v1/sonda-http \
       -H "Authorization: Bearer $FALSO"
  ```
  Corpo com `UNAUTHORIZED_INVALID_JWT_FORMAT` = o gateway barrou, sua função nem
  rodou. Corpo com o erro **da sua função** (ex.: `{"error":"unauthorized"}`) =
  gateway liberado, sua guarda recusou. O status 401 é igual nos dois; só o corpo
  separa.
- O status real das chamadas está no pg_net, não no cron:
  ```sql
  select status_code, count(*), max(created)
  from net._http_response
  where created > now() - interval '1 hour'
  group by 1 order by 2 desc;
  ```
  Ao ler o corpo da requisição em `net.http_request_queue`, lembre que `body` é
  `bytea`: use `convert_from(body, 'UTF8')`.

## Calado nº 3: o gate que abre com o segredo vazio

`'Bearer ' + ''` é igual a `'Bearer '`. Função que compara o header com
`Bearer ${Deno.env.get('CRON_SECRET')}` **aceita qualquer um** quando a env não
foi setada naquele projeto. Segredo ausente tem que fechar, e a comparação é em
tempo constante:

```ts
export function cronAutorizado(req: Request, segredo = Deno.env.get('CRON_SECRET') ?? '') {
  if (!segredo) return false                       // sem segredo, ninguém entra
  const recebido = (req.headers.get('authorization') ?? '').replace(/^Bearer /, '')
  const a = new TextEncoder().encode(recebido)
  const b = new TextEncoder().encode(segredo)
  if (a.length !== b.length) return false
  let d = 0
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i]
  return d === 0
}
```

## Calado nº 4: o job que pula um ciclo sim, outro não

Alvo com `interval_seconds = 600` e cron a cada 10 min. A sonda filtra "quem está
devido" com `last_run_at + interval <= now()`. O ciclo anterior gravou
`last_run_at` alguns segundos depois do início, então no ciclo seguinte faltam
segundos — e o alvo só roda de 20 em 20 min.

```sql
where last_run_at is null
   or last_run_at + make_interval(secs => interval_seconds)
      <= now() + interval '30 seconds'
```

Sonda sequencial longa ainda deriva; a correção é folga proporcional ao tempo
do ciclo.

## O monitor derrubando o banco

O banco ficou **3h45 cego**: `net._http_response` chegou a 190 MB para ~1.000
linhas vivas (o pg_net não tinha autovacuum dando conta), o garbage collector do
próprio pg_net virou a query nº 1 em tempo total, o I/O saturou e **todo cron e
toda sonda pararam junto com os alertas**. O painel dizia `ACTIVE_HEALTHY`.

- `TRUNCATE net._http_response` resolve na hora; um cron de
  `VACUUM (ANALYZE) net._http_response` a cada 6h previne.
- Retenção do histórico do cron (ele cresce para sempre):
  ```sql
  select cron.schedule('limpa-cron-historico', '17 3 * * *',
    $$delete from cron.job_run_details where end_time < now() - interval '2 days'$$);
  ```
- "Failed to connect to database" no health não quer dizer Postgres caído:
  conecte pelo pooler antes de concluir.
- O termômetro honesto é a **latência de uma query trivial** (`select 1`),
  medida de fora. Status de painel não é.
- `pg_stat_statements` ordenado por `total_exec_time` acha o culpado.

## Sondando a Management API do Supabase

Para vigiar projetos (saúde, disco, pausado), a sonda usa um token pessoal (PAT)
da Management API:

- **O PAT é por usuário** e enxerga só as organizações dele. Monitorar projetos de
  várias orgs pede um token por org, guardado no Vault.
- `401` = token revogado. `403` em `/v1/projects/<ref>` = o ref é de outra org.
  Os dois são `down` na hora: credencial quebrada tem que gritar.
- Projeto pausado aparece como `INACTIVE`, não `PAUSED`.
- Uso de disco: a fração é `used / size`.
- As rotas de logs e métricas têm limite próprio (as de logs, ~10 req/min) e
  respondem **403 quando estoura** — um 403 ali pode ser rate limit, não permissão.
- Counter de métrica que regride é reset de instância, não evento.
- Na troca de token, teste as rotas que a sonda usa com o token novo **antes** de
  gravar, e grave no mesmo segredo (sem trocar o id) para nada apontar para o velho.

Confira na doc oficial antes de depender de qualquer rota: a de logs já mudou de
endpoint uma vez e a antiga passou a responder 410.

## Testando sem disparar mensagem de verdade

`BEGIN; \i migration.sql; ROLLBACK;` **não é dry-run** se o arquivo tem `COMMIT`
dentro: o `COMMIT` fecha a sua transação e o resto roda em autocommit. Assim uma
migration de monitor foi aplicada em produção antes do PR, gravou um incidente
de teste e enfileirou 6 entregas reais — que só não viraram mensagem porque deu
tempo de apagar as linhas antes do dispatch rodar. Antes de confiar no
`ROLLBACK`, `grep -n '^\(BEGIN\|COMMIT\);' <arquivo>.sql`.

Para provar regra de alerta sem mandar nada: teste pgTAP que insere checks numa
transação e afirma o que entrou na fila de entregas, e um destino ntfy de teste
(tópico descartável) quando for testar ponta a ponta.
