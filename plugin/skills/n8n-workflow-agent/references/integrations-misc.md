# ElevenLabs TTS, Whisper (transcrição), Webhook Auth, API Route, Supabase Storage

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

## ElevenLabs (TTS)

```
POST https://api.elevenlabs.io/v1/text-to-speech/{voiceId}
Header: xi-api-key: <key>
Body: { text, model_id, voice_settings }
```

### Preparar texto para TTS

- Remover URLs, emojis, asteriscos (markdown bold), `[TRANSFERIR_PARA_HUMANO]`
- Remover tags HTML/SSML, risadas (haha, kkk, rsrs)
- Humanizar: "voce" → "ce", "para" → "pra", "estou" → "to"

### Lógica de quando responder em áudio

1. Cliente mandou áudio → responde com áudio
2. Cliente pediu áudio via regex → responde com áudio
3. A cada 3 interações de texto → counter via `$getWorkflowStaticData('global')`

### Cadeia TTS

```
Responder em Áudio? → Preparar TTS (limpa texto) → ElevenLabs TTS
  → Verificar TTS (checa mimeType=audio/mpeg, senão PARA)
    → Extrair Base64 → Enviar Áudio WhatsApp (NotificaMe)
```

**Armadilha:** Se ElevenLabs retorna JSON (erro billing) em vez de audio/mpeg, o nó "Verificar TTS" deve parar a cadeia (senão envia "áudio" inválido).

### Voice IDs

Cada projeto tem sua própria voz cadastrada no ElevenLabs. Estrutura:

| Campo | Onde encontrar |
|---|---|
| Voice ID | ElevenLabs dashboard → Voice Library → copy ID |
| Model | `eleven_multilingual_v2` (estável, multi-idioma) ou `eleven_v3` (mais expressivo) |

Salve o Voice ID em env var do n8n (ex: `ELEVENLABS_VOICE_ID`) — não hard-code no workflow.

---

## OpenAI Whisper (transcrição de áudio)

### Arquivo sem extensão → 400 "Unrecognized file format"

O link que o `/message/download` da UAZAPI devolve (`https://<inst>.uazapi.com/files/<hash>`) não tem extensão. A OpenAI `/v1/audio/transcriptions` decide o formato pelo **nome do arquivo** no multipart, não pelo conteúdo: baixado com esse nome, o POST volta **400 "Unrecognized file format"**. Com `onError: continueRegularOutput` no HTTP node a falha é silenciosa, e o único sintoma é o agente responder com o texto de fallback ("[áudio que não consegui transcrever]") para todo áudio.

Fix: um Code node entre o download (`responseFormat: 'file'`, `outputPropertyName: 'data'`) e o HTTP da transcrição, dando nome e tipo ao binário. No caso medido o conteúdo era mp3; use a extensão do formato real.

```js
var items = $input.all();
for (var i = 0; i < items.length; i++) {
  if (items[i].binary && items[i].binary.data) {
    Object.assign(items[i].binary.data, { fileName: 'audio.mp3', fileExtension: 'mp3', mimeType: 'audio/mpeg' });
  }
}
return items;
```

O HTTP da transcrição segue o multipart do `code-node.md` § Multipart Form Upload: `formBinaryData` com `name: 'file'` e `inputDataFieldName: 'data'`, mais `formData` `model`.

---

---

## Webhook Auth Patterns

### Timing-Safe Comparison (OBRIGATÓRIO)

```typescript
import { timingSafeEqual } from "crypto";
// Compara tamanho primeiro, depois bytes — previne timing attacks
```

### Patterns por webhook

| Webhook | Auth | Segredo |
|---------|------|---------|
| WhatsApp/NotificaMe | Header `x-webhook-secret` ou `Authorization: Bearer` | o do webhook do provider |
| Chatwoot | Query param `?token=` (fallback header) | o do webhook do Chatwoot |
| Cron (Vercel/N8N) | `Authorization: Bearer` | o do cron |

Um segredo por integração, nunca reaproveitado entre elas: se um vaza, você rotaciona só aquele.

### Token no corpo do webhook, validado no n8n sem guardar o segredo

