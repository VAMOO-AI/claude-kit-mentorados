---
name: worktrees
description: >-
  Como trabalhar em paralelo no mesmo projeto sem uma sessão atrapalhar a
  outra: worktrees isolados, commit seguro quando várias abas compartilham o
  mesmo clone, e limpeza no fim. Use quando abrir mais de um terminal/sessão no
  mesmo repositório, antes de criar um worktree, ou antes de commitar num clone
  que outra sessão também usa. Gatilhos: "worktree", "paralelo no mesmo repo",
  "outra aba/sessão", "limpar branch".
---

# Terminais paralelos & worktrees

## Por que isso importa

Várias abas/sessões abertas no MESMO clone compartilham a mesma branch e a mesma
área de staging do Git. Se uma sessão troca de branch, a outra pode commitar sem
perceber no lugar errado. Duas formas de se proteger:

## Isolamento (o jeito seguro)

- Sessão que vai **escrever**: crie um *worktree* próprio (pasta separada com
  branch própria) sempre que outra sessão puder estar ativa no mesmo repo. O
  clone principal fica na `main`, só pra leitura.
  `git worktree add ../meu-worktree -b feat/minha-tarefa`.
- **NUNCA** faça `git checkout`/`switch`/`stash`/`reset` num clone que outra
  sessão está usando sem avisar — ela pode ter trabalho em andamento.
- Um worktree branca da versão do `origin`. Pra restaurar um arquivo, use
  `git restore --source=origin/<branch> <arquivo>` — não copie o arquivo de
  outro clone na mão (ele pode estar desatualizado e você sobrescreve código
  novo com velho).

## Commit seguro quando o clone é compartilhado

- Confirme a branch **no mesmo comando** do commit, não em passos separados (a
  branch pode mudar no meio):
  `[ "$(git branch --show-current)" = "feat/x" ] && git commit ...`.
- `git add` só nos arquivos que você mexeu (`git add <arquivos>`), **nunca**
  `git add -A`/`-u`/`.` — o staging é compartilhado; arquivo de outra sessão
  entra de carona no seu commit.
- Depois de todo commit: `git log --oneline -1` e confira que caiu na branch
  certa ANTES de push/merge.
- O kit instala um hook que **bloqueia `git commit` na `main`/`master`**. Se um
  dia precisar mesmo commitar na main de propósito, rode o comando com
  `HOTFIX_MAIN=1` na frente. O hook checa a branch **antes** do comando —
  `git checkout -b X && git commit` é bloqueado (ele vê a main). Crie a branch
  num comando separado, depois commite.

## Limpeza no fim

Ao terminar o trabalho num worktree: remova worktrees órfãos
(`git worktree remove`), delete branches já mergeadas, rode `git fetch --prune`,
e volte pra `main` com `git pull`.
