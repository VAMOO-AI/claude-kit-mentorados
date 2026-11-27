#!/usr/bin/env bash
# Prova do git-sync contra o trem de release (scripts/release-trem.sh + workflow release).
#
# Em 25/11/2026, na limpeza do Mac, o `--cleanup-dry-run` deste repo disse
#
#   ! branch local 'docs/whatsapp-inbox-tela-viva' tem 11 commit(s) e NUNCA foi ao GitHub
#
# para 4 branches que já estavam na main. Cada uma teve PR com head == tip (#373, #375, #376,
# #378), que entrou num release (#374, #377, #379: merge --no-ff de pull/<n>/head num
# release/<v>, PR do release por squash na main) e foi FECHADO, não mergeado, pelo job
# fecha-prs do workflow, que também apaga a remota. Seguir o aviso recriaria as remotas
# que o workflow apaga de propósito. Dois defeitos:
#   1. o origin/HEAD do repo é o `stable` e o trabalho entra na `main`: o "ahead" contra o
#      stable contava commits da main, e até branch nova sem commit próprio virava aviso;
#   2. a prova só aceitava PR MERGED. PR CLOSED cujo head está num PR MERGED da mesma base
#      (o release) também foi entregue.
#
# Casos, pelo gh e pela API REST:
#   trem        PR #10 fechado, head == tip, dentro do release #11 mergeado → sobra, candidata
#   tremgone    o mesmo, com upstream [gone]                              → candidata a -D
#   tremdepois  head no release, mas commit local depois                  → segue avisando
#   abandonada  PR #12 fechado sem release                                → segue avisando
#   forjada     a API diz que o release #11 a levou, o git não confirma   → segue avisando
#   nova        criada de origin/main, sem commit próprio                 → nenhum aviso
#   sozinha     nunca publicada                                           → segue avisando
#
# Uso: bash tests/test-git-sync-release-trem.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/git-sync/scripts/git-sync.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }
unset GH_TOKEN GITHUB_TOKEN

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitsync-trem.XXXXXX")"
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
commit() { echo "$1" > "$1.txt"; git add "$1.txt"; git commit -qm "$1"; }
commit base
git branch -M main; git remote add origin "$ORIGIN"
git push -q origin main
# stable: o canal do mentorado, atrás da main e branch padrão do repo (origin/HEAD)
git push -q origin main:refs/heads/stable
commit main-2; commit main-3; git push -q origin main
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/stable
git fetch -q origin
git remote set-head origin stable >/dev/null
git branch -q --set-upstream-to=origin/main main

# branches de feature: pushadas SEM -u (o estado das 4 do caso real), menos a tremgone
nova_br() { git checkout -q main; git checkout -qb "$1"; commit "$1-1"; }
nova_br trem;       git push -q origin trem;          SHA_TREM="$(git rev-parse HEAD)"
nova_br tremgone;   git push -qu origin tremgone;     SHA_TREMGONE="$(git rev-parse HEAD)"
nova_br tremdepois; git push -q origin tremdepois;    SHA_TREMDEPOIS="$(git rev-parse HEAD)"
nova_br abandonada; git push -q origin abandonada;    SHA_ABANDONADA="$(git rev-parse HEAD)"
nova_br forjada;    git push -q origin forjada;       SHA_FORJADA="$(git rev-parse HEAD)"
nova_br sozinha
git checkout -q main; git checkout -qb nova   # sem commit próprio
git checkout -q main
git push -q origin trem:refs/pull/10/head tremgone:refs/pull/13/head \
  tremdepois:refs/pull/14/head abandonada:refs/pull/12/head forjada:refs/pull/15/head

# O release sai de outro clone (o worktree do release-trem.sh, o squash no GitHub): o head
# dele só existe no origin, em refs/pull/11/head, que o fetch --prune do script não traz.
git clone -q "$ORIGIN" "$OUTRO" 2>/dev/null
cd "$OUTRO" || exit 2
git config user.email eu@x; git config user.name eu; git config commit.gpgsign false
git checkout -q -b release/1.0.0 origin/main
for n in 10 13 14; do
  git fetch -q origin "refs/pull/$n/head"
  git merge -q --no-ff --no-edit -m "Merge #$n" FETCH_HEAD
