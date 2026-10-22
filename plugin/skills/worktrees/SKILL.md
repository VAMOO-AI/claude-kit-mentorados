---
name: worktrees
description: >-
  Como trabalhar em paralelo no mesmo projeto sem uma sessão atrapalhar a
  outra: worktrees isolados, commit seguro quando várias abas compartilham o
  mesmo clone, e limpeza no fim. Use quando abrir mais de um terminal/sessão no
  mesmo repositório, antes de criar um worktree, ou antes de commitar num clone
  que outra sessão também usa. Gatilhos: "worktree", "paralelo no mesmo repo",
  "outra aba/sessão", "limpar branch".
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-gc.sh" --verificar *)'
  - 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-gc.sh --verificar *)'
---

# Terminais paralelos & worktrees

## Isolamento

- Sessão que vai **escrever**, com outra sessão possivelmente ativa no repo: worktree
  próprio com o `EnterWorktree` (cria em `<repo>/.claude/worktrees/`, onde o kit copia o env
  e liga a memória). O clone principal fica na `main`, só leitura.
- Arquivo **versionado** se restaura de `origin` (`git restore --source=origin/<branch> <arq>`),
  nunca copiado do clone principal: ele pode estar commits atrás.
- **Env:** no primeiro prompt dentro do worktree, um hook copia do clone os `.env*` que o git
  ignora, sem sobrescrever. Worktree criado no meio de uma resposta só recebe no prompt
  seguinte; criado fora de `.claude/worktrees/`, copie à mão. `.npmrc`/`bunfig.toml` ficam de
  fora (token de registry). Sintoma da falta: login com **"Failed to fetch"**.
- **`node_modules`** não vem: `npm install` no worktree. Symlink quebra os binários do `.bin`.

## Quando o guard recusa o comando

*"too complex to verify that it stays inside the worktree"* é do harness, não do kit. Na
2.1.306 seguem recusados: `bash "$VAR/x.sh"` (o caminho literal passa), `source <arquivo>`,
`gh` com `VAR="$(…)"` somado a `-q`/`--jq` entre aspas, launcher antes do `git` (o `git` tem
de ser o primeiro token) e heredoc seguido de `&&`. Contorno: `Write` o comando num `.sh` no
scratchpad e `bash /caminho/absoluto.sh`. Segunda recusa idêntica → troque de ferramenta.

## Base velha

- O squash do GitHub não apaga arquivo que só existe na `main`. Diff de PR é de **três
  pontos** (`origin/main...HEAD`); dois pontos mostra o alheio como deleção.
- **O verde do CI é do seu SHA, não da `main` de agora.** Cruze `git diff --name-only
  origin/main...HEAD` com `git log --name-only HEAD..origin/main`: arquivo ou comportamento
  nas duas → traga a `main` (rebase se a branch é só sua, merge se outra pessoa commita nela) e
  rode os testes de novo. Sem sobreposição, siga: rebase por higiene vira esteira.
- Branch de **outra sessão viva**: não rebase por baixo dela. Worktree próprio de
  `origin/main` e `git cherry-pick` dos commits.

## Commit seguro em clone compartilhado

- Branch conferida no mesmo comando do commit; `git add <arquivos>`, nunca `-A`/`.`.
- O kit bloqueia `git commit` na `main` (`HOTFIX_MAIN=1` de propósito) e checa a branch
  **antes** do comando: crie a branch num comando, commite em outro.
- O kit bloqueia `checkout`/`switch`/`stash`/`reset --hard` no clone principal com outra
  sessão ativa nos últimos 30 min (`PARALLEL_OK=1` só com certeza) e avisa se a branch mudou
  entre prompts.

## O banco local NÃO é isolado por worktree

O `supabase start` (ou o Postgres em Docker) é um só na máquina: a migration de um worktree
aparece no banco do outro. O sintoma é um **`git push` recusado** por gate de schema que acha
tabela fora das suas migrations.

1. `git fetch && git log HEAD..origin/main`: quase sempre o outro já mergeou; traga a `main`.
2. Não mergeado: `--no-verify` é decisão da pessoa, com o motivo dito no PR.
3. **Nunca `db reset` para "limpar"**: apaga as migrations do outro worktree. Dado de teste
   que você inseriu, apague você, linha a linha.

## Limpeza no fim

Só com pedido da pessoa ("pode limpar") e com a **prova completa**:

```bash
gh pr list --state merged --head <branch> --json number,headRefOid   # MERGED
git rev-parse <branch>                                               # == headRefOid
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-gc.sh" --verificar <worktree>   # exit 0
```

O `git worktree remove` apaga o que o git ignora sem recusar (`.env.local` editado,
`outputs/video.mp4`, repo clonado dentro). O `--verificar` não remove nada: sai 0 com
`pode remover:` ou 1 com `keep: <caminho> — <motivos>` (não commitado, env diferente do clone,
repo aninhado, ignorado de valor, branch não mergeada); exit 2 é uso errado. Quando o motivo
diz "sem gh nem token da API", a prova do PR acima vale à mão, com uma conta do `gh` que
enxergue o repo.

- Faltou um item (exit 1): o worktree fica (`ExitWorktree` com `action: "keep"`) e você diz à
  pessoa o que faltou, com a linha `keep:`.
- Prova completa: `git worktree remove <wt>` (nunca `--force`), `git branch -D`, `git worktree
  prune`. Worktree do `EnterWorktree`: `ExitWorktree` `action: "remove"`; `discard_changes:
  true` só com a prova completa e o `--verificar` rodado de novo **logo antes** (ele apaga
  ignorado sem listar).
- Vários: `git-sync --cleanup-dry-run`; `--cleanup-apply` só com o pedido.

Depois, `git fetch --prune`; o clone principal se atualiza com `git pull --ff-only`, sem trocar
de branch.
