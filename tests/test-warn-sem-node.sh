#!/usr/bin/env bash
# Prova de regressão do plugin/hooks/warn-sem-node.sh, que roda dentro do pre-prompt.sh.
#
# Os guards do kit começam com `command -v node || exit 0`: sem node, o block-main-commit,
# o check-careful e os outros saem 0 calados e nada protege, sem ninguém ficar sabendo.
# Este hook é quem fala: uma vez por sessão, e nada quando o node existe.
#
# Cada caso passa pelo DISPATCHER com um PATH montado à mão: no Mac o node pode morar em
# /usr/local/bin ou /opt/homebrew/bin, então só um PATH explícito tira ele de vista.
# Porte de VAMOO-AI/claude-config-team#312 (lá o binário é o jq).
#
# Uso: bash tests/test-warn-sem-node.sh [caminho-do-dispatcher]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/pre-prompt.sh}"
[ -f "$HOOK" ] || { echo "dispatcher não encontrado: $HOOK"; exit 2; }
HOOKS_DIR="$(cd "$(dirname "$HOOK")" && pwd)"
BASH_BIN="$(command -v bash)"

falhas=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
contem() { grep -qF -- "$2" "$1" && ok "$3" || falha "$3 (não achei '$2' em: $(cat "$1"))"; }

# Só o dispatcher e este hook: o resto da cadeia não é o que está em teste.
SO="$TMP/hooks"; mkdir -p "$SO"
cp "$HOOK" "$SO/pre-prompt.sh"
[ -f "$HOOKS_DIR/warn-sem-node.sh" ] && cp "$HOOKS_DIR/warn-sem-node.sh" "$SO/"

# PATH sem node: o cat, que o dispatcher usa para ler o payload, o sed do emite e o mkdir
# do marcador.
SEM="$TMP/bin-sem-node"; mkdir -p "$SEM"
for c in cat sed mkdir; do ln -s "$(command -v "$c")" "$SEM/$c"; done
# PATH com node: o mesmo, mais um node de mentira — basta existir.
COM="$TMP/bin-com-node"; mkdir -p "$COM"
for c in cat sed mkdir; do ln -s "$(command -v "$c")" "$COM/$c"; done
printf '%s\n' '#!/bin/sh' 'exit 0' > "$COM/node"; chmod +x "$COM/node"

# roda <PATH> <session_id> → rc; stdout em $TMP/out
roda() {
  printf '{"session_id":"%s","cwd":"/","prompt":"oi"}' "$2" \
    | HOME="$TMP/home" PATH="$1" PRE_PROMPT_HOOKS_DIR="$SO" "$BASH_BIN" "$SO/pre-prompt.sh" >"$TMP/out" 2>"$TMP/err"
  echo $?
}

echo "== sem node: avisa no primeiro prompt da sessão =="
rc=$(roda "$SEM" sessao-a)
[ "$rc" = 0 ] && ok "sai 0 (só avisa, nunca bloqueia)" || falha "rc=$rc"
contem "$TMP/out" "falta o node" "diz o que falta"
contem "$TMP/out" "block-main-commit" "diz quais guards estão desligados"
contem "$TMP/out" "avise a pessoa" "pede ao modelo que avise a pessoa (sem node não há systemMessage)"
contem "$TMP/out" "nodejs.org" "diz como instalar"

echo
echo "== sem node: o segundo prompt da mesma sessão fica calado =="
rc=$(roda "$SEM" sessao-a)
[ -s "$TMP/out" ] && falha "repetiu o aviso: $(cat "$TMP/out")" || ok "calado"

echo
echo "== sem node: sessão nova avisa de novo =="
rc=$(roda "$SEM" sessao-b)
contem "$TMP/out" "falta o node" "avisa na sessão nova"

echo
echo "== com node: nada a dizer =="
rm -rf "${TMP:?}/home"
rc=$(roda "$COM" sessao-c)
[ "$rc" = 0 ] && ok "sai 0" || falha "rc=$rc"
[ -s "$TMP/out" ] && falha "falou com node presente: $(cat "$TMP/out")" || ok "calado"

echo
echo "== sem node e sem como gravar o marcador: avisa mesmo assim =="
rm -rf "${TMP:?}/home"; : > "$TMP/home"   # HOME é um arquivo: mkdir falha
rc=$(roda "$SEM" sessao-d)
[ "$rc" = 0 ] && ok "sai 0" || falha "rc=$rc"
contem "$TMP/out" "falta o node" "avisa (melhor repetir que calar)"
rm -f "$TMP/home"

echo
echo "== payload sem session_id: avisa, e não grava marcador vazio =="
printf '{"prompt":"oi"}' | HOME="$TMP/home" PATH="$SEM" PRE_PROMPT_HOOKS_DIR="$SO" "$BASH_BIN" "$SO/pre-prompt.sh" 2>/dev/null >"$TMP/out"
contem "$TMP/out" "falta o node" "avisa"
[ -e "$TMP/home/.claude/.cache/warn-sem-node" ] && [ ! -s "$TMP/home/.claude/.cache/warn-sem-node" ] \
  && falha "gravou marcador vazio" || ok "nenhum marcador vazio"

echo
echo "== o hook está na cadeia do pre-prompt, em primeiro =="
primeiro=$(grep -E '^for h in ' "$HOOKS_DIR/pre-prompt.sh" | awk '{print $4}')
[ "$primeiro" = warn-sem-node.sh ] && ok "warn-sem-node.sh é o primeiro do laço" || falha "primeiro do laço: '$primeiro'"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
