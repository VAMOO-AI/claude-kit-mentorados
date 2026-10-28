# whatsapp-inbox-stack — gotchas de mídia (#1 a #9)

Lido no passo 2 do SKILL.md (arquitetura B: mídia inbound, CSP, edge, bucket). Cada um saiu de um bug real.

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
