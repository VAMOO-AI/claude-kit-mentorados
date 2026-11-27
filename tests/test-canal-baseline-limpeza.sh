#!/usr/bin/env bash
# Base de trabalho no gate do baseline e na limpeza-mac quando a default do GitHub é um canal
# que anda atrás da main.
#
# No kit, o origin/HEAD é o `stable` (o que o marketplace do mentorado segue) e todo PR entra
# na `main`. O git-sync (0.103.2) e o worktree-gc (0.103.3) já medem contra a main nesse caso.
# Faltavam dois:
#   - o gate do ship roda `collect.sh --diff origin/HEAD`: o range virava stable..HEAD, com
#     tudo o que a main andou desde o stable, e o PR era bloqueado por arquivo que não era dele;
#   - o inventario.sh da limpeza-mac media o "mergeado" contra origin/stable e perguntava por PR
#     com base stable. E a branch local `stable` saía merged(ancestral): o aplicar.sh dava
#     `branch -D stable`.
#
# Falham no base:
#   baseline  --diff origin/HEAD sai 0 e não acusa o .env que a main já tinha
#   limpeza   entregue (merge --no-ff na main) e squash (PR com base main) saem merged;
#             a branch stable não entra no plano e sobrevive ao aplicar
# Guardas: --diff origin/stable explícito continua medindo o range do stable (exit 1);
#   git-sync.defaultBranch stable vence a detecção; origin/HEAD = main não muda nada.
#
# Uso: bash tests/test-canal-baseline-limpeza.sh [collect.sh] [dir-dos-scripts-da-limpeza-mac]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
COLLECT="${1:-$RAIZ/plugin/skills/baseline/scripts/collect.sh}"
SCR="${2:-$RAIZ/plugin/skills/limpeza-mac/scripts}"
[ -f "$COLLECT" ] && [ -f "$SCR/inventario.sh" ] || { echo "scripts não encontrados"; exit 2; }
# o teste faz cd no repo sintético: caminho relativo passado na linha de comando quebraria
COLLECT="$(cd "$(dirname "$COLLECT")" && pwd)/$(basename "$COLLECT")"; SCR="$(cd "$SCR" && pwd)"
command -v jq >/dev/null || { echo "jq ausente"; exit 2; }
unset GH_TOKEN GITHUB_TOKEN GH_REPO

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/canal-bl.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando antes de tocar em /"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/bin" "$TMP/ws"

