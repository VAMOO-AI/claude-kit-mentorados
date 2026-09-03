---
name: git-sync
description: >-
  Sincroniza o clone local e todos os worktrees com o GitHub de forma segura
  (fetch --prune + fast-forward only) e reporta o estado vs GitHub (worktrees,
  ahead/behind, PRs abertos). Use quando pedirem "/git-sync", "atualiza com o
  github", "sync github", "puxa o remote", "source control desatualizado", ou no
  INÍCIO/FIM de sessão num repo compartilhado ("vou mexer no projeto", "meu
  colega mexeu?", "tem PR aberto?"). Complementa a skill worktrees (isolamento).
---

> Derivada de `claude-config-team/skills/git-sync`. Ao divergir de propósito, diga aqui o quê e por quê.

# /git-sync — Atualizar local com o GitHub

Objetivo: deixar o clone e os worktrees **em dia com o remoto**, reportar o que a IDE mostra no Source Control, e opcionalmente listar PRs + dry-run de lixo (branches `gone`, worktrees mortos).

**Alvo do sync por checkout**: o upstream próprio da branch (`@{u}`) quando existir — é assim que commits de outra pessoa em `feat/x` chegam no seu worktree — senão `origin/<default>`. Commits só locais (ahead) **não** são problema: aparecem como "push pendente", nunca como skip.

Responda em **PT-BR**, direto. Cole output real dos comandos.

## Quando acionar

- Usuário pede atualizar/sync com GitHub, “puxar main”, “Sync Changes N↓”.
- Source Control da IDE mostra behind / worktree desatualizado.
- Início de feature (antes de branch nova): garantir `main` fresca.
- Fim de sessão: ver o que sobrou sujo (sem apagar sozinho).
- **Repo compartilhado — SEMPRE ao abrir e ao fechar a sessão** (ver “Modo time”).

## Modo time (2+ pessoas no mesmo repo)

Este é o caso em que o Claude Code Desktop cega o usuário: ele não mostra PR, não
mostra branch remota nova, não avisa que o colega mexeu nos mesmos arquivos. O
modo time preenche isso.

**Ativação: automática.** O script liga o modo time sozinho quando encontra ≥2
autores distintos em `origin/<default>` nos últimos 30 dias. Force com `--team`
(ex.: repo novo, colega ainda sem commit na default) ou desligue com `--no-team`.

### Protocolo de sessão (é isso que você roda)

**Ao abrir — antes de escrever qualquer linha:**

```bash
S="${CLAUDE_PLUGIN_ROOT}/skills/git-sync/scripts/git-sync.sh"        # plugin: o Claude Code preenche ao carregar a skill
[ -f "$S" ] || S="$HOME/.claude/skills/git-sync/scripts/git-sync.sh"  # instalação antiga pelo install.sh
bash "$S"
```

Leia nesta ordem e não comece a codar antes de zerar:

1. `### avisos (ação sua)` — cada `!` é bloqueante até você decidir o que fazer.
2. `--- risco de conflito ---` — se listar arquivo, sincronize com a default **antes**
   de tocar nele. É o único jeito de não descobrir o conflito na hora do PR.
3. `--- novidades em origin/<default> ---` e `### PRs abertos` — o que o colega fez
   e o que está em revisão. Se há PR aberto tocando sua área, fale com ele antes.
4. `--- branches remotas ativas ---` — antes de criar `feat/x`, veja se já existe.

**Ao fechar:** rode de novo. Nenhum aviso de *“commit(s) sem push”* / *“NUNCA foi ao
GitHub”* pode sobrar — trabalho que não subiu não existe para o outro.

### Regras de convivência (as duas pessoas seguem)

| Situação | O que fazer |
|---|---|
| Vai começar tarefa nova | `git-sync` primeiro, **sempre**, e só então crie a branch |
| Branch nova | `feat/<escopo>-<seu-nome>` — nomes distintos evitam a colisão silenciosa |
| Aviso “DIVERGED … MESMA branch” | os dois commitaram no mesmo lugar: `git pull --rebase` com working tree limpa. **Nunca** `push --force` |
| Aviso “N atrás de origin/main” | atualize antes de continuar (`git merge origin/main`); quanto mais esperar, pior o conflito |
| Aviso “existe origin/\<branch\>” | o outro já criou essa branch: `git branch --set-upstream-to=origin/<branch>` ou renomeie a sua |
| Terminou um pedaço | commit + **push no mesmo dia**; branch parada local é conflito acumulando |
| Vai mexer em arquivo listado em “risco de conflito” | sincronize primeiro; se o outro tem PR aberto nele, espere o merge |

### Pré-requisito: o `gh`

`gh` é o que dá visibilidade de PR. Sem ele o relatório funciona, mas cego para revisão:

```bash
gh --version || brew install gh     # macOS
gh auth status || gh auth login     # precisa de acesso ao repo
```

Se `gh auth status` falhar, o script reporta e segue — não trava a sessão.

## Regras duras (nunca violar)

1. **Só fast-forward** — `git pull --ff-only` / `git merge --ff-only`. Nunca `pull` com merge commit, nunca `rebase` automático, nunca `reset --hard`.
2. **Não commita** untracked/staged. Não faz `git add`. Não inventa mensagem de commit.
3. **Não apaga** worktree/branch/remoto sem pedido explícito (`--apply` / “pode limpar”). Default de cleanup = **dry-run**.
4. **Não force-push**, não `push --force`, não altera remoto.
5. **Working tree suja** (modified/staged, não só untracked) → **não puxa** nessa checkout; reporta e segue nos outros.
6. **Untracked sozinho** não bloqueia ff-only (git permite), mas **reporta** no final e **não** oferece commitar.
7. Clone principal em `main` com outra sessão ativa: respeitar a skill `worktrees` / hook — só atualizar com ff-only se clean o bastante; se o hook bloquear, reportar.
8. Preferir o script helper (abaixo). Se falhar, rodar os passos manuais equivalentes.
9. **Repo de time**: se `### avisos` vier não-vazio, mostre os avisos **antes** de qualquer outra coisa e trate como bloqueio até o usuário decidir. Não comece a implementar por cima de branch atrás/divergida — o conflito só cresce. `git pull --rebase` para resolver divergência é sugestão ao usuário, **nunca** execução automática (regra 1).

## Preferência: script helper

O script vem junto com a skill, dentro do plugin — o Claude Code preenche
`${CLAUDE_PLUGIN_ROOT}` ao carregar a skill. As outras duas linhas cobrem a
instalação antiga pelo `install.sh` e outro agente apontando por symlink:

```bash
S="${CLAUDE_PLUGIN_ROOT}/skills/git-sync/scripts/git-sync.sh"
[ -f "$S" ] || S="$HOME/.claude/skills/git-sync/scripts/git-sync.sh"
[ -f "$S" ] || S="$HOME/.agents/skills/git-sync/scripts/git-sync.sh"
bash "$S"
```

Flags:

| Flag | Efeito |
|---|---|
| (nenhuma) | fetch + status + ff-only em checkouts elegíveis + relatório (+ modo time se auto-detectado) |
| `--status-only` | só fetch + relatório (não mexe em HEAD) |
| `--no-pr` | pula `gh pr list` |
| `--team` | força modo time (quem mudou o quê, PR com autor/mergeable, branches ativas, risco de conflito) |
| `--no-team` | desliga o modo time mesmo em repo multi-autor |
| `--since N` | janela de atividade do modo time em dias (default 14) |
| `--cleanup-dry-run` | lista branches `gone` e worktrees candidatos a remoção (não apaga) |
| `--cleanup-apply` | **perigoso** — só se o usuário pediu “aplica limpeza”. Remove worktrees **clean + mergeados + sem sessão viva** (`git worktree remove`, nunca `--force`) e depois as branches `gone`: `-d` primeiro, e `-D` **só quando o `gh` confirma um PR mergeado com aquela head** (squash merge quebra a ancestralidade — sem isso o cleanup skipa 100% das branches). Branch sem PR encontrado, ou `gh` indisponível, é sempre preservada |
| `--default-branch <nome>` | override (default: detecta `origin/HEAD` ou `main`/`master`) |
| `--cwd <path>` | roda a partir desse path (útil em multi-root IDE) |

Exemplos (`S` resolvido como acima):

```bash
# Sync completo (padrão)
bash "$S"

# Só ver o estado
bash "$S" --status-only

# Abrindo sessão num repo compartilhado (força o modo time)
bash "$S" --team

# Incluir dry-run de lixo
bash "$S" --cleanup-dry-run

# Usuário disse "pode limpar o que for dry-run seguro"
bash "$S" --cleanup-apply
```

Se o script não existir ou falhar no shebang, execute a **sequência manual** abaixo.

---

## Sequência manual (fallback)

### 0. Pre-flight

```bash
pwd
git rev-parse --show-toplevel 2>/dev/null || { echo "NÃO É REPO GIT"; exit 1; }
git remote -v
git branch --show-current
git status -sb
```

### 1. Fetch + prune

```bash
git fetch --prune origin
# se existir upstream default:
git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p'
```

Detectar default branch:

```bash
DEFAULT=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
DEFAULT=${DEFAULT:-main}
git rev-parse --verify "origin/$DEFAULT" >/dev/null 2>&1 || DEFAULT=master
echo "DEFAULT=$DEFAULT"
```

### 2. Inventário de worktrees

```bash
git worktree list --porcelain
# ou legível:
git worktree list
```

Para **cada** worktree path:

```bash
cd <path>
git status -sb
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
# ahead/behind vs origin/DEFAULT (e vs upstream se houver):
git rev-list --left-right --count "HEAD...origin/$DEFAULT" 2>/dev/null
# dirty?
git status --porcelain
```

Classificar cada checkout (alvo = `@{u}` se existir, senão `origin/$DEFAULT`):

| Estado | Ação |
|---|---|
| clean + behind do alvo (ahead 0) | `git merge --ff-only <alvo>` |
| clean + ahead do alvo (behind 0) | nada a puxar — reportar "push pendente", **não** é skip |
| clean + diverged do alvo | **NÃO** rebase; reportar divergência |
| dirty (M/A/D staged ou unstaged) | skip pull; listar arquivos |
| only untracked (`??`) | pode ff; reportar untracked no final |
| detached HEAD | skip; não mover HEAD solto (e fora dos candidatos de cleanup) |
| upstream configurado mas **gone** (pruned) | não mexer — branch morta, candidata a cleanup |
| locked worktree | se clean, ainda pode ff; reportar locked (e se o pid do lock estiver morto, dizer que é stale) |
| branch sem upstream, ancestral de `origin/$DEFAULT` | ff para `origin/$DEFAULT` se clean |

**Nunca** `checkout` no clone principal só para “alinhar” se isso derrubar outra sessão. Prefira atualizar o worktree/branch **já checkoutado**.

### 3. Atualizar o que for seguro

No clone principal (se em `$DEFAULT` e elegível):

```bash
git merge --ff-only "origin/$DEFAULT"
```

Em cada worktree elegível (mesmo critério). Preferir `merge --ff-only` no ref remoto em vez de trocar de branch.

### 4. PRs abertos (opcional — default ON)

```bash
gh pr list --limit 20 2>&1
# se gh falhar no name do remote (auth/scope), reportar e seguir sem bloquear
```

### 4b. Time (só em repo compartilhado)

```bash
# quantos autores distintos na default nos últimos 30d (>=2 → repo de time)
git log "origin/$DEFAULT" --since='30 days ago' --format='%an <%ae>' | sort -u

# o que entrou na default desde a base da minha branch
BASE=$(git merge-base HEAD "origin/$DEFAULT")
git log --format='%h %an %ar %s' "$BASE..origin/$DEFAULT"

# branches remotas ativas (quem está em quê)
git for-each-ref --sort=-committerdate refs/remotes/origin \
  --format='%(refname:short) | %(committerdate:relative) | %(authorname) | %(subject)'

# PRs com o que importa pra decidir
gh pr list --state open --limit 30 \
  --json number,title,author,headRefName,isDraft,mergeable,reviewDecision,updatedAt

# risco de conflito: arquivos tocados dos dois lados
comm -12 \
  <( { git diff --name-only "$BASE" HEAD; git diff --name-only; git diff --cached --name-only
       git ls-files --others --exclude-standard; } | sort -u ) \
  <( git diff --name-only "$BASE" "origin/$DEFAULT" | sort -u )

# branches locais que colidem com remota homônima ou que nunca subiram
git for-each-ref --format='%(refname:short)|%(upstream:short)|%(upstream:track)' refs/heads
```

### 5. Cleanup dry-run (default OFF; ligar com flag ou se usuário pediu “limpa/lixo”)

```bash
# branches locais cujo upstream sumiu (não use grep em `branch -vv` —
# mensagem de commit pode conter ": gone]" e dar falso positivo)
git for-each-ref --format='%(refname:short)|%(upstream:track)' refs/heads | awk -F'|' '$2=="[gone]"{print $1}'

# branches locais atrás demais / ship-* legadas
git branch -vv

# worktrees
git worktree list
```

Candidatos típicos a remoção (só listar no dry-run):

- Branch local com `[origin/…: gone]` e working tree clean
- Worktree em branch `ship-*` / PR já mergeado, clean, HEAD == `origin/$DEFAULT`
- `tmp-main` e similares bem atrás de `origin/$DEFAULT`

**Apply** (só com pedido explícito) — worktrees primeiro, para liberar as branches deles:

```bash
# worktree candidato (clean + mergeado por ancestralidade OU por PR + sem sessão viva)
git worktree remove <path>      # falha se dirty — não force
git worktree prune

# branch gone, não checkoutada em nenhum worktree restante
git branch -d <branch>          # -d recusa se não mergeada — bom
# se squash-merge e -d recusar: confirmar PR merged via gh, aí git branch -D com OK do user

git fetch --prune
```

Se o worktree for gerenciado por outra ferramenta, não `rm -rf` no path — use `git worktree remove`.

### 6. Relatório final (obrigatório)

**Se o script rodou com sucesso, o output dele JÁ É o relatório** — cole-o (ou os trechos relevantes) e acrescente só a seção `PENDENTE:`. Não re-tabule no template abaixo; ele serve para o fallback manual.

```
## git-sync

Repo:     <toplevel>
Remote:   <url>
Default:  <main|master|...>
Fetch:    ok | erro

### Checkouts
| path | branch | HEAD | vs origin/<default> | vs upstream | dirty | ação |
|---|---|---|---|---|---|---|
| ... | main | ebed769 | even | even | 2 untracked | none / ff 6 commits |

### Atualizados (ff-only)
- <path>: <old> → <new> (de <alvo>)

### Skipped
- <path>: reason (dirty: … / diverged vs alvo / detached / locked+dirty)

### Avisos (ação sua)
- ! <branch>: N atrás de origin/<default> / commits sem push / DIVERGED / branch homônima no remoto

### Time (só em repo compartilhado)
- autores na default (30d), novidades desde a sua base, branches remotas ativas,
  PRs abertos (autor/mergeable/review) e mergeados na janela, risco de conflito

### Untracked / local-only (não commitados)
- path/file …

### Stashes (compartilhados entre worktrees)
- stash@{0}: …

### PRs abertos
- #n title (branch) | gh indisponível: <erro>

### Cleanup (dry-run | apply | skipped)
- branches gone: …
- worktrees candidatos: …
- removidos (só apply): …

### Pendente
- o que o user ainda precisa decidir
```

---

## Integração com outras skills

| Skill | Relação |
|---|---|
| `worktrees` | isolamento de write; git-sync **não** cria worktree de feature |
| `ship` | deploy; git-sync roda *antes* de abrir feature ou *depois* de merge alheio |

## Anti-patterns

- `git pull` sem `--ff-only` em main compartilhada
- `git add -A` / commit dos untracked “pra limpar o status”
- Apagar worktree locked com sessão ativa — mas `locked` **não** é prova de sessão viva:
  o lock traz o pid (`.git/worktrees/<nome>/locked`) e fica pra trás quando a sessão morre.
  O script confere com `kill -0` e só destrava o que está morto, no `--cleanup-apply`.
  Sem pid legível no motivo, assume vivo e não toca
- Assumir que “Sync Changes 6↓” na IDE é o clone principal — **pode ser worktree**
- Copiar arquivos do clone principal para worktree “pra sincronizar” (use `origin/*`)

Em repo de time, mais:

- Começar a codar sem rodar `git-sync` — é assim que nasce o conflito de 200 linhas
- Deixar branch local dias sem push “porque ainda não terminei”: o outro trabalha às cegas
- Resolver `DIVERGED` com `push --force` — apaga o commit do colega
- Criar `feat/x` sem checar se `origin/feat/x` já existe
- Trabalhar direto na `main` compartilhada
- Concluir “está tudo em dia” só porque o `fetch` passou: **`### avisos` tem que estar vazio**

## Onde a skill vive

Instalada como plugin (o caminho recomendado), a skill fica dentro do plugin, no
cache do marketplace — é para lá que `${CLAUDE_PLUGIN_ROOT}` aponta:

```text
${CLAUDE_PLUGIN_ROOT}/skills/git-sync/
  SKILL.md
  scripts/git-sync.sh
```

A instalação antiga pelo `install.sh` deixava a mesma pasta em
`~/.claude/skills/git-sync/` — é o fallback dos comandos acima. Se você usa outro
agente além do Claude Code, pode apontar um symlink da pasta dele para cá — a
skill não depende de nada específico do harness.
