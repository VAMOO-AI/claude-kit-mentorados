#!/usr/bin/env bash
# warn-skills-projeto.sh — SessionStart hook.
# Avisa quando as skills DESTE projeto (.claude/skills) passaram do teto ou quando
# alguma cobra sem servir (name ≠ pasta, corpo vazio). Quem faz a conta é o
# scripts/skills-projeto-scan.sh; aqui só se decide QUANDO falar.
#
# Fala uma vez por mudança, não uma vez por sessão: o marcador em
# ~/.claude/.cache/kit-vamoo/skills-projeto/ guarda o momento do último aviso, e o
# hook só volta a olhar quando algum SKILL.md do projeto é mais novo que ele. Sem
# isso, o `npx skills add` de ontem viraria o mesmo parágrafo em todo /clear.
#
# Lê o cwd do payload por node (scripts/hookjson.js) — jq não é pré-requisito de
# quem está aprendendo. Falha-aberta: qualquer coisa fora do lugar, exit 0 calado.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || exit 0
SCAN="$AQUI/../scripts/skills-projeto-scan.sh"
H="$AQUI/../scripts/hookjson.js"
[ -f "$SCAN" ] || exit 0

DIR=""
if [ -f "$H" ] && command -v node >/dev/null 2>&1; then
  DIR="$(cat | node "$H" cwd 2>/dev/null)"
fi
[ -n "$DIR" ] || DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$DIR/.claude/skills" ] || exit 0

CACHE="$HOME/.claude/.cache/kit-vamoo/skills-projeto"
h="$(printf '%s' "$DIR" | shasum 2>/dev/null | awk '{print $1}')"
[ -z "$h" ] && h="$(printf '%s' "$DIR" | cksum | awk '{print $1}')"
marker="$CACHE/$h"

if [ -f "$marker" ]; then
  # Nada mudou desde o último aviso? Então não há novidade para contar.
  [ -n "$(find "$DIR/.claude/skills" -name SKILL.md -newer "$marker" -print -quit 2>/dev/null)" ] || exit 0
fi

saida="$(bash "$SCAN" "$DIR" --resumo 2>/dev/null)"
mkdir -p "$CACHE" 2>/dev/null && touch "$marker" 2>/dev/null
find "$CACHE" -type f -mtime +90 -delete 2>/dev/null   # projeto que ninguém abre mais
[ -n "$saida" ] && printf '%s\n' "$saida"
exit 0
