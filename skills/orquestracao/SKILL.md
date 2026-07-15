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

# Orquestração de subagents

## Quando fan-out

- Subagents paralelos pra **>5 arquivos independentes**.
- Escolha de modelo: deixa o harness decidir por tarefa. Haiku via subagent
  explícito só pra lote mecânico real (ex: 20 renames).

## Resiliência a rate-limit (429/529)

- Dispare em **ondas**, não todos de uma vez — pico simultâneo dispara o limite.
- `.filter(Boolean)` **SEMPRE** nos resultados de `parallel()`/`pipeline()` —
  agente morto retorna `null` e vira "null object error" sem o filtro.
- Run morreu no meio → retome com `resumeFromRunId` (recupera o prefixo já
  feito), não reprocesse.
- `pipeline()` > `parallel()` onde der: barrier concentra carga, pipeline
  espalha.

## Writes em paralelo (scope contract)

- Subagents read-only por default (Grep/Read/Glob). Edit/Write na conversa
  principal.
- Writes paralelos só com **scope contract explícito por agent**. Worktree:
  cada agent confirma a branch correta antes do primeiro write.
- **Subagent não recebe `~/.claude/agents.md` sozinho** — ao dispatchar com
  writes, cole o scope contract e o formato de report de lá no prompt do agent.

## Cleanup

Worktree cleanup ao finalizar → skill `worktrees`.
