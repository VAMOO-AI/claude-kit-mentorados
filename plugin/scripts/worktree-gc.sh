#!/usr/bin/env bash
# worktree-gc.sh — coleta-de-lixo de git worktrees.
#
# Remove worktrees em .claude/worktrees/ cuja branch JÁ FOI MERGEADA (ancestral de
# origin/main OU squash-merge detectado via `gh pr`), e que estejam LIMPOS (sem
# mudança não-commitada). Nunca toca: clone principal, branch main/master, worktree
# sujo, arquivo ignorado de valor (env diferente do clone principal, repo aninhado, ou
# qualquer ignorado fora da lista de cache/build), branch ou detached sem commit
# próprio (sessão recém-aberta), ou o worktree de onde o script roda (use ExitWorktree
# pra esse).
#
# Uso:
#   worktree-gc.sh            # dry-run (só mostra o que faria) — PADRÃO
#   worktree-gc.sh --apply    # remove de fato (worktree + branch local mergeada)
#   worktree-gc.sh --apply --prune-remote   # também deleta a branch remota mergeada
#   worktree-gc.sh --verificar <caminho>    # um worktree só; não remove nada, mas atualiza
#       as refs remotas com `git fetch --prune`. As mesmas travas, exit 0 + "pode remover"
#       ou exit 1 + "keep: <motivos>"; uso errado ou caminho que não é worktree do repo sai 2.
#       É o que a skill worktrees roda antes do ExitWorktree / git worktree remove (a remoção
#       continua só com pedido da pessoa). Aqui o worktree atual conta, e "sem commit
#       próprio" não segura: não há commit a perder.
#   WORKTREE_GC_SKIP_FETCH=1  pula o fetch — para quem chama em série e já buscou uma vez
#       por repo (o aplicar.sh da limpeza-mac).
#
# Seguro por padrão: dry-run, e só remove o que passa em TODAS as travas.
set -uo pipefail

APPLY=0
PRUNE_REMOTE=0
VERIFICAR=0; ALVO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --prune-remote) PRUNE_REMOTE=1 ;;
    --verificar)
      VERIFICAR=1
      case "${2:-}" in ""|--*) ;; *) ALVO="$2"; shift ;; esac ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "arg desconhecido: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$VERIFICAR" = 1 ]; then
  [ -n "$ALVO" ] || { echo "uso: worktree-gc.sh --verificar <caminho>" >&2; exit 2; }
  [ "$APPLY$PRUNE_REMOTE" = 00 ] || { echo "--verificar não remove nada: não combina com --apply/--prune-remote" >&2; exit 2; }
  ALVO="$(cd "$ALVO" 2>/dev/null && pwd -P)" || { echo "não é worktree deste repo: caminho inexistente" >&2; exit 2; }
  _top="$(git -C "$ALVO" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$_top" ] && [ "$(cd "$_top" && pwd -P)" = "$ALVO" ] || { echo "não é worktree (nem raiz de um): $ALVO" >&2; exit 2; }
  cd "$ALVO" || exit 2
else
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "não é um repo git" >&2; exit 1; }
fi

COMMON="$(git rev-parse --git-common-dir 2>/dev/null)"
COMMON="$(cd "$COMMON" && pwd -P)"
PRIMARY="$(dirname "$COMMON")"                 # raiz do clone principal (contém .git/)
SELF="$(git rev-parse --show-toplevel 2>/dev/null && :)"; SELF="$(cd "$SELF" && pwd -P)"

if [ "$VERIFICAR" = 1 ]; then
  [ "$ALVO" != "$PRIMARY" ] || { echo "é o clone principal, não um worktree: $ALVO" >&2; exit 2; }
  [ "${WORKTREE_GC_SKIP_FETCH:-0}" = 1 ] \
    || git -C "$PRIMARY" fetch --prune --quiet origin 2>/dev/null || echo "(fetch falhou — seguindo com o que há local)" >&2
else
  echo "🧹 worktree-gc  (modo: $([ "$APPLY" = 1 ] && echo APLICAR || echo dry-run))"
  [ "${WORKTREE_GC_SKIP_FETCH:-0}" = 1 ] \
    || git -C "$PRIMARY" fetch --prune --quiet origin 2>/dev/null || echo "  (fetch falhou — seguindo com o que há local)"
fi

have_gh=0; command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && have_gh=1

