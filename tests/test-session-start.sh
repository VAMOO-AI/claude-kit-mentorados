#!/usr/bin/env bash
# Prova do plugin/hooks/session-start.sh, o dispatcher do SessionStart (D13 de 09/11/2026).
#
# Até a 0.90 os quatro avisos de abertura eram quatro entries no hooks.json: quatro `sh`,
# quatro `bash` e três `node` lendo o mesmo `cwd`, tudo antes do 1º prompt. O dispatcher lê
# o payload uma vez e tem que devolver o que os avisos devolviam separados: os textos na
# ordem, todos com o payload, e aviso com bug não desliga os seguintes.
#
# Uso: bash tests/test-session-start.sh [caminho-do-dispatcher]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${1:-$RAIZ/plugin/hooks/session-start.sh}"
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }
[ -f "$HOOK" ] || { echo "  FALHA dispatcher não encontrado: $HOOK"; echo; echo "1 falha(s)"; exit 1; }
PLUGIN="$(cd "$(dirname "$HOOK")/.." && pwd)"
unset CLAUDE_PROJECT_DIR KIT_SESSAO_CWD KIT_VAMOO_HOOKS

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/session-start.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
igual() { [ "$1" = "$2" ] && ok "$3" || falha "$3 (esperado '$1', veio '$2')"; }

payload() { D="$1" node -e 'process.stdout.write(JSON.stringify({session_id:"s1",hook_event_name:"SessionStart",source:"startup",cwd:process.env.D}))'; }
# raiz <dir> → uma raiz de plugin de mentira, com o hookjson.js de verdade
raiz() { mkdir -p "$1/hooks" "$1/scripts"; cp "$PLUGIN/scripts/hookjson.js" "$1/scripts/"; printf '%s' "$1"; }
# aviso <raiz> <rel> <linhas do script…>
aviso() { local r="$1" rel="$2"; shift 2; printf '%s\n' '#!/usr/bin/env bash' "$@" > "$r/$rel"; }
# roda <raiz> <cwd do payload> → rc; stdout em $TMP/out, stderr em $TMP/err
roda() {
  payload "$2" > "$TMP/payload.json"
  ( cd "$TMP" && SESSION_START_ROOT="$1" bash "$HOOK" < "$TMP/payload.json" > "$TMP/out" 2> "$TMP/err" ); echo $?
}
QUATRO="scripts/warn-branch-worktree.sh scripts/warn-kit-updated.sh hooks/warn-skills-projeto.sh hooks/warn-doc-ancorado.sh"

echo "== os quatro avisos, na ordem, todos com o payload e com o cwd lido uma vez =="
R="$(raiz "$TMP/r1")"
for rel in $QUATRO; do
  n="$(basename "$rel" .sh)"
  aviso "$R" "$rel" "case \"\$(cat)\" in *'\"session_id\":\"s1\"'*) echo \"$n leu cwd=\$KIT_SESSAO_CWD\" ;; *) echo \"$n sem-payload\" ;; esac"
done
# cwd sem `/` na frente: no Git Bash o MSYS converte para caminho do Windows a variável que
# parece caminho POSIX ao chamar o node nativo (`/x/…` virava `X:/…`), e o que se prova aqui é
# que o valor chega igual aos quatro, não o formato dele.
rc=$(roda "$R" "x/meu projeto")
igual 0 "$rc" "sai 0"
esperado="$(for rel in $QUATRO; do echo "$(basename "$rel" .sh) leu cwd=x/meu projeto"; done)"
igual "$esperado" "$(cat "$TMP/out")" "os quatro leem o payload, nesta ordem, e recebem o cwd em KIT_SESSAO_CWD"

