#!/usr/bin/env bash
# O estado do repo atravessa o compact — uma vez só, e sem vazar entre sessões.
#
# O par de hooks existe porque o PreCompact não injeta contexto (o stdout dele vai para o
# log de debug): quem injeta é o SessionStart(compact), com o UserPromptSubmit (pelo
# pre-prompt.sh) de rede. Os dois modos de falha próprios desse arranjo estão cobertos aqui:
#
#   - o snapshot nunca chegar (gravado com o nome errado, hook fora do hooks.json, ou o
#     hook bloqueando o compact);
#   - o snapshot chegar SEMPRE, e a partir do segundo prompt mentir sobre a branch atual.
#
# E o custo: fora do prompt seguinte a um compact, a devolução não pode abrir o node.
#
# Uso: bash tests/test-precompact.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SNAP="$RAIZ/plugin/hooks/precompact-snapshot.sh"
DEV="$RAIZ/plugin/hooks/precompact-devolve.sh"
DISPATCH="$RAIZ/plugin/hooks/pre-prompt.sh"
HOOKS_JSON="$RAIZ/plugin/hooks/hooks.json"
for f in "$SNAP" "$DEV" "$DISPATCH" "$HOOKS_JSON"; do [ -f "$f" ] || { echo "não encontrado: $f"; exit 2; }; done
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

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name teste
printf 'a\n' > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit -qm "primeiro commit"
git -C "$REPO" checkout -qb feat/algo

# payload <sid> <cwd> [trigger] — JSON montado pelo node: aspas no caminho não quebram nada.
# Para a devolução o payload vem de arquivo (pf), não de pipe: ela sai sem ler stdin quando
# não há snapshot, e com pipefail o EPIPE de quem escreve viraria o rc do caso.
payload() {
  S="$1" D="$2" T="${3-auto}" node -e '
    const p = { session_id: process.env.S, cwd: process.env.D, hook_event_name: "PreCompact", prompt: "oi" };
    if (process.env.T) p.trigger = process.env.T;
    process.stdout.write(JSON.stringify(p));'
}
pf() { payload "$@" > "$TMP/pf.json"; printf '%s' "$TMP/pf.json"; }

H1="$TMP/home"
CACHE="$H1/.claude/.cache/precompact"

echo "== o snapshot grava o que o compact apaga =="
printf 'mudanca\n' >> "$REPO/a.txt"
printf 'b\n' > "$REPO/b.txt"
printf 'c\n' > "$REPO/com espaço.txt"
antes="$(git -C "$REPO" status --porcelain)"
payload s1 "$REPO" manual | ( cd "$TMP" && HOME="$H1" bash "$SNAP" ); rc=$?
check "sai 0 (nunca bloqueia o compact)" "$(sim [ "$rc" = 0 ])"
check "gravou o arquivo da sessão" "$(sim [ -f "$CACHE/s1.md" ])"
S1="$(cat "$CACHE/s1.md" 2>/dev/null)"
check "traz a branch (lida do cwd do payload, não do diretório do hook)" "$(sim grep -q 'branch feat/algo' <<<"$S1")"
check "traz o HEAD" "$(sim grep -q 'primeiro commit' <<<"$S1")"
check "conta os modificados" "$(sim grep -q 'modificados: 3' <<<"$S1")"
check "nomeia os arquivos separados por vírgula e espaço" "$(sim grep -qF 'a.txt, b.txt' <<<"$S1")"
check "nome com espaço sai inteiro" "$(sim grep -qF 'com espaço.txt' <<<"$S1")"
check "registra o gatilho" "$(sim grep -qF '(manual)' <<<"$S1")"
check "não escreveu nada no repo" "$(sim [ "$(git -C "$REPO" status --porcelain)" = "$antes" ])"
rm -f "$REPO/com espaço.txt"

echo "== worktrees ativos entram na lista =="
git -C "$REPO" worktree add -q -b feat/outro "$TMP/wt-outro" main
payload s4 "$REPO" | HOME="$H1" bash "$SNAP"
check "cita o worktree pelo nome da pasta" "$(sim grep -q 'worktrees: wt-outro' "$CACHE/s4.md")"
rm -f "$CACHE/s4.md"