# É mergeada? ancestral de origin/main OU tip local contido no head do PR MERGED (squash).
is_merged() {
  local br="$1"
  git -C "$PRIMARY" merge-base --is-ancestor "refs/heads/$br" origin/main 2>/dev/null && return 0
  if [ "$have_gh" = 1 ]; then
    local oid
    oid="$(gh pr list --head "$br" --state merged --json headRefOid --jq '.[0].headRefOid // empty' 2>/dev/null)"
    # o tip LOCAL precisa estar contido no head do PR mergeado — commits feitos
    # DEPOIS do merge (não pushados) deixam de contar como "mergeada".
    [ -n "$oid" ] && git -C "$PRIMARY" merge-base --is-ancestor "refs/heads/$br" "$oid" 2>/dev/null && return 0
  fi
  # Fail-closed: sem PR merged, oid vazio ou inexistente localmente → mantém a branch.
  return 1
}

# Branch recém-criada de origin/main é ancestral dela sem ter commit nenhum, e o
# `--is-ancestor` sozinho a chamava de mergeada: o --apply removia o worktree limpo de
# uma sessão que acabou de abrir (24/09/2026, o mesmo defeito do warn-worktree-stale).
# Sem commit próprio = o tip não passou do ponto de criação (a 1ª entrada do reflog), ou
# é commit da linha first-parent da main — a branch que só puxou a base, a de reflog
# expirado, e o detached que é só checkout da main (sem branch, sem reflog).
sem_commit_proprio() {
  local tip="$1" br="${2:-}" criacao ultimo
  [ -n "$tip" ] || return 1
  if [ -n "$br" ]; then
    criacao="$(git -C "$PRIMARY" reflog show --format='%H %gs' "refs/heads/$br" 2>/dev/null | tail -n 1)"
    case "$criacao" in
      *" branch: Created from "*)
        [ "$(git -C "$PRIMARY" rev-list --count "${criacao%% *}..$tip" 2>/dev/null)" = 0 ] && return 0 ;;
    esac
  fi
  # atalho: branch mergeada por fast-forward na main nunca é coletada (parece base puxada); rever se o time mergear por ff fora do PR
  [ "$tip" = "$(git -C "$PRIMARY" rev-parse --verify -q origin/main)" ] && return 0
  ultimo="$(git -C "$PRIMARY" rev-list --first-parent origin/main "^$tip" 2>/dev/null | tail -n 1)"
  [ -n "$ultimo" ] && [ "$(git -C "$PRIMARY" rev-parse --verify -q "$ultimo^1")" = "$tip" ]
}

