#!/usr/bin/env bash
# Prova de regressão do cleanup do plugin/skills/git-sync/scripts/git-sync.sh.
#
# O repo faz squash merge, então o commit da branch nunca vira ancestral de origin/main:
# `git branch -d` recusa e `merge-base --is-ancestor` dá falso para trabalho que JÁ está
# inteiro em main. Até 31/08/2026 o `--cleanup-apply` skipava 100% das branches por isso —
# num repo de time foram 20 branches gone, 20 skips e 2 worktrees `keep:`, todos falso
# positivo, e a limpeza teve que ser feita à mão. A prova real é o PR, via gh.
#
# O teste cobre também os dois modos de falhar PERIGOSAMENTE:
#   - cache de PR que vaza entre branches (bash 3.2 degrada `declare -A` calado: toda
#     chave vira índice 0, e uma branch sem PR herdaria o número da última consultada);
#   - lock de worktree cuja sessão morreu, que imunizaria o worktree pra sempre.
#
# E o buraco de 03/09/2026: o cleanup só olhava branch [gone]. Branch mergeada por PR cujo
# remoto sobreviveu (gh pr merge --delete-branch quebrando de dentro de um worktree) ou que
# nunca teve upstream ficava invisível — 10 no kit mentorados, 5 no CRM Multipedidos. A
# prova é PR merged + head do PR == tip; commit depois do merge é trabalho e fica.
#
# Até 28/09/2026 essa prova dupla só valia para as branches fora do [gone]. A branch [gone]
# e o worktree achavam o PR pelo nome e bastava: commit feito depois do merge, sem push,
# sumia no -D (ou no `worktree remove` seguido do -D). Agora os três passos exigem head do PR
# == tip. E o worktree "limpo" levava junto o env ignorado (.env* de qualquer pasta, .npmrc,
# .bunfig.toml), que o `status` não mostra e o `worktree remove` apaga sem recusar: agora ele
# fica quando algum desses arquivos difere do clone principal ou só existe no worktree.
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
SHA_SQUASHED="$(git rev-parse HEAD)"
git push -qu origin squashed
git checkout -q main
git merge -q --squash squashed && git commit -qm "trabalho (#42)"
git push -q origin main

# branch 'orfa': trabalho que NUNCA foi para main e não tem PR
git checkout -qb orfa
echo exclusivo > exclusivo.txt; git add exclusivo.txt; git commit -qm "so aqui"
git push -qu origin orfa

# branch 'semupstream': mergeada por squash mas nunca pushada — sem upstream, nunca fica [gone]
git checkout -q main
git checkout -qb semupstream
echo local > local.txt; git add local.txt; git commit -qm "so local"
SHA_SEMUPSTREAM="$(git rev-parse HEAD)"
git checkout -q main
git merge -q --squash semupstream >/dev/null && git commit -qm "so local (#43)"

# branch 'viva': mergeada por squash, remoto sobreviveu ao --delete-branch — track vazio
git checkout -qb viva
echo viva > viva.txt; git add viva.txt; git commit -qm "viva"
SHA_VIVA="$(git rev-parse HEAD)"
git push -qu origin viva
git checkout -q main
git merge -q --squash viva >/dev/null && git commit -qm "viva (#44)"

# branch 'avancou': PR mergeado, mas continuou commitando depois — tip != head do PR
git checkout -qb avancou
echo a > a.txt; git add a.txt; git commit -qm "a"
SHA_AVANCOU_PR="$(git rev-parse HEAD)"
git push -qu origin avancou
git checkout -q main
git merge -q --squash avancou >/dev/null && git commit -qm "a (#45)"
git checkout -q avancou
echo b > b.txt; git add b.txt; git commit -qm "b depois do merge"

# branch 'goneavancou': PR mergeado, remoto apagado no merge ([gone]) e um commit local
# depois do head do PR, sem push — achar o PR pelo nome não prova que ele levou tudo
git checkout -q main
git checkout -qb goneavancou
echo g > g.txt; git add g.txt; git commit -qm "g"
SHA_GONEAVANCOU_PR="$(git rev-parse HEAD)"
git push -qu origin goneavancou
git checkout -q main
git merge -q --squash goneavancou >/dev/null && git commit -qm "g (#47)"
git checkout -q goneavancou
echo g2 > g2.txt; git add g2.txt; git commit -qm "g2 depois do merge, sem push"

# branch 'wtavancou': o mesmo defeito, mas checkoutada num worktree (entra no fim do teste).
# Nunca pushada, para o passo (3) — que já exigia head == tip — deixá-la em paz até lá.
git checkout -q main
git checkout -qb wtavancou
echo w > w.txt; git add w.txt; git commit -qm "w"
SHA_WTAVANCOU_PR="$(git rev-parse HEAD)"
git checkout -q main
git merge -q --squash wtavancou >/dev/null && git commit -qm "w (#48)"
git checkout -q wtavancou
echo w2 > w2.txt; git add w2.txt; git commit -qm "w2 depois do merge, sem push"

