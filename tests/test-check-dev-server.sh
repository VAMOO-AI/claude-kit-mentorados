#!/usr/bin/env bash
# Prova de regressão do plugin/hooks/check-dev-server.sh (PreToolUse em navigate).
#
# Navegar para um localhost que não está no ar abre uma página de erro, e todo screenshot
# ou read_page depois disso volta "Frame with ID 0 is showing error page": imagem inútil
# que fica na conversa sendo relida a cada request. O hook bloqueia antes.
#
# O hook não parseia comando, parseia URL, então a suíte é cobertura básica: só localhost
# fora do ar bloqueia; o resto passa sem tocar na rede externa. Veio do kit do time (F8a do
# núcleo único), onde lia o payload por jq e, sem jq, saía 0 sem checar nada. Aqui lê por
# node (scripts/hookjson.js), como os outros guards, e o caso "sem jq" prova isso.
#
# Uso: bash tests/test-check-dev-server.sh [caminho-do-hook]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${1:-$RAIZ/plugin/hooks/check-dev-server.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }
HOOKS_JSON="$RAIZ/plugin/hooks/hooks.json"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-dev-server.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
SPID=""
trap '[ -n "$SPID" ] && kill "$SPID" 2>/dev/null; rm -rf "$TMP"' EXIT

falhas=0
decide() { # decide <payload-json> [PATH]
  printf '%s' "$1" | PATH="${2:-$PATH}" bash "$HOOK" >/dev/null 2>&1
  [ $? -eq 2 ] && echo block || echo pass
}
check() { # check <esperado> <descrição> <payload> [PATH]
  local got; got=$(decide "$3" "${4:-$PATH}")
  if [ "$got" = "$1" ]; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (esperado %s, veio %s)\n' "$2" "$1" "$got"; falhas=$((falhas+1)); fi
}

# PATH sem jq: cada pasta que tem jq vira uma cópia de links sem ele (o padrão do
# test-path-rules.sh). Quem lê o payload é o node, então o guard tem de seguir valendo.
SEM_JQ=""; n=0; resto="$PATH:"
while [ -n "$resto" ]; do
  d="${resto%%:*}"; resto="${resto#*:}"
  [ -n "$d" ] || continue
  if [ -e "$d/jq" ] || [ -e "$d/jq.exe" ]; then
    n=$((n+1)); mkdir -p "$TMP/sem-jq/$n"
    ln -s "$d"/* "$TMP/sem-jq/$n/" 2>/dev/null
    rm -f "$TMP/sem-jq/$n/jq" "$TMP/sem-jq/$n/jq.exe"
    d="$TMP/sem-jq/$n"
  fi
  SEM_JQ="${SEM_JQ:+$SEM_JQ:}$d"
done

check pass  "url externa não é da alçada do hook" '{"tool_input":{"url":"https://example.com/x"}}'
check pass  "payload sem url"                     '{"tool_input":{}}'
check block "localhost em porta fechada"          '{"tool_input":{"url":"http://127.0.0.1:1/"}}'
check block "sem jq no PATH, localhost em porta fechada ainda bloqueia" \
  '{"tool_input":{"url":"http://127.0.0.1:1/"}}' "$SEM_JQ"

# Servidor de pé em node, não python: o node é pré-requisito do kit, e o runner do
# Windows não garante o python3.
node -e '
  const s = require("http").createServer((q, r) => r.end("ok"));
  s.listen(0, "127.0.0.1", () => {
    require("fs").writeFileSync(process.argv[1], String(s.address().port));
  });
' "$TMP/porta" &
SPID=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -s "$TMP/porta" ] && break
  sleep 0.2
done
PORT="$(cat "$TMP/porta" 2>/dev/null)"
check pass  "localhost com servidor de pé"        "{\"tool_input\":{\"url\":\"http://127.0.0.1:${PORT:-1}/\"}}"
kill "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null; SPID=""

# O hook não olha o nome da ferramenta: quem decide se ele roda é o matcher do hooks.json.
# No time, até 15/10/2026 só o Chrome casava, e o navegador embutido do app desktop passava
# sem checar.
echo
matcher="$(node -e '
  const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  for (const g of (j.hooks || {}).PreToolUse || [])
    if ((g.hooks || []).some((h) => (h.command || "").includes("check-dev-server.sh"))) {
      console.log(g.matcher || ""); break;
    }
' "$HOOKS_JSON" 2>/dev/null)"
if [ -z "$matcher" ]; then
  printf '  FALHA o hooks.json registra o check-dev-server no PreToolUse\n'; falhas=$((falhas+1))
else
  printf '  ok    o hooks.json registra o check-dev-server no PreToolUse\n'
  casa() { node -e 'process.exit(new RegExp("^(?:" + process.argv[1] + ")$").test(process.argv[2]) ? 0 : 1)' "$matcher" "$1"; }
  for t in mcp__claude-in-chrome__navigate mcp__Claude_Browser__navigate mcp__remote-devices__Claude_Browser__navigate; do
    casa "$t" && printf '  ok    matcher casa %s\n' "$t" || { printf '  FALHA matcher "%s" não casa %s\n' "$matcher" "$t"; falhas=$((falhas+1)); }
  done
  for t in mcp__Claude_Browser__computer mcp__claude-in-chrome__read_page Bash; do
    casa "$t" && { printf '  FALHA matcher "%s" casa %s\n' "$matcher" "$t"; falhas=$((falhas+1)); } || printf '  ok    matcher não casa %s\n' "$t"
  done
fi

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
