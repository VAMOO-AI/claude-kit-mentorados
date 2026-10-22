---
name: whatsapp-inbox-stack
description: >-
  Inbox/chat de WhatsApp sobre n8n + Supabase (página própria ou Chatwoot, via
  NotificaMe ou UAZAPI): mídia que não chega ou não toca, IA e humano no mesmo
  fio, sessão que cai ou mensagem sem confirmação de entrega, relatório de quem
  falou com o lead. O workflow n8n em si é da n8n-workflow-agent.
---

# WhatsApp Inbox Stack

Padrão reutilizável pra montar um inbox de WhatsApp COMPLETO (mídia inclusa). Nasceu de produção — **cada gotcha abaixo corrigiu um bug real**. Este arquivo é o roteador + o checklist anti-recorrência. Código copia-e-cola em `references/media-pipeline.md`.

Pra construir/editar o WORKFLOW n8n em si (Code Node, API, layout, UAZAPI/NotificaMe/Chatwoot outbound), rode **`/kit-vamoo:n8n-workflow-agent`**. Esta skill foca na ponta inbox: schema + render + storage + edge + os gotchas que ninguém vê até quebrar em prod.

## Duas arquiteturas (decida primeiro)

| | **A — Chatwoot É o inbox** | **B — página própria + Supabase** |
|---|---|---|
| UI | Chatwoot (web/app) | React/Next próprio |
| Mídia | **nativa** (Chatwoot baixa, transcodifica, toca) | **você faz tudo**: baixar, transcodar, storage, assinar, renderizar |
| Quando | cliente já usa Chatwoot, sem UI custom | inbox embutido no seu app (ex: uma aba de atendimento) |
| Exemplos | agente de vendas que responde dentro do Chatwoot | inbox próprio com mídia, embutido no app |
| Esforço de mídia | baixo (attachments[]+source_id, ver `n8n-workflow-agent/references/chatwoot.md` via `/kit-vamoo:n8n-workflow-agent`) | **alto** — é onde moram TODOS os gotchas abaixo |

Se for **A**, a maior parte desta skill não se aplica (Chatwoot resolve mídia). Se for **B**, leia tudo: a página própria precisa reimplementar o que o Chatwoot dá de graça, e cada etapa tem uma armadilha.

## Pipeline de mídia inbound (arquitetura B)

```
Provider webhook (NotificaMe/UAZAPI)
  → n8n: Normaliza (NÃO derrube mídia sem legenda! ver gotcha #7)
  → n8n: Brain Query → INSERT <agente>_messages (content_type, media_url=path|null)
  → n8n: IF mídia? → Ingerir Mídia (HTTP → edge function; timeout 300s; passa inbound_id)
        → edge: baixa o binário (proxy, NÃO a lookaside direta — gotcha #5)
        → edge: upload do ORIGINAL pro bucket PRIVADO → devolve o PATH (rápido — gotcha #9)
        → edge (background waitUntil): áudio ogg/opus → MP3 + Whisper + PATCH media_url (gotcha #2, #9)
  → n8n: UPDATE media_url = path (path pode ser .ogg no 1º beat; realtime troca pra .mp3 depois)
  → front: listMessages ASSINA o path no read (signed URL) → <audio>/<img>
```

Modelo canônico da mensagem: `content_type` (text|audio|image|document|sticker|template|…) + `media_url` (PATH do bucket privado, não URL pública) + `content` (legenda/texto). O front assina o path on-read; valores `http*` ou null passam direto.

## Gotchas de produção

