#!/usr/bin/env bash
# O catálogo de skills entra no contexto de TODA request: a description de cada skill
# visível ao modelo é lida antes de qualquer trabalho. Medido em 04/09/2026: 14 skills
# visíveis somavam 6.328 chars (~1,6K tokens por request). Este teste é o teto — 500
# chars por description — e a checagem de que o `name:` do frontmatter bate com a pasta
# (o Claude Code roteia pelo nome; pasta com nome diferente vira skill que nunca dispara).
#
# Uso: bash tests/test-skill-descriptions.sh [pasta-de-skills] [limite]
set -uo pipefail
DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills}"
LIMITE="${2:-${LIMITE_DESCRIPTION:-500}}"
[ -d "$DIR" ] || { echo "pasta de skills não encontrada: $DIR"; exit 2; }

falhas=0
descricao() { # imprime a description do frontmatter numa linha só (aceita >- e | dobrados)
  awk '
    /^---[[:space:]]*$/ { c++; if (c == 2) exit; next }
    c == 1 && /^description:/ { p = 1; sub(/^description:[[:space:]]*/, ""); sub(/^[>|]-?[[:space:]]*$/, ""); if ($0 != "") printf "%s ", $0; next }
    c == 1 && p && /^[A-Za-z_-]+:/ { p = 0 }
    c == 1 && p { sub(/^[[:space:]]+/, ""); if ($0 != "") printf "%s ", $0 }
  ' "$1" | sed -E 's/[[:space:]]+$//; s/^"//; s/"$//'
}

printf '%-28s %6s\n' "skill" "chars"
for f in "$DIR"/*/SKILL.md; do
  [ -f "$f" ] || continue
  pasta="$(basename "$(dirname "$f")")"
  nome="$(awk -F': *' '/^---/{c++; next} c==1 && /^name:/{gsub(/\r/,""); print $2; exit}' "$f")"
  d="$(descricao "$f")"
  n="$(printf '%s' "$d" | wc -m | tr -d ' ')"
  printf '%-28s %6s' "$pasta" "$n"
  if [ "$nome" != "$pasta" ]; then printf '   FALHA name=%s ≠ pasta\n' "$nome"; falhas=$((falhas+1))
  elif [ -z "$d" ]; then printf '   FALHA sem description\n'; falhas=$((falhas+1))
  elif [ "$n" -gt "$LIMITE" ]; then printf '   FALHA acima de %s chars\n' "$LIMITE"; falhas=$((falhas+1))
  else printf '\n'; fi
done

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde (limite $LIMITE chars)"; else echo "$falhas falha(s)"; exit 1; fi
