# Dispatch / Client Pipeline, Daily Summary, Follow-Up + Dependency Matrix

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

## Dispatch Pipeline (Fluxo Completo)

> **Nota:** este pipeline assume um **backend intermediário** (ex.: app Next.js) que gerencia `dispatch_tracking` e callbacks. Em projetos **n8n self-contained**, toda essa lógica pode viver dentro do próprio workflow (Postgres node + Tool do AI Agent disparando UAZAPI/NotificaMe direto). Confirme a arquitetura do projeto atual antes de assumir esta topologia.

### Arquitetura (variante com backend)

```
Dispatch backend (ex: rota /bulk-sdr)
  → POST N8N webhook (por lead)
    → N8N envia template via NotificaMe
      → NotificaMe callback: dispatch_sent (com message_id)
        → backend salva em dispatch_tracking
          → Mirror para Chatwoot (fire-and-forget)
      → NotificaMe status callbacks: SENT, DELIVERED, READ, FAILED
        → backend atualiza dispatch_tracking
          → Auto-avança client pipeline
```

### 1. Dispatch (bulk-sdr route)

```typescript
// Input
{ leads: [{ id, nome, telefone, empresa, cargo }], mode: "sdr"|"nutricao", templateId?, template_name? }

// Server-side dedup
Se template_name informado → verifica dispatch_tracking existente com sent_at + !failed_at → skip

// Retry
MAX_RETRIES = 2 (3 tentativas total)
RETRYABLE_STATUSES = [408, 429, 500, 502, 503, 504]
Backoff: BATCH_DELAY_MS * (attempt + 1) * 2

// Tracking síncrono (CRÍTICO)
Insere dispatch_tracking ANTES de retornar response
→ Deve completar antes do callback SENT (~1-2s)
```

### 2. Dispatch Sent Callback (whatsapp-webhook)

```typescript
// Atomic upsert
1. UPDATE dispatch_tracking SET message_id WHERE telefone = X AND message_id IS NULL (ORDER BY created_at DESC LIMIT 1)
2. Se nenhum atualizado → INSERT novo registro
3. Ignore erro 23505 (unique constraint = idempotente)
```

### 3. Status Update Callbacks

```
SENT      → sent_at = timestamp
DELIVERED → delivered_at = timestamp
READ      → read_at = timestamp → avança para "visualizado" + label Chatwoot
FAILED    → failed_at = timestamp + error_message
REJECTED  → same as FAILED
ERROR     → same as FAILED
```

**Lookup duplo:** Tenta `message_id` primeiro, fallback `provider_message_id`.

### 4. Message Received (cliente respondeu)

```
1. Busca dispatch mais recente para o telefone → marca replied_at
2. Infere delivered_at e read_at = now (não responde sem ler)
3. Avança para "interagiu"
4. NÃO espelha para Chatwoot (NotificaMe já faz via integração canal)
```

### Zod Schemas

```typescript
statusUpdateSchema:  { type, message_id, provider_message_id?, status, timestamp?, error_message? }
messageReceivedSchema: { type, telefone, nome?, empresa?, message_text? }
dispatchSentSchema:  { type, message_id, lead_id?, telefone, template_name?, mode?, is_customer? }
```

---

## Client Pipeline

### Stage Hierarchy (só avança, nunca retroage)

```
cadastrado < contatado < visualizado < interagiu < qualificado < transferido
```

### advanceClientStage(leadId, targetStage)

```
1. Busca lead → valida is_customer === true
2. Compara ordem: current vs target
3. Só avança se target > current (ignora silenciosamente se igual ou menor)
4. Update: client_stage_id + updated_at
5. Se stage é "qualificado" ou "transferido" → sendPipelineAlert()
```

### advanceClientByPhone(phone, targetStage)

```
1. Query leads WHERE is_customer = true
2. matchLeadByPhone() (normaliza e compara variantes)
3. Chama advanceClientStage()
```

### Auto-avanço por evento

| Evento | Target Stage |
|--------|-------------|
| dispatch_sent SENT/DELIVERED | contatado |
| status_update READ | visualizado |
| message_received (reply) | interagiu |
| Chatwoot assignee change | transferido |

### Pipeline Alert

Disparado em `qualificado` e `transferido`:
- Monta resumo do lead (dados + notes + dispatches + intenção detectada)
- Envia via UAZAPI para phones de alerta
- Fire-and-forget (`.catch()` silencioso)

### Keyword-based Intent Detection

```
"interesse/quero/gostaria" → "Demonstrou interesse"
"preço/valor/custo/orçamento" → "Perguntou sobre preço"
"reunião/agendar/conversar" → "Quer agendar reunião"
"não + interesse/momento" → "Sem interesse no momento"
```

---

## Daily Summary

Duas variantes possíveis — verifique qual o projeto atual usa antes de descrever o fluxo.

### Variante A — Backend gera o resumo

```
Endpoint: POST /api/cron/daily-summary
Auth:     CRON_SECRET (Vercel) ou WEBHOOK_SECRET (N8N)
```

```
Schedule N8N (cron BRT)
  → POST /api/cron/daily-summary (backend agrega dados, retorna messageText)
    → Code node formata para UAZAPI (1 item por número destino)
      → POST <your-instance>.uazapi.com/send/text
```

### Variante B — N8N self-contained

```
Schedule N8N (cron BRT)
  → Postgres node: query agregando tabelas do projeto
  → Code node formata texto do resumo
  → HTTP POST <your-instance>.uazapi.com/send/text → número(s) de alerta
  → (opcional) Postgres node: INSERT em tabela de auditoria
```

Nesse caso não há backend chamado — todo o resumo vive dentro do workflow.