echo "== aviso calado não deixa linha; ausente é pulado; bug não desliga os seguintes =="
R="$(raiz "$TMP/r2")"
aviso "$R" scripts/warn-branch-worktree.sh 'cat >/dev/null' 'exit 0'
aviso "$R" scripts/warn-kit-updated.sh 'cat >/dev/null' 'echo saida-do-bug' 'echo erro-do-bug >&2' 'exit 1'
aviso "$R" hooks/warn-doc-ancorado.sh 'cat >/dev/null' 'set -uo pipefail' 'echo seguinte-rodou' 'exit 3'
rc=$(roda "$R" "$TMP")
igual 0 "$rc" "aviso que sai 1 e aviso que sai 3: a cadeia sai 0 (SessionStart não bloqueia)"
igual "$(printf 'saida-do-bug\nseguinte-rodou')" "$(cat "$TMP/out")" "o calado não deixa linha, o ausente é pulado e o seguinte ao bug roda"
grep -q 'erro-do-bug' "$TMP/err" && ok "o stderr do aviso segue para o log do harness" || falha "o stderr do aviso sumiu"
R="$(raiz "$TMP/r3")"
rc=$(roda "$R" "$TMP")
[ "$rc" = 0 ] && [ ! -s "$TMP/out" ] && ok "raiz sem aviso nenhum: sai 0 calado" || falha "raiz vazia (rc=$rc, out=$(cat "$TMP/out"))"

echo "== fail-open: sem payload e sem node os avisos ainda rodam =="
R="$(raiz "$TMP/r4")"
aviso "$R" scripts/warn-kit-updated.sh 'cat >/dev/null' 'echo "rodou cwd=[${KIT_SESSAO_CWD:-}]"'
out="$(cd "$TMP" && printf '' | SESSION_START_ROOT="$R" bash "$HOOK" 2>/dev/null)"; rc=$?
igual "0 rodou cwd=[]" "$rc $out" "payload vazio: sai 0, o aviso roda e cai no fallback dele"
SEM="$TMP/sem-node"; mkdir -p "$SEM"
for c in cat bash; do printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$c")" > "$SEM/$c"; chmod +x "$SEM/$c"; done
out="$(cd "$TMP" && payload /x | PATH="$SEM" SESSION_START_ROOT="$R" "$(command -v bash)" "$HOOK" 2>/dev/null)"; rc=$?
igual "0 rodou cwd=[]" "$rc $out" "sem node no PATH: sai 0 e o aviso roda sem o cwd"

echo "== com os avisos de verdade: 1 node por abertura de sessão, e o texto de cada um chega =="
# Repo atrás do upstream, com doc ancorado velho: dois avisos reais têm o que dizer.
ORIGIN="$TMP/origin.git"; SEED="$TMP/seed"; WORK="$TMP/work"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare -b main "$ORIGIN"
git init -q -b main "$SEED"; git -C "$SEED" commit -q --allow-empty -m base
git -C "$SEED" remote add origin "$ORIGIN"; git -C "$SEED" push -q -u origin main 2>/dev/null
git clone -q "$ORIGIN" "$WORK" 2>/dev/null
sha="$(git -C "$WORK" rev-parse HEAD)"
git -C "$SEED" commit -q --allow-empty -m novo; git -C "$SEED" push -q origin main 2>/dev/null
mkdir -p "$WORK/.context/docs/handoffs"
printf '# Handoff\n\n**Base:** main @ `%s`\n' "$sha" > "$WORK/.context/docs/handoffs/2026-01-01.md"
for i in 1 2 3; do git -C "$WORK" commit -q --allow-empty -m "c$i"; done
NODE_REAL="$(command -v node)"; CONTA="$TMP/conta"; mkdir -p "$CONTA"
printf '#!/bin/sh\necho x >> "%s/chamadas"\nexec "%s" "$@"\n' "$CONTA" "$NODE_REAL" > "$CONTA/node"; chmod +x "$CONTA/node"
payload "$WORK" > "$TMP/payload.json"
: > "$CONTA/chamadas"
out="$(cd "$TMP" && PATH="$CONTA:$PATH" DOC_ANCORADO_COMMITS=2 CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOK" < "$TMP/payload.json" 2>"$TMP/err")"; rc=$?
igual 0 "$rc" "sai 0"
n="$(wc -l < "$CONTA/chamadas" | tr -d ' ')"
igual 1 "$n" "o payload é lido por um node só (eram três)"
case "$out" in *"1 commit(s) atrás"*) ok "o aviso de branch atrás do upstream chega, lendo o repo do cwd do payload" ;; *) falha "sem o aviso de branch atrás (out=$out; err=$(cat "$TMP/err"))" ;; esac
case "$out" in *"doc ancorado em SHA distante"*) ok "o aviso de doc ancorado chega" ;; *) falha "sem o aviso de doc ancorado (out=$out)" ;; esac
case "$out" in *"atrás de origin/main"*"doc ancorado"*) ok "na ordem da lista" ;; *) falha "fora de ordem (out=$out)" ;; esac

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
