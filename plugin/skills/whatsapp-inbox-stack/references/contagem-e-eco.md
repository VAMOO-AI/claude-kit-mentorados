# whatsapp-inbox-stack — não lidas e eco do celular (#24 e #25)

Lido no passo 3 do SKILL.md, antes de mexer em contador de não lidas ou em quem envia pela API e também recebe o eco `fromMe` do aparelho (UAZAPI).

### #24 — Não lidas que não acompanham o celular
**Bug real:** a equipe responde quase só pelo celular (num caso real, 144 de 146 respostas em uma semana). `unread_count` só subia (mensagem do cliente) e só zerava ao abrir a conversa no app. Resultado: 106 de 122 conversas com não lidas, 72 delas já lidas no aparelho.

**Regra: o celular só baixa a contagem, nunca sobe.** O app continua contando as mensagens do cliente, e o que o aparelho já leu sai da conta: `unread = LEAST(unread, wa_unreadCount)`, aplicado **só** com um retrato do aparelho pelo menos tão novo quanto a última mensagem do cliente que o app conhece. Evento atrasado ou retrato velho não apaga mensagem nova. Use o mesmo horário, com teto em `now`, usado em `last_inbound_at`.

Três fontes, em ordem:
1. **Eco `fromMe` que é a mais nova da conversa zera.** Mas o **WhatsApp Business manda a resposta automática como `fromMe`**: com `wa_unreadCount` no evento, o eco só baixa até essa contagem e só zera direto quando a contagem não vem. Resposta de outro número da equipe em grupo misto (sem `fromMe`) não mexe, porque o celular dono não leu.
2. **`wa_unreadCount` vem em toda mensagem** (`providerRaw.chat.wa_unreadCount`). Aplique o `LEAST` depois do incremento. A contagem que vem com a mensagem do cliente **já inclui a própria mensagem**. **Reação não conta** (vem 0).
3. **Leitura no celular sem responder não gera evento de mensagem.** Um relógio (~2 min), por número conectado **que tenha conversa com não lidas**, faz `POST /chat/find` (projeção compacta, `wa_lastMsgTimestamp >=` a não lida mais antiga, até 5 páginas de 200), aplica o mesmo `LEAST` com guarda e atualiza só a linha que muda. Número sem pendência não gera chamada. Lock entre réplicas e prazo curto.
   - Teto conhecido: ~1.000 conversas por número.
   - O evento `chats` da UAZAPI deixaria instantâneo, mas exige mexer no webhook de produção. O relógio resolve sem isso.

**Não faça** `/chat/read` ao ler no app: marcaria como lida no WhatsApp e mandaria o tique azul ao cliente.

**Prova:** teste com o retrato tendo o **mesmo** horário da última mensagem do cliente (no caso real, tudo em segundos).

### #25 — Eco do celular vs. envio pela API: corridas que duplicam ou reenviam
Quem envia pela API e também recebe o eco `fromMe` do aparelho tem corridas. Quatro bugs reais:
- **O provider estoura o timeout mas envia.** O eco `fromMe` chega e adota a mensagem em voo (por `provider_message_id`), mas o finalize com `unknown` a marcava `failed` e o `retryable` a reenviava ao cliente. Conserto: a adoção pelo eco promove a mensagem para `sent` com entrega confirmada, e o finalize não reescreve mensagem já confirmada.
- **Eco tardio, depois do finalize:** virava uma segunda mensagem, e o job reagendado reenviava. A adoção aceita `unknown`/`retryable` sem provider id numa janela curta (5 min), fecha o job como sucesso e nunca rebaixa `delivered`/`read`.
- **Eco sem corpo:** a foto mandada pelo celular adotava o texto em voo. Sem corpo, o alvo só pode ser mídia sem legenda, e único. Mensagem apagada nunca é adotada.
- **Auditoria "o que saiu pela API":** o eco do celular tem `accepted_at` nulo e não tem `sender_profile_id` (ninguém do app enviou). Separe por aí antes de concluir que "a IA mandou mensagem".
