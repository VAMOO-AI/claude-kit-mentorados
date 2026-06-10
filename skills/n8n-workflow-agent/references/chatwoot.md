# Chatwoot (CRM omnichannel)

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

## Chatwoot (CRM)

```
Base: https://<your-chatwoot-host>
Header: api_access_token: <account-token>
Account: <account-id>

POST /api/v1/accounts/{id}/conversations/{conv_id}/messages
GET  /api/v1/accounts/{id}/contacts/search?q={phone}
POST /api/v1/accounts/{id}/contacts
GET  /api/v1/accounts/{id}/conversations?page={n}
POST /api/v1/accounts/{id}/webhooks
```

### Config (Supabase `integrations` table)

```typescript
interface ChatwootConfig {
  server_url: string   // https://<your-chatwoot-host>
  api_key: string      // api_access_token
  account_id: string   // numeric, as string (ex: "1", "2")
}
```

### Contato: Find or Create

```
1. searchContact(phone) → GET /contacts/search?q=+{digits}   ← '+' prefix OBRIGATÓRIO
2. Se não existe → createContact({ inbox_id, phone_number: "+{digits}", name })
   (POST /contacts com inbox_id já cria a contact_inbox; NÃO chamar POST /contact_inboxes em seguida — duplica)
```

**Gotcha:** `GET /contacts/search?q=554733221100` retorna `payload: []` mesmo com o contato existindo. **Precisa do `+` prefix:** `?q=%2B554733221100`. Sem isso, o pipeline tenta criar de novo e o Chatwoot retorna 422 `["phone_number"]` (already taken). Sintoma de loop de Create Contact após o 1º run.

**Alternativa mais robusta — `/contacts/filter` (match exato):**

```bash
POST /api/v1/accounts/{acct}/contacts/filter?include=contact_inboxes
Content-Type: application/json
{
  "payload": [{
    "attribute_key": "phone_number",
    "filter_operator": "equal_to",
    "values": ["+554733221100"],
    "attribute_model": "standard"
  }]
}
```

Match exato instantâneo, sem depender do índice de search (que pode ter lag após create). Use quando o pipeline puder rodar logo após um create.

⚠️ **Pitfall no n8n HTTP node:** ao usar `/contacts/filter` com `jsonBody: "={{ JSON.stringify({...}) }}"`, o request pode chegar com body vazio/escapado errado no Chatwoot self-hosted (mesmo retornando 200). Sintoma: `payload: []` mesmo com contato existente. Workaround: voltar pra `GET /contacts/search?q=+<digits>` (funciona via `queryParameters`).

### Conversa: Find or Create

```
1. GET conversas do contato → prefere status="open"
2. Se não existe → findWhatsAppInboxId() → POST nova conversa
3. Inbox cache com TTL 5min
```

### Labels — MERGE SEMÂNTICO (crítico)

Chatwoot SUBSTITUI labels no POST (não appenda). Pattern obrigatório:

```typescript
// 1. Buscar labels atuais
const current = await getConversationLabels(config, conversationId);
// 2. Union com novos
const merged = [...new Set([...current, ...newLabels])];
// 3. POST merged
await setConversationLabels(config, conversationId, merged);
```

**Bug real:** Se você fizer POST direto com novos labels, remove todos os existentes.

### Labels do Sistema

| Label | Aplicado quando |
|-------|----------------|
| `prospeccao` | Dispatch SDR |
| `nutricao` | Dispatch nutrição |
| `interagiu` | Cliente responde mensagem |
| `visualizado` | Cliente lê mensagem |
| `pausar_ia` | Transferido para humano |
| `qualificado` | Lead qualificado |
| `transferido` | Transfer executado |

### Messages — Private Flag (previne loop)

```js
// OBRIGATORIO: private: true em mensagens do agente
{
  content: mensagemDoAgente,
  message_type: 'outgoing',
  private: true  // Sem isso, Chatwoot reenvia como webhook → loop infinito
}
```

### Mirror de Dispatch

Quando um dispatch (template) é enviado via N8N — seja por backend intermediário ou pelo próprio workflow:
1. `findOrCreateContact()` no Chatwoot
2. `findOrCreateConversation()`
3. Envia nota privada com info do template
4. Adiciona label (`prospeccao` ou `nutricao`)

### Mirror de OUTGOING (mensagem do agente IA) — CRÍTICO

**NotificaMe channel→Chatwoot integration espelha apenas mensagens INCOMING.** Mensagens enviadas pela API (pelo N8N → NotificaMe) **NÃO** aparecem automaticamente no Chatwoot. Se você quer ver o que o agente IA enviou, precisa postar explicitamente.

**Padrão antigo (insuficiente):** postar uma `nota privada` (`private: true`) com o texto. Funciona mas:
- Texto aparece como nota interna (visual diferente, não parece mensagem)
- Áudios/imagens não aparecem nunca (só o texto da resposta)
- Agentes humanos não conseguem ouvir o áudio que a IA enviou

**Padrão novo (recomendado):** postar como **mensagem outgoing PÚBLICA** com `source_id` único + (se for mídia) anexo via multipart upload.

#### A) Loop guard com `source_id`

