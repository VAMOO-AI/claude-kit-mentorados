# whatsapp-inbox-stack — thread picada, sessão que cai e entrega (#10 a #12, #21 a #23)

Lido no passo 3 do SKILL.md, antes de mexer em status de sessão, webhook do provider, confirmação de entrega ou retentativa de aviso.

### #10 — Inbox "vazio" é thread picada, não bug de fetch (Chatwoot)
Sintoma: a lista mostra o contato, mas ao abrir só aparece a última mensagem — como se o histórico tivesse sumido. Quase nunca é o fetch. É o **mirror inbound** abrindo conversa nova: se o nó de resolve filtra só `open|pending`, toda mensagem que o cliente manda depois de uma conversa resolvida (transferência, cron, CSAT) cria outra thread com uma mensagem só. Se a UI lista "uma linha por contato, a mais recente" e busca mensagens por `conversationId`, ela mostra justamente a thread nova e vazia.

Diagnóstico em 1 chamada — `GET /contacts/{id}/conversations` e conte: mais de uma no mesmo inbox = fragmentado, e o histórico está na resolvida. Corrija no mirror (reaproveitar a resolvida + reabrir), não na UI; ver `n8n-workflow-agent/references/chatwoot.md` § Conversa: Find or Create (`/kit-vamoo:n8n-workflow-agent`). Fix não retroage — o que já fragmentou continua dividido.

Corolário: com a IA pausada, o log do agente **não** é histórico de conversa. O guard de pausa costuma cortar o fluxo antes do nó que grava o inbound, então tudo que o lead escreve depois da transferência não existe no log — só no Chatwoot.

### #11 — Ninguém sabe que a sessão caiu, e "enviado" não é "entregue"
Vale pra QUALQUER provider por QR (UAZAPI, Evolution, qualquer coisa em cima de Baileys/whatsmeow). Dois pontos cegos que sempre vêm juntos e só aparecem quando alguém olha um celular.

**a) A coluna de status mente.** O padrão errado: `<tabela de canais>.status` com default `'desconectado'`, alguém marca `'conectado'` na mão no dia do setup, e ninguém nunca mais escreve. Num caso real isso segurou o alerta zerado por mais de uma semana, enquanto **avisos de lead falhavam em silêncio** — descobertos por acaso. Se nenhum código faz UPDATE naquela coluna, ela não é status, é decoração; `<coluna de última atualização> NULL` é o teste de 1 segundo.
Correto: assinar o evento `connection` do provider e escrever status + timestamp a cada transição. Cron batendo no `/instance/status` como rede — se o provider cair inteiro, o webhook também não chega.
**Estado que você não reconhece não escreve nada.** Um `desconectado` falso dispara alerta e queima a credibilidade dele; guarde o valor cru no log de eventos e ajuste o mapa quando vir o primeiro evento real. Estado `hibernated` (sessão pausada com credenciais preservadas) conta como não-entregando.

**b) 2xx do provider ≠ mensagem entregue.** `POST /send/text` respondendo 200 só diz que o provider ACEITOU — vários enfileiram internamente. Sem assinar `messages_update` você nunca sabe se chegou. Sintoma de diagnóstico: rode um `group by status` na tabela de mensagens; se **nada jamais avançou de `sent`**, você está cego (num caso real eram centenas de mensagens, zero confirmações, e uma pendência aberta esperando um humano confirmar por telefone se o vendedor recebeu).
Semântica do check na tela: ✓ quando o provider aceitou (`accepted`, ~3 s), ✓✓ na entrega, azul na leitura. Mostrar relógio até a entrega deixa "enviando" por ~1 min (depende do celular de quem recebe) com a mensagem já no WhatsApp. "Respondida" no SLA conta só com entrega confirmada. O parser que move esse estado é o #21.

**c) A armadilha de LIGAR a assinatura.** Duas, e as duas mordem:
- `POST /webhook` em modo simples **substitui** o webhook único. Mandar `events:["connection","messages_update"]` derruba `messages` e para a ingestão de lead inteira. Sempre **read-then-write**: `GET /webhook` primeiro, depois POST com a UNIÃO dos eventos atuais mais os novos, mesma url, preservando `excludeMessages`.
- Se a rota trata status com `if (ehStatus && messageid && statusMapeado)`, um `messages_update` com status que o seu mapa não conhece (`SERVER_ACK`, `PLAYED`, `PENDING`, códigos numéricos) **cai no fluxo de ingestão de lead** e cria contato + negócio + atribuição fantasmas, com WhatsApp real pra alguém. Fica dormente enquanto o evento não é assinado — **assinar é o que arma**. Faça o early-return ser do EVENTO, não do status reconhecido; aí o fall-through é impossível independente do que o provider mandar.

