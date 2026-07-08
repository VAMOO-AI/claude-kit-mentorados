# 🚀 Claude Starter Kit

[![CI](https://github.com/VAMOO-AI/claude-kit-mentorados/actions/workflows/ci.yml/badge.svg)](https://github.com/VAMOO-AI/claude-kit-mentorados/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/VAMOO-AI/claude-kit-mentorados)](https://github.com/VAMOO-AI/claude-kit-mentorados/releases)

A configuração de Claude Code que eu uso em projetos reais — regras, skills,
automações e método — empacotada pra você instalar em **~2 minutos**.

Sem o kit, o Claude "puro" tende a três vícios que queimam iniciante: diz que
terminou **sem testar**, mexe em arquivo que **você não pediu** e **inventa API**
que não existe. O kit instala as regras e skills que corrigem esses
comportamentos — as mesmas que eu uso com clientes em produção, sanitizadas.
E cada regra aqui existe porque preveniu ou corrigiu um bug real.

> **Pré-requisito:** ter o [Claude Code](https://claude.com/claude-code) instalado e
> logado. Teste no terminal: `claude --version`. Se aparecer um número, você está pronto.

---

## O que vem no kit

| Arquivo | Vai pra onde | Pra que serve |
|---|---|---|
| `templates/CLAUDE-global.md` | `~/.claude/CLAUDE.md` | Suas **regras globais** — valem em todo projeto. Como o Claude deve agir, verificar, commitar, proteger escopo. (Fica em `templates/` pra não ser carregado como config de quem abre uma sessão dentro do clone do kit.) |
| `AGENTS.md` | `~/.claude/agents.md` | Regras dos **sub-agentes** (quando o Claude dispara ajudantes em paralelo). |
| `settings.json` | `~/.claude/settings.json` | **Atalhos e automações**: idioma PT, lint/typecheck automático a cada edição, som ao terminar. É uma config **produtiva** (libera `npm run`, `npm test`, git read-only sem perguntar) — se preferir aprovar tudo, apague entradas da lista `allow`. |
| `statusline-command.sh` + `scripts/statusline.js` | `~/.claude/` | **Barra de status** (sempre visível): diretório, branch, alterações não salvas (`✗`), à frente/atrás do remoto (`↑`/`↓`), **GitHub conectado** (`gh✓`/`gh✗`), **PR aberto** (`PR#`) e uso do contexto. Resolve a cegueira do Desktop, que não mostra nada disso. |
| `hooks/` | `~/.claude/hooks/` | **Guard-rails de git**: bloqueia commit na `main`, pede confirmação em `rm -rf`/`DROP`/`push --force`, e roda lint/typecheck a cada edição. Leem tudo via **node** (não precisam de `jq`). |
| `scripts/` | `~/.claude/scripts/` | Avisos no início da sessão (**branch atrás do remoto**, **worktree já mergeado**), limpeza de worktrees (`worktree-gc.sh`) e a barra de status. |
| `skills/` | `~/.claude/skills/` | **10 skills** (busca de docs, revisão de segurança, deploy, n8n/WhatsApp, VPS, CRM e mais). Ver a seção [Skills incluídas](#skills-incluídas) abaixo. |
| `commands/` | `~/.claude/commands/` | Atalhos: `/revisar` (revisa seu diff) e `/explicar` (explica um código de forma didática). |
| `docs/como-trabalhar-com-claude.md` | — | **Guia de leitura** — como pedir bem, verificar e não se queimar. Comece por aqui. |
| `templates/` | — | Modelos pra copiar em projetos novos: `CLAUDE.md` de projeto, `.env.example`, `.gitignore`, CI, e **`playwright/`** (testes e2e). |
| `install.sh` | — | O instalador que coloca tudo no lugar e instala o dotcontext + ctx7. |

Além disso o kit instala duas coisas que multiplicam o Claude:

- **superpowers** — pacote de "skills" (TDD, debugging sistemático, brainstorming). O Claude passa a seguir métodos comprovados em vez de improvisar.
- **dotcontext** (`dotcontext`) — dá ao Claude uma **memória do projeto**. Ele guarda documentação e contexto em `.context/` dentro do seu projeto e relê toda sessão (um hook injeta o índice no início de cada sessão = menos alucinação).

> 📖 **Antes de tudo, leia [`docs/como-trabalhar-com-claude.md`](docs/como-trabalhar-com-claude.md).** É o que mais vai te ajudar — config sem método não adianta.

---

## Skills incluídas

O instalador copia todas as skills abaixo. Algumas funcionam de cara; outras só
fazem efeito depois que você liga um pré-requisito (uma API, um MCP, uma conta).
Sem o pré-requisito a skill simplesmente **não dispara** — não quebra nada, só
não faz nada.

### ✅ Prontas pra usar (sem setup extra)

| Skill | Pra que serve | Pré-requisito |
|---|---|---|
| **find-docs** | Busca documentação oficial e atualizada antes de escrever código. Mata API inventada. | nenhum (o instalador já põe o ctx7) |
| **secscan** | Revisão de segurança read-only: RLS, secrets, deps vulneráveis. "roda um secscan". Ver `docs/seguranca.md`. | nenhum |
| **ship** | Pipeline de release com gates (typecheck/lint/test → commit → push → PR). | editar o passo de deploy pro seu stack |
| **pipedrive-automation** | Modelos de automação de CRM Pipedrive (deals, pipeline, relatórios). | conta/API Pipedrive pra rodar de fato |

### ⚙️ Exigem ligar um pré-requisito

| Skill | Pra que serve | Pré-requisito |
|---|---|---|
| **n8n-workflow-agent** | Construir/debugar workflows n8n com agentes de WhatsApp (UAZAPI, Chatwoot, etc.). | instância n8n + API key, instância UAZAPI |
| **notebooklm** | Consultar seus notebooks do Google NotebookLM com respostas citadas. | login Google (auth via browser, 1ª vez) |
| **notebooklm-project-ops** | Criar/sincronizar um notebook NotebookLM a partir das docs do projeto. | CLI `nlm` ou MCP notebooklm + docs no projeto |
| **agent-reporting** | Registra progresso das tarefas no TickTick automaticamente. | TickTick MCP configurado + token |
| **vps-hardening-clientes** | Runbook anti-queda de VPS Docker Swarm + Traefik (bug Docker 27→29). | é referência/receita — aplica numa VPS com essa stack |
| **ambientes-clientes** | Runbook de setup de ambiente de cliente (GitHub + Vercel + Supabase) sem custo de seat. | é referência — você segue o passo a passo |

> As skills de WhatsApp/VPS/CRM vêm de casos reais de produção, **anonimizados**.
> Os exemplos usam placeholders (`<agente>`, `Cliente A`, telefones fake) — troque
> pelos seus dados ao aplicar.
>
> A skill **notebooklm** é *vendorizada* (copiada de um projeto de terceiro, em
> inglês — ver `skills/notebooklm/ATTRIBUTION.md`). Não edite os arquivos dela à
> mão: pra atualizar, re-vendorize do upstream.

---

## Instalação (passo a passo)

### 1. Baixe o kit
```bash
git clone https://github.com/VAMOO-AI/claude-kit-mentorados.git claude-starter-kit
cd claude-starter-kit
```

### 2. Rode o instalador
```bash
bash install.sh
```
Ele copia os arquivos pro seu `~/.claude` e instala o MCP dotcontext. Antes de
sobrescrever qualquer coisa (CLAUDE.md, agents.md, statusline, skills, comandos),
ele salva uma cópia em **`~/.claude/backup-kit-<data>/`**. Só o `settings.json`
não é sobrescrito nunca — se você já tiver um, o modelo do kit fica em
`settings.kit.json` pra mesclar à mão.

Quer ver o que ele faria antes de rodar de verdade?
```bash
bash install.sh --dry-run
```

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
claude mcp list        # deve aparecer "dotcontext ... ✓ Connected"
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
2. [`docs/memoria-e-contexto.md`](docs/memoria-e-contexto.md) — como o Claude lembra: global vs projeto, o que vai no CLAUDE.md vs em `docs/`. (O tema que mais confunde.)
3. [`docs/seguranca.md`](docs/seguranca.md) — os 5 furos que iniciante esquece (RLS, secrets, deps) + revisão automática.
4. Use `/explicar` e `/revisar`, modo "explica", e a skill `find-docs`.

**Avançado — quando já estiver confortável:**
1. [`docs/testes-e2e-com-playwright.md`](docs/testes-e2e-com-playwright.md) — testar o caminho do usuário de verdade (template em `templates/playwright/`).
2. [`docs/programacao-avancada-com-claude.md`](docs/programacao-avancada-com-claude.md) — sub-agentes paralelos, worktrees, hooks, criar suas próprias skills.
2. Skill **`/ship`** — pipeline de release com gates (typecheck/lint/test → commit → push → PR). Edite o passo de deploy com o comando do seu stack.
3. [`templates/ci.yml`](templates/ci.yml) — CI no GitHub Actions pra travar qualidade no PR.
4. [`docs/mcps-recomendados.md`](docs/mcps-recomendados.md) — Playwright, GitHub e cia., **sob demanda**.
5. [`templates/CLAUDE-projeto.md.exemplo`](templates/CLAUDE-projeto.md.exemplo) — um `CLAUDE.md` por projeto.

---

## Perguntas comuns

**Já tinha um CLAUDE.md (ou skills, ou statusline), vou perder?**
Não. Tudo que o instalador sobrescreve ganha uma cópia em
`~/.claude/backup-kit-<data>/` antes. Skills suas que não vieram do kit ficam
intactas. O `settings.json`, se já existir, **não** é sobrescrito — o modelo do
kit fica em `settings.kit.json` pra você comparar e mesclar.

**Funciona no Windows?**
O kit foi pensado pra macOS/Linux. No Windows, use o WSL (Ubuntu) e rode os mesmos
comandos. O som de "terminou" no `settings.json` é específico de Mac — pode remover
a parte do `afplay` sem problema.

**Posso desinstalar?**
Sim. Restaure seus arquivos de `~/.claude/backup-kit-<data>/` e rode
`claude mcp remove dotcontext`. Pra tirar o plugin: `/plugin uninstall superpowers`.

---

## 🎓 Quer ir além?

O kit é a base. O que multiplica de verdade é o **método**: como pedir bem,
verificar de verdade, estruturar projeto e shipar com segurança — e isso eu
trabalho de perto na mentoria, com projetos reais.

- 📩 Me chama no Instagram: [**@ruanvamoo.ai**](https://instagram.com/ruanvamoo.ai)
- ⭐ O kit te ajudou? Deixa uma estrela no repo — é o que me diz que vale manter público.
- 🐛 Achou um problema? [Abre uma issue](https://github.com/VAMOO-AI/claude-kit-mentorados/issues) — feedback de quem está começando vale ouro aqui.

Bom proveito! 🤖
