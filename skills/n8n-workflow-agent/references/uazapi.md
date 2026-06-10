# UAZAPI (WhatsApp interno) + Uptime Watcher

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

## UAZAPI (WhatsApp — Alertas Internos)

```
Base: https://<your-instance>.uazapi.com
Header: token: <instance-token>  (NÃO AdminToken — header `token` lowercase)

POST /send/text      — { number, text }
POST /send/media     — { number, type, file (base64 com prefix) }
POST /message/download — { id, return_link: true }
POST /chat/archive   — { number, archive: true }
GET  /instance/status
POST /message/find   — { messageid } → status delivery (Pending/Sent/Delivered/Read)
GET  /webhook        — lista webhook subscribers (multi)
```

### UAZAPI é Baileys, NÃO Meta Cloud API (regra dura)

UAZAPI usa o protocolo **Multi-Device do WhatsApp Web (Baileys)**, API **não-oficial**. Implicações práticas que confundem mesmo quem conhece a Cloud API oficial:

- **NÃO** há `reachout_timelock` da Meta. Pode enviar pra qualquer número a qualquer hora sem janela de 24h, sem template aprovado, sem opt-in prévio. O fluxo natural é `status: "Pending" → "Sent" → "Delivered" → "Read"` em segundos.
- **NÃO** há message templates. Cada `/send/text` é livre.
- **Risco real é da WhatsApp (não da Meta Business)** — bloqueio por volume/spam pattern do próprio app. Mitigar com aquecimento gradual de número novo (5-7 dias mandando msgs casuais antes de bulk).
- **`isBusiness: true`** no `/instance/status` significa apenas que a CONTA WhatsApp é Business (com perfil comercial visível). Não habilita features da Cloud API — segue sendo Baileys.
- Diagnóstico "mensagem não chega": NUNCA atribuir a regra Meta de 24h. Causas reais: número não tem WhatsApp ativo, conta bloqueada pelo WhatsApp por spam, Multi-Device da instância caiu (`lastDisconnect` recente), ou usuário só não notou (`/message/find` mostra status real).

### Phone normalization — leading 9 do mobile brasileiro (CRÍTICO)

WhatsApp normaliza números móveis brasileiros removendo o `9` extra do prefix. Exemplo: você manda `/send/text` com `number: "5547991234567"` (13 dígitos, com 9 do mobile) e o webhook retorna `chatid: "554791234567@s.whatsapp.net"` (12 dígitos, sem o 9).

| Forma | Quando aparece |
|---|---|
| `5547991234567` (13 dig, com 9) | Como você envia no body `/send/text`. Usuário tipicamente fornece nesse formato. |
| `554791234567` (12 dig, sem 9) | Como UAZAPI devolve no `chatid`, no webhook payload, e nos chats do Baileys. |

**Implicação grave:** filtros tipo `BLOCKED_PHONES`, dedup keys (`PAUSA_<agente>_<phone>`, `DEDUP_<phone>`), e qualquer lookup por phone precisam usar a versão **normalizada (sem o 9)** porque é o que o `chatid` retorna ao webhook. Se você popular essas keys com a versão de 13 dígitos, o filtro nunca casa.

Padrão de extração no Code node (consistente com o resto da skill):
```js
var rawPhone = msg.chatid ? msg.chatid.replace(/@.*$/, '') : (chat.phone || '');
var phone = rawPhone.replace(/\D/g, '');  // já vem normalizado (sem 9) do chatid
```

Se você precisa ENVIAR pra um número que veio no formato normalizado de 12 dígitos, pode mandar assim — UAZAPI aceita os dois formatos no `/send/text`.

### Quando usar UAZAPI vs NotificaMe

| Uso | Provider | Motivo |
|-----|----------|--------|
| Alertas internos (resumo diário, transferência) | **UAZAPI** | Envio livre sem template |
| Mensagens client-facing (SDR, nutrição, follow-up) | **NotificaMe** | Templates aprovados Meta |
| TTS/áudio para cliente | **NotificaMe** | Integra com Chatwoot canal |
| Espelhamento CRM | **Chatwoot** | Via NotificaMe integration |

### Múltiplos webhooks por instância (CRÍTICO)

UAZAPI aceita **múltiplos webhook subscribers** numa mesma instância (ex: workflow agente IA + workflow mirror Chatwoot). MAS:

- **`GET /webhook`** retorna **array** com todos os subscribers (cada um com `id`, `url`, `events`, `excludeMessages`).
- **`POST /webhook`** via API REST **NÃO cria um novo subscriber** — ele faz **upsert single-by-instance** (sobrescreve o array inteiro pra ter só 1 entry, mesmo enviando `id` ausente / URL diferente).
- **Único jeito de adicionar 2º+ webhook:** painel admin da instância (`uazapi.dev` → Configurar Webhooks → botão **"Salvar com um novo"**). Lá cada save gera um `id` distinto.

