#!/usr/bin/env bash
# Prova de regressão: o gh do plugin/skills/git-sync/scripts/git-sync.sh consulta o repo do origin.
#
# Sem `gh repo set-default`, o gh escolhe o repo base pelo NOME do remote e prefere
# `upstream` a `origin`. Em 07/10/2026, no linkbio-vamoo (origin = VAMOO-AI/linkbio-vamoo,
# upstream = VAMOO-AI/linkbio-template com push DISABLE), todas as chamadas do script
# consultaram o template: "### open PRs" disse "(nenhum PR aberto)" com o PR #15 aberto, os
# mergeados listados eram do template e o cleanup deu dois vereditos errados —
# `docs/agents-md-ponte` casou com o PR #5 do template ("tip avançou: preservada", o certo era
# o #7, head == tip) e `docs/deploy-md` saiu "sem PR merged" (o certo era o #14 merged).
#
# O script agora exporta GH_REPO com o slug do origin (ou do `git config git-sync.repo`) antes
# do primeiro gh, sem passar por cima de um GH_REPO que já venha do ambiente. A sondagem de
# contas (`GH_TOKEN=… gh repo view`) também tem que olhar o origin: a conta ativa enxergar o
# template público não quer dizer que enxerga o repo privado.
#
# Uso: bash tests/test-git-sync-gh-repo-origin.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/git-sync/scripts/git-sync.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitsync-ghrepo.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando antes de tocar em /"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

check() { # <esperado-regex> <descrição> <saída>
  if grep -qE "$1" <<<"$3"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if grep -qE "$1" <<<"$3"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}

# --- fixture ------------------------------------------------------------------
# Os bares ficam sob .../github.com/acme/: o script tira o slug da URL do origin, e um path
# local sem "github.com" daria slug vazio — o teste passaria igual com e sem o fix.
# (insteadOf não serve: o `git remote get-url` expande e devolve o path local.)
APP="$TMP/github.com/acme/app.git"; TEMPLATE="$TMP/github.com/acme/template.git"; CLONE="$TMP/clone"
mkdir -p "$TMP/github.com/acme"
git init -q --bare "$APP"
git init -q --bare "$TEMPLATE"
git init -q "$CLONE"
cd "$CLONE"
git config user.email t@t; git config user.name t; git config commit.gpgsign false
echo base > base.txt; git add base.txt; git commit -qm base
SHA_BASE="$(git rev-parse HEAD)"
git branch -M main; git remote add origin "$APP"; git push -qu origin main
git remote add upstream "$TEMPLATE"
git remote set-url --push upstream DISABLE

# docs/deploy-md: PR #14 do app, squash, remoto apagado no merge ([gone])
git checkout -qb docs/deploy-md
echo d > deploy.md; git add deploy.md; git commit -qm "docs: deploy"
SHA_DEPLOY="$(git rev-parse HEAD)"
git push -qu origin docs/deploy-md
git checkout -q main
git merge -q --squash docs/deploy-md >/dev/null && git commit -qm "docs: deploy (#14)"

# docs/agents-md-ponte: PR #7 do app, squash, remoto vivo. O template tem um PR #5 com a
# MESMA branch e outro head — é ele que o gh achava.
git checkout -qb docs/agents-md-ponte
echo p > ponte.md; git add ponte.md; git commit -qm "docs: ponte"
SHA_PONTE="$(git rev-parse HEAD)"
git push -qu origin docs/agents-md-ponte
git checkout -q main
git merge -q --squash docs/agents-md-ponte >/dev/null && git commit -qm "docs: ponte (#7)"

git push -q origin main
git push -q origin --delete docs/deploy-md >/dev/null 2>&1
git fetch -q --prune origin