check() { # <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
se() { if "$@"; then echo ok; else echo fail; fi; }
tem_ref() { git -C "$R" rev-parse -q --verify "refs/heads/$1" >/dev/null; }
sem_env() { [ -f "$1" ] && jq -e '[.findings[]|select(.title=="Arquivo .env versionado")]|length==0' "$1" >/dev/null; }

ORIGIN="$TMP/origin.git"; R="$TMP/ws/repo"
git init -q --bare -b main "$ORIGIN"
git init -q -b main "$R"
cd "$R" || exit 2
git config commit.gpgsign false
echo '{"name":"x"}' > package.json; git add package.json; git commit -qm base
git remote add origin "$ORIGIN"
git push -q origin main main:refs/heads/stable
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/stable
# a main anda depois do stable: um .env versionado (problema de outro PR, já na main), uma
# branch entregue por merge --no-ff e o squash do PR #7
echo 'SEGREDO=1' > .env.producao; git add .env.producao; git commit -qm "env na main"
git checkout -qb entregue; echo e > e.txt; git add e.txt; git commit -qm entregue; git checkout -q main
git checkout -qb squash;   echo s > s.txt; git add s.txt; git commit -qm squash;   git checkout -q main
SQ="$(git rev-parse squash)"
git merge -q --no-ff -m "merge entregue" entregue
git commit -q --allow-empty -m "squash do PR #7"
git push -q origin main
git fetch -q origin
git branch -q stable origin/stable
git remote set-head origin stable >/dev/null
[ "$(git symbolic-ref refs/remotes/origin/HEAD)" = refs/remotes/origin/stable ] || { echo "fixture inválida: origin/HEAD não é o stable"; exit 2; }
git merge-base --is-ancestor origin/stable origin/main || { echo "fixture inválida: stable não é ancestral da main"; exit 2; }

echo "== baseline: --diff origin/HEAD mede contra a main =="
git checkout -qb feat/limpa origin/main
echo 'ok' > leia.txt; git add leia.txt; git commit -qm "feature limpa"
bash "$COLLECT" --diff origin/HEAD --out "$TMP/bl" >"$TMP/bl.log" 2>&1; rc=$?
check "--diff origin/HEAD: o PR limpo passa (exit $rc, esperado 0)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "--diff origin/HEAD: não acusa o .env que já estava na main" \
  "$(se sem_env "$TMP/bl/findings.json")"
check "--diff origin/HEAD: o stderr diz que a base virou a main" "$(se grep -q 'origin/HEAD = stable' "$TMP/bl.log")"
bash "$COLLECT" --diff origin/stable --out "$TMP/bl2" >/dev/null 2>&1; rc=$?
check "--diff origin/stable explícito mede o range do stable (exit $rc, esperado 1)" "$([ "$rc" = 1 ] && echo ok || echo fail)"
git config git-sync.defaultBranch stable
bash "$COLLECT" --diff origin/HEAD --out "$TMP/bl3" >/dev/null 2>&1; rc=$?
check "git-sync.defaultBranch stable vence a detecção (exit $rc, esperado 1)" "$([ "$rc" = 1 ] && echo ok || echo fail)"
git config --unset git-sync.defaultBranch
git checkout -q main

echo "== limpeza-mac: o inventário mede contra a main e protege o canal =="
# gh falso: só o PR #7 (head squash) foi mergeado, com base main
cat > "$TMP/bin/gh" <<STUB
#!/usr/bin/env bash
h=""; base=""
while [ \$# -gt 0 ]; do case "\$1" in --head) h="\$2"; shift;; --base) base="\$2"; shift;; esac; shift; done
[ "\$h" = squash ] && [ "\$base" = main ] && printf '7\t%s\n' "$SQ"
exit 0
STUB
printf '#!/usr/bin/env bash\necho Darwin\n' > "$TMP/bin/uname"
printf '#!/usr/bin/env bash\necho "pode remover: $2"; exit 0\n' > "$TMP/gc-stub"
chmod +x "$TMP/bin/gh" "$TMP/bin/uname" "$TMP/gc-stub"
export PATH="$TMP/bin:$PATH"
estado() { awk -F'\t' -v b="$1" '$2==b{print $4}' "$TMP/plano/branches.tsv"; }
POCO_TIMEOUT=2 bash "$SCR/inventario.sh" "$TMP/plano" "$TMP/ws" >/dev/null 2>&1
git -C "$R" remote set-head origin stable >/dev/null
check "entregue (merge na main): merged(ancestral) [$(estado entregue)]" "$([ "$(estado entregue)" = "merged(ancestral)" ] && echo ok || echo fail)"
check "squash (PR com base main): merged(PR#7) [$(estado squash)]"      "$([ "$(estado squash)" = "merged(PR#7)" ] && echo ok || echo fail)"
check "a branch stable não entra no plano [$(estado stable)]"            "$([ -z "$(estado stable)" ] && echo ok || echo fail)"
LIMPEZA_WORKTREE_GC="$TMP/gc-stub" bash "$SCR/aplicar.sh" "$TMP/plano" "$TMP/ledger" >"$TMP/aplicar.out" 2>&1
check "o aplicar remove a entregue" "$(se eval '! tem_ref entregue')"
check "a branch stable sobrevive ao aplicar" "$(se tem_ref stable)"
check "a main sobrevive ao aplicar" "$(se tem_ref main)"

echo "== limpeza-mac: worktree aberto no canal =="
WS="$R/.claude/worktrees/wt-stable"
git -C "$R" worktree add -q "$WS" stable
# índice velho: worktree mexido nas últimas 24h sai "ativa" e esconderia o estado
touch -t 202001010000 "$(git -C "$WS" rev-parse --path-format=absolute --git-path index)"
POCO_TIMEOUT=2 bash "$SCR/inventario.sh" "$TMP/plano" "$TMP/ws" >/dev/null 2>&1
git -C "$R" remote set-head origin stable >/dev/null
est_wt="$(awk -F'\t' -v p="$WS" '$3==p{print $6}' "$TMP/plano/worktrees.tsv")"
check "worktree no stable: estado canal [$est_wt]" "$([ "$est_wt" = canal ] && echo ok || echo fail)"
LIMPEZA_WORKTREE_GC="$TMP/gc-stub" bash "$SCR/aplicar.sh" "$TMP/plano" "$TMP/ledger2" >/dev/null 2>&1
check "o aplicar não remove o worktree do canal" "$(se test -d "$WS")"
check "nem a branch stable" "$(se tem_ref stable)"
git -C "$R" worktree remove "$WS" 2>/dev/null

echo "== guarda: origin/HEAD = main não muda nada =="
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
git -C "$R" checkout -qb outra-entregue; git -C "$R" commit -q --allow-empty -m oe; git -C "$R" checkout -q main
git -C "$R" merge -q --no-ff -m "merge oe" outra-entregue; git -C "$R" push -q origin main
POCO_TIMEOUT=2 bash "$SCR/inventario.sh" "$TMP/plano" "$TMP/ws" >/dev/null 2>&1
check "origin/HEAD = main: outra-entregue merged(ancestral) [$(estado outra-entregue)]" "$([ "$(estado outra-entregue)" = "merged(ancestral)" ] && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
