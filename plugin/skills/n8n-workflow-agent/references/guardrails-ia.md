# Guard-rails da IA no workflow n8n

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

O que a IA pode afirmar, por que pedido de parar é estado permanente, quando
escalar e quem é dono do canal: skill `guardrails-ia`. Aqui fica só **onde cada
guard-rail entra** no fluxo típico do `SKILL.md` (Log Entrada → IF dono/pausa →
AI Agent → Validar JSON → IF transferir → Split Out → Enviar).

## Alegações: no prompt E num filtro depois do agente

- A lista do que o agente pode afirmar (e do que nunca afirma) mora num lugar só
  do projeto (tabela, JSON versionado ou variável do workflow) e entra no
  **system prompt do AI Agent** por expressão, não colada como texto solto que
  alguém edita no canvas.
- O controle de verdade é um **Code Node depois de "Validar JSON resposta"**,
  antes do Split Out: aplica a regra do dígito (todo número da resposta tem que
  vir da lista ou da fala do lead) e a lista bloqueada. Prompt sozinho vaza.
- Saída reprovada **não segue para o envio**: o Code Node devolve um item com
  `precisa_humano: true` e o texto que o modelo tentou mandar, e um IF desvia
  para a notificação de revisão. Nunca troque por resposta genérica em silêncio.
- Para testar o filtro em conversa longa: checagem `numeros_permitidos` da QA
  simulada ([qa-simulada.md](qa-simulada.md)).

## Opt-out: lookup antes de CADA nó de envio

- Grave `nao_contatar` no ramo que detecta o pedido de parar, com origem e
  timestamp, e **depois** de o Log Entrada ter gravado a mensagem.
- Coloque um Postgres de lookup em `nao_contatar` imediatamente antes de todo
  nó que envia: resposta do agente, follow-up, keep-alive, cron de disparo. A
  fila do cron foi montada antes do opt-out chegar.
- Esse lookup tem que devolver **sempre 1 linha** (CTE + subquery escalar, ver
  [postgres.md](postgres.md) § `executeQuery` retornando 0 rows): com 0 linhas
  o n8n não emite item, o IF seguinte não roda e o fluxo morre sem dizer se o
  contato estava ou não na lista.

## Escalar para humano: saída de Switch que muda o dono

- `precisa_humano` é uma saída própria no Switch depois do agente (ou no IF
  "transferir?"), não uma frase que o agente escreve e alguém procura no log.
- Essa saída faz três coisas: `UPDATE` do dono do canal para `humano` (com
  motivo e timestamp), notificação para quem atende e labels/atribuição no
  Chatwoot ([chatwoot.md](chatwoot.md)).
- O IF de dono/pausa no começo do fluxo fica **depois** do Log Entrada: com o
  humano no fio, o inbound continua gravado e só a resposta automática para.

## Pausa no Redis é cache, não fonte de verdade

- A chave `PAUSA_{AGENTE}_{phone}` com TTL serve para o anti-loop
  ([messaging-patterns.md](messaging-patterns.md) § Redis e § Anti-Loop
  Detector). Handoff para humano não usa TTL: quando a chave expira, o fio volta
  para a IA no meio da conversa humana.
- O dono do canal vive no Postgres. Se o Redis cair ou for limpo, o workflow
  tem que continuar respeitando o dono gravado lá.

## Custo e canal

- Teto de gasto de IA e custo por lead: skill `baseline`, pilares `04` e `06`.
- Quem responde o fio quando IA, humano e API disputam, no lado do inbox:
  `/kit-vamoo:whatsapp-inbox-stack` #13.