done
commit bump-1.0.0
SHA_RELEASE="$(git rev-parse HEAD)"
git push -q origin HEAD:refs/pull/11/head
git checkout -q main; git merge -q --squash release/1.0.0 >/dev/null; git commit -qm "release: 1.0.0 (#11)"
git push -q origin main
# o workflow fecha os PRs e apaga as remotas
git push -q origin --delete trem tremgone tremdepois abandonada forjada

cd "$CLONE" || exit 2
git checkout -q tremdepois; commit tremdepois-depois; git checkout -q main
git fetch -q --prune origin
git cat-file -e "$SHA_RELEASE^{commit}" 2>/dev/null && { echo "fixture inválida: head do release já está no clone"; exit 2; }
[ "$(git symbolic-ref refs/remotes/origin/HEAD)" = refs/remotes/origin/stable ] || { echo "fixture inválida: origin/HEAD não é o stable"; exit 2; }
git config git-sync.repo dono/repo
cp -R "$CLONE" "$TMP/clone-rest"
CLONE_REST="$TMP/clone-rest"
git -C "$CLONE_REST" config git-sync.noGh true
git -C "$CLONE_REST" config git-sync.tokenVar TESTE_GH_TOKEN
printf 'TESTE_GH_TOKEN=segredo-123\n' > "$TMP/tokens"

# gh falso: nenhum PR mergeado com estas heads; fechados com o que --jq imprimiria;
# commits/<sha>/pulls devolve o release (mergeado, base main) para os heads que ele levou.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"repo view"*) exit 0 ;;
  *"pr list"*"--state merged"*) echo "" ;;
  *"pr list"*"--state closed"*"--head trem "*|*"pr list"*"--state closed"*"--head trem") echo "10 $SHA_TREM main" ;;
  *"pr list"*"--state closed"*"--head tremgone"*)   echo "13 $SHA_TREMGONE main" ;;
  *"pr list"*"--state closed"*"--head tremdepois"*) echo "14 $SHA_TREMDEPOIS main" ;;
  *"pr list"*"--state closed"*"--head abandonada"*) echo "12 $SHA_ABANDONADA main" ;;
  *"pr list"*"--state closed"*"--head forjada"*)    echo "15 $SHA_FORJADA main" ;;
  *"api"*"commits/$SHA_TREM/pulls"*|*"api"*"commits/$SHA_TREMGONE/pulls"*|*"api"*"commits/$SHA_TREMDEPOIS/pulls"*|*"api"*"commits/$SHA_FORJADA/pulls"*)
    echo "11 $SHA_RELEASE" ;;
  *"api"*"/pulls"*) echo "" ;;
  *"pr list"*) echo "" ;;