**d) Os 14 dias do celular principal (e 30 do aparelho conectado).** Pela FAQ oficial do WhatsApp (faq.whatsapp.com, "About linked devices"): **celular principal** sem usar o WhatsApp por mais de 14 dias desloga todos os aparelhos conectados; e um **aparelho conectado** inativo por 30 dias também é desconectado. **Não existe endpoint que renove isso** — só estar conectado renova. `/instance/presence` NÃO é keep-alive (exige já estar conectado). `/instance/status` detecta, `/instance/reset` recupera runtime travado, `/instance/connect` repareia — com `phone` devolve um código de pareamento que o dono digita no celular (dispensa câmera/segunda tela); humano com o aparelho continua obrigatório. **Nunca `/instance/disconnect` como tentativa de conserto** — apaga as credenciais e força QR novo.
Motivo real da queda (`lastDisconnectReason`) e escada de reconexão: `n8n-workflow-agent/references/uazapi.md` § Queda e reconexão (`/kit-vamoo:n8n-workflow-agent`).
Diagnóstico de saúde da sessão: **a prova é o inbound**, nunca o outbound. Uma mensagem recebida só entra com socket conectado; `sent` não prova nada (ver b).

**Desenho preferido: dois destinos, um por trabalho.** Em vez de um webhook único com a união dos eventos, crie dois com `action:"add"`, um de cada vez, com `GET /webhook` antes e depois:

```jsonc
{ "action":"add", "enabled":true, "url":"<inbound>", "events":["messages"],
  "excludeMessages":["wasSentByApi"] }          // o inbound não recebe o eco da própria API
{ "action":"add", "enabled":true, "url":"<ack>", "events":["messages_update"] }  // sem filtro: o ACK recebe tudo
```

Com isso as confirmações de entrega das mensagens enviadas pela API chegam (✓✓ funcionando em produção num inbox real). Em endereços separados, ACK nunca vira mensagem; se os dois eventos forem ao **mesmo** endereço, descarte pelo tipo do **EVENTO**, nunca por "tipo contém `message`" (um `isInboundMessageEvent` assim transforma ACK em mensagem fantasma).

**Runbook — alternativa: um webhook só, ligando a assinatura sem derrubar a ingestão** (validado em produção):

```bash
TOKEN='<token DA INSTÂNCIA>'   # não é o Admin Token: /webhook recusa o admin com 401
HOST=https://<sub>.uazapi.com

# 1) LER. GET /webhook devolve um ARRAY — pode haver mais de um webhook.
curl -s "$HOST/webhook" -H "token: $TOKEN" | jq

# 2) POST com action:"update" + o id lido, repetindo url/excludeMessages/flags
#    e somando os eventos novos aos que já existiam.
curl -s -X POST "$HOST/webhook" -H "token: $TOKEN" \
  -H 'content-type: application/json' -d '{
  "id": "<id do passo 1>", "action": "update", "enabled": true,
  "url": "<a MESMA url do passo 1>",
  "events": ["messages", "connection", "messages_update"],
  "excludeMessages": ["wasSentByApi"],
  "addUrlEvents": false, "addUrlTypesMessages": false }' | jq

# 3) CONFERIR que messages continua lá e que não nasceu webhook duplicado
curl -s "$HOST/webhook" -H "token: $TOKEN" | jq '.[] | {id, events, url}'
```

**`isGroupYes` só entra no `excludeMessages` quando o projeto não atende grupo** (agente de IA 1:1). Num inbox que atende grupo, ele derruba a mensagem de grupo **sem erro nenhum**.

Com `action:"update"` + `id` o registro é preservado; é o modo simples (sem `action`) que substitui e derruba `messages`. Um 401 aborta antes de tocar na config — falha de token não quebra nada.

**Contornado (não provado):** `excludeMessages:["wasSentByApi"]` poderia filtrar também os `messages_update` das mensagens que a própria API enviou, que são as que interessam para a entrega. Se o filtro age ou não sobre o `messages_update` continua sem resposta na doc, e com os dois destinos acima não importa mais. No webhook único, ligue e meça: se em um dia não chegar nenhum `messages_update`, tire `wasSentByApi` do filtro (o loop-guard da rota protege contra o eco). `connection` não é mensagem e não sofre esse filtro.

**Depois de ligar, não conclua nada pelo silêncio.** `connection` só dispara em TRANSIÇÃO de estado — sessão estável não emite nada, e isso é sucesso, não falha. A primeira prova real chega na próxima queda.

### #21 — O `messages_update` real não tem `message`, e o ACK fica preso em "aceito"
**Bug real:** o handler de ACK lia `body.status` e `body.messageId`. Esses campos não existem no `messages_update` da UAZAPI, o código lançava em todo ACK, e **nenhuma mensagem saiu de `accepted` por ~3 meses**. Ninguém percebeu porque o envio funcionava.