git checkout -q main
git push -q origin main
git push -q origin --delete squashed >/dev/null 2>&1
git push -q origin --delete orfa >/dev/null 2>&1
git push -q origin --delete goneavancou >/dev/null 2>&1
git fetch -q --prune origin

# --- gh falso: 'squashed' tem PR #42; 'orfa' não tem nenhum ------------------
# Cada linha devolve "número headRefOid", o formato do --jq do script. É função porque o
# PR #49 ('wtok') só nasce na seção de worktrees: ela reescreve o gh com o oid dele.
mkdir -p "$TMP/bin"
SHA_WTOK=""
escreve_gh() {
  {
    echo '#!/usr/bin/env bash'
    echo 'case "$*" in'
    echo '  *"repo view"*) exit 0 ;;'
    echo "  *\"pr list\"*\"--head squashed\"*) echo \"42 $SHA_SQUASHED\"; exit 0 ;;"
    echo '  *"pr list"*"--head orfa"*)     echo "";   exit 0 ;;'
    echo "  *\"pr list\"*\"--head goneavancou\"*) echo \"47 $SHA_GONEAVANCOU_PR\"; exit 0 ;;"
    echo "  *\"pr list\"*\"--head wtavancou\"*)   echo \"48 $SHA_WTAVANCOU_PR\"; exit 0 ;;"
    echo "  *\"pr list\"*\"--head wtok\"*)        echo \"49 $SHA_WTOK\"; exit 0 ;;"
    echo "  *\"pr list\"*\"--head semupstream\"*) echo \"43 $SHA_SEMUPSTREAM\"; exit 0 ;;"
    echo "  *\"pr list\"*\"--head viva\"*)        echo \"44 $SHA_VIVA\"; exit 0 ;;"
    echo "  *\"pr list\"*\"--head avancou\"*)     echo \"45 $SHA_AVANCOU_PR\"; exit 0 ;;"
    echo '  *"pr list"*) echo ""; exit 0 ;;'
    echo 'esac'
    echo 'exit 0'
  } > "$TMP/bin/gh"
  chmod +x "$TMP/bin/gh"
}
escreve_gh

run() { PATH="$TMP/bin:$PATH" bash "$SCRIPT" --cwd "$CLONE" --status-only --no-pr "$@" 2>&1; }

echo "== dry-run distingue squash-merge de trabalho órfão =="
OUT="$(run --cleanup-dry-run)"
check 'squashed — SQUASH de PR #42 merged'      "squashed: reconhecida pelo PR"       "$OUT"
check 'orfa — ! sem PR merged'                  "orfa: marcada como suspeita"         "$OUT"
refute 'orfa — SQUASH'                          "orfa: NÃO herda PR de outra branch"  "$OUT"
check 'semupstream — PR #43 merged, head == tip' "semupstream: sem upstream, reconhecida pelo PR" "$OUT"
check 'viva — PR #44 merged, head == tip.*remoto ainda existe' "viva: remoto vivo, reconhecida e aponta o remoto" "$OUT"
check 'avancou — ! PR #45 merged, mas o tip avançou' "avancou: commit depois do merge preserva" "$OUT"
check 'goneavancou — ! PR #47 merged, mas o tip avançou' "goneavancou: [gone] com commit depois do merge preservada" "$OUT"
refute 'goneavancou — SQUASH'                   "goneavancou: não vira candidata a -D só pelo nome do PR" "$OUT"

echo "== apply deleta a provada e preserva a órfã =="
OUT="$(run --cleanup-apply)"
check 'deleted branch squashed \(-D — squash de PR #42 merged' "squashed: deletada com prova" "$OUT"
refute 'deleted branch goneavancou'             "goneavancou: não deletada"           "$OUT"
check 'skip goneavancou \(PR #47 merged, mas o tip avançou' "goneavancou: o skip diz por quê" "$OUT"
check 'skip orfa \(nenhum PR merged'            "orfa: preservada"                    "$OUT"
check 'deleted branch semupstream \(-D — PR #43 merged, head == tip\)' "semupstream: deletada com prova" "$OUT"
check 'deleted branch viva \(-D — PR #44 merged, head == tip\)'        "viva: deletada com prova"        "$OUT"
refute 'deleted branch avancou'                 "avancou: não deletada"               "$OUT"
has_branch() { git -C "$CLONE" show-ref --verify --quiet "refs/heads/$1"; }
if has_branch avancou; then printf '  ok    %s\n' "avancou: ainda existe no repo"
else printf '  FALHA %s\n' "avancou: deletada com commit depois do merge"; falhas=$((falhas+1)); fi
if has_branch semupstream || has_branch viva; then printf '  FALHA %s\n' "semupstream/viva: continuam no repo"; falhas=$((falhas+1))
else printf '  ok    %s\n' "semupstream e viva: sumiram do repo"; fi
if has_branch orfa; then printf '  ok    %s\n' "orfa: ainda existe no repo"
else printf '  FALHA %s\n' "orfa: foi deletada sem prova de merge"; falhas=$((falhas+1)); fi
if has_branch squashed; then printf '  FALHA %s\n' "squashed: continua no repo"; falhas=$((falhas+1))
else printf '  ok    %s\n' "squashed: sumiu do repo"; fi
if has_branch goneavancou; then printf '  ok    %s\n' "goneavancou: ainda existe no repo"
else printf '  FALHA %s\n' "goneavancou: -D apagou o commit feito depois do merge"; falhas=$((falhas+1)); fi