# --- gh falso que resolve o repo base como o gh de verdade ----------------------
# Ordem: GH_REPO; remote marcado por `gh repo set-default` (remote.<x>.gh-resolved);
# remote `upstream`; `origin`. Cada chamada grava "<repo>|<args>" em $GH_LOG.
# Contas: tok-cliente enxerga tudo; tok-pessoal só o template (público).
mkdir -p "$TMP/bin"
GH_LOG="$TMP/gh.log"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
tok="${GH_TOKEN:-${FAKE_GH_ACTIVE:-tok-cliente}}"
case "$*" in
  "auth status"*)
    ap=true; ac=false; [ "${FAKE_GH_ACTIVE:-tok-cliente}" = tok-cliente ] && { ap=false; ac=true; }
    printf '%s\n' "github.com" \
      "  ✓ Logged in to github.com account pessoal (keyring)" "  - Active account: $ap" \
      "  ✓ Logged in to github.com account cliente (keyring)" "  - Active account: $ac"
    exit 0 ;;
  "auth token -u pessoal") echo tok-pessoal; exit 0 ;;
  "auth token -u cliente") echo tok-cliente; exit 0 ;;
esac
repo="${GH_REPO:-}"
# `gh repo view` sem argumento IGNORA o GH_REPO e resolve pelos remotes (gh 2.102, conferido
# à mão em 07/10/2026); só o repo passado como argumento vale. Um fake que respeitasse o
# GH_REPO aqui aprovaria a sondagem de contas olhando o template.
if [ "${1:-}" = repo ] && [ "${2:-}" = view ]; then
  repo=""; case "${3:-}" in ""|-*) ;; *) repo="$3" ;; esac
fi
if [ -z "$repo" ]; then
  r="$(git config --get-regexp '^remote\..*\.gh-resolved$' 2>/dev/null | head -1 | sed -E 's/^remote\.(.*)\.gh-resolved .*/\1/')"
  if [ -z "$r" ]; then
    for n in upstream github origin; do git remote get-url "$n" >/dev/null 2>&1 && { r="$n"; break; }; done
  fi
  repo="$(git remote get-url "$r" 2>/dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"
fi
echo "$repo|$*" >> "$GH_LOG"
sees() { [ "$tok" = tok-cliente ] || [ "$repo" = acme/template ]; }
nao_ve() { echo "GraphQL: Could not resolve to a Repository with the name '$repo'. (repository)" >&2; exit 1; }
head=""; prev=""
for a in "$@"; do [ "$prev" = "--head" ] && head="$a"; prev="$a"; done
case "$*" in
  "repo view"*) sees && exit 0; nao_ve ;;
  "pr list"*)
    sees || nao_ve
    case "$repo|$*" in
      "acme/app|"*"--state merged"*"--head"*)
        case "$head" in
          docs/deploy-md) echo "14 $FAKE_SHA_DEPLOY" ;;
          docs/agents-md-ponte) echo "7 $FAKE_SHA_PONTE" ;;
        esac ;;
      "acme/template|"*"--state merged"*"--head"*)
        [ "$head" = docs/agents-md-ponte ] && echo "5 $FAKE_SHA_BASE" ;;
      "acme/app|"*"--state merged"*)     echo "  #14 docs: deploy (ruan, 1 day ago)" ;;
      "acme/template|"*"--state merged"*) echo "  #5 docs: ponte do template (outro, 3 days ago)" ;;
      "acme/app|"*"--state open"*)       echo "  #15 feat: link novo (feat/link-novo, ruan)" ;;
      "acme/template|"*"--state open"*)  echo "  (nenhum PR aberto)" ;;
      *"--state open"*)                  echo "  (nenhum PR aberto)" ;;
      # O script daqui, fora do modo time, chama `gh pr list --limit 20` sem `--state open`.
      "acme/app|"*)                      echo "  #15 feat: link novo (feat/link-novo, ruan)" ;;
      "acme/template|"*)                 echo "  (nenhum PR aberto)" ;;
    esac
    exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"

