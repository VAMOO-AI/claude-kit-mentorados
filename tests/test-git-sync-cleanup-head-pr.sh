#!/usr/bin/env bash
# Prova de regressão da comparação entre o tip local e o head do PR no cleanup do
# plugin/skills/git-sync/scripts/git-sync.sh.
#
# Em 23/10/2026, num projeto de cliente, o `--cleanup-dry-run` deu "o tip avançou depois do head
# do PR: preservada" para 9 branches [gone] com PR mergeado por squash. O tip estava ATRÁS:
# os últimos commits do PR (merge da main, correções) saíram de outro clone, e o objeto do
# headRefOid nem existia neste. O script lia "head != tip" como "avançou", sem olhar a direção.
# Conferido à mão com `git fetch origin refs/pull/N/head` + `merge-base --is-ancestor`.
#
# Casos, pelo gh e pela API REST, no dry-run e no --cleanup-apply:
#   igual     tip == head                      → candidata
#   contido   tip ancestral do head (atrás)    → candidata, motivo próprio (head buscado do origin)
#   avancou   head ancestral do tip            → preservada
#   divergiu  nenhum é ancestral do outro      → preservada
#   ausente   head não existe local nem no origin → preservada, "indisponível", nunca "avançou"
# E o mesmo "contido" nos outros caminhos que usam a prova: branch com remoto vivo, worktree,
# remota sem cópia local e o aviso de "nunca foi ao GitHub".
#
# Uso: bash tests/test-git-sync-cleanup-head-pr.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/git-sync/scripts/git-sync.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }
unset GH_TOKEN GITHUB_TOKEN

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitsync-headpr.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando antes de tocar em /"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

check() { # <esperado-regex> <descrição> <saída>
  if printf '%s' "$3" | grep >/dev/null -E -- "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep >/dev/null -E -- "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}
tem_branch() { # <clone> <branch> <deve: sim|nao> <descrição>
  local tem=nao
  git -C "$1" show-ref --verify --quiet "refs/heads/$2" && tem=sim
  if [ "$tem" = "$3" ]; then printf '  ok    %s\n' "$4"
  else printf '  FALHA %s\n' "$4"; falhas=$((falhas+1)); fi
}

ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"; OUTRO="$TMP/outro"
git init -q --bare "$ORIGIN"
git init -q "$CLONE"
cd "$CLONE" || exit 2
git config user.email eu@x; git config user.name eu; git config commit.gpgsign false
echo base > base.txt; git add base.txt; git commit -qm base
git branch -M main; git remote add origin "$ORIGIN"; git push -qu origin main

commit() { echo "$1" > "$1.txt"; git add "$1.txt"; git commit -qm "$1"; }
nova() { git checkout -q main; git checkout -qb "$1"; commit "$1-1"; }
squash() { git checkout -q main; git merge -q --squash "$1" >/dev/null && git commit -qm "$1 (squash)"; }

nova igual;    git push -qu origin igual;    SHA_IGUAL="$(git rev-parse HEAD)"; squash igual
nova atras;    git push -qu origin atras;    squash atras
nova avancou;  git push -qu origin avancou;  SHA_AVANCOU="$(git rev-parse HEAD)"; squash avancou
git checkout -q avancou; commit avancou-depois
nova divergiu; git push -qu origin divergiu; squash divergiu
nova ausente;  git push -qu origin ausente;  squash ausente
# vivaatras: remoto vivo no mesmo commit da local; o head do PR foi além, de outro clone
nova vivaatras; git push -qu origin vivaatras; squash vivaatras
# soremota: só a remota sobrou (a local foi apagada), atrás do head do PR
nova soremota; git push -qu origin soremota; squash soremota
# wtatras: worktree [gone] atrás do head; wtsemup: worktree sem upstream nenhum, atrás do head
nova wtatras;  git push -qu origin wtatras;  squash wtatras
nova wtsemup;  git push -q origin wtsemup:refs/heads/tmp-wtsemup; squash wtsemup
git checkout -q main; git push -q origin main

# O outro clone fecha os PRs: os commits finais só existem no origin, em refs/pull/N/head,
# que o `git fetch --prune origin` do script não traz.
git clone -q "$ORIGIN" "$OUTRO" 2>/dev/null
cd "$OUTRO" || exit 2
git config user.email eu@x; git config user.name eu; git config commit.gpgsign false
fecha_pr() { # <branch-remota> <n> — commit além do tip remoto, publicado só em refs/pull/<n>/head
  git checkout -q --detach "origin/$1"; commit "$1-final"
  git push -q origin "HEAD:refs/pull/$2/head"; git rev-parse HEAD
}
SHA_ATRAS="$(fecha_pr atras 61)"
SHA_DIVERGIU="$(fecha_pr divergiu 63)"
SHA_VIVAATRAS="$(fecha_pr vivaatras 66)"
SHA_SOREMOTA="$(fecha_pr soremota 67)"
SHA_WTATRAS="$(fecha_pr wtatras 65)"
SHA_WTSEMUP="$(fecha_pr tmp-wtsemup 68)"
# ausente: o head do PR nunca chegou ao origin — não há de onde buscar
git checkout -q --detach origin/ausente; commit ausente-final; SHA_AUSENTE="$(git rev-parse HEAD)"