**Implicação prática:** se você for testar a API `POST /webhook` em prod sem cuidado, **vai desativar o webhook ativo do agente** (sintoma: agente para de responder). Sempre ter rollback pronto:
```bash
curl -X GET https://<inst>.uazapi.com/webhook -H "token: $TOKEN" > /tmp/webhook-backup.json
# se sobrescrever, restaurar com POST do entry original
```

### `excludeMessages` flags (CRÍTICO)

| Flag | Efeito |
|---|---|
| `wasSentByApi` | **Não dispara webhook pra mensagens enviadas pela própria API** (suprime echo de `fromMe=true`). Use no webhook do agente IA pra ele não receber as próprias respostas. |
| `isGroupYes` | Suprime mensagens de grupos `@g.us`. Quase sempre desejável. |

**Pro mirror Chatwoot espelhar `outgoing` da IA**, o webhook do mirror precisa **NÃO** ter `wasSentByApi` (caso contrário não recebe `fromMe=true` da resposta da IA, e o admin não vê no Chatwoot o que a IA respondeu). Configure no painel UAZAPI separadamente do webhook principal do agente.

### Payload Webhook Inbound UAZAPI (CRITICO)

**NUNCA assuma formato flat.** UAZAPI envia aninhado:

```json
{
  "chat": {
    "phone": "+55 47 9923-0173",
    "wa_chatid": "554791234567@s.whatsapp.net",
    "name": "Nome do Contato"
  },
  "message": {
    "chatid": "554791234567@s.whatsapp.net",
    "text": "Conteúdo",
    "content": "Conteúdo",
    "fromMe": false,
    "messageType": "Conversation",
    "messageid": "2A25C97D16C0C0D29B5F",
    "mediaType": "", "mediaUrl": "", "caption": ""
  }
}
```

### Extrair dados do payload UAZAPI

```js
var msg = body.message || {};
var chat = body.chat || {};
var rawPhone = msg.chatid ? msg.chatid.replace(/@.*$/, '') : (chat.phone || '');
var phone = rawPhone.replace(/\D/g, '');
var texto = msg.text || msg.content || '';
var fromMe = msg.fromMe === true;
var messageId = msg.messageid || '';
var msgType = (msg.messageType || '').toLowerCase();
```

### Normalizar tipos de mensagem UAZAPI

| messageType | Tipo interno | Tratamento |
|---|---|---|
| `text`, `conversation` | texto | Direto pro agente |
| `audioMessage`, `audio` | audio | Transcrever |
| `imageMessage`, `image` | imagem | Vision ou auto-reply |
| `stickerMessage`, `sticker` | imagem | Download UAZAPI + processar |
| `reactionMessage` | texto | `[Cliente reagiu com {emoji}]` |
| `videoMessage` | texto | `[Video enviado pelo cliente]` |
| `documentMessage` | texto | `[Documento: {nome}]` |
| `locationMessage` | texto | `[Localizacao compartilhada]` |

### Reply/Quote context

```js
if (msg.quoted && typeof msg.quoted === 'object' && msg.quoted.text) {
  var quotedText = msg.quoted.text.substring(0, 200);
  conteudo = '[Respondendo a: "' + quotedText + '"]\n' + conteudo;
}
```

---

## Out-of-Band Uptime Watcher (REGRA DURA)

**Princípio:** o canal de notificação de "X caiu" NUNCA pode ser o próprio X. Watcher de UAZAPI de cliente vai em **n8n + UAZAPI de OUTRO tenant** (tipicamente o n8n da Sua Empresa com instância UAZAPI da própria Sua Empresa). Notificação out-of-band.

**Anti-pattern (real, cometido na Cliente A até 2026-05-28):** schedule trigger no mesmo n8n do cliente → `GET suaempresa.uazapi.com/instance/status` (UAZAPI do cliente) → IF disconnected → `POST suaempresa.uazapi.com/send/text` (mesma UAZAPI caída). Dependência circular: quando UAZAPI cai, `/send/text` também cai. Zero alerta.

### Topologia

```
n8n Sua Empresa  ── Schedule 5min ──┐
(infra externa)                  ↓
                  GET <cliente>.uazapi.com/instance/status
                                 ↓ (probe usa token DO CLIENTE)
                        ┌────────┴────────┐
                     connected      ≠ connected
                                 ↓
                  Postgres Sua Empresa: read last_state
                                 ↓
                       Decide: queda / lembrete / recovery / probe_falha
                                 ↓ fan-out paralelo 3 canais
                ┌────────────────┼────────────────┐
                ↓                ↓                ↓
        WhatsApp                Email           Push
        (UAZAPI Sua Empresa)       (Resend)        (ntfy.sh)
                                 ↓
                        Postgres Sua Empresa: log execution
```

