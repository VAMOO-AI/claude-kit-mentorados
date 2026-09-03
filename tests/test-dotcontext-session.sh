#!/usr/bin/env bash
# Prova de regressão do plugin/hooks/dotcontext-session.sh (SessionStart).
#
# O hook existe por dois números medidos em 03/09/2026: o `hook dispatch` do
# dotcontext 1.1.1 leva >10 s (e estoura o teto de 60 s do hook) em repo git SEM
# `.context/`, e o `npx` custa ~1,3 s contra ~0,6 s do binário global. Então o que
# precisa continuar valendo: sem `.context/` o dispatch NÃO é chamado; com
# `.context/` (na pasta ou na raiz do repo) é chamado uma vez, pelo binário quando
# houver e pelo npx quando não; o payload chega intacto; e o hook nunca falha.
#
# Uso: bash tests/test-dotcontext-session.sh [caminho-do-hook]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/dotcontext-session.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotcontext-session.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
# O TMPDIR do macOS termina em "/": sem normalizar, HOME fica com "//" e o
# `[ "$PWD" = "$HOME" ]` do hook compara strings diferentes pra mesma pasta.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# Dois executáveis falsos: cada um anota que rodou (e com que argumentos) e o
# dotcontext copia o stdin, pra provar que o payload atravessa o hook.
BIN="$TMP/bin"; SEM_BIN="$TMP/bin-sem-dotcontext"; mkdir -p "$BIN" "$SEM_BIN"
cat > "$BIN/dotcontext" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMP/chamadas-dotcontext"
cat > "$TMP/stdin-dotcontext"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"falso"}}\n'
EOF
cat > "$SEM_BIN/npx" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMP/chamadas-npx"
cat >/dev/null
printf '{"continue":true}\n'
EOF
cp "$SEM_BIN/npx" "$BIN/npx"
chmod +x "$BIN/dotcontext" "$BIN/npx" "$SEM_BIN/npx"

FAKE_HOME="$TMP/home"; mkdir -p "$FAKE_HOME"
PAYLOAD='{"session_id":"s1","hook_event_name":"SessionStart","source":"startup"}'

falhas=0
saida=""; codigo=0
roda() { # roda <pasta> [PATH extra]
  rm -f "$TMP/chamadas-dotcontext" "$TMP/chamadas-npx" "$TMP/stdin-dotcontext"
  saida="$(cd "$1" && printf '%s' "$PAYLOAD" | HOME="$FAKE_HOME" PATH="${2:-$BIN}:/usr/bin:/bin" bash "$HOOK" 2>/dev/null)"
  codigo=$?
}
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
chamadas() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }

echo "== repo sem .context: o dispatch não roda =="
SEM="$TMP/sem-context"; mkdir -p "$SEM"; git -C "$SEM" init -q
roda "$SEM"
check "exit 0"                              "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
check "dotcontext não foi chamado"          "$([ "$(chamadas "$TMP/chamadas-dotcontext")" = 0 ] && echo ok || echo fail)"
check "npx não foi chamado"                 "$([ "$(chamadas "$TMP/chamadas-npx")" = 0 ] && echo ok || echo fail)"
check "stdout vazio (nada pra injetar)"     "$([ -z "$saida" ] && echo ok || echo fail)"

echo "== repo com .context: uma chamada, pelo binário, com o payload =="
COM="$TMP/com-context"; mkdir -p "$COM/.context/docs" "$COM/src"; git -C "$COM" init -q
roda "$COM"
check "exit 0"                              "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
check "dotcontext chamado exatamente 1 vez" "$([ "$(chamadas "$TMP/chamadas-dotcontext")" = 1 ] && echo ok || echo fail)"
check "com 'hook dispatch --source claude-code'" \
  "$(grep -qx 'hook dispatch --source claude-code' "$TMP/chamadas-dotcontext" 2>/dev/null && echo ok || echo fail)"
check "npx NÃO chamado quando o binário existe" "$([ "$(chamadas "$TMP/chamadas-npx")" = 0 ] && echo ok || echo fail)"
check "payload chegou intacto no dotcontext" "$([ "$(cat "$TMP/stdin-dotcontext" 2>/dev/null)" = "$PAYLOAD" ] && echo ok || echo fail)"
check "a resposta do dotcontext vai pro stdout" "$(printf '%s' "$saida" | grep -q additionalContext && echo ok || echo fail)"

echo "== subpasta do repo: acha o .context na raiz =="
roda "$COM/src"
check "dotcontext chamado a partir de src/"  "$([ "$(chamadas "$TMP/chamadas-dotcontext")" = 1 ] && echo ok || echo fail)"

echo "== sem o binário: cai pro npx com a versão pinada =="
roda "$COM" "$SEM_BIN"
check "exit 0"                              "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
check "npx chamado exatamente 1 vez"        "$([ "$(chamadas "$TMP/chamadas-npx")" = 1 ] && echo ok || echo fail)"
check "com '-y @dotcontext/cli@1.1.1 hook dispatch --source claude-code'" \
  "$(grep -qx -- '-y @dotcontext/cli@1.1.1 hook dispatch --source claude-code' "$TMP/chamadas-npx" 2>/dev/null && echo ok || echo fail)"

echo "== sessão aberta no HOME: não roda, mesmo com .context =="
mkdir -p "$FAKE_HOME/.context"
roda "$FAKE_HOME"
check "dotcontext não foi chamado no HOME"  "$([ "$(chamadas "$TMP/chamadas-dotcontext")" = 0 ] && echo ok || echo fail)"
check "exit 0"                              "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
