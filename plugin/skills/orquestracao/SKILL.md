---
name: orquestracao
description: >-
  Como dispatchar subagents e executores em paralelo sem dois writers no mesmo
  arquivo: lotes por dependência (Files:/Depends-on:), scope contract pra writes,
  brief autossuficiente com Status:, N terminais no mesmo repo. Use ao orquestrar
  >5 arquivos independentes, montar workflow/fan-out, ou quando um run morre no
  meio. Gatilhos: "subagents", "fan-out", "workflow", "paralelo em N arquivos",
  "rate limit 429/529".
---

# Orquestração de subagents

A mecânica do Workflow (teto de concorrência do runner, `.filter(Boolean)`, `pipeline()` >
`parallel()`, `resumeFromRunId`, effort por estágio) está na skill built-in
`workflow-authoring`. Aqui fica o que ela não cobre.

## Quando fan-out (e quando NÃO)

- Subagents paralelos pra **>5 arquivos independentes**. Não delegue o que resolve em poucos
  tool calls, nem a conferência do trabalho recém-feito: revisor é pra PR/branch.
- Qual subagente: lote de implementação despachado → agente `executor` do kit; review →
  `revisor`. Os dois rodam em `effort: medium`.
- Onda manual, com barreira entre lotes, só com 429/529 medido: o runner já segura o pico.

## Ambiente sem a dependência → implemente, simule, documente o real

Agente em container/cloud/sandbox não alcança o que só existe na máquina do operador (Chrome
logado, VPN, banco de produção, credencial que não sai do cofre). Escreva no prompt do dispatch:

> Se este ambiente não alcança <dependência>, **não pare o projeto**: implemente
> a camada completa, teste contra um fake/página simulada, e deixe o teste real
> DOCUMENTADO (comando exato + o que observar) para rodar no ambiente que
> alcança. Reporte o bloqueio exato quando chegar nele; siga com tudo que não
> depende dele.

A segunda metade é a que some: o que não foi verificado volta declarado como não verificado,
com o comando pronto. Vale igual para credencial faltando.

## Quais executores rodam juntos: lotes por dependência

Antes de despachar N executores, marque cada lote com dois campos:

- `Files:` são os caminhos exatos que o lote cria ou edita ("os arquivos do front" não
  é marcação). `Depends-on:` são os lotes de que ele precisa, ou `nenhum`. Usar função,
  tipo ou tabela que outro lote cria é depender dele.
- Dois lotes só saem juntos sem dependência entre eles, nem transitiva, **e** com os
  `Files:` disjuntos. Mesmo arquivo em pontos diferentes desqualifica: o worktree adia o
  choque para o merge, não o evita.
- Dúvida em qualquer um dos dois campos → o lote depende de tudo que veio antes. O erro
  seguro é perder paralelismo.
- Dois lotes no mesmo arquivo → um executor só, com os dois.
- `CHANGELOG.md`, lockfile e settings compartilhado não entram no `Files:` de executor:
  ficam com a conversa principal, que escreve depois dos merges.
- Cada executor continua em worktree próprio, com commit e PR próprios; o merge é
  serializado (seção "N terminais", abaixo).

## Writes em paralelo (scope contract)

- Subagents read-only por default (Grep/Read/Glob). Edit/Write na conversa principal.
- Writes paralelos só com **scope contract explícito por agent**. Em worktree, cada agent
  confirma a branch correta antes do primeiro write.
- **O `~/.claude/subagentes.md` não chega sozinho ao subagente.** O CLAUDE.md que o kit
  instala só resume as regras e aponta o arquivo, e `Explore`/`Plan` não recebem nem o resumo:
  - dispatch para `Explore`/`Plan`: o prompt diz "Leia ~/.claude/subagentes.md antes de
    começar e siga as regras de subagent de lá";
  - nos outros, não mande reler o CLAUDE.md: cite só a regra de que aquele estágio precisa;
  - com writes, cole no prompt o scope contract e o formato de report do `subagentes.md`;
  - com browser ou QA visual, cole a regra de imagem (screenshot só quando o pixel é a
    evidência; estado/texto/erro/DOM → `read_page`/`get_page_text`; veredito em texto).
- **O brief é autossuficiente.** O executor não viu a conversa: "igual ao lote 3" e teste
  descrito em prosa não existem para ele. Cole o trecho, o caminho e o comando. O report abre
  com a linha `Status:` (`FEITO`, `FEITO_COM_RESSALVAS`, `PRECISA_CONTEXTO` ou `BLOQUEADO`),
  que é o que você lê primeiro ao juntar N reports.

## N terminais no mesmo repo: escopo disjunto e merge em fila

Várias sessões no mesmo repositório são fan-out sem orquestrador:

- **Escopo disjunto por arquivo**, decidido ANTES de abrir os terminais. Dois terminais no
  mesmo `src/pages/X.tsx` escrevem o mesmo código duas vezes.
- **Merge é serializado.** O primeiro que mergeia move a `main`, e o verde do CI dos outros
  passa a ser de uma base velha. Rebase quem tocar os mesmos arquivos; o resto mergeia como
  está (skill `worktrees`, "Base velha").

Cleanup de worktree ao finalizar → skill `worktrees`.
