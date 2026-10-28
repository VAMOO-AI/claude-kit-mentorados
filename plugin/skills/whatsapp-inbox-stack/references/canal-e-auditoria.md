# whatsapp-inbox-stack — dono do canal e prova de contato (#13 e #14)

Lido no passo 4 do SKILL.md, antes de mexer em pausa/handoff IA-humano ou em relatório de quem falou com o lead.

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
