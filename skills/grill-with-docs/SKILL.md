---
name: grill-with-docs
description: >-
  Versão "por-projeto" do grilling: interroga o plano ANCORADO no domínio do
  projeto (.context/docs, AGENTS.md, regras acordadas) e grava as decisões de
  volta na doc. Use quando o projeto tem .context/ e o plano toca regras de
  negócio, automação (n8n/Pipedrive) ou dado sensível — onde read-before-act
  vale. Gatilhos: "grill com docs", "fecha o plano com o contexto do projeto".
---

# Grill with docs — grilling ancorado no projeto

Igual à skill `grilling`, com dois acréscimos que só fazem sentido dentro de um
projeto recorrente:

## Antes de interrogar

1. **Leia o contexto do projeto primeiro** (read-before-act): `AGENTS.md` na
   raiz + `.context/docs/` + qualquer regra acordada/memória do projeto. Não
   pergunte o que a doc já responde — traga como fato.
2. **Respeite estado intencional.** Nó n8n desabilitado, flag, decisão de
   negócio registrada no `.context` = não desfaça sem autorização explícita.
   Acordo verbal não basta; vale o que está escrito no `.context`.

## Durante

Rode o loop da skill `grilling` (uma pergunta por vez, com recomendação, fato
→ busca / decisão → pergunta, não executa até confirmar).

## Depois

Ao fechar o entendimento, **grave as decisões na doc certa** (roteamento de
feedback do CLAUDE.md):

- Regra de comportamento durável do projeto → `.context/docs/` (ou CLAUDE.md do
  projeto se for regra dura).
- Fato durável → memória.
- Doc de implementação / changelog → `.context/docs/`.

Nunca infle o CLAUDE.md com o histórico da conversa — ele cresce com regra, não
com changelog.
