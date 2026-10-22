#!/usr/bin/env bash
# O estado do repo volta logo depois do compact, calculado na hora, sem tocar no repo.
#
# Até a 0.64 eram dois hooks: precompact-snapshot.sh gravava em disco no PreCompact (que
# não injeta contexto) e precompact-devolve.sh entregava no SessionStart(compact) e, de
# rede, no UserPromptSubmit. Depois da 0.64 virou um só, plugin/hooks/compact-estado.sh, no
# SessionStart com matcher `compact`: o repo não muda durante o compact, então o estado
# calculado ali é o mesmo, sem cache e sem processo a mais em todo prompt.
#
# O que este teste segura:
#   - o hooks.json liga o compact-estado só no SessionStart(compact), e não há mais
#     PreCompact nem devolução no pre-prompt;
#   - o repositório vem do `.cwd` do payload, não do $PWD do processo;
#   - o conteúdo (branch, HEAD, modificados, worktrees, memória pendente) e os nomes de
#     arquivo difíceis (espaço, rename, seta no nome);
#   - fail-open: fora de repo, sem node, payload de outro `source`.
#
# Uso: bash tests/test-precompact.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
HOOK="$RAIZ/plugin/hooks/compact-estado.sh"
DISPATCH="$RAIZ/plugin/hooks/pre-prompt.sh"
HOOKS_JSON="$RAIZ/plugin/hooks/hooks.json"
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }
unset KIT_VAMOO_HOOKS

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
sim() { if "$@"; then echo ok; else echo fail; fi; }
nao() { ! "$@"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/precompact.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

echo "== o hooks.json liga o hook fundido só no SessionStart(compact) =="
liga="$(node -e '
  const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const tem = (g, re) => (g.hooks || []).some((h) => re.test(h.command || ""));
  const ss = j.hooks.SessionStart || [];
  const g = ss.find((g) => g.matcher === "compact" && tem(g, /compact-estado\.sh/));
  const fora = ss.filter((g) => g.matcher !== "compact" && tem(g, /compact-estado\.sh/)).length;
  const velhos = JSON.stringify(j).match(/precompact-(snapshot|devolve)\.sh/g) || [];
  const h = g ? g.hooks.find((h) => /compact-estado\.sh/.test(h.command)) : null;
  console.log([g ? "sim" : "nao", fora, (j.hooks.PreCompact || []).length, velhos.length, h && h.timeout > 0 ? "timeout" : "sem", h ? h.command : ""].join("\t"));
' "$HOOKS_JSON" 2>/dev/null)"
check "há grupo SessionStart com matcher compact chamando o compact-estado.sh" "$(sim [ "$(printf '%s' "$liga" | cut -f1)" = sim ])"
check "e só nesse grupo (startup/resume/clear não imprimem o estado)" "$(sim [ "$(printf '%s' "$liga" | cut -f2)" = 0 ])"
check "não há mais PreCompact no hooks.json" "$(sim [ "$(printf '%s' "$liga" | cut -f3)" = 0 ])"
check "nenhum comando cita o par antigo precompact-snapshot/devolve" "$(sim [ "$(printf '%s' "$liga" | cut -f4)" = 0 ])"
check "com timeout (a sessão não espera hook preso)" "$(sim [ "$(printf '%s' "$liga" | cut -f5)" = timeout ])"
comando="$(printf '%s' "$liga" | cut -f6-)"
check "o pre-prompt.sh não roda mais devolução de compact" "$(sim nao grep -qE '^for h in .*(precompact|compact-estado)' "$DISPATCH")"
[ -f "$HOOK" ] || { echo "não encontrado: $HOOK"; echo "$((falhas+1)) falha(s)"; exit 1; }

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name teste
printf 'a\n' > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit -qm "primeiro commit"
git -C "$REPO" checkout -qb feat/algo

# payload <cwd> [source] — JSON montado pelo node: aspas no caminho não quebram nada.
payload() {
  D="$1" O="${2-compact}" node -e '
    const p = { session_id: "s1", cwd: process.env.D, hook_event_name: "SessionStart" };
    if (process.env.O) p.source = process.env.O;
    process.stdout.write(JSON.stringify(p));'
}
# roda <cwd do payload> [source] — o processo roda em $TMP (fora de qualquer repo)
roda() { payload "$@" > "$TMP/p.json"; ( cd "$TMP" && bash "$HOOK" < "$TMP/p.json" ); }

echo "== o estado sai do cwd do payload =="
printf 'mudanca\n' >> "$REPO/a.txt"
printf 'b\n' > "$REPO/b.txt"
printf 'c\n' > "$REPO/com espaço.txt"
antes="$(git -C "$REPO" status --porcelain)"
out="$(roda "$REPO")"; rc=$?
check "sai 0" "$(sim [ "$rc" = 0 ])"
check "traz a branch (lida do cwd do payload, com o processo fora do repo)" "$(sim grep -q 'branch feat/algo' <<<"$out")"
check "traz o HEAD" "$(sim grep -q 'primeiro commit' <<<"$out")"
check "conta os modificados" "$(sim grep -q 'modificados: 3' <<<"$out")"
check "nomeia os arquivos separados por vírgula e espaço" "$(sim grep -qF 'a.txt, b.txt' <<<"$out")"
check "nome com espaço sai inteiro" "$(sim grep -qF 'com espaço.txt' <<<"$out")"
check "não escreveu nada no repo" "$(sim [ "$(git -C "$REPO" status --porcelain)" = "$antes" ])"
check "não grava cache em ~/.claude/.cache" "$(sim [ ! -d "$HOME/.claude/.cache/precompact" ])"
rm -f "$REPO/com espaço.txt"
# O processo dentro de OUTRO repo: quem manda é o payload.
OUTRO="$TMP/outro"; mkdir -p "$OUTRO"; git -C "$OUTRO" init -q -b outra-branch
git -C "$OUTRO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x
payload "$REPO" > "$TMP/p.json"
out="$( cd "$OUTRO" && bash "$HOOK" < "$TMP/p.json" )"
check "processo noutro repo: a branch é a do cwd do payload" "$(sim grep -q 'branch feat/algo' <<<"$out")"
check "…e não a do \$PWD" "$(sim nao grep -q 'outra-branch' <<<"$out")"

echo "== worktrees ativos entram na lista =="
git -C "$REPO" worktree add -q -b feat/outro "$TMP/wt-outro" main
check "cita o worktree pelo nome da pasta" "$(sim grep -q 'worktrees: wt-outro' <<<"$(roda "$REPO")")"

echo "== memória escrita e não commitada aparece com o passo da skill =="
mkdir -p "$REPO/.context/memoria"
printf '# fato\n' > "$REPO/.context/memoria/fato.md"
printf '# outro\n' > "$REPO/.context/memoria/outro.md"
out="$(roda "$REPO")"
check "conta os arquivos, não a pasta nova (2, não 1)" "$(sim grep -q 'memória do projeto: 2 arquivo' <<<"$out")"
check "aponta a skill memoria-projeto" "$(sim grep -q 'memoria-projeto' <<<"$out")"
check "não manda rodar script que este kit não tem" "$(sim nao grep -q 'publicar-memoria' <<<"$out")"
check "a memória continua não commitada (o hook não publica)" "$(sim [ -n "$(git -C "$REPO" status --porcelain -- .context/memoria)" ])"
rm -rf "$REPO/.context"

echo "== nomes difíceis =="
REPO3="$TMP/repo3"; mkdir -p "$REPO3"
git -C "$REPO3" init -q -b main
git -C "$REPO3" config user.email t@t.t
git -C "$REPO3" config user.name teste
printf 'x\n' > "$REPO3/old name.txt"
git -C "$REPO3" add "old name.txt"
git -C "$REPO3" commit -qm x
git -C "$REPO3" mv "old name.txt" "novo relatório.txt"
check "rename com espaço: só o destino, sem aspas" "$(sim grep -qx 'modificados: 1 (novo relatório.txt)' <<<"$(roda "$REPO3")")"
REPO4="$TMP/repo4"; mkdir -p "$REPO4"
git -C "$REPO4" init -q -b main
git -C "$REPO4" config user.email t@t.t
git -C "$REPO4" config user.name teste
printf 'x\n' > "$REPO4/a.txt"
git -C "$REPO4" add a.txt
git -C "$REPO4" commit -qm x
git -C "$REPO4" mv a.txt "x -> y.txt"
printf 'u\n' > "$REPO4/u -> v.md"
check "seta no nome: arquivo novo e destino de rename saem inteiros" "$(sim grep -qx 'modificados: 2 (x -> y.txt, u -> v.md)' <<<"$(roda "$REPO4")")"

echo "== fail-open =="
out="$(roda "$TMP")"; rc=$?
check "fora de repo git: sai 0 calado" "$(sim [ "$rc" = 0 ] && [ -z "$out" ])"
out="$(roda "$REPO" startup)"
check "source ≠ compact (chamado à mão): calado" "$(sim [ -z "$out" ])"
out="$(roda "$REPO" "")"
check "sem source no payload: entrega (o matcher já filtrou)" "$(sim grep -q 'branch feat/algo' <<<"$out")"
SEM_NODE="$TMP/sem-node"; mkdir -p "$SEM_NODE"
for c in cat sed dirname git; do ln -s "$(command -v "$c")" "$SEM_NODE/$c"; done
payload "$REPO" > "$TMP/p6.json"
out="$( PATH="$SEM_NODE" "$(command -v bash)" "$HOOK" < "$TMP/p6.json" )"; rc=$?
check "sem node: sai 0 calado" "$(sim [ "$rc" = 0 ] && [ -z "$out" ])"
mkdir -p "$HOME/.claude/.cache/precompact"
printf 'velho\n' > "$HOME/.claude/.cache/precompact/abandonada.md"; touch -t 202601010000 "$HOME/.claude/.cache/precompact/abandonada.md"
printf 'recente\n' > "$HOME/.claude/.cache/precompact/do-time.md"
roda "$REPO" >/dev/null
check "snapshot antigo (>2 dias) do par anterior é podado" "$(sim [ ! -f "$HOME/.claude/.cache/precompact/abandonada.md" ])"
check "…e o recente (o kit do time grava no mesmo lugar) fica" "$(sim [ -f "$HOME/.claude/.cache/precompact/do-time.md" ])"

echo "== o comando do hooks.json, como o Claude Code roda =="
payload "$REPO" > "$TMP/p.json"
out="$( cd "$TMP" && CLAUDE_PLUGIN_ROOT="$RAIZ/plugin" sh -c "$comando" < "$TMP/p.json" )"; rc=$?
check "imprime o estado" "$(sim [ "$rc" = 0 ] && grep -q 'branch feat/algo' <<<"$out")"
H3="$TMP/home-time"; mkdir -p "$H3/.claude"; : > "$H3/.claude/.team-manifest"
out="$( cd "$TMP" && HOME="$H3" CLAUDE_PLUGIN_ROOT="$RAIZ/plugin" sh -c "$comando" < "$TMP/p.json" )"; rc=$?
check "com o kit do time na máquina, cede (sai 0 calado)" "$(sim [ "$rc" = 0 ] && [ -z "$out" ])"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
