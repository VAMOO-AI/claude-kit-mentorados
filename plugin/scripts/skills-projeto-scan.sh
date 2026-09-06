#!/usr/bin/env bash
# skills-projeto-scan.sh — o que as skills DESTE projeto custam em toda request.
#
# A description de cada skill visível ao modelo entra no contexto antes do seu
# primeiro prompt e é relida a cada request — a skill não precisa disparar para
# cobrar. Medição de 05/09/2026 em quatro repositórios de cliente: 52 skills em
# `.claude/skills` somando ~9.030 chars de description (~2.257 tokens por request,
# ESTIMADO por chars÷4). Mais que o catálogo global inteiro de quem mediu.
#
# E há o pior caso: skill que cobra e não entrega. Em 04/09/2026, dez SKILL.md de
# um projeto tinham 99–135 bytes, corpo VAZIO e `name: Refactoring` numa pasta
# `refactoring` — como o roteamento é pelo `name`, elas nunca disparavam. Pagavam
# sem servir.
#
# Uso:
#   bash skills-projeto-scan.sh [pasta-do-projeto]      # tabela + veredito
#   bash skills-projeto-scan.sh [pasta] --resumo        # 1–2 linhas (é o que o hook usa)
#
# Tetos (o hook e a skill `skills-projeto` usam os mesmos):
#   TETO_SKILLS=8  TETO_CHARS=2000  TETO_UMA=500
# Sai 1 quando o projeto passa do teto ou tem skill quebrada; 0 quando está limpo.
set -uo pipefail

DIR="."; RESUMO=0
for a in "$@"; do
  case "$a" in
    --resumo) RESUMO=1 ;;
    -*) ;;
    *) DIR="$a" ;;
  esac
done
TETO_SKILLS="${TETO_SKILLS:-8}"
TETO_CHARS="${TETO_CHARS:-2000}"
TETO_UMA="${TETO_UMA:-500}"

SK="$DIR/.claude/skills"
[ -d "$SK" ] || exit 0

descricao() { # description do frontmatter numa linha só (aceita >- e | dobrados)
  awk '
    /^---[[:space:]]*$/ { c++; if (c == 2) exit; next }
    c == 1 && /^description:/ { p = 1; sub(/^description:[[:space:]]*/, ""); sub(/^[>|]-?[[:space:]]*$/, ""); if ($0 != "") printf "%s ", $0; next }
    c == 1 && p && /^[A-Za-z_-]+:/ { p = 0 }
    c == 1 && p { sub(/^[[:space:]]+/, ""); if ($0 != "") printf "%s ", $0 }
  ' "$1" | sed -E 's/[[:space:]]+$//; s/^"//; s/"$//'
}

total_chars=0; n_skills=0; quebradas=0
linhas_tabela=""; problemas=""
for f in "$SK"/*/SKILL.md; do
  [ -f "$f" ] || continue
  pasta="$(basename "$(dirname "$f")")"
  nome="$(awk -F': *' '/^---/{c++; next} c==1 && /^name:/{gsub(/\r/,""); print $2; exit}' "$f")"
  d="$(descricao "$f")"
  n="$(printf '%s' "$d" | wc -m | tr -d ' ')"
  corpo="$(awk '/^---[[:space:]]*$/ { c++; next } c >= 2 && NF { n++ } END { print n + 0 }' "$f")"
  n_skills=$((n_skills + 1))
  total_chars=$((total_chars + n))

  situacao="ok"
  if [ -z "$nome" ]; then
    situacao="sem name no frontmatter — não roteia"
  elif [ "$nome" != "$pasta" ]; then
    situacao="name \"$nome\" ≠ pasta \"$pasta\" — não roteia"
  elif [ -z "$d" ]; then
    situacao="sem description — o modelo não tem como saber quando usar"
  elif [ "$corpo" -lt 5 ]; then
    situacao="casca: $corpo linha(s) de corpo — cobra e não ensina nada"
  elif [ "$n" -gt "$TETO_UMA" ]; then
    situacao="description de $n chars (teto $TETO_UMA)"
  fi
  [ "$situacao" = ok ] || { quebradas=$((quebradas + 1)); problemas="${problemas}${pasta}: ${situacao}
"; }
  linhas_tabela="${linhas_tabela}$(printf '%-28s %6s %6s  %s' "$pasta" "$n" "$corpo" "$situacao")
"
done

[ "$n_skills" -eq 0 ] && exit 0
tokens=$((total_chars / 4))
estourou=0
[ "$n_skills" -gt "$TETO_SKILLS" ] && estourou=1
[ "$total_chars" -gt "$TETO_CHARS" ] && estourou=1

if [ "$RESUMO" -eq 1 ]; then
  [ "$estourou" -eq 0 ] && [ "$quebradas" -eq 0 ] && exit 0
  msg="📎 skills deste projeto: $n_skills em .claude/skills, $total_chars chars de description (~$tokens tokens em TODA request; teto do kit: $TETO_SKILLS skills / $TETO_CHARS chars)"
  [ "$quebradas" -gt 0 ] && msg="$msg · $quebradas não roteia(m) ou tem corpo vazio"
  echo "$msg."
  echo "   Peça \"revisa as skills deste projeto\" (skill skills-projeto) ou rode: bash \"\${CLAUDE_PLUGIN_ROOT}/scripts/skills-projeto-scan.sh\" ."
  exit 1
fi

printf '%-28s %6s %6s  %s\n' "skill" "chars" "corpo" "situação"
printf '%s' "$linhas_tabela"
echo
echo "$n_skills skill(s) · $total_chars chars de description · ~$tokens tokens por request (ESTIMADO, chars÷4)"
echo "teto: $TETO_SKILLS skills / $TETO_CHARS chars"
if [ "$quebradas" -gt 0 ]; then
  echo
  echo "$quebradas skill(s) cobram sem servir:"
  printf '%s' "$problemas" | sed 's/^/  · /'
fi
if [ "$estourou" -eq 1 ] || [ "$quebradas" -gt 0 ]; then
  echo
  echo "Não é para apagar tudo: a pergunta por skill é \"o que ela ensina que eu teria que repetir?\"."
  echo "O que não ensina nada vira uma linha no CLAUDE.md do projeto, ou vai embora."
  exit 1
fi
echo "dentro do teto."
exit 0
