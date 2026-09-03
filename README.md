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

O kit é um **plugin do Claude Code** (`plugin/`) mais um pequeno setup que roda
depois. A divisão não é estética: o `settings.json` de um plugin só aceita as
chaves `agent` e `subagentStatusLine`, então CLAUDE.md global, barra de status,
idioma e permissões **não cabem num plugin** — quem instala isso é o
`/kit-vamoo:setup`.

| O que | Vai pra onde | Pra que serve |
|---|---|---|
| `plugin/skills/` | plugin | **18 skills** (busca de doc, revisão de segurança, deploy, sincronia com o GitHub, memória de projeto, mais as de processo). Ver [Skills incluídas](#skills-incluídas). |
| `plugin/commands/` | plugin | `/kit-vamoo:revisar` (revisa seu diff, separando o que é mecânico do que é decisão sua), `/kit-vamoo:explicar` (explica um código de forma didática) e `/kit-vamoo:atalhos` (lista as simplificações marcadas com `// atalho:` e aponta as que não têm gatilho de revisão). |
| `plugin/hooks/` | plugin | **Guard-rails de git**: bloqueia commit na `main`, pede confirmação em `rm -rf`/`DROP`/`push --force`/`git add -A`, roda lint a cada edição, e avisa no início da sessão quando sua branch está atrás do remoto. Leem tudo via **node** (não precisam de `jq`). |
| `plugin/.mcp.json` | plugin | O **dotcontext**, que dá ao Claude uma memória do projeto em `.context/`. Vem junto com o plugin — sem `claude mcp add` à mão. |
| `plugin/templates/CLAUDE-global.md` | `~/.claude/CLAUDE.md` | Suas **regras globais** — valem em todo projeto. Como o Claude deve agir, verificar, commitar, proteger escopo. |
| `plugin/templates/agents.md` | `~/.claude/agents.md` | Regras dos **sub-agentes** (quando o Claude dispara ajudantes em paralelo). |
| `plugin/templates/settings.json` | `~/.claude/settings.json` | **Preferências**: idioma PT, tema, barra de status e uma lista de comandos liberados sem perguntar (`npm run`, `npm test`, git read-only). É **mesclado** com o que você já tem — nada seu é perdido. |
| `plugin/scripts/statusline.js` | `~/.claude/scripts/` | **Barra de status** (sempre visível): diretório, branch, alterações não salvas (`✗`), à frente/atrás do remoto (`↑`/`↓`), **GitHub conectado** (`gh✓`/`gh✗`), **PR aberto** (`PR#`) e o contexto **em número absoluto**. Resolve a cegueira do Desktop, que não mostra nada disso. |
| `plugin/skills/setup/` | — | O `/kit-vamoo:setup`, que instala as quatro linhas acima. |
| `docs/como-trabalhar-com-claude.md` | — | **Guia de leitura** — como pedir bem, verificar e não se queimar. Comece por aqui. |
| `plugin/scripts/skill-pressure-test.sh` + `tests/skills/` | — | **Teste de skill sob pressão**: prova se uma skill de disciplina segura o Claude quando ele tem motivo pra furar a regra. Cenários prontos pra `verificacao` e `worktrees`; método em [`docs/testar-skills-sob-pressao.md`](docs/testar-skills-sob-pressao.md). |
| `plugin/templates/` | — | Modelos pra copiar em projetos novos: `CLAUDE.md` de projeto, `.env.example`, `.gitignore`, CI e **`playwright/`** (testes e2e). |
| `install.sh` | — | Instalação pelo terminal, pra quem prefere — ou pra instalar de um clone local, sem rede. |

> **Custo de contexto:** o plugin adiciona ~3,1k tokens a cada sessão (as
> descrições das skills, que é como o Claude sabe quando usar cada uma). Skill
> que você não usa pode ser desligada em `/plugin`.

> 📖 **Antes de tudo, leia [`docs/como-trabalhar-com-claude.md`](docs/como-trabalhar-com-claude.md).** É o que mais vai te ajudar — config sem método não adianta.

---

## Skills incluídas

São 15. Algumas funcionam de cara; outras só fazem efeito depois que você liga
um pré-requisito (uma API, um MCP, uma conta) — sem ele a skill simplesmente
**não dispara**, não quebra nada.

A maior parte o Claude aciona sozinho, pela situação. As que você chama na mão
levam o prefixo do plugin: `/kit-vamoo:setup`, `/kit-vamoo:revisar`.

### ✅ Prontas pra usar (sem setup extra)

| Skill | Pra que serve | Pré-requisito |
|---|---|---|
| **find-docs** | Busca documentação oficial e atualizada antes de escrever código. Mata API inventada. | nenhum (o instalador já põe o ctx7) |
| **auditoria-seguranca** | Auditoria em 5 categorias (isolamento de inquilino, permissão decidida no navegador, IDOR, chaves expostas, XSS) que sai em **PDF pt-BR + issues prontas**. Detecta a stack antes de auditar, então serve projeto que não é Supabase. | nenhum |
| **secscan** | Revisão de segurança read-only: RLS, secrets, deps vulneráveis. "roda um secscan". Ver `docs/seguranca.md`. | nenhum |
| **baseline** | *"Este app está pronto pra produção?"* — 7 frentes: bundle e secrets, RLS, login e permissão, limites de uso, carga, observabilidade, segredos. Inclui a checklist de migration que não derruba um banco com dado. Dois modos: **construir** (app novo nasce certo) e **auditar** (app no ar). Mede com script, não com achismo. Ver `docs/observabilidade.md`. | `jq`, `node` |
| **handoff** | `/kit-vamoo:handoff` — monta o documento de passagem pra outra sessão, outro dev, ou você daqui a três semanas. Marca o que foi **verificado** e o que é só **crença**, que é o que evita o próximo trabalhar em cima de premissa falsa. | nenhum |
| **ship** | Pipeline de release com gates (typecheck/lint/test → commit → push → PR). | editar o passo de deploy pro seu stack |
| **memoria-projeto** | Tira a memória do projeto da sua máquina e põe no repositório (`.context/memoria/`). É o que faz o contexto sobreviver a trocar de computador — e o que deixa outra pessoa (ou o Codex) enxergar o que vocês decidiram. Recusa a adoção se achar credencial escrita ali dentro. | projeto em git |
| **setup** | `/kit-vamoo:setup` — instala o que o plugin não consegue (CLAUDE.md global, barra de status, preferências) e te ajuda a preencher o CLAUDE.md. Rode uma vez, depois de instalar. | nenhum |
| **git-sync** | Deixa seu clone em dia com o GitHub (fetch + fast-forward, nunca force). Em repo com mais gente, mostra o que o outro mudou, PRs abertos e **risco de conflito** antes de você codar. `/kit-vamoo:git-sync`. | `gh` instalado e autenticado (opcional — sem ele, só perde a visão de PR) |
| **bot-discord** | Bot de Discord em Node/TypeScript hospedado em VPS própria, do Developer Portal ao container rodando: intents, convite, código, idempotência, cron, Docker e a verificação de que subiu de verdade. Também serve pra debugar bot que "conecta mas não responde". | conta Discord; VPS com Docker (só na hora do deploy) |

### 🧭 Processo (como o Claude trabalha — sem setup)

Estas são as skills que o CLAUDE.md roteia por situação (ver a tabela de
roteamento no topo do `plugin/templates/CLAUDE-global.md`). Guardam o passo-a-passo
que sairia do CLAUDE.md pra não pesar o contexto toda sessão.

| Skill | Pra que serve | Pré-requisito |
|---|---|---|
| **grilling** | Interroga um plano grande até fechar antes de codar. O Claude aciona ao detectar uma implementação grande. | nenhum |
| **grill-me** | Gatilho manual do `/kit-vamoo:grill-me` — dispara o `grilling` na hora que você quiser. | nenhum |
| **grill-with-docs** | Igual ao grilling, mas ancorado na doc do projeto (quando tem `.context/`). | projeto com `.context/` |
| **guardrails-ia** | Agente de IA que fala com cliente: o que ele pode afirmar, pedido de parar, escalar pra humano, e quem responde o fio quando IA e humano disputam. | nenhum |
| **verificacao** | Casos de "como testar de verdade antes de dizer pronto" (ramos, UI, runners, erro de prod), o formato do veredito de QA e o método pra teste instável (esperar condição, achar o teste que suja o estado). | nenhum |
| **orquestracao** | Como disparar vários subagentes em paralelo sem estourar rate-limit. | nenhum |
| **worktrees** | Trabalhar com vários terminais no mesmo projeto sem um atrapalhar o outro. | nenhum |

### 🎨 Bônus

| Skill | Pra que serve | Pré-requisito |
|---|---|---|
| **diretor-imagem** | Transforma um pedido em linguagem normal ("mais cinematográfico", "zoom out lento") em prompt pronto pra gerador de imagem e vídeo (nano banana, Midjourney, Flux, Kling). Nada a ver com código — é a que mais rende em post e material de apresentação. Pesa ~27k tokens quando dispara, então desligue em `/plugin` se não for usar. | conta no gerador |

---

## Instalação (sem terminal)

Três coisas digitadas **dentro do Claude Code**. Não precisa clonar nada, nem
abrir terminal, nem instalar MCP à mão.

```
/plugin marketplace add VAMOO-AI/claude-kit-mentorados
/plugin install kit-vamoo@vamoo-ai
/kit-vamoo:setup
```

O que cada uma faz:

1. **`marketplace add`** — diz ao Claude Code onde este kit mora.
2. **`install`** — instala skills, comandos, guard-rails de git e o MCP
   dotcontext. Se ele pedir, rode `/reload-plugins`.
3. **`/kit-vamoo:setup`** — instala o que um plugin não consegue declarar
   (CLAUDE.md global, barra de status, preferências) e te ajuda a preencher o
   CLAUDE.md com os seus dados, ali na conversa mesmo.

Depois **reinicie o Claude Code**. Não é só pela barra: a sessão aberta começou
com as configurações antigas, então idioma, permissões e barra de status só
valem no próximo start.

> **Instalou o kit antes de 24/08/2026, pelo `install.sh`?** Você precisa de um passo a
> mais, senão fica com cada skill duas vezes — a cópia velha em `~/.claude/skills/` e a
> nova do plugin, com o mesmo nome. O `/kit-vamoo:setup` limpa isso sozinho, mas vale ler
> [`docs/migrar-do-install-antigo.md`](docs/migrar-do-install-antigo.md): tem um prompt
> pronto pra colar no Claude, que faz o diagnóstico, a migração e a conferência.

### Duas garantias, porque instalador que apaga config é traumático

- **Seu `CLAUDE.md` não é sobrescrito.** Se você já tem um, o modelo do kit fica
  em `~/.claude/CLAUDE.kit.md` pra comparar. Trocar pelo do kit é uma escolha
  sua, explícita.
- **Seu `settings.json` é mesclado, não substituído.** Suas chaves ganham; a
  lista de permissões vira a união das duas. E tudo que é tocado ganha cópia em
  `~/.claude/backup-kit-<data>/` antes (ficam os 3 backups mais recentes).
- **O que é seu em `~/.claude` não é removido se você disser que é seu.** Liste
  em `~/.claude/.keep-local` — um caminho por linha, relativo a `~/.claude`,
  `#` comenta, glob simples (`skills/meu-*`). A limpeza da instalação antiga
  pula o que está lá; o kit continua instalando e atualizando o que é dele.

### Pelo terminal (alternativa)

```bash
git clone https://github.com/VAMOO-AI/claude-kit-mentorados.git claude-starter-kit
cd claude-starter-kit
bash install.sh            # ou --dry-run pra ver o que ele faria
```

Faz exatamente o mesmo que os três comandos acima, a partir do clone local.

### Confira se deu certo

```
/plugin          → kit-vamoo aparece como enabled
/kit-vamoo:      → autocompleta as skills do kit
```

E a barra de status aparece no rodapé depois de reiniciar. Pronto. 🎉

### Atualizar depois

**Atualização não é automática por padrão.** O Claude Code desliga o auto-update para
marketplaces de terceiros — e este kit é um deles. Enquanto ninguém rodar nada, você
continua na versão que instalou, mesmo com versão nova publicada.

Você escolhe entre os dois caminhos abaixo. O primeiro é o recomendado: liga uma vez e
acabou.

**Ligar o auto-update (uma vez, recomendado)**

```
/plugin
```

Vá em **Marketplaces → vamoo-ai → Enable auto-update**. A partir daí o kit se atualiza
sozinho e você só precisa aplicar as mudanças na sessão aberta:

```
/reload-plugins
```

**Atualizar na mão (quando quiser)**

```
/plugin marketplace update vamoo-ai
/plugin update kit-vamoo
/reload-plugins
```

O primeiro comando re-lê o catálogo do repositório (é o que descobre que existe versão
nova); o segundo baixa; o terceiro aplica sem precisar reiniciar. Se o `/reload-plugins`
avisar sobre cache de prompt, rode `/reload-plugins --force`.

#### Duas coisas que o auto-update **não** faz

1. **Não atualiza o que veio do `/kit-vamoo:setup`.** O `CLAUDE.md` global, a barra de
   status e as preferências não são parte do plugin — um plugin não consegue declarar
   essas chaves. Depois de uma atualização grande, rode `/kit-vamoo:setup` de novo. Ele
   **não sobrescreve** o seu `CLAUDE.md`: deixa o modelo novo em `~/.claude/CLAUDE.kit.md`
   para você comparar. Regra nova do kit fica parada ali até alguém olhar.
2. **Não te avisa em voz alta.** O indicador de versão nova aparece dentro do `/plugin`.
   Se você nunca abre esse menu, não vê.

#### Se você mantém o kit (não é o caso do mentorado)

O campo `version` do `plugin/.claude-plugin/plugin.json` é a **chave do cache**: o Claude
Code guarda cada versão numa pasta própria e só busca de novo quando o número muda.
Publicar mudança sem subir a versão significa que **ninguém recebe** — nem quem está com
auto-update ligado. Bump de versão não é formalidade, é o mecanismo de entrega.

---

## Como usar no dia a dia

- **Memória de projeto:** num projeto novo, na primeira conversa, peça
  **"init the context"**. O Claude cria a pasta `.context/` e passa a lembrar do projeto.
- **Memória que sobrevive à máquina:** rode `/kit-vamoo:memoria-projeto` num
  projeto em git. O que o Claude aprende passa a morar em `.context/memoria/`,
  dentro do repositório — vai junto no commit, e continua lá no próximo
  computador ou pra quem mais trabalhar no projeto.
- **Modo aprendizado:** diga **"explica"** ou **"modo aula"** e o Claude passa a ensinar
  o porquê de cada coisa, passo a passo (definido no seu CLAUDE.md).
- **Skills de decisão:** use `/kit-vamoo:grill-me` quando quiser testar um plano e
  `/kit-vamoo:grill-with-docs` quando a decisão precisar considerar a documentação do projeto.
- **TDD e debugging:** as regras do `CLAUDE.md` já exigem teste failing-first e
  investigação de causa raiz; não dependem de plugin externo.

---

## 🌱 Iniciante vs ⚡ Avançado

O kit serve aos dois níveis. Comece pelo seu e cresça.

**Iniciante — leia primeiro:**
1. [`docs/como-trabalhar-com-claude.md`](docs/como-trabalhar-com-claude.md) — o método.
2. [`docs/memoria-e-contexto.md`](docs/memoria-e-contexto.md) — como o Claude lembra: global vs projeto, o que vai no CLAUDE.md vs em `docs/`. (O tema que mais confunde.)
3. [`docs/seguranca.md`](docs/seguranca.md) — os 7 furos que iniciante esquece (RLS, secrets, deps, limite de uso, secret que não é secret) + revisão automática.
4. [`docs/economia-de-tokens.md`](docs/economia-de-tokens.md) — por que seu limite acaba tão rápido e os 4 hábitos que fazem ele render (spoiler: sessão longa custa juros compostos).
5. Use `/kit-vamoo:explicar` e `/kit-vamoo:revisar`, modo "explica", e a skill `find-docs`.

**Avançado — quando já estiver confortável:**
1. [`docs/observabilidade.md`](docs/observabilidade.md) — *"como você descobre que quebrou?"*. Se a resposta é "tento reproduzir", leia antes de colocar qualquer coisa no ar.
2. [`docs/testes-e2e-com-playwright.md`](docs/testes-e2e-com-playwright.md) — testar o caminho do usuário de verdade (template em `plugin/templates/playwright/`).
3. [`docs/programacao-avancada-com-claude.md`](docs/programacao-avancada-com-claude.md) — sub-agentes paralelos, worktrees, hooks, criar suas próprias skills.
4. Skill **`baseline`** — *"está pronto pra produção?"* nas 7 frentes. Rode antes do primeiro deploy, e de novo depois que o app estiver no ar.
5. Skill **`/kit-vamoo:ship`** — pipeline de release com gates (typecheck/lint/test → commit → push → PR). Edite o passo de deploy com o comando do seu stack.
6. Skill **`/kit-vamoo:handoff`** — quando for passar o projeto (ou voltar nele daqui a um mês).
7. [`plugin/templates/ci.yml`](plugin/templates/ci.yml) — CI no GitHub Actions pra travar qualidade no PR.
8. [`docs/mcps-recomendados.md`](docs/mcps-recomendados.md) — Playwright, GitHub e cia., **sob demanda**.
9. [`plugin/templates/CLAUDE-projeto.md.exemplo`](plugin/templates/CLAUDE-projeto.md.exemplo) — um `CLAUDE.md` por projeto.

---

## Perguntas comuns

**Já tinha um CLAUDE.md (ou skills, ou statusline), vou perder?**
Não. O `CLAUDE.md` que já existir **não** é tocado — o modelo do kit fica em
`~/.claude/CLAUDE.kit.md` pra você comparar, e trocar é uma escolha explícita
sua (`bash kit-setup.sh --force`). O `settings.json` é **mesclado**: suas chaves
ganham, a lista de permissões vira a união das duas, e nada de `env` ou hook seu
se perde. Tudo que é tocado ganha cópia em `~/.claude/backup-kit-<data>/` antes.

**Eu já tinha instalado o kit pelo `install.sh` antigo. E agora?**
O setup detecta a instalação antiga pelo manifesto e **remove** as skills, hooks
e comandos que ele tinha copiado pra `~/.claude/` — porque agora eles vêm do
plugin, e ter os dois significaria skill duplicada e hook rodando em dobro, na
versão velha inclusive. O que sai vai pro backup. Editou uma dessas cópias, ou
tem algo seu com o mesmo nome? Liste em `~/.claude/.keep-local` antes de rodar
o setup e fica.

**Funciona no Windows?**
Sim, com WSL (Ubuntu). Fora do WSL, o Git Bash roda os hooks e a barra (tudo é
`bash` + `node`, sem `jq`), mas o som de "terminou" é só macOS — o hook checa se
o `afplay` existe antes de tocar, então no Windows ele simplesmente não faz nada.

**Isso vai deixar minhas sessões mais caras?**
O plugin adiciona ~2,6k tokens por sessão: são as descrições das skills, que é
como o Claude sabe quando usar cada uma. Se alguma você nunca vai usar, desligue
em `/plugin`. Em tempo, os hooks custam menos de 0,1 s por ação (o do dotcontext
roda só na abertura da sessão, e só em projeto com `.context/`). O que pesa de
verdade no seu limite é sessão longa — está em
[`docs/economia-de-tokens.md`](docs/economia-de-tokens.md).

**Posso desinstalar?**
Sim: `/plugin uninstall kit-vamoo`. E restaure o que quiser de
`~/.claude/backup-kit-<data>/`.

---

## 🎓 Quer ir além?

O kit é a base. O que multiplica de verdade é o **método**: como pedir bem,
verificar de verdade, estruturar projeto e shipar com segurança — e isso eu
trabalho de perto na mentoria, com projetos reais.

- 📩 Me chama no Instagram: [**@ruanvamoo.ai**](https://instagram.com/ruanvamoo.ai)
- ⭐ O kit te ajudou? Deixa uma estrela no repo — é o que me diz que vale manter público.
- 🐛 Achou um problema? [Abre uma issue](https://github.com/VAMOO-AI/claude-kit-mentorados/issues) — feedback de quem está começando vale ouro aqui.

Bom proveito! 🤖