cd "$CLONE" || exit 2
git checkout -q divergiu; commit divergiu-local
git checkout -q main
git push -q origin --delete atras avancou divergiu ausente wtatras tmp-wtsemup igual >/dev/null 2>&1
git branch -q -D soremota
git fetch -q --prune origin
git branch -q --unset-upstream wtsemup 2>/dev/null || true
git cat-file -e "$SHA_ATRAS^{commit}" 2>/dev/null && { echo "fixture inválida: head do PR #61 já está no clone"; exit 2; }

# Cópia antes de qualquer run: o run pelo gh busca os heads, e a cópia testa a busca de novo pela API
cp -R "$CLONE" "$TMP/clone-rest"
CLONE_REST="$TMP/clone-rest"

git worktree add -q "$TMP/wt-atras" wtatras 2>/dev/null
git worktree add -q "$TMP/wt-semup" wtsemup 2>/dev/null

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"repo view"*) exit 0 ;;
  *"pr list"*"--head igual"*)     echo "60 $SHA_IGUAL" ;;
  *"pr list"*"--head atras"*)     echo "61 $SHA_ATRAS" ;;
  *"pr list"*"--head avancou"*)   echo "62 $SHA_AVANCOU" ;;
  *"pr list"*"--head divergiu"*)  echo "63 $SHA_DIVERGIU" ;;
  *"pr list"*"--head ausente"*)   echo "64 $SHA_AUSENTE" ;;
  *"pr list"*"--head wtatras"*)   echo "65 $SHA_WTATRAS" ;;
  *"pr list"*"--head vivaatras"*) echo "66 $SHA_VIVAATRAS" ;;
  *"pr list"*"--head soremota"*)  echo "67 $SHA_SOREMOTA" ;;
  *"pr list"*"--head wtsemup"*)   echo "68 $SHA_WTSEMUP" ;;
  *"pr list"*) echo "" ;;
esac
exit 0
EOF
cat > "$TMP/bin/curl" <<EOF
#!/usr/bin/env bash
hdr="\$(cat)"
case "\$hdr" in *"Bearer segredo-123"*) ;; *) echo '{"message":"Bad credentials"}'; exit 22 ;; esac
head=""
for a in "\$@"; do case "\$a" in head=*) head="\${a#head=}" ;; esac; done
pr() { echo "[{\"number\":\$1,\"merged_at\":\"2026-10-01T00:00:00Z\",\"head\":{\"sha\":\"\$2\"}}]"; }
case "\$head" in
  dono:igual)     pr 60 $SHA_IGUAL ;;
  dono:atras)     pr 61 $SHA_ATRAS ;;
  dono:avancou)   pr 62 $SHA_AVANCOU ;;
  dono:divergiu)  pr 63 $SHA_DIVERGIU ;;
  dono:ausente)   pr 64 $SHA_AUSENTE ;;
  dono:vivaatras) pr 66 $SHA_VIVAATRAS ;;
  dono:soremota)  pr 67 $SHA_SOREMOTA ;;
  *) echo '[]' ;;
esac
EOF
chmod +x "$TMP/bin/gh" "$TMP/bin/curl"
git -C "$CLONE_REST" config git-sync.noGh true
git -C "$CLONE_REST" config git-sync.tokenVar TESTE_GH_TOKEN
git -C "$CLONE_REST" config git-sync.repo dono/repo
printf 'TESTE_GH_TOKEN=segredo-123\n' > "$TMP/tokens"

run() { # <clone> <args...>
  local c="$1"; shift
  GIT_SYNC_TOKENS_FILE="$TMP/tokens" PATH="$TMP/bin:$PATH" bash "$SCRIPT" --cwd "$c" --status-only --no-pr "$@" 2>&1
}

