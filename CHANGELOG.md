# Changelog

Mudanças notáveis do kit. Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/).
Mentorado: compare a versão daqui com a que você instalou — se mudou, rode
`bash install.sh` de novo (ele faz backup de tudo antes).

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