echo "== memória escrita e não commitada aparece com o passo da skill =="
mkdir -p "$REPO/.context/memoria"
printf '# fato\n' > "$REPO/.context/memoria/fato.md"
printf '# outro\n' > "$REPO/.context/memoria/outro.md"
payload s2 "$REPO" | HOME="$H1" bash "$SNAP"
check "conta os arquivos, não a pasta nova (2, não 1)" "$(sim grep -q 'memória do projeto: 2 arquivo' "$CACHE/s2.md")"
check "aponta a skill memoria-projeto" "$(sim grep -q 'memoria-projeto' "$CACHE/s2.md")"
check "não manda rodar script que este kit não tem" "$(sim nao grep -q 'publicar-memoria' "$CACHE/s2.md")"
check "a memória continua não commitada (o hook não publica)" "$(sim [ -n "$(git -C "$REPO" status --porcelain -- .context/memoria)" ])"
rm -rf "$REPO/.context"

echo "== o que não é repo, e o que é nome de arquivo perigoso =="
payload s3 "$TMP" | HOME="$H1" bash "$SNAP"; rc=$?
check "fora de repo git: sai 0" "$(sim [ "$rc" = 0 ])"
check "fora de repo git: não grava" "$(sim [ ! -f "$CACHE/s3.md" ])"
payload "../fuga" "$REPO" | HOME="$H1" bash "$SNAP" >/dev/null 2>&1
check "session_id com ../ não vira caminho" "$(sim [ ! -e "$H1/.claude/.cache/fuga.md" ])"
payload ".oculto" "$REPO" | HOME="$H1" bash "$SNAP" >/dev/null 2>&1
check "session_id começando com ponto é recusado" "$(sim [ ! -e "$CACHE/.oculto.md" ])"
# Rename vem como `"velho nome" -> "novo nome"` no porcelain: sai só o destino.
REPO3="$TMP/repo3"
mkdir -p "$REPO3"
git -C "$REPO3" init -q -b main
git -C "$REPO3" config user.email t@t.t
git -C "$REPO3" config user.name teste
printf 'x\n' > "$REPO3/old name.txt"
git -C "$REPO3" add "old name.txt"
git -C "$REPO3" commit -qm x
git -C "$REPO3" mv "old name.txt" "novo relatório.txt"
payload s10 "$REPO3" auto | HOME="$H1" bash "$SNAP"
check "rename com espaço: só o destino, sem aspas" "$(sim grep -qx 'modificados: 1 (novo relatório.txt)' "$CACHE/s10.md")"
# ` -> ` só separa em linha de rename, e só a primeira: arquivo novo com a seta no nome
# sai inteiro, e destino com a seta também.
REPO4="$TMP/repo4"
mkdir -p "$REPO4"
git -C "$REPO4" init -q -b main
git -C "$REPO4" config user.email t@t.t
git -C "$REPO4" config user.name teste
printf 'x\n' > "$REPO4/a.txt"
git -C "$REPO4" add a.txt
git -C "$REPO4" commit -qm x
git -C "$REPO4" mv a.txt "x -> y.txt"
printf 'u\n' > "$REPO4/u -> v.md"
payload s11 "$REPO4" auto | HOME="$H1" bash "$SNAP"
check "seta no nome: arquivo novo e destino de rename saem inteiros" "$(sim grep -qx 'modificados: 2 (x -> y.txt, u -> v.md)' "$CACHE/s11.md")"
payload s5 "$REPO" "" | HOME="$H1" bash "$SNAP"
check "sem trigger no payload: grava com (?)" "$(sim grep -qF '(?)' "$CACHE/s5.md")"
rm -f "$CACHE/s5.md"
SEM_NODE="$TMP/sem-node"; mkdir -p "$SEM_NODE"
for c in cat sed dirname git; do ln -s "$(command -v "$c")" "$SEM_NODE/$c"; done
payload s6 "$REPO" > "$TMP/p6.json"
( HOME="$H1" PATH="$SEM_NODE" "$(command -v bash)" "$SNAP" < "$TMP/p6.json" ); rc=$?
check "sem node: sai 0 e não grava" "$(sim [ "$rc" = 0 ] && [ ! -f "$CACHE/s6.md" ])"