echo "== sem gh não deleta no escuro =="
OUT="$(PATH="/usr/bin:/bin" bash "$SCRIPT" --cwd "$CLONE" --status-only --no-pr --cleanup-apply 2>&1)"
refute 'deleted branch orfa'                    "orfa: intacta sem gh"                "$OUT"
refute 'deleted branch avancou'                 "avancou: intacta sem gh"             "$OUT"

echo "== lock stale não imuniza worktree =="
WT="$TMP/wt"; git -C "$CLONE" worktree add -q "$WT" orfa 2>/dev/null
git -C "$CLONE" worktree lock --reason "claude session teste (pid 999999 start now)" "$WT" 2>/dev/null
OUT="$(run --cleanup-dry-run)"
refute 'keep: .*(locked|sessão viva)'           "pid morto: não conta como sessão viva" "$OUT"
git -C "$CLONE" worktree unlock "$WT" 2>/dev/null
git -C "$CLONE" worktree lock --reason "claude session viva (pid $$ start now)" "$WT" 2>/dev/null
OUT="$(run --cleanup-dry-run)"
check 'locked \(sessão viva\)'                  "pid vivo: worktree protegido"        "$OUT"
git -C "$CLONE" worktree unlock "$WT" 2>/dev/null

# Branch recém-criada de origin/main é ancestral trivial de origin/main: o
# `merge-base --is-ancestor` chamava de "merged" o worktree limpo de uma sessão que
# acabou de abrir, e o --cleanup-apply o removia. Sessão do app desktop não trava o
# worktree, então o lock não protege. Mesmo defeito do warn-worktree-stale (0.48.1) e
# do worktree-gc (0.49.1).
echo "== worktree sem commit próprio não é candidato =="
# 'sessao-antiga' nasceu de origin/main e a main andou depois: tip na linha first-parent
git -C "$CLONE" worktree add -q -b sessao-antiga "$TMP/wt-antiga" origin/main 2>/dev/null
# 'mergeada': commit próprio que entrou em main por merge commit — continua candidata
git -C "$CLONE" worktree add -q -b mergeada "$TMP/wt-mergeada" origin/main 2>/dev/null
( cd "$TMP/wt-mergeada" && echo m > m.txt && git add m.txt && git commit -qm "mergeada" )
git -C "$CLONE" merge -q --no-ff -m "Merge mergeada (#46)" mergeada
# Env ignorado não aparece no `status` e o `git worktree remove` o apaga sem recusar. Os três
# worktrees abaixo estão mergeados e limpos: só a trava do env pode segurá-los.
mkdir -p "$CLONE/.git/info"; printf '.env*\n.npmrc\n.bunfig.toml\nbunfig.toml\nvendor/\n' >> "$CLONE/.git/info/exclude"
printf 'A=clone\n' > "$CLONE/.env.local"; printf 'registry=clone\n' > "$CLONE/.npmrc"
printf 'exact = true\n' > "$CLONE/bunfig.toml"
for n in envlocal envnpmrc envapps envbunfig envnpmrcsub envrepo; do
  git -C "$CLONE" worktree add -q -b "$n" "$TMP/wt-$n" origin/main 2>/dev/null
  ( cd "$TMP/wt-$n" && echo "$n" > "$n.txt" && git add "$n.txt" && git commit -qm "$n" )
  git -C "$CLONE" merge -q --no-ff -m "Merge $n" "$n"
