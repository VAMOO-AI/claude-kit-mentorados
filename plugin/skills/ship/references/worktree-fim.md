# ship §6 — worktree no fim em detalhe

Lido no §6, quando `git rev-parse --show-toplevel` está dentro de `.claude/worktrees/` ou `.claude-worktrees/`.

Se `git rev-parse --show-toplevel` estiver dentro de `.claude/worktrees/` ou `.claude-worktrees/`,
confira as guardas — é a prova da skill `worktrees` ("Limpeza no fim"):

```bash
git rev-parse --show-toplevel | grep -qE '/\.claude/worktrees/|/\.claude-worktrees/' && echo EM_WORKTREE   # senão, pule o §6
gh pr view <n> --json state -q .state           # MERGED
gh pr view <n> --json headRefOid -q .headRefOid # o SHA que o PR levou
git rev-parse HEAD                              # o mesmo SHA: nenhum commit local ficou fora do PR
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-gc.sh" --verificar <wt>   # exit 0 "pode remover" · exit 1 "keep: <motivos>"
```

`<wt>` é o caminho do worktree, escrito por extenso. O `--verificar` pega mudança não commitada,
branch não mergeada e o que o git ignora e o `remove` apagaria calado: env ignorado (`.env*`,
`.npmrc`, `bunfig.toml`, de qualquer pasta) diferente do clone principal ou só existente no
worktree, repositório aninhado ignorado e qualquer outro ignorado fora da lista fechada de
cache/build (`outputs/`, `.context/runtime/`, um dump). A única exceção é symlink que aponta para
fora do worktree (o `.venv` que o projeto liga ao clone principal): o `remove` apaga o link, não o
alvo. Se esse é o único motivo e o `git status --porcelain` só mostra o link, a guarda vale.

Não troque a guarda do `headRefOid` por `git diff origin/main`: é a armadilha de dois pontos do
2-base, e basta a `main` andar depois do squash para o diff sair não-vazio.

- **Alguma guarda falhou** → não remova. Relatório: `worktree: mantido (motivo)`.
- **Todas verdes, sem pedido de limpeza** → relatório: `worktree: removível (prova verde)`, e
  pergunte. Quem está aprendendo não sabe o que some junto com um worktree.
- **Todas verdes, com o pedido** (a pessoa disse "ship e limpa", ou o `CLAUDE.md` dela ou o
  `AGENTS.md`/`deploy.md` do projeto diz que a ship fecha o worktree) → remova via `ExitWorktree`
  com `action: "remove"`.
  - **Squash-merge:** o `ExitWorktree` recusa dizendo "N commits serão descartados", porque o squash
    criou um commit novo na `main`. Isso é esperado e seguro quando o `HEAD` é o `headRefOid` do PR
    mergeado. Rode o `--verificar` de novo e re-invoque com `discard_changes: true`: a recusa lista
    commits e arquivos não commitados, nunca o que o git ignora, e o descarte leva o `.env.local`
    junto. Nunca passe `discard_changes: true` sem as duas guardas verdes, e nunca contorne com
    `git worktree remove --force` ou `rm`.
