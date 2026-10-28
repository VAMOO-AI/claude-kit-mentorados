# ship §2 — PR, base, CI e merge em detalhe

Lido no §2, depois do push e antes de qualquer `gh pr merge`. A ordem é 2-base → 2b → 2c → 2a → merge.

### Corpo do PR em arquivo

Corpo em arquivo, não em `--body "$(cat <<EOF …)"`: dentro de worktree o Claude Code recusa o
comando (o `(escopo)` do título vira subshell, e o heredoc dentro de `$(…)` também). Ponha o
`gh pr create` num `.sh` no scratchpad, chamado pelo caminho literal (`bash /caminho/abs/pr.sh`).

### 2-base. A `main` andou desde que você branchou?

Não é gate, é leitura. O squash do GitHub **não** apaga o que entrou no meio (é merge de três
vias), e conflito textual ele acusa sozinho. O que a base velha compromete é a **evidência**: o
verde do CI é do seu SHA, não da `main` de agora.

```bash
git fetch origin -q
git log --name-only --oneline HEAD..origin/main   # o que entrou desde a sua base
git diff --name-only origin/main...HEAD           # TRÊS pontos: o diff real do PR
```

Algum arquivo aparece nas duas listas, ou o que entrou mexe no mesmo comportamento que você?
Traga a `main` (rebase se a branch é só sua, `git merge origin/main` se outra pessoa commita
nela), rode o §1 de novo e só então siga. Sem sobreposição, siga: rebase por higiene só faz a
base envelhecer de novo enquanto o CI roda. O critério completo, e o que fazer quando a branch é
de outra sessão viva, está na skill `worktrees` ("Base velha").

**Nunca julgue um merge por `git diff origin/main..HEAD` (dois pontos):** ele mostra como deleção
tudo que só existe na `main` — artefato do comando, não do merge.

**O PR toca `supabase/migrations/` (ou qualquer DDL)?** A segunda lista acima responde. Passe
antes do push pela checklist "Migration que não derruba produção" da skill `baseline`
(`baseline/references/02-banco.md`): NOT NULL só depois do backfill, índice em tabela viva com
CONCURRENTLY, DROP/RENAME só depois do deploy que parou de usar. Migration que reprova num item
não sobe inteira: vira duas ou três.

### 2b. Esperar o CI do PR — fail-fast

**Antes de tudo: o PR é rascunho?** CI que pula rascunho
(`if: ${{ !github.event.pull_request.draft }}` com `ready_for_review` nos `types`) deixa os jobs
`SKIPPED`. Aí o `gh pr checks` sai 0, o que parece verde, ou responde `no checks reported` e o
watch espera algo que nunca vem. `SKIPPED` de rascunho não é verde. Tire do rascunho antes do
watch:

```bash
gh pr view <n> --json isDraft --jq .isDraft     # true = rascunho
gh pr ready <n>                                 # só se deu true
gh run list --branch "$(git branch --show-current)" --event pull_request --limit 3 \
  --json databaseId,status,createdAt,headSha
```

O `gh pr ready` dispara um run novo no mesmo SHA, que leva alguns segundos para aparecer. Até lá o
`gh pr checks` ainda mostra os `SKIPPED` do rascunho, e um watch disparado na hora sai como se
tivesse terminado. Só siga para o watch com o run novo (`createdAt` depois do `ready`) na lista.
Em repo que não pula rascunho, o `ready` não dispara run: os checks do último push valem.

**Nunca use `gh run watch --exit-status` no CI do PR.** Ele espera **todos** os jobs: o de lint
pode já estar `FAILURE` e o de testes continua 7 minutos, e você fica olhando um CI morto.

```bash
gh pr view <n> --json mergeStateStatus,statusCheckRollup \
  --jq '{mergeStateStatus,checks:[(.statusCheckRollup // [])[]|{name,status,conclusion:(.conclusion // .state)}]}'
```

- Check obrigatório com `FAILURE` → **PARE agora.** Leia o log do job que falhou
  (`gh run view <id> --log-failed`), corrija, commit, push. Não espere os irmãos do run morto.
- `mergeStateStatus` = `CLEAN` e obrigatórios verdes → siga o 2a.
- `BLOCKED` só por checks `IN_PROGRESS`/`pending` → não fique consultando em loop. Dispare a
  espera em background (`run_in_background`) e siga:

```bash
gh pr checks <n> --watch --fail-fast > /tmp/ci-<n>.log 2>&1
```

Em background você recebe **uma** notificação, no fim, e o `--fail-fast` aborta no primeiro check
obrigatório vermelho. **Nunca ponha `--watch` num monitor de stream (`Monitor`):** o watch
redesenha a tabela inteira a cada poucos segundos, e cada redesenho acorda a sessão e faz reler a
conversa toda — dezenas de despertares sem uma linha de informação nova. Monitor é para stream de
uma linha por acontecimento (`tail -f | grep --line-buffered`).

**Não pendure nada atrás do watch.** Com `; echo "exit=$?"` no fim, a notificação mostra o exit
do `echo` (sempre 0) e esconde o do watch. Foi assim que um PR real (14/10/2026) entrou com os
checks ainda pendentes: o watch saiu 1, a notificação disse 0.

