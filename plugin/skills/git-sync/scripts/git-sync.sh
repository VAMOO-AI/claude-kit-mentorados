#!/usr/bin/env bash
# git-sync.sh — fetch + report + optional ff-only sync of main clone + worktrees.
# Safe by default. Never force-push, never commit, never hard-reset.
# Sync target per checkout: the branch's own upstream (@{u}) when it exists,
# otherwise origin/<default>.
set -euo pipefail

STATUS_ONLY=0
NO_PR=0
CLEANUP_DRY=0
CLEANUP_APPLY=0
DEFAULT_BRANCH=""
CWD=""
TEAM=-1          # -1 auto | 0 off | 1 on
TEAM_SINCE_DAYS=14

usage() {
  cat <<'EOF'
Usage: git-sync.sh [options]

  (default)           fetch --prune, report, ff-only eligible checkouts
  --status-only       fetch + report only (no HEAD moves)
  --no-pr             skip gh pr list
  --team              force team mode (shared repo: who changed what, PR detail,
                      conflict risk vs origin/default)
  --no-team           force team mode off (default is auto-detect: >=2 authors
                      in origin/<default> over the last 30 days)
  --since DAYS        activity window for team mode (default 14)
  --cleanup-dry-run   list gone branches / removable worktree candidates
  --cleanup-apply     delete gone branches provadas (-d; -D só com PR merged
                      confirmado no gh) + remove worktrees clean e mergeados
                      (nunca --force; lock de sessão morta é destravado)
  --default-branch B  override default branch (else origin/HEAD, main, master)
  --cwd PATH          run from PATH
  -h, --help          this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --status-only) STATUS_ONLY=1; shift ;;
    --no-pr) NO_PR=1; shift ;;
    --team) TEAM=1; shift ;;
    --no-team) TEAM=0; shift ;;
    --since) TEAM_SINCE_DAYS="${2:-14}"; shift 2 ;;
    --cleanup-dry-run) CLEANUP_DRY=1; shift ;;
    --cleanup-apply) CLEANUP_APPLY=1; CLEANUP_DRY=1; shift ;;
    --default-branch) DEFAULT_BRANCH="${2:-}"; shift 2 ;;
    --cwd) CWD="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -n "$CWD" ]]; then
  cd "$CWD"
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not a git repository ($(pwd))"
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
COMMON="$(git rev-parse --git-common-dir)"
if [[ "$COMMON" != /* ]]; then
  COMMON="$ROOT/$COMMON"
fi
COMMON="$(cd "$COMMON" && pwd)"

hr() { printf '%s\n' "------------------------------------------------------------"; }

echo "## git-sync"
echo "cwd:      $(pwd)"
echo "root:     $ROOT"
echo "git-dir:  $COMMON"
echo "remote:   $(git remote get-url origin 2>/dev/null || echo '(no origin)')"
echo "time:     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
hr

echo "### fetch --prune origin"
if ! git fetch --prune origin 2>&1; then
  echo "WARN: fetch failed — continuing with last-known remote refs"
fi
hr

if [[ -z "$DEFAULT_BRANCH" ]]; then
  DEFAULT_BRANCH="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)"
fi
if [[ -z "$DEFAULT_BRANCH" ]]; then
  if git rev-parse --verify origin/main >/dev/null 2>&1; then
    DEFAULT_BRANCH=main
  elif git rev-parse --verify origin/master >/dev/null 2>&1; then
    DEFAULT_BRANCH=master
  else
    DEFAULT_BRANCH=main
  fi
fi
ORIGIN_DEFAULT="origin/$DEFAULT_BRANCH"
if ! git rev-parse --verify "$ORIGIN_DEFAULT" >/dev/null 2>&1; then
  echo "ERROR: missing $ORIGIN_DEFAULT after fetch"
  exit 1
fi
DEFAULT_SHA="$(git rev-parse --short "$ORIGIN_DEFAULT")"
echo "default:  $DEFAULT_BRANCH ($DEFAULT_SHA = $ORIGIN_DEFAULT)"

# Team auto-detect: >=2 autores distintos em origin/<default> nos últimos 30 dias.
TEAM_AUTHORS="$(git log "$ORIGIN_DEFAULT" --since='30 days ago' --format='%an <%ae>' 2>/dev/null | sort -u || true)"
TEAM_AUTHOR_N="$(printf '%s\n' "$TEAM_AUTHORS" | grep -c . || true)"
TEAM_AUTHOR_N="${TEAM_AUTHOR_N:-0}"
if [[ "$TEAM" -eq -1 ]]; then
  if [[ "$TEAM_AUTHOR_N" -ge 2 ]]; then TEAM=1; else TEAM=0; fi
  echo "team:     $([[ $TEAM -eq 1 ]] && echo 'ON (auto)' || echo 'off (auto)') — $TEAM_AUTHOR_N autor(es) em $ORIGIN_DEFAULT nos últimos 30d"
else
  echo "team:     $([[ $TEAM -eq 1 ]] && echo 'ON (forçado)' || echo 'off (forçado)')"
fi
hr

# Collect worktree paths (absolute) — bash 3.2 compatible (no mapfile).
# First entry is always the main worktree.
WT_PATHS=()
while IFS= read -r _wt; do
  [[ -n "$_wt" ]] && WT_PATHS+=("$_wt")
done < <(git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}')
if [[ ${#WT_PATHS[@]} -eq 0 ]]; then
  WT_PATHS=("$ROOT")
fi
MAIN_WT="${WT_PATHS[0]}"

# Locked worktrees — single porcelain pass.
# Guardamos "path<TAB>motivo" porque o lock do Claude traz o pid da sessão que travou:
# quando esse processo morre o lock fica pra trás e imunizaria o worktree pra sempre.
LOCKED_INFO="$(git worktree list --porcelain \
  | awk '/^worktree /{p=substr($0,10)} /^locked/{r=(length($0)>6)?substr($0,8):""; print p "\t" r}')"
is_locked() { printf '%s\n' "$LOCKED_INFO" | cut -f1 | grep -qxF "$1"; }
lock_reason() { printf '%s\n' "$LOCKED_INFO" | awk -F'\t' -v w="$1" '$1==w{print $2; exit}'; }

# Lock morto = tem "pid N" no motivo e o processo N não existe mais.
# Sem pid extraível assumimos vivo (conservador: nunca destrave lock de terceiro).
lock_is_stale() {
  local _r _pid
  _r="$(lock_reason "$1")"
  _pid="$(printf '%s' "$_r" | sed -n -E 's/.*[Pp]id[[:space:]]+([0-9]+).*/\1/p')"
  [[ -n "$_pid" ]] || return 1
  kill -0 "$_pid" 2>/dev/null && return 1
  STALE_PID="$_pid"
  return 0
}

UPDATED=()
SKIPPED=()
UNTRACKED_LINES=()
WARNS=()

is_dirty_tracked() {
  # returns 0 if there are tracked modifications (staged or unstaged), ignoring untracked
  local path="$1"
  git -C "$path" status --porcelain 2>/dev/null | grep -v '^??' | grep -q .
}

count_untracked() {
  local path="$1"
  git -C "$path" status --porcelain 2>/dev/null | grep -c '^??' || true
}

counts_vs() {
  # path ref -> "ahead behind" ("? ?" if not comparable)
  local out
  out="$(git -C "$1" rev-list --left-right --count "HEAD...$2" 2>/dev/null | tr '\t' ' ')" || out=""
  if [[ -n "$out" ]]; then printf '%s\n' "$out"; else printf '? ?\n'; fi
}

fmt_vs() {
  local a="$1" b="$2"
  if [[ "$a" == "?" || "$b" == "?" ]]; then echo "?"
  elif [[ "$a" == "0" && "$b" == "0" ]]; then echo "even"
  elif [[ "$b" == "0" ]]; then echo "ahead $a"
  elif [[ "$a" == "0" ]]; then echo "behind $b"
  else echo "diverged a$a/b$b"
  fi
}

echo "### checkouts"
printf '%-60s %-22s %-10s %-16s %-16s %-12s %s\n' "PATH" "BRANCH" "HEAD" "vs $ORIGIN_DEFAULT" "vs upstream" "DIRTY" "ACTION"
printf '%-60s %-22s %-10s %-16s %-16s %-12s %s\n' "----" "------" "----" "----------------" "-----------" "-----" "------"

for wt in "${WT_PATHS[@]}"; do
  [[ -d "$wt" ]] || continue
  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  head_s="$(git -C "$wt" rev-parse --short HEAD 2>/dev/null || echo '?')"

  read -r d_ahead d_behind <<<"$(counts_vs "$wt" "$ORIGIN_DEFAULT")"
  vs_def="$(fmt_vs "$d_ahead" "$d_behind")"

  upstream="$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  upstream_gone=0
  track="-"
  u_ahead="?"
  u_behind="?"
  if [[ -n "$upstream" ]] && ! git -C "$wt" rev-parse --verify --quiet "$upstream" >/dev/null 2>&1; then
    # upstream configurado mas a ref não existe mais (pruned) — branch gone
    upstream=""
    upstream_gone=1
    track="gone"
  fi
  if [[ -n "$upstream" ]]; then
    read -r u_ahead u_behind <<<"$(counts_vs "$wt" "$upstream")"
    track="$(fmt_vs "$u_ahead" "$u_behind")"
  fi

  dirty_flag="clean"
  ut_n="$(count_untracked "$wt")"
  if is_dirty_tracked "$wt"; then
    dirty_flag="DIRTY"
  elif [[ "${ut_n:-0}" -gt 0 ]]; then
    dirty_flag="${ut_n} untracked"
  fi

  locked=""
  if is_locked "$wt"; then
    locked=" locked"
  fi

  # Sync target: the branch's own upstream when it has one, else origin/default
  target="$ORIGIN_DEFAULT"
  t_ahead="$d_ahead"
  t_behind="$d_behind"
  if [[ -n "$upstream" && "$upstream" != "$ORIGIN_DEFAULT" ]]; then
    target="$upstream"
    t_ahead="$u_ahead"
    t_behind="$u_behind"
  fi

  action="none"
  if [[ "$STATUS_ONLY" -eq 1 ]]; then
    action="status-only"
  elif [[ "$branch" == "HEAD" ]]; then
    action="skip:detached"
    SKIPPED+=("$wt: detached HEAD — não movo HEAD solto")
  elif [[ "$dirty_flag" == "DIRTY" ]]; then
    action="skip:dirty"
    SKIPPED+=("$wt ($branch): dirty tracked changes")
  elif [[ "$upstream_gone" -eq 1 ]]; then
    # branch morta esperando cleanup — não mexer
    action="none (upstream gone — candidata a cleanup)"
  elif [[ "$t_ahead" == "?" || "$t_behind" == "?" ]]; then
    action="skip:no-compare"
    SKIPPED+=("$wt ($branch): sem base de comparação com $target")
  elif [[ "$t_ahead" == "0" && "$t_behind" == "0" ]]; then
    action="even"
  elif [[ "$t_behind" == "0" ]]; then
    # only local commits — nothing to pull; not a problem, don't list as skipped
    if [[ "$target" == "$ORIGIN_DEFAULT" && -z "$upstream" ]]; then
      action="none (ahead $t_ahead, sem upstream)"
    else
      action="none (ahead $t_ahead — push pendente)"
    fi
  elif [[ "$t_ahead" == "0" ]]; then
    old_sha="$head_s"
    merge_err=""
    if merge_err="$(git -C "$wt" merge --ff-only "$target" 2>&1 >/dev/null)"; then
      new_sha="$(git -C "$wt" rev-parse --short HEAD)"
      action="ff ${old_sha}→${new_sha} ($target)"
      UPDATED+=("$wt ($branch): $old_sha → $new_sha (de $target)")
      head_s="$new_sha"
      read -r d_ahead d_behind <<<"$(counts_vs "$wt" "$ORIGIN_DEFAULT")"
      vs_def="$(fmt_vs "$d_ahead" "$d_behind")"
      if [[ -n "$upstream" ]]; then
        read -r u_ahead u_behind <<<"$(counts_vs "$wt" "$upstream")"
        track="$(fmt_vs "$u_ahead" "$u_behind")"
      fi
    else
      action="skip:ff-failed"
      SKIPPED+=("$wt ($branch): ff-only para $target falhou — ${merge_err:-sem detalhe}")
    fi
  else
    action="skip:diverged"
    SKIPPED+=("$wt ($branch): diverged a$t_ahead/b$t_behind vs $target — resolver manualmente (sem rebase automático)")
  fi

  # --- avisos acionáveis (o que a IDE não mostra) ---
  if [[ "$branch" != "HEAD" ]]; then
    # 1) feature branch ficou para trás da default → conflito futuro no PR
    if [[ "$branch" != "$DEFAULT_BRANCH" && "$d_behind" != "?" && "${d_behind:-0}" -gt 0 ]]; then
      WARNS+=("$branch ($wt): $d_behind commit(s) atrás de $ORIGIN_DEFAULT — atualize ANTES de continuar: git -C '$wt' merge $ORIGIN_DEFAULT (ou rebase, se a branch ainda não foi publicada)")
    fi
    # 2) commits locais que o colega não enxerga
    if [[ -n "$upstream" && "$u_ahead" != "?" && "${u_ahead:-0}" -gt 0 && "${u_behind:-0}" -eq 0 ]]; then
      WARNS+=("$branch ($wt): $u_ahead commit(s) local(is) sem push — o time não enxerga seu trabalho: git -C '$wt' push")
    fi
    # 3) os dois commitaram na mesma branch
    if [[ -n "$upstream" && "$u_ahead" != "?" && "${u_ahead:-0}" -gt 0 && "${u_behind:-0}" -gt 0 ]]; then
      WARNS+=("$branch ($wt): DIVERGED do $upstream (a$u_ahead/b$u_behind) — outra pessoa commitou na MESMA branch. Com working tree limpa: git -C '$wt' pull --rebase (ou merge). Nunca force-push.")
    fi
    # 4) sujo e atrás ao mesmo tempo: não dá pra puxar
    if [[ "$dirty_flag" == "DIRTY" && "$t_behind" != "?" && "${t_behind:-0}" -gt 0 ]]; then
      WARNS+=("$branch ($wt): dirty E $t_behind atrás de $target — commite ou 'git stash' antes de sincronizar")
    fi
  fi

  printf '%-60s %-22s %-10s %-16s %-16s %-12s %s%s\n' \
    "$wt" "$branch" "$head_s" "$vs_def" "$track" "$dirty_flag" "$action" "$locked"

  # collect untracked paths (relative to that worktree)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    file="${line#?? }"
    UNTRACKED_LINES+=("$wt :: $file")
  done < <(git -C "$wt" status --porcelain 2>/dev/null | grep '^??' || true)
done
hr

echo "### updated (ff-only)"
if [[ ${#UPDATED[@]} -eq 0 ]]; then
  echo "(none)"
else
  for u in "${UPDATED[@]}"; do echo "- $u"; done
fi
hr

echo "### skipped"
if [[ ${#SKIPPED[@]} -eq 0 ]]; then
  echo "(none)"
else
  for s in "${SKIPPED[@]}"; do echo "- $s"; done
fi
hr

# Varredura de TODAS as branches locais (inclusive as não checkoutadas em worktree).
# Pega o caso clássico de time: os dois criam a mesma branch, ou alguém trabalha
# dias numa branch que nunca foi ao GitHub.
CHECKED_OUT_BR="$(git worktree list --porcelain | awk '/^branch /{sub(/^branch refs\/heads\//,""); print}')"
while IFS='|' read -r lb lup ltrack; do
  [[ -z "$lb" ]] && continue
  if [[ -z "$lup" ]]; then
    # sem upstream — o loop de checkouts não avalia isso, então vale para toda branch local
    if git rev-parse --verify --quiet "refs/remotes/origin/$lb" >/dev/null 2>&1; then
      WARNS+=("branch local '$lb' NÃO trackeia origin/$lb, que já existe no GitHub — outra pessoa pode estar nela. Ligue o upstream antes de commitar: git branch --set-upstream-to=origin/$lb $lb")
    else
      lb_ahead="$(git rev-list --count "$ORIGIN_DEFAULT..$lb" 2>/dev/null || echo 0)"
      if [[ "${lb_ahead:-0}" -gt 0 ]]; then
        WARNS+=("branch local '$lb' tem $lb_ahead commit(s) e NUNCA foi ao GitHub — publique: git push -u origin $lb")
      fi
    fi
    continue
  fi
  # com upstream: só as NÃO checkoutadas (as checkoutadas já foram avaliadas acima)
  printf '%s\n' "$CHECKED_OUT_BR" | grep -qxF "$lb" && continue
  [[ "$ltrack" == "[gone]" ]] && continue   # branch morta — assunto do cleanup
  lb_cnt="$(git rev-list --left-right --count "$lb...$lup" 2>/dev/null | tr '\t' ' ' || true)"
  read -r lb_a lb_b <<<"${lb_cnt:-0 0}"
  if [[ "${lb_a:-0}" -gt 0 && "${lb_b:-0}" -gt 0 ]]; then
    WARNS+=("branch '$lb' (não checkoutada) DIVERGED de $lup (a$lb_a/b$lb_b) — alguém commitou nela pelo GitHub. Resolva ao entrar nela: git checkout $lb && git pull --rebase")
  elif [[ "${lb_a:-0}" -gt 0 ]]; then
    WARNS+=("branch '$lb' (não checkoutada) tem $lb_a commit(s) sem push — o time não enxerga: git push origin $lb")
  elif [[ "${lb_b:-0}" -gt 0 ]]; then
    WARNS+=("branch '$lb' (não checkoutada) está $lb_b atrás de $lup — atualize ao entrar nela")
  fi
done < <(git for-each-ref --format='%(refname:short)|%(upstream:short)|%(upstream:track)' refs/heads)

echo "### avisos (ação sua)"
if [[ ${#WARNS[@]} -eq 0 ]]; then
  echo "(nenhum — pode trabalhar)"
else
  for w in "${WARNS[@]}"; do echo "! $w"; done
fi
hr

echo "### untracked / local-only (not committed)"
if [[ ${#UNTRACKED_LINES[@]} -eq 0 ]]; then
  echo "(none)"
else
  for u in "${UNTRACKED_LINES[@]}"; do echo "- $u"; done
fi
hr

echo "### stashes (compartilhados entre os worktrees)"
STASH_LIST="$(git stash list 2>/dev/null || true)"
if [[ -z "$STASH_LIST" ]]; then
  echo "(none)"
else
  printf '%s\n' "$STASH_LIST"
fi
hr

if [[ "$NO_PR" -eq 0 ]]; then
  echo "### PRs abertos (gh)"
  if command -v gh >/dev/null 2>&1; then
    if [[ "$TEAM" -eq 1 ]]; then
      PR_FIELDS='number,title,author,headRefName,baseRefName,isDraft,mergeable,reviewDecision,updatedAt'
      PR_JQ='.[] | "  #\(.number) \(if .isDraft then "[DRAFT] " else "" end)\(.title)\n        \(.headRefName) → \(.baseRefName) | autor=\(.author.login) | mergeable=\(.mergeable) | review=\(.reviewDecision // "—") | atualizado=\(.updatedAt)"'
      if PR_OUT="$(gh pr list --state open --limit 30 --json "$PR_FIELDS" --jq "$PR_JQ" 2>&1)"; then
        if [[ -n "$PR_OUT" ]]; then printf '%s\n' "$PR_OUT"; else echo "  (nenhum PR aberto)"; fi
      else
        echo "  (gh pr list falhou — rode 'gh auth status' e confirme acesso ao repo)"
        printf '  %s\n' "$PR_OUT"
      fi
    else
      if PR_OUT="$(gh pr list --limit 20 2>&1)"; then
        if [[ -n "$PR_OUT" ]]; then printf '%s\n' "$PR_OUT"; else echo "  (nenhum PR aberto)"; fi
      else
        echo "(gh pr list failed — check auth/repo visibility)"
        printf '  %s\n' "$PR_OUT"
      fi
    fi
  else
    echo "(gh não instalado — sem visibilidade de PR. Instale: brew install gh && gh auth login)"
  fi
  hr
fi

if [[ "$TEAM" -eq 1 ]]; then
  echo "### time (repo compartilhado)"

  ME_NAME="$(git config user.name 2>/dev/null || echo '?')"
  ME_MAIL="$(git config user.email 2>/dev/null || echo '?')"
  GH_LOGIN=""
  if command -v gh >/dev/null 2>&1; then
    GH_LOGIN="$(gh api user -q .login 2>/dev/null || true)"
  fi
  echo "eu:       $ME_NAME <$ME_MAIL>${GH_LOGIN:+ | gh: $GH_LOGIN}"
  echo "autores em $ORIGIN_DEFAULT (30d): $TEAM_AUTHOR_N"
  printf '%s\n' "$TEAM_AUTHORS" | sed 's/^/  - /'
  echo

  CUR_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  BASE="$(git merge-base HEAD "$ORIGIN_DEFAULT" 2>/dev/null || true)"

  echo "--- novidades em $ORIGIN_DEFAULT desde a base de '$CUR_BRANCH' ---"
  if [[ -z "$BASE" ]]; then
    echo "  (sem base comum — não dá pra comparar)"
  else
    NEW_LOG="$(git log --format='  %h  %<(18,trunc)%an %<(15,trunc)%ar %s' "$BASE..$ORIGIN_DEFAULT" 2>/dev/null | awk 'NR<=25' || true)"
    if [[ -n "$NEW_LOG" ]]; then
      printf '%s\n' "$NEW_LOG"
    else
      echo "  (nenhum — você está na ponta da $DEFAULT_BRANCH)"
    fi
  fi
  echo

  echo "--- branches remotas ativas (últimos ${TEAM_SINCE_DAYS}d) ---"
  CUTOFF="$(date -u -v-"${TEAM_SINCE_DAYS}"d +%s 2>/dev/null || date -u -d "${TEAM_SINCE_DAYS} days ago" +%s 2>/dev/null || echo 0)"
  ACTIVE_BR="$(git for-each-ref --sort=-committerdate refs/remotes/origin \
      --format='%(refname:short)|%(committerdate:unix)|%(committerdate:relative)|%(authorname)|%(subject)' 2>/dev/null \
    | awk -F'|' -v cutoff="${CUTOFF:-0}" '
        $1 != "origin/HEAD" && $1 != "origin" && ($2+0) >= cutoff {
          rest = $5; for (i = 6; i <= NF; i++) rest = rest "|" $i
          printf "  %-34s %-17s %-20s %s\n", $1, $3, $4, rest
        }' \
    | awk 'NR<=25' || true)"
  if [[ -n "$ACTIVE_BR" ]]; then printf '%s\n' "$ACTIVE_BR"; else echo "  (nenhuma)"; fi
  echo

  if [[ "$NO_PR" -eq 0 ]] && command -v gh >/dev/null 2>&1; then
    echo "--- PRs mergeados nos últimos ${TEAM_SINCE_DAYS}d (explicam por que a $DEFAULT_BRANCH mudou) ---"
    MERGED_JQ=".[] | select((.mergedAt // \"\") != \"\") | select((.mergedAt|fromdateiso8601) >= ${CUTOFF:-0}) | \"  #\(.number) \(.title) — \(.author.login) | \(.headRefName) | merged \(.mergedAt[0:10])\""
    if MERGED_OUT="$(gh pr list --state merged --limit 30 \
        --json number,title,author,headRefName,mergedAt \
        --jq "$MERGED_JQ" 2>&1)"; then
      if [[ -n "$MERGED_OUT" ]]; then printf '%s\n' "$MERGED_OUT"; else echo "  (nenhum)"; fi
    else
      echo "  (gh indisponível para PRs mergeados)"
    fi
    echo
  fi

  echo "--- risco de conflito: arquivos tocados dos DOIS lados ---"
  if [[ -z "$BASE" ]]; then
    echo "  (sem base comum — não avaliado)"
  else
    THEIRS_F="$(git diff --name-only "$BASE" "$ORIGIN_DEFAULT" 2>/dev/null | sort -u || true)"
    MINE_F="$( { git diff --name-only "$BASE" HEAD 2>/dev/null || true
                 git diff --name-only 2>/dev/null || true
                 git diff --cached --name-only 2>/dev/null || true
                 git ls-files --others --exclude-standard 2>/dev/null || true
               } | grep -v '^$' | sort -u || true)"
    if [[ -z "$THEIRS_F" || -z "$MINE_F" ]]; then
      echo "  (nenhum)"
    else
      OVERLAP="$(comm -12 <(printf '%s\n' "$MINE_F") <(printf '%s\n' "$THEIRS_F") || true)"
      if [[ -n "$OVERLAP" ]]; then
        printf '%s\n' "$OVERLAP" | sed 's/^/  ⚠ /'
        echo "  → sincronize com $ORIGIN_DEFAULT ANTES de mexer nesses arquivos"
      else
        echo "  (nenhum)"
      fi
    fi
  fi
  hr
fi

# Squash merge nunca faz o commit da branch virar ancestral de origin/<default>:
# `branch -d` e `merge-base --is-ancestor` recusam trabalho que JÁ está inteiro em main.
# A prova real é o PR.
#
# Cache em arquivo, não em array associativo: o bash do macOS é 3.2 e lá
# `declare -A` degrada CALADO para array indexado — toda chave vira índice 0 e
# uma branch sem PR herdaria o número da última consultada (= -D em trabalho vivo).
MERGED_PR_CACHE=""
trap '[[ -n "$MERGED_PR_CACHE" ]] && rm -f "$MERGED_PR_CACHE"' EXIT
merged_pr_num() {
  # template com XXXXXX: `mktemp -t <prefixo>` é forma do macOS e o GNU coreutils recusa
  [[ -n "$MERGED_PR_CACHE" ]] || MERGED_PR_CACHE="$(mktemp "${TMPDIR:-/tmp}/gitsync-pr.XXXXXX")"
  local b="$1" hit n=""
  hit="$(awk -F'\t' -v k="$b" '$1==k{print $2; found=1; exit} END{if(!found) exit 1}' \
         "$MERGED_PR_CACHE" 2>/dev/null)" && { printf '%s' "$hit"; return; }
  if [[ "$GH_CLEANUP_OK" -eq 1 ]]; then
    n="$(gh pr list --state merged --head "$b" --limit 1 --json number \
         --jq '.[0].number // empty' 2>/dev/null || true)"
  fi
  printf '%s\t%s\n' "$b" "$n" >> "$MERGED_PR_CACHE"
  printf '%s' "$n"
}

GH_CLEANUP_OK=0
if [[ "$CLEANUP_DRY" -eq 1 ]] && command -v gh >/dev/null 2>&1 \
   && gh repo view --json name >/dev/null 2>&1; then
  GH_CLEANUP_OK=1
fi

if [[ "$CLEANUP_DRY" -eq 1 ]]; then
  echo "### cleanup candidates"

  echo "--- branches com upstream gone ---"
  GONE_BRANCHES=()
  while IFS= read -r b; do
    [[ -n "$b" ]] && GONE_BRANCHES+=("$b")
  done < <(git for-each-ref --format='%(refname:short)|%(upstream:track)' refs/heads | awk -F'|' '$2=="[gone]"{print $1}')
  if [[ ${#GONE_BRANCHES[@]} -eq 0 ]]; then
    echo "  (none)"
  else
    for b in "${GONE_BRANCHES[@]}"; do
      if git merge-base --is-ancestor "$b" "$ORIGIN_DEFAULT" 2>/dev/null; then
        echo "  $b — mergeada (branch -d resolve)"
      else
        _pr="$(merged_pr_num "$b")"
        if [[ -n "$_pr" ]]; then
          echo "  $b — SQUASH de PR #$_pr merged → candidata a -D"
        elif [[ "$GH_CLEANUP_OK" -eq 1 ]]; then
          echo "  $b — ! sem PR merged: pode ter trabalho exclusivo, confira antes"
        else
          echo "  $b — (gh indisponível: sem prova, será só skipada)"
        fi
      fi
    done
  fi

  echo "--- worktrees candidatos a remoção (clean + merged em $ORIGIN_DEFAULT + não locked) ---"
  WT_REMOVE=()
  if [[ ${#WT_PATHS[@]} -le 1 ]]; then
    echo "  (só o clone principal — nada a avaliar)"
  else
    for wt in "${WT_PATHS[@]}"; do
      [[ "$wt" == "$MAIN_WT" ]] && continue
      [[ -d "$wt" ]] || continue
      wt_branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
      reason=""; nota=""; STALE_PID=""
      if [[ "$wt_branch" == "HEAD" ]]; then
        reason="detached HEAD — avaliar manualmente"
      elif is_locked "$wt" && ! lock_is_stale "$wt"; then
        reason="locked (sessão viva)"
      elif [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
        reason="não-clean (dirty ou untracked)"
      elif ! git -C "$wt" merge-base --is-ancestor HEAD "$ORIGIN_DEFAULT" 2>/dev/null; then
        _pr="$(merged_pr_num "$wt_branch")"
        if [[ -n "$_pr" ]]; then
          nota=" [squash: PR #$_pr merged]"
        elif [[ "$GH_CLEANUP_OK" -eq 1 ]]; then
          reason="não mergeado em $ORIGIN_DEFAULT (e nenhum PR merged para '"'"'$wt_branch'"'"')"
        else
          reason="não mergeado em $ORIGIN_DEFAULT (gh indisponível — sem prova de PR)"
        fi
      fi
      if [[ -z "$reason" ]]; then
        _stale_nota=""
        is_locked "$wt" && _stale_nota=" [lock stale — pid ${STALE_PID:-?} morto, será destravado]"
        echo "  CANDIDATO: $wt ($wt_branch)${nota:-}${_stale_nota}"
        WT_REMOVE+=("$wt")
      else
        echo "  keep: $wt ($wt_branch) — $reason"
      fi
    done
  fi

  echo "--- branches locais atrás / gone (info) ---"
  git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads \
    | grep -E 'behind|gone' || echo "  (none with track info)"

  if [[ "$CLEANUP_APPLY" -eq 1 ]]; then
    echo
    echo "### cleanup APPLY"
    # 1) worktrees primeiro (libera as branches deles para o -d abaixo)
    if [[ ${#WT_REMOVE[@]} -eq 0 ]]; then
      echo "  (nenhum worktree candidato)"
    else
      for wt in "${WT_REMOVE[@]}"; do
        # lock stale só é destravado aqui, no apply — nunca no dry-run
        if is_locked "$wt" && lock_is_stale "$wt"; then
          git worktree unlock "$wt" >/dev/null 2>&1 \
            && echo "  unlocked $wt (lock stale — pid $STALE_PID morto)"
        fi
        if git worktree remove "$wt" >/dev/null 2>&1; then
          echo "  removed worktree $wt"
        else
          echo "  skip worktree $wt (git worktree remove recusou — não forço)"
        fi
      done
    fi
    git worktree prune
    echo "  worktree prune done"

    # 2) branches gone não checkoutadas em nenhum worktree restante
    CHECKED_OUT="$(git worktree list --porcelain | awk '/^branch /{sub(/^branch refs\/heads\//,""); print}')"
    if [[ ${#GONE_BRANCHES[@]} -gt 0 ]]; then
      for b in "${GONE_BRANCHES[@]}"; do
        [[ -z "$b" ]] && continue
        if printf '%s\n' "$CHECKED_OUT" | grep -qxF "$b"; then
          echo "  keep $b (checked out em worktree)"
          continue
        fi
        if git branch -d "$b" >/dev/null 2>&1; then
          echo "  deleted branch $b (-d)"
          continue
        fi
        # -d recusou: só o PR distingue squash-merge de trabalho de verdade
        _pr="$(merged_pr_num "$b")"
        if [[ -n "$_pr" ]]; then
          if git branch -D "$b" >/dev/null 2>&1; then
            echo "  deleted branch $b (-D — squash de PR #$_pr merged)"
          else
            echo "  skip $b (-D falhou)"
          fi
        elif [[ "$GH_CLEANUP_OK" -eq 1 ]]; then
          echo "  skip $b (nenhum PR merged encontrado — pode ter trabalho exclusivo; confira antes de -D)"
        else
          echo "  skip $b (gh indisponível — sem prova de merge, não deleto no escuro)"
        fi
      done
    fi
  else
    echo
    echo "(dry-run — rode com --cleanup-apply após aprovação do usuário)"
  fi
  hr
fi

echo "### summary"
echo "default=$DEFAULT_BRANCH tip=$DEFAULT_SHA"
echo "updated=${#UPDATED[@]} skipped=${#SKIPPED[@]} warns=${#WARNS[@]} untracked_entries=${#UNTRACKED_LINES[@]}"
echo "status_only=$STATUS_ONLY team=$TEAM cleanup_dry=$CLEANUP_DRY cleanup_apply=$CLEANUP_APPLY"
echo "DONE"
