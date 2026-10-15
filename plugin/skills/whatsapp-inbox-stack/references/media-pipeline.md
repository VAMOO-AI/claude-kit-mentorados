# Media Pipeline — código verificado em produção

Tudo aqui rodou e2e em prod. Adapte nomes (bucket, tabelas) ao projeto.

## 1. CSP — adicionar `media-src` (gotcha #1)

Em TODO lugar que define CSP. Header em `vercel.json`:
```json
"value": "default-src 'self'; ...; img-src 'self' data: https: blob:; media-src 'self' data: https: blob:; connect-src 'self' https://*.supabase.co ...;"
```
E meta em `index.html` (ambos enforçados — interseção):
```html
<meta http-equiv="Content-Security-Policy" content="...; img-src 'self' data: https: blob:; media-src 'self' data: https: blob:; connect-src 'self' https://*.supabase.co ...;" />
```
Sem `media-src`, `<audio>`/`<video>` caem no `default-src 'self'` e são bloqueados — mesmo com signed URL válida e fetch 200.

## 2. Edge function — ingest + transcode (gotchas #2, #5, #9)

**Regra de ouro:** NUNCA transcodificar no caminho crítico da request.
Sync = download + upload original → responde `path`. Transcode + Whisper = `EdgeRuntime.waitUntil`
(re-baixa do Storage no background pra liberar RAM do request).

```ts
declare const EdgeRuntime: { waitUntil: (p: Promise<unknown>) => void };

// IMPORTA via npm:, NÃO esm.sh (esm.sh arrasta @eshaz/web-worker -> node:vm,
// que o edge-runtime do Supabase NÃO tem; deploy passa, runtime quebra).
import { OggOpusDecoder } from 'npm:ogg-opus-decoder@1.6.16';
import { Mp3Encoder } from 'npm:@breezystack/lamejs@1.2.7';

const MEDIA_ENDPOINT = 'https://api.notificame.com.br/v1/channels/whatsapp/media';
const MEDIA_DOWNLOAD_TIMEOUT_MS = 120_000;

async function transcodeOpusToMp3(opus: Uint8Array): Promise<Uint8Array> {
  const decoder = new OggOpusDecoder();
  await decoder.ready;
  let channelData: Float32Array[]; let sampleRate: number;
  // decodeFile, NÃO decode() — decode() bufferiza os últimos frames e exige flush();
  // sem isso o áudio sai CORTADO no final (~0.5-1s, pior em curtos: 3s->2s). gotcha #8.
  try { const d = await decoder.decodeFile(opus); channelData = d.channelData; sampleRate = d.sampleRate; }
  finally { decoder.free(); }
  if (!channelData.length || !channelData[0].length) throw new Error('opus vazio após decode');
  const toI16 = (f: Float32Array) => {
    const o = new Int16Array(f.length);
    for (let i = 0; i < f.length; i++) { const s = Math.max(-1, Math.min(1, f[i])); o[i] = s < 0 ? s * 0x8000 : s * 0x7fff; }
    return o;
  };
  const ch = channelData.length >= 2 ? 2 : 1;
  const enc = new Mp3Encoder(ch, sampleRate, 64);
  const L = toI16(channelData[0]); const R = ch === 2 ? toI16(channelData[1]) : null;
  const blocks: Uint8Array[] = [];
  for (let i = 0; i < L.length; i += 1152) {
    const b = R ? enc.encodeBuffer(L.subarray(i, i+1152), R.subarray(i, i+1152)) : enc.encodeBuffer(L.subarray(i, i+1152));
    if (b.length) blocks.push(b);
  }
  const tail = enc.flush(); if (tail.length) blocks.push(tail);
  const total = blocks.reduce((a, b) => a + b.length, 0);
  const mp3 = new Uint8Array(total); let off = 0;
  for (const b of blocks) { mp3.set(b, off); off += b.length; }
  return mp3;
}

// no serve(): auth por secret (verify_jwt OFF, gotcha #3) ->
// SYNC: baixa via proxy -> upload ORIGINAL -> responde path
// BACKGROUND: transcode -> mp3 -> PATCH media_url + whisper (gotcha #9)
const mediaResp = await fetch(MEDIA_ENDPOINT, {
  method: 'POST',
  headers: { 'X-Api-Token': apiToken, 'Content-Type': 'application/json' },
  signal: AbortSignal.timeout(MEDIA_DOWNLOAD_TIMEOUT_MS),
  body: JSON.stringify({ from, to: 'whatsapp', contents: [{ type: 'file', fileUrl, fileMimeType: shortType(mime) }] }),
});
const originalBytes = new Uint8Array(await mediaResp.arrayBuffer());
const originalMime = baseMime(mime), originalExt = EXT_BY_MIME[originalMime] || 'bin';
const path = `${baseName}.${originalExt}`;
await supabase.storage.from(INBOX_MEDIA_BUCKET).upload(path, new Blob([originalBytes], { type: originalMime }), { contentType: originalMime, upsert: true });

if (isOpusAudio(mime)) {
  EdgeRuntime.waitUntil(runDeferredAudioJob({ supabase, inboundId, providerMessageId: messageId, originalPath: path, ... }));
}
return json({ ok: true, path, mime: originalMime, deferred: isOpusAudio(mime), transcription: null });

// runDeferredAudioJob: download(originalPath) do Storage -> transcodeOpusToMp3 -> upload .mp3 ->
// PATCH <agente>_messages.media_url -> whisper -> PATCH extracted_data.transcription
// Payload n8n deve incluir inbound_id (uuid da msg do Brain Query).
```

