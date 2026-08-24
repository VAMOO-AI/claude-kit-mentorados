---
name: memoria-projeto
description: >-
  Põe a memória do projeto dentro do repositório em vez de deixar presa na sua
  máquina — cria `.context/memoria/`, liga o diretório do Claude Code lá, e
  recusa a adoção se achar credencial escrita na memória. Use ao começar a
  trabalhar num projeto e em "/memoria-projeto", "liga a memória deste projeto",
  "o Claude esquece o que aprendeu", "troquei de computador e perdi o contexto",
  "meu colega não vê o que decidimos aqui", "essa memória está no repo?".
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
git rev-parse --show-toplevel
ls .context/memoria/*.md 2>/dev/null | wc -l
readlink ~/.claude/projects/"$(pwd | tr '/ ' '--')"/memory
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

Vazio: em dia. Com linhas, antes de fechar a sessão:

```bash
git add .context/memoria && git commit -m "docs(memoria): o que aprendi nesta sessão"
```

Se você trabalha com branch e PR, isso entra no PR como qualquer mudança. Não
deixe pra depois: sincronizar o repo antes de commitar é como se perde memória.

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
| Projeto com espaço no nome era ignorado | O diretório do Claude Code troca **barra e espaço** por `-`; conta trocar só a barra gera um caminho que não existe |
| `--adotar` recusou e o projeto é meu mesmo | O gate não pergunta de quem é o repo. Limpar o arquivo é mais barato que trocar credencial depois |
| Memória sumiu depois de dar `git pull` | Não estava commitada. Commite antes de sincronizar — sempre |
