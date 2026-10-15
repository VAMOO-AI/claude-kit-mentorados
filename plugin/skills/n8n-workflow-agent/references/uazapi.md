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
POST /chat/check     — { numbers: [...] } → o número existe no WhatsApp? (lote)
GET  /webhook        — lista webhook subscribers (multi)
```

### `/chat/check` — "esse número existe?" é outra pergunta (e a mais barata)

Aceita **lote** e responde por número: 10 números em ~1s.

```jsonc
// POST /chat/check  { "numbers": ["5500999990001", "5500930000002"] }
[
  { "query": "5500999990001", "isInWhatsapp": true,  "jid": "5500999990001@s.whatsapp.net", "lid": "..." },
  { "query": "5500930000002", "isInWhatsapp": false, "jid": "", "error": "the number ...@s.whatsapp.net is not on WhatsApp" }
]
```

**Por que isso importa:** `/message/find` responde *saiu mensagem?* e devolve vazio tanto para "falhamos em enviar" quanto para "esse número nunca existiu". Sem `/chat/check`, as duas viram a mesma acusação ao atendimento. Julgar o número **pelo formato** (13 dígitos, DDD válido, nono dígito) não substitui: os dois números que motivaram isto passavam na régua de formato e não existiam no WhatsApp.

**Sempre cheque as VARIANTES, não só o número gravado.** Num caso real, entre os leads marcados como "sem WhatsApp" a maioria estava morta de verdade, alguns eram de teste e **uma parte era recuperável** — o veredito só consultava a forma gravada.

| Variante | Exemplo |
|---|---|
| sem o nono dígito | `+5500930000002` não existe; `+550030000002` **pode existir** — o `9` foi inserido num fixo, e fixo tem WhatsApp Business |
| sem o `55` prefixado | o número dos EUA (ex.: `+1 555 010 0199`, fictício) pode existir; com `55` prefixado vira `+5515550100199`, que não existe — a normalização tratou como BR (11 dígitos é o tamanho de celular BR **e** de US) |
| o próprio número | às vezes o check anterior deu falso negativo (instância fora do ar na hora) |

Regra dura ao consumir a resposta: **timeout, não-2xx ou resposta faltando = inconclusivo, nunca "não existe"**. Inocentar um disparo que falhou de verdade é pior que deixar a linha em dúvida. E distinga na UI **"não tem WhatsApp"** (encerra o lead) de **"o WhatsApp está em outro número"** (recupera o lead) — são ações opostas.

### UAZAPI é WhatsApp Web não-oficial (uazapiGO = whatsmeow), NÃO Meta Cloud API (regra dura)

O uazapiGO roda sobre o **whatsmeow** (lib Go do protocolo **Multi-Device do WhatsApp Web**), API **não-oficial**. Evidência: os `lastDisconnectReason` devolvidos por `GET /instance/all` são exatamente as mensagens de `ConnectFailureReason` do whatsmeow, e o `WHATSAPP_REACHOUT_TIMELOCK` corresponde ao evento `NotifyAccountReachoutTimelock` do whatsmeow. Implicações práticas que confundem mesmo quem conhece a Cloud API oficial:

- **NÃO** há janela de 24h nem template aprovado (regras da Cloud API não se aplicam). **MAS o WhatsApp aplica restrição própria por volume/qualidade**: erro **463 `WHATSAPP_REACHOUT_TIMELOCK`** (UAZAPI devolve 500 com esse `error_key`, `enforcement_type: RESTRICT_ALL_COMPANIONS`) — a conta fica temporariamente proibida de **INICIAR conversa com número novo**, mas conversas existentes continuam saindo normal (caso real). Assinatura diagnóstica: alertas pra contatos conhecidos = 200; primeira mensagem pra número novo = falha. Checar `GET /instance/wa_messages_limits`; `last_error` da instância pode estar limpo (um envio OK posterior sobrescreve). Fallback: copiar a mensagem e mandar manual; prevenção: warmup + reduzir volume iniciado pela instância. O fluxo natural é `status: "Pending" → "Sent" → "Delivered" → "Read"` em segundos.
- **NÃO** há message templates. Cada `/send/text` é livre.
- **Risco real é da WhatsApp (não da Meta Business)** — bloqueio por volume/spam pattern do próprio app. Mitigar com aquecimento gradual de número novo (5-7 dias mandando msgs casuais antes de bulk).
- **`isBusiness: true`** no `/instance/status` significa apenas que a CONTA WhatsApp é Business (com perfil comercial visível). Não habilita features da Cloud API — segue sendo WhatsApp Web não-oficial.
- Diagnóstico "mensagem não chega": NUNCA atribuir a regra Meta de 24h. Causas reais: número não tem WhatsApp ativo (**confirme com `/chat/check` e as variantes** — ver acima; não julgue pelo formato), conta bloqueada OU sob 463 REACHOUT_TIMELOCK (só conversas novas — ver acima), Multi-Device da instância caiu (`lastDisconnect` recente), ou usuário só não notou (`/message/find` mostra status real).

### Queda e reconexão: motivo real, escada e pareamento por código

**Versão.** O seu servidor informa a versão em `GET /status` (`build.version`), e ela pode estar atrás do contrato publicado em `docs.uazapi.com`. Campo que só aparece na doc (`type`/`event_id` no webhook `connection`, `history_days`, `request_id`, respostas detalhadas do `/instance/reset`) só vale depois de aparecer num payload real do seu servidor.

**O motivo está em `lastDisconnectReason`** (`GET /instance/all` com admintoken, ou `/instance/status`) — não é genérico. Motivos observados em produção (algumas instâncias ficam sem motivo registrado):

| `lastDisconnectReason` | Significado | Credencial |
|---|---|---|
| `401: logged out from another device` (o mais comum) | aparelho removido/deslogado pelo lado do celular ou do WhatsApp | perdida → re-parear |
| `401: logged out from another device with recentMessage` | variante observada; o sufixo não é documentado | perdida |
| `403: primary device was logged out` | celular principal deslogou, trocou de aparelho ou reinstalou (o whatsmeow também usa para ban) | perdida |
| `QR Code timeout` | alguém iniciou `connect` e não leu o QR/código a tempo | — (não é queda) |
| `disconnected by API` | alguém chamou `POST /instance/disconnect` | apagada |

Outros códigos do whatsmeow, sem caso observado aqui: **402 TemporaryBan** com `Code` 101 (mensagens para quem não te tem na agenda), 102 (muitos bloqueios), 103 (grupos demais com desconhecidos), 104 (mesma mensagem para muitos), 106 (lista de transmissão); **405** client outdated; **406** logout desconhecido (BANNED); `StreamReplaced` = sessão duplicada (dois processos/painéis com a mesma sessão); `KeepAliveTimeout` = rede/proxy.

**`GET /status` é público** (sem token) e traz `instance_counts.{connected,reconnecting,queued_reconnect,disconnected,hibernated}`. Várias instâncias caindo na mesma janela = incidente do servidor/uazapi, não do número.

**Escada de reconexão.** Roda ASSÍNCRONA, depois de responder 200 ao webhook; uma por instância de cada vez, com trava.

| Degrau | Ação | Leitura |
|---|---|---|
| 1 | esperar ~2 min e reler status | voltou sozinha = transitória, para aqui |
| 2 | `POST /instance/reset` | 200 aceito/em andamento/cooldown; 403 bloqueado pela política; **409 "não reconectável por reset" = forte sinal de credencial perdida** |
| 3 | `POST /instance/connect {"phone": <número do cadastro>}` | 409 = já há pareamento em andamento, só leia status; 429 limite de conexões; 503 + `Retry-After`. Voltou `connected` sem `paircode` = credencial intacta; veio `instance.paircode` = credencial perdida |
| 4 | enviar o código out-of-band ao dono | ver pareamento por código abaixo |

`type: TemporaryBan` ou campo `temporaryBan` → **NÃO reconectar**, alertar com o prazo. **Nunca `/instance/disconnect` como conserto.**

**Pareamento por código no lugar do QR.** `POST /instance/connect` com `phone` devolve `instance.paircode` (formato `XXXX-XXXX`); o dono digita em WhatsApp → Aparelhos conectados → Conectar com número de telefone — sem câmera nem segunda tela. O código é credencial: só para o contato do dono já cadastrado, nunca em log. Validade não documentada (medir). **Re-parear SEMPRE exige humano com o celular**: é regra do WhatsApp, nenhum endpoint contorna.

**A validar:** se `connect` com `phone` numa instância ainda pareada só reconecta sem gerar código (a doc diz que "instância já pareada reconecta sem pedir histórico").

**Prevenção.** Conta Business (a doc avisa que WhatsApp comum desconecta mais); a doc recomenda `browser: "auto"` e `systemName` em branco "para maior estabilidade" (confira se as suas instâncias não usam `systemName` custom); regra dos 14 dias (ver `/kit-vamoo:whatsapp-inbox-stack` #11).

### Phone normalization — leading 9 do mobile brasileiro (CRÍTICO)

WhatsApp normaliza números móveis brasileiros removendo o `9` extra do prefix. Exemplo: você manda `/send/text` com `number: "5500999990001"` (13 dígitos, com 9 do mobile) e o webhook retorna `chatid: "550099990001@s.whatsapp.net"` (12 dígitos, sem o 9).

| Forma | Quando aparece |
|---|---|
| `5500999990001` (13 dig, com 9) | Como você envia no body `/send/text`. Usuário tipicamente fornece nesse formato. |
| `550099990001` (12 dig, sem 9) | Como UAZAPI devolve no `chatid`, no webhook payload, e nos chats do WhatsApp Web (whatsmeow). |

**Implicação grave:** filtros tipo `BLOCKED_PHONES`, dedup keys (`PAUSA_<AGENTE>_<phone>`, `DEDUP_<phone>`), e qualquer lookup por phone precisam usar a versão **normalizada (sem o 9)** porque é o que o `chatid` retorna ao webhook. Se você popular essas keys com a versão de 13 dígitos, o filtro nunca casa.

Padrão de extração no Code node (consistente com o resto da skill):
```js
var rawPhone = msg.chatid ? msg.chatid.replace(/@.*$/, '') : (chat.phone || '');
var phone = rawPhone.replace(/\D/g, '');  // já vem normalizado (sem 9) do chatid
```

Se você precisa ENVIAR pra um número que veio no formato normalizado de 12 dígitos, pode mandar assim — UAZAPI aceita os dois formatos no `/send/text`.

#### O irmão desse bug: `+55` colado em número estrangeiro

Toda normalização "se não tem DDI, prefixe 55" quebra em número internacional de **11 dígitos**, porque é exatamente o tamanho de um celular BR sem DDI. `+1 555 010 0199` (EUA) vira `+5515550100199`, que não existe — e a pessoa fica inalcançável enquanto conversa normalmente pelo número real.

O que separa os dois é o **dígito depois do DDD**, sempre `9` num celular brasileiro:

```js
// 11 dígitos: só é BR se o 3º dígito for 9 (e o DDD for >= 11)
if (d.length === 11 && Number(d.slice(0,2)) >= 11 && d[2] === '9') return '+55' + d;
if (d.length === 10 && Number(d.slice(0,2)) >= 11) return '+55' + d;  // fixo
if (d.length === 11) return '+' + d;                                   // internacional
return null;                                                           // acima disso, não afirme
```

Dois cuidados aprendidos apanhando:

1. **Não aceite `length >= 11` como internacional.** Espelhos costumam ter lixo de 14–19 dígitos (IDs de formulário, `99999999999999`) nesses campos; aceitá-los transforma "sem telefone" em "telefone que não existe". Num caso real, a primeira versão do patch sujou registros antes de a medição pegar.
2. **Se houver DUAS normalizações (SQL e app), elas mudam juntas ou não mudam.** Havia uma função de normalização no Postgres (usada por views e coluna gerada) e outra no TypeScript. Como o join comparava o E.164 inteiro, a distorção era **simétrica** e os joins fechavam por causa dela; corrigir só um lado quebrou o casamento por telefone e teve de ser revertido.

### Grupos: LID (autor) + JID (envio) — NÃO são telefone (CRÍTICO)

**Autor em grupo é LID, não telefone.** Em mensagens de grupo (`@g.us`), o autor vem como **LID** (id anônimo do WhatsApp, ex.: `123456789012345`), às vezes com sufixo de device (`:25`). Heurística: LID tem **≥14 dígitos**; telefone BR tem 12-13.

```js
// strip do @server e do :device ANTES de extrair dígitos —
// replace(/\D/g,'') direto corrompe o id (ex.: '1234:5' vira '12345')
var authorId = rawAuthor.replace(/@.*$/, '').split(':')[0].replace(/\D/g, '');
var isLid = authorId.length >= 14;
```

- O snippet de extração de phone desta skill (`rawPhone.replace(/\D/g,'')`) vale pra chat 1:1; pra id de AUTOR em grupo, use o strip acima.
- Matching por telefone (`.eq('phone')`) contra LID NUNCA casa. Detecção de "mensagem da própria instância" em grupo precisa dos DOIS ids: o phone E o LID da instância (guarde ambos em config; atualize os dois ao migrar de instância).
- Avatar/nome de autor LID: `GetNameAndImageURL` aceita `<lid>@lid` (verificado em produção).

**Envio pra grupo exige o JID** (`120363…@g.us`) — só o NOME do grupo não envia nada (falha silenciosa; caso real: badge "Ativo" + nome davam impressão de pronto e a publicação falhava). O JID só é conhecido depois da 1ª mensagem inbound do grupo (webhook) ou listando chats via API. UI de config deve preferir picker de grupos já detectados (JID não-vazio) a texto livre.

**Matching phone × banco (nono dígito):** o phone extraído de JID pode vir SEM o nono dígito (`550099990001`) enquanto o cadastro guarda COM (`5500999990001`). Igualdade estrita falha silenciosa — no lookup gere as variantes com/sem 9 (`.in('phone', variantes)`, num helper único do projeto; nunca cópia local de normalização, cópia divergente já causou bug) e na escrita grave canônico só-dígitos.

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
- **`POST /webhook` SEM `action`** (modo simples) **NÃO cria um novo subscriber**: faz **upsert single-by-instance** e sobrescreve o array inteiro pra ter só 1 entry, mesmo com `id` ausente ou URL diferente.
- **`POST /webhook` com `action:"add"` ADICIONA** um subscriber e preserva os existentes. Medido numa instância que já tinha 2 webhooks: `{"action":"add","enabled":true,"url":"<url>","events":["messages"],"excludeMessages":["wasSentByApi"]}` criou o 3º, e o `GET` antes e depois mostrou os 2 originais intactos. Erro comum: achar que só o painel adiciona webhook e montar o 2º na mão.
- **Painel admin** (`uazapi.dev` → Configurar Webhooks → **"Salvar com um novo"**) também adiciona; cada save gera um `id` distinto.
- **Editar um subscriber sem recriar:** `action:"update"` + o `id` do `GET` preserva o registro — runbook em `/kit-vamoo:whatsapp-inbox-stack` #11 (confira no `GET` final que os outros continuam).

**Implicação prática:** um `POST /webhook` sem `action` em prod **desativa o webhook ativo do agente** (sintoma: agente para de responder). Mesmo com `action:"add"`, salve o `GET` antes e confira o `GET` depois. Rollback pronto:
```bash
curl -X GET https://<inst>.uazapi.com/webhook -H "token: $TOKEN" > /tmp/webhook-backup.json
# se sobrescrever, restaurar com POST do entry original
```

### `excludeMessages` flags (CRÍTICO)

| Flag | Efeito |
|---|---|
| `wasSentByApi` | **Não dispara webhook pra mensagens enviadas pela própria API** (suprime echo de `fromMe=true`). Use no webhook do agente IA pra ele não receber as próprias respostas. |
| `isGroupYes` | Suprime mensagens de grupos `@g.us`. Quase sempre desejável. |

**Pro mirror Chatwoot espelhar `outgoing` da IA**, o webhook do mirror precisa **NÃO** ter `wasSentByApi` (caso contrário não recebe `fromMe=true` da resposta da IA, e o admin não vê no Chatwoot o que a IA respondeu). Configure separadamente do webhook principal do agente, no painel UAZAPI ou via `POST /webhook` com `action:"add"`.

### Payload Webhook Inbound UAZAPI (CRITICO)

**NUNCA assuma formato flat.** UAZAPI envia aninhado:

```json
{
  "chat": {
    "phone": "+55 00 9999-0001",
    "wa_chatid": "550099990001@s.whatsapp.net",
    "name": "Nome do Contato"
  },
  "message": {
    "chatid": "550099990001@s.whatsapp.net",
    "text": "Conteúdo",
    "content": "Conteúdo",
    "fromMe": false,
    "messageType": "Conversation",
    "messageid": "3EB0XXXXXXXXXXXXXXXX",
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
var msgType = (msg.messageType || '').toLowerCase();
// GATE por tipo (CRÍTICO): em mídia (video/image/audio/document), msg.content é um OBJETO
// (URL .enc + mediaKey + fileEncSHA256 + mimetype). `msg.text || msg.content` deixa esse
// objeto virar JSON cru no campo de texto do DB (bug real). Só copie content
// em tipo de texto — e mesmo assim só se for string.
var isTextType = /^(text|chat|conversation|extendedtextmessage)$/.test(msgType);
function asStr(v) { return typeof v === 'string' ? v : ''; }
var texto = isTextType
  ? (asStr(msg.text) || asStr(msg.content) || '')
  : (asStr(msg.text) || asStr(msg.caption) || '');
var fromMe = msg.fromMe === true;
var messageId = msg.messageid || '';
```

**Defesa em profundidade no boundary (edge fn/DB):** regex `^\s*\{.*"(URL|directPath|mediaKey|fileEncSHA256|mimetype)"` no campo de texto → null; frontend usa placeholder por tipo (🎥/🖼️/🎵/📎), nunca o blob cru.

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

---

## Out-of-Band Uptime Watcher (REGRA DURA)

**Princípio:** o canal de notificação de "X caiu" NUNCA pode ser o próprio X. Watcher de UAZAPI de cliente vai em **n8n + UAZAPI de OUTRO tenant** (tipicamente um n8n de monitoramento numa infra que não é a do cliente, com uma instância UAZAPI em outro servidor). Notificação out-of-band.

**Anti-pattern (real):** schedule trigger no mesmo n8n do cliente → `GET <instancia-do-cliente>.uazapi.com/instance/status` (UAZAPI do cliente) → IF disconnected → `POST <instancia-do-cliente>.uazapi.com/send/text` (mesma UAZAPI caída). Dependência circular: quando UAZAPI cai, `/send/text` também cai. Zero alerta.

### Topologia

```
n8n monitor   ── Schedule 5min ──┐
(outra infra)                    ↓
                  GET <cliente>.uazapi.com/instance/status
                                 ↓ (probe usa token DO CLIENTE)
                        ┌────────┴────────┐
                     connected      ≠ connected
                                 ↓
                  Postgres do monitor: read last_state
                                 ↓
                       Decide: queda / lembrete / recovery / probe_falha
                                 ↓ fan-out paralelo 3 canais
                ┌────────────────┼────────────────┐
                ↓                ↓                ↓
        WhatsApp                Email           Push
        (UAZAPI outro servidor) (Resend)        (ntfy.sh)
                                 ↓
                        Postgres do monitor: log execution
```

### State machine + dedup (Postgres, não Redis)

Tabela `monitor_alertas` em Postgres centraliza estado. Função `ultimo_alerta(alvo)` retorna o último registro. State machine no Code node "Decide Action":

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
| WhatsApp (UAZAPI de outro servidor) | Mesmo host do cliente cair junto (servidor UAZAPI multi-tenant compartilhado); número Business novo sem warmup; destinatário com WhatsApp off |
| Email (Resend/SES) | DNS bloqueando, spam folder, MX problem |
| Push (ntfy.sh) | App push desinstalado, token de subscriber expirado |

Pelo menos 1 dos 3 chega em ~100% dos cenários reais.

### Gotcha: ntfy.sh Title header não aceita Unicode

`Title:` header é RFC-7230 (ASCII strict). Mandar emoji direto:
```
Title: ⚠️ UAZAPI CLIENTE-X desconectada
```
retorna `Invalid character in header content ["title"]`. Mover emoji pro **body** (que é UTF-8 livre) ou strip-and-encode na expressão:
```
Title: UAZAPI CLIENTE-X desconectada  ← ASCII puro no header
body:  ⚠️ Detalhes aqui...           ← emoji vai no body
```

Tags do ntfy (`Tags: warning,rotating_light`) podem usar nomes de emoji curtos — renderiza no app.

### Tabela schema (referência)

```sql
CREATE TABLE monitor_alertas (
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
CREATE INDEX idx_monitor_alertas_cliente_recente ON monitor_alertas(cliente, disparado_em DESC);
```

Função wrapper pra usar com o pattern de `WITH ult AS (...)` (ver PostgreSQL Pitfalls "0 rows breaks downstream"):
```sql
CREATE OR REPLACE FUNCTION ultimo_alerta(p_alvo TEXT)
RETURNS TABLE (status_atual TEXT, evento TEXT, disparado_em TIMESTAMPTZ)
LANGUAGE sql STABLE AS $$
  SELECT status_atual, evento, disparado_em
  FROM monitor_alertas WHERE cliente = p_alvo
  ORDER BY disparado_em DESC LIMIT 1;
$$;
```

---
