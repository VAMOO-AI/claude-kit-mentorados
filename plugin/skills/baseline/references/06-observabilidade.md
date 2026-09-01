# 06 · Observabilidade e error tracking

O teste deste pilar é uma pergunta só: **um usuário reporta "deu erro" às 14h de
ontem — quanto tempo até você estar olhando a linha de código?** Se a resposta
depende de reproduzir, o pilar está reprovado.

Sistema sem rastro não é sistema estável — é sistema onde ninguém vê a
instabilidade.

## Contrato

- [ ] **Error tracking instalado antes de qualquer `dropConsole`.** A ordem não é
      negociável.
- [ ] **ErrorBoundary por área**, não um só no topo da árvore.
- [ ] Erro capturado carrega contexto: usuário, rota, build, request id — e
      **nunca** PII sensível ou token.
- [ ] **Log estruturado com prefixo estável** em toda função de servidor.
- [ ] **Toda chamada de IA grava modelo, tokens e custo estimado — e o custo é
      atribuível a uma unidade de negócio** (lead, conversa, cliente ativo).
      "Quanto gastamos de IA no mês" é fatura; "quanto custa um lead" é decisão.
- [ ] **Um identificador de correlação atravessa** front → edge → n8n → banco.
- [ ] **Alerta sai do sistema monitorado.** Alerta que só aparece dentro do
      próprio app morre junto com ele.
- [ ] Trilha de auditoria **viva** para ação sensível — tabela que ninguém escreve
      é pior que nenhuma, porque parece cobertura.
- [ ] O caminho "erro em produção → linha de código" está escrito em algum lugar.

## Como implementar

**Custo de IA — uma tabela, escrita na mesma transação da resposta:**

```sql
create table public.ai_calls (
  id           bigserial primary key,
  criado_em    timestamptz not null default now(),
  modelo       text        not null,      -- o nome exato, nunca um alias
  operacao     text        not null,      -- 'classificar' | 'redigir' | ...
  tokens_in    integer     not null,
  tokens_out   integer     not null,
  custo_usd    numeric(10,6) not null,    -- calculado no momento, com a tabela vigente
  entidade_tipo text,                     -- 'lead' | 'conversa' | 'cliente'
  entidade_id   uuid                      -- é isto que transforma fatura em decisão
);
create index on public.ai_calls (criado_em);
create index on public.ai_calls (entidade_tipo, entidade_id);
```

Duas decisões que parecem detalhe e não são. **Grave o custo, não só os
tokens** — preço muda, e recalcular seis meses depois com a tabela de hoje
mente sobre o que a operação custou naquele dia. E **grave o nome exato do
modelo**: alias flutuante em produção muda o custo e a qualidade da resposta
sem uma linha de diff.

Sem `entidade_id` você tem gasto total e nada mais. Com ele, custo por lead e
por cliente ativo saem de um `group by` — e é essa razão, contra a receita do
mesmo lead, que diz se a automação dá lucro ou se você está comprando conversa
com desconto. Automação de IA sem custo por unidade é a única categoria de
sistema em que "está funcionando" e "está dando prejuízo" convivem em silêncio.

**Error tracking (Sentry como default do stack):**

```ts
// src/lib/observability.ts
import * as Sentry from '@sentry/react'

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,          // DSN é público por design
  environment: import.meta.env.MODE,
  release: __BUILD_SHA__,                         // injetado pelo vite define
  tracesSampleRate: 0.1,
  sendDefaultPii: false,
  beforeSend(event) {
    // nunca mande header de auth nem corpo com dado de cliente
    delete event.request?.headers
    if (event.request?.data) event.request.data = '[redacted]'
    return event
  },
})
```

O `release` é o que faz o sourcemap valer: sem ele o stack trace continua
minificado. Suba o mapa no CI, em canal privado, e **não** publique junto com o
bundle (pilar 01):

```bash
sentry-cli sourcemaps upload --release "$GITHUB_SHA" ./dist
find dist -name '*.map' -delete     # sobe pro Sentry, não pro CDN
```

**ErrorBoundary por área.** Um boundary único no topo transforma qualquer erro de
componente em tela branca do app inteiro:

```tsx
<Suspense fallback={<Skeleton />}>
  <ErrorBoundary area="crm"       onError={report}><CRMModule /></ErrorBoundary>
  <ErrorBoundary area="faturamento" onError={report}><BillingModule /></ErrorBoundary>
</Suspense>

function report(error: Error, info: React.ErrorInfo, area: string) {
  Sentry.captureException(error, { tags: { area }, extra: { componentStack: info.componentStack } })
}
```

O `onError` precisa chamar o tracker. Um `componentDidCatch` que só faz
`console.error` não sobrevive ao build de produção — o minificador remove a
chamada e o erro deixa de existir.

**Log estruturado no servidor:**

