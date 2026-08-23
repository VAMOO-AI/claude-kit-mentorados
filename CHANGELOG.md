# Changelog

Mudanças notáveis do kit. Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/).
Mentorado: compare a versão daqui com a que você instalou — se mudou, rode
`bash install.sh` de novo (ele faz backup de tudo antes).

## [Não lançado] — 2026-08-23

### Adicionado

- **Skill `baseline`** — responde *"este app está pronto pra produção?"* em 7 frentes:
  bundle e secrets, RLS, login e permissão, limites de uso, carga e cache,
  observabilidade e gestão de segredos. Dois modos: construir (app novo nasce certo) e
  auditar (app que já está no ar). Traz scripts que **medem** — `doctor` (o que dá pra
  medir), `collect` (mede sem julgar), `render` (relatório com cobertura declarada) e
  `splinter` (os 21 lints de segurança do Supabase, rodados como consulta, sem alterar
  nada no banco).

  A regra que vale levar pra qualquer auditoria: **"não medido" nunca vira "está ok"**, e
  quando não consegue medir nada ela **falha de propósito** — relatório vazio parece
  aprovação, e é o pior resultado possível.

- **Skill `handoff`** — `/handoff` monta o documento de passagem com template fixo e
  âncora de git. A regra que dá valor ao documento: marcar cada afirmação como
  `[verificado: <comando>]` ou `[acreditado]`. Quem assume trata o handoff como contrato
  e não re-confere; crença escrita como fato vira premissa falsa pra tudo depois.

- **`docs/observabilidade.md`** — *"como você descobre que quebrou?"*. Começa pela
  armadilha de ligar `drop: ['console']` antes de ter error tracking, que apaga o único
  rastro que você teria em produção.

### Alterado

- `templates/CLAUDE-global.md` ganha duas regras de custo que valem no dia a dia:
  **screenshot fica na conversa e é relido a cada mensagem seguinte** (tire print
  quando o visual é a pergunta; pra conferir texto ou erro, leia a página como
  texto) e **sessão longa é o que mais consome seu limite** — a cada comando o
  Claude relê a conversa inteira, então três sessões de 1h custam bem menos que
  uma de 3h com o mesmo trabalho. Terminou a tarefa, assunto novo → `/clear`.

- `docs/seguranca.md` passa de 5 para 7 furos comuns: entram **falta de limite de uso**
  (endpoint que chama IA sem `max_tokens` nem cota vira conta impagável) e **"secret" que
  não é secret** (`VITE_`/`NEXT_PUBLIC_` vai pro bundle). Ganha também a seção de ordem —
  as duas armadilhas onde o problema não é o quê, é o quando.
## [0.6.0] — 2026-08-06

### Skill nova: `git-sync` (trabalhar no mesmo repo que outra pessoa)

O Claude Code Desktop não mostra PR, nem branch remota nova, nem avisa que alguém
mexeu nos mesmos arquivos que você. Duas pessoas no mesmo projeto descobrem o
conflito tarde demais — na hora do PR. Essa skill fecha esse buraco.

- **`skills/git-sync`** — `/git-sync` faz `fetch --prune` e atualiza o clone e os
  worktrees **só por fast-forward** (nunca `pull` com merge, nunca `rebase`
  automático, nunca `reset --hard`, nunca commita por você).
- **Modo time, automático**: quando o repo tem 2+ autores na branch principal nos
  últimos 30 dias, o relatório passa a mostrar o que o outro mudou, branches
  remotas ativas, PRs abertos com autor/`mergeable`/review, PRs mergeados na
  janela — e **risco de conflito**: os arquivos que mudaram na `main` e que você
  também tocou. Force com `--team`, desligue com `--no-team`.
- **Avisos acionáveis** (com o comando exato ao lado): branch atrás da `main`,
  commits locais sem push, branch divergida porque os dois commitaram nela, e
  branch local homônima de uma que já existe no GitHub.
- **Protocolo de sessão** documentado na skill: rode ao abrir (antes de escrever
  a primeira linha) e ao fechar (nada pode ficar sem push).
- Roteamento novo em `templates/CLAUDE-global.md` — o Claude carrega a skill
  sozinho quando você diz que vai começar a mexer no projeto.

Opcional: `gh` instalado e autenticado (`gh auth login`). Sem ele tudo funciona,
só não há visão de PR.

## [0.5.1] — 2026-07-28