Postar `private: false` no Chatwoot dispara webhook `message_created` → seu workflow N8N → `Processar Evento Chatwoot`. Se essa node tem lógica "outgoing + !private → reenviar via WhatsApp" (para manual agent typing), ela cria **loop infinito**: workflow posta → webhook chega → workflow reenvia → repete.

**Solução:** marcar a mensagem com `source_id: "n8n-{tipo}-{messageId}"` e adicionar guard no event handler:

```js
// Processar Evento Chatwoot — adicionar filtro source_id
var sourceId = body.source_id || "";
var isFromN8n = typeof sourceId === "string" && sourceId.indexOf("n8n-") === 0;

if (isOutgoing && !isPrivate && content && inboxId === SEU_INBOX && !isFromN8n) {
  // só reenvia se NÃO for mensagem que nós mesmos postamos
  return [{ json: { action: "send_agent_message", ... } }];
}
```

Chatwoot preserva `source_id` no payload do webhook. Verificado: msg criada via API com `source_id: n8n-test-123` retorna o mesmo source_id no GET e no webhook event.

#### B) Multipart upload de áudio (mensagem pública com anexo)

Para áudio aparecer como mensagem pública com player no Chatwoot, fazer multipart POST:

```bash
POST /api/v1/accounts/{id}/conversations/{conv_id}/messages
Content-Type: multipart/form-data

Fields:
- content: "🎤 [transcrição/legenda]"
- message_type: outgoing
- private: false
- source_id: n8n-audio-{messageId}
- attachments[]: <binário do arquivo>
```

Chatwoot aceita o arquivo, salva no Active Storage, retorna o objeto da mensagem com `attachments[].data_url` apontando para o CDN. O áudio fica reproduzível na UI.

**Topologia N8N completa para audio mirror:**

```
Enviar Audio NotificaMe (existing) → Salvar Resposta IA (existing)
                                   → Chatwoot - Busca Contato → Busca Conversa → Nota Privada (existing, mantém)
                                   → [NEW] Download Audio Bin (HTTP GET responseFormat:file) → [NEW] Chatwoot Audio Público (multipart POST)
```

Os 3 ramos paralelos da `Enviar Audio NotificaMe` rodam independente. O download usa `Upload Audio Supabase.first().json.Key` para construir a URL pública. O multipart POST referencia `Chatwoot - Busca Conversa.first().json.payload.sort((a,b) => b.id - a.id)[0].id` para o conv id.

### Coexistence: templates não aparecem no app WhatsApp Business

**Confirmado por docs Meta + Respond.io:** templates enviados via Cloud API (NotificaMe → Meta → WhatsApp) **NÃO sincronizam para o histórico do app WhatsApp Business**, mesmo com coexistence ativo. É by design — templates só podem ser disparados pela API, não pelo app.

**Implicação:** se um agente humano usa o app WhatsApp Business e quer ver os templates que a IA disparou, ele PRECISA olhar no Chatwoot (ou outro CRM espelho), nunca no app. Isso reforça a necessidade do "Mirror de OUTGOING" acima.

### Transfer para Humano

```
1. Detecta transferência (tag [TRANSFERIR_PARA_HUMANO], JSON, frases confirmativas)
2. applyTransferLabels() → ["pausar_ia", "qualificado", "transferido"]
3. Envia resumo do lead como nota privada (só agentes veem)
4. Redis: SET PAUSA_{AGENTE}_{phone} TTL 3600
```

**Frases que NÃO disparam:** "Posso transferir", "transferir para" (genérico)
**Frases que DISPARAM:** "vou te conectar", "vou te transferir", "estou transferindo"

### Webhook Registration

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "api_access_token: {TOKEN}" \
  "https://<your-chatwoot-host>/api/v1/accounts/<account_id>/webhooks" \
  -d '{"url": "https://app.example.com/api/chatwoot-webhook?token={SECRET}",
       "subscriptions": ["message_created","conversation_created","conversation_updated","conversation_status_changed"]}'
```

**Nota:** `assignee_changed` NÃO é evento válido no Chatwoot. Transferências vêm via `conversation_updated`.

### Webhook Auth no App

Chatwoot não envia custom headers → usar query param `?token={SECRET}`:

```typescript
validateWebhookSecretOrQuery(headers, url, envVar)
// 1. Tenta header x-webhook-secret / Authorization Bearer
// 2. Fallback: query param ?token=
// 3. Comparação timing-safe (crypto.timingSafeEqual)
```

Rota do webhook faz fallback duplo:
```
1. Tenta CHATWOOT_WEBHOOK_SECRET
2. Se falha, tenta WEBHOOK_SECRET
3. Se ambos falham → 401
```

### getChatwootActivityToday (Daily Summary)

Pagina conversations (25/página, max 10 páginas), filtra `last_activity_at >= startOfDay`. Retorna `{ nome, telefone, messageCount, lastActivity }`.

**Caveat:** `messageCount` é lifetime, não só hoje (trade-off performance).

### Caching

```typescript
inboxCache: { id, expiresAt }  // TTL 5min
agentCache: { agents, expiresAt }  // TTL 5min
```

### Timeout

Todos os fetch Chatwoot: `AbortController` + `setTimeout(FETCH_TIMEOUT_MS)` (default 5000ms).

---
