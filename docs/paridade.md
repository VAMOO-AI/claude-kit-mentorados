# Paridade com o kit do time (`claude-config-team`)

Este kit e o `claude-config-team` compartilham hooks, scripts, skills e testes — e **todos
divergem no arquivo**. Em 04/09/2026 a medição foi: 13 de 13 hooks, 16 de 16 skills, 3 de 7
scripts e 13 de 13 testes diferentes entre os dois repositórios. Parte é desenho; parte era
porte atrasado. Ninguém conseguia dizer qual era qual, e é isso que este documento resolve.

Regra: **divergência não registrada aqui é porte atrasado.** Quem adapta um item do time
para cá acrescenta a linha; quem lê o relatório do `scripts/paridade.sh` decide olhando esta
tabela, não a memória.

## Por que os arquivos divergem por construção

| Dimensão | `claude-config-team` | aqui (`kit-vamoo`) |
|---|---|---|
| Instalação | `update.sh` copia para `~/.claude` | plugin do marketplace + `/kit-vamoo:setup` |
| Caminho dos hooks | `$HOME/.claude/hooks/...` | `${CLAUDE_PLUGIN_ROOT}/hooks/...` |
| Leitura do payload | `jq` | `node` + `scripts/hookjson.js` (jq não é pré-requisito de quem está aprendendo) |
| Registro dos hooks | `settings.json` (merge com o da pessoa) | `hooks/hooks.json` (do plugin) |
| Nome das skills | `vamoo-verificacao`, `vamoo-worktrees`… | `verificacao`, `worktrees`… |
| Público | time VAMOO, fluxo com Supabase/n8n/Vercel e `db-query.sh` | mentorado, projeto qualquer |

Isso torna `diff` inútil entre os dois. O que **dá** para comparar é cobertura de teste:
`bash scripts/paridade.sh` lista, por suíte, os casos que existem lá e não têm par textual
aqui. É ponto de partida para leitura, não dívida confirmada — a mesma prova costuma estar
escrita com outras palavras.

## O que é deliberado (não portar)

| Item | Só no time | Por quê |
|---|---|---|
| `hooks/rtk-claude.sh`, `rtk-codex.sh` + suítes | sim | O RTK é uma ferramenta que o time usa; mentorado não instala. |
| `check-careful`: `db-query.sh`, `.env.1password`, cofre de tokens | sim | Regras de um fluxo que só existe no time — 25 dos 66 casos da suíte de lá. |
| `hooks/check-dev-server.sh` | sim | Depende do fluxo de dev server + `claude-in-chrome` do time. |
| `scripts/publicar-memoria.sh`, `memoria-link.sh` completo | parcial | Aqui a memória é ensinada pela skill `memoria-projeto`; lá há automação de publicação. |
| `update.sh` e suítes `test-update-*` | sim | Aqui quem instala é o plugin; o equivalente é `kit-setup.sh` (`test-kit-setup-keep-local.sh`). |
| Skills de domínio (`n8n-workflow-agent`, `whatsapp-inbox-stack`, `pipedrive-automation`, `vamoo-infra`, `ambientes-clientes`, `vps-hardening-clientes`, `graphify`, `video-watch`, `notebooklm-project-ops`, `pulso-mentorado`, `rsc-client-boundary`, `vamoo-memoria`) | sim | Conhecimento de cliente e de infra da casa. O kit público leva o método, não o cliente. |
| `skills/diretor-imagem`, `guardrails-ia`, `setup` | só aqui | Nasceram para o mentorado; o time não tem o problema. |
| `agents/revisor.md` | diverge | Mesmo contrato; lá cita `bun run type-check` e caminhos do time. |

## O que é espelhado (porte obrigatório nos dois sentidos)

Mudou um destes de um lado? O outro entra na mesma sessão — PR, ou issue com o link do PR.
É a regra que o `path-rules.conf` injeta ao tocar em qualquer um dos dois repositórios.

| Item | Último porte | Nota |
|---|---|---|
| `block-main-commit.sh` | 0.25.0 (03/09) | inclui o parser de heredoc |
| `check-careful.sh` (núcleo: force push, DROP/TRUNCATE, rm -rf, exfiltração, bypass) | 0.25.0 (03/09) | as regras de fluxo do time ficam lá |
| `block-cd-leitura-relativa.sh` | 0.26.0 (05/09) | + redirecionamento não é caminho |
| `block-parallel-clone-switch.sh`, `block-delete-branch-with-children.sh` | 0.25.0 (03/09) | |
| `block-monitor-ci.sh` | 0.26.0 (05/09) | nasceu no time em 0.29.0 |
| `pre-bash.sh`, `pre-prompt.sh` (dispatchers) | 0.26.0 (05/09) | mesma semântica de cadeia; aqui sem o rtk |
| `branch-guard.sh`, `session-size-guard.sh`, `repo-session.sh`, `notify-stop.sh`, `path-rules.sh` | 0.25.0 (03/09) | |
| `lint-fix.sh` / hook de eslint | 0.26.0 (05/09) | `--cache` + `async` |
| `warn-branch-behind.sh`, `warn-worktree-stale.sh`, `worktree-gc.sh`, `atalhos.sh` | idênticos | byte a byte |
| `memoria-indice.sh`, `memoria-link.sh` (núcleo), `skill-pressure-test.sh` | 0.26.0 (05/09) | |
| `settings.json` → `permissions.deny` | 0.26.0 (05/09) | as 26 regras são as mesmas |
| Skills `ship`, `verificacao`, `worktrees`, `orquestracao`, `git-sync`, `harness-check`, `memoria-projeto`, `secscan`, `auditoria-seguranca`, `baseline`, `grilling`, `grill-me`, `grill-with-docs`, `handoff`, `find-docs`, `bot-discord` | 0.26.0 (05/09) | o método é o mesmo; o exemplo pode ser outro |
| Teto de 500 chars por description | 0.26.0 (05/09) | `tests/test-skill-descriptions.sh` nos dois |
| `workflows/audit-multidim.js` | 0.26.0 (05/09) | citado pela skill `baseline` |
| Indicador de sessão longa na barra de status | 0.26.1 (05/09) | mesma régua (600/1.200/2.000); a barra em si diverge — uma linha aqui, sete no time |

## Como usar

```bash
bash scripts/paridade.sh              # tabela por suíte, até 5 casos sem par
bash scripts/paridade.sh --detalhe    # todos os casos
bash scripts/paridade.sh --check      # sai 1 só quando uma suíte inteira do time não existe aqui
TEAM_REPO=/caminho/do/clone bash scripts/paridade.sh
```

O `--check` é frouxo de propósito: reprovar por diferença de redação transformaria o relatório
em ruído que ninguém lê — e relatório que ninguém lê é como a divergência chegou a 100%.
