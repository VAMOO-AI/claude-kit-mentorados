#!/usr/bin/env bash
# Aplica o plano do inventario.sh. Só remove o que é seguro por construção:
#   worktree  merged, limpa (dirty=0, conta ignorado fora de build), HEAD igual ao do
#             inventário, sem lock de processo vivo e com `worktree-gc.sh --verificar`
#             dizendo "pode remover" — `worktree remove` sem --force. O fetch --prune roda
#             uma vez por repo aqui, e o do --verificar é pulado (WORKTREE_GC_SKIP_FETCH=1)
#   branch    merged(ancestral) ou merged(PR#N) com SHA conferido no inventário; nunca
#             main, master, develop, dev, staging ou production
#   órfã      pasta sem .git e sem nenhum arquivo fora de node_modules/.next
#   build     node_modules e .next de repo parado há >= DIAS_NM dias (default 7)
# Tudo que sai vai para o ledger antes: repo, branch e SHA restauram com `git branch <b> <sha>`
# enquanto ninguém rodar `git gc --prune=now`.
#
# Uso: bash aplicar.sh <dir-do-plano> <dir-do-ledger>
#      DRY=1 não remove nada nem escreve no plano ou no ledger; o fetch --prune roda igual
#      LIMPEZA_WORKTREE_GC troca o worktree-gc.sh (padrão: o de scripts/ do plugin)
# Só macOS: fora dele, sai 0 sem fazer nada.
set -uo pipefail
[ "$(uname -s)" = Darwin ] || { echo "limpeza-mac: só macOS (aqui: $(uname -s)); nada feito"; exit 0; }
P="${1:?uso: aplicar.sh <dir-do-plano> <dir-do-ledger>}"; L="${2:?falta o dir do ledger}"
DIAS_NM="${DIAS_NM:-7}"; DRY="${DRY:-0}"
# plugin/skills/limpeza-mac/scripts → plugin/scripts. O ${CLAUDE_PLUGIN_ROOT} é preenchido
# no texto da skill, não no ambiente deste processo.
GC="${LIMPEZA_WORKTREE_GC:-$(cd "$(dirname "$0")/../../.." && pwd)/scripts/worktree-gc.sh}"
[ "$DRY" = 1 ] || mkdir -p "$L"
run() { if [ "$DRY" = 1 ]; then echo "[dry] $*" >&2; else "$@"; fi; }
anota() { [ "$DRY" = 1 ] || printf '%s\n' "$2" >> "$L/$1"; }   # anota <arquivo> <linha>

# lock de sessão Claude traz "pid N"; lock de processo morto não protege nada
lock_vivo() {
  local pid
  pid=$(printf '%s' "$1" | sed -n 's/.*pid \([0-9][0-9]*\).*/\1/p')
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && return 0
  [ -z "$pid" ] && [ "$1" != "-" ] && return 0   # lock manual sem pid: respeita
  return 1
}

LIBERADAS=$(mktemp "${TMPDIR:-/tmp}/limpeza-liberadas.XXXXXX")
trap 'rm -f "$LIBERADAS"' EXIT

nwt=0; nbr=0; norf=0; nbld=0; buscado=""
while IFS=$'\t' read -r r b p sha dirty est lock; do
  case "$est" in merged*) ;; *) continue;; esac
  [ "$dirty" = 0 ] || { echo "mantida (suja): $p"; continue; }
  # commit feito depois do inventário (em detached não há branch que o segure)
  [ "$(git -C "$p" rev-parse HEAD 2>/dev/null)" = "$sha" ] || { echo "mantida (HEAD mudou desde o inventário): $p"; continue; }
  [ "$lock" != "-" ] && lock_vivo "$lock" && { echo "mantida (lock vivo): $p"; continue; }
  # worktrees.tsv sai agrupado por repo: um fetch por repo, e o gc não repete
  if [ "$r" != "$buscado" ]; then
    GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
      -C "$r" fetch --prune --quiet origin >/dev/null 2>&1
    buscado="$r"
  fi
  # a trava do gc (sujo, ignorado de valor, branch não mergeada) decide por último; qualquer
  # saída diferente de 0, inclusive o 2 de um worktree-gc.sh sem o --verificar, mantém
  veredito=$(cd "$p" && WORKTREE_GC_SKIP_FETCH=1 bash "$GC" --verificar "$p" 2>&1); vrc=$?
  [ "$vrc" = 0 ] || { echo "mantida (worktree-gc --verificar saiu $vrc): $p — $(printf '%s' "$veredito" | tail -1)"; continue; }
  [ "$lock" != "-" ] && run git -C "$r" worktree unlock "$p" 2>/dev/null
  anota worktrees.tsv "$(printf '%s\t%s\t%s\t%s' "$r" "$b" "$p" "$sha")"
  if run git -C "$r" worktree remove "$p"; then
    nwt=$((nwt+1))
    # a branch da worktree removida entra no mesmo crivo: o inventário já conferiu o SHA,
    # e as de longa duração ficam, como no branches.tsv
    case "$b" in
      -|main|master|develop|dev|staging|production) ;;
      *) printf '%s\t%s\t%s\t%s\n' "$r" "$b" "$sha" "$est" >> "$LIBERADAS" ;;
    esac
  elif [ "$lock" != "-" ]; then
    git -C "$r" worktree lock --reason "$lock" "$p" 2>/dev/null
  fi
done < "$P/worktrees.tsv"

while IFS=$'\t' read -r r b sha est; do
  case "$est" in merged*) ;; *) continue;; esac
  atual=$(git -C "$r" rev-parse -q --verify "refs/heads/$b") || continue
  [ "$atual" = "$sha" ] || { echo "mantida (mudou desde o inventário): $r $b"; continue; }
  anota branches.tsv "$(printf '%s\t%s\t%s\t%s' "$r" "$b" "$sha" "$est")"
  if [ "$DRY" = 1 ]; then run git -C "$r" branch -D "$b"; nbr=$((nbr+1))
  else git -C "$r" branch -D "$b" >/dev/null && nbr=$((nbr+1)); fi
done < <(cat "$P/branches.tsv" "$LIBERADAS")

while IFS=$'\t' read -r d kb conteudo; do
  [ "$conteudo" = "sem-.git,0-arquivos-fora-de-build" ] || { echo "órfã para auditar à mão: $d ($conteudo)"; continue; }
  anota orfas.txt "$d"; run rm -rf "$d" && norf=$((norf+1))
done < "$P/orfas.tsv"

while IFS=$'\t' read -r dias kb d; do
  case "$d" in
    */.next|*/node_modules) [ "$dias" -ge "$DIAS_NM" ] || continue ;;
    *) continue ;;
  esac
  anota builds.txt "$d"; run rm -rf "$d" && nbld=$((nbld+1))
done < "$P/builds.tsv"

echo "worktrees: $nwt  branches: $nbr  órfãs: $norf  builds: $nbld  (ledger: $L)"
