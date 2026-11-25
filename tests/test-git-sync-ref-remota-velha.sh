#!/usr/bin/env bash
# git-sync num clone com refspec estreito (clone --single-branch, ou fetch só da main).
#
# Com `remote.origin.fetch = +refs/heads/main:refs/remotes/origin/main`, o fetch não traz as
# outras branches e o --prune não limpa as cópias delas: origin/<b> local pode ser uma branch
# que o GitHub apagou há semanas. O relatório a tratava como viva. Em "remotas suas sem cópia
# local" saía `git push origin --delete <b>`, que responde "remote ref does not exist"
# (25/11/2026, no clone do kit), e o modo time a listava como branch remota ativa.
#
# Falham no base:
#   velha    apagada no GitHub, cópia local velha → "cópia local velha" + `git branch -rd`, sem --delete
#   ativas   o modo time não lista a velha como branch remota ativa
#   aviso    branch local com o nome dela não recebe "origin/<b> já existe no GitHub"
#   cabeçalho diz que o refspec é estreito
# Guardas: a viva (existe no GitHub) continua com o --delete; com o refspec de sempre nada muda.
#
# Uso: bash tests/test-git-sync-ref-remota-velha.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/git-sync/scripts/git-sync.sh}"
case "$SCRIPT" in /*) ;; *) SCRIPT="$PWD/$SCRIPT" ;; esac
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }
unset GH_TOKEN GITHUB_TOKEN GH_REPO

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitsync-refvelha.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando antes de tocar em /"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

check() { # <regex> <descrição> <saída>
  if printf '%s' "$3" | grep >/dev/null -E -- "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep >/dev/null -E -- "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}

ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"; OUTRO="$TMP/outro"
git init -q --bare -b main "$ORIGIN"
git init -q -b main "$CLONE"
cd "$CLONE" || exit 2
git config user.email eu@x; git config user.name eu; git config commit.gpgsign false
git commit -q --allow-empty -m base
git remote add origin "$ORIGIN"
# velha e viva: entregues na main (ancestrais), pushadas, e a local apagada
# a velha tem o commit mais antigo: é a última linha do modo time (--sort=-committerdate), e
# o filtro precisa sobreviver a descartar justo a última
for b in velha viva; do
  git checkout -qb "$b"
  if [ "$b" = velha ]; then GIT_COMMITTER_DATE="$(date -u -v-2H +%s 2>/dev/null || date -u -d '2 hours ago' +%s) +0000" git commit -q --allow-empty -m "$b-1"
  else git commit -q --allow-empty -m "$b-1"; fi
  git checkout -q main
  git merge -q --no-ff --no-edit "$b"
done
git push -q origin main velha viva
git fetch -q origin
git branch -q -D velha viva
git branch -q --set-upstream-to=origin/main main
# o clone passa a buscar só a main; outro clone apaga a velha no GitHub
git config --replace-all remote.origin.fetch '+refs/heads/main:refs/remotes/origin/main'
git clone -q "$ORIGIN" "$OUTRO" 2>/dev/null
git -C "$OUTRO" push -q origin --delete velha
git rev-parse -q --verify refs/remotes/origin/velha >/dev/null || { echo "fixture inválida: origin/velha local sumiu"; exit 2; }
git ls-remote --heads origin velha | grep -q . && { echo "fixture inválida: velha ainda existe no origin"; exit 2; }

# gh falso: enxerga o repo e não acha PR nenhum (a prova aqui é a ancestralidade)
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\ncase "$*" in *"repo view"*) exit 0 ;; esac\necho ""\nexit 0\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
run() { PATH="$TMP/bin:$PATH" bash "$SCRIPT" --cwd "$CLONE" --no-pr "$@" 2>&1; }

echo "== refspec só da main: origin/velha é cópia local velha =="
OUT="$(run --status-only --team --cleanup-dry-run)"
refute "push origin --delete velha"                       "a velha não recebe git push origin --delete"     "$OUT"
check  "velha — .*cópia local velha.*git branch -rd origin/velha" "a velha sai como cópia local velha, com o -rd" "$OUT"
check  "viva — .*git push origin --delete viva"           "a viva continua com o --delete"                 "$OUT"
refute "^  origin/velha "                                 "o modo time não lista a velha como ativa"       "$OUT"
check  "^  origin/viva "                                  "o modo time lista a viva"                       "$OUT"
check  "^refspec: "                                       "o cabeçalho diz que o refspec é estreito"       "$OUT"

echo "== branch local com o nome da velha =="
git checkout -qb velha main; git commit -q --allow-empty -m velha-de-novo; git checkout -q main
OUT="$(run --status-only)"
refute "'velha' NÃO trackeia origin/velha, que já existe no GitHub" "sem 'já existe no GitHub' para a velha" "$OUT"
git branch -q -D velha

echo "== guarda: refspec de sempre =="
git config --replace-all remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
OUT="$(run --status-only --cleanup-dry-run)"
check  "viva — .*git push origin --delete viva"           "refspec de sempre: viva com --delete"           "$OUT"
refute "^refspec: "                                       "refspec de sempre: sem a linha do refspec"      "$OUT"
refute "^  velha — "                                      "refspec de sempre: o prune já tirou a velha"    "$OUT"

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
