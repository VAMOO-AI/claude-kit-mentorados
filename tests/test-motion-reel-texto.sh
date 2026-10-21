#!/usr/bin/env bash
# Texto medido da motion-reel (C5): nenhuma palavra cortada na borda na bancada de pior caso.
#
# Até o lote 7 o fit() estimava 0,56 em por caractere e o Grande do Reel tinha 226 px fixos:
# "SOLUÇÃO" (7 letras, dentro do limite documentado) já saía cortada nas duas bordas. Render real:
# a galeria --pior-caso renderiza cada cena do presets/pior-caso.json assentada em 9:16 e 16:9 e
# o Grande com cada palavra da lista; em cada quadro, a coluna da borda (4 px de cada lado) não
# pode ter tinta: pixel que se afasta do fundo daquela coluna em mais de 100 níveis de luminância.
# Mede corte na BORDA do quadro, não a guia segura: a guia se confere de olho na página da bancada
# (out/galeria-pior-caso/index.html), onde cada quadro tem a linha vermelha por cima.
#
# Precisa de um projeto já instalado (o new.sh roda o npm ci): o teste copia o projeto sem o
# node_modules, liga o node_modules dele e põe o src/, os presets/ e os scripts/ da skill em teste.
# Uso: MOTION_RENDER_REAL=1 MOTION_PROJETO=<projeto com node_modules> bash tests/test-motion-reel-texto.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SK="$RAIZ/skills/motion-reel"
[ -d "$SK" ] || SK="$RAIZ/plugin/skills/motion-reel"
A="$SK/assets/template"
[ -f "$A/presets/pior-caso.json" ] || { echo "sem presets/pior-caso.json em $A"; exit 2; }
[ "${MOTION_RENDER_REAL:-}" = 1 ] || { echo "pulado: render real só com MOTION_RENDER_REAL=1"; exit 0; }
PROJ="${MOTION_PROJETO:?MOTION_PROJETO=<projeto criado pelo new.sh>}"
[ -d "$PROJ/node_modules/remotion" ] || { echo "$PROJ sem node_modules: rode o new.sh"; exit 2; }
PY="$("$SK/scripts/py.sh")" || exit 2

falhas=0
check() { if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"; else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/motion-texto.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"; mkdir -p "$P"
(cd "$PROJ" && tar --exclude=./node_modules --exclude=./out -cf - .) | (cd "$P" && tar -xf -)
ln -s "$PROJ/node_modules" "$P/node_modules"
mkdir -p "$P/presets"
cp "$A"/src/* "$P/src/"; cp "$A"/presets/*.json "$P/presets/"; cp "$A"/scripts/* "$P/scripts/"
[ -n "${MOTION_TEXTO_SAIDA:-}" ] && trap 'mkdir -p "$MOTION_TEXTO_SAIDA"; cp "$P"/out/galeria-pior-caso/*.png "$MOTION_TEXTO_SAIDA"/ 2>/dev/null; rm -rf "$TMP"' EXIT

echo "1. bancada de pior caso renderiza"
"$PY" "$SK/scripts/galeria.py" "$P" --pior-caso > "$TMP/gal.log" 2>&1; rc=$?
check "galeria --pior-caso sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || tail -8 "$TMP/gal.log" | sed 's/^/        /'

echo "2. nenhuma palavra encosta na borda"
"$PY" - "$P/out/galeria-pior-caso" > "$TMP/borda.log" 2>&1 <<'PY'
import pathlib, sys
import numpy as np
from PIL import Image
pngs = sorted(pathlib.Path(sys.argv[1]).glob("pior-*.png"))
print("quadros", len(pngs))
for p in pngs:
    lum = np.asarray(Image.open(p).convert("L"), dtype=float)
    ruim = 0
    for col in (lum[:, :4], lum[:, -4:]):
        fundo = np.median(col)
        ruim += int((np.abs(col - fundo) > 100).any(axis=1).sum())
    print(p.stem, ruim)
PY
cat "$TMP/borda.log" | sed 's/^/        /'
n="$(awk '$1=="quadros"{print $2}' "$TMP/borda.log")"
check "a bancada tem quadros (veio ${n:-0})" "$([ "${n:-0}" -ge 10 ] && echo ok || echo fail)"
while read -r nome linhas; do
  [ "$nome" = quadros ] && continue
  check "$nome sem tinta na borda ($linhas linhas)" "$([ "$linhas" = 0 ] && echo ok || echo fail)"
done < "$TMP/borda.log"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
