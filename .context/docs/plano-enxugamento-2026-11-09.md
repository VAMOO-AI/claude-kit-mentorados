# Plano: enxugar o plugin público e fechar o corte com o time (2026-11-09)

Origem: auditoria de 09/11/2026 dos três repos + entrevista de decisões. Este arquivo guarda as decisões e o plano; o histórico da conversa não entra.

## Decisões

| # | Tema | Decisão |
|---|---|---|
| D1 | Público do plugin | O que só o time usa sai do `kit-vamoo` e vai para o `kit-vamoo-time` ou `marca`. Revoga o invariante "sem perfil por público". |
| D2 | RTK (`rtk-claude`, `rtk-codex`, `rtk-holdout`, `codex-espelho`, `codex-optimize`) | Migra para o time. Holdout a 10% por 7 dias; sem ganho real, sai do time também. |
| D3 | `block-parallel-clone-switch` + `repo-session` | Removidos dos dois kits. |
| D4 | Auto-update | Canal estável: branch padrão do repo vira `stable`; `main` segue com self-merge. Promoção manual por tag. |
| D5 | Destrutivo | Regras `ask`/`deny` donas do que é globável; `check-careful` fica só com `rm -rf` contextual, SQL executado, `db reset` remoto e exfiltração. |
| D6 | `lint-modificados` no Stop | Sem `--fix`; devolve os erros ao modelo. |
| D7 | Custo de contexto | `skills-projeto` segue invocável; `harness-check` vira só-slash e perde os trechos de time. |
| D8 | Skills de conteúdo | `motion-reel`, `diretor-imagem`, `gerar-imagem` vão para o plugin `marca`, com os testes/CI da `motion-reel`. |
| D9 | Só-slash | `handoff`, `auditoria-seguranca`, `geo-ia`, `bot-discord`, `harness-check`, `mcp-sistema`, `guardrails-ia`. |
| D10 | Commands | `/explicar` e `/revisar` saem. |
| D11 | `CLAUDE-global.md` | Reescrito a partir do v6 do Ruan, sem linhas de manutenção do kit, mantendo EXPLAIN/MENTOR. Meta: ≤ 7.000 bytes. |
| D12 | Kit do time | Entra depois do público: template comum neutro, fim do corte do núcleo, deny de `.env` por glob, docs datadas arquivadas. |
| D13 | Hooks menores | Sai `warn-cli-outdated`; `path-rules` sem `Read` no matcher; `timeout` em todas as entradas; um dispatcher de SessionStart; `warn-branch-worktree` só com "branch atrás do upstream". `session-size-guard` e `block-cd-leitura-relativa` ficam até haver medição em modo `auto`. |
| D14 | Duplicação entre skills | 5 extrações: memória×handoff, dono do canal, limpeza de worktree, fronteira de segurança, formato de vereditos. "N terminais" fica de fora (exige re-medir com `claude -p`). |
| D15 | Supabase | `ask` para `secrets set/unset` e `migration repair`, em todas as formas. `functions deploy` livre. |
| D16 | Entrega no público | Um PR único. |
| D17 | Dono do canal | Canônico: `ia · humano · api_oficial · aguardando_inbound · nao_contatar`. `aguardando_resposta` some. Mora na `guardrails-ia`. |
| D18 | Máquina do Ruan | Pelo kit do time o que ele governa; `~/.agents/skills` e `cleanupPeriodDays` direto, com backup e confirmação antes de apagar. |
| — | `Bash(git push *)` no allow | Fica: decisão testada (`tests/test-merge-settings.sh:572`). |

## Premissas

Com recibo (lido em 09/11, worktree em `fbbb5e6`, 0.90.0):
- `hooks/hooks.json` registra 16 entradas; só 3 têm `timeout`.
- `pre-bash.sh:110-111` despacha 6 guards em ordem fixa; `rtk-claude` é o último.
- `templates/settings.json:16` grava `autoUpdate: true`; `:81` `Bash(npx supabase:*)`; contagem 169 allow / 544 deny / 214 ask.
- `merge-settings.js:19` não troca a fonte de marketplace que a pessoa já tem.
- `guardrails-ia/SKILL.md:96` lista 4 donos; `whatsapp-inbox-stack/references/canal-e-auditoria.md:15` lista 5.
- `test-skill-descriptions.sh`: catálogo em 7.836 de 8.000 chars.

A verificar no passo 0 (sem recibo; se falhar, o passo indicado volta para decisão):
- P1. Marketplace `github` sem `ref` segue o branch padrão do repo, e trocar o padrão não quebra o clone já feito no cache. → D4.
- P2. `disable-model-invocation: true` tira a skill do listing no CLI e no Desktop. → D9.
- P3. Saída de hook `Stop` com `decision: block` + motivo volta ao modelo. → D6.
- P4. `release-trem.sh`, CI (`validate`, `versao`, `CodeQL`) e `nucleo-ciclo.sh` assumem `main` por nome, não "branch padrão". → D4.
- P5. O plugin `marca` tem CI que rode os 13 arquivos de teste da `motion-reel`. → D8.
- P6. Quem mais consome `repo-session` além do parallel-switch (statusline? `compact-estado`?). → D3.

## Passos

Cada passo tem o check que o prova. Teste novo falha no base antes de passar.

