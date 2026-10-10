#!/usr/bin/env bash
# A motion-reel que o mentorado instala não carrega a marca de ninguém além da dele.
#
# Em 10/10/2026 a skill já vinha com logos "SUA MARCA", mas a Intro do Reel e o
# Outro (e o Title) do Film ainda desenhavam o infinito azul da VAMOO AI em SVG,
# o Outro do Reel fechava com "/plugin update kit-vamoo" e o SKILL.md/blocks.json
# traziam a voz que o mantenedor usa. Tudo isso saía em toda peça gerada pelo kit.
#
# Este teste confere, de forma estática, que:
#   1. nenhum resíduo (traço do infinito, nome da marca, voz do mantenedor, caminho
#      de máquina) aparece no corpo da skill;
#   2. abertura e encerramento (Intro/Outro do Reel, Title/Outro do Film) desenham
#      o símbolo a partir do public/marca.png da pessoa, com a prop `symbol`;
#   3. o Reel lê `symbol` do timeline.json e o SKILL.md documenta narração sem custo.
#
# Uso: bash tests/test-motion-reel-sem-marca.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SK="$RAIZ/plugin/skills/motion-reel"
SRC="$SK/assets/template/src"
[ -d "$SK" ] || { echo "skill motion-reel não encontrada em $SK"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

# Texto da skill (sem node_modules nem lockfile, que são de terceiros).
residuos() {
  /usr/bin/grep -rniE "$1" "$SK" --exclude-dir=node_modules --exclude=package-lock.json \
    --include='*.md' --include='*.tsx' --include='*.ts' --include='*.json' \
    --include='*.py' --include='*.sh' --include='*.mjs' 2>/dev/null
}

for padrao in 'lemniscate' 'url\(#inf\)' 'infinit' '∞' 'vamoo' 'RGymW84CSmfVugnA5tvA' 'Roberta' '/Users/'; do
  achou="$(residuos "$padrao")"
  if [ -z "$achou" ]; then check "sem \"$padrao\" na skill" ok
  else check "sem \"$padrao\" na skill" fail; printf '%s\n' "$achou" | sed 's/^/        /' | head -5; fi
done

# Corpo de um componente: da linha "export const <Nome>" até a próxima "export const".
corpo() { awk -v n="export const $2" 'index($0, n)==1 {on=1; print; next} on && /^export const / {exit} on {print}' "$1"; }

for par in "scenes.tsx Intro" "scenes.tsx Outro" "film-scenes.tsx Title" "film-scenes.tsx Outro"; do
  set -- $par
  c="$(corpo "$SRC/$1" "$2")"
  if printf '%s' "$c" | /usr/bin/grep -q 'MarkIn' && printf '%s' "$c" | /usr/bin/grep -q 'symbol'; then
    check "$1 $2 usa o marca.png (MarkIn) e respeita symbol" ok
  else
    check "$1 $2 usa o marca.png (MarkIn) e respeita symbol" fail
  fi
done

if /usr/bin/grep -q 'staticFile("marca.png")' "$SRC/lib.tsx" && corpo "$SRC/lib.tsx" MarkIn | /usr/bin/grep -q 'objectFit: "contain"'; then
  check "MarkIn (lib.tsx) lê public/marca.png sem esticar" ok
else
  check "MarkIn (lib.tsx) lê public/marca.png sem esticar" fail
fi

if /usr/bin/grep -q 'symbol' "$SRC/timeline.ts" && /usr/bin/grep -q 'symbol={slot.symbol}' "$SRC/Reel.tsx"; then
  check "Reel lê symbol do timeline.json" ok
else
  check "Reel lê symbol do timeline.json" fail
fi

if /usr/bin/grep -q 'Vídeo para mentorados' "$SK/SKILL.md"; then
  check "SKILL.md sem a seção de uso do mantenedor" fail
else
  check "SKILL.md sem a seção de uso do mantenedor" ok
fi

if /usr/bin/grep -qF "say -v '?'" "$SK/SKILL.md" "$SK/references/narracao.md" && /usr/bin/grep -q 'split-vo' "$SK/SKILL.md"; then
  check "narração sem custo documentada (voz própria + split-vo, say do macOS)" ok
else
  check "narração sem custo documentada (voz própria + split-vo, say do macOS)" fail
fi

echo
if [ "$falhas" -eq 0 ]; then echo "OK: motion-reel sem marca de terceiro"; exit 0; fi
echo "$falhas falha(s)"; exit 1
