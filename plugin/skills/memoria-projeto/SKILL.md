---
name: memoria-projeto
description: >-
  Põe a memória do projeto dentro do repositório em vez de deixar presa na sua
  máquina — cria .context/memoria/, liga o diretório do Claude Code lá, e recusa
  a adoção se achar credencial escrita na memória. Use ao começar a trabalhar
  num projeto e em "/memoria-projeto", "liga a memória deste projeto", "o Claude
  esquece o que aprendeu", "troquei de computador e perdi o contexto", "essa
  memória está no repo?".
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/memoria-link.sh" *)'
  - 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/memoria-link.sh *)'
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/memoria-indice.sh" *)'
  - 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/memoria-indice.sh *)'
---

# Memória do projeto dentro do repositório

A memória do Claude Code mora na **sua máquina** (`~/.claude/projects/<slug>/memory`): não
vai junto para outro computador, e quem clona o repo (pessoa, Codex, Grok) não a vê. Aqui ela
passa a ser versionada em `.context/memoria/`. O formato de um fato está no
`.context/memoria/README.md` que a adoção escreve; o que vale salvar, em
`references/vale-salvar.md`.

## 1. Onde estamos

```bash
ls .context/memoria/*.md 2>/dev/null | wc -l        # fatos versionados
# slug = caminho com TODO caractere fora de [a-zA-Z0-9] virando '-'; sem o `printf '%s'`
# (o `pwd` traz newline) e o `sed`, o readlink sai vazio num projeto ligado
readlink ~/.claude/projects/"$(printf '%s' "$PWD" | LC_ALL=C tr -c 'a-zA-Z0-9' '-' | sed 's/-$//')"/memory
```

`readlink` devolve `.context/memoria`: ligado, vá à §4. Pasta existe e `readlink` vazio: §3.
Nada disso: §2.

## 2. Adotar (primeira vez neste projeto)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/memoria-link.sh" --adotar --dry-run --repo .   # mostre a saída
bash "${CLAUDE_PLUGIN_ROOT}/scripts/memoria-link.sh" --adotar --repo .
```

**Se recusar por credencial, não contorne.** Versionar memória é *distribuir* memória: o
histórico guarda a chave mesmo que você apague no commit seguinte, e o gate não pergunta de
quem é o repo. Troque o valor pelo lugar onde ele vive (`` `DATABASE_URL` no `.env.local` ``),
no arquivo que o script apontou, e rode o `--adotar` de novo. Não cole o valor no chat nem no commit. Credencial válida que já
circulou em arquivo está exposta: troque ela antes de seguir.

## 3. Ligar (o repo já tem a pasta, esta máquina não)

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/memoria-link.sh" --repo .`, em cada computador (o
symlink é por máquina). O que existe dos dois lados com conteúdo diferente é **reportado,
nunca sobrescrito**: cada aviso pede uma decisão sua.

## 4. Publicar o que a sessão escreveu

Ligar **não** publica. `git status --short .context/memoria/` com linhas: commite antes de
fechar a sessão, **numa branch** (o hook bloqueia a `main`) — a da tarefa, se vai virar PR;
senão `docs/memoria-<AAAA-MM-DD>`, num worktree se outra sessão usa este clone. Memória não
commitada fica nesta máquina e, num worktree, vai embora com ele. Antes de abrir PR **só de
memória**, procure um aberto na mesma pasta:

```bash
gh pr list --state open --limit 100 --json number,headRefName,url,files --jq '.[]
  | select(any(.files[]?; .path | startswith(".context/memoria/")))
  | (if all(.files[]?; .path | startswith(".context/memoria/")) then "memoria" else "misto" end) as $t
  | "#\(.number) \($t) \(.headRefName) \(.url)"'
```

Linha `memoria`: não abra outro, commite na branch dele (dois PRs da mesma memória
conflitam). Linha `misto` é PR de feature: **não commite nele**; publique a sua e cite o PR.

`MEMORY.md` acima de 8 KB: `references/indice.md`. Worktree que não grava e outros
sintomas: `references/armadilhas.md`.