**Fase 0 — premissas**
0. Verificar P1–P6 (docs do Claude Code via `find-docs`; grep nos scripts). Check: cada premissa vira recibo ou pergunta.

**Fase 1 — quem recebe, antes de quem remove**
1. `vamoo-marca`: receber `motion-reel`, `diretor-imagem`, `gerar-imagem` + testes. Check: `claude plugin validate` e suítes da `motion-reel` verdes lá; as 3 aparecem no listing como `marca:*`.
2. `claude-config-team` (`plugin-time`): receber RTK, Codex e a parte VPS de `monitoramento-infra`; registrar `rtk-claude` num PreToolUse(Bash) próprio do plugin-time; tirar esses itens da `nucleo.lista`. Check: `tests/test-plugin-time.sh`; `rtk gain` responde; um `ls` na sua máquina passa pelo rtk com o hook vindo do plugin-time.

**Fase 2 — PR único no público** (branch `fix/riscos-mentorados`, já com block-main-commit e contradições do template)
3. Remover RTK/Codex/`repo-session`/parallel-switch/`warn-cli-outdated` e as 3 skills de conteúdo + parte VPS. Check: grep sem referência órfã; `test-pre-bash`, `test-hooks-convidado`, `test-docs-consistencia`, `test-readme-contagem`, `test-skills-sh-catalogo` verdes; cadeia de um Bash cai de 2 node para 1 (contador de node de mentira, como em `test-block-main-commit.sh`).
4. `check-careful` mínimo (D5). Check: replay do corpus (`scripts/replay-corpus.sh`) sem comando que antes perguntava e agora passa calado; cada caso retirado do hook tem regra `ask`/`deny` que o casa (asserção em `test-merge-settings.sh`).
5. `lint-modificados` sem `--fix` (D6). Check: teste com arquivo com erro de lint → arquivo inalterado (hash igual) e erro na saída que vai ao modelo.
6. Hooks menores (D13). Check: teste que falha se alguma entrada do `hooks.json` não tiver `timeout`; Read de arquivo não dispara `path-rules`; SessionStart com 1 entrada + `compact`.
7. Template `settings.json`: `ask` de supabase (D15). Check: asserções `casa ask` para `npx supabase secrets set X`, `supabase migration repair`, e `casa allow` sem ask para `npx supabase functions deploy`.
8. Skills: só-slash (D9), `/explicar` e `/revisar` fora (D10), `harness-check` sem trechos de time (D7), 5 extrações (D14, D17). Check: `test-skill-descriptions` (catálogo ≤ 5.000 chars), `test-skill-tamanho`, `test-skill-spec`, `test-lint-instrucoes`; grep: `aguardando_resposta` zero ocorrências; bloco `jq` de publicar memória em um arquivo só.
9. `CLAUDE-global.md` reescrito (D11). Check: `wc -c` ≤ 7.000; `test-lint-instrucoes`; nenhuma citação a `docs/…` que não vai no pacote; nenhuma skill removida citada.
10. Suíte inteira + gates do kit, PR em draft, release pelo `release-trem.sh`. Check: `validate` verde; `versao` vermelho é esperado até o trem.

**Fase 3 — canal estável**
11. Criar `stable` na tag do release anterior, ajustar CI/scripts (P4), documentar a promoção no `CONTRIBUTING.md`. Trocar o branch padrão no GitHub: **confirmação sua na hora**. Check: `claude plugin marketplace update vamoo-ai` numa instalação sem `ref` traz a versão de `stable`, não a da `main`.

**Fase 4 — kit do time**
12. `nucleo-ciclo.sh plugin`, depois PR do time: template comum neutro, hooks do núcleo fora do `settings.json` e do `update.sh`, `.env` por glob, docs datadas em `docs/historico/` fora do update, `skillOverrides` e hook `echo 📍` fora, `modelSettings` e regras `ask` por nome no `settings.ruan.json`. Check: gates do time; `update.sh` real; `~/.claude/hooks` só com o que tem leitor; `Read` de um `.env.qualquercoisa` negado.

**Fase 5 — sua máquina e medição**
13. Backup e remoção de `~/.agents/skills` antigas (**confirmação antes de apagar**), `cleanupPeriodDays`. Check: `ls`; listing de skills sem duplicata de `audit-multidim`.
14. Holdout do RTK a 10% por 7 dias. Check: ledger em `~/.claude/.cache/rtk-holdout/` com as duas populações; decisão registrada aqui.

## Foco do review (entradas que nenhum passo testa por padrão)

1. Mentorado em versão antiga que pula direto para a nova: hook removido ainda referenciado no `settings.json` dele (instalação pré-plugin pelo `install.sh`).
2. Máquina do time com `nucleo=plugin` durante a janela entre o merge do público e o do time: RTK e Codex sem casa.
3. Windows/Git Bash: dispatcher novo de SessionStart e `timeout` nas entradas.
4. Comando que só o `check-careful` pegava por contexto e nenhum glob expressa (`git push -f` sem refspec com a branch atual na main; `bash -c '…'`).
5. Skill tornada só-slash que outra skill ou hook manda "acionar" em linguagem natural (`skills-projeto-scan.sh`, `n8n-workflow-agent` → `guardrails-ia`, `agents/revisor.md` → `auditoria-seguranca`).
