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

> Derivada de `claude-config-team/skills/vamoo-worktrees`. Ao divergir de propósito, diga aqui o quê e por quê.

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

## Quando o Claude recusa seu comando dentro do worktree

Trabalhando numa sessão isolada, alguns comandos de shell são recusados com
*"too complex to verify that it stays inside the worktree"*. Isso é do **harness**,
não do kit, e não é bug: ele não consegue provar que aquele comando fica dentro
do worktree, então nega.

Pega heredoc grande (`cat > arquivo <<'EOF'`, `python3 - <<'EOF'`), encadeamento
de `&&` com heredoc, laço artesanal com `for`/`comm`/`jq`, e qualquer coisa com
`cd` para o clone compartilhado — inclusive `git worktree add` rodado de lá.

**Não insista no mesmo comando.** Troque de ferramenta:

| Em vez de | Faça |
|---|---|
| `cat > arquivo <<'EOF'` com conteúdo longo | `Write` |
| `python3 - <<'EOF'` com patch de texto | `Edit` (é exatamente o caso de uso dele) |
| `cd <clone>` + `git worktree add` | rode `git worktree add` de dentro do próprio worktree |
| heredoc `&&` comando encadeado | comandos separados, um por chamada |

Heredoc curto (10–15 linhas, sem `&&` depois) costuma passar. O sinal de que
você está insistindo é a **segunda recusa idêntica**: pare e troque de
ferramenta em vez de reescrever o mesmo comando.

Uma pegadinha relacionada: worktree criado fora de `<repo>/.claude/worktrees/`
**não pode ser habitado** pelo `EnterWorktree` ("switching is limited to
worktrees managed by Claude Code"). Se você já está num worktree e precisa de
outra branch, o barato é `git checkout -b <nova> origin/main` no worktree que
você já tem — desde que o trabalho anterior já esteja mergeado ou pusheado.

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

## O banco local NÃO é isolado por worktree

O worktree isola os arquivos do projeto. O banco de desenvolvimento — o
`supabase start`, o Postgres em Docker, o que for — é **um só na sua máquina**,
compartilhado por todos os worktrees. A migration que você roda num worktree
aparece no banco que o outro está usando.

O sintoma não é um erro de banco: é um **`git push` recusado** por um gate que
compara o schema do código com o schema vivo (tipos gerados, checagem de
migrations). Ele acha tabelas que não estão nas suas migrations e reprova por
um motivo que não tem nada a ver com o que você mexeu.

O que fazer, nessa ordem:

1. **`git fetch && git log HEAD..origin/main`.** Quase sempre o trabalho do
   outro worktree já foi mergeado. Traga a `main` para a sua branch — as
   tabelas "estranhas" viram legitimamente suas e o gate fica verde sozinho.
2. Se ainda não foi mergeado: pule o hook no push (`--no-verify`), **desde que**
   o gate completo tenha passado antes do drift aparecer, e **diga isso** na
   resposta. Quem cobre é o CI, que roda contra um banco limpo.
3. **Nunca resete o banco para "limpar".** `db reset` apaga as migrations do
   outro worktree junto: você desbloqueia o seu push destruindo o ambiente de
   quem está trabalhando ao lado.

Vale para os DADOS também: linha de teste que você inserir para provar alguma
coisa aparece na tela da outra sessão. Insira, prove e **apague o que você
criou** — não com um reset.

## Limpeza no fim

Ao terminar o trabalho num worktree: remova worktrees órfãos
(`git worktree remove`), delete branches já mergeadas, rode `git fetch --prune`,
e volte pra `main` com `git pull`.
