# limpeza-mac — travas do aplicar.sh

Lido no passo 2, antes de mostrar a saída do `DRY=1` e quando algo fica em `<ledger>/mantidas.tsv`.

O que o script respeita, e por quê:
- **`merged(PR#N)` só com o SHA igual ao head do PR.** O `gh pr list --head` casa pelo
  nome da branch, então um commit feito depois do merge ou um nome reusado se perderia num
  `-D`. Um tip que é só ancestral do head também fica. O PR também tem que ter sido mergeado
  **no default** (`--base`), porque uma branch empilhada mergeada em outra feature não
  chegou lá. E o `origin/HEAD` local é atualizado (`set-head --auto`) antes, porque ele fica
  velho quando o default muda no GitHub.
- **Todo worktree passa pelo `worktree-gc.sh --verificar <caminho>` do plugin.** São as
  mesmas travas do gc: sujo, arquivo ignorado de valor, branch não mergeada na branch
  padrão do origin (sem padrão descoberta, é keep com o motivo). A trava do inventário
  vale para a hora em que ele rodou; um `outputs/video.mp4` que aparece depois só a de
  agora pega. Qualquer saída diferente de 0 mantém o worktree, e o motivo vai para
  `<ledger>/mantidas.tsv`. O `--verificar` não remove nada, mas atualiza as refs
  remotas com `git fetch --prune`; o `aplicar.sh` faz esse fetch uma vez por repo e chama o
  `--verificar` sem o dele.
- **A branch de um worktree removido sai com ele**, menos `main`, `master`, `develop`,
  `dev`, `staging` e `production`, que ficam como no `branches.tsv`.
- **Arquivo ignorado conta como sujeira.** O `worktree remove` sem `--force` apaga ignorado
  sem avisar (`.env.local`, sqlite, dump), e o ledger não restaura isso. Só passa ignorado
  de build ou cópia byte a byte do mesmo arquivo no clone principal (o `.env` semeado).
- **Worktree cujo HEAD mudou depois do inventário fica.** Em detached, nenhuma branch
  seguraria o commit novo.
- **Lock de sessão morta não protege nada.** O Claude grava `claude session X (pid N)` no
  lock do worktree. Se o pid não existe e o `--verificar` libera, o script faz `unlock` e
  remove. Se o remove falhar, o lock volta.
- **Worktree com índice mexido nas últimas 24h é `ativa`**, nunca merged: uma branch
  recém-criada sem commit também é ancestral do default. O inventário usa
  `--no-optional-locks` para o próprio `status` não reescrever o índice e apagar esse sinal.
  Qualquer `git status` comum (IDE, git-sync, você) reescreve o índice e faz tudo virar
  `ativa` por 24h. O erro é para o lado de manter.
- **`.next` e `node_modules` saem só de repo parado há `DIAS_NM` dias (padrão 7).** O de um
  repo em uso é o build que o dev server está servindo.
- **`.next` dentro de `.vercel/output` não é build solto.** É o prebuilt do deploy, e o
  inventário não desce em `.vercel`.
- **Ferramenta vendorizada não é build.** O inventário não lista `node_modules` sob `.tools`
  (ex.: `.claude/skills/<ferramenta>/.tools`), `.context/vendor` nem de clone aninhado (`.git`
  diretório) que o projeto ignora. Medida pelo clone de dentro, ela parece parada mesmo com o
  projeto em uso; worktree (`.git` arquivo) segue a regra comum.
- **A idade do repo vem do reflog do HEAD**, não do mtime do índice, que qualquer
  `git status` reescreve.