A UAZAPI manda o `token` da instância no corpo do webhook. Para validar sem colar o segredo no workflow, guarde só o SHA-256 dele e compare num IF: a string extension `.hash('sha256')` funciona em expressão de IF, como em `{{ $json.body.token.hash('sha256') }}` igual ao hash guardado (env var ou constante no workflow). Quem lê o JSON do workflow vê o hash, não o token. Não é comparação timing-safe como a de cima; o que ela protege é o segredo em repouso.

---

---

## API Route Pattern (Next.js)

### Estrutura padrão

```typescript
// Helpers de JSON, CORS e erro do seu projeto (nomes ilustrativos)
import { respostaJson, handlerOptions, tratarErroApi } from "@/lib/api";

const METHODS = ["POST", "OPTIONS"];
const json = respostaJson(METHODS);
export const OPTIONS = handlerOptions(METHODS);

export async function POST(req: NextRequest) {
  try {
    // 1. Auth
    // 2. Parse body (Zod)
    // 3. Business logic
    // 4. Return json(req, data, 200)
  } catch (error) {
    return tratarErroApi(req, error, "service-name", json);
  }
}
```

### CORS

```typescript
// respostaJson monta os headers de CORS
Access-Control-Allow-Methods: POST, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
Vary: Origin
```

### Error Mapping (tratarErroApi)

```
"Unauthorized access" / "Missing authorization" → 401
"Forbidden" → 403
"not configured" / "not active" → 404
Default → 500
```

---

---

## Supabase Storage (Public CDN para Mídia)

Pattern para hospedar arquivos públicos refetcháveis (template images, áudios do agente IA, etc.) sem depender de CDN externo.

### Setup do bucket público

```sql
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('<bucket-de-imagens>', '<bucket-de-imagens>', true, 5242880,
  ARRAY['image/png','image/jpeg','image/webp']::text[])
ON CONFLICT (id) DO NOTHING;
```

**Public bucket** = SELECT público sem policy explícita. Service role bypassa RLS para INSERT/UPDATE/DELETE.

### Criar bucket via API (sem SQL)

```bash
curl -X POST "https://{ref}.supabase.co/storage/v1/bucket" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"id":"my-bucket","name":"my-bucket","public":true,"file_size_limit":5242880,"allowed_mime_types":["image/png"]}'
```

### Upload + getPublicUrl

```ts
// Backend (Node, supabase-js)
await supabase.storage
  .from('my-bucket')
  .upload(fileName, buffer, { contentType: 'image/png', upsert: true });

const { data } = supabase.storage
  .from('my-bucket')
  .getPublicUrl(fileName);
// → https://{ref}.supabase.co/storage/v1/object/public/my-bucket/{fileName}
```

```bash
# Direct API (binary upload)
curl -X POST "https://{ref}.supabase.co/storage/v1/object/my-bucket/file.png" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: image/png" \
  -H "x-upsert: true" \
  --data-binary @/path/to/file.png
```

### Vercel env extraction (gotcha)

`vercel env pull /tmp/file` salva valores entre aspas. Valores JWT podem vir com `\n` literal no final (escape do CLI). Sempre limpar:

```js
const m = dotenv.match(/^SUPABASE_SERVICE_ROLE_KEY="([^"]+)"/m);
let key = m[1];
if (key.endsWith('\\n')) key = key.slice(0, -2);  // strip literal \n
```

### Smoke test pattern

```bash
# 1. List buckets
curl ".../storage/v1/bucket" -H "apikey: $K" -H "Authorization: Bearer $K"

# 2. Create
curl -X POST ".../storage/v1/bucket" -H "apikey: $K" -d '{"id":"test","name":"test","public":true}'

# 3. Upload
curl -X POST ".../storage/v1/object/test/file.png" -H "Authorization: Bearer $K" -H "Content-Type: image/png" --data-binary @file.png

# 4. Public fetch (no auth)
curl ".../storage/v1/object/public/test/file.png"

# 5. Cleanup
curl -X DELETE ".../storage/v1/object/test/file.png" -H "Authorization: Bearer $K"
```

### Quando usar

| Caso | Storage | Por quê |
|---|---|---|
| Template header image (Meta CDN URL) | Supabase Storage | header_handle não refetchável |
| Áudio TTS pra reenviar via API | Supabase Storage | URL pública durável |
| Anexos Chatwoot → reuso | Supabase Storage | Active Storage URLs expiram |
| Avatar de contato | Supabase Storage | Upload via UI |
| Imagens de UI (estáticas) | `/public` Next.js | Sem upload runtime |

---
