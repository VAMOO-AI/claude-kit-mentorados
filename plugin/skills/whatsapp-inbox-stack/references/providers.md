# whatsapp-inbox-stack — providers, reação, reply-citado e nota interna

Lido no passo 6 do SKILL.md, antes de escolher provider, mandar áudio de saída (inclusive o gravado no Chatwoot, #20) ou renderizar nota/reação.

## Providers (resumo)
- **NotificaMe** (oficial/Meta): templates client-facing, status callbacks, áudio de saída como `file` (linha abaixo). Inbound mídia via proxy /media (#5). Node oficial só tem OUTBOUND — download de mídia e reação NÃO existem no node, é HTTP cru.
- **UAZAPI** (não-oficial): alertas internos, mídia, mais permissivo. Ver `n8n-workflow-agent/references/uazapi.md` (`/kit-vamoo:n8n-workflow-agent`). Mídia inbound: `.enc` resolvido por `/message/download` (#5). Sessão, ACK e grupo: #11, #21 a #23. Não lidas e eco: #24 e #25. `@lid` e retentativa do webhook: #26 e #27. Histórico: #28.
  - **Editar mensagem enviada:** `POST /message/edit`, só texto, até 15 min depois do envio. Fora do prazo a opção some. O banco só muda se o provider aceitar. A bolha mostra "editada".
  - **Participantes de grupo:** `/group/updateParticipants`, resultado por pessoa (privacidade devolve 403 explicável). Exige que o número da conversa seja admin do grupo.
  - **Provisionar número pelo app:** `/instance/create` com token de administrador. Cadastre o número no app **antes** do webhook (inbound de instância desconhecida é descartado), depois os webhooks com `action:"add"`, um de cada vez (#11c). Remover apaga a instância só com o token **próprio** dela, nunca o de admin. Número cadastrado de fora sai só do app.
- Outbound áudio: `POST /v1/channels/whatsapp/messages`, `contents:[{type:'file',fileMimeType:'audio',fileUrl:<storage público>}]`, com header `X-Api-Token`. Fonte: o nó de envio de áudio NotificaMe de um agente em produção, lido pela API do n8n; todos os nós NotificaMe dele estão em `/v1`, e nenhum usa `voice:true`. O `/v2` com `voice:true` não tem fonte: não use sem testar com um número próprio e conferir no celular se chega como mensagem de voz.

### #20 — Chatwoot até a v4.14 manda áudio ogg/opus como `audio/opus`, e a Meta recusa
**Bug real:** áudio gravado no Chatwoot e enviado pela Cloud API da Meta voltava com `131053: Media upload error`. O Chatwoot serve o anexo ogg/opus como `audio/opus`, tipo que a Meta não aceita.
- Declarar `audio/ogg` no upload não adianta: o ActiveStorage detecta o tipo pelo conteúdo do arquivo.
- A correção do Chatwoot (`normalize_opus_content_type`) saiu na v4.15.0. Com Chatwoot anterior, grave e mande áudio de saída em **mp3**.
- O mesmo `131053` também aparece pelo limite de download da Meta por ASN. Separe as causas por tipo de anexo antes de concluir: se só o áudio falha e foto e documento passam, é o tipo.
- **Prova:** mp3 de saída sem falha, e o áudio tocou no celular.

## Reação / reply-citado / nota interna / resumo IA
- **Nota interna + resumo IA**: linha com `sender='system'` → renderiza em bloco AMARELO full-width (não balão), fora do esquema de mensagens trocadas com o cliente.
- **Reação / reply-citado:** NÃO são tratados nativamente por NotificaMe node nem pelos workflows de referência — design novo (coluna `reply_to`, tabela `reactions`). Slice de rollout, não vem de graça.
