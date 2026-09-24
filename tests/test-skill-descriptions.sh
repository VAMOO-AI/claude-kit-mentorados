#!/usr/bin/env bash
# O catálogo de skills entra no contexto de TODA request: a description de cada skill
# visível ao modelo é lida antes de qualquer trabalho. Medido em 04/09/2026: 14 skills
# visíveis somavam 6.328 chars (~1,6K tokens por request). Este teste é o teto — 500
# chars por description — e a checagem de que o `name:` do frontmatter bate com a pasta
# (o Claude Code roteia pelo nome; pasta com nome diferente vira skill que nunca dispara).
#
# A soma também tem teto. O Claude Code monta a lista de skills do modelo dentro de um
# budget em chars: janela do modelo × 4 × skillListingBudgetFraction (default 0,01, ou seja
# 8.000 chars numa janela de 200K). Desde a 0.40.0 o /kit-vamoo:setup grava 0,02 no
# settings.json: 16.000 em 200K, 80.000 em 1M. A env SLASH_COMMAND_TOOL_CHAR_BUDGET vence a
# fração e fixa o número em qualquer janela (numa de 1M, onde o default é 40K, baixa), então
# o teste reprova a env no template. Skill de plugin entra na lista com o nome do plugin na
# frente: cada uma custa `kit-vamoo:` + nome + 4 + description (com " - " + when_to_use, se
# houver), mais uma quebra de linha entre entradas. O que não cabe não dá erro: as skills
# bundled ficam inteiras e as outras perdem a description até caber.
#
# Só conta o que o modelo vê: skill com `disable-model-invocation: true` fica fora. O teto é
# medido na janela de 200K. O budget é dividido com as skills bundled, as de outros plugins,
# as de ~/.claude/skills e as do projeto, então o kit fica com metade. Em 24/09/2026: 18
# skills na lista, 7.956 chars, 49,7% do budget — a próxima skill visível entra enxugando
# description ou com disable-model-invocation.
#
# `wc -m` conta bytes quando o locale é C ou vazio, e é assim que rodam o Bash tool e os
# hooks do app Desktop: uma description acentuada reprovaria aqui e passaria no CI. O teste
# fixa um locale UTF-8 por conta própria, igual ao plugin/scripts/skills-projeto-scan.sh.
#
# Uso: bash tests/test-skill-descriptions.sh [pasta-de-skills] [limite]
#      (SETTINGS_KIT=<settings.json> troca a origem do budget; FRACAO_KIT=<%>, a parte dele
#       que o kit pode ocupar)
set -uo pipefail
for l in C.UTF-8 en_US.UTF-8; do
  { export LC_ALL="$l"; } 2>/dev/null
  x='ç'; [ "${#x}" -eq 1 ] && break
