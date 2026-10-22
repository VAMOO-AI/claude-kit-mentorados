#!/usr/bin/env bash
# O /kit-vamoo:setup tira o MCP do dotcontext de quem o tem registrado (#239).
#
# O plugin parou de registrar o MCP na 0.56.0, mas o install.sh de antes de 24/08/2026
# o gravou no escopo de usuário (~/.claude.json), e ele continuava subindo um processo
# node por sessão e lendo arquivo fora do deny de .env*. O setup lê o ~/.claude.json e,
# só se o dotcontext estiver lá, roda `claude mcp remove dotcontext --scope user`.
#   (a) registrado: o setup chama a remoção e avisa;
#   (b) não registrado: o setup não chama o `claude`;
#   (c) --dry-run com o registro: só anuncia.
# O `claude` aqui é um stub que registra os argumentos: o teste nunca toca no CLI real.
#
# Uso: bash tests/test-kit-setup-dotcontext.sh [caminho-do-kit-setup.sh]
set -uo pipefail
SETUP="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/kit-setup.sh}"
[ -f "$SETUP" ] || { echo "script não encontrado: $SETUP"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "sem node — pulando"; exit 0; }

HOME_REAL="$HOME"
falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit-setup-dotcontext.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/claude-chamadas.log"
STUB
chmod +x "$TMP/bin/claude"

roda_setup() { # roda_setup <home> [args...] — saída em <home>.log
  local h="$1"; shift
  case "$h" in
    "$TMP"/*) ;;
    *) echo "GUARDA: HOME '$h' não está sob o temporário — abortando"; exit 2 ;;
  esac
  [ "$h/.claude" = "$HOME_REAL/.claude" ] && { echo "GUARDA: destino é o ~/.claude real — abortando"; exit 2; }
  HOME="$h" PATH="$TMP/bin:$PATH" bash "$SETUP" "$@" >"$h.log" 2>&1
}

com_dotcontext() {
  mkdir -p "$1"
  printf '%s\n' '{ "mcpServers": { "dotcontext": { "type": "stdio", "command": "npx", "args": ["-y", "@dotcontext/mcp"] }, "outro": { "type": "stdio", "command": "x" } } }' > "$1/.claude.json"
}

echo "== (a) dotcontext registrado no escopo de usuário =="
A="$TMP/a"; com_dotcontext "$A"
roda_setup "$A" || falha "setup saiu com erro: $(tail -5 "$A.log")"
grep -qx 'mcp remove dotcontext --scope user' "$A/claude-chamadas.log" 2>/dev/null \
  && ok "chama claude mcp remove dotcontext --scope user" \
  || falha "não chamou a remoção (chamadas: $(cat "$A/claude-chamadas.log" 2>/dev/null))"
grep -q 'MCP do dotcontext' "$A.log" && ok "a saída avisa da remoção" || falha "a saída não fala do dotcontext"

echo "== (b) sem dotcontext =="
B="$TMP/b"; mkdir -p "$B"
printf '%s\n' '{ "mcpServers": { "outro": { "type": "stdio", "command": "x" } } }' > "$B/.claude.json"
roda_setup "$B" || falha "setup saiu com erro: $(tail -5 "$B.log")"
[ ! -s "$B/claude-chamadas.log" ] && ok "não chama o claude" || falha "chamou o claude sem precisar: $(cat "$B/claude-chamadas.log")"

echo "== (c) --dry-run com dotcontext =="
C="$TMP/c"; com_dotcontext "$C"
roda_setup "$C" --dry-run || falha "setup saiu com erro: $(tail -5 "$C.log")"
[ ! -s "$C/claude-chamadas.log" ] && ok "dry-run não remove" || falha "dry-run chamou: $(cat "$C/claude-chamadas.log")"
grep -q 'dry-run.*claude mcp remove dotcontext' "$C.log" && ok "dry-run anuncia a remoção" || falha "dry-run não anuncia"

echo
[ "$falhas" -eq 0 ] && { echo "tudo verde"; exit 0; }
echo "$falhas falha(s)"; exit 1
