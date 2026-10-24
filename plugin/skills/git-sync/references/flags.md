# git-sync: flags, cleanup e `gh`

Referência sob demanda da skill `git-sync`. O script é a fonte da verdade; isto descreve o que
ele faz para você decidir qual flag passar.

## Flags

| Flag | Efeito |
|---|---|
| (nenhuma) | fetch + status + ff-only em checkouts elegíveis + relatório (+ modo time se auto-detectado) |
| `--status-only` | só fetch + relatório (não mexe em HEAD) |
| `--no-pr` | pula `gh pr list` |
| `--no-gh` | nunca chama o `gh`: PRs e prova de merge pela API REST (`git config git-sync.tokenVar`); o mesmo que `git config git-sync.noGh true` |
| `--team` | força modo time (quem mudou o quê, PR com autor/mergeable, branches ativas, risco de conflito) |
| `--no-team` | desliga o modo time mesmo em repo multi-autor |
| `--voltar-main` | **opt-in.** No fim, devolve o checkout deste clone à branch default (ff-only). Aborta e explica em: working tree suja, detached HEAD, merge/rebase/cherry-pick/bisect em andamento, worktree locked, default divergente da remota. Commit local à frente é preservado e vira aviso de push pendente, nunca reset. Em `--status-only` não toca em HEAD. Não é o padrão: com duas sessões no mesmo clone, a última a rodar decidiria a branch da outra |
| `--since N` | janela de atividade do modo time em dias (default 14). Não sendo número, sai 2 |
| `--cleanup-dry-run` | lista o que o apply removeria (abaixo), mais as branches **remotas suas sem cópia local** (autor = `user.name` + `user.email` do clone), com o `git push origin --delete` impresso, nunca executado. O run padrão já avisa quantas branches e worktrees há além da default |
| `--cleanup-apply` | **perigoso**: só se a pessoa pediu "aplica limpeza". Detalhe abaixo |
| `--default-branch <nome>` | override (default: detecta `origin/HEAD` ou `main`/`master`) |
| `--cwd <path>` | roda a partir desse path (multi-root IDE, risco de conflito de outro worktree) |

## O que o `--cleanup-apply` remove, nesta ordem

1. **Worktrees** clean + mergeados + sem sessão viva, com `git worktree remove` (nunca
   `--force`). Mergeado é ancestral de `origin/<default>` ou PR mergeado com head igual ao
   `HEAD` do worktree. Clean é também **sem ignorado de valor**, porque o `remove` apaga
   ignorado sem recusar: env (`.env*`, `.npmrc`, `bunfig.toml`, `.bunfig.toml`, de qualquer
   pasta) igual ao do clone principal, nenhum repo aninhado ignorado e nenhum outro ignorado
   além de symlink e cache/build (`node_modules`, `.next`, `dist`, `.venv`...). Fica, com o
   motivo, o que não passa.
2. Worktree que é **cwd de processo vivo** (sessão do app, terminal, dev server) fica, com
   `keep: cwd de processo vivo (<processo>)`, e a branch dele junto: `/proc` no Linux, `lsof` no
   macOS. O que a checagem não vê (sessão que vai voltar, processo de outro usuário), trave antes
   com `git worktree lock --reason "<motivo sem dígitos>"`: lock sem pid legível conta como
   sessão viva. Lock com pid morto (`kill -0`) é stale e só o apply destrava.
3. **Branches `gone`**: `-d`; se o `-d` recusar, `-D` só com PR mergeado **e** tip igual ao
   head do PR ou contido nele (squash quebra a ancestralidade; tip atrás do head é o caso dos
   últimos commits do PR feitos noutro clone). O head que não está no clone é buscado em
   `refs/pull/<n>/head` sem gravar ref; se não vier, a branch fica com "head do PR
   indisponível". Head ancestral do tip (commit depois do merge é trabalho) e divergência
   preservam, cada um com o seu motivo.
4. **Branches fora do `[gone]`** (remoto vivo ou nunca pushada), com a mesma prova e só a local.
   O `git push origin --delete <b>` sai impresso para você decidir.

Branch sem commit próprio (tip igual a `origin/<default>` ou na linha first-parent dela) nunca
conta como mergeada: é sessão recém-aberta. Sem PR, sem head para conferir, head indisponível ou sem `gh` nem token
da API, a branch fica. Remoto nunca é apagado.

## `gh` e API REST

- `gh auth status` falhando: o script reporta e segue.
- **Duas contas no keyring** (pessoal e trabalho): a ativa devolve `Could not resolve to a
  Repository` para o repo da outra. O script testa as outras contas, usa a que enxerga o repo só
  neste processo e diz qual, com o comando para usar à mão
  (`GH_TOKEN=$(gh auth token -u <conta>) gh ...`). `GH_TOKEN` exportado por você vence e
  desliga a busca.