Cada um saiu de um bug real. Os de mídia (#1 a #9) falham sem erro visível — a foto aparece, o `fetch` dá 200, o deploy passa, o áudio toca cortado —, e por isso o pré-flight "áudio toca", logo depois dos gotchas, é o que define pronto.

### #1 — CSP `media-src` (o clássico "áudio não toca, mas foto sim")
Página própria que serve mídia de domínio EXTERNO (Supabase Storage/CDN) **precisa de `media-src` no Content-Security-Policy**. `<audio>`/`<video>` usam a diretiva `media-src`; se ela não existe, cai no `default-src 'self'` e o navegador **BLOQUEIA** ("Loading media violates CSP ... media-src was not explicitly set").
- **Pegadinha que confunde:** `img-src` costuma liberar `https:` → foto funciona → você acha que CSP está ok. Áudio/vídeo usam `media-src`, que é SEPARADO. Foto OK ≠ áudio OK.
- **`fetch()` engana:** `fetch(signedUrl)` usa `connect-src` (que libera o supabase pro app funcionar) → retorna 200. Mas o `<audio>` usa `media-src` → bloqueado. Um `fetch 200` NÃO prova que o `<audio>` vai tocar.
- **Fix:** adicione `media-src 'self' data: https: blob:` ao CSP, em TODOS os lugares onde ele é definido (header HTTP em `vercel.json` E meta `<meta http-equiv>` no `index.html`) — ambos são enforçados, a política efetiva é a INTERSEÇÃO.
- **Service worker:** workbox pode servir `index.html` velho com o meta-CSP antigo. Após deploy → hard refresh (Cmd+Shift+R) ou Unregister do SW (DevTools→Application).
- **Diagnóstico definitivo no navegador:** `const a=document.querySelector('audio'); console.log(a?.src); fetch(a.src).then(r=>console.log(r.status,r.headers.get('content-type')))`. Se o SRC é signed URL https + fetch 200 mas não toca + console tem "violates CSP / media-src" → é ISTO.

### #2 — Transcode opus→mp3 em edge function: `npm:` NUNCA `esm.sh`
WhatsApp manda voz em **Ogg/Opus**, que não toca confiável em `<audio>` HTML5 (Safari nunca decodifica; Chrome instável). Tem que transcodar pra **MP3**. Em Deno/Supabase edge: `ogg-opus-decoder` (decode wasm) + `@breezystack/lamejs` (encode MP3, JS puro).
- **A armadilha:** importe via `npm:ogg-opus-decoder@x`, **NÃO** `https://esm.sh/ogg-opus-decoder@x`. O build esm.sh arrasta `@eshaz/web-worker` → `node:vm`, que o `edge-runtime` do Supabase **não implementa**. O deploy PASSA (o bundler do CLI tolera), mas em RUNTIME o decode lança → cai no fallback (áudio fica .ogg) → não toca.
- **Deno local engana:** tanto esm.sh quanto npm: funcionam no `deno run` local. Só o runtime sandbox da edge quebra. Não confie no teste local de Deno pra validar a edge.
- **Reproduzir o runtime REAL sem deploy:** docker `edge-runtime bundle + start` no mesmo container de prod (comandos prontos em `references/media-pipeline.md` §3) — `supabase functions serve` exige stack local completo, o docker isolado é mais rápido.
- Best-effort: try/catch no transcode → fallback pro original (nunca pior que o estado atual).

### #3 — `verify_jwt` reseta pra ON a cada deploy
Webhook/callback externo (n8n, NotificaMe, Chatwoot, Google) chama a edge **sem header Authorization** e faz auth própria (secret no body / assinatura). Precisa de `verify_jwt` OFF. Mas `supabase functions deploy` **religa verify_jwt=ON** a cada deploy que não passe a flag → o caller externo toma **gateway 401 `UNAUTHORIZED_NO_AUTH_HEADER`** depois de todo push.
- **Distinguir os dois 401:** `UNAUTHORIZED_NO_AUTH_HEADER` = gateway (verify_jwt ON, request nem chega na função) vs `{"error":"<sua msg>"}` = função (verify_jwt OFF, chegou). Probe: `curl -X POST <fn-url> -d '{}'`.
- **Fix durável:** no CI de deploy, passe `--no-verify-jwt` pras funções públicas (allowlist), OU `[functions.<nome>] verify_jwt=false` no `config.toml`. NÃO dependa do toggle do dashboard — ele some no próximo deploy.
- **Auditoria:** TODA função pública (webhook de terceiro sem JWT) precisa disso. Liste-as e marque na allowlist. Funções chamadas pelo front (com JWT do usuário) ou que fazem `auth.getUser` ficam ON.

### #4 — WhatsApp voz = Ogg/Opus (ver #2). Foto = jpg ok. Sticker = webp animado.
Áudio é o único que exige transcode. Foto/documento sobem direto. Sticker (webp) toca como img mas anima.

### #8 — Decoder bufferiza o tail → áudio CORTA no final: use `decodeFile`, não `decode`
`ogg-opus-decoder.decode()` decodifica mas SEGURA os últimos frames num buffer interno; sem `flush()` o áudio sai **cortado no final** (~0.5-1s; em áudios curtos vira fração grande: 3s→2s, 7s→6s). **Fix: use `decoder.decodeFile(opus)`** (decodifica o arquivo completo com flush embutido) — ou `decode()` seguido de `flush()` concatenando os dois.
- **Prova sem original de referência** (parse do `granulepos` da última página ogg vs `samplesDecoded`): receita em `references/media-pipeline.md` §validação.
- **Validação:** afinfo/ffprobe a duração do mp3 final == duração do ogg original. NÃO confie só em "tocou" — toca cortado e parece ok.
- **Irrecuperável:** se a edge NÃO guarda o opus original (só sobe o mp3), áudios já ingeridos com o bug não dá pra re-transcodar (lookaside expirada). Considere guardar o original no bucket (.ogg ao lado do .mp3) como seguro contra bugs futuros de transcode.

### #9 — Áudio longo (~1min+): OOM na edge se transcodificar no caminho crítico
**Sintoma em prod:** `media_url` NULL no banco → UI "Mídia indisponível — tente atualizar…". Áudios curtos funcionam; longos não. Um selo "IA leu: Produto X · Fulano" **NÃO é transcrição Whisper** — é extração de lead (gpt-4o-mini: `<campo de interesse>` + `nome` em `extracted_data`). Transcrição real fica em `extracted_data.transcription` ou `content` (preenchido pelo Whisper em background).

**Log n8n (diagnóstico definitivo):** `GET /executions?workflowId=X&includeData=true` → node `Ingerir Mídia`:
```json
{ "message": "Function failed due to not having enough compute resources (please check logs)" }
```
→ `Atualiza media_url` grava `media_url: null` (neverError continua o fluxo).

**Causa:** transcode opus→PCM na **mesma request** da edge estoura memória/CPU do sandbox Supabase. O arquivo pode ser pequeno (~120KB pra 1min) mas o decode expande pra PCM inteiro na RAM — erro **não** é timeout do n8n (mesmo com 180s).

**Fix (padrão que roda em produção):**
1. **Caminho crítico (sync):** download via proxy NotificaMe → upload do **original** (`.ogg`) → responde `{ ok, path, deferred: true }`. **NUNCA** transcodificar antes do upload/resposta.
2. **Background (`EdgeRuntime.waitUntil`):** re-baixa do Storage (libera buffer do request) → transcode→mp3 → upload `.mp3` → `PATCH media_url` via service_role (`inbound_id` ou `provider_message_id`) → Whisper → `PATCH` transcrição.
3. **n8n node `Ingerir Mídia`:** body inclui `inbound_id` do Brain Query; `timeout: 300000` (só cobre download+upload); `neverError: true` + `onError: continueRegularOutput`.
4. **Front:** realtime em `<agente>_messages` com UPDATE (gotcha #6) troca `.ogg`→`.mp3` sem refresh manual. Chrome toca `.ogg`; Safari precisa do `.mp3` do background.
5. **Mensagens antigas com `media_url` NULL:** irrecuperáveis (lookaside Meta expirou em ~2min). Só reenvio do cliente.

**Anti-pattern:** threshold de bytes (`if size > X defer`) — 1min de voz cabe em ~120KB e ainda OOMa no sync. Regra: **todo áudio opus = fast path + background**, sem exceção por tamanho.

### #5 — NotificaMe mídia inbound: NÃO baixe a `fileUrl` direta
O webhook entrega `contents[0].fileUrl` = URL **lookaside da Meta** (`lookaside.fbsbx.com/...`) que exige token Meta (**401**) e **expira em ~2min**. Não dá pra exibir/baixar direto.
- **Download:** POST a lookaside pro PROXY do NotificaMe: `POST https://api.notificame.com.br/v1/channels/whatsapp/media`, header `X-Api-Token`, body `{from:<channel_id>, to:"whatsapp", contents:[{type:"file", fileUrl:<lookaside>, fileMimeType:"ogg"}]}` → devolve o BINÁRIO. (Mesmo endpoint pra foto.)
- **Janela de ~2min** = baixe na hora do webhook, não depois. Áudios NULL no banco = ingestão falhou na janela (irrecuperável, mídia expirou).
- UAZAPI: a URL de mídia vem utilizável por mais tempo, mas re-hospede igual (não dependa da origem).

### #6 — Bucket privado: assinar on-read + RLS + realtime self-heal
- Bucket **privado**, mime allowlist incluindo `audio/mpeg`. `media_url` guarda o PATH, não URL pública.
- Front assina no read: `storage.from(bucket).createSignedUrls(paths, 3600)`. RLS `authenticated SELECT` no bucket habilita o usuário logado a assinar (anon não — e dá "Object not found", que parece 404 mas é RLS).
- **Self-heal:** a edge faz INSERT (media_url=lookaside/null) e DEPOIS UPDATE (media_url=path). O front só corrige a URL velha se o realtime publicar **UPDATE** (não só INSERT). Garanta a tabela na publication `supabase_realtime` com update=true; senão o áudio fica quebrado até refresh manual.

### #7 — n8n: skip guard derruba mídia sem legenda
O guard comum `if(!phone || !text) skip` mata áudio/foto (que vêm com `text` vazio). Troque por `if(!phone || (!text && !mediaUrl)) skip`. Rotule mídia sem legenda (`content='🎤 Áudio'`) pra nunca gravar balão vazio.

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

**c) A armadilha de LIGAR a assinatura.** Duas, e as duas mordem:
- `POST /webhook` em modo simples **substitui** o webhook único. Mandar `events:["connection","messages_update"]` derruba `messages` e para a ingestão de lead inteira. Sempre **read-then-write**: `GET /webhook` primeiro, depois POST com a UNIÃO dos eventos atuais mais os novos, mesma url, preservando `excludeMessages`.
- Se a rota trata status com `if (ehStatus && messageid && statusMapeado)`, um `messages_update` com status que o seu mapa não conhece (`SERVER_ACK`, `PLAYED`, `PENDING`, códigos numéricos) **cai no fluxo de ingestão de lead** e cria contato + negócio + atribuição fantasmas, com WhatsApp real pra alguém. Fica dormente enquanto o evento não é assinado — **assinar é o que arma**. Faça o early-return ser do EVENTO, não do status reconhecido; aí o fall-through é impossível independente do que o provider mandar.

**d) Os 14 dias do celular principal (e 30 do aparelho conectado).** Pela FAQ oficial do WhatsApp (faq.whatsapp.com, "About linked devices"): **celular principal** sem usar o WhatsApp por mais de 14 dias desloga todos os aparelhos conectados; e um **aparelho conectado** inativo por 30 dias também é desconectado. **Não existe endpoint que renove isso** — só estar conectado renova. `/instance/presence` NÃO é keep-alive (exige já estar conectado). `/instance/status` detecta, `/instance/reset` recupera runtime travado, `/instance/connect` repareia — com `phone` devolve um código de pareamento que o dono digita no celular (dispensa câmera/segunda tela); humano com o aparelho continua obrigatório. **Nunca `/instance/disconnect` como tentativa de conserto** — apaga as credenciais e força QR novo.
Motivo real da queda (`lastDisconnectReason`) e escada de reconexão: `n8n-workflow-agent/references/uazapi.md` § Queda e reconexão (`/kit-vamoo:n8n-workflow-agent`).
Diagnóstico de saúde da sessão: **a prova é o inbound**, nunca o outbound. Uma mensagem recebida só entra com socket conectado; `sent` não prova nada (ver b).

