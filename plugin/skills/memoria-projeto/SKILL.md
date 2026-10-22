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

O Claude Code guarda o que aprende sobre um projeto em
`~/.claude/projects/<slug>/memory` — um lugar na **sua máquina**. Isso significa
três coisas que só doem depois:

- Trocou de computador (ou formatou): a memória não vai junto.
- Trabalha com mais alguém: a pessoa abre o repo e não sabe por que a decisão
  foi tomada daquele jeito.
- Usa outra ferramenta (Codex, Cursor, Grok): ela lê o `.context/` do repo e não
  acha nada, porque o que o Claude aprendeu nunca chegou lá.

O conserto é mover a memória pra dentro do repositório e ligar o diretório do
Claude Code nela. A partir daí tudo que ele registrar nasce versionado.

## 1. Onde estamos

```bash
git rev-parse --show-toplevel                       # o repo
ls .context/memoria/*.md 2>/dev/null | wc -l        # fatos versionados
# O nome do diretório do Claude Code é o caminho com TODO caractere fora de
# [a-zA-Z0-9] virando '-' — não só a barra. E `pwd` termina com uma quebra de
# linha, que vira mais um '-' no fim: o slug com traço sobrando não existe, o
# readlink sai vazio e a resposta abaixo mente "não adotado" num projeto ligado.
# Por isso `printf '%s' "$PWD"` (sem newline) e o `sed` cortando o '-' final.
readlink ~/.claude/projects/"$(printf '%s' "$PWD" | LC_ALL=C tr -c 'a-zA-Z0-9' '-' | sed 's/-$//')"/memory
```

| O que você vê | Estado | Vá para |
|---|---|---|
| o `readlink` devolve o caminho de `.context/memoria` | ligado | §4 |
| a pasta existe, `readlink` vazio | versionado, esta máquina não | §3 |
| nada disso | não adotado | §2 |

## 2. Adotar (primeira vez neste projeto)

Sempre dry-run antes, e mostre a saída:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/memoria-link.sh" --adotar --dry-run --repo .
bash "${CLAUDE_PLUGIN_ROOT}/scripts/memoria-link.sh" --adotar --repo .
```

Cria `.context/memoria/` com um README de como escrever, traz o que estava preso
na máquina e liga o symlink.

**Se recusar por credencial, não contorne.** O gate roda antes de criar a pasta
porque versionar memória é *distribuir* memória: adotar por cima de uma API key
escrita ali dentro commita essa chave no repositório, e não tem desfazer — quem
clonar depois leva junto, e o histórico guarda mesmo que você apague no commit
seguinte.

O conserto é trocar o valor pelo lugar onde ele vive, no arquivo que o script
apontou:

```markdown
- Conexão do banco: `DATABASE_URL` no `.env.local`
```

Não cole o valor no chat nem na mensagem de commit. Se a credencial é válida e
já circulou em arquivo, trate como exposta: troque ela antes de seguir.

## 3. Ligar (o repo já tem a pasta, esta máquina não)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/memoria-link.sh" --repo .
```

Se houver memória local, ela vira backup datado e é reconciliada: o que o repo
não tem é copiado, e o que existe dos dois lados com conteúdo diferente é
**reportado, nunca sobrescrito**. Leia os avisos — cada um é um fato que precisa
de uma decisão sua.

## 4. Publicar o que a sessão escreveu

Ligar **não** publica. O symlink põe no seu clone; o commit põe no repositório.

```bash
git status --short .context/memoria/
```

Vazio: em dia. Com linhas, antes de fechar a sessão, commite **numa branch** — o
hook do kit bloqueia commit na `main`. Se a sessão tem branch de tarefa que vai
virar PR, é nela; senão, uma só de memória (`docs/memoria-<AAAA-MM-DD>`), num
worktree se outra sessão usa este clone (skill `worktrees`), com PR:

```bash
git add .context/memoria && git commit -m "docs(memoria): o que aprendi nesta sessão"
```

Não deixe pra depois: memória que não foi commitada fica presa nesta máquina — e,
num worktree, vai embora com ele.

Antes de abrir um PR **só de memória**, veja se já existe um aberto mexendo na
mesma pasta:

```bash
gh pr list --state open --limit 100 --json number,headRefName,url,files --jq '.[]
  | select(any(.files[]?; .path | startswith(".context/memoria/")))
  | (if all(.files[]?; .path | startswith(".context/memoria/")) then "memoria" else "misto" end) as $t
  | "#\(.number) \($t) \(.headRefName) \(.url)"'
```

