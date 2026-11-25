# whatsapp-inbox-stack — inbound da UAZAPI: `@lid` e webhook sem reenvio (#26 e #27)

Lido no passo 3 do SKILL.md, antes de mexer no adaptador do webhook, em telefone de remetente ou na retentativa do encaminhamento (UAZAPI).

**O adaptador traduz o payload.** A UAZAPI manda `owner`/`token` (nunca `instanceId`) e `message.chatid`/`messageid`/`text` (não `chatId`/`messageId`/`body` no topo). Quem consome o evento não deve ler o payload cru: a tradução mora num lugar só, o adaptador (n8n fino ou código).

### #26 — `@lid` não é telefone
**Bug real duplo:**
- Tirar os dígitos de um JID `@lid` e tratar como telefone **casava com número da equipe por coincidência** e nunca com o número real. O LID é um id opaco: a chave de telefone de um `@lid` é **vazia**, e o caso vai para o log.
- Em grupo, o participante em `@lid` vem com `sender_pn` (o telefone real). O adaptador repassa `senderPn` e `senderLid` separados, e a API usa o `senderPn` quando vem.
  - Conversa privada com `chatid` em `@lid` continua sem mapeamento (risco conhecido).
- Avatar e nome por LID: `n8n-workflow-agent/references/uazapi.md` (`/kit-vamoo:n8n-workflow-agent`).

### #27 — A UAZAPI não reenvia webhook: responda 200 antes e retente você
**Bug real:** o encaminhamento n8n → API desistia depois de 3 tentativas em ~15 s. API fora por esse tempo = mensagem perdida, e **a UAZAPI não reenvia**.

Conserto:
- O fluxo responde 200 à UAZAPI logo depois do adaptador e retenta a API em esperas crescentes (2 min, 10 min, 30 min, 2 h, 6 h, ≈ 8h40). Acima de ~65 s o n8n grava a execução e a retoma depois de reiniciar.
- Esgotado, falha para o `errorWorkflow` alertar.
- Toda rodada manda o **mesmo `externalEventId`**, que a API deduplica.
- O alerta de "API fora" não pode depender da própria API: monitor externo no `/heartbeat`.
- Descarte ACK pelo tipo do **evento**, nunca por "tipo contém `message`" (#11c).
