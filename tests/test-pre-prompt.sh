#!/usr/bin/env bash
# Prova de regressão do plugin/hooks/pre-prompt.sh, o dispatcher do UserPromptSubmit.
#
# Até a 0.28.3 eram quatro entries no settings.json (session-size-guard, repo-session,
# branch-guard, memoria-worktree-link), cada um um processo `sh` mais um `bash <hook>` por
# prompt. O dispatcher lê o payload uma vez e tem que devolver o que os quatro devolviam:
# os avisos concatenados na ordem, o exit ≠ 0 do primeiro que falha, e nada quando ninguém
# fala. Cada caso passa pelo DISPATCHER, com os hooks reais ao lado dele.
#
# Uso: bash tests/test-pre-prompt.sh [caminho-do-dispatcher]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/pre-prompt.sh}"
[ -f "$HOOK" ] || { echo "dispatcher não encontrado: $HOOK"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }
HOOKS_DIR="$(cd "$(dirname "$HOOK")" && pwd)"
SCRIPTS_DIR="$(cd "$HOOKS_DIR/../scripts" && pwd)"
# Hook do plugin resolve o hookjson.js em ../scripts: pasta de hooks avulsa precisa do
# helper ao lado, senão o hook sai 0 fail-open e o teste aprovaria um dispatcher mudo.
árvore() { mkdir -p "$1/hooks" "$1/scripts"; cp "$SCRIPTS_DIR/hookjson.js" "$1/scripts/"; printf '%s' "$1/hooks"; }

falhas=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
TP="$TMP/transcript.jsonl"; : > "$TP"
linhas() { : > "$TP"; local i=0; while [ "$i" -lt "$1" ]; do echo '{"x":1}' >> "$TP"; i=$((i+1)); done; }

# roda <sid> <cwd> [pasta-de-hooks] → rc; stdout em $TMP/out, stderr em $TMP/err
roda() {
  S="$1" D="$2" T="$TP" node -e 'process.stdout.write(JSON.stringify({session_id:process.env.S,cwd:process.env.D,transcript_path:process.env.T,prompt:"oi"}))' \
    | ( cd "$2" && PRE_PROMPT_HOOKS_DIR="${3:-}" bash "$HOOK" ) >"$TMP/out" 2>"$TMP/err"
  echo $?
}
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
espera_rc() { [ "$1" = "$2" ] && ok "$3" || falha "$3 (esperado rc=$1, veio rc=$2)"; }
contem()     { grep -qF -- "$2" "$1" && ok "$3" || falha "$3 (não achei '$2' em: $(cat "$1"))"; }
nao_contem() { grep -qF -- "$2" "$1" && falha "$3 (achei '$2')" || ok "$3"; }

echo "== primeiro prompt: silêncio, e o repo-session registrou a sessão =="
rc=$(roda s1 "$REPO")
espera_rc 0 "$rc" "sai 0"
[ -s "$TMP/out" ] && falha "stdout deveria estar vazio: $(cat "$TMP/out")" || ok "stdout vazio (nenhum hook tinha o que dizer)"
H=$(printf '%s' "$(git -C "$REPO" rev-parse --show-toplevel)" | shasum | awk '{print $1}')
[ -f "$HOME/.claude/.cache/repo-sessions/$H/s1" ] && ok "repo-session marcou s1 no repo" || falha "repo-session não marcou a sessão"

echo
echo "== os avisos dos hooks chegam concatenados, na ordem =="
linhas 700
git -C "$REPO" switch -q -c feat/outra
rc=$(roda s1 "$REPO")
espera_rc 0 "$rc" "sai 0"
contem "$TMP/out" "~600 linhas" "aviso do session-size-guard"
contem "$TMP/out" "branch-guard" "aviso do branch-guard (main → feat/outra)"
primeiro=$(grep -n -m1 -E 'session-size|branch-guard' "$TMP/out" | cut -d: -f2 | grep -o -E 'session-size|branch-guard')
[ "$primeiro" = "session-size" ] && ok "session-size vem antes do branch-guard (ordem das entries antigas)" || falha "ordem trocada: $(cat "$TMP/out")"
rc=$(roda s1 "$REPO")
[ -s "$TMP/out" ] && falha "repetiu aviso: $(cat "$TMP/out")" || ok "prompt seguinte: nada a repetir"

echo
echo "== hook ausente é pulado; pasta vazia sai 0 calado =="
SO_UM="$(árvore "$TMP/so-um")"; cp "$HOOKS_DIR/branch-guard.sh" "$SO_UM/"
git -C "$REPO" switch -q main
rc=$(roda s1 "$REPO" "$SO_UM")
espera_rc 0 "$rc" "só branch-guard instalado: sai 0"
contem "$TMP/out" "branch-guard" "…e o branch-guard que existe segue avisando"
VAZIO="$(árvore "$TMP/vazio")"
rc=$(roda s1 "$REPO" "$VAZIO")
espera_rc 0 "$rc" "pasta sem hook sai 0"
[ -s "$TMP/out" ] && falha "stdout deveria estar vazio" || ok "stdout vazio"

echo
echo "== cadeia: o primeiro código ≠ 0 encerra, com o stdout e o stderr dele =="
FALSOS="$(árvore "$TMP/falsos")"
printf '%s\n' '#!/bin/bash' 'cat >/dev/null' 'echo aviso-do-primeiro' 'exit 0' > "$FALSOS/session-size-guard.sh"
printf '%s\n' '#!/bin/bash' 'cat >/dev/null' 'echo bloqueio' 'echo motivo >&2' 'exit 2' > "$FALSOS/branch-guard.sh"
printf '%s\n' '#!/bin/bash' 'echo NAO-DEVIA-RODAR' 'exit 0' > "$FALSOS/memoria-worktree-link.sh"
rc=$(roda s9 "$REPO" "$FALSOS")
espera_rc 2 "$rc" "exit 2 do hook vira exit 2 da cadeia"
contem "$TMP/out" 'aviso-do-primeiro' "o que os anteriores disseram é repassado"
contem "$TMP/out" 'bloqueio' "stdout do hook que saiu ≠ 0 é repassado"
contem "$TMP/err" 'motivo' "stderr do hook que saiu ≠ 0 é repassado"
nao_contem "$TMP/out" 'NAO-DEVIA-RODAR' "o hook seguinte não roda"

echo
echo "== fail-open =="
rc=$(printf '' | bash "$HOOK" >/dev/null 2>&1; echo $?)
espera_rc 0 "$rc" "payload vazio sai 0"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