**Cron offset:** se houver outro cron disparando no mesmo horário (ex.: Follow-Up), use offset de minutos (`:05` vs `:00`) pra evitar contention.

### 4 Seções do Resumo

1. **📨 Disparos de Hoje** — total, enviados, entregues, lidos, respondidos, falharam + taxas (%)
2. **📬 Templates Anteriores — Atividade Hoje** — dispatches antigos com read/reply/delivered hoje + lista de quem interagiu
3. **💬 Interações do Dia** — merge lead_notes + Chatwoot API, dedup por telefone, top 15 clientes
4. **📈 Movimentações do Pipeline** — novos leads + contagem por stage + lista de transferidos/qualificados

### Timezone (CRÍTICO)

```typescript
// Brasília UTC-3
const brasiliaOffset = -3 * 60;
const brasiliaTime = new Date(now.getTime() + (brasiliaOffset + now.getTimezoneOffset()) * 60000);
const startOfDay = new Date(
  Date.UTC(brasiliaTime.getFullYear(), brasiliaTime.getMonth(), brasiliaTime.getDate()) - brasiliaOffset * 60000,
).toISOString();
```

### Merge de Interações (Dedup)

```
1. Query lead_notes (type = "whatsapp", created_at >= startOfDay)
2. Query Chatwoot API (getChatwootActivityToday)
3. Merge by telefone (lead_notes tem prioridade)
4. Sort by messageCount DESC
```

### Chatwoot opcional

Se Chatwoot não configurado → continua só com lead_notes (try/catch silencioso).

---

## Follow-Up Automático

### Regras

- **Alvo:** Clientes em stage `"interagiu"` com `updated_at < 2h atrás`
- **Idempotência:** Verifica se já existe dispatch `mode: "followup"` após `client.updated_at`
- **Business hours:** Seg-Sex, 8h-18h BRT apenas
- **Frequência:** 1x por período de silêncio
- **Envio:** Via N8N webhook com `mode: "followup"` → NotificaMe

### Cron

N8N: `*/30 11-21 * * 1-5` (cada 30min, seg-sex, 8h-18h BRT)
Vercel: backup (menos frequente)

### Cadência multi-touchpoint (24/48/72h) SEM CRM — âncora própria

Um agente com CRM (ex. Cliente A) acopla a cadência aos **stages do Pipedrive** (75→76→77→78 = máquina de estados). Quando o agente NÃO tem CRM (ex.: <agente>, que só tem `<agente>_messages`), ancore numa **tabela de estado própria** (`<agente>_leads`) que depois vira a ponte p/ o CRM futuro (Kommo etc.):

- **Âncora = `last_inbound_at`** (última msg do PACIENTE). Silêncio = `now - last_inbound_at`. Thresholds crescentes de uma âncora ÚNICA: TP1≥24h, TP2≥48h, TP3≥72h (NÃO gaps cumulativos).
- **Elegível** só quem tem `status='ativo'` E `last_outbound_at >= last_inbound_at` (o agente respondeu por último; o paciente que sumiu — senão você cobra quem ESTÁ esperando resposta).
- **Idempotência por rodada de silêncio:** tabela `<agente>_followup_log(phone, touchpoint, status, content, anchor_at)`. Conta follows com `created_at >= last_inbound_at` (a âncora atual). Quando o paciente responde, a âncora avança → a cadência reinicia limpa, sem apagar nada. `next_tp = sent_na_rodada + 1`; para após TP3 (`status='encerrado'`).
- **NÃO logar o follow enviado no histórico como `inbound`** — só `last_inbound_at` é a âncora. Pode espelhar como `assistant` p/ memória sem afetar a âncora.
- **Sinal de saída do funil:** no ramo de transferência do workflow principal, gravar `status='transferido'` na tabela de estado — senão o cron manda "você sumiu" pra quem já foi pra recepção (gera nova reclamação).
- **Go-live seguro:** backfill marca os leads pré-existentes como `encerrado` (baseline), sem disparo retroativo; o UPSERT inbound reativa pra `ativo` quando o paciente voltar a falar.
- **A query de candidatos pode calcular tudo** (silêncio, sent_count, next_tp, histórico recente via `string_agg`) num SELECT só com subqueries LATERAL — evita o merge-após-Postgres-node que perde o contexto do lead.

---

---

## Dependency Matrix

```
chatwoot-webhook route
  ├→ validateWebhookSecretOrQuery (http.ts)
  ├→ advanceClientByPhone (client-pipeline.ts)
  ├→ getChatwootConfig, applyTransferLabels, addLabelsToConversation (chatwoot.ts)
  ├→ buildLeadSummary (alerts.ts)
  └→ matchLeadByPhone (lib/phone.ts)

whatsapp-webhook route
  ├→ validateWebhookSecret (http.ts)
  ├→ advanceClientStage, advanceClientByPhone (client-pipeline.ts)
  ├→ getChatwootConfig, mirrorDispatchToChatwoot, findConversationByPhone (chatwoot.ts)
  └→ Zod schemas

bulk-sdr route
  ├→ authenticateRequest, getActiveIntegrationConfig (server/supabase.ts)
  ├→ normalizePhone (lib/phone.ts)
  └→ mirrorDispatchToChatwoot (chatwoot.ts)

daily-summary cron
  ├→ validateCronSecret (http.ts)
  └→ sendDailySummary (alerts.ts → chatwoot.ts)

client-pipeline.ts
  ├→ matchLeadByPhone (lib/phone.ts)
  ├→ sendPipelineAlert (alerts.ts)
  └→ getChatwootConfig, applyTransferLabels (chatwoot.ts)
```

---
