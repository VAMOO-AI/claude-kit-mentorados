# 🚀 Claude Starter Kit

Configuração base do Claude Code que eu uso com meus mentorados. Em ~2 minutos você
fica com o mesmo "esqueleto" de regras, sub-agentes, atalhos e memória de projeto
que potencializa o uso do Claude no dia a dia.

> **Pré-requisito:** ter o [Claude Code](https://claude.com/claude-code) instalado e
> logado. Teste no terminal: `claude --version`. Se aparecer um número, você está pronto.

---

## O que vem no kit

| Arquivo | Vai pra onde | Pra que serve |
|---|---|---|
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | Suas **regras globais** — valem em todo projeto. Como o Claude deve agir, verificar, commitar, proteger escopo. |
| `AGENTS.md` | `~/.claude/agents.md` | Regras dos **sub-agentes** (quando o Claude dispara ajudantes em paralelo). |
| `settings.json` | `~/.claude/settings.json` | **Atalhos e automações**: idioma PT, lint/typecheck automático a cada edição, som ao terminar. |
| `statusline-command.sh` | `~/.claude/statusline-command.sh` | Barra de status: diretório atual, branch git e quanto do contexto já foi usado. |
| `skills/find-docs/` | `~/.claude/skills/` | Skill que busca **documentação oficial e atualizada** antes de escrever código. Mata API inventada/desatualizada. |
| `commands/` | `~/.claude/commands/` | Atalhos: `/revisar` (revisa seu diff) e `/explicar` (explica um código de forma didática). |
| `docs/como-trabalhar-com-claude.md` | — | **Guia de leitura** — como pedir bem, verificar e não se queimar. Comece por aqui. |
| `templates/` | — | Modelos pra copiar em projetos novos: `CLAUDE.md` de projeto, `.env.example`, `.gitignore`. |
| `install.sh` | — | O instalador que coloca tudo no lugar e instala o dot-context + ctx7. |

Além disso o kit instala duas coisas que multiplicam o Claude:

- **superpowers** — pacote de "skills" (TDD, debugging sistemático, brainstorming). O Claude passa a seguir métodos comprovados em vez de improvisar.
- **dot-context** (`ai-context`) — dá ao Claude uma **memória do projeto**. Ele guarda documentação e contexto em `.context/` dentro do seu projeto e relê toda sessão.

> 📖 **Antes de tudo, leia [`docs/como-trabalhar-com-claude.md`](docs/como-trabalhar-com-claude.md).** É o que mais vai te ajudar — config sem método não adianta.

---

## Instalação (passo a passo)

### 1. Baixe o kit
Se eu te mandei como `.zip`, descompacte. Se virou repositório no GitHub:
```bash
git clone <URL-DO-REPO> claude-starter-kit
cd claude-starter-kit
```

### 2. Rode o instalador
```bash
bash install.sh
```
Ele copia os arquivos pro seu `~/.claude` (fazendo **backup** de qualquer coisa que
você já tivesse) e instala o MCP dot-context.

### 3. Instale o superpowers (dentro do Claude Code)
Isso é um passo manual — abra o Claude Code e rode estes dois comandos:
```
/plugin marketplace add anthropics/claude-plugins-official
/plugin install superpowers@claude-plugins-official
```

### 4. Preencha o CLAUDE.md com os SEUS dados
Abra `~/.claude/CLAUDE.md` e troque os trechos `<entre-colchetes>` (seu nome, sua
stack, como você quer ser respondido). Apague o que não usar. Esse arquivo é seu —
adapte à vontade.

### 5. Confira se deu certo
```bash
claude mcp list        # deve aparecer "ai-context ... ✓ Connected"
```
Abra o Claude Code e rode `/help` ou comece a digitar `/` — você deve ver skills do
superpowers na lista. Pronto. 🎉

---

## Como usar no dia a dia

- **Memória de projeto:** num projeto novo, na primeira conversa, peça
  **"init the context"**. O Claude cria a pasta `.context/` e passa a lembrar do projeto.
- **Modo aprendizado:** diga **"explica"** ou **"modo aula"** e o Claude passa a ensinar
  o porquê de cada coisa, passo a passo (definido no seu CLAUDE.md).
- **Skills:** quando uma tarefa casa com uma skill (escrever testes, debugar um erro),
  o Claude usa o método certo sozinho. Você também pode pedir, ex.:
  "usa test-driven-development".

---

## 🌱 Iniciante vs ⚡ Avançado

O kit serve aos dois níveis. Comece pelo seu e cresça.

**Iniciante — leia primeiro:**
1. [`docs/como-trabalhar-com-claude.md`](docs/como-trabalhar-com-claude.md) — o método.
2. Use `/explicar` e `/revisar`, modo "explica", e a skill `find-docs`.

**Avançado — quando já estiver confortável:**
1. [`docs/programacao-avancada-com-claude.md`](docs/programacao-avancada-com-claude.md) — sub-agentes paralelos, worktrees, hooks, criar suas próprias skills.
2. Skill **`/ship`** — pipeline de release com gates (typecheck/lint/test → commit → push → PR). Edite o passo de deploy com o comando do seu stack.
3. [`templates/ci.yml`](templates/ci.yml) — CI no GitHub Actions pra travar qualidade no PR.
4. [`docs/mcps-recomendados.md`](docs/mcps-recomendados.md) — Playwright, GitHub e cia., **sob demanda**.
5. [`templates/CLAUDE-projeto.md.exemplo`](templates/CLAUDE-projeto.md.exemplo) — um `CLAUDE.md` por projeto.

---

## Perguntas comuns

**Já tinha um CLAUDE.md, vou perder?**
Não. O instalador salva o seu antigo como `CLAUDE.md.bak-<data>` antes de copiar.
O `settings.json`, se já existir, **não** é sobrescrito — o modelo do kit fica em
`settings.kit.json` pra você comparar e mesclar.

**Funciona no Windows?**
O kit foi pensado pra macOS/Linux. No Windows, use o WSL (Ubuntu) e rode os mesmos
comandos. O som de "terminou" no `settings.json` é específico de Mac — pode remover
a parte do `afplay` sem problema.

**Posso desinstalar?**
Sim. Restaure seus backups (`*.bak-<data>`) e rode
`claude mcp remove ai-context`. Pra tirar o plugin: `/plugin uninstall superpowers`.

---

Dúvida? Me chama. Bom proveito! 🤖
