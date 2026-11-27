#!/usr/bin/env bash
# Prova da base de trabalho do plugin/scripts/worktree-gc.sh quando a default do GitHub é um
# canal que anda atrás da main.
#
# No kit, o origin/HEAD é o `stable` (o que o marketplace do mentorado segue) e todo PR entra
# na `main`. O gc tomava o stable como base: a ancestralidade era medida contra origin/stable
# e a prova de squash perguntava por PR com base stable. Toda branch já entregue na main saía
# "NÃO mergeada", e o --verificar que a skill worktrees roda antes do ExitWorktree dizia keep
# para tudo. O mesmo defeito que o git-sync corrigiu no 0.103.2. Agora, com origin/HEAD = X
# ancestral de origin/main, a base é a main e X vira canal protegido.
#
# Falham no base:
#   mergeada  branch entregue na main por merge --no-ff        → candidata, --verificar "pode remover"
#   squash    head de PR squash-mergeado com base main          → candidata
#   --apply   remove as duas
# Guardas (passam no base e no fix):
#   o worktree do canal nunca sai, nem no --apply; a branch sem commit próprio fica;
#   git-sync.defaultBranch vence a detecção; origin/HEAD que não é ancestral da main fica.
#
# Uso: bash tests/test-worktree-gc-base-de-trabalho.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/worktree-gc.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }
unset GH_TOKEN GITHUB_TOKEN GH_REPO

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wtgc-base.XXXXXX")"
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
codigo() { # <esperado> <obtido> <descrição>
  if [ "$1" = "$2" ]; then printf '  ok    %s (exit %s)\n' "$3" "$2"
  else printf '  FALHA %s (exit %s, esperado %s)\n' "$3" "$2" "$1"; falhas=$((falhas+1)); fi
}
no_disco() { # <worktree>
  if [ -d "$WTS/$1" ]; then printf '  ok    %s continua no disco\n' "$1"
  else printf '  FALHA %s foi apagado\n' "$1"; falhas=$((falhas+1)); fi
}

ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"; WTS="$CLONE/.claude/worktrees"
git init -q --bare -b main "$ORIGIN"
git init -q "$CLONE"
g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
G() { g -C "$CLONE" "$@"; }
echo base > "$CLONE/base.txt"; G add base.txt; G commit -qm base
G branch -M main; G remote add origin "$ORIGIN"
G push -q origin main main:refs/heads/stable
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/stable
G fetch -q origin
mkdir -p "$WTS"
novo_wt() { G worktree add -q -b "$1" "$WTS/wt-$1" "${2:-origin/main}"; }

novo_wt mergeada; g -C "$WTS/wt-mergeada" commit -q --allow-empty -m mergeada-1
novo_wt squash;   g -C "$WTS/wt-squash"   commit -q --allow-empty -m squash-1
SQ="$(G rev-parse squash)"
G merge -q --no-ff -m "merge mergeada" mergeada
G commit -q --allow-empty -m "squash do PR #7"
G push -q origin main
G fetch -q --prune origin
novo_wt nova
G worktree add -q -b stable "$WTS/wt-stable" origin/stable 2>/dev/null
G remote set-head origin stable >/dev/null
[ "$(G symbolic-ref refs/remotes/origin/HEAD)" = refs/remotes/origin/stable ] || { echo "fixture inválida: origin/HEAD não é o stable"; exit 2; }
G merge-base --is-ancestor origin/stable origin/main || { echo "fixture inválida: stable não é ancestral da main"; exit 2; }
G merge-base --is-ancestor mergeada origin/stable && { echo "fixture inválida: mergeada já está no stable"; exit 2; }

# gh falso: o PR #7 (head = squash) foi mergeado com base main; nenhum outro existe.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "auth status"*) exit 0 ;;
  *"pr list"*"--head squash"*"--base main"*) echo "7 $SQ" ;;
  *"pr list"*) echo "" ;;
  *api*) echo "[]" ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"
run() { ( cd "$CLONE" && PATH="$TMP/bin:$PATH" WORKTREE_GC_SKIP_FETCH=1 bash "$SCRIPT" "$@" 2>&1 ); }

echo "== origin/HEAD = stable atrás da main: o dry-run mede contra a main =="
OUT="$(run)"
check  "removeria: .*/wt-mergeada"                         "mergeada na main: candidata"                    "$OUT"
check  "removeria: .*/wt-squash"                           "squash com base main: candidata"                "$OUT"
check  "wt-stable +→ branch 'stable' \(mantido\)"          "worktree do canal: mantido"                     "$OUT"
refute "removeria: .*/wt-stable"                           "worktree do canal nunca é candidato"            "$OUT"
check  "wt-nova +→ branch 'nova' sem commit próprio"       "branch sem commit próprio: mantida"             "$OUT"
check  "origin/HEAD = stable"                              "cabeçalho diz por que a base é a main"          "$OUT"

echo "== --verificar =="
OUT="$(run --verificar "$WTS/wt-mergeada")"; rc=$?
check  "^pode remover: .*/wt-mergeada"                     "--verificar mergeada: pode remover"             "$OUT"
codigo 0 "$rc"                                             "--verificar mergeada"
OUT="$(run --verificar "$WTS/wt-stable")"; rc=$?
check  "^keep: .*branch 'stable' \(nunca removida\)"       "--verificar canal: keep"                        "$OUT"
codigo 1 "$rc"                                             "--verificar canal"

echo "== guardas: quem decide a base =="
G config git-sync.defaultBranch stable
OUT="$(run --verificar "$WTS/wt-mergeada")"
check  "^keep: .*NÃO mergeada"                             "git-sync.defaultBranch stable vence a detecção" "$OUT"
G config --unset git-sync.defaultBranch
# develop que não contém a main (não é ancestral dela): continua sendo a default
DEVTIP="$(G commit-tree -p origin/stable -m dev-1 "origin/stable^{tree}")"
G push -q origin "$DEVTIP":refs/heads/develop
G fetch -q origin
G remote set-head origin develop >/dev/null
OUT="$(run --verificar "$WTS/wt-mergeada")"
check  "^keep: .*NÃO mergeada"                             "origin/HEAD fora da linha da main fica a default" "$OUT"
G remote set-head origin stable >/dev/null

echo "== --apply =="
OUT="$(run --apply)"
check  "removido: .*/wt-mergeada"                          "--apply remove a mergeada"                      "$OUT"
check  "removido: .*/wt-squash"                            "--apply remove a do squash"                     "$OUT"
no_disco wt-stable
no_disco wt-nova
if G show-ref --verify -q refs/heads/stable; then echo "  ok    branch stable local continua"
else echo "  FALHA branch stable apagada"; falhas=$((falhas+1)); fi

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