done
printf 'A=editado na sessão\n' > "$TMP/wt-envlocal/.env.local"
printf 'registry=outro\n' > "$TMP/wt-envnpmrc/.npmrc"
mkdir -p "$TMP/wt-envapps/apps/x"; printf 'B=1\n' > "$TMP/wt-envapps/apps/x/.env.local"
# o bunfig.toml de projeto (sem ponto), um .npmrc de subpasta e um repo aninhado ignorado,
# que o remove apagaria com .git e tudo
printf 'exact = false\n' > "$TMP/wt-envbunfig/bunfig.toml"
mkdir -p "$TMP/wt-envnpmrcsub/apps/y"; printf 'registry=sub\n' > "$TMP/wt-envnpmrcsub/apps/y/.npmrc"
git init -q "$TMP/wt-envrepo/vendor/lib"
# 'wtok': squash de PR com head == tip e o .env.local igual ao do clone — é candidato
git -C "$CLONE" worktree add -q -b wtok "$TMP/wt-ok" origin/main 2>/dev/null
( cd "$TMP/wt-ok" && echo ok > ok.txt && git add ok.txt && git commit -qm "ok" )
SHA_WTOK="$(git -C "$TMP/wt-ok" rev-parse HEAD)"
git -C "$CLONE" merge -q --squash wtok >/dev/null 2>&1 && git -C "$CLONE" commit -qm "ok (#49)"
cp "$CLONE/.env.local" "$TMP/wt-ok/.env.local"
escreve_gh
git -C "$CLONE" push -q origin main
git -C "$CLONE" fetch -q origin
# sessão que acabou de abrir: branch nova e detached, os dois no tip de origin/main
git -C "$CLONE" worktree add -q -b sessao-nova "$TMP/wt-nova" origin/main 2>/dev/null
git -C "$CLONE" worktree add -q --detach "$TMP/wt-detached" origin/main 2>/dev/null
# PR #48 squash-mergeado e o worktree limpo, mas com um commit depois do head do PR
git -C "$CLONE" worktree add -q "$TMP/wt-avancou" wtavancou 2>/dev/null
OUT="$(run --cleanup-dry-run)"
refute "CANDIDATO: .*/wt-nova "                "branch recém-criada de origin/main: não é candidata"  "$OUT"
check  "keep: .*/wt-nova \(sessao-nova\) — sem commit próprio" "branch recém-criada: keep com motivo" "$OUT"
refute "CANDIDATO: .*/wt-antiga "              "branch sem commit, main andou depois: não é candidata" "$OUT"
refute "CANDIDATO: .*/wt-detached "            "detached no tip da main: não é candidato"             "$OUT"
check  "CANDIDATO: .*/wt-mergeada \(mergeada\)" "branch com commit mergeado: continua candidata"       "$OUT"
refute "CANDIDATO: .*/wt-avancou "             "commit depois do head do PR: worktree não é candidato" "$OUT"
check  "keep: .*/wt-avancou \(wtavancou\) — PR #48 merged, mas o tip avançou" "commit depois do head do PR: keep com motivo" "$OUT"
check  "CANDIDATO: .*/wt-ok \(wtok\) \[squash: PR #49 merged, head == tip\]" "squash com head == tip e env igual ao do clone: candidato" "$OUT"
check  "keep: .*/wt-envlocal \(envlocal\) — \.env\.local difere do clone principal" ".env.local editado no worktree: keep com o nome do arquivo" "$OUT"
check  "keep: .*/wt-envnpmrc \(envnpmrc\) — \.npmrc difere do clone principal" ".npmrc diferente: keep com o nome do arquivo" "$OUT"
check  "keep: .*/wt-envapps \(envapps\) — apps/x/\.env\.local difere do clone principal" "env aninhado que só existe no worktree: keep com o nome" "$OUT"
check  "keep: .*/wt-envbunfig \(envbunfig\) — bunfig\.toml difere do clone principal" "bunfig.toml de projeto diferente: keep com o nome" "$OUT"
check  "keep: .*/wt-envnpmrcsub \(envnpmrcsub\) — apps/y/\.npmrc difere do clone principal" ".npmrc de subpasta: keep com o nome" "$OUT"
check  "keep: .*/wt-envrepo \(envrepo\) — .*repo aninhado ignorado: vendor/lib/" "repo aninhado ignorado: keep com o caminho" "$OUT"
OUT="$(run --cleanup-apply)"
for w in wt-nova wt-antiga wt-detached wt-avancou wt-envlocal wt-envnpmrc wt-envapps wt-envbunfig wt-envnpmrcsub wt-envrepo; do
  if [ -d "$TMP/$w" ]; then printf '  ok    %s\n' "$w: sobreviveu ao --cleanup-apply"
  else printf '  FALHA %s\n' "$w: removido pelo --cleanup-apply"; falhas=$((falhas+1)); fi
done
for w in wt-mergeada wt-ok; do
  if [ -d "$TMP/$w" ]; then printf '  FALHA %s\n' "$w: não foi removido"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$w: removido pelo --cleanup-apply"; fi
done
if has_branch wtavancou; then printf '  ok    %s\n' "wtavancou: a branch com o commit depois do merge continua"
else printf '  FALHA %s\n' "wtavancou: branch apagada com commit depois do merge"; falhas=$((falhas+1)); fi

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
