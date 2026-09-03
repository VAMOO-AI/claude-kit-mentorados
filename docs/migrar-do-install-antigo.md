# Migrar da instalação antiga (install.sh) para o plugin

Até a **v0.7.0** (24/08/2026) o kit era instalado por um script que copiava arquivos para
dentro do seu `~/.claude`. Depois disso ele virou um **plugin do Claude Code**: instalar e
atualizar acontece dentro do próprio Claude, sem terminal.

Se você instalou antes dessa data, tem um passo a mais — e ele importa. As duas versões
usam **os mesmos nomes de skill** (`ship`, `git-sync`, `secscan`, `worktrees`…), então
instalar o plugin por cima sem limpar deixa você com **cada skill duas vezes**: a cópia
velha em `~/.claude/skills/` e a nova vinda do plugin. Fora o custo de contexto, o risco
real é o hook antigo continuar rodando — inclusive numa versão que já teve bug corrigido.

## Como saber se você é desse caso

Existe o arquivo `~/.claude/.kit-manifest`? Ele é o marcador da instalação antiga e lista
tudo que foi copiado. Se existir, este documento é para você.

## O jeito recomendado: cole o prompt

Você não precisa mexer no terminal. Abra o Claude Code em qualquer pasta e cole:

```
Preciso migrar o Claude Starter Kit da VAMOO da instalação antiga (feita por
install.sh, que copiava arquivos para ~/.claude) para o formato novo, que é um
plugin do Claude Code.

Repositório: https://github.com/VAMOO-AI/claude-kit-mentorados

Faça nesta ordem e me explique cada passo em português conforme for:

1. DIAGNÓSTICO — antes de mudar nada, me diga o que encontrou:
   - existe ~/.claude/.kit-manifest? (é o marcador da instalação antiga)
   - quantas skills existem em ~/.claude/skills/ e quais são
   - o plugin já está instalado? (cheque ~/.claude/plugins/installed_plugins.json)
   - existe ~/.claude/CLAUDE.md e ele parece customizado por mim?

2. INSTALAR O PLUGIN — rode, nesta ordem:
   /plugin marketplace add VAMOO-AI/claude-kit-mentorados
   /plugin install kit-vamoo@vamoo-ai
   /kit-vamoo:setup

   O terceiro comando é o que importa na migração: ele instala o que um plugin
   não consegue (CLAUDE.md global, barra de status, permissões) E remove as
   cópias da instalação antiga lendo o ~/.claude/.kit-manifest, fazendo backup
   em ~/.claude/backup-kit-<data>/ antes. Peça para ele rodar em --dry-run
   primeiro e me mostre a saída antes de aplicar de verdade.

3. CONFERIR — depois de aplicar, verifique e me mostre:
   - ~/.claude/skills/ ficou sem as skills duplicadas do kit
   - o ~/.claude/.kit-manifest sumiu (sinal de que a limpeza rodou)
   - o backup existe e tem o que foi removido
   - as skills do kit aparecem agora vindas do plugin

4. MEU CLAUDE.md — atenção, este passo é manual de propósito: o setup NÃO
   sobrescreve um CLAUDE.md que já existe, para não apagar o que é meu. Ele
   deixa o modelo novo em ~/.claude/CLAUDE.kit.md. Compare os dois arquivos e
   me mostre o que o modelo novo tem e o meu não — em especial regras novas de
   comportamento. Me pergunte, item por item, o que eu quero trazer. Não edite
   meu CLAUDE.md sem eu aprovar.

REGRAS:
- Não apague nada sem backup e sem me mostrar antes.
- Se algum comando falhar, pare e me explique o erro em vez de tentar
  contornar por conta própria.
- No fim, me diga em uma linha o que mudou e se preciso reiniciar o Claude Code.
```

## O que acontece por baixo

O trabalho pesado é do `/kit-vamoo:setup`. Ele percorre o `.kit-manifest`, e para cada
skill, hook, comando e script que a instalação antiga deixou: faz backup em
`~/.claude/backup-kit-<data>/` e remove. No fim apaga o próprio manifesto — é assim que
você sabe que a limpeza rodou. (Código: `plugin/scripts/kit-setup.sh`.)

Dois arquivos ficam de propósito, porque são dele e não do plugin: `statusline.js` e
`hookjson.js` em `~/.claude/scripts/`.

E fica também tudo que você listar em `~/.claude/.keep-local`. O manifesto diz o que o
instalador antigo copiou, não o que você fez com a cópia depois — quem editou uma skill
do kit, ou escreveu um script com um nome que o manifesto também tinha, perderia
trabalho seu. O arquivo é um caminho por linha, relativo a `~/.claude`; `#` comenta e
glob simples funciona:

```
# meu, não remove
skills/minha-skill
skills/meu-projeto-*
scripts/deploy-cliente.sh
```

Protege contra remoção, não contra instalação: `agents.md`, a barra de status e os
scripts do kit continuam sendo atualizados a cada setup, mesmo listados. E o setup
guarda só os 3 `backup-kit-<data>/` mais recentes — antes acumulava um por execução.

## O passo que ninguém automatiza: o seu CLAUDE.md

O setup **não sobrescreve** um `CLAUDE.md` que já existe. Isso é deliberado — se
sobrescrevesse, apagaria tudo que você escreveu sobre você e seus projetos. O modelo novo
fica em `~/.claude/CLAUDE.kit.md`, do lado, para comparação.

A consequência é fácil de esquecer: **regras novas que o kit passa a recomendar não
chegam sozinhas até você**. Elas existem no `CLAUDE.kit.md` e ficam paradas ali até
alguém comparar. É por isso que o passo 4 do prompt manda o Claude mostrar a diferença e
perguntar item por item, em vez de aplicar.

Vale repetir essa comparação depois de cada atualização grande do kit.

## Desfazer

Tudo que foi removido está em `~/.claude/backup-kit-<data>/`, com a mesma estrutura de
pastas. Para voltar, é copiar de lá. E para sair do plugin: `/plugin uninstall kit-vamoo`.
