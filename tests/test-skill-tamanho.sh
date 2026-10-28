#!/usr/bin/env bash
# Skill grande perde o fim na compactação. Na compactação automática o Claude Code reanexa a
# última invocação de cada skill só com os primeiros 5.000 tokens, num orçamento total de
# 25.000 tokens preenchido da skill mais recente para a mais antiga (code.claude.com/docs/en/
# skills, "Skill content lifecycle"). O que passa do corte some pelo resto da sessão: na ship
# eram o deploy, o relatório e as "Regras duras"; na secscan, a Fase 6 inteira. O superpowers
# 7.0.1 achou o mesmo (18 rodadas de fix numa task depois de a skill perder o limite de 5).
#
# O teto é em caracteres porque o CI não tem tokenizador. Medido em 28/10/2026 com
# `claude -p --model claude-opus-5-5` (usage do SKILL.md menos o de um prompt vazio): ship
# 28.617 chars = 12.804 tokens, secscan 36.746 = 16.559, grilling 3.872 = 1.678. Dá 2,2 a
# 2,3 chars por token no nosso pt-BR com bloco de código, bem abaixo dos 4 do inglês.
# 10.000 chars ≈ 4.500 tokens: cabe nos 5.000 com margem. O que é passo a passo longo, tabela
# de referência ou script vai para references/, que a skill lê do disco no passo que precisa.
#
# LEGADO é a catraca: as skills que já passavam do teto quando o teste nasceu, com o tamanho
# daquele dia. Skill da lista só pode encolher (crescer reprova); a que desce do teto tem de
# sair da lista (senão a lista mente); skill fora da lista acima do teto reprova. Em
# 28/10/2026: 11 acima do teto; ship e secscan foram fatiadas no mesmo PR → 9. A setup
# (10.447 chars ≈ 4.750 tokens) está abaixo do corte real e acima da margem.
#
# Uso: bash tests/test-skill-tamanho.sh [pasta-de-skills] [teto-em-chars]
set -uo pipefail
for l in C.UTF-8 en_US.UTF-8; do
  { export LC_ALL="$l"; } 2>/dev/null
  x='ç'; [ "${#x}" -eq 1 ] && break
done
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${1:-$RAIZ/plugin/skills}"
TETO="${2:-10000}"
[ -d "$DIR" ] || { echo "pasta de skills não encontrada: $DIR"; exit 2; }

# nome chars-em-28/10/2026
LEGADO="
auditoria-seguranca 44495
diretor-imagem 28478
whatsapp-inbox-stack 27598
motion-reel 20624
baseline 12826
skills-projeto 12073
orquestracao 11180
limpeza-mac 11066
setup 10447
"

falhas=0
avisos=0
printf '%-24s %6s  %s\n' "skill" "chars" "teto $TETO"
for f in "$DIR"/*/SKILL.md; do
  [ -f "$f" ] || continue
  nome="$(basename "$(dirname "$f")")"
  conteudo="$(cat "$f"; printf x)"; conteudo="${conteudo%x}"
  n=${#conteudo}
  max="$(printf '%s\n' "$LEGADO" | awk -v k="$nome" '$1 == k { print $2 }')"
  if [ -z "$max" ]; then
    if [ "$n" -gt "$TETO" ]; then
      printf '%-24s %6d  FALHA: passa do teto; mova seções para references/\n' "$nome" "$n"
      falhas=$((falhas+1))
    fi
  elif [ "$n" -gt "$max" ]; then
    printf '%-24s %6d  FALHA: legado cresceu (era %d); só pode encolher\n' "$nome" "$n" "$max"
    falhas=$((falhas+1))
  elif [ "$n" -le "$TETO" ]; then
    printf '%-24s %6d  FALHA: já cabe no teto; tire da lista LEGADO deste teste\n' "$nome" "$n"
    falhas=$((falhas+1))
  else
    printf '%-24s %6d  aviso: legado acima do teto (máx %d)\n' "$nome" "$n" "$max"
    avisos=$((avisos+1))
  fi
done
for nome in $(printf '%s\n' "$LEGADO" | awk 'NF { print $1 }'); do
  [ -f "$DIR/$nome/SKILL.md" ] || { printf '%-24s        FALHA: está no LEGADO e a skill não existe\n' "$nome"; falhas=$((falhas+1)); }
done

echo
echo "$avisos skill(s) de legado acima do teto"
if [ "$falhas" -eq 0 ]; then echo "PASSOU"; exit 0; fi
echo "FALHOU ($falhas)"; exit 1
