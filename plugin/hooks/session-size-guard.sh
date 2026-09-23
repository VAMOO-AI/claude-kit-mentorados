#!/usr/bin/env bash
# UserPromptSubmit: avisa VOCÊ quando a sessão fica comprida — uma vez por faixa, não a
# cada prompt.
#
# Cada tool call relê a conversa inteira, então o total de tokens relidos cresce com o
# QUADRADO do comprimento da sessão. Medido no time em 22/08/2026: sessões com 100+
# requests concentraram 97,8% do cache read da semana. O aviso precisa chegar antes, não
# depois.
#
# Cada linha sai com o prefixo `@usuario `: o pre-prompt.sh manda essas linhas para a sua
# tela (systemMessage), fora do contexto do modelo. Dentro do contexto o aviso virava
# contagem regressiva — medido no time em 22/09/2026: depois dele, 13,8% das respostas
# falavam em /clear ou /compact, contra 2,7% nas demais.
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

# Limiares em linhas de transcript, a ~7 linhas por request (medido no time em 22/09/2026):
# 600 linhas ≈ 84 requests e ~200 mil tokens de contexto; 1.200 ≈ 170 requests e ~300 mil;
# 2.000 ≈ 280 requests e ~425 mil.
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
  600)  echo "@usuario 📊 session-size: esta sessão passou de ~600 linhas, perto de 200 mil tokens de contexto, e cada passo do Claude relê tudo isso. Terminou a tarefa? Rode /clear antes do próximo assunto." ;;
  1200) echo "@usuario ⚠️ session-size: ~1.200 linhas, perto de 300 mil tokens relidos a cada passo do Claude. Rode /compact agora, ou /clear se o assunto mudou." ;;
  2000) echo "@usuario 🚨 session-size: ~2.000+ linhas, 425 mil tokens ou mais relidos a cada passo do Claude. Rode /clear ou /compact." ;;
esac
exit 0
