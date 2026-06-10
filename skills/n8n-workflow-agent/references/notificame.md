# NotificaMe (WhatsApp client-facing)

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

## NotificaMe (WhatsApp — Client-Facing)

```
Base: https://api.notificame.com.br/v1/channels/whatsapp
Header: X-Api-Token: <api-token>

POST /messages — enviar mensagem/template
```

### Payload de envio

```js
{
  from: channelId,     // ID do canal NotificaMe
  to: telefone,        // formato: 5547999001122
  contents: [{ type: "text", text: "mensagem" }]
}
```

### Integração com N8N

O N8N recebe leads via webhook, envia templates via NotificaMe, e NotificaMe faz callback com status:
- **SENT** → mensagem aceita pelo WhatsApp
- **DELIVERED** → entregue no dispositivo
- **READ** → lida pelo cliente
- **FAILED/REJECTED/ERROR** → falhou

### Provider Message ID

NotificaMe retorna um `message_id` no envio. Callbacks de status usam esse ID. Porém, o dispatch_tracking pode ter sido criado com um `message_id` diferente (do N8N). Sempre suporte lookup duplo:

```
1. Busca por message_id
2. Fallback: busca por provider_message_id
```

### Template com header IMAGE — `header_handle` Caveat (CRÍTICO)

Quando você lê templates via `GET /v1/templates/{channel_token}`, templates com header IMAGE retornam:

```json
{
  "name": "esteiras_e_transportadores",
  "components": [
    {
      "type": "HEADER",
      "format": "IMAGE",
      "example": {
        "header_handle": ["https://scontent.whatsapp.net/v/t61.../...png?...&oh=...&oe=..."]
      }
    },
    { "type": "BODY", "text": "..." }
  ]
}
```

**ARMADILHA:** O `header_handle` é uma URL **assinada interna do CDN do Meta**, usada APENAS como exemplo durante review do template. Quando você passa essa URL como `link` no payload de envio:

```json
{
  "type": "image",
  "image": { "link": "https://scontent.whatsapp.net/..." }  // ❌ NÃO refetchável
}
```

NotificaMe **aceita inicialmente** (callback SENT, retorna message_id), mas ~7 segundos depois o callback FAILED chega com `error_message: "Media upload error"`. Meta tenta baixar a imagem do `header_handle` e falha porque a URL é assinada para um contexto específico, não publicamente refetchável.

**SOLUÇÃO: Cachear em storage público próprio**

Arquitetura: download do `header_handle` 1x → re-host em bucket público (ex: Supabase Storage) → cache key com hash do source URL para auto-invalidação:

```typescript
// Helper que resolve URL pública refetchável
async function getCachedTemplateImageUrl(
  supabase: SupabaseClient,
  config: NotificameConfig,
  templateName: string,
): Promise<string | null> {
  // 1. Resolve header_handle via NotificaMe API
  const sourceUrl = await getTemplateHeaderImageUrl(config, templateName);
  if (!sourceUrl) return null;

  // 2. Cache key embute hash do source → auto-invalida quando Meta atualiza
  const sourceHash = createHash("sha1").update(sourceUrl).digest("hex").slice(0, 8);
  const safeName = templateName.replace(/[^a-zA-Z0-9_-]/g, "_");
  const fileNamePrefix = `${safeName}-${sourceHash}`;

  // 3. Cache hit?
  const { data: existing } = await supabase.storage
    .from("whatsapp-template-images")
    .list("", { search: fileNamePrefix, limit: 1 });
  if (existing && existing.length > 0) {
    const cached = existing.find((f) => f.name.startsWith(fileNamePrefix));
    if (cached) {
      return supabase.storage.from(BUCKET).getPublicUrl(cached.name).data.publicUrl;
    }
  }

  // 4. Cache miss → download + upload
  const res = await fetch(sourceUrl);
  const buffer = Buffer.from(await res.arrayBuffer());
  const fileName = `${fileNamePrefix}.png`;
  await supabase.storage
    .from("whatsapp-template-images")
    .upload(fileName, buffer, { contentType: "image/png", upsert: true });

  return supabase.storage.from(BUCKET).getPublicUrl(fileName).data.publicUrl;
}
```

**Bucket setup (Supabase):**
```sql
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('whatsapp-template-images', 'whatsapp-template-images', true, 5242880,
  ARRAY['image/png','image/jpeg','image/webp']::text[])
ON CONFLICT (id) DO NOTHING;
```

**Latência:**
- Cache miss (1ª vez): ~500-1500ms (download + upload)
- Cache hit: ~50-100ms (list + getPublicUrl)
- Self-service: qualquer template novo aprovado funciona sem editar workflow/DB/UI

**Por que hash sufix:** Quando o `header_handle` muda (Meta rotaciona ou template é editado), o hash muda → novo arquivo é criado → URL antiga continua válida (lixo a ser limpado depois) e nova é gerada automaticamente. Sem cache invalidation manual.

---
