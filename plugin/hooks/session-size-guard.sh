#!/usr/bin/env bash
# UserPromptSubmit: avisa quando a sessão passa de tamanhos que dominam o custo.
#
# Cada tool call relê a conversa inteira, então o custo cresce com o QUADRADO do
# comprimento da sessão. Medido no time em 22/08/2026: sessões com 100+ requests
# concentraram 97,8% do cache read da semana. O aviso precisa chegar antes, não depois
# — e uma vez por faixa, não a cada prompt.
#
# Lê o JSON do hook via node (sem depender de jq). Falha-aberta: qualquer erro => exit 0.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
info="$(cat | node "$H" session_id transcript_path)"
sid="$(printf '%s\n' "$info" | sed -n 1p)"
tp="$(printf '%s\n' "$info"  | sed '1d')"
{ [ -z "$sid" ] || [ -z "$tp" ] || [ ! -f "$tp" ]; } && exit 0

lines=$(wc -l < "$tp" 2>/dev/null | tr -d ' ')
[ -z "$lines" ] && exit 0

# Limiares em linhas de transcript (~2-3 linhas por request).
if   [ "$lines" -ge 2000 ]; then tier=2000
elif [ "$lines" -ge 1200 ]; then tier=1200
elif [ "$lines" -ge 600 ];  then tier=600
else exit 0
fi

d="$HOME/.claude/.cache/session-size"
mkdir -p "$d" 2>/dev/null
f="$d/$sid"
prev=$(cat "$f" 2>/dev/null)
prev=${prev:-0}
[ "$tier" -le "$prev" ] && exit 0
printf '%s' "$tier" > "$f" 2>/dev/null

case "$tier" in
  600)  echo "📊 session-size: ~600 linhas de transcript. Se a tarefa atual acabou, /clear antes do próximo assunto sai muito mais barato que continuar aqui." ;;
  1200) echo "⚠️ session-size: ~1.200 linhas. Esta sessão já está na faixa que domina o custo. Rode /compact agora, ou /clear se o assunto mudou." ;;
  2000) echo "🚨 session-size: ~2.000+ linhas — faixa das sessões-maratona. Cada tool call daqui pra frente relê tudo. /clear ou /compact." ;;
esac
exit 0