echo "== a devolução acontece uma vez, na sessão certa =="
out=$(HOME="$H1" bash "$DEV" < "$(pf s1 "$REPO")")
check "imprime o estado no primeiro prompt" "$(sim grep -q 'branch feat/algo' <<<"$out")"
check "e consome o arquivo" "$(sim [ ! -f "$CACHE/s1.md" ])"
out=$(HOME="$H1" bash "$DEV" < "$(pf s1 "$REPO")")
check "no segundo prompt fica em silêncio" "$(sim [ -z "$out" ])"
out=$(HOME="$H1" bash "$DEV" < "$(pf s9 "$REPO")")
check "não entrega o snapshot de outra sessão" "$(sim [ -z "$out" ])"
check "e o snapshot de s2 continua lá" "$(sim [ -f "$CACHE/s2.md" ])"
out=$(HOME="$TMP/vazio" bash "$DEV" < "$(pf sX "$REPO")"); rc=$?
check "sem cache nenhum: silêncio e exit 0" "$(sim [ -z "$out" ] && [ "$rc" = 0 ])"
printf 'velho\n' > "$CACHE/abandonada.md"
touch -t 202601010000 "$CACHE/abandonada.md"
HOME="$H1" bash "$DEV" < "$(pf s9 "$REPO")" >/dev/null
check "snapshot de sessão abandonada (>2 dias) é podado mesmo sem entrega" "$(sim [ ! -f "$CACHE/abandonada.md" ])"
check "…e o recente de outra sessão fica" "$(sim [ -f "$CACHE/s2.md" ])"

echo "== custo: sem snapshot esperando, a devolução nem abre o node =="
ESPIAO="$TMP/espiao"; mkdir -p "$ESPIAO"
printf '#!/bin/sh\n: > "%s/node-abriu"\ncat >/dev/null\nexit 1\n' "$TMP" > "$ESPIAO/node"; chmod +x "$ESPIAO/node"
H2="$TMP/home-custo"; mkdir -p "$H2/.claude/.cache/precompact"
p="$(pf s1 "$REPO")"   # fora da linha: com PATH=… na frente, o pf chamaria o espião
HOME="$H2" PATH="$ESPIAO:$PATH" bash "$DEV" < "$p"; rc=$?
check "pasta do cache existe e está vazia: sai 0 sem abrir o node" "$(sim [ "$rc" = 0 ] && [ ! -e "$TMP/node-abriu" ])"
printf 'x\n' > "$H2/.claude/.cache/precompact/s1.md"
HOME="$H2" PATH="$ESPIAO:$PATH" bash "$DEV" < "$p" >/dev/null
check "com snapshot esperando, abre (prova que o espião funciona)" "$(sim [ -e "$TMP/node-abriu" ])"

echo "== o dispatcher do UserPromptSubmit entrega, antes dos outros avisos =="
p="$(pf s2 "$REPO")"
out=$( cd "$REPO" && HOME="$H1" bash "$DISPATCH" < "$p" 2>/dev/null ); rc=$?
check "dispatcher sai 0" "$(sim [ "$rc" = 0 ])"
check "o estado do compact está na saída dele" "$(sim grep -q 'estado do repo antes do compact' <<<"$out")"
check "…e é a primeira coisa que o modelo lê" "$(sim [ "$(printf '%s\n' "$out" | sed -n 1p | cut -c1-32)" = '[estado do repo antes do compact' ])"
check "consumido pelo dispatcher também" "$(sim [ ! -f "$CACHE/s2.md" ])"

