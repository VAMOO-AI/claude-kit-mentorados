#!/usr/bin/env bash
# O inventario.sh + aplicar.sh da skill limpeza-mac apagam só o que é seguro por construção?
#
# Cada caso é um jeito de perder trabalho: worktree recém-criada (sem commit, logo
# "ancestral do default") saindo como mergeada, branch com commit depois do merge, branch
# cujo SHA é só ancestral do head do PR (aqui a prova é head == tip), worktree suja, lock de
# sessão viva, .next do prebuilt da Vercel, órfã com código dentro, commit em worktree
# detached depois do inventário, branch empilhada mergeada em outra feature, .env ignorado
# dentro de worktree "limpa" e node_modules julgado pela data do commit, não do checkout.
# Toda remoção de worktree passa pelo `worktree-gc.sh --verificar <caminho>`: um stub
# responde "keep" ou "pode remover", e sem o modo (exit 2) o worktree fica.
#
# Roda no Ubuntu do CI: o gh é um stub que lê $TMP/prs (head base número sha) e respeita
# --base, e o `uname` é um stub que responde Darwin (ou Linux, no caso da saída limpa).
#
# Uso: bash tests/test-limpeza-mac.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SCR="$RAIZ/plugin/skills/limpeza-mac/scripts"
UNAME_REAL="$(uname -s)"

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
existe() { [ -e "$1" ] && echo ok || echo fail; }
sumiu()  { [ -e "$1" ] && echo fail || echo ok; }
tem_branch()   { git -C "$R" rev-parse -q --verify "refs/heads/$1" >/dev/null && echo ok || echo fail; }
sem_branch()   { git -C "$R" rev-parse -q --verify "refs/heads/$1" >/dev/null && echo fail || echo ok; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/limpeza-mac.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"   # macOS: /var → /private/var, e o git devolve o caminho real
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# HOME de mentira: os poços (~/Library, ~/.npm, ~/.claude/projects) não medem a máquina de quem roda
export HOME="$TMP/home"
mkdir -p "$TMP/bin" "$TMP/ws" "$HOME"

cat > "$TMP/bin/gh" <<STUB
#!/usr/bin/env bash
h=""; base=""
while [ \$# -gt 0 ]; do case "\$1" in --head) h="\$2"; shift;; --base) base="\$2"; shift;; esac; shift; done
[ -f "$TMP/prs" ] || exit 0
while read -r ph pb n sha; do
  [ "\$ph" = "\$h" ] && { [ -z "\$base" ] || [ "\$pb" = "\$base" ]; } && printf '%s\t%s\n' "\$n" "\$sha"
done < "$TMP/prs"
STUB
cat > "$TMP/bin/uname" <<STUB
#!/usr/bin/env bash
cat "$TMP/uname-s"
STUB
echo Darwin > "$TMP/uname-s"
# du espião: o poço .cache/uv nunca responde. exec: o corte mata este pid
DU_REAL="$(command -v du)"
cat > "$TMP/bin/du" <<STUB
#!/usr/bin/env bash
case "\$*" in *"/.cache/uv"*) exec sleep 20 ;; esac
exec "$DU_REAL" "\$@"
STUB
chmod +x "$TMP/bin/du"
# stub do worktree-gc: anota a chamada; "keep" para o caminho listado em $TMP/gc-keep
cat > "$TMP/gc-stub" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMP/gc.log"
printf '%s\n' "\${WORKTREE_GC_SKIP_FETCH:-}" >> "$TMP/gc-env.log"
[ "\$1" = --verificar ] || { echo "arg desconhecido: \$1" >&2; exit 2; }
if [ -f "$TMP/gc-keep" ] && grep -qxF "\$2" "$TMP/gc-keep"; then echo "keep: \$2 — stub"; exit 1; fi
echo "pode remover: \$2"; exit 0
STUB
# o worktree-gc.sh de antes do --verificar: recusa o argumento com exit 2
printf '#!/usr/bin/env bash\necho "arg desconhecido: $1" >&2\nexit 2\n' > "$TMP/gc-antigo"
chmod +x "$TMP/bin/gh" "$TMP/bin/uname" "$TMP/gc-stub" "$TMP/gc-antigo"
export PATH="$TMP/bin:$PATH"
export LIMPEZA_WORKTREE_GC="$TMP/gc-stub"

echo "== fora do macOS: sai 0, diz por quê e não escreve nada =="
echo Linux > "$TMP/uname-s"
out="$(bash "$SCR/inventario.sh" "$TMP/plano-linux" "$TMP/ws" 2>&1)"; rc=$?
check "inventário sai 0 fora do Darwin"           "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "inventário diz que é só macOS"             "$(printf '%s' "$out" | grep -q 'só macOS' && echo ok || echo fail)"
check "inventário não cria o plano"               "$(sumiu "$TMP/plano-linux")"
out="$(bash "$SCR/aplicar.sh" "$TMP/plano-linux" "$TMP/ledger-linux" 2>&1)"; rc=$?
check "aplicar sai 0 fora do Darwin"              "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "aplicar diz que é só macOS"                "$(printf '%s' "$out" | grep -q 'só macOS' && echo ok || echo fail)"
check "aplicar não cria o ledger"                 "$(sumiu "$TMP/ledger-linux")"
echo Darwin > "$TMP/uname-s"

echo "== raízes: padrão genérico, LIMPEZA_RAIZES troca =="
for d in Developer Projects code Sites outra; do
  git init -q "$HOME/$d/proj-$d"
done
bash "$SCR/inventario.sh" "$TMP/plano-raiz" >/dev/null 2>&1
check "padrão acha ~/Developer"                    "$(grep -qx "$HOME/Developer/proj-Developer" "$TMP/plano-raiz/repos.txt" && echo ok || echo fail)"
check "padrão acha ~/Projects e ~/code"            "$(grep -c "proj-Projects\|proj-code" "$TMP/plano-raiz/repos.txt" | grep -qx 2 && echo ok || echo fail)"
check "padrão não traz pasta fora da lista (~/Sites)" "$(grep -q proj-Sites "$TMP/plano-raiz/repos.txt" && echo fail || echo ok)"
LIMPEZA_RAIZES="$HOME/outra:$HOME/Sites" bash "$SCR/inventario.sh" "$TMP/plano-env" >/dev/null 2>&1
check "LIMPEZA_RAIZES (separada por :) troca as raízes" \
  "$([ "$(wc -l < "$TMP/plano-env/repos.txt" | tr -d ' ')" = 2 ] && grep -q proj-outra "$TMP/plano-env/repos.txt" && echo ok || echo fail)"
LIMPEZA_RAIZES="$HOME/outra" bash "$SCR/inventario.sh" "$TMP/plano-arg" "$HOME/code" >/dev/null 2>&1
check "raiz na linha de comando vence a variável"  "$(grep -qx "$HOME/code/proj-code" "$TMP/plano-arg/repos.txt" && ! grep -q proj-outra "$TMP/plano-arg/repos.txt" && echo ok || echo fail)"
# raiz que é symlink (~/Developer apontando para outro disco): o BSD find sem -H não entra
ln -s "$HOME/Developer" "$HOME/link-dev"; mkdir -p "$HOME/Developer/proj-Developer/.next"
bash "$SCR/inventario.sh" "$TMP/plano-link" "$HOME/link-dev" >/dev/null 2>&1
check "raiz symlink: acha o repo"                  "$(grep -q proj-Developer "$TMP/plano-link/repos.txt" && echo ok || echo fail)"
check "raiz symlink: acha o .next"                 "$(grep -q 'proj-Developer/\.next$' "$TMP/plano-link/builds.tsv" && echo ok || echo fail)"

echo "== limpeza =="
git init -q --bare -b main "$TMP/origin.git"
R="$TMP/ws/repo"
git clone -q "$TMP/origin.git" "$R" 2>/dev/null
# commit antigo: a idade do node_modules tem que vir do checkout (reflog), não daqui
GIT_AUTHOR_DATE=2026-01-01T00:00:00 GIT_COMMITTER_DATE=2026-01-01T00:00:00 git -C "$R" commit -q --allow-empty -m base
git -C "$R" push -q origin main
git -C "$R" remote set-head origin main >/dev/null

# branch mergeada (ancestral) e branch com trabalho local
git -C "$R" branch mergeada
git -C "$R" checkout -q -b local-com-commit
git -C "$R" commit -q --allow-empty -m trabalho
git -C "$R" checkout -q main
# squash mergeado no default (sai), empilhada mergeada em outra feature (fica) e branch
# cujo tip é só ancestral do head do PR mergeado (fica: a prova aqui é head == tip)
for b in feat-squash feat-empilhada feat-atras-do-pr; do
  git -C "$R" checkout -q -b "$b" main; git -C "$R" commit -q --allow-empty -m "$b"
done
git -C "$R" commit -q --allow-empty -m "commit que só o PR tem"
head_pr="$(git -C "$R" rev-parse HEAD)"; git -C "$R" reset -q --hard HEAD~1
git -C "$R" checkout -q main
printf 'feat-squash main 8 %s\nfeat-empilhada feat-base 7 %s\nfeat-atras-do-pr main 9 %s\n' \
  "$(git -C "$R" rev-parse feat-squash)" "$(git -C "$R" rev-parse feat-empilhada)" "$head_pr" > "$TMP/prs"
echo .env.local >> "$R/.git/info/exclude"; echo A=1 > "$R/.env.local"
mkdir -p "$R/node_modules/x"
# repo parado: a última entrada do reflog é de janeiro, e o node_modules e o .next dele saem
P="$TMP/ws/parado"
git init -q "$P"
GIT_AUTHOR_DATE=2026-01-01T00:00:00 GIT_COMMITTER_DATE=2026-01-01T00:00:00 git -C "$P" commit -q --allow-empty -m base
mkdir -p "$P/.next/cache" "$P/node_modules/y"

velho() { # velho <worktree> — joga o índice para 3 dias atrás
  local idx; idx=$(git -C "$1" rev-parse --git-path index)
  case "$idx" in /*) ;; *) idx="$1/$idx";; esac
  touch -t "$(date -v-3d +%Y%m%d%H%M 2>/dev/null || date -d "3 days ago" +%Y%m%d%H%M)" "$idx"
}
WT="$R/.claude/worktrees"
git -C "$R" worktree add -q -b wt-velha-merged "$WT/velha" main;  velho "$WT/velha"
git -C "$R" worktree add -q -b wt-nova "$WT/nova" main
git -C "$R" worktree add -q -b wt-suja "$WT/suja" main;           velho "$WT/suja"; echo x > "$WT/suja/arquivo.txt"
git -C "$R" worktree add -q -b wt-lock-vivo "$WT/lockviva" main;  velho "$WT/lockviva"
git -C "$R" worktree lock --reason "claude session x (pid $$ start agora)" "$WT/lockviva"
git -C "$R" worktree add -q -b wt-lock-morto "$WT/lockmorta" main; velho "$WT/lockmorta"
git -C "$R" worktree lock --reason "claude session y (pid 999999 start ontem)" "$WT/lockmorta"
git -C "$R" worktree add -q --detach "$WT/detached" main;       velho "$WT/detached"
git -C "$R" worktree add -q -b wt-com-env "$WT/comenv" main;      velho "$WT/comenv"; echo SEGREDO=2 > "$WT/comenv/.env.local"
git -C "$R" worktree add -q -b wt-seed "$WT/seed" main;           velho "$WT/seed";   echo A=1 > "$WT/seed/.env.local"
git -C "$R" worktree add -q -b wt-espaco "$WT/wt com espaço" main; velho "$WT/wt com espaço"
# o --verificar diz keep: o inventário acha mergeada, mas a trava do gc manda
git -C "$R" worktree add -q -b wt-gc-keep "$WT/gckeep" main;      velho "$WT/gckeep"
echo "$WT/gckeep" > "$TMP/gc-keep"
# develop mergeada num worktree: o worktree sai, a branch não (a mesma exclusão do branches.tsv)
git -C "$R" worktree add -q -b develop "$WT/develop" main;          velho "$WT/develop"
# lock de pid morto + gc keep: o lock volta como estava
git -C "$R" worktree add -q -b wt-gc-keep-lock "$WT/gckeeplock" main; velho "$WT/gckeeplock"
git -C "$R" worktree lock --reason "claude session z (pid 999998 start ontem)" "$WT/gckeeplock"
echo "$WT/gckeeplock" >> "$TMP/gc-keep"

mkdir -p "$WT/orfa-build/.next" "$WT/orfa-codigo/src"
echo 'export {}' > "$WT/orfa-codigo/src/a.ts"
mkdir -p "$R/.next/cache" "$R/.vercel/output/functions/x.func/.next"

# poço cujo du nunca responde, como o de ~/Library/Group Containers/*.dev.orbstack que parou
# 13 min num Mac (04/10/2026): o corte mata o du e o inventário segue
mkdir -p "$HOME/.cache/uv"
ini=$(date +%s)
POCO_TIMEOUT=2 bash "$SCR/inventario.sh" "$TMP/plano" "$TMP/ws" 2>/dev/null
dur=$(( $(date +%s) - ini ))
check "poços: du que não volta é cortado e marcado (${dur}s)" \
  "$([ "$dur" -lt 15 ] && grep -qxF "timeout	$HOME/.cache/uv" "$TMP/plano/pocos.tsv" && echo ok || echo fail)"
rm -rf "$HOME/.cache/uv"
check "inventário marca worktree recém-criada como ativa" \
  "$(grep -F "$WT/nova" "$TMP/plano/worktrees.tsv" | cut -f6 | grep -q '^ativa' && echo ok || echo fail)"
check "inventário não lista .next dentro de .vercel" \
  "$(grep -qF '.vercel' "$TMP/plano/builds.tsv" && echo fail || echo ok)"
check "inventário marca detached no default como merged" \
  "$(grep -F "$WT/detached" "$TMP/plano/worktrees.tsv" | cut -f6 | grep -q '^merged' && echo ok || echo fail)"
check "inventário não chama de merged a branch atrás do head do PR" \
  "$(awk -F'\t' '$2=="feat-atras-do-pr"{print $4}' "$TMP/plano/branches.tsv" | grep -q '^merged' && echo fail || echo ok)"
check "inventário dá mais de 7 dias ao .next do repo parado" \
  "$(awk -F'\t' -v d="$P/.next" '$3==d && $1>=7' "$TMP/plano/builds.tsv" | grep -q . && echo ok || echo fail)"
cp "$TMP/plano/branches.tsv" "$TMP/branches-antes.tsv"
DRY=1 bash "$SCR/aplicar.sh" "$TMP/plano" "$TMP/ledger-dry" > "$TMP/dry.out" 2>&1
check "DRY=1 não apaga nada"                   "$(existe "$WT/velha")"
check "DRY=1 não cria ledger"                  "$(sumiu "$TMP/ledger-dry")"
check "DRY=1 não mexe no plano"                "$(cmp -s "$TMP/plano/branches.tsv" "$TMP/branches-antes.tsv" && echo ok || echo fail)"
check "DRY=1 mostra qual branch sairia"        "$(grep -q 'branch -D mergeada' "$TMP/dry.out" && echo ok || echo fail)"

# commit na detached DEPOIS do inventário: nenhuma branch segura esse commit
git -C "$WT/detached" commit -q --allow-empty -m "trabalho novo"

: > "$TMP/gc.log"; : > "$TMP/gc-env.log"
# shim do git: conta os fetch do aplicar (um por repo, e o do gc pulado)
GIT_REAL="$(command -v git)"; mkdir -p "$TMP/shim"
printf '#!/usr/bin/env bash\ncase " $* " in *" fetch "*) echo "$*" >> "%s/fetch.log";; esac\nexec "%s" "$@"\n' "$TMP" "$GIT_REAL" > "$TMP/shim/git"
chmod +x "$TMP/shim/git"; : > "$TMP/fetch.log"
PATH="$TMP/shim:$PATH" bash "$SCR/aplicar.sh" "$TMP/plano" "$TMP/ledger" > "$TMP/aplicar.out" 2>&1
check "worktree velha e mergeada sai"          "$(sumiu "$WT/velha")"
check "o gc foi chamado com --verificar <caminho>" "$(grep -qxF -- "--verificar $WT/velha" "$TMP/gc.log" && echo ok || echo fail)"
check "a branch dela sai junto"                "$(sem_branch wt-velha-merged)"
check "um fetch só para o repo com N worktrees" "$([ "$(wc -l < "$TMP/fetch.log" | tr -d ' ')" = 1 ] && echo ok || echo fail)"
check "o --verificar é chamado sem o fetch dele" "$([ -s "$TMP/gc-env.log" ] && [ "$(sort -u "$TMP/gc-env.log")" = 1 ] && echo ok || echo fail)"
check "worktree em develop mergeada sai"       "$(sumiu "$WT/develop")"
check "a branch develop fica"                  "$(tem_branch develop)"
check "worktree recém-criada fica"             "$(existe "$WT/nova")"
check "worktree suja fica"                     "$(existe "$WT/suja")"
check "worktree com lock de pid vivo fica"     "$(existe "$WT/lockviva")"
check "worktree com lock de pid morto sai"     "$(sumiu "$WT/lockmorta")"
check "worktree que o --verificar manda manter fica" "$(existe "$WT/gckeep")"
check "a branch dela também fica"              "$(tem_branch wt-gc-keep)"
check "a saída mostra o keep do gc"            "$(grep -q "keep: $WT/gckeep" "$TMP/aplicar.out" && echo ok || echo fail)"
check "keep do gc não destrava o lock"         "$(git -C "$R" worktree list --porcelain | grep -A4 -F "worktree $WT/gckeeplock" | grep -q '^locked' && echo ok || echo fail)"
check "branch mergeada sai"                    "$(sem_branch mergeada)"
check "branch com commit local fica"           "$(tem_branch local-com-commit)"
check "branch só ancestral do head do PR fica" "$(tem_branch feat-atras-do-pr)"
check "órfã só com build sai"                  "$(sumiu "$WT/orfa-build")"
check "órfã com código fica"                   "$(existe "$WT/orfa-codigo/src/a.ts")"
check ".next de repo com atividade recente fica" "$(existe "$R/.next")"
check ".next de repo parado sai"               "$(sumiu "$P/.next")"
check "node_modules de repo parado sai"        "$(sumiu "$P/node_modules")"
check ".next do prebuilt da Vercel fica"       "$(existe "$R/.vercel/output/functions/x.func/.next")"
sha=$(awk -F'\t' '$2=="mergeada"{print $3}' "$TMP/ledger/branches.tsv")
check "detached com commit novo fica"         "$(existe "$WT/detached")"
check "squash mergeado no default sai"         "$(sem_branch feat-squash)"
check "empilhada mergeada em outra base fica"  "$(tem_branch feat-empilhada)"
check "worktree com .env ignorado próprio fica" "$(existe "$WT/comenv/.env.local")"
check "worktree com .env igual ao do clone sai" "$(sumiu "$WT/seed")"
check "worktree com espaço no path sai"        "$(sumiu "$WT/wt com espaço")"
check "node_modules de checkout recente fica (commit velho)" "$(existe "$R/node_modules/x")"
check "ledger guarda o SHA para restaurar"     "$(git -C "$R" cat-file -e "$sha" 2>/dev/null && echo ok || echo fail)"

echo "== worktree-gc sem o --verificar: nada sai =="
git -C "$R" worktree add -q -b wt-gc-antigo "$WT/gcantigo" main; velho "$WT/gcantigo"
bash "$SCR/inventario.sh" "$TMP/plano2" "$TMP/ws" 2>/dev/null
LIMPEZA_WORKTREE_GC="$TMP/gc-antigo" bash "$SCR/aplicar.sh" "$TMP/plano2" "$TMP/ledger2" > "$TMP/antigo.out" 2>&1
check "gc que recusa --verificar (exit 2) mantém o worktree" "$(existe "$WT/gcantigo")"
check "e a branch"                             "$(tem_branch wt-gc-antigo)"
check "e diz por quê"                          "$(grep -q 'mantida (worktree-gc --verificar' "$TMP/antigo.out" && echo ok || echo fail)"

echo "== sem LIMPEZA_WORKTREE_GC: usa o worktree-gc.sh vizinho, do plugin =="
# Cópia do aplicar.sh numa árvore de plugin falsa, com um gc vizinho que só diz keep: se o
# worktree fica e o log tem a chamada, foi esse gc que decidiu
mkdir -p "$TMP/fake/skills/limpeza-mac/scripts" "$TMP/fake/scripts"
cp "$SCR/aplicar.sh" "$TMP/fake/skills/limpeza-mac/scripts/"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/gc-vizinho.log"\necho "keep: $2 — vizinho"; exit 1\n' "$TMP" > "$TMP/fake/scripts/worktree-gc.sh"
bash "$SCR/inventario.sh" "$TMP/plano3" "$TMP/ws" 2>/dev/null
env -u LIMPEZA_WORKTREE_GC bash "$TMP/fake/skills/limpeza-mac/scripts/aplicar.sh" "$TMP/plano3" "$TMP/ledger3" > "$TMP/real.out" 2>&1
check "o gc vizinho foi chamado para o worktree" "$(grep -qxF -- "--verificar $WT/gcantigo" "$TMP/gc-vizinho.log" 2>/dev/null && echo ok || echo fail)"
check "e o keep dele segurou o worktree"       "$(existe "$WT/gcantigo")"

echo "== uname de verdade =="
if [ "$UNAME_REAL" = Darwin ]; then
  PATH="${PATH#"$TMP/bin:"}" bash "$SCR/inventario.sh" "$TMP/plano-real" "$TMP/ws" >/dev/null 2>&1
  check "no macOS de verdade o inventário roda"   "$(existe "$TMP/plano-real/repos.txt")"
else
  echo "  pulado: 'no macOS de verdade o inventário roda' só existe no Darwin (aqui: $UNAME_REAL)"
  out="$(PATH="${PATH#"$TMP/bin:"}" bash "$SCR/inventario.sh" "$TMP/plano-real" "$TMP/ws" 2>&1)"
  check "em $UNAME_REAL de verdade o inventário sai limpo" \
    "$(printf '%s' "$out" | grep -q 'só macOS' && [ ! -e "$TMP/plano-real" ] && echo ok || echo fail)"
fi

echo; [ "$falhas" -eq 0 ] && echo "tudo ok" || echo "$falhas falha(s)"
exit "$falhas"
