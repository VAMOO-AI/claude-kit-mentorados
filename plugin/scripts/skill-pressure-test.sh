#!/usr/bin/env bash
# Prova que uma skill de disciplina segura o agente quando ele QUER furar a regra.
#
# Uma skill de disciplina (verificacao, worktrees, grilling) muda por incidente:
# alguém fura a regra, a gente escreve o parágrafo, e ninguém prova que o
# parágrafo evita a próxima racionalização. Este script roda um cenário de
# pressão em dois modos e compara:
#
#   --baseline    sem a skill (settings/CLAUDE.md/skills do usuário fora) — o RED
#   --com-skill   com o harness normal e a SKILL.md do plugin no system prompt — o GREEN
#
# O cenário é um .md em tests/skills/<skill>/, com frontmatter:
#
#   ---
#   skill: verificacao
#   esperado: A
#   ---
#   <o cenário, terminando com "Responda só a letra, no formato ESCOLHA: X">
#
# Uso:
#   bash plugin/scripts/skill-pressure-test.sh --baseline  tests/skills/verificacao/cenario-01-pronto-sem-rodar.md
#   bash plugin/scripts/skill-pressure-test.sh --com-skill tests/skills/verificacao/cenario-01-pronto-sem-rodar.md
#   bash plugin/scripts/skill-pressure-test.sh --com-skill --n 3 --model sonnet tests/skills/verificacao/
#
# Saída: por cenário, a letra escolhida vs a esperada, e a justificativa do modelo
# (é ela que vira a tabela de racionalizações da skill). Exit 1 se algum cenário
# no modo --com-skill escolheu errado. No --baseline errar é o esperado: se o
# agente acerta SEM a skill, a skill não está provando nada com esse cenário.
set -uo pipefail

MODO=""; N=1; MODEL=""; ALVOS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --baseline|--com-skill) MODO="$1"; shift ;;
    --n) N="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ALVOS+=("$1"); shift ;;
  esac
done
[ -n "$MODO" ] && [ "${#ALVOS[@]}" -gt 0 ] || { echo "uso: $0 --baseline|--com-skill [--n N] [--model m] <cenario.md|dir>..."; exit 2; }
command -v claude >/dev/null || { echo "claude não está no PATH"; exit 2; }

CENARIOS=()
for a in "${ALVOS[@]}"; do
  if [ -d "$a" ]; then while IFS= read -r f; do CENARIOS+=("$f"); done < <(find "$a" -name 'cenario-*.md' | sort)
  else CENARIOS+=("$a"); fi
done

frontmatter() { awk -v k="$2" 'NR==1&&$0!="---"{exit} /^---$/{c++; next} c==1 && $0 ~ "^"k":"{sub("^"k":[ ]*",""); print; exit}' "$1"; }
corpo() { awk '/^---$/{c++; next} c>=2' "$1"; }

# O cwd é um diretório vazio: nenhum CLAUDE.md nem .claude/ de projeto entra.
# Baseline: --setting-sources vazio tira o CLAUDE.md, as skills e o settings do
# usuário, e nenhuma ferramenta fica ligada. Com skill: harness normal, o texto
# da SKILL.md entra no system prompt (o que está em teste é o texto, não o
# gatilho) e só a ferramenta Skill fica ligada. Sem Bash em nenhum dos dois: o
# cenário é de decisão, e com Bash o modelo "verifica" pra escapar da escolha.
SKILLS_DIR="$(cd "$(dirname "$0")/../skills" && pwd)"
CWD=$(mktemp -d)
FALHAS=0; TOTAL=0
for c in "${CENARIOS[@]}"; do
  SKILL=$(frontmatter "$c" skill); ESPERADO=$(frontmatter "$c" esperado)
  [ -n "$ESPERADO" ] || { echo "$c: sem 'esperado:' no frontmatter"; exit 2; }
  PROMPT=$(corpo "$c")
  for i in $(seq 1 "$N"); do
    TOTAL=$((TOTAL+1))
    # --tools é variádico e engole o que vier depois: fica por último, e o prompt vai por stdin.
    ARGS=(-p --output-format text --max-turns 3)
    [ -n "$MODEL" ] && ARGS+=(--model "$MODEL")
    if [ "$MODO" = "--baseline" ]; then
      ARGS+=(--setting-sources "" --tools "")
    else
      [ -f "$SKILLS_DIR/$SKILL/SKILL.md" ] || { echo "$c: skill '$SKILL' não está em $SKILLS_DIR"; exit 2; }
      ARGS+=(--append-system-prompt-file "$SKILLS_DIR/$SKILL/SKILL.md" --tools Skill)
    fi
    RESP=$(cd "$CWD" && printf '%s' "$PROMPT" | claude "${ARGS[@]}" 2>/dev/null)
    LETRA=$(printf '%s' "$RESP" | grep -oE 'ESCOLHA:[[:space:]]*[A-Z]' | tail -1 | grep -oE '[A-Z]$')
    if [ "$LETRA" = "$ESPERADO" ]; then MARCA="ok   "; else MARCA="ERROU"; [ "$MODO" = "--com-skill" ] && FALHAS=$((FALHAS+1)); fi
    printf '%s %s [%s] run %d/%d: escolheu %s, esperado %s\n' "$MARCA" "$(basename "$c" .md)" "${SKILL:-?}" "$i" "$N" "${LETRA:-?}" "$ESPERADO"
    printf '%s\n' "$RESP" | grep -v 'ESCOLHA:' | sed '/^[[:space:]]*$/d' | tail -6 | sed 's/^/      │ /'
  done
done
rm -rf "$CWD"

echo
if [ "$MODO" = "--baseline" ]; then
  echo "$TOTAL execução(ões) sem a skill. Onde 'ok' apareceu, o cenário não pressiona o suficiente — aperte antes de usar como prova."
else
  echo "$TOTAL execução(ões) com a skill, $FALHAS errada(s)."
  [ "$FALHAS" -gt 0 ] && echo "Copie a justificativa verbatim pra tabela de racionalizações da skill e feche o buraco antes de rodar de novo."
fi
[ "$FALHAS" -eq 0 ]
