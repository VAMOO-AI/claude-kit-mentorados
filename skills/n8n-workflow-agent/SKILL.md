---
name: n8n-workflow-agent
description: Use when building, editing, debugging, or deploying n8n workflows that use WhatsApp agents — covers n8n API, Code Node rules, UAZAPI, Chatwoot, NotificaMe, dispatch pipeline, client pipeline, daily summary, ElevenLabs TTS, Redis pausa, and common pitfalls learned from production incidents
---

# n8n Workflow Agent — Full WhatsApp Automation Stack

Skill de referência pra construir e manter agentes de IA no WhatsApp via n8n.
Nasceu de produção — cada regra preveniu ou corrigiu um bug real.

Este arquivo é o **roteador**: traz a regra dura de layout, a arquitetura típica
e a ordem de decisão. O conhecimento por domínio está em `references/` — **leia
só a referência do tema da tarefa**, não todas.

## Qual referência ler (ordem de decisão)

| Tarefa envolve... | Leia |
|---|---|
| Criar/editar workflow via API, PUT, ativação, build a partir de source files | [references/n8n-api.md](references/n8n-api.md) |
| Code Node (JS), HTTP node com `jsonBody` | [references/code-node.md](references/code-node.md) |
| Query Postgres/Supabase, `queryReplacement`, schema `dispatch_tracking` | [references/postgres.md](references/postgres.md) |
| Enviar N mensagens/balões, fan-out, debounce, pausa Redis, anti-loop, dedup, keep-alive 24h | [references/messaging-patterns.md](references/messaging-patterns.md) |
| UAZAPI (alertas internos, mídia, uptime watcher) | [references/uazapi.md](references/uazapi.md) |
| NotificaMe (templates client-facing, status callbacks) | [references/notificame.md](references/notificame.md) |
| Chatwoot (espelho, labels, transferência, webhooks) | [references/chatwoot.md](references/chatwoot.md) |
| Pipedrive (deals, stages via n8n) | [references/pipedrive.md](references/pipedrive.md) |
| Pipeline de dispatch, estágios do cliente, resumo diário, follow-up | [references/pipelines.md](references/pipelines.md) |
| ElevenLabs TTS, auth de webhook, API route Next.js, Supabase Storage | [references/integrations-misc.md](references/integrations-misc.md) |
| **Qualquer bug, erro estranho, teste de agente** | [references/troubleshooting.md](references/troubleshooting.md) — comece pela tabela Common Mistakes |

## Layout Visual — Linhas Retas (REGRA DURA — NUNCA QUEBRAR)

**NUNCA criar nodes com conexões que se cruzam.** Isso é inegociável. Workflows são lidos visualmente por humanos. **Linhas que se cruzam = caos cognitivo = rejeição imediata.** Canvas limpo com chains retas é o padrão esperado — confirmado em produção.

Ao posicionar nodes via API (`node.position = [x, y]`), SEMPRE calcular coordenadas para garantir zero cruzamentos. Se um workflow simples (linear) não tem branches, todos os nodes ficam na mesma Y com X crescente.

### Regras

1. **Chain linear horizontal:** mesma coordenada Y. Se A→B→C, mantém Y constante, varia só X. Espaçamento mínimo 220px em X.
2. **Branches paralelas em Y separados:** quando um Switch/IF cria N branches, distribui em Y crescente (ex: branch[0] Y=400, branch[1] Y=600, branch[2] Y=800). Cada branch corre horizontal nessa Y dela.
3. **Branches que convergem:** quando 2+ branches voltam pro mesmo node downstream, escolhe a Y do branch principal e roteia visualmente em "L" (canto reto), nunca em diagonal.
4. **Não puxa linha pra trás:** se um node referencia outro upstream via `$('Foo').first()`, mantém a conexão visual fluindo pra direita. Pra trás é só pra Wait/Loop com retorno explícito.
5. **Sub-fluxos verticais quando branches são muitas:** se Switch tem 4+ branches, considera empilhar verticalmente em colunas alinhadas (canvas vira grid).
6. **Hierarquia Y por tipo de operação:** Y baixo = caminho feliz; Y alto = error handling, skip branches, alerts. Mantém consistente no workflow inteiro.

### Anti-pattern (causa cruzamento)

- Mover um node "pra cima" geometricamente quando o anterior está embaixo → cria diagonal que cruza outras chains
- Mesma Y pra branches paralelas (todas em 400) → ramais sobrepostos
- Posicionar Set/Code "auxiliar" longe do node que consome → linha longa atravessa outras

### Ao editar via API

`node.position = [x, y]` é onde o n8n renderiza. Quando script adiciona um node novo no meio de uma chain, **calcula a posição assim**:

```python
# Insere node entre A e B
new_x = nodeA["position"][0] + 220
new_y = nodeA["position"][1]   # mesma Y de A
# Depois shifta B (e tudo a partir dele) +220 em X pra abrir espaço
```

Sem isso, fica empilhado em cima ou cruzando. Após PUT, drag+save no UI **preserva** as coordenadas (não auto-relayouta) — então responsabilidade do script colocar certo já.

## Workflow Architecture (Fluxo Típico N8N)

```
Webhook UAZAPI
  → Normalizar Entrada (Code Node)
  → IF skip? (grupo, fromMe)
  → IF audio? (sim → transcrever → set texto)
  → Dedup (lock file)
  → IF pausa IA? (Redis check)
  → Debounce Save → Wait 3s → Debounce Verify
  → AI Agent (LangChain + GPT-4o + Postgres Memory)
  → Validar JSON resposta
  → IF transferir? (sim → notificar admin + pausa Redis + Chatwoot labels)
  → IF audio response? (TTS ElevenLabs)
  → Split Out Mensagens → Loop → Enviar UAZAPI/NotificaMe
  → Registrar Chatwoot (private: true)
```

## Stack coberta

- **n8n**: API, Code Nodes, workflow patterns
- **UAZAPI**: WhatsApp provider (alertas internos, mídia)
- **NotificaMe**: WhatsApp provider (templates client-facing)
- **Chatwoot**: CRM omnichannel (espelho, labels, transferência, atividade)
- **Dispatch Pipeline**: dispatch backend (ou o próprio n8n) → N8N → NotificaMe → webhook callbacks
- **Client Pipeline**: avanço de estágio (contatado → visualizado → interagiu → qualificado → transferido)
- **Daily Summary**: relatório diário agregado via UAZAPI
- **ElevenLabs**: TTS pra respostas em áudio
- **Redis**: pausa IA, debounce