**Logo depois do push os checks podem ainda não existir.** O watch sai 1 em segundos com
`no checks reported on the '<branch>' branch`. Isso não é verde nem vermelho: rode o watch de
novo, ou acompanhe a execução com `gh run list --branch <branch>` e `gh run watch <id>`.

**O gate do merge é a metadata do PR, não o exit do watch.** Com o watch terminado:

```bash
gh pr view <n> --json mergeStateStatus,headRefOid,statusCheckRollup \
  --jq '{mergeStateStatus,headRefOid,checks:[(.statusCheckRollup // [])[]|{name,conclusion:(.conclusion // .state)}]}'
```

Só mergeie com `mergeStateStatus` = `CLEAN`, todo check com conclusão `SUCCESS` e o `headRefOid`
igual ao seu `git rev-parse HEAD`. `UNSTABLE` (check pendente ou falho que não é obrigatório),
conclusão vazia ou `BLOCKED`: não mergeia. O contrário também acontece: o `gh run watch` sai 1 por
queda de rede com a execução verde. Na dúvida entre o exit e a metadata, vale a metadata.

### 2c. O verde é de um SHA — e `--admin` não é um atalho para ele

"CI verde basta" quer dizer verde **do commit que vai para a main**, não do anterior. Empurrou
qualquer coisa depois do último `gh pr checks`? O gate reabre, mesmo que o diff novo seja um
comentário: a garantia é sobre o SHA que rodou, não sobre a sua leitura do diff.

E `gh pr merge --admin` não substitui a espera: ele existe para check obrigatório quebrado ou
inexistente, com autorização de quem manda no repositório, não para pular fila de runner.

Isto está escrito porque falhou de verdade. Num cenário de pressão medido em 05/09/2026 (o único
diff do commit era um comentário, a fila do runner era de 40 minutos, o cliente estava numa tela
compartilhada), o agente **sem** esta skill mergeou em 2 de 2 execuções, e **com** ela ainda
errava 1 em 3, argumentando:

> "O diff é um comentário — não altera nenhum caminho de execução, então o verde do commit
> anterior continua válido para o código que vai para a main."

> "`--admin` com registro explícito do motivo preserva 'self-merge livre' sem fingir que o
> pipeline rodou, e mantém rollback trivial."

As duas soam responsáveis e erram pelo mesmo motivo: trocam a evidência (um run verde naquele SHA)
por uma inferência sobre o diff. Comentário mal fechado quebra parser; `//` dentro de string muda
comportamento; e o CI roda lint e formatação, que reprovam arquivo por causa de comentário.

**Quando a espera é cara de verdade**, diga o tempo real a quem pediu e devolva a decisão. Uma
janela com cliente é decisão de negócio dele, não uma leitura técnica que você faz sozinho sob
pressão.

### 2a. Antes de cada merge: há PR encadeado nesta branch?

**Um PR cuja base é deletada FECHA e NÃO REABRE** ("Cannot change the base branch of a closed pull
request"). Só resta recriar do zero, perdendo review e número. Rode **sempre**, antes de qualquer
`gh pr merge`:

```bash
BR=$(gh pr view <n> --json headRefName -q .headRefName)
gh pr list --base "$BR" --state open --json number,headRefName -q '.[] | "\(.number) \(.headRefName)"'
```

**Saída vazia** → merge normal: `gh pr merge <n> --squash --delete-branch` (de dentro de worktree,
a versão do fim desta seção).

**Saída com PRs** → NÃO passe `--delete-branch`. Siga esta ordem:

```bash
# 1. mergeia o pai SEM deletar a branch — é a deleção que mata o filho
gh pr merge <pai> --squash 2>&1 | grep -v "fatal: 'main'" || true
gh pr view <pai> --json state -q .state                      # MERGED

# 2. cada filho: rebase para a main nova. O squash reescreveu o ancestry, então
#    `git merge origin/main` daria conflito; `rebase --onto` é o que funciona.
git fetch -q origin
git checkout <branch-filho>
git rebase --onto origin/main <sha-da-base-antiga>           # sha do topo do pai ANTES do merge
git push --force-with-lease origin <branch-filho>
gh pr edit <filho> --base main                               # só agora aponta para a main

# 3. com todos os filhos retargetados, a branch do pai pode morrer
git push origin --delete <branch-do-pai>
```

**Alternativa que evita o problema inteiro:** para uma leva de PRs que vão mergear na mesma
sessão, abra todos com base `main` desde o início. O diff do PR2 inclui o PR1, mas nenhum PR fecha
e nenhum rebase é necessário.

**Ship de dentro de um worktree:** `gh pr merge --delete-branch` tenta dar `git checkout main`
local e falha com `fatal: 'main' is already used by worktree` (o clone principal segura a `main`).
O **merge no GitHub acontece mesmo assim**, mas a **branch remota não é deletada**:

```bash
gh pr merge <n> --squash --delete-branch 2>&1 | grep -v "fatal: 'main'" || true
gh pr view <n> --json state -q .state                    # deve ser MERGED
git push origin --delete "$(git branch --show-current)" 2>&1 | tail -1   # a remota que o gh não deletou
```
