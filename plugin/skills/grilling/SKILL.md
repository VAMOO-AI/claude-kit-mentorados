---
name: grilling
description: >-
  Interroga o usuário sem dó sobre um plano ou design até chegar a
  entendimento compartilhado, resolvendo cada ramo da árvore de decisão antes
  de codar. Acione ao detectar uma implementação GRANDE — multi-sistema,
  schema/auth/infra, irreversível ou de escopo material — onde vale fechar o
  plano antes de codar. NÃO acione por vagueza genérica de tarefa pequena. Os
  comandos manuais "/grill-me" e "/grill-with-docs" continuam sendo do usuário.
---

> Derivada de `claude-config-team/skills/grilling`. Ao divergir de propósito, diga aqui o quê e por quê.

# Grilling — interrogatório de plano

Transforma "instruções vagas → pergunte" (regra passiva) num loop ativo que
**não deixa começar** enquanto houver ramo de decisão em aberto. É o Target Lock
levado a sério.

## Antes de começar: projeto com `.context/`?

Se o projeto tem `.context/` e o plano toca regra de negócio, automação
(n8n/Pipedrive) ou dado sensível, **ancore o loop na doc**: leia `.context/docs`
antes de perguntar (não re-pergunte o que já está decidido lá) e grave as
decisões novas de volta em `.context/docs` ao fechar. (Não delegue pra
`grill-with-docs` — essa skill é `disable-model-invocation`, roda só quando o
usuário a dispara manualmente com `/grill-with-docs`.)

## O loop

Interrogue o usuário sem dó sobre cada aspecto do plano até chegarem a
entendimento compartilhado. Percorra cada ramo da árvore de decisão,
resolvendo as dependências entre decisões uma a uma.

Regras do loop:

1. **Uma pergunta por vez.** Espere a resposta antes da próxima. Despejar
   várias perguntas juntas confunde e mata o fluxo.
2. **Para cada pergunta, dê a sua recomendação.** Nunca pergunte "aberto" —
   pergunte com um default proposto ("eu faria X porque Y — concorda?").
3. **Fato → busque; decisão → pergunte.** Se dá pra descobrir explorando o
   código (qual arquivo de rota, que tipo, existe tal função), NÃO pergunte:
   faça grep/read e traga o fato. As *decisões* são do usuário — ponha cada
   uma e espere a resposta.
4. **Não execute o plano até o usuário confirmar** que chegaram a
   entendimento compartilhado.

## Quando parar

Pare de interrogar quando não restar ramo de decisão que mude o que você vai
tocar (arquivo, tabela, endpoint, comportamento). Aí feche com um resumo
curto do plano acordado e peça "go".

## Modo EXECUTE (atalho)

Se o usuário responder "sim/faz/manda" a um plano já claro, NÃO reabra o
grilling — execute. O grilling é pra quando há ambiguidade real, não pra
carimbar decisão já tomada.