# Cache e build que qualquer instalação ou build recria. Casa por segmento de caminho, para
# apps/web/node_modules/ valer igual a node_modules/. Lista fechada: o que não está aqui é
# trabalho até prova em contrário. Fora de propósito: *.log (log de sessão pode ser a prova
# de um incidente, e nenhum build o recria) e out/ (ferramenta de render, como o Remotion,
# grava ali o arquivo final).
eh_regeneravel() {   # <caminho relativo; diretório termina em />
  case "/$1" in
    */node_modules/*|*/.next/*|*/dist/*|*/build/*|*/.turbo/*|*/.cache/*|*/coverage/*) return 0 ;;
    */__pycache__/*|*.pyc|*/.pytest_cache/*|*/.mypy_cache/*|*/.ruff_cache/*|*/.venv/*) return 0 ;;  # .venv: só diretório
    */.DS_Store|*/.vercel/*|*/target/*|*/.gradle/*) return 0 ;;
    */.parcel-cache/*|*/.svelte-kit/*|*/.nuxt/*|*/.expo/*|*.tsbuildinfo) return 0 ;;
  esac
  return 1
}

# Ignorado não aparece no `status` e o `git worktree remove` sem --force o apaga calado: até
# 28/09/2026 só env era conferido, e um outputs/video.mp4 sumia com o worktree "limpo". Lista
# os ignorados no nível em que o padrão casa (`status --ignored=matching`: node_modules/ sai
# inteiro, sem os pais não ignorados que o `ls-files --directory` mistura) e põe em IGN_MOTIVO:
#   - env (.env*, .npmrc, bunfig.toml, .bunfig.toml) diferente do clone principal ou só aqui;
#   - repo aninhado (um .git dentro do ignorado), que o remove apagaria com .git e tudo;
#   - qualquer outro ignorado que não seja symlink (remover o link não apaga o alvo) nem
#     cache da lista acima — os primeiros IGN_MAX e a contagem.
# A mesma trava do git-sync e da "Limpeza no fim" da skill worktrees. Fail-closed.
IGN_MAX=5
ignorado_de_valor() {   # <worktree> — 0 = achou algum
  local wt="$1" e f r dif="" repo="" outros="" n=0
  while IFS= read -r -d '' e; do
    case "$e" in '!! '*) f="${e#!! }" ;; *) continue ;; esac
    [ -L "$wt/${f%/}" ] && continue
    eh_regeneravel "$f" && continue
    case "$f" in
      */) r="$(cd "$wt" && find "${f%/}" -name .git -prune 2>/dev/null | sed 's|\.git$||' | tr '\n' ' ')"
          r="${r% }"
          [ -n "$r" ] && { repo="${repo:+$repo }$r"; continue; } ;;
      *) case "${f##*/}" in
           .env*|.npmrc|bunfig.toml|.bunfig.toml)
             cmp -s "$wt/$f" "$PRIMARY/$f" || dif="${dif:+$dif }$f"; continue ;;
         esac ;;
    esac
    n=$((n+1)); [ "$n" -le "$IGN_MAX" ] && outros="${outros:+$outros }$f"
  done < <(git -C "$wt" status --porcelain -z --ignored=matching --untracked-files=all 2>/dev/null)
  IGN_MOTIVO=""
  case "$dif" in "") ;; *" "*) IGN_MOTIVO="$dif diferem do clone principal" ;; *) IGN_MOTIVO="$dif difere do clone principal" ;; esac
  [ -n "$repo" ] && IGN_MOTIVO="${IGN_MOTIVO:+$IGN_MOTIVO; }repo aninhado ignorado: $repo"
  if [ "$n" -gt 0 ]; then
    [ "$n" -gt "$IGN_MAX" ] && outros="$outros (+$((n-IGN_MAX)))"
    [ "$n" = 1 ] && outros="ignorado que o remove apagaria: $outros" || outros="$n ignorados que o remove apagaria: $outros"
    IGN_MOTIVO="${IGN_MOTIVO:+$IGN_MOTIVO; }$outros"
  fi
  [ -n "$IGN_MOTIVO" ]
}

# --verificar: as travas do gc para um worktree só, sem remover nada (o fetch lá em cima é a
# única escrita). Junta todos os motivos.
if [ "$VERIFICAR" = 1 ]; then
  motivos=""; add() { motivos="${motivos:+$motivos; }$1"; }
  branch="$(git -C "$ALVO" symbolic-ref -q --short HEAD 2>/dev/null)"
  tip="$(git -C "$ALVO" rev-parse --verify -q HEAD 2>/dev/null)"
  case "$branch" in main|master) add "branch '$branch' (nunca removida)" ;; esac
  [ -z "$(git -C "$ALVO" status --porcelain 2>/dev/null)" ] || add "SUJO (mudança não-commitada)"
  ignorado_de_valor "$ALVO" && add "$IGN_MOTIVO"
  if [ -n "$branch" ]; then
    case "$branch" in main|master) ;; *)
      sem_commit_proprio "$tip" "$branch" || is_merged "$branch" || add "branch '$branch' NÃO mergeada" ;;
    esac
  else
    sem_commit_proprio "$tip" || git -C "$ALVO" merge-base --is-ancestor HEAD origin/main 2>/dev/null \
      || add "detached com commit fora de origin/main"
  fi
  if [ -z "$motivos" ]; then echo "pode remover: $ALVO"; exit 0; fi
  echo "keep: $ALVO — $motivos"; exit 1
fi

