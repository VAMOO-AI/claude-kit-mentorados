# ship §6 — worktree no fim em detalhe

Lido no §6, quando `git rev-parse --show-toplevel` está dentro de `.claude/worktrees/` ou `.claude-worktrees/`.

Fora de um worktree desses, pule o §6. Dentro, confira as guardas: a prova manual (PR `MERGED`,
o `headRefOid` dele e `worktree-gc.sh --verificar <wt>` com exit 0) é a da skill `worktrees`,
seção "Limpeza no fim". Rode os comandos de lá.

O critério da ship para o SHA é mais estrito que o de lá: `git rev-parse HEAD` tem de ser
**igual** ao `headRefOid` do PR (nenhum commit local ficou fora do PR); tip só contido no head
não basta aqui.

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
