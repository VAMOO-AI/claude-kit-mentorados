#!/usr/bin/env bash
# Prova da base de trabalho do plugin/skills/git-sync/scripts/git-sync.sh quando a default do
# GitHub é um canal que anda atrás da main.
#
# No kit, o origin/HEAD é o `stable` (o que o marketplace do mentorado segue) e todo PR entra
# na `main`. O #380 (0.103.1) corrigiu só o aviso "NUNCA foi ao GitHub". O resto do script
# ainda media tudo contra o stable: branch mergeada na main saía "não mergeado em
# origin/stable", branch atrás da main não avisava, o --voltar-main levava o clone para o
# stable. Agora, com origin/HEAD = X ancestral de origin/main, a base é a main e X vira canal
# protegido.
#
# Falham no base:
#   wtmergeada  worktree com branch mergeada na main (merge --no-ff) → candidato a remoção
#   atras       worktree criada do stable, 2 atrás da main            → aviso "atrás de origin/main"
#   gonemerg    branch [gone] mergeada na main                        → "mergeada (branch -d resolve)"
#   --voltar-main                                                     → termina na main
# Guardas (passam no base e no fix):
#   o canal nunca vira "git push origin --delete stable" nem "stable atrás de origin/main";
#   origin/HEAD à frente da main (develop) fica; --default-branch e git-sync.defaultBranch vencem.
#
# Uso: bash tests/test-git-sync-base-de-trabalho.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/git-sync/scripts/git-sync.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }
unset GH_TOKEN GITHUB_TOKEN

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitsync-base.XXXXXX")"
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

ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"
git init -q --bare "$ORIGIN"
git init -q "$CLONE"
cd "$CLONE" || exit 2
git config user.email eu@x; git config user.name eu; git config commit.gpgsign false
commit() { echo "$1" > "$1.txt"; git add "$1.txt"; git commit -qm "$1"; }
commit base
git branch -M main; git remote add origin "$ORIGIN"
git push -q origin main main:refs/heads/stable
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/stable

# atras: nasce do stable, com commit próprio; a main anda 2 depois
git checkout -qb atras; commit atras-1; git push -qu origin atras; git checkout -q main
# wtmergeada e gonemerg: entram na main por merge --no-ff (ancestrais da main, não do stable)
git checkout -qb wtmergeada; commit wtmergeada-1; git checkout -q main
git checkout -qb gonemerg;   commit gonemerg-1;   git push -qu origin gonemerg; git checkout -q main
git merge -q --no-ff --no-edit wtmergeada
git merge -q --no-ff --no-edit gonemerg
commit main-2
git push -q origin main
git push -q origin --delete gonemerg
git fetch -q --prune origin
git remote set-head origin stable >/dev/null
git branch -q --set-upstream-to=origin/main main
[ "$(git symbolic-ref refs/remotes/origin/HEAD)" = refs/remotes/origin/stable ] || { echo "fixture inválida: origin/HEAD não é o stable"; exit 2; }
git merge-base --is-ancestor origin/stable origin/main || { echo "fixture inválida: stable não é ancestral da main"; exit 2; }

git worktree add -q "$TMP/wt-mergeada" wtmergeada
git worktree add -q "$TMP/wt-atras" atras
git worktree add -q "$TMP/wt-stable" -b stable --track origin/stable >/dev/null 2>&1
# o clone principal fica numa feature limpa, para o --voltar-main ter o que fazer
git checkout -qb feat/volta
cp -R "$CLONE" "$TMP/clone-volta"

# gh falso: enxerga o repo e não acha PR nenhum (a prova aqui é a ancestralidade)
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\ncase "$*" in *"repo view"*) exit 0 ;; esac\necho ""\nexit 0\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
run() { # <clone> <args...>
  local c="$1"; shift
  PATH="$TMP/bin:$PATH" bash "$SCRIPT" --cwd "$c" --no-pr "$@" 2>&1
}