## 2b. n8n — node `Ingerir Mídia`
```json
{
  "url": "https://<project>.supabase.co/functions/v1/inbox-media-ingest",
  "jsonBody": "={{ JSON.stringify({ fileUrl, phone, message_id, inbound_id: $('Brain Query').first().json.inbound_id, mime, from: channel_id, secret }) }}",
  "options": { "timeout": 300000, "response": { "response": { "neverError": true, "responseFormat": "json" } } },
  "onError": "continueRegularOutput"
}
```
Diagnóstico: `Ingerir Mídia` com `"not having enough compute resources"` = transcode no caminho síncrono (gotcha #9). `Atualiza media_url` com path vazio = ingest falhou mas fluxo seguiu.

## 2c. UI — "IA leu" ≠ transcrição de áudio
- O selo de extração na thread (`<intent de extração>`): `formatarResumoExtracao(dados)` → ex. "Produto X · nome".
- Transcrição Whisper: `extracted_data.transcription` ou `content` (o componente do balão de áudio).
- `media_url` NULL + selo visível = extração OK, ingest de mídia falhou (gotcha #9).

## 3. Reproduzir o edge-runtime REAL local, sem deploy (gotcha #2)
Troque `vX.Y.Z` pela versão da imagem que o seu CLI usa: `strings $(which supabase) | grep edge-runtime:v`.
```bash
mkdir fn && cp index.ts fn/        # entrypoint isolado
docker run --rm -v "$PWD/fn":/app public.ecr.aws/supabase/edge-runtime:vX.Y.Z \
  bundle --entrypoint /app/index.ts --output /app/bin.eszip   # falha aqui (ex: node:vm) = falha em prod
docker run -d --name et -p 9011:9000 -v "$PWD/fn":/app public.ecr.aws/supabase/edge-runtime:vX.Y.Z \
  start --main-service /app/bin.eszip --main-entrypoint file:///app/index.ts -p 9000
curl localhost:9011 ; docker logs et ; docker rm -f et
```

## 4. Service de leitura — assinar paths on-read (gotcha #6)
```ts
const INBOX_MEDIA_BUCKET = 'inbox-media';
async function signInboxMediaUrls(messages: Msg[]): Promise<void> {
  const paths = messages.map(m => m.media_url).filter((u): u is string => !!u && !/^https?:\/\//i.test(u));
  if (!paths.length) return;
  const { data } = await supabase.storage.from(INBOX_MEDIA_BUCKET).createSignedUrls(paths, 3600);
  const byPath = new Map((data ?? []).filter(i => i.path && i.signedUrl).map(i => [i.path!, i.signedUrl!]));
  for (const m of messages) if (m.media_url && byPath.has(m.media_url)) m.media_url = byPath.get(m.media_url)!;
}
// listMessages: const msgs = ...; await signInboxMediaUrls(msgs); return msgs;
// IMPORTANTE: chamar em TODO reload, inclusive o disparado por realtime (senão msg
// nova entra com path cru e o <audio src> quebra).
```

## 5. Render dispatcher (despacha o balão por content_type)
```tsx
function MessageBody({ m }: { m: Msg }) {
  const url = m.media_url, ct = m.content_type;
  if (url && ct === 'audio') return <audio controls src={url} className="max-w-[240px]" />;
  if (url && ct === 'image') return <img src={url} alt={m.content ?? ''} className="max-h-60 rounded" />;
  if (url && ct === 'document') return <a href={url} target="_blank" rel="noreferrer">📎 {m.content || 'Documento'}</a>;
  if (ct !== 'text' && ct !== 'template' && !url) return <em>{ {audio:'🎤 Áudio',image:'📷 Imagem',document:'📎 Documento'}[ct] ?? 'Mídia'}</em>;
  return <span className="whitespace-pre-wrap break-words">{m.content}</span>;
}
```

## 6. Bucket privado + RLS (gotcha #6)
```sql
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('inbox-media','inbox-media', false, 26214400,
  array['audio/ogg','audio/mpeg','audio/mp4','image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set allowed_mime_types = excluded.allowed_mime_types;

create policy inbox_media_auth_read on storage.objects
  for select to authenticated using (bucket_id = 'inbox-media');
```
Realtime self-heal: garanta a tabela de mensagens na publication com UPDATE:
```sql
-- confere: select pubinsert,pubupdate from pg_publication where pubname='supabase_realtime';
alter publication supabase_realtime add table <agente>_messages;  -- se faltar
```

## 7. verify_jwt durável no CI (gotcha #3)
No workflow de deploy, allowlist das funções públicas:
```bash
PUBLIC_FUNCTIONS="inbox-media-ingest"   # + outros webhooks externos
deploy_one() { fn="$1"; extra=""; case " $PUBLIC_FUNCTIONS " in *" $fn "*) extra="--no-verify-jwt";; esac;
  supabase functions deploy "$fn" --project-ref "$REF" $extra; }
```
Mudar só o `.yml` não casa filtro `supabase/functions/**` → redeploya via `gh workflow run deploy.yml -f function=<fn>`.

## 8. Backfill de áudios antigos .ogg → .mp3 (Deno local + service_role)
Deno LOCAL transcodifica com npm: ou esm.sh (ambos OK fora da edge). Para cada áudio com `media_url like '%.ogg'`: download via `/storage/v1/object/<bucket>/<path>` (Bearer service_role) → transcode → upload `.mp3` (`x-upsert:true`, content-type audio/mpeg) → PATCH `<agente>_messages?id=eq.<id>` `{media_url:'<path>.mp3'}` via PostgREST. Mantém o .ogg (reversível). Lookaside já expirada = irrecuperável (media_url ficou NULL).

## 9. Probes de diagnóstico
```bash
# verify_jwt: gateway-401 (ON) vs função-401 (OFF)
curl -s -X POST "$URL/functions/v1/<fn>" -d '{}'   # UNAUTHORIZED_NO_AUTH_HEADER = ON

# signed URL serve áudio + range?
curl -sD- -o/dev/null "$SIGNED" | grep -iE 'HTTP|content-type|accept-ranges'
curl -sD- -o/dev/null -H 'Range: bytes=0-1023' "$SIGNED" | grep -iE 'HTTP|content-range'  # quer 206

# no navegador (a prova final do CSP):
# const a=document.querySelector('audio'); console.log(a?.src);
# fetch(a.src).then(r=>console.log(r.status,r.headers.get('content-type')))
```

## Validação de duração sem o original (gotcha #8)
Parseie o `granulepos` da ÚLTIMA página ogg (8 bytes LE em offset+6 do último `OggS`) menos o preskip (OpusHead+10) = total real de samples @48kHz. Compare com `samplesDecoded`. Ex real: granulepos e `decodeFile()` deram ~4,7 s (completo), `decode()` deu ~4,2 s (corta o fim).