done
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${1:-$RAIZ/plugin/skills}"
LIMITE="${2:-${LIMITE_DESCRIPTION:-500}}"
S="${SETTINGS_KIT:-$RAIZ/plugin/templates/settings.json}"
FRACAO="${FRACAO_KIT:-50}"
JANELA=200000 # também é o default do CLI quando não sabe a janela do modelo
[ -d "$DIR" ] || { echo "pasta de skills não encontrada: $DIR"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq ausente"; exit 2; }
PLUGIN="$(jq -r '.name // empty' "$RAIZ/plugin/.claude-plugin/plugin.json" 2>/dev/null)"
[ -n "$PLUGIN" ] || { echo "plugin.json sem name: $RAIZ/plugin/.claude-plugin/plugin.json"; exit 2; }
FRACAO_BUDGET="$(jq -r '.skillListingBudgetFraction // empty' "$S" 2>/dev/null)"
BUDGET="$(jq -r --argjson j "$JANELA" '.skillListingBudgetFraction
  | if type == "number" and . > 0 and . <= 1 then ($j * 4 * . | floor) else empty end' "$S" 2>/dev/null)"
ENV_BUDGET="$(jq -r '.env.SLASH_COMMAND_TOOL_CHAR_BUDGET // empty' "$S" 2>/dev/null)"
MAX_DESC=1536 # skillListingMaxDescChars do CLI: a description entra cortada nesse tamanho

falhas=0
soma=0
entradas=0
campo() { # imprime o campo $1 do frontmatter numa linha só (aceita >- e | dobrados)
  awk -v k="$1" '
    /^---[[:space:]]*$/ { c++; if (c == 2) exit; next }
    c == 1 && index($0, k ":") == 1 { p = 1; sub("^" k ":[[:space:]]*", ""); sub(/^[>|]-?[[:space:]]*$/, ""); if ($0 != "") printf "%s ", $0; next }
    c == 1 && p && /^[A-Za-z_-]+:/ { p = 0 }
    c == 1 && p { sub(/^[[:space:]]+/, ""); if ($0 != "") printf "%s ", $0 }
  ' "$2" | sed -E 's/[[:space:]]+$//; s/^"//; s/"$//'
}

printf '%-28s %6s\n' "skill" "chars"
for f in "$DIR"/*/SKILL.md; do
  [ -f "$f" ] || continue
  pasta="$(basename "$(dirname "$f")")"
  nome="$(awk -F': *' '/^---/{c++; next} c==1 && /^name:/{gsub(/\r/,""); print $2; exit}' "$f")"
  d="$(campo description "$f")"
  n="$(printf '%s' "$d" | wc -m | tr -d ' ')"
  manual="$(awk -F': *' '/^---/{c++; next} c==1 && /^disable-model-invocation:/{gsub(/\r/,""); print $2; exit}' "$f")"
  fora=""
  if [ "$manual" = true ]; then fora="só /$PLUGIN:$pasta, fora da lista"
  else
    w="$(campo when_to_use "$f")"
    len="$n"
    [ -n "$w" ] && len=$((n + 3 + $(printf '%s' "$w" | wc -m | tr -d ' ')))
    [ "$len" -gt "$MAX_DESC" ] && len="$MAX_DESC"
    entrada="$PLUGIN:$nome"
    soma=$((soma + ${#entrada} + 4 + len)); entradas=$((entradas + 1))
  fi
  printf '%-28s %6s' "$pasta" "$n"
  [ -n "$fora" ] && printf '   (%s)' "$fora"
  if [ "$nome" != "$pasta" ]; then printf '   FALHA name=%s ≠ pasta\n' "$nome"; falhas=$((falhas+1))
  elif [ -z "$d" ]; then printf '   FALHA sem description\n'; falhas=$((falhas+1))
  elif [ "$n" -gt "$LIMITE" ]; then printf '   FALHA acima de %s chars\n' "$LIMITE"; falhas=$((falhas+1))
  else printf '\n'; fi
done
[ "$entradas" -gt 1 ] && soma=$((soma + entradas - 1))

echo
if [ -n "$ENV_BUDGET" ]; then
  echo "FALHA $S define env.SLASH_COMMAND_TOOL_CHAR_BUDGET=$ENV_BUDGET: a env vence skillListingBudgetFraction e fixa o budget em qualquer janela (numa de 1M, baixa)"
  falhas=$((falhas+1))
fi
if ! [[ "$BUDGET" =~ ^[0-9]+$ ]]; then
  echo "FALHA $S sem skillListingBudgetFraction válido (número entre 0 e 1): a lista de skills volta ao default de 1% da janela e corta"
  falhas=$((falhas+1))
else
  teto=$((BUDGET * FRACAO / 100))
  printf '%-28s %6s   teto %s (%s%% do budget de %s: fração %s na janela de 200K)' \
    "(lista: $entradas skills)" "$soma" "$teto" "$FRACAO" "$BUDGET" "$FRACAO_BUDGET"
  if [ "$soma" -gt "$teto" ]; then
    printf '   FALHA — enxugue descriptions, ou tire da lista a skill que só roda por /nome (disable-model-invocation: true no SKILL.md)\n'
    falhas=$((falhas+1))
  else printf '\n'; fi
fi

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde (limite $LIMITE chars)"; else echo "$falhas falha(s)"; exit 1; fi