**Runbook — ligar a assinatura sem derrubar a ingestão** (validado em produção):

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
  "excludeMessages": ["wasSentByApi","isGroupYes"],
  "addUrlEvents": false, "addUrlTypesMessages": false }' | jq

# 3) CONFERIR que messages continua lá e que não nasceu webhook duplicado
curl -s "$HOST/webhook" -H "token: $TOKEN" | jq '.[] | {id, events, url}'
```

Com `action:"update"` + `id` o registro é preservado; é o modo simples (sem `action`) que substitui e derruba `messages`. Um 401 aborta antes de tocar na config — falha de token não quebra nada.

**Aberto, não resolvido:** `excludeMessages:["wasSentByApi"]` pode filtrar também os `messages_update` das mensagens que a própria API enviou — que são exatamente as que interessam para confirmação de entrega. A doc não diz. Ligue e meça: se em um dia não chegar nenhum `messages_update`, tire `wasSentByApi` do filtro (o loop-guard da rota já protege contra o eco). `connection` não é mensagem e não sofre esse filtro.

**Depois de ligar, não conclua nada pelo silêncio.** `connection` só dispara em TRANSIÇÃO de estado — sessão estável não emite nada, e isso é sucesso, não falha. A primeira prova real chega na próxima queda.

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

### #13 — Propriedade de canal: quem responde não é quem grava
Todo inbox sério acaba com três emissores possíveis no mesmo fio — a IA, o humano no Chatwoot e a API/rotina de aviso. O jeito comum de arbitrar isso é um interruptor de pausa no começo do fluxo, e ele produz o buraco documentado no corolário do #10: **com a IA pausada, o guard corta antes do nó que grava o inbound**, e tudo que o lead escreveu depois da transferência não existe no log — só no Chatwoot. Quando alguém vai auditar a conversa, faltam justamente as mensagens do período em que um humano estava conduzindo.

A causa é modelar pausa como interruptor do fluxo inteiro em vez de **propriedade do canal**.

**A regra, em uma linha: propriedade de canal decide quem RESPONDE, nunca quem GRAVA.**

O modelo são dois campos independentes, nunca um só:

- **estágio do funil** — `novo`, `qualificado`, `proposta`, `ganho`… (onde o negócio está)
- **dono do canal** — `ia` · `humano` · `api_oficial` · `aguardando_inbound` · `nao_contatar` (quem pode falar agora), com `dono_desde` e `dono_motivo`

Consequências práticas:

- Ordem obrigatória no fluxo: **gravar inbound → resolver dono → decidir envio**. Todo guard de pausa fica depois da gravação, nunca antes.
- Quem não é dono **não envia**. Humano assumiu → a IA não manda nem "posso ajudar em mais alguma coisa"; a rotina de follow-up também respeita o dono, senão o cron atropela a conversa humana às 9h da manhã.
- Handoff é `UPDATE` explícito no dono, com motivo e timestamp — não um `pausado_ate` que expira sozinho. Pausa por tempo devolve o fio para a IA no meio de uma negociação humana, e ninguém liga uma coisa à outra.
- Estágio e dono mudam por razões diferentes: `ganho` com dono `humano` é normal, e forçar os dois no mesmo campo faz você escolher entre perder o funil ou perder o controle de quem fala.
- Nunca dois emissores no mesmo fio. Se duas rotas podem enviar, a trava é o dono — não a esperança de que não coincidam.

**Prova (2 minutos, e é o teste que ninguém faz):** transfira uma conversa para humano e mande 3 mensagens como lead. As 3 têm que aparecer na sua tabela de mensagens, e nenhuma resposta automática pode sair. Se o log tem 0 mensagens, o guard está antes da gravação — é o bug, não a configuração.

### #14 — O webhook de CONTA é a prova de contato; o `agent_name` não diz quem falou
Vale para arquitetura A com um inbox por vendedor (o padrão quando cada um tem seu WhatsApp corporativo). Dois fatos que sempre vêm juntos:

**a) Um webhook de conta já cobre o time inteiro.** `POST /accounts/{id}/webhooks` com `message_created` recebe as mensagens de **todos** os inboxes, não só do inbox da IA. Se você grava essas linhas numa tabela de auditoria, ganha de graça a resposta para "alguém do nosso lado falou com este telefone, e quando" — sem varrer a API conversa por conversa (que serializa e custa segundos por renderização). Num caso real essa tabela tinha milhares de mensagens e centenas de telefones que a timeline do CRM não via, porque ela só consultava os logs do agente de IA: lead atendido pelo vendedor aparecia como **"ninguém falou com o lead"**, e isso fazia a IA parecer negligente na cobrança. A prova estava no banco havia meses, num lugar que ninguém consultava para essa pergunta.

**b) `sender.name` / `agent_name` é a conta do token, não a pessoa.** Quando o espelho outbound do n8n posta a mensagem do vendedor no Chatwoot, ela entra com `sender.type: "user"` e o nome do dono do **token de API** — todas as mensagens do time estavam atribuídas ao mesmo agente. Quem falou de verdade só se descobre pelo **`inbox_id` da conversa** (`GET /accounts/{acc}/conversations/{id}`). Relatório de produtividade por agente montado nesse campo dá 100% para uma pessoa e zero para o time — e o número não parece errado, parece um vendedor muito dedicado.

**Filtro de quem conta:** descartar `sender.type === 'user'` achando que "user" é robô apaga justamente o que sai por API, que é quase tudo. Descarte `contact` (é o lead) e `agent_bot` (é a IA); **`user` conta**. E nota interna (`private: true`) **não** é contato: ninguém do lado de lá recebe — quem inclui nota na definição de "falamos com ele" marca como atendido quem só foi comentado.

## Pré-flight "áudio toca" (a definição de PRONTO — teste o caminho real)
1. [ ] Áudio **>1 min** inbound: `media_url` **NÃO fica NULL** em até ~15s (pode ser `.ogg` no 1º beat; `.mp3` depois via background). n8n `Ingerir Mídia` **sem** "compute resources".
1a. [ ] Áudio curto: bucket grava `.mp3` (audio/mpeg). Áudio longo: `.ogg` imediato + `.mp3` em background.
1b. [ ] **Duração do mp3 == duração do áudio enviado** (gotcha #8 — manda 7s, confere ~7s, não 6s). `afinfo` no objeto do bucket.
2. [ ] `media_url` no banco = path do bucket (não lookaside http, não null).
3. [ ] Signed URL serve `200 audio/mpeg` + `Accept-Ranges: bytes` (Range → 206; `<audio>` HTML5 exige).
4. [ ] **CSP tem `media-src`** liberando o domínio do storage (header + meta).
5. [ ] `verify_jwt` OFF pra edge de ingestão (probe = 401 de função, não gateway).
6. [ ] Toca de verdade no navegador, **Chrome E Safari**, após hard refresh. Console sem "violates CSP".
7. [ ] Áudios antigos quebrados: backfill (re-transcode local + UPDATE media_url) OU aceite irrecuperáveis (lookaside expirada).

Os itens 1–5 e 7 o agente fecha sozinho. O **6 não**: quem ouve é uma pessoa, nos dois
navegadores. Não peça isso em prosa no meio da resposta — escreva um roteiro e rode
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/hitl-loop.sh" <roteiro>` (receita na skill `verificacao`),
que devolve `TOCOU=s|n` e o erro do console em `KEY=VALUE`. Enter vazio reprova: sem a
resposta, o item 6 fica em aberto e "pronto" não sai.