Linha `memoria` (PR só de memória): não abra outro. Commite na branch desse PR (ou
espere o merge e publique depois) — dois PRs com a mesma memória conflitam entre
si, e quem mergeia o segundo resolve conflito em arquivo que ninguém lembra de ter
escrito. Linha `misto` é PR de feature que levou memória junto: **não commite
nele** (a branch é de outra frente, talvez de outra pessoa); publique a sua e, se
mexer nos mesmos arquivos, cite o PR na descrição.

## 5. Índice em dois níveis (quando o `MEMORY.md` passa de 8 KB)

O `MEMORY.md` entra no contexto de **toda** request. Sem teto ele cresce com o
projeto — 57 KB num CRM com 303 memórias — e cada linha custa em cada prompt.
O script redistribui o índice: `MEMORY.md` fica curto (até 8 KB, por prioridade
de tipo: feedback > user > reference > project) e a cauda vai para
`MEMORY-completo.md`, no mesmo formato. Idempotente; sem `--apply` é dry-run.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/memoria-indice.sh" .context/memoria
bash "${CLAUDE_PLUGIN_ROOT}/scripts/memoria-indice.sh" .context/memoria --apply
```

Duas regras que vêm junto: memória nova entra **sempre** no `MEMORY.md` (o script
redistribui na rodada seguinte), e antes de concluir que uma memória não existe,
`grep` no `MEMORY-completo.md` — só o curto veio no contexto. Linha do índice que
não aponta para arquivo (cabeçalho de seção, prosa) sai com aviso: converta em
arquivo de memória antes de aplicar, senão perde o conteúdo.

## Vale salvar?

A pergunta: uma sessão daqui a um mês, sem esta conversa, ficaria surpresa ao
descobrir isso sozinha e grata por já saber? Se ela leria no código, no `git log`,
no `AGENTS.md` ou na documentação do projeto (`.context/docs/`), não salve: memória que repete o
projeto só ocupa o limite do índice. Também fica de fora o que só vale hoje (prazo,
o estado de um PR aberto, quem vai revisar amanhã).

| Não salve | Salve |
|---|---|
| "O projeto usa Next.js e Supabase" (está no `package.json`) | "O e-mail de boas-vindas sai pela função `enviar-boas-vindas`, não pelo Auth do Supabase: o template do Auth não aceita o logo do cliente" |
| "Corrigi o bug do carrinho hoje" (é o commit) | "O total do carrinho diverge do relatório com cupom percentual: o relatório arredonda por item, o carrinho no total. Verificado em 12/10/2026" |
| "Rodar `npm test` antes do PR" (já está no `AGENTS.md`) | "O teste de data passa no meu Mac e falha no CI: ele assume o fuso UTC" |
| "Revisar isso amanhã com o sócio" (contexto do momento) | "O cliente aprova layout pelo WhatsApp, não pelo link de preview: o preview pede login e não abre no celular dele" |

## Escrever um fato que vale a pena

1. **Registre o porquê, não o quê.** O *quê* já está no `git log`.
2. **Separe verificado de acreditado**, com essas palavras. Inferência escrita
   como fato vira premissa falsa pra todo mundo que ler depois — inclusive você.
3. **Data absoluta.** "Semana passada" não sobrevive a três sessões.
4. **Fato que se provou errado se apaga.** Memória errada é pior que memória
   faltando: é lida com confiança e ninguém re-checa.
5. **Nunca escreva credencial.** Escreva onde o valor vive, nunca o valor.

## Armadilhas

| Sintoma | Causa real |
|---|---|
| "Liguei, mas continua só na minha máquina" | Ligar não commita. O symlink põe no clone, o commit põe no repositório (§4) |
| Máquina nova sem nada da memória | O symlink é por máquina. Rode a §3 em cada computador que você usar |
| Slug calculado à mão não acha a memória (erra todo worktree) | O Claude Code troca **todo caractere fora de `[a-zA-Z0-9]`** por `-` — barra, espaço, ponto, `+`; caminho de worktree tem `.claude`. Use o comando da §1 |
| Sessão em worktree "não achou" o que registrou | A memória automática é por repositório e compartilhada entre os worktrees ([doc](https://code.claude.com/docs/en/memory.md#auto-memory)): a sessão do worktree grava pelo link do clone principal, no `.context/memoria/` dele. Procure lá (`git -C <clone-principal> status --short .context/memoria/`) e publique pela §4 |
| `--adotar` recusou e o projeto é meu mesmo | O gate não pergunta de quem é o repo. Limpar o arquivo é mais barato que trocar credencial depois |
| Memória sumiu depois de dar `git pull` | Não estava commitada. Commite antes de sincronizar — sempre |
| Dois ou três PRs abertos com a mesma memória | Cada sessão publicou sem olhar se já havia PR de memória aberto. Confira com o `gh pr list` da §4 antes de abrir outro |