```ts
const log = (level: 'info'|'warn'|'error', event: string, data: Record<string, unknown> = {}) =>
  console[level](JSON.stringify({ ts: new Date().toISOString(), fn: 'ai-chat', level, event, ...data }))

log('info',  'request.start', { request_id, user_id })
log('error', 'llm.failed',    { request_id, code: err.code })   // sem prompt, sem PII
```

JSON de uma linha é grepável e agregável; texto livre não é. Prefixo de função
estável (`fn`) é o que permite filtrar quando tudo cai no mesmo stream.

**Correlação ponta a ponta.** Um id gerado no cliente e propagado:

```ts
const requestId = crypto.randomUUID()
await fetch(url, { headers: { 'x-request-id': requestId } })   // front
const requestId = req.headers.get('x-request-id') ?? crypto.randomUUID()  // edge
await admin.from('job_log').insert({ request_id: requestId, ... })        // banco
```

Sem isso, investigar um incidente é cruzar timestamps na mão.

**Alerta que sai do sistema.** O erro comum é o watchdog gravar numa tabela que a
própria aplicação exibe: quando a aplicação cai, o alerta cai junto e o silêncio
parece normalidade.

```sql
-- alerta com destino EXTERNO (webhook n8n → WhatsApp/Slack/e-mail)
select net.http_post(
  url     := 'https://n8n.exemplo.com/webhook/alerta-ingestao',
  headers := jsonb_build_object('content-type','application/json',
                                'x-app-secret', current_setting('app.alert_secret', true)),
  body    := jsonb_build_object('evento','ingestao_atrasada','desde',max(criado_em))
) from public.ingestao_log;
```

**Monitore o silêncio, não o status.** "O processo está ativo" mente: já houve
caso de trigger de e-mail com `active: true` que não recebia nada havia horas. O
alerta correto é *"nenhum evento nas últimas N horas úteis"*, não *"o serviço
respondeu"*.

E ao ler `net.http_request_queue`, lembre que `body` é `bytea`: comparar
`body::text` devolve zero sem erro. Use `convert_from(body, 'UTF8')`.

**Auditoria viva.** Se existe tabela de auditoria, alguma coisa precisa escrever
nela. O padrão que não apodrece é trigger, não chamada espalhada no código:

```sql
create or replace function public.fn_audit() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.audit_log (tabela, operacao, registro_id, ator, dados)
  values (tg_table_name, tg_op, coalesce(new.id, old.id), auth.uid(),
          to_jsonb(coalesce(new, old)));
  return coalesce(new, old);
end $$;

create trigger audit_pedidos after insert or update or delete
  on public.pedidos for each row execute function public.fn_audit();
```

## Como provar

```bash
# existe error tracking?
grep -rn 'captureException\|Sentry\.init\|@sentry' src/ package.json | head

# a combinação fatal: console removido no build e nenhum tracker
grep -rn "drop.*console\|dropConsole\|removeConsole" vite.config.* next.config.* 2>/dev/null
# se achou acima e nada no comando anterior → CRITICAL de observabilidade

# quantos ErrorBoundary de fato montados
grep -rn '<ErrorBoundary' src/ | wc -l

# tabela de auditoria viva ou morta?
grep -rn "from('audit_log')\|into public.audit_log\|insert into audit" src/ supabase/ | head
```

No banco:

```sql
-- a auditoria recebe escrita?
select count(*) as total, max(created_at) as ultimo from public.audit_log;
-- total > 0 e ultimo recente → viva. Senão é tabela decorativa.

-- alertas têm destino externo?
select jobname, command from cron.job;   -- procure net.http_post, não só insert
```

**O teste que fecha o pilar** — provoque um erro real em produção (um botão que
chama uma rota inexistente, num ambiente autorizado) e cronometre: quanto tempo
até o stack trace com a linha do código? Se não aparecer em minutos, o pilar é
`nao_conforme` mesmo que todos os comandos acima passem.

## Armadilhas

| Sintoma | Causa real |
|---|---|
| Erro de React em produção sem rastro nenhum | `dropConsole` ligado e nenhum tracker. O único log era `console.error` |
| Tela branca no app inteiro por um componente | ErrorBoundary único no topo. Um por área isola o estrago |
| Stack trace minificado e ilegível no tracker | Sourcemap não subiu, ou subiu sem `release` casando com o build |
| Alerta nunca disparou e o processo estava parado | O alerta escrevia numa tabela que só a UI do app lê |
| "Está ativo" e nada chega há horas | Status mente. Monitore ausência de evento, não flag de ativo |
| Assert sobre `net.http_request_queue` sempre zero | `body` é `bytea`; use `convert_from(body,'UTF8')` |
| Tabela de auditoria existe, com policy e grant, e vazia | Ninguém escreve. Cobertura aparente é pior que ausência declarada |
| Log de produção existe mas é inútil | Texto livre sem prefixo nem request id. Não dá pra filtrar nem correlacionar |
| Sentry cheio de ruído e ninguém olha | Sem `tracesSampleRate`, sem agrupamento, sem dono. Alerta que ninguém lê não é alerta |
