#!/usr/bin/env bash
# Devolve, logo depois do compact, o estado que o `precompact-snapshot.sh` gravou — e some.
#
# Roda em dois lugares, e o payload chega por stdin nos dois (é dele que sai o session_id):
#   - SessionStart com matcher `compact` (hooks.json): o principal. O stdout entra no
#     contexto assim que o compact termina, inclusive no auto-compact no meio de um turno,
#     em que não há prompt novo;
#   - dentro do pre-prompt.sh (UserPromptSubmit), como rede. Como o arquivo é consumido
#     na primeira entrega, o prompt seguinte não repete.
#
# Custo fora do prompt seguinte a um compact: um glob na pasta do cache. O node só abre
# quando existe algum snapshot esperando — checar só se a PASTA existe não serve, porque
# ela existe para sempre depois do primeiro compact da máquina.
#
# O arquivo é consumido uma vez (apagado depois de impresso). Se ficasse, o estado
# congelado voltaria a cada prompt e passaria a mentir sobre a branch atual.
# Falha-aberta: sai 0 em qualquer caso.
d="$HOME/.claude/.cache/precompact"
set -- "$d"/*.md
[ -e "$1" ] || exit 0

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0

# A poda vem antes da entrega e roda sempre que o node abriu: snapshot de sessão que nunca
# mandou outro prompt ficaria ali, e o glob acima abriria o node em todo prompt de toda
# sessão da máquina. Dois dias cobrem uma sessão parada de um dia para o outro.
find "$d" -type f -name '*.md' -mmin +2880 -delete 2>/dev/null

sid="$(node "$H" session_id 2>/dev/null)"
[ -z "$sid" ] && exit 0
case "$sid" in */*|.*) exit 0 ;; esac

f="$d/$sid.md"
[ -f "$f" ] || exit 0
cat "$f" 2>/dev/null
rm -f "$f" 2>/dev/null
exit 0
