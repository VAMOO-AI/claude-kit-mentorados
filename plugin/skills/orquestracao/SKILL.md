---
name: orquestracao
description: >-
  Como dispatchar subagents e workflows resilientes a rate-limit no fluxo
  ondas vs. big-bang, .filter(Boolean), pipeline > parallel, scope
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
- Effort em `agent()`: `effort: 'low'` em estágio mecânico, `high`+ só em
  judge/verify — low/medium seguram qualidade a fração do custo.

## Resiliência a rate-limit (429/529)

- Dispare em **ondas**, não todos de uma vez — pico simultâneo dispara o limite.
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
- **Subagent não recebe `~/.claude/agents.md` sozinho** — ao dispatchar com
  writes, cole o scope contract e o formato de report de lá no prompt do agent.

## Cleanup

Worktree cleanup ao finalizar → skill `worktrees`.