echo "== o hooks.json liga o snapshot no PreCompact =="
cmd="$(node -e '
  const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const g = (j.hooks.PreCompact || []).find((x) => (x.hooks || []).some((h) => /precompact-snapshot\.sh/.test(h.command || "")));
  if (!g) process.exit(1);
  const h = g.hooks.find((h) => /precompact-snapshot\.sh/.test(h.command));
  console.log([g.matcher, h.timeout > 0 ? "timeout" : "sem-timeout", h.command].join("\t"));
' "$HOOKS_JSON" 2>/dev/null)"
check "há entrada PreCompact para o precompact-snapshot.sh" "$(sim [ -n "$cmd" ])"
check "matcher manual|auto" "$(sim [ "$(printf '%s' "$cmd" | cut -f1)" = 'manual|auto' ])"
check "com timeout (compact não espera hook preso)" "$(sim [ "$(printf '%s' "$cmd" | cut -f2)" = timeout ])"
comando="$(printf '%s' "$cmd" | cut -f3-)"
payload s7 "$REPO" > "$TMP/p7.json"
( cd "$REPO" && HOME="$H1" CLAUDE_PLUGIN_ROOT="$RAIZ/plugin" sh -c "$comando" < "$TMP/p7.json" ); rc=$?
check "o comando do hooks.json, como o Claude Code roda, grava o snapshot" "$(sim [ "$rc" = 0 ] && [ -f "$CACHE/s7.md" ])"
H3="$TMP/home-time"; mkdir -p "$H3/.claude"; : > "$H3/.claude/.team-manifest"
( cd "$REPO" && HOME="$H3" CLAUDE_PLUGIN_ROOT="$RAIZ/plugin" sh -c "$comando" < "$TMP/p7.json" ); rc=$?
check "com o kit do time na máquina, cede (sai 0 sem gravar)" "$(sim [ "$rc" = 0 ] && [ ! -d "$H3/.claude/.cache" ])"

echo "== SessionStart(compact) entrega logo depois do compact, e o prompt seguinte cala =="
# Visto num /compact manual (desktop, 2.1.280): o stdout do SessionStart com source=compact
# entra no contexto. No auto-compact no meio de um turno não há prompt novo, e pelo
# UserPromptSubmit o estado só chegaria na próxima mensagem da pessoa.
dev_cmd="$(node -e '
  const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const tem = (g) => (g.hooks || []).some((h) => /precompact-devolve\.sh/.test(h.command || ""));
  const ss = j.hooks.SessionStart || [];
  const fora = ss.filter((g) => g.matcher !== "compact" && tem(g)).length;
  const g = ss.find((g) => g.matcher === "compact" && tem(g));
  if (!g) process.exit(1);
  console.log([fora, g.hooks.find((h) => /precompact-devolve\.sh/.test(h.command)).command].join("\t"));
' "$HOOKS_JSON" 2>/dev/null)"
check "hooks.json liga o devolve no SessionStart com matcher compact" "$(sim [ -n "$dev_cmd" ])"
check "e só nesse grupo (startup/resume/clear não consomem)" "$(sim [ "$(printf '%s' "$dev_cmd" | cut -f1)" = 0 ])"
comando="$(printf '%s' "$dev_cmd" | cut -f2-)"
payload s8 "$REPO" | HOME="$H1" bash "$SNAP"
S="s8" D="$REPO" node -e 'process.stdout.write(JSON.stringify({session_id: process.env.S, cwd: process.env.D, hook_event_name: "SessionStart", source: "compact"}))' > "$TMP/p8.json"
out=$( cd "$REPO" && HOME="$H1" CLAUDE_PLUGIN_ROOT="$RAIZ/plugin" sh -c "$comando" < "$TMP/p8.json" )
check "o comando do hooks.json imprime o estado" "$(sim grep -q 'branch feat/algo' <<<"$out")"
out=$( cd "$REPO" && HOME="$H1" bash "$DISPATCH" < "$(pf s8 "$REPO")" 2>/dev/null )
check "o primeiro prompt depois não repete o estado" "$(sim nao grep -q 'estado do repo antes do compact' <<<"$out")"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