# `env -u`: GH_TOKEN/GH_REPO herdados da máquina de quem roda mudariam o caminho do script.
# Quem testa a precedência passa o valor explicitamente na chamada.
# run [VAR=valor …] [flags do script…] — os VAR=valor vão para o env do script
run() {
  local envs=(); while [[ "${1:-}" == *=* ]]; do envs+=("$1"); shift; done
  : > "$GH_LOG"
  env -u GH_TOKEN -u GITHUB_TOKEN -u GH_REPO GH_LOG="$GH_LOG" PATH="$TMP/bin:$PATH" \
    FAKE_SHA_DEPLOY="$SHA_DEPLOY" FAKE_SHA_PONTE="$SHA_PONTE" FAKE_SHA_BASE="$SHA_BASE" \
    ${envs[@]+"${envs[@]}"} bash "$SCRIPT" --cwd "$CLONE" --status-only "$@" 2>&1
}
log() { cat "$GH_LOG" 2>/dev/null; }

echo "== upstream sem set-default: open PRs vêm do origin =="
OUT="$(run --no-team)"; LOG="$(log)"
check '#15 feat: link novo'                       "lista o PR aberto do origin"            "$OUT"
refute 'nenhum PR aberto'                         "não diz que não há PR"                  "$OUT"
check '^acme/app\|pr list'                        "o gh consultou o app"                   "$LOG"
refute '^acme/template\|'                         "nenhuma chamada caiu no template"       "$LOG"

echo "== --team: os mergeados também são do origin =="
OUT="$(run --team)"; LOG="$(log)"
check '#14 docs: deploy'                          "mergeado do app"                        "$OUT"
refute 'ponte do template'                        "nada do template"                       "$OUT"
refute '^acme/template\|'                         "nenhuma chamada caiu no template"       "$LOG"

echo "== --cleanup-dry-run: o veredito vem do PR do origin =="
OUT="$(run --no-team --no-pr --cleanup-dry-run)"; LOG="$(log)"
check 'docs/deploy-md — SQUASH de PR #14 merged, head == tip'      "[gone] provada pelo #14"   "$OUT"
refute 'docs/deploy-md — ! sem PR merged'                          "não diz 'sem PR merged'"   "$OUT"
check 'docs/agents-md-ponte — PR #7 merged, head == tip'           "remoto vivo provado pelo #7" "$OUT"
refute 'PR #5'                                                     "o #5 do template não aparece" "$OUT"
refute '^acme/template\|'                                          "nenhuma chamada caiu no template" "$LOG"

echo "== conta ativa enxerga só o template: a sondagem olha o origin e troca de conta =="
OUT="$(run FAKE_GH_ACTIVE=tok-pessoal --no-team)"; LOG="$(log)"
check 'conta gh: cliente — a ativa não enxerga este repositório' "acha a conta que vê o app" "$OUT"
check '#15 feat: link novo'                                       "lista o PR pela conta certa" "$OUT"
refute '^acme/template\|'                                         "a sondagem não caiu no template" "$LOG"
refute 'tok-'                                                     "token não vaza na saída"   "$OUT"

echo "== GH_REPO do ambiente tem precedência =="
OUT="$(run GH_REPO=acme/template --no-team)"; LOG="$(log)"
check '^acme/template\|pr list'                   "usa o GH_REPO da pessoa"                "$LOG"
refute '^acme/app\|'                              "não sobrescreve com o origin"           "$LOG"

echo "== git config git-sync.repo vence o origin =="
git -C "$CLONE" config git-sync.repo acme/outro
OUT="$(run --no-team)"; LOG="$(log)"
git -C "$CLONE" config --unset git-sync.repo
check '^acme/outro\|pr list'                      "o gh consulta o repo do override"       "$LOG"
refute '^acme/(app|template)\|'                   "nem o origin nem o upstream"            "$LOG"

echo "== origin fora do GitHub: não exporta GH_REPO (o gh resolve sozinho) =="
git -C "$CLONE" remote set-url origin "$TMP/fora/app.git"
mkdir -p "$TMP/fora"; cp -R "$APP" "$TMP/fora/app.git"
OUT="$(run --no-team)"; LOG="$(log)"
git -C "$CLONE" remote set-url origin "$APP"
refute '^\|'                                      "nenhuma chamada com repo vazio forçado" "$LOG"
check '^acme/template\|pr list'                   "sem slug, segue a resolução do gh"      "$LOG"

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