### State machine + dedup (Postgres, não Redis)

Tabela `alertas_uazapi` em Postgres centraliza estado. Função `ultimo_estado_alerta(cliente)` retorna o último registro. State machine no Code node "Decide Action":

| last_status | current_status | age_min | evento | shouldFanout |
|---|---|---|---|---|
| `null` | `connected` | — | `baseline` | false (1ª vez já online) |
| `null` | `disconnected` | — | `queda` | true (1ª vez já offline — alerta imediato) |
| `connected` | `connected` | — | `baseline` | false (sem mudança) |
| `connected` | `disconnected` | — | `queda` | true (transição) |
| `disconnected` | `disconnected` | <30 | `lembrete` | false (dedup) |
| `disconnected` | `disconnected` | ≥30 | `lembrete` | true (re-alerta a cada 30min) |
| qualquer | `connected` (vindo de !connected) | — | `recovery` | true |
| probe HTTP 5xx/timeout | — | — | `probe_falha` | true (dedup 30min igual) |

Dedup em Postgres (lookup do último row) é mais simples e visível que Redis TTL pra esse caso — também sobrevive a restart do n8n.

### Channel fan-out com `neverError: true` + collector

Cada canal HTTP tem `neverError: true` pra que falha em um não mate os outros. Node collector após o Merge agrega quais canais deram 2xx vs falha, grava em `canais_ok[]` / `canais_falha[]` no log:

```js
function ok(resp) { return resp && resp.statusCode >= 200 && resp.statusCode < 300; }
var canais_ok = [];
var canais_falha = [];
if (ok(wa)) canais_ok.push('whatsapp'); else canais_falha.push('whatsapp');
if (ok(em)) canais_ok.push('email');    else canais_falha.push('email');
if (ok(pu)) canais_ok.push('push');     else canais_falha.push('push');
```

### Tripla redundância obrigatória

Sempre 3 canais (não 1, não 2). Razões reais por que cada um pode falhar isoladamente:

| Canal | Falha típica |
|---|---|
| WhatsApp (UAZAPI Sua Empresa) | Mesma host do cliente cair junto (multi-tenant `suaempresa.uazapi.com`); número Business novo sem warmup; destinatário com WhatsApp off |
| Email (Resend/SES) | DNS bloqueando, spam folder, MX problem |
| Push (ntfy.sh) | App push desinstalado, token de subscriber expirado |

Pelo menos 1 dos 3 chega em ~100% dos cenários reais.

### Gotcha: ntfy.sh Title header não aceita Unicode

`Title:` header é RFC-7230 (ASCII strict). Mandar emoji direto:
```
Title: ⚠️ UAZAPI CLIENTE A desconectada
```
retorna `Invalid character in header content ["title"]`. Mover emoji pro **body** (que é UTF-8 livre) ou strip-and-encode na expressão:
```
Title: UAZAPI CLIENTE A desconectada    ← ASCII puro no header
body:  ⚠️ Detalhes aqui...           ← emoji vai no body
```

Tags do ntfy (`Tags: warning,rotating_light`) podem usar nomes de emoji curtos — renderiza no app.

### Tabela schema (referência)

```sql
CREATE TABLE alertas_uazapi (
  id BIGSERIAL PRIMARY KEY,
  cliente         TEXT NOT NULL,
  uazapi_url      TEXT NOT NULL,
  status_atual    TEXT NOT NULL,
  status_anterior TEXT,
  evento          TEXT NOT NULL CHECK (evento IN ('baseline','queda','lembrete','recovery','probe_falha')),
  disparado_em    TIMESTAMPTZ NOT NULL DEFAULT now(),
  canais_ok       TEXT[] NOT NULL DEFAULT '{}',
  canais_falha    TEXT[] NOT NULL DEFAULT '{}',
  detalhes        JSONB NOT NULL DEFAULT '{}'
);
CREATE INDEX idx_alertas_uazapi_cliente_recente ON alertas_uazapi(cliente, disparado_em DESC);
```

Função wrapper pra usar com o pattern de `WITH ult AS (...)` (ver PostgreSQL Pitfalls "0 rows breaks downstream"):
```sql
CREATE OR REPLACE FUNCTION ultimo_estado_alerta(p_cliente TEXT)
RETURNS TABLE (status_atual TEXT, evento TEXT, disparado_em TIMESTAMPTZ)
LANGUAGE sql STABLE AS $$
  SELECT status_atual, evento, disparado_em
  FROM alertas_uazapi WHERE cliente = p_cliente
  ORDER BY disparado_em DESC LIMIT 1;
$$;
```

---
