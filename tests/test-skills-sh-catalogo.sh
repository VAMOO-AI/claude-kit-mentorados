#!/usr/bin/env bash
# O catálogo do skills.sh cobre exatamente as skills que existem.
#
# O `skills.sh.json` agrupa as skills na página pública do repo. O modo de falha é
# silencioso dos dois lados: skill nova que ninguém agrupou cai em "notGrouped" no
# fim da página (o kit anuncia 21 skills e o catálogo mostra 20 mais uma órfã), e
# slug que sobrou de uma skill renomeada some da página sem erro nenhum.
#
# Nenhum dos dois quebra a instalação — por isso é teste, e não revisão.
#
# Uso: bash tests/test-skills-sh-catalogo.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
JSON="$RAIZ/skills.sh.json"
SKILLS="$RAIZ/plugin/skills"
[ -f "$JSON" ]   || { echo "skills.sh.json não encontrado em $RAIZ"; exit 2; }
[ -d "$SKILLS" ] || { echo "plugin/skills não encontrado em $RAIZ"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

python3 -m json.tool "$JSON" > /dev/null 2>&1
check "skills.sh.json é JSON válido" "$([ $? = 0 ] && echo ok || echo fail)"

# Slugs declarados, um por linha, na ordem em que aparecem (repetição preservada
# de propósito: é ela que denuncia skill listada em dois grupos).
declarados=$(python3 -c '
import json,sys
d = json.load(open(sys.argv[1]))
for g in d.get("groupings", []):
    for s in g.get("skills", []):
        print(s)
' "$JSON" 2>/dev/null | sort)

existentes=$(find "$SKILLS" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null \
  | sed -E 's|.*/([^/]+)/SKILL.md|\1|' | sort)

faltando=$(comm -13 <(printf '%s\n' "$declarados" | uniq) <(printf '%s\n' "$existentes"))
sobrando=$(comm -23 <(printf '%s\n' "$declarados" | uniq) <(printf '%s\n' "$existentes"))
duplicados=$(printf '%s\n' "$declarados" | uniq -d)

if [ -z "$faltando" ]; then
  check "toda skill de plugin/skills está num grupo" ok
else
  check "toda skill de plugin/skills está num grupo" fail
  printf '%s\n' "$faltando" | sed 's/^/        → sem grupo: /'
  echo "        → sem grupo, ela cai no fim da página do skills.sh e some do catálogo que a gente anuncia"
fi

if [ -z "$sobrando" ]; then
  check "todo slug do catálogo existe como skill" ok
else
  check "todo slug do catálogo existe como skill" fail
  printf '%s\n' "$sobrando" | sed 's/^/        → slug órfão: /'
fi

if [ -z "$duplicados" ]; then
  check "nenhuma skill aparece em dois grupos" ok
else
  check "nenhuma skill aparece em dois grupos" fail
  printf '%s\n' "$duplicados" | sed 's/^/        → duplicada: /'
fi

n_decl=$(printf '%s\n' "$declarados" | uniq | grep -c .)
n_exist=$(printf '%s\n' "$existentes" | grep -c .)
echo "  (catálogo: $n_decl · plugin/skills: $n_exist)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