esac
exit 0
EOF
cat > "$TMP/bin/curl" <<EOF
#!/usr/bin/env bash
hdr="\$(cat)"
case "\$hdr" in *"Bearer segredo-123"*) ;; *) echo '{"message":"Bad credentials"}'; exit 22 ;; esac
head=""; url=""
for a in "\$@"; do case "\$a" in head=*) head="\${a#head=}" ;; https://*) url="\$a" ;; esac; done
fechado() { echo "[{\"number\":\$1,\"merged_at\":null,\"state\":\"closed\",\"head\":{\"sha\":\"\$2\",\"ref\":\"x\"},\"base\":{\"ref\":\"main\"}}]"; }
release() { echo "[{\"number\":11,\"merged_at\":\"2026-11-25T00:00:00Z\",\"state\":\"closed\",\"head\":{\"sha\":\"$SHA_RELEASE\",\"ref\":\"release/1.0.0\"},\"base\":{\"ref\":\"main\"}}]"; }
case "\$url" in
  */commits/$SHA_TREM/pulls|*/commits/$SHA_TREMGONE/pulls|*/commits/$SHA_TREMDEPOIS/pulls|*/commits/$SHA_FORJADA/pulls) release; exit 0 ;;
  */commits/*/pulls) echo '[]'; exit 0 ;;
esac
case "\$head" in
  dono:trem)       fechado 10 $SHA_TREM ;;
  dono:tremgone)   fechado 13 $SHA_TREMGONE ;;
  dono:tremdepois) fechado 14 $SHA_TREMDEPOIS ;;
  dono:abandonada) fechado 12 $SHA_ABANDONADA ;;
  dono:forjada)    fechado 15 $SHA_FORJADA ;;
  *) echo '[]' ;;
esac
EOF
chmod +x "$TMP/bin/gh" "$TMP/bin/curl"

run() { # <clone> <args...>
  local c="$1"; shift
  GIT_SYNC_TOKENS_FILE="$TMP/tokens" PATH="$TMP/bin:$PATH" bash "$SCRIPT" --cwd "$c" --status-only --no-pr "$@" 2>&1
}

avisos() { # <rótulo> <saída>
  local r="$1" o="$2"
  refute "branch local 'trem' .*NUNCA foi ao GitHub"             "$r trem: não diz 'nunca foi ao GitHub'"     "$o"
  refute "push -u origin trem$"                                  "$r trem: não manda pushar de volta"          "$o"
  check  "branch local 'trem': .*release #11.*PR #10.*não pushe de volta" "$r trem: nomeia o release e o PR fechado" "$o"
  check  "branch local 'trem': os 1 commit\(s\) já estão em origin/main" "$r trem: conta só o commit dela, em origin/main" "$o"
  check  "branch local 'tremdepois' tem 2 commit\(s\) e NUNCA foi ao GitHub" "$r tremdepois: commit depois do release segue avisando" "$o"
  check  "branch local 'abandonada' tem 1 commit\(s\) e NUNCA foi ao GitHub" "$r abandonada: PR fechado sem release segue avisando" "$o"
  check  "branch local 'forjada' tem 1 commit\(s\) e NUNCA foi ao GitHub"    "$r forjada: API sem confirmação no git segue avisando" "$o"
  check  "branch local 'sozinha' tem 1 commit\(s\) e NUNCA foi ao GitHub"    "$r sozinha: nunca publicada segue avisando"  "$o"
  refute "branch local 'nova'"                                   "$r nova: sem commit próprio não vira aviso"  "$o"
}

dry_run() { # <rótulo> <saída>
  local r="$1" o="$2"
  check  "trem — PR #10 fechado pelo trem e entregue no release #11, head == tip → candidata a -D" "$r dry-run trem: candidata" "$o"
  check  "tremgone — SQUASH de PR #13 fechado pelo trem e entregue no release #11, head == tip → candidata a -D" "$r dry-run tremgone: candidata" "$o"
  check  "tremdepois — ! PR #14 fechado pelo trem e entregue no release #11, mas o tip avançou depois do head do PR: preservada" "$r dry-run tremdepois: preservada" "$o"
  refute "abandonada — .*candidata"                              "$r dry-run abandonada: não é candidata"       "$o"
  refute "forjada — .*candidata"                                 "$r dry-run forjada: não é candidata"          "$o"
}

echo "== gh: avisos =="
OUT="$(run "$CLONE")"
avisos gh "$OUT"

echo "== gh: dry-run =="
OUT="$(run "$CLONE" --cleanup-dry-run)"
dry_run gh "$OUT"
if [ -z "$(git -C "$CLONE" for-each-ref refs/pull)" ]; then printf '  ok    %s\n' "gh: a busca do head do release não deixa ref"
else printf '  FALHA %s\n' "ficou ref em refs/pull"; falhas=$((falhas+1)); fi

echo "== gh: apply =="
OUT="$(run "$CLONE" --cleanup-apply)"
check "deleted branch tremgone \(-D — squash de PR #13 fechado pelo trem e entregue no release #11, head == tip\)" "gh apply: tremgone apagada" "$OUT"
check "deleted branch trem \(-D — PR #10 fechado pelo trem e entregue no release #11, head == tip\)" "gh apply: trem apagada" "$OUT"
for b in trem tremgone; do tem_branch "$CLONE" "$b" nao "gh apply: $b apagada"; done
for b in tremdepois abandonada forjada sozinha nova; do tem_branch "$CLONE" "$b" sim "gh apply: $b continua"; done

echo "== API REST: avisos =="
OUT="$(run "$CLONE_REST")"
avisos rest "$OUT"
refute "segredo-123" "rest: token nunca aparece" "$OUT"

echo "== API REST: dry-run =="
OUT="$(run "$CLONE_REST" --cleanup-dry-run)"
dry_run rest "$OUT"

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
