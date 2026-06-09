---
name: agent-reporting
description: Use when starting any task that involves ≥3 tool calls or file edits (Write/Edit/NotebookEdit) — registers progress in TickTick project "🤖 Claude Agents" with checkpoints. Skip for read-only Q&A, simple lookups, slash commands, or single-file fixes already requested. Triggered automatically at task start, NOT mid-session.
---

# Agent Reporting

Reporta trabalho substancial no TickTick automaticamente, criando uma trilha do que os agentes Claude estão fazendo. O usuário consome via app TickTick (kanban, calendar, mobile).

## Quando usar

**Trigger no início da tarefa** se qualquer condição:
- Pedido envolve ≥3 tool calls esperados
- Pedido envolve edição de arquivo (Write, Edit, NotebookEdit)
- User explicitamente pede ("registra no TickTick", "loga isso", "abre task")

**NÃO trigger** em:
- Perguntas-resposta puras (sem tool calls ou apenas 1)
- Slash commands de exploração (`/help`, `/status`, `/config`)
- `git status`, `git log`, `ls`, `cat` (read-only)
- Edits triviais já apontados pelo user (typo, rename de 1 var)

## Como usar

A skill expõe 3 comandos via script `~/.claude/skills/agent-reporting/ticktick-task.sh`. Use Bash tool com **runs paralelos** quando possível.

### 1. Início da tarefa — `create`

Logo após decidir que a tarefa qualifica, mas ANTES de mais de 1 tool call de trabalho real:

```bash
~/.claude/skills/agent-reporting/ticktick-task.sh create \
  "<título curto, ≤80 chars>" \
  "<descrição com pedido completo do user>" \
  "agent" "<basename-do-cwd>"
```

**Título**: primeira frase do pedido do user, sem aspas duplas internas. Ex.: `"refatora componente Header pra usar shadcn"`.

**Descrição**: pedido completo do user (parafraseado se for longo). Tags adicionais: nome do projeto. Ex.: `"agent" "mentorias-platform"`.

Output: imprime `task_id` (ignorar — script já gravou em state).

### 2. Durante o trabalho — `checkpoint`

A cada **mudança de direção significativa**, descoberta importante, ou conclusão de sub-step. Não use pra cada tool call (vira ruído). Bons momentos:
- Acabei de explorar o codebase, descobri que X
- Mudei de approach: era A, agora é B porque Y
- Implementei o componente, agora vou pra integração
- Bug encontrado: descrição
- Test pass / fail relevante

```bash
~/.claude/skills/agent-reporting/ticktick-task.sh checkpoint "<linha curta>"
```

Mantenha cada checkpoint em **uma linha** (sem `\n`). Sanitize.

### 3. Fim da tarefa — `done`

Quando você está prestes a reportar conclusão pro user (antes do summary final):

```bash
~/.claude/skills/agent-reporting/ticktick-task.sh done \
  "<resumo: arquivos tocados, commits, deploys, links>"
```

Resumo deve caber em 2-4 linhas curtas. Inclua:
- Arquivos principais modificados (paths relativos)
- Commits criados (sha curto + msg)
- Comandos de validação rodados (test, typecheck) e resultado
- Links se houver (PR, deploy URL)

## Limitações & quirks

- TickTick API quebra silenciosamente com `\n` cru, `\\`, certos escapes. O script já sanitiza — não precisa pré-tratar.
- 1 task ativa **por cwd**. Se você abrir 2 sessões no mesmo dir, segunda sobrescreve state. (Edge case raro; iterar depois se virar problema.)
- Se `create` falhar (rede, token expirado), **não bloquear o trabalho**. Reportar erro brevemente ao user e seguir. Re-auth: `cd ~/WORKSPACES/mcp-servers/ticktick-mcp && ~/.local/bin/uv run -m ticktick_mcp.cli auth`.
- `checkpoint` e `done` são no-op silenciosos se não houver task ativa (sem state file). Útil pra evitar erro se trigger falhou.

## Exemplos rápidos

**Tarefa**: "adiciona Sidebar ao layout principal"
```bash
~/.claude/skills/agent-reporting/ticktick-task.sh create \
  "adiciona Sidebar ao layout principal" \
  "User quer Sidebar no app/(app)/layout.tsx, com links pras rotas autenticadas. Stack: Next 16 + Tailwind v4 + shadcn." \
  "agent" "mentorias-platform"
```

Mid-task:
```bash
~/.claude/skills/agent-reporting/ticktick-task.sh checkpoint "Sidebar component criado em components/Sidebar.tsx, falta wirear no layout"
```

Fim:
```bash
~/.claude/skills/agent-reporting/ticktick-task.sh done \
  "Tocados: components/Sidebar.tsx (novo), app/(app)/layout.tsx (import). Commit feat(layout): add sidebar (a3b4c5d). Typecheck ok."
```

## Anti-padrões

- ❌ Criar task pra perguntas (`"como o RLS funciona aqui?"`) — não tocou código.
- ❌ 1 checkpoint por tool call — vira spam, perde sinal.
- ❌ Esquecer `done` — task fica aberta forever, kanban entope.
- ❌ Title genérico (`"trabalho no projeto"`) — o user vai abrir o kanban e não saber o que é.
