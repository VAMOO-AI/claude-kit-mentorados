# ⚡ Programação avançada com o Claude

Pra quem já programa e quer extrair o máximo. Isto é a "camada de cima" do guia
básico — assume que você já entende git, testes e linha de comando.

A ideia central: **o Claude rende muito mais quando você lhe dá método e estrutura**,
não só pedidos soltos. Abaixo, os mecanismos que mais elevam o nível.

---

## 1. Skills: deixe o Claude seguir métodos, não improvisar

Skills são "manuais" que o Claude carrega sozinho quando a tarefa casa. O kit já traz
skills de processo que trocam "improviso" por método:

- **`grilling`** — interroga um plano grande até fechar antes de codar.
- **`verificacao`** — como testar de verdade antes de dizer "pronto" (ramos, UI, runners, erro de prod).
- **`orquestracao`** — divide trabalho independente entre vários subagentes em paralelo.
- **`worktrees`** — isola trabalho em git worktrees quando há vários terminais no mesmo projeto.
- **`find-docs`** / **`ship`** / **`secscan`** — busca doc oficial, release com gates, scan de segurança.

Você pode invocar de propósito: *"usa a skill verificacao antes de fechar"*.

> **Crie as suas.** Quando você se pega repetindo a mesma instrução em toda sessão,
> isso é uma skill esperando pra nascer. Peça: *"cria uma skill que faça X"*. Skills
> ficam em `~/.claude/skills/<nome>/SKILL.md` (global) ou `.claude/skills/` (do projeto).

---

## 2. Sub-agentes e paralelismo

Pra tarefas independentes (ex.: revisar 8 arquivos, renomear em vários módulos), o Claude
pode disparar **sub-agentes em paralelo**. Eles trabalham isolados e reportam de volta.

Regras (estão no seu `~/.claude/agents.md`):
- Sub-agentes são **read-only por padrão** (exploração). Edit/Write fica na conversa principal.
- Para writes paralelos, cada agente recebe um **contrato de escopo** (arquivos que pode tocar).
- Eles não podem dizer "passou" sem rodar e colar o output.

Quando usar: *"investiga esses 5 módulos em paralelo e me traz um resumo de cada"*.
Quando NÃO usar: tarefa pequena ou com dependência sequencial — o overhead não compensa.

---

## 3. Git worktrees: trabalho isolado sem trocar de branch

Worktree = uma cópia do repo em outra pasta, numa branch separada, sem mexer no seu
diretório atual. Ótimo pra tocar uma feature arriscada sem poluir o working tree.

Peça: *"cria um worktree pra essa feature"* (a skill `worktrees` cuida).
Ao terminar: faça merge/PR e limpe a worktree e a branch.

---

## 4. Hooks: automação que dispara sozinha

Hooks rodam comandos automaticamente em eventos do Claude Code. O `settings.json` do kit
já traz um: depois de toda edição, roda `eslint --fix` + `tsc --noEmit` no arquivo.

Outros úteis pra você adicionar:
- Rodar testes do módulo afetado depois de salvar.
- `gitleaks` antes de commitar (pega secret vazando).
- Notificação custom quando o Claude termina.

Configure via a skill `update-config` ou editando `~/.claude/settings.json` (chave `hooks`).

---

## 5. /ship: release com portões de verificação

O kit traz a skill **`ship`**. Diga *"/ship"* ou *"manda pra prod"* e o Claude roda:
pré-voo (`pwd`/branch) → typecheck/lint/test (gates duros, output colado) → conventional
commit → push → PR via `gh`. Deploy é passo adaptável ao seu stack.

O ponto: ele **não deixa você dizer "passou" sem provar**. Edite o passo de deploy da
skill com o comando do seu projeto.

---

## 6. dotcontext para projetos sérios

Além do `init the context`, em projetos grandes:
- Documente decisões de arquitetura em `.context/docs/` — vira contexto permanente.
- Mantenha um `AGENTS.md` na raiz como ponto de entrada (Claude/Codex/Cursor leem).
- `.context/` é fonte única — não duplique contexto espalhado pelo repo.

---

## 7. CI: trave a qualidade no PR

Use o template em [`templates/ci.yml`](../templates/ci.yml): roda typecheck + lint + test
em todo PR. Branch só entra na `main` com o verde. É a versão "time" do verify-don't-claim.

---

## 8. MCPs: dê novas mãos ao Claude

MCPs conectam o Claude a serviços (banco, browser, GitHub). O kit já instala o
**dotcontext**. Veja [`docs/mcps-recomendados.md`](mcps-recomendados.md) pra adicionar
Playwright (testar UI de verdade), GitHub (PRs/issues) e outros — **sob demanda**, não
todos de uma vez.

---

## Mentalidade do usuário avançado

- **Estrutura > pedido solto.** Skill, worktree, contrato de escopo — o método multiplica.
- **Gates não-negociáveis.** Nada de "passou" sem output. Nada de deploy sem `pwd` certo.
- **Automatize o repetitivo.** Repetiu a instrução 3x? Vira hook ou skill.
- **Causa raiz, sempre.** 2 fixes de superfície falharam? Pare e vá vertical.
- **O Claude é alavanca, não piloto automático.** Você ainda revisa o diff.
