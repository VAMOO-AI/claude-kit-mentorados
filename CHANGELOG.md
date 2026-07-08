# Changelog

Mudanças notáveis do kit. Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/).
Mentorado: compare a versão daqui com a que você instalou — se mudou, rode
`bash install.sh` de novo (ele faz backup de tudo antes).

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