### Ajustes pra família Claude 5 (Fable/Opus 5)
- **`templates/CLAUDE-global.md`**: 2 regras novas — (1) pedido que parece errado/subótimo:
  o Claude diz em 1 frase e segue como pedido, nunca transforma a tarefa silenciosamente;
  (2) docs/relatórios gerados sem filler (sem seção boilerplate nem resumo redundante).
  Os modelos da família 5 tendem a expandir escopo e inflar relatórios — o controle é por prompt.
- **`commands/revisar.md`**: trocado "não invente problema pra parecer útil" por "reporte tudo
  que encontrar, rankeado por severidade". Em modelo com precisão alta, a instrução conservadora
  fazia subreportar bug real.
- **`skills/orquestracao`**: freio anti-over-delegation (não delegar o que resolve em poucos
  tool calls; sem subagent pra auto-conferência) + dica de `effort` por estágio em `agent()`.

### Docs
- **`docs/programacao-avancada-com-claude.md`**: link de leitura avançada pro repo
  aipromptguide-workflows (workflows multi-agente + Workflow Principles).

## [0.5.0] — 2026-07-15

### Segurança / sanitização
- **Removidas 8 skills internas/de-cliente** que não eram pedagógicas e expunham operação
  interna: `agent-reporting`, `ambientes-clientes`, `n8n-workflow-agent`,
  `pipedrive-automation`, `vamoo-infra`, `vps-hardening-clientes`, `notebooklm`,
  `notebooklm-project-ops`. (Remover `n8n-workflow-agent` também tirou um identificador
  real de projeto Supabase que aparecia num exemplo.)
- Renomeadas `vamoo-{orquestracao,verificacao,worktrees}` → nomes neutros.

### Performance
- **Removido o hook `typecheck.sh`** (rodava `tsc --noEmit` do projeto inteiro a cada
  edição — travava 12-20s). Fica só o `lint-fix.sh`; o type-check vira parte do check
  final antes de "pronto".

### Instalador — reinstalação que CONSERTA o legado
- `install.sh` agora **sobrescreve o `settings.json`** (com backup) em vez de recusar —
  assim quem tinha o hook tsc antigo o perde ao reinstalar. A versão anterior fica em
  `backup-kit-<data>/settings.json` pra reaplicar customizações (permissions/env).
- Mecanismo "fantasma" estendido a **hooks/scripts/comandos** (antes só skills): item
  que saiu do kit é removido da sua instalação com backup — ex: o `typecheck.sh`.
- **Versionamento**: o manifesto guarda a versão (`kit 0.5.0`) e o instalador avisa
  "atualizando de X → Y".

### Config
- `CLAUDE-global.md` enxugado (v5): `grilling` aciona por **implementação grande** (não
  vagueza); removidas as referências órfãs ao plugin `superpowers`; mantidos os modos
  EXPLAIN/MENTOR (é pedagógico).
- README/SECURITY/docs atualizados (17 → 9 skills).

## [0.4.0] — 2026-07-07

### Adicionado
- **Barra de status com visibilidade de GitHub.** A statusline agora mostra, além de
  diretório/branch/contexto: alterações não salvas (`✗`), commits à frente/atrás do
  remoto (`↑`/`↓`), **GitHub conectado** (`gh✓`/`gh✗`) e **PR aberto pra branch** (`PR#`).
  Resolve a cegueira do Claude Code Desktop, que não mostra nada disso visualmente. O
  estado do GitHub é cacheado (~90s) e atualizado em segundo plano — a barra nunca trava
  esperando a rede. Escrita em node puro (`scripts/statusline.js`), roda no Mac e no Windows.
- **Guard-rails de git como arquivos** (`hooks/`, `scripts/`):
  - `check-careful.sh` — pede confirmação antes de `rm -rf` (fora de pastas descartáveis),
    `DROP`/`TRUNCATE`, `git push --force` e `git add -A/-u/.`.
  - `warn-branch-behind.sh` — avisa, ao abrir a sessão, se a branch está atrás do remoto.
  - `warn-worktree-stale.sh` — avisa se o worktree atual já foi mergeado (é lixo) ou se o
    clone principal não está em `main`.
  - `worktree-gc.sh` — utilitário pra limpar worktrees de branches já mergeadas
    (`worktree-gc.sh` = dry-run; `--apply` remove).

