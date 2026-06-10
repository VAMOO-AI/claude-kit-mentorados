---
name: pipedrive-automation
description: Use ao automatizar CRM Pipedrive — criar/mover deals, configurar pipeline e estágios, automações por gatilho (deal criado, estágio mudou, deal parado), atividades e relatórios de vendas. Gatilhos - "pipedrive", "automação de CRM", "pipeline de vendas", "deal parado", "relatório de vendas".
---

# Pipedrive Automation

Modelos práticos pra automatizar o Pipedrive: estrutura de pipeline, automações por
gatilho, gestão de atividades e chamadas de API. Use como ponto de partida — troque
nomes de estágios, valores e campos pelos do funil real do cliente.

> **Pré-requisito:** conta Pipedrive com API token (Settings → Personal preferences
> → API). Sem o token dá pra desenhar a automação, mas não executar.

## Ordem de decisão

1. **Mapeie o funil antes de automatizar.** Liste estágios reais, probabilidade e
   tempo máximo aceitável parado (rotting) em cada um. Automação em cima de funil
   bagunçado só acelera a bagunça.
2. **Um gatilho → poucas ações.** Automação que faz 10 coisas é impossível de
   debugar. Prefira várias automações pequenas e nomeadas.
3. **Todo deal precisa de próxima atividade.** A automação mais valiosa é a que
   garante isso: deal sem atividade futura = deal esquecido.

## Estrutura de pipeline (modelo)

```yaml
pipeline:
  nome: "Funil de Vendas"
  estagios:
    - { nome: "Lead",          probabilidade: 10,  rotting_dias: 7 }
    - { nome: "Contato Feito", probabilidade: 20,  rotting_dias: 10 }
    - { nome: "Proposta",      probabilidade: 60,  rotting_dias: 14 }
    - { nome: "Negociação",    probabilidade: 80,  rotting_dias: 7 }
    - { nome: "Ganho",         probabilidade: 100 }
    - { nome: "Perdido",       probabilidade: 0 }

campos_obrigatorios_do_deal: [titulo, valor, organizacao, estagio, dono]

campos_customizados_uteis:
  - { nome: "Origem do Lead", tipo: enum, opcoes: [Site, Indicação, Outbound, Evento] }
  - { nome: "Prazo de Decisão", tipo: enum, opcoes: ["< 1 mês", "1-3 meses", "3-6 meses"] }
  - { nome: "Motivo de Perda", tipo: enum, opcoes: [Preço, Concorrente, Sem budget, Sumiu] }
```

## Automações por gatilho (modelos)

```yaml
automacoes:
  - nome: deal_novo
    gatilho: { tipo: deal_created }
    acoes:
      - criar_atividade: { tipo: call, assunto: "Ligação de descoberta", vence_em_dias: 1 }
      - adicionar_label: "Novo"

  - nome: proposta_enviada
    gatilho: { tipo: deal_stage_changed, para_estagio: "Proposta" }
    acoes:
      - criar_atividade: { tipo: task, assunto: "Follow-up da proposta", vence_em_dias: 3 }
      - atualizar_campo: { campo: "Data da Proposta", valor: "{{hoje}}" }

  - nome: deal_parado
    gatilho: { tipo: deal_rotting, dias: 14 }
    acoes:
      - notificar: { quem: dono, mensagem: "Deal parado há 14 dias" }
      - adicionar_label: "Em risco"
```

## API — operações de deal

```javascript
// Criar deal
const deal = await pipedrive.deals.create({
  title: "Cliente A — Plano Anual",
  value: 50000,
  currency: "BRL",
  org_id: 123,
  person_id: 456,
  stage_id: 1,
  expected_close_date: "2026-08-30",
});

// Mover de estágio
await pipedrive.deals.update(deal.id, { stage_id: 3 });

// Criar atividade vinculada
await pipedrive.activities.create({
  deal_id: deal.id,
  type: "call",
  subject: "Ligação de descoberta",
  due_date: "2026-06-15",
  due_time: "14:00",
});

// Concluir atividade com nota
await pipedrive.activities.update(activityId, {
  done: true,
  note: "Boa conversa, enviar proposta",
});
```

Descobrir IDs de pipeline/estágio (necessário antes de mover deals via API):

```bash
curl -s "https://api.pipedrive.com/v1/pipelines?api_token=$PIPEDRIVE_TOKEN" | jq '.data[] | {id, name}'
curl -s "https://api.pipedrive.com/v1/stages?api_token=$PIPEDRIVE_TOKEN" | jq '.data[] | {id, name, pipeline_id}'
```

> O token vai em `.env.local` (`PIPEDRIVE_TOKEN=...`), nunca hard-coded nem commitado.

## Relatório semanal (o mínimo que vale a pena)

Métricas que importam pra revisão de pipeline:

- **Valor por estágio** (total e ponderado pela probabilidade)
- **Win rate** do período e **ciclo médio** (dias entre criação e ganho)
- **Deals parados** acima do rotting do estágio
- **Motivos de perda** agregados (alimenta o campo customizado acima)

## Boas práticas

1. **Critério claro por estágio** — o time inteiro responde igual "quando um deal vai pra Proposta?".
2. **Higiene de pipeline** — revisão semanal; deal morto vai pra Perdido com motivo, não fica apodrecendo.
3. **Registre toda interação** como atividade — relatório só presta se o dado existir.
4. **Integração via n8n:** pra conectar Pipedrive a WhatsApp/Chatwoot, ver a skill `n8n-workflow-agent` (referência `pipedrive.md`).
