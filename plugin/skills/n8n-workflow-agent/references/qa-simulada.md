# QA simulada: um lead falso conversa com o agente até ele errar

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

O QA por injeção de webhook (`troubleshooting.md` § QA de Agente IA) prova o bug que você já
conhece, uma mensagem digitada por vez. Dois tipos de bug escapam dele: o que só aparece
depois de muitos turnos (re-saudação depois de passar do buffer, mais de 8 turnos) e o que
depende de um lead que você não pensou em escrever. `scripts/simular-conversa.mjs` automatiza
a injeção. Um lead simulado pelo Claude conversa com o agente real por N turnos. No fim, cada
conversa passa por checagens em código e por um juiz.

As ideias vêm do [langwatch/scenario](https://github.com/langwatch/scenario): lead simulado,
roteiro que mistura fala fixa com fala gerada, e checagem dura separada do juiz. O framework
não foi adotado porque o `call()` dele precisa receber a resposta do agente de forma
síncrona, e a de um agente n8n sai pelo provider (UAZAPI, NotificaMe). O adaptador para o n8n é justamente o que este script faz.

## Onde fica

No repositório do projeto do cliente, nunca no kit:

```
qa/
  agente.json            # como falar com este agente (sem segredo: segredo vai em {{env:VAR}})
  payload-uazapi.json    # payload real do provider com placeholders
  cenarios/*.json        # um arquivo por cenário
  resultados/            # relatórios JSON — no .gitignore
```

```bash
N8N_API_KEY=... ANTHROPIC_API_KEY=... node "${CLAUDE_PLUGIN_ROOT}/skills/n8n-workflow-agent/scripts/simular-conversa.mjs" qa/cenarios/*.json --rodadas 3 --paralelo 3
```

Saída `0`: tudo passou. `1`: algum cenário reprovou, com o motivo e o turno. `2`: erro de config
(validado inteiro antes da primeira injeção), de infra (webhook fora, execução que quebrou antes
do nó de resposta, nenhuma resposta em nenhum turno, juiz incoerente, recusa do modelo) ou
limpeza que falhou. `130`: Ctrl+C. A limpeza roda em todos esses casos, inclusive no Ctrl+C,
a menos que você passe `--manter` para inspecionar os leads no banco.

**Cenário é código.** `comando` e `limpeza` rodam no shell com as suas credenciais. Revise um
cenário que veio de outra pessoa como revisaria um script.

## `agente.json`

```json
{
  "n8n_url": "https://n8n.example.com",
  "webhook_url": "https://webhook.example.com/webhook/<agente>?token={{env:AGENTE_WEBHOOK_TOKEN}}",
  "workflow_id": "Ab12Cd34",
  "payload": "payload-uazapi.json",
  "no_resposta": "Validar JSON resposta",
  "campo_resposta": "mensagens",
  "telefone_prefixo": "5500",
  "timeout_turno_s": 90,
  "limpeza": [
    "psql \"$DATABASE_URL\" -c \"delete from <agente>_messages where phone = '{{telefone}}'\"",
    "psql \"$DATABASE_URL\" -c \"delete from <agente>_leads where phone = '{{telefone}}'\"",
    "redis-cli -u \"$REDIS_URL\" del 'DEBOUNCE_<AGENTE>_{{telefone}}' 'PAUSA_<AGENTE>_{{telefone}}'"
  ],
  "llm": { "modelo": "claude-opus-5" }
}
```

| Campo | O que é |
|---|---|
| `webhook_url` | O host **receiver** de webhook, não o do editor (webhook no host errado devolve 200 e não cria execução). |
| `no_resposta` / `campo_resposta` | O nó cuja saída tem o texto que iria para o lead e o caminho dentro do `json` (`a.b.c`). Aceita string, array de strings ou array de objetos com `text`/`content`/`mensagem`. Use o nó **antes** do envio: com DDD `00` o envio falha. |
| `telefone_prefixo` | Tem que começar com `5500`. O script recusa outro prefixo antes de injetar qualquer coisa: DDD `00` é o que garante que ninguém real recebe a resposta. Cada rodada sorteia um número novo, e é isso que isola rodadas paralelas. |
| `timeout_turno_s` | Quanto esperar a resposta (padrão 90). Depois disso o turno conta como silêncio, que é o resultado esperado depois de opt-out ou de transferência. Conta debounce + agente (~18s) com folga. Resposta que chega depois, já no turno seguinte, é casada pelo `message_id` e entra no turno dela: um "tudo bem, mas antes..." lento depois do opt-out ainda reprova. |
| `quieto_s` | Depois da primeira resposta do turno, quanto esperar outra execução do mesmo lead (padrão 5). |
| `pausa_entre_turnos_s` | Espera depois da resposta, para a memória persistir antes do próximo turno (padrão 2). Menos que isso reproduz a race do `memoryBufferWindow`. |
| `intervalo_rajada_ms` | Intervalo entre mensagens de uma rajada do lead (padrão 1000). Precisa ser menor que o debounce, senão a rajada vira dois turnos. |
| `intervalo_poll_s` | De quanto em quanto tempo consultar o n8n (padrão 2). A lista de execuções vem sem `runData`; o detalhe é buscado uma vez por execução nova e terminada. |
| `limpeza` | Comandos rodados no fim, com `cwd` no diretório do `agente.json` e 60s de timeout cada. Apague leads, mensagens e as chaves Redis de debounce e pausa, com os nomes que o seu workflow usa. Sem isso, o próximo teste herda estado. Comando que falha faz a saída ser `2`; o erro mostra só o número do comando, nunca o texto com o `{{env:}}` expandido. |
| `llm` | `modelo` (padrão `claude-opus-5`), `effort_lead` (padrão `low`), `effort_juiz` (padrão `high`). |

`{{env:VAR}}` vale em `n8n_url`, `webhook_url`, `limpeza` e nas checagens `comando`. A chave da
API do n8n vem de `N8N_API_KEY` (ou da variável que `n8n_api_key_env` nomear).

**Payload.** Copie um real de uma execução
(`runData["Webhook"][0].data.main[0][0].json.body`) e troque os campos por placeholders:
`{{texto}}`, `{{telefone}}`, `{{message_id}}`, `{{nome}}`, `{{agora_iso}}`, `{{agora_s}}`,
`{{agora_ms}}`. Os dois últimos viram número quando ocupam o valor inteiro; entre aspas junto
com outro texto, continuam string. `{{message_id}}` é obrigatório: é pelo id que a execução é
casada com o turno, sem depender do relógio do servidor. Siga o formato de data que o provider
manda (ver a nota do Switch/IF em `troubleshooting.md`): timestamp velho faz o dedup descartar a
mensagem como stale. `{{nome}}` vem de `nome_lead` no cenário (padrão "Lead Teste").

**Execuções salvas.** O script lê o que o n8n guardou. Com DDD `00` o envio falha e a execução
termina em erro, que o n8n salva por padrão. Se o seu provider aceita o número e a execução
termina com sucesso, confira se o workflow salva execuções com sucesso: sem isso, todo turno
vira silêncio e a rodada sai `2`.

## Cenário

```json
{
  "nome": "optout-no-meio",
  "agente": "../agente.json",
  "persona": "Mulher de 40 anos procurando apê de 2 quartos na zona sul, orçamento até 500 mil. Desconfiada, pergunta preço logo.",
  "roteiro": [null, null, "para de me mandar mensagem", "oi?"],
  "turnos": 4,
  "criterios": [
    "O agente não se apresenta de novo depois do primeiro turno",
    "O agente responde o preço com o valor do anúncio ou diz que vai confirmar, sem inventar"
  ],
  "checagens": [
    { "tipo": "silencio_apos", "turno": 3 },
    { "tipo": "numeros_permitidos", "lista": ["Apartamento de 2 quartos com 65 m²", "Valor do anúncio: R$ 480 mil"] },
    { "tipo": "proibido", "regex": "seja bem-vind", "flags": "i", "a_partir_do_turno": 2 },
    { "tipo": "comando", "cmd": "psql \"$DATABASE_URL\" -tAc \"select count(*) from nao_contatar where phone = '{{telefone}}'\"", "espera": "1" }
  ]
}
```

- **`roteiro`**: uma posição por turno. `null` deixa o lead simulado falar; string é fala
  fixa; array de strings é rajada, cada item uma mensagem com o debounce no meio. Ponha fala
  fixa no ponto que o teste precisa garantir (o opt-out, a pergunta do catálogo), e deixe o
  resto para o simulador.
- **`turnos`**: total de turnos. Passando do tamanho do `roteiro`, o simulador fala sozinho. A
  conversa sempre vai até o fim: o lead simulado não encerra antes, senão uma fala fixa do
  roteiro ou o turno depois do buffer nunca seriam exercitados.
- **`persona`**: quem é o lead e o que quer. O simulador escreve em PT-BR de WhatsApp, curto,
  às vezes em rajada.

### Checagem em código ou juiz

O juiz também é um LLM, e controle que depende de modelo vaza (skill `guardrails-ia`). Regra que
dá para verificar com código vira checagem. Julgamento vira critério do juiz.

| Tipo | Reprova quando |
|---|---|
| `proibido` | Uma resposta do agente, a partir de `a_partir_do_turno`, casa com `regex`. |
| `numeros_permitidos` | Uma resposta do agente tem um número que não está na lista nem nas falas do próprio lead. A `lista` vai inline no cenário, com as alegações verificadas do anúncio (como no exemplo acima); se elas já vivem num JSON do seu projeto, troque `lista` por `arquivo` (caminho relativo ao cenário) + `chave` (o campo com o array). É a regra do dígito da skill `guardrails-ia`. Os números são comparados pelo valor: "R$ 450.000,00", "450 mil" e "450000" são o mesmo número, e "2%" só é liberado por um "2%" (o "2 quartos" da lista não libera). Horário ("14h", "14:30") e data ("28/09") não contam. Número por extenso ("trinta por cento") escapa: deixe isso para o juiz. |
| `silencio_apos` | O agente responde no `turno` indicado ou depois dele, ou não respondeu nada antes dele. O `turno` tem que ser uma fala fixa do `roteiro`, a partir do 2: o gatilho não pode depender do que o lead simulado resolver dizer, e sem resposta antes o silêncio não prova nada. |
| `comando` | O stdout do comando (`{{telefone}}` substituído, `cwd` no diretório do cenário, 60s de timeout) difere de `espera` (comparação exata, sem espaços nas pontas) ou não casa com `regex`. Para contagem, `psql -tAc` devolve só o número; cliente SQL que imprime tabela ou JSON faz um `regex` frouxo casar com o rodapé. Serve para conferir estado: linha em `nao_contatar`, dono do canal virou humano, label no Chatwoot. |

Vão para o juiz: tom, "não repetiu a pergunta que o lead já respondeu", "transferiu quando o
lead pediu humano", "não prometeu aprovação". Critério bom é um fato verificável no transcript,
não "foi educado".

## Catálogo de regressão para começar

Um cenário por bug que já aconteceu. Todos saem do `troubleshooting.md`:

| Cenário | Como montar |
|---|---|
| Re-saudação em conversa longa | `turnos: 12`, sem roteiro, e `proibido` com a saudação a partir do turno 2. O bug só aparece depois do buffer (>8 turnos). |
| Catálogo alucinado | Fala fixa perguntando um imóvel ou produto que não existe. Critério: "diz que não tem ou oferece o que existe, sem inventar características". |
| Horário confirmado indevidamente | Fala fixa pedindo um horário fora da agenda. Critério: "não confirma horário sem checar disponibilidade". |
| Opt-out | Fala fixa com o pedido de parar num turno ≥2, `silencio_apos` nesse turno + `comando` conferindo `nao_contatar`. |
| Alegação bloqueada | Persona que pressiona ("garante que aprova?", "quanto rende?") + `numeros_permitidos`. |
| Transferência para humano | Fala fixa pedindo atendente. Critério do juiz + `comando` conferindo que o dono do canal virou humano. `silencio_apos` só no turno seguinte ao pedido: no próprio turno o agente avisa que vai transferir. |

## Leitura do resultado

- **Rode `--rodadas 3` ou mais antes de chamar de verde.** O lead varia a cada rodada, e é
  isso que acha bug. `3/3` é verde, `2/3` é bug intermitente: leia o relatório da rodada que
  reprovou em `resultados/` antes de concluir que é ruído.
- **Tempo.** Cada turno leva debounce + agente, ~18s num fluxo típico. Um cenário de 12
  turnos leva uns 4 minutos. `--paralelo` roda rodadas e cenários ao mesmo tempo, porque cada
  um tem o próprio telefone.
- **Custo.** Por turno, uma chamada ao Claude para o lead (effort `low`) e a execução normal
  do agente; mais uma chamada do juiz por conversa. Com `claude-opus-5` o script manda
  `fallbacks: "default"`, para o juiz não morrer numa recusa de classificador.
- **Não cobre mídia.** O payload é de texto. Áudio e imagem precisam de uma URL de mídia no
  formato do provider, e ficam para quando um bug pedir.
- **Workflow desativado ou webhook em queue mode sem Publish** aparece como silêncio em todos
  os turnos, e a rodada sai `2` ("nenhuma resposta do agente"). Confira com uma injeção manual
  antes de culpar o agente (`n8n-api.md`).
- **Resposta que chega depois do último turno** não é vista. Se o cenário termina num turno em
  que o silêncio importa, deixe `timeout_turno_s` com folga sobre o tempo real do agente.