Forma real do evento:
- vem em `body.event` (objeto) ou `body.data`. Concatenar como string vira `'[object Object]'`;
- os ids vêm em **`event.MessageIDs` (array: um recibo cobre várias mensagens)**, com fallback `event.messageid`/`messageId`/`id`;
- o estado vem em `event.Type` (fallback `type`, `status`, `body.state`, `body.ack`);
- **o id chega com prefixo `numero:`**: canonize com `id.split(':').pop()` para casar com o `provider_message_id` gravado no envio;
- a instância se identifica por `body.owner` (o número), não por `instanceId`.

Mapa de estados que funciona:
```js
{ sent:'sent', server_ack:'accepted', pending:'accepted', delivered:'delivered',
  delivery_ack:'delivered', read:'read', played:'read', error:'failed', failed:'failed',
  accepted:'accepted', '1':'accepted', '2':'sent', '3':'delivered', '4':'read' }
```
- `Retry`, `Sender`, `Inactive` e afins não movem a entrega: devolva `skip`, mas **responda 200** mesmo assim (no n8n, um IF desvia; sem item o `Respond` não roda).
- Timestamp em segundos: `n < 1e12 ? n*1000 : n`.
- **Prova:** depois de ligar, rode o `group by status` do #11b de novo. Precisa aparecer `delivered`/`read`. Ficar só em `accepted` quer dizer que o parser está errado.

### #22 — Envio para grupo fica em "Enviando" para sempre
**Bug real:** em grupo, a UAZAPI manda `messages_update` com `Type: "GroupReceipts"` e o estado de cada participante em `event.Receipts[].state` (`Delivered`/`Read`). O mapa do #21 não conhecia `GroupReceipts`, descartava, e toda mensagem para grupo ficava em "Enviando".

```js
if (String(rawStatus).toLowerCase() === 'groupreceipts') {
  const states = (ev.Receipts ?? ev.receipts ?? []).map(r => String(r?.state || '').toLowerCase());
  rawStatus = states.some(s => ['delivered','read','played'].includes(s)) ? 'delivered' : '';
}
```
- Grupo **para em `delivered`**: "lida" exigiria saber que todos leram, e o recibo traz só quem respondeu.
- **Prova:** código ensaiado contra 5 retornos reais de produção, todos viraram `delivered`.

### #23 — O token da instância vem dentro do webhook
O payload da UAZAPI traz `body.token`, que autoriza `/send/*` naquele número. Quem grava o payload cru (`raw_payload`, `message_acks`, log de eventos) guarda uma credencial de envio.
- **Conserto:** `const { token: _t, ...rawSafe } = body;` antes de gravar ou repassar.

### #12 — Queda longa estoura o teto de retentativa, e os avisos NÃO voltam sozinhos
Todo sistema de aviso sério tem retentativa com teto (por exemplo, 5 tentativas com backoff crescente). O que ninguém percebe até acontecer: **uma queda mais longa que teto × backoff consome todas as tentativas e deixa o aviso morto em `failed` para sempre**. Quando a sessão volta, ele não sai — saiu da fila.

Os que chegam ao teto ficam mudos para sempre: lead atribuído no CRM, vendedor sem saber.

Diagnóstico depois de qualquer reconexão — não confie no "voltou, então normalizou" (`avisos` é a tabela onde cada atribuição registra o aviso ao dono; troque tabela e colunas pelos nomes do seu schema):

```sql
select status, tentativas, count(*)
from avisos where created_at > now() - interval '24 hours'
group by 1,2 order by 2 desc;
```

Linha com `failed` no teto = aviso órfão. Para reenviar, zere o contador (o texto original tem que estar guardado numa coluna, senão sai aviso genérico ou nada).

⚠️ **Não zere em bloco.** Entre a falha e agora, a atribuição pode ter sido **redistribuída** (SLA, roleta, reatribuição manual). Reenviar para o dono original manda um vendedor atrás de lead que não é mais dele — e duas pessoas ligam para o mesmo cliente. Num caso real, parte dos órfãos era de um contato redistribuído menos de uma hora depois da falha; esses ficaram de fora do reenvio de propósito. Cheque o dono ATUAL antes:

```sql
select telefone, dono_id, motivo, created_at
from avisos where telefone in (<os telefones dos órfãos>)
order by telefone, created_at;
```

Mesmo telefone com `dono_id` diferente e `motivo='<redistribuicao>'` (o valor que a sua regra de SLA ou roleta grava) depois da falha = redistribuído, não reenvie para o antigo.
