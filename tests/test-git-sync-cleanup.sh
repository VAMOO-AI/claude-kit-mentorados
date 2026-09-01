#!/usr/bin/env bash
# Prova de regressão do cleanup do plugin/skills/git-sync/scripts/git-sync.sh.
#
# O repo faz squash merge, então o commit da branch nunca vira ancestral de origin/main:
# `git branch -d` recusa e `merge-base --is-ancestor` dá falso para trabalho que JÁ está
# inteiro em main. Até 31/08/2026 o `--cleanup-apply` skipava 100% das branches por isso —
# no kanbanvamooai foram 20 branches gone, 20 skips e 2 worktrees `keep:`, todos falso
# positivo, e a limpeza teve que ser feita à mão. A prova real é o PR, via gh.
#
# O teste cobre também os dois modos de falhar PERIGOSAMENTE:
#   - cache de PR que vaza entre branches (bash 3.2 degrada `declare -A` calado: toda
#     chave vira índice 0, e uma branch sem PR herdaria o número da última consultada);
#   - lock de worktree cuja sessão morreu, que imunizaria o worktree pra sempre.
#
# Uso: bash tests/test-git-sync-cleanup.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/git-sync/scripts/git-sync.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
# `mktemp -t <prefixo>` é forma do macOS; o GNU coreutils exige XXXXXX no template e
# falha com "too few X's". Sem a guarda abaixo, TMP vazio faz o teste operar na RAIZ —
# foi o que aconteceu no primeiro run deste arquivo no CI (Ubuntu).
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitsync-test.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando antes de tocar em /"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

check() { # <esperado-regex> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}

# --- fixture: origin com squash merge + duas branches gone -------------------
ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"
git init -q --bare "$ORIGIN"
git init -q "$CLONE"
cd "$CLONE"
git config user.email t@t; git config user.name t; git config commit.gpgsign false
echo base > base.txt; git add base.txt; git commit -qm base
git branch -M main; git remote add origin "$ORIGIN"; git push -qu origin main

# branch 'squashed': trabalho que entra em main por squash (commit não vira ancestral)
git checkout -qb squashed
echo feito > feito.txt; git add feito.txt; git commit -qm "trabalho"
git push -qu origin squashed
git checkout -q main
git merge -q --squash squashed && git commit -qm "trabalho (#42)"
git push -q origin main

# branch 'orfa': trabalho que NUNCA foi para main e não tem PR
git checkout -qb orfa
echo exclusivo > exclusivo.txt; git add exclusivo.txt; git commit -qm "so aqui"
git push -qu origin orfa

git checkout -q main
git push -q origin --delete squashed >/dev/null 2>&1
git push -q origin --delete orfa >/dev/null 2>&1
git fetch -q --prune origin

# --- gh falso: 'squashed' tem PR #42; 'orfa' não tem nenhum ------------------
mkdir -p "$TMP/bin"
{
  echo '#!/usr/bin/env bash'
  echo 'case "$*" in'
  echo '  *"repo view"*) exit 0 ;;'
  echo '  *"pr list"*"--head squashed"*) echo "42"; exit 0 ;;'
  echo '  *"pr list"*"--head orfa"*)     echo "";   exit 0 ;;'
  echo '  *"pr list"*) echo ""; exit 0 ;;'
  echo 'esac'
  echo 'exit 0'
} > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"

run() { PATH="$TMP/bin:$PATH" bash "$SCRIPT" --cwd "$CLONE" --status-only --no-pr "$@" 2>&1; }

echo "== dry-run distingue squash-merge de trabalho órfão =="
OUT="$(run --cleanup-dry-run)"
check 'squashed — SQUASH de PR #42 merged'      "squashed: reconhecida pelo PR"       "$OUT"
check 'orfa — ! sem PR merged'                  "orfa: marcada como suspeita"         "$OUT"
refute 'orfa — SQUASH'                          "orfa: NÃO herda PR de outra branch"  "$OUT"

echo "== apply deleta a provada e preserva a órfã =="
OUT="$(run --cleanup-apply)"
check 'deleted branch squashed \(-D — squash de PR #42 merged\)' "squashed: deletada com prova" "$OUT"
check 'skip orfa \(nenhum PR merged'            "orfa: preservada"                    "$OUT"
has_branch() { git -C "$CLONE" show-ref --verify --quiet "refs/heads/$1"; }
if has_branch orfa; then printf '  ok    %s\n' "orfa: ainda existe no repo"
else printf '  FALHA %s\n' "orfa: foi deletada sem prova de merge"; falhas=$((falhas+1)); fi
if has_branch squashed; then printf '  FALHA %s\n' "squashed: continua no repo"; falhas=$((falhas+1))
else printf '  ok    %s\n' "squashed: sumiu do repo"; fi

echo "== sem gh não deleta no escuro =="
OUT="$(PATH="/usr/bin:/bin" bash "$SCRIPT" --cwd "$CLONE" --status-only --no-pr --cleanup-apply 2>&1)"
refute 'deleted branch orfa'                    "orfa: intacta sem gh"                "$OUT"

echo "== lock stale não imuniza worktree =="
WT="$TMP/wt"; git -C "$CLONE" worktree add -q "$WT" orfa 2>/dev/null
git -C "$CLONE" worktree lock --reason "claude session teste (pid 999999 start now)" "$WT" 2>/dev/null
OUT="$(run --cleanup-dry-run)"
refute 'keep: .*(locked|sessão viva)'           "pid morto: não conta como sessão viva" "$OUT"
git -C "$CLONE" worktree unlock "$WT" 2>/dev/null
git -C "$CLONE" worktree lock --reason "claude session viva (pid $$ start now)" "$WT" 2>/dev/null
OUT="$(run --cleanup-dry-run)"
check 'locked \(sessão viva\)'                  "pid vivo: worktree protegido"        "$OUT"

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
