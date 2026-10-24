#!/usr/bin/env bash
# check-dev-server.sh — PreToolUse em mcp__claude-in-chrome__navigate e
# mcp__Claude_Browser__navigate (o navegador embutido do app desktop).
#
# Navegar para um localhost que não está no ar gera uma página de erro, e todo
# screenshot/read_page depois disso volta "Frame with ID 0 is showing error page":
# imagem inútil que fica na conversa sendo relida a cada request. Bloqueia antes disso:
# se a URL for local e não responder, pede para subir o servidor.
#
# Lê a URL do payload por node (scripts/hookjson.js), como os outros guards: jq não é
# pré-requisito de quem está aprendendo, e no kit do time, que lia por jq, a máquina sem
# jq ficava sem o guard sem ninguém saber. Sem node, sai 0 (falha aberto) e quem avisa é
# o warn-sem-node.sh, no primeiro prompt.
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || exit 0
H="$AQUI/../scripts/hookjson.js"
[ -f "$H" ] && command -v node >/dev/null 2>&1 || exit 0

url="$(node "$H" tool_input.url 2>/dev/null)"
[ -z "$url" ] && exit 0

case "$url" in
  http://localhost*|https://localhost*|http://127.0.0.1*|https://127.0.0.1*|http://0.0.0.0*|http://\[::1\]*) ;;
  *) exit 0 ;;
esac

if ! curl -sfI --max-time 2 "$url" >/dev/null 2>&1 && ! curl -sf --max-time 2 -o /dev/null "$url" 2>/dev/null; then
  echo "dev server em $url não responde. Suba o servidor (npm run dev / vite) e confirme que está no ar ANTES de navegar; senão o screenshot volta 'Frame with ID 0 is showing error page' e a imagem inútil fica pesando na conversa." >&2
  exit 2
fi

exit 0
