#!/usr/bin/env bash
# warn-doc-ancorado.sh — SessionStart hook.
#
# Handoff e baseline trazem "**Base:** <branch> @ `<sha>`". O documento não apodrece
# sozinho: o repo é que anda. Sem este aviso, alguém planeja em cima de um doc que
# descreve um estado de três semanas atrás e não tem como saber.
#
# O repo vem do `.cwd` do payload (lido por node, scripts/hookjson.js): numa sessão de
# worktree do app desktop, `${CLAUDE_PROJECT_DIR:-$PWD}` pode ser a raiz do clone principal.
# O env e o $PWD ficam só de reserva, para payload sem cwd.
#
# Silencioso no caso bom, e o caso bom é conferido em toda sessão (são três ou quatro
# chamadas de git). Depois de avisar, cala no mesmo repo até o dia seguinte: o marcador é
# nomeado pela pasta + hash do caminho, para dois repos com a mesma pasta não calarem um
# ao outro. Fail-open: qualquer erro => silêncio.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
H="$AQUI/../scripts/hookjson.js"
DIR=""
if [ -f "$H" ] && command -v node >/dev/null 2>&1 && [ ! -t 0 ]; then
  DIR="$(node "$H" cwd 2>/dev/null)"
fi
[ -n "$DIR" ] || DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$DIR" 2>/dev/null || exit 0
[ -d .context/docs ] || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
LIMITE="${DOC_ANCORADO_COMMITS:-40}"

CACHE_DIR="$HOME/.claude/.cache/doc-ancorado"
slug="${DIR##*/}"; slug="${slug//[^A-Za-z0-9._-]/_}"
cam="$(printf '%s' "$DIR" | cksum | awk '{print $1}')"
marcador="$CACHE_DIR/${slug}-${cam}.$(date +%Y%m%d)"
[ -f "$marcador" ] && exit 0

stale=""
for f in .context/docs/baseline.md .context/docs/handoffs/*.md .context/docs/HANDOFF*.md; do
  [ -f "$f" ] || continue
  sha=$(grep -m1 -oE '\*\*Base:\*\*[^`]*`[^`]+`[^`]*`([0-9a-f]{7,40})`|\*\*Base:\*\*[^`]*`([0-9a-f]{7,40})`' "$f" 2>/dev/null \
        | grep -oE '[0-9a-f]{7,40}' | tail -1)
  [ -n "$sha" ] || continue
  git cat-file -e "$sha^{commit}" 2>/dev/null || continue
  behind=$(git rev-list --count "$sha"..HEAD 2>/dev/null) || continue
  [ "${behind:-0}" -ge "$LIMITE" ] && stale="$stale   $f — $behind commits atrás de HEAD"$'\n'
done

[ -n "$stale" ] || exit 0
echo "⚠️ doc ancorado em SHA distante do HEAD (confirme antes de planejar por ele):"
printf '%s' "$stale"
mkdir -p "$CACHE_DIR" 2>/dev/null && : > "$marcador" 2>/dev/null
find "$CACHE_DIR" -type f -mtime +7 -delete 2>/dev/null
exit 0