## Providers (resumo)
- **NotificaMe** (oficial/Meta): templates client-facing, status callbacks, áudio de saída como `file` (linha abaixo). Inbound mídia via proxy /media (#5). Node oficial só tem OUTBOUND — download de mídia e reação NÃO existem no node, é HTTP cru.
- **UAZAPI** (não-oficial): alertas internos, mídia, mais permissivo. Ver `n8n-workflow-agent/references/uazapi.md` (`/kit-vamoo:n8n-workflow-agent`).
- Outbound áudio: `POST /v1/channels/whatsapp/messages`, `contents:[{type:'file',fileMimeType:'audio',fileUrl:<storage público>}]`, com header `X-Api-Token`. Fonte: o nó de envio de áudio NotificaMe de um agente em produção, lido pela API do n8n; todos os nós NotificaMe dele estão em `/v1`, e nenhum usa `voice:true`. O `/v2` com `voice:true` não tem fonte: não use sem testar com um número próprio e conferir no celular se chega como mensagem de voz.

## Reação / reply-citado / nota interna / resumo IA
- **Nota interna + resumo IA**: linha com `sender='system'` → renderiza em bloco AMARELO full-width (não balão), fora do esquema de mensagens trocadas com o cliente.
- **Reação / reply-citado:** NÃO são tratados nativamente por NotificaMe node nem pelos workflows de referência — design novo (coluna `reply_to`, tabela `reactions`). Slice de rollout, não vem de graça.

Veja `references/media-pipeline.md` pro código verificado (edge ingest+transcode, signing service, render dispatcher, CSP, bucket SQL, backfill, probes).
