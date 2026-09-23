---
name: orquestracao
description: >-
  Como dispatchar subagents e workflows resilientes a rate-limit: teto de
  concorrência do runner, .filter(Boolean), pipeline > parallel, scope
  contract pra writes, resumeFromRunId. Use ao orquestrar >5 arquivos
  independentes, montar workflow/fan-out, ou quando um run morre no meio.
  Gatilhos: "subagents", "fan-out", "workflow", "paralelo em N arquivos",
  "rate limit 429/529".
---

> Derivada de `claude-config-team/skills/vamoo-orquestracao`. Ao divergir de propósito, diga aqui o quê e por quê.

# Orquestração de subagents

## Quando fan-out (e quando NÃO)

- Subagents paralelos pra **>5 arquivos independentes**.
- Freio anti-over-delegation: não delegue o que resolve em poucos tool
  calls; 1 agent se 1 basta; NÃO use subagent pra verificar/double-checkar
  trabalho recém-feito — revisor é pra PR/branch, não pra auto-conferência.
- Escolha de modelo: deixa o harness decidir por tarefa. Haiku via subagent
  explícito só pra lote mecânico real (ex: 20 renames).
- Effort em `agent()`: `effort: 'low'` em estágio mecânico (extrair,
  renomear, formatar), que não depende de raciocínio; omitido no resto, e aí
  o agente herda o esforço da sessão; `'high'` só no judge/verify que errou
  no nível herdado; `'xhigh'`/`'max'` só com ganho medido. Cada nível acima
  gasta mais do limite do seu plano, então o esforço sobe onde o erro
  apareceu, não por precaução. No Opus 5.5 cada nível pensa mais que o mesmo nível no
  Opus 5, e um `'high'` copiado de workflow antigo sai mais caro do que saía.

## Resiliência a rate-limit (429/529)

- O runner do Workflow já limita a concorrência: no máximo `min(16, CPUs−2)`
  chamadas `agent()` rodando ao mesmo tempo por workflow (com 8 CPUs, 6 de
  cada vez; com 4, só 2), e o excesso entra em fila e roda quando abre vaga.
  Passe a lista inteira para `pipeline()`/`parallel()`. Dividir em lotes à
  mão, com barreira entre eles, não baixa o pico, que o teto já segura: só
  faz cada lote esperar o agente mais lento enquanto as vagas ficam paradas.
- `.filter(Boolean)` **SEMPRE** nos resultados de `parallel()`/`pipeline()` —
  agente morto retorna `null` e vira "null object error" sem o filtro.
- Run morreu no meio → retome com `resumeFromRunId` (recupera o prefixo já
  feito), não reprocesse.
- `pipeline()` > `parallel()` onde der: barrier concentra carga, pipeline
  espalha.

## Ambiente sem a dependência → implemente, simule, documente o real

Agente em container/cloud/sandbox não alcança o que só existe na máquina do
operador: Chrome logado, VPN, banco de produção, dispositivo, credencial que
não sai do cofre. O default do agente aí é ruim de dois jeitos — trava o
projeto inteiro por causa de um pedaço, ou finge que testou.

Escreva a cláusula no prompt do dispatch, sempre nestes termos:

> Se este ambiente não alcança <dependência>, **não pare o projeto**: implemente
> a camada completa, teste contra um fake/página simulada, e deixe o teste real
> DOCUMENTADO (comando exato + o que observar) para rodar no ambiente que
> alcança. Reporte o bloqueio exato quando chegar nele; siga com tudo que não
> depende dele.

Duas metades, e a segunda é a que costuma sumir: o trabalho continua **e** o
que não foi verificado é declarado como não verificado, com o comando pronto
para quem tem o ambiente. Sem ela, o relatório volta com "implementado e
testado" e ninguém sabe qual metade é qual.

Vale igual para credencial faltando: continue tudo que não depende dela.

## Writes em paralelo (scope contract)

- Subagents read-only por default (Grep/Read/Glob). Edit/Write na conversa
  principal.
- Writes paralelos só com **scope contract explícito por agent**. Worktree:
  cada agent confirma a branch correta antes do primeiro write.
- **O `~/.claude/agents.md` não chega sozinho ao subagente.** Subagente
  recebe os mesmos CLAUDE.md da sua sessão, menos tipos embutidos como
  `Explore` e `Plan`, que não recebem nenhum. E o CLAUDE.md que o kit instala
  só resume as regras de subagente e aponta o arquivo, sem importá-lo. Então:
  - dispatch para `Explore`/`Plan`: o prompt diz "Leia ~/.claude/agents.md
    antes de começar e siga as regras de subagent de lá", porque eles não têm
    nem o resumo;
  - nos outros, não mande reler o CLAUDE.md nem cole as regras dele no
    prompt: cite só a regra de que aquele estágio precisa;
  - com writes, cole no prompt o scope contract e o formato de report do
    `agents.md`, que o resumo do CLAUDE.md não traz.

## N terminais no mesmo repo: escopo disjunto e merge em fila

Abrir várias sessões de uma vez no mesmo repositório é fan-out sem orquestrador:
ninguém vê o que o outro faz. Duas regras bastam:

- **Escopo disjunto por arquivo**, decidido ANTES de abrir os terminais. Dois
  terminais no mesmo `src/pages/X.tsx` escrevem o mesmo código duas vezes, e o
  segundo só descobre na hora do PR.
- **Merge é serializado, não paralelo.** O primeiro que mergeia move a `main`, e
  o verde do CI de todos os outros passa a ser de uma base que já não é a da
  `main`. Rebase quem tocar os mesmos arquivos; o resto mergeia como está — o
  squash não apaga trabalho alheio. O porquê, e a armadilha do diff de dois
  pontos que sugere o contrário, estão na skill `worktrees` ("Base velha").

## Cleanup

Worktree cleanup ao finalizar → skill `worktrees`.
