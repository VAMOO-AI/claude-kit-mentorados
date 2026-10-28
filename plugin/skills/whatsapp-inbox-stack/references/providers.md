# whatsapp-inbox-stack — providers, reação, reply-citado e nota interna

Lido no passo 6 do SKILL.md, antes de escolher provider, mandar áudio de saída ou renderizar nota/reação.

## Providers (resumo)
- **NotificaMe** (oficial/Meta): templates client-facing, status callbacks, áudio de saída como `file` (linha abaixo). Inbound mídia via proxy /media (#5). Node oficial só tem OUTBOUND — download de mídia e reação NÃO existem no node, é HTTP cru.
- **UAZAPI** (não-oficial): alertas internos, mídia, mais permissivo. Ver `n8n-workflow-agent/references/uazapi.md` (`/kit-vamoo:n8n-workflow-agent`).
- Outbound áudio: `POST /v1/channels/whatsapp/messages`, `contents:[{type:'file',fileMimeType:'audio',fileUrl:<storage público>}]`, com header `X-Api-Token`. Fonte: o nó de envio de áudio NotificaMe de um agente em produção, lido pela API do n8n; todos os nós NotificaMe dele estão em `/v1`, e nenhum usa `voice:true`. O `/v2` com `voice:true` não tem fonte: não use sem testar com um número próprio e conferir no celular se chega como mensagem de voz.

## Reação / reply-citado / nota interna / resumo IA
- **Nota interna + resumo IA**: linha com `sender='system'` → renderiza em bloco AMARELO full-width (não balão), fora do esquema de mensagens trocadas com o cliente.
- **Reação / reply-citado:** NÃO são tratados nativamente por NotificaMe node nem pelos workflows de referência — design novo (coluna `reply_to`, tabela `reactions`). Slice de rollout, não vem de graça.