### Alterado
- **Fim da dependência de `jq`.** Todos os hooks passaram a ler o JSON do Claude Code via
  **node** (helper `scripts/hookjson.js`) em vez de `jq`. Como o node já é pré-requisito do
  kit (a statusline roda nele), o `jq` sai da lista de dependências — um pré-requisito a
  menos pra instalar. Os hooks de lint/typecheck e a proteção de commit continuam iguais,
  só sem precisar de `jq`.
- **`block-main-commit` virou arquivo robusto** (`hooks/block-main-commit.sh`), no lugar da
  versão inline por substring. Agora resolve o **repo-alvo real** (`git -C <path>` / primeiro
  `cd <path>`) em vez de olhar só o diretório da sessão, e não confunde `git commit` que
  aparece dentro de uma string (grep/echo). O escape `HOTFIX_MAIN=1` segue igual.
- `install.sh` agora instala as pastas `hooks/` e `scripts/`, e o aviso sobre `jq` virou
  aviso sobre `node`/`gh` (as dependências que de fato importam).

## [0.3.0] — 2026-06-11

### Corrigido
- **Hooks de lint/typecheck automático estavam quebrados (no-op silencioso).** Usavam
  `$CLAUDE_FILE_PATH`, que não é uma variável de ambiente oficial do Claude Code — vinha
  sempre vazia, então o eslint/tsc nunca rodava de fato. Agora leem o caminho do arquivo
  do JSON via stdin (`jq -r '.tool_input.file_path'`), conforme a documentação oficial.
  Degradam graciosamente se `jq` não estiver instalado (não rodam, mas não quebram).

### Adicionado
- Hook `PreToolUse` no `settings.json`: **bloqueia `git commit` direto na `main`/`master`**
  (escape `HOTFIX_MAIN=1` pra quando for proposital). Protege do erro clássico de
  commitar na branch errada — comum com vários terminais abertos no mesmo projeto.
  Portável (só `grep` + `git`, sem depender de `jq`).
- `CLAUDE-global.md`: seção sobre rodar vários terminais no mesmo repo (branch por
  sessão, `git add` só dos seus arquivos, conferir `git log` após o commit).
- `install.sh` avisa quando `jq` não está instalado (os hooks de lint/typecheck
  precisam dele) e mostra como instalar.

## [0.2.0] — 2026-06-09

### Segurança
- `python-dotenv` da skill notebooklm atualizado 1.0.0 → 1.2.2 (GHSA-mf9w-mj56-hr94).

### Adicionado
- `install.sh --dry-run` (mostra o que faria) e `--backup-dir` (muda o destino do backup).
- Backup completo: statusline, skills e comandos agora também são salvos em
  `~/.claude/backup-kit-<data>/` antes de sobrescrever (antes só CLAUDE.md/agents.md).
- Manifesto de instalação (`~/.claude/.kit-manifest`): skills removidas do kit em
  versões novas são limpas na reinstalação (com backup), sem tocar nas suas skills próprias.
- CI do próprio kit (valida JSON, shell, Python, links, secrets e dependências).
- `LICENSE` (MIT), `SECURITY.md` e este `CHANGELOG.md`.
- README com badges (CI/licença/release), URL real de clone e seção "Quer ir além?".

### Mudado
- Skill `pipedrive-automation`: frontmatter corrigido (name batia com a pasta) e
  conteúdo reescrito em PT-BR, curado e enxuto.
- Skill `n8n-workflow-agent`: SKILL.md de 2.310 linhas virou roteador curto +
  referências por domínio em `references/` (carrega só o contexto necessário).
- Templates de CI atualizados pra Node 22.
- Hooks do `settings.json` usam `npm exec --no` (só roda eslint/tsc se o projeto
  tiver a ferramenta instalada — não baixa nada por conta própria).
- Skill `agent-reporting`: caminhos configuráveis via `TICKTICK_ENV_FILE` /
  `TICKTICK_PROJECTS_FILE`; sem credencial configurada, avisa e sai sem quebrar.

### Removido
- Permissão `Bash(npm install:*)` do settings.json default — instalar dependência
  nova volta a pedir sua aprovação (mais seguro pra quem está começando).

## [0.1.0] — 2026-06-08

- Versão inicial: CLAUDE.md, agents.md, settings.json, statusline, /revisar,
  /explicar, docs pedagógicas, templates (projeto, CI, Playwright) e 10 skills.