echo "== origin/HEAD = stable atrás da main: a base é a main =="
OUT="$(run "$CLONE" --status-only)"
check  "^default: +main .*origin/HEAD = stable"                   "cabeçalho diz main e o porquê"                  "$OUT"
check  "atras \(.*\): 5 commit\(s\) atrás de origin/main"         "atras: avisa que está atrás da main"            "$OUT"
refute "stable \(.*\): [0-9]+ commit\(s\) atrás"                   "canal checkoutado não recebe 'atrás'"           "$OUT"
refute "stable \(.*\): alterações não commitadas"                   "canal limpo não recebe aviso de edição"         "$OUT"
check  "default=main "                                              "rodapé diz main"                                "$OUT"

echo "== cleanup dry-run =="
OUT="$(run "$CLONE" --status-only --cleanup-dry-run)"
check  "gonemerg — mergeada \(branch -d resolve\)"                  "gonemerg: mergeada na main"                     "$OUT"
check  "CANDIDATO: .*/wt-mergeada \(wtmergeada\)"                   "wt-mergeada: candidato a remoção"               "$OUT"
refute "não mergeado em origin/stable"                              "nada é medido contra o stable"                  "$OUT"
refute "^  stable — "                                               "canal nunca vira candidato a --delete"          "$OUT"
refute "push origin --delete stable"                                "nenhum comando apaga o canal"                   "$OUT"
refute "CANDIDATO: .*\(stable\)"                                    "worktree do canal não é candidato"              "$OUT"

echo "== clone sem o stable local: o canal só existe no remoto =="
# O estado perigoso: sem cópia local, "remotas suas sem cópia local" via o stable (autor = eu,
# contido na main) e imprimia o comando que apaga a branch padrão do GitHub.
git clone -q -b main "$ORIGIN" "$TMP/clone-limpo" 2>/dev/null
git -C "$TMP/clone-limpo" config user.email eu@x; git -C "$TMP/clone-limpo" config user.name eu
git -C "$TMP/clone-limpo" show-ref --verify -q refs/heads/stable && { echo "fixture inválida: clone-limpo tem stable local"; exit 2; }
OUT="$(run "$TMP/clone-limpo" --status-only --cleanup-dry-run)"
check  "^default: +main "                                           "clone limpo: base main"                         "$OUT"
refute "^  stable — "                                               "clone limpo: canal não vira candidato a --delete" "$OUT"
refute "push origin --delete stable"                                "clone limpo: nenhum comando apaga o canal"      "$OUT"

echo "== --voltar-main volta para a main =="
OUT="$(run "$TMP/clone-volta" --voltar-main)"
check  "branch final: main "                                        "--voltar-main termina na main"                  "$OUT"
refute "(branch final:|Retorno a|→) stable"                          "--voltar-main nem tenta ir para o canal"        "$OUT"

echo "== guardas: quem decide a default =="
OUT="$(run "$CLONE" --status-only --default-branch stable)"
check  "^default: +stable "                                         "--default-branch stable vence a detecção"       "$OUT"
git -C "$CLONE" config git-sync.defaultBranch stable
OUT="$(run "$CLONE" --status-only)"
check  "^default: +stable "                                         "git-sync.defaultBranch vence a detecção"        "$OUT"
git -C "$CLONE" config --unset git-sync.defaultBranch
# develop à frente da main (git flow): a default do GitHub é onde o trabalho entra, fica
DEVTIP="$(git -C "$CLONE" commit-tree -p origin/main -m dev-1 "origin/main^{tree}")"
git -C "$CLONE" push -q origin "$DEVTIP":refs/heads/develop
git -C "$CLONE" fetch -q origin
git -C "$CLONE" remote set-head origin develop >/dev/null
OUT="$(run "$CLONE" --status-only)"
check  "^default: +develop "                                        "origin/HEAD à frente da main continua a default" "$OUT"
git -C "$CLONE" remote set-head origin main >/dev/null
OUT="$(run "$CLONE" --status-only)"
check  "^default: +main \([0-9a-f]+ = origin/main\)$"               "origin/HEAD = main: cabeçalho de sempre"        "$OUT"

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
