# whatsapp-inbox-stack — dono do canal e prova de contato (#13 e #14)

Lido no passo 4 do SKILL.md, antes de mexer em pausa/handoff IA-humano ou em relatório de quem falou com o lead.

### #13 — Propriedade de canal: quem responde não é quem grava
**A regra, em uma linha: propriedade de canal decide quem RESPONDE, nunca quem GRAVA.**

O modelo (estágio do funil e dono do canal em dois campos, a lista de donos, a ordem gravar inbound → resolver dono → decidir envio, o handoff por `UPDATE` sem TTL e a prova de 2 minutos) mora num lugar só: leia a seção "Propriedade de canal" de `guardrails-ia/SKILL.md` antes de mexer. A skill é só-slash, o modelo não a aciona: abra o arquivo (a pessoa chama por `/kit-vamoo:guardrails-ia`).

O que é só do inbox:

- Os três emissores aqui são a IA, o humano no Chatwoot e a API/rotina de aviso. Com a pausa modelada como interruptor no começo do fluxo, o guard corta antes do nó que grava o inbound (corolário do #10): o que o lead escreveu depois da transferência fica só no Chatwoot, e é o trecho que alguém vai querer auditar.
- Na prova de 2 minutos, confira a sua tabela de mensagens, não a tela do Chatwoot: o Chatwoot mostra as 3 mensagens mesmo com o log vazio.

### #14 — O webhook de CONTA é a prova de contato; o `agent_name` não diz quem falou
Vale para arquitetura A com um inbox por vendedor (o padrão quando cada um tem seu WhatsApp corporativo). Dois fatos que sempre vêm juntos:

**a) Um webhook de conta já cobre o time inteiro.** `POST /accounts/{id}/webhooks` com `message_created` recebe as mensagens de **todos** os inboxes, não só do inbox da IA. Se você grava essas linhas numa tabela de auditoria, ganha de graça a resposta para "alguém do nosso lado falou com este telefone, e quando" — sem varrer a API conversa por conversa (que serializa e custa segundos por renderização). Num caso real essa tabela tinha milhares de mensagens e centenas de telefones que a timeline do CRM não via, porque ela só consultava os logs do agente de IA: lead atendido pelo vendedor aparecia como **"ninguém falou com o lead"**, e isso fazia a IA parecer negligente na cobrança. A prova estava no banco havia meses, num lugar que ninguém consultava para essa pergunta.

**b) `sender.name` / `agent_name` é a conta do token, não a pessoa.** Quando o espelho outbound do n8n posta a mensagem do vendedor no Chatwoot, ela entra com `sender.type: "user"` e o nome do dono do **token de API** — todas as mensagens do time estavam atribuídas ao mesmo agente. Quem falou de verdade só se descobre pelo **`inbox_id` da conversa** (`GET /accounts/{acc}/conversations/{id}`). Relatório de produtividade por agente montado nesse campo dá 100% para uma pessoa e zero para o time — e o número não parece errado, parece um vendedor muito dedicado.

**Filtro de quem conta:** descartar `sender.type === 'user'` achando que "user" é robô apaga justamente o que sai por API, que é quase tudo. Descarte `contact` (é o lead) e `agent_bot` (é a IA); **`user` conta**. E nota interna (`private: true`) **não** é contato: ninguém do lado de lá recebe — quem inclui nota na definição de "falamos com ele" marca como atendido quem só foi comentado.