dry_run_casos() { # <rótulo> <saída>
  local r="$1" o="$2"
  check   "igual — SQUASH de PR #60 merged, head == tip → candidata a -D"                    "$r igual: candidata"                   "$o"
  check   "atras — SQUASH de PR #61 merged, tip contido no head do PR → candidata a -D"      "$r atrás do head: candidata, motivo próprio" "$o"
  refute  "^  atras — ! "                                                                      "$r atrás do head: não é preservada"    "$o"
  check   "avancou — ! PR #62 merged, mas o tip avançou depois do head do PR: preservada"    "$r avançou: preservada"                "$o"
  check   "divergiu — ! PR #63 merged, mas o tip divergiu do head do PR: preservada"         "$r divergiu: preservada com o motivo"  "$o"
  check   "ausente — ! PR #64 merged, mas o head do PR está indisponível.*: preservada"      "$r head ausente: indisponível"         "$o"
  refute  "ausente — .*avançou"                                                               "$r head ausente: nunca 'avançou'"      "$o"
  check   "vivaatras — PR #66 merged, tip contido no head do PR → candidata a -D"            "$r remoto vivo atrás do head: candidata" "$o"
  check   "soremota — PR #67 merged, remota contida no head do PR → git push origin --delete soremota" "$r remota atrás do head: comando de apagar" "$o"
}

echo "== gh: dry-run =="
OUT="$(run "$CLONE" --cleanup-dry-run)"
dry_run_casos gh "$OUT"
check  "CANDIDATO: .*/wt-atras \(wtatras\) \[squash: PR #65 merged, tip contido no head do PR\]" "gh worktree atrás do head: candidato" "$OUT"
refute "keep: .*/wt-atras "                                                                  "gh worktree atrás do head: não é keep" "$OUT"
if [ -z "$(git -C "$CLONE" for-each-ref refs/pull)" ]; then printf '  ok    %s\n' "a busca do head não deixa ref"
else printf '  FALHA %s\n' "ficou ref em refs/pull: $(git -C "$CLONE" for-each-ref refs/pull | tr '\n' ';')"; falhas=$((falhas+1)); fi

echo "== gh: aviso de worktree sem upstream atrás do head =="
OUT="$(run "$CLONE")"
check  "branch local 'wtsemup': os 1 commit\(s\) já estão em origin/main pelo PR #68"               "aviso reconhece o PR com o tip atrás do head" "$OUT"
refute "branch local 'wtsemup' .*NUNCA foi ao GitHub"                                               "aviso não manda pushar de volta"     "$OUT"

echo "== gh: apply =="
OUT="$(run "$CLONE" --cleanup-apply)"
check  "deleted branch atras \(-D — squash de PR #61 merged, tip contido no head do PR\)"   "gh apply: atrás do head apagada"       "$OUT"
check  "deleted branch igual \(-D — squash de PR #60 merged, head == tip\)"                 "gh apply: igual apagada"               "$OUT"
check  "skip avancou \(PR #62 merged, mas o tip avançou depois do head do PR"               "gh apply: avançou skip"                "$OUT"
check  "skip divergiu \(PR #63 merged, mas o tip divergiu do head do PR"                    "gh apply: divergiu skip"               "$OUT"
check  "skip ausente \(PR #64 merged, mas o head do PR está indisponível"                   "gh apply: ausente skip"                "$OUT"
check  "deleted branch vivaatras \(-D — PR #66 merged, tip contido no head do PR\)"         "gh apply: remoto vivo atrás apagada"   "$OUT"
check  "removed worktree .*/wt-atras"                                                       "gh apply: worktree atrás removido"     "$OUT"
for b in avancou divergiu ausente; do tem_branch "$CLONE" "$b" sim "gh apply: $b continua"; done
for b in atras igual vivaatras wtatras; do tem_branch "$CLONE" "$b" nao "gh apply: $b apagada"; done
if git ls-remote --exit-code --heads origin soremota >/dev/null 2>&1; then printf '  ok    %s\n' "remota soremota intacta"
else printf '  FALHA %s\n' "remota soremota apagada pelo script"; falhas=$((falhas+1)); fi

echo "== API REST: dry-run =="
git -C "$CLONE_REST" cat-file -e "$SHA_ATRAS^{commit}" 2>/dev/null && echo "  (aviso: cópia já tinha o head)"
OUT="$(run "$CLONE_REST" --cleanup-dry-run)"
dry_run_casos rest "$OUT"
refute "segredo-123"                                                                         "rest: token nunca aparece"           "$OUT"

echo "== API REST: apply =="
OUT="$(run "$CLONE_REST" --cleanup-apply)"
check  "deleted branch atras \(-D — squash de PR #61 merged, tip contido no head do PR\)"   "rest apply: atrás do head apagada"     "$OUT"
check  "skip ausente \(PR #64 merged, mas o head do PR está indisponível"                   "rest apply: ausente skip"              "$OUT"
for b in avancou divergiu ausente; do tem_branch "$CLONE_REST" "$b" sim "rest apply: $b continua"; done
for b in atras igual vivaatras; do tem_branch "$CLONE_REST" "$b" nao "rest apply: $b apagada"; done

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