- **PAT do repo** (repo de outra org, que nenhuma conta do keyring enxerga): o script procura
  `GH_TOKEN` ou `GITHUB_TOKEN` em `.env.tokens`, `.env.local` e `.env` da raiz, nessa ordem, lê
  só a linha dele (nunca `source`), confere que ele enxerga o repo e o usa só neste processo. A
  seção de PRs diz `(autenticado pelo <arquivo> do repo …)`. Onde o keyring já enxerga, ou com
  `GH_TOKEN` exportado por você, o arquivo nem é lido. Não resolva com `gh auth login
  --with-token` usando esse token: ele iria para o keyring e valeria nos outros repositórios.
- **Repo onde o `gh` não pode rodar** (o AGENTS.md proíbe, ou a máquina não tem), configure uma
  vez, local ao clone:

  ```bash
  git config git-sync.noGh true               # o gh nunca é chamado, nem para sondar conta
  git config git-sync.tokenVar MEU_GH_TOKEN   # a variável, no ambiente ou em ~/.claude/.env.tokens
  ```

  O token é lido só na linha dele, nunca impresso, e vai ao `curl` pelo stdin.
  Sem token, o cleanup diz
  "sem prova" e não apaga nada. Com o `gh` instalado mas cego para o repo, só a prova de merge
  cai sozinha na API; a lista de PRs continua no `gh` e só avisa que ele falhou.

- **Qual repo o `gh` consulta:** o do `origin`. O script exporta `GH_REPO` com o slug dele,
  porque sem `gh repo set-default` o `gh` preferiria um remote `upstream` (template, fork de
  origem), e o relatório inteiro sairia do repo errado. `git config git-sync.repo dono/nome`
  sobrepõe o slug (no `gh` e na API REST), e um `GH_REPO` já exportado no ambiente vence os
  dois. Fork que abre PR no upstream: `git config git-sync.repo dono/upstream`.

## Convivência em repo de time

| Situação | O que fazer |
|---|---|
| Vai começar tarefa nova | `git-sync` primeiro, e só então crie a branch |
| Branch nova | `feat/<escopo>-<seu-nome>`: nomes distintos evitam a colisão silenciosa |
| Aviso "DIVERGED … MESMA branch" | `git pull --rebase` com working tree limpa, sugerido à pessoa. **Nunca** `push --force` |
| Aviso "N atrás de origin/main" | se o `risco de conflito` lista arquivo seu, `git merge origin/main` antes de continuar; sem sobreposição, siga |
| Aviso "existe origin/\<branch\>" | o outro já criou essa branch: `git branch --set-upstream-to=origin/<branch>` ou renomeie a sua |
| Terminou um pedaço | commit + push no mesmo dia; branch parada local é conflito acumulando |

O modo time liga sozinho com 2 ou mais autores **por nome** na default em 30 dias: a mesma pessoa
com o e-mail pessoal e o noreply do GitHub conta uma vez. Os PRs mergeados da janela vêm filtrados
por data no servidor, então repo com mais de 30 merges na janela não perde os mais antigos.

## Como o script classifica cada checkout

Alvo = `@{u}` se existir, senão `origin/<default>`. Serve para ler o relatório e para o fallback
só de leitura da skill.

| Estado | Ação do script |
|---|---|
| clean + atrás do alvo (ahead 0) | `merge --ff-only <alvo>` |
| clean + à frente do alvo (behind 0) | nada a puxar: "push pendente", **não** é skip |
| clean + divergido do alvo | **não** faz rebase; reporta a divergência |
| sujo (modificado ou staged) | não puxa; reporta |
| só untracked | pode fazer ff; reporta os untracked no fim |
| detached HEAD | não move HEAD solto (e fica fora do cleanup) |
| upstream configurado mas `gone` | não mexe: branch morta, candidata a cleanup |
| worktree locked | se clean, ainda faz ff; reporta o lock (e se o pid dele morreu, diz que é stale) |

O clone principal nunca recebe `checkout` só para "alinhar": com outra sessão nele, trocar a
branch derruba a outra. O script atualiza a branch que já está em cada checkout.

## Anti-padrões

- `git pull` sem `--ff-only` numa default compartilhada.
- `git add -A` ou commit dos untracked "para limpar o status".
- Assumir que o "Sync Changes 6↓" da IDE é o clone principal: pode ser um worktree.
- Copiar arquivo do clone principal para o worktree "para sincronizar": use `origin/*`.
- Em repo de time: começar a codar sem rodar o git-sync; deixar branch local dias sem push
  "porque ainda não terminei"; resolver `DIVERGED` com `push --force`, que apaga o commit do
  colega; criar `feat/x` sem ver se `origin/feat/x` existe; trabalhar direto na default.
