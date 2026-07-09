---
name: grilling
description: >-
  Interroga o usuário sem dó sobre um plano ou design até chegar a
  entendimento compartilhado, resolvendo cada ramo da árvore de decisão antes
  de codar. Use quando o pedido é vago, a decisão está aberta, ou o usuário
  usa qualquer gatilho "grill" / "me interroga" / "fecha o plano comigo".
---

# Grilling — interrogatório de plano

Transforma "instruções vagas → pergunte" (regra passiva) num loop ativo que
**não deixa começar** enquanto houver ramo de decisão em aberto. É o Target Lock
levado a sério.

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