removed=0; kept=0; skipped=0
# Percorre os worktrees (path + branch) do porcelain.
path=""; branch=""
while IFS= read -r line; do
  case "$line" in
    worktree\ *) path="${line#worktree }" ;;
    branch\ *)   branch="${line#branch refs/heads/}" ;;
    "")  # fim de um bloco → avalia
      [ -z "$path" ] && { path=""; branch=""; continue; }
      p="$(cd "$path" 2>/dev/null && pwd -P || echo "$path")"

      # trava 1: nunca o clone principal
      if [ "$p" = "$PRIMARY" ]; then path=""; branch=""; continue; fi
      # trava 2: nunca main/master
      if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
        echo "  ⏭️  $p  → branch '$branch' (mantido)"; skipped=$((skipped+1)); path=""; branch=""; continue
      fi
      # detached (EnterWorktree cria assim): lixo se limpo e o HEAD é commit já contido
      # em origin/main fora da linha da main — HEAD na linha da main é checkout da base
      if [ -z "$branch" ]; then
        tip="$(git -C "$p" rev-parse --verify -q HEAD 2>/dev/null)"
        if [ "$p" != "$SELF" ] && sem_commit_proprio "$tip"; then
          echo "  ⏭️  $p  → detached sem commit próprio (HEAD na linha da main) — mantido"; skipped=$((skipped+1))
        elif [ "$p" != "$SELF" ] && ignorado_de_valor "$p"; then
          echo "  ✋ $p  → $IGN_MOTIVO — copie/confira antes; mantido"; kept=$((kept+1))
        elif [ "$p" != "$SELF" ] && [ -z "$(git -C "$p" status --porcelain 2>/dev/null)" ] \
           && git -C "$p" merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
          if [ "$APPLY" = 1 ]; then
            if git -C "$PRIMARY" worktree remove "$p" 2>/dev/null; then
              echo "  ✅ removido: $p  (detached, limpo, HEAD já em origin/main)"; removed=$((removed+1))
            else
              echo "  ⚠️  falhou remover: $p"; kept=$((kept+1))
            fi
          else
            echo "  🗑️  [dry-run] removeria: $p  (detached, limpo, HEAD já em origin/main)"; removed=$((removed+1))
          fi
        else
          echo "  ⏭️  $p  → detached (mantido)"; skipped=$((skipped+1))
        fi
        path=""; branch=""; continue
      fi
      # trava 3: nunca o worktree atual
      if [ "$p" = "$SELF" ]; then
        echo "  ⏭️  $p  → é o worktree ATUAL (use ExitWorktree pra remover)"; skipped=$((skipped+1)); path=""; branch=""; continue
      fi
      # trava 4: nunca se estiver sujo
      if [ -n "$(git -C "$p" status --porcelain 2>/dev/null)" ]; then
        echo "  ✋ $p  → SUJO (mudança não-commitada) — mantido"; kept=$((kept+1)); path=""; branch=""; continue
      fi
      # trava 4.5: ignorado pelo git (invisível no status) some junto com o worktree — só
      # remove se for env igual ao do clone principal, symlink ou cache regenerável.
      if ignorado_de_valor "$p"; then
        echo "  ✋ $p  → $IGN_MOTIVO — copie/confira antes; mantido"; kept=$((kept+1)); path=""; branch=""; continue
      fi
      # trava 5: só se mergeada — e branch sem commit próprio nunca foi mergeada
      if sem_commit_proprio "$(git -C "$PRIMARY" rev-parse --verify -q "refs/heads/$branch")" "$branch"; then
        echo "  🔒 $p  → branch '$branch' sem commit próprio (recém-criada ou só puxou a base) — mantido"; kept=$((kept+1)); path=""; branch=""; continue
      fi
      if ! is_merged "$branch"; then
        echo "  🔒 $p  → branch '$branch' NÃO mergeada — mantido"; kept=$((kept+1)); path=""; branch=""; continue
      fi

      if [ "$APPLY" = 1 ]; then
        if git -C "$PRIMARY" worktree remove "$p" 2>/dev/null; then
          git -C "$PRIMARY" branch -D "$branch" >/dev/null 2>&1 || true
          [ "$PRUNE_REMOTE" = 1 ] && git -C "$PRIMARY" push origin --delete "$branch" >/dev/null 2>&1 || true
          echo "  ✅ removido: $p  (branch '$branch' mergeada, deletada)"; removed=$((removed+1))
        else
          echo "  ⚠️  falhou remover: $p (rode manualmente 'git worktree remove --force' se apropriado)"; kept=$((kept+1))
        fi
      else
        echo "  🗑️  [dry-run] removeria: $p  (branch '$branch' mergeada + limpa)"; removed=$((removed+1))
      fi
      path=""; branch=""
      ;;
  esac
done < <(git -C "$PRIMARY" worktree list --porcelain; echo "")

git -C "$PRIMARY" worktree prune 2>/dev/null || true
echo "—"
if [ "$APPLY" = 1 ]; then
  echo "resumo: $removed removido(s), $kept mantido(s), $skipped pulado(s)."
else
  echo "resumo (dry-run): $removed candidato(s) a remoção, $kept mantido(s), $skipped pulado(s).  Rode com --apply pra remover."
fi
