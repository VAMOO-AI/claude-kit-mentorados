---
name: setup
description: >-
  Termina de instalar o Claude Starter Kit depois do /plugin install — escreve o
  CLAUDE.md global, liga a barra de status e mescla as preferências, que são as
  partes que um plugin não consegue instalar sozinho. Depois ajuda a preencher o
  CLAUDE.md com os dados de quem está instalando. Use em "/kit-vamoo:setup",
  "terminar de instalar o kit", "configurar o kit", "instalei o plugin e agora?",
  "a barra de status não apareceu", "o kit não está pegando as regras".
---

# Terminar a instalação do kit

O `/plugin install` entregou as skills, os comandos, os guard-rails de git e o
MCP dotcontext. Falta o resto — e falta por um motivo técnico, não por descuido:
o `settings.json` de um plugin só aceita as chaves `agent` e
`subagentStatusLine`. **CLAUDE.md global, barra de status, idioma e lista de
permissões não podem vir num plugin.** É isto que esta skill instala.

## 1. Rode o setup

Sempre com `--dry-run` primeiro, e mostre a saída para a pessoa:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/kit-setup.sh" --dry-run
```

Confirmado, rode de verdade:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/kit-setup.sh"
```

O script faz backup de tudo que toca em `~/.claude/backup-kit-<data>/` antes de
mexer (ficam os 3 mais recentes). Se a pessoa tem algo próprio em `~/.claude`
que a limpeza da instalação antiga poderia levar — uma skill do kit que ela
editou, um script com nome igual —, liste em `~/.claude/.keep-local` (um
caminho por linha, relativo a `~/.claude`, glob simples) **antes** de rodar sem
`--dry-run`. Duas decisões já vêm tomadas nele, e vale dizer em voz alta:

- **`CLAUDE.md` que já existir não é sobrescrito.** O modelo do kit fica em
  `~/.claude/CLAUDE.kit.md` pra comparar. Só troca com `--force`, e só se a
  pessoa pedir.
- **`settings.json` é mesclado, não substituído.** As chaves de quem instala
  ganham; a lista `allow` vira a união das duas. Ninguém perde permissão ou
  variável de ambiente que já tinha configurado.

## 2. Preencha o CLAUDE.md com os dados da pessoa

O template vem com campos `<entre-colchetes>`. Um CLAUDE.md com os colchetes
ainda lá é pior que nenhum: o modelo lê `<sua stack>` como instrução literal.

Leia `~/.claude/CLAUDE.md`, colete o que falta **numa pergunta só** e edite o
arquivo:

- Como a pessoa quer ser chamada
- A stack do dia a dia (ex.: React + Supabase, Python + FastAPI, WordPress)
- Nível: quer explicação didática a cada passo, ou resposta direta?
- Se já usa GitHub com mais gente ou trabalha sozinha

Não invente resposta: se ela não souber a stack, deixe genérico e diga que dá
pra ajustar depois — o arquivo é dela.

## 3. Confira que pegou

```bash
claude plugin list | grep -A2 kit-vamoo     # deve aparecer enabled
ls ~/.claude/CLAUDE.md ~/.claude/statusline-command.sh
```

**Diga pra pessoa reiniciar o Claude Code** — e diga que é pra tudo, não só pra
barra. A sessão que está aberta começou com o `settings.json` antigo: idioma,
lista de permissões e barra de status só valem no próximo start. Sem esse aviso
a pessoa conclui que o setup não pegou e vai debugar um problema que não existe.

Depois de reiniciar, a barra mostra diretório, branch, alterações não salvas,
à frente/atrás do remoto, `gh✓`, PR aberto e o contexto em número absoluto.

## Se algo não estiver funcionando

| Sintoma | Causa | Conserto |
|---|---|---|
| Barra não aparece | Claude Code não foi reiniciado, ou falta `node` | Reiniciar; `node --version` |
| `/kit-vamoo:` não completa nenhuma skill | Plugin instalado mas não recarregado | `/reload-plugins` |
| Hook não bloqueia commit na main | Sem `node` — os hooks falham em aberto de propósito | Instalar o Node.js LTS |
| Skill aparece duas vezes | Instalação antiga pelo `install.sh` ainda em `~/.claude/skills/` | O `kit-setup.sh` remove pelo manifesto; rode-o de novo |
| `gh✗` na barra | GitHub CLI ausente ou deslogado | `gh auth login` (opcional — só perde a visão de PR) |
