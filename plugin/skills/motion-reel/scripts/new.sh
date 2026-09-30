#!/usr/bin/env bash
# Cria um projeto motion-reel novo: copia o template, os assets, instala e gera a trilha.
# Uso: new.sh <pasta-destino>
# Fonte (Plus Jakarta Sans, OFL) e os 7 SFX vêm empacotados na skill. Os logos padrão são
# placeholders "SUA MARCA": aponte os seus com MOTION_LOGO_LIGHT (para fundo claro),
# MOTION_LOGO_DARK (para fundo escuro) e MOTION_MARK (símbolo). MOTION_FONT e MOTION_SFX_DIR
# trocam fonte e banco de efeitos.
set -euo pipefail
SK="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:?uso: new.sh <pasta-destino>}"
[ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ] && { echo "!! $DEST já existe e não está vazia"; exit 1; }

FONT="${MOTION_FONT:-$SK/assets/fonts/PlusJakartaSans.ttf}"
SFXD="${MOTION_SFX_DIR:-$SK/assets/sfx}"
LIGHT="${MOTION_LOGO_LIGHT:-$SK/assets/logos/logo-light.png}"
DARK="${MOTION_LOGO_DARK:-$SK/assets/logos/logo-dark.png}"
MARK="${MOTION_MARK:-$SK/assets/logos/marca.png}"
for f in "$FONT" "$LIGHT" "$DARK" "$MARK" "$SFXD/soft-whoosh.wav"; do
  [ -f "$f" ] || { echo "!! asset ausente: $f (confira MOTION_FONT / MOTION_LOGO_* / MOTION_MARK / MOTION_SFX_DIR)"; exit 1; }
done
command -v npm > /dev/null || { echo "!! npm não encontrado: instale o Node.js 18+"; exit 1; }
command -v ffmpeg > /dev/null || echo "aviso: ffmpeg ausente; o qa.sh e o final.sh precisam dele (brew install ffmpeg)"
PY="$("$SK/scripts/py.sh")"

mkdir -p "$DEST"; DEST="$(cd "$DEST" && pwd)"
cp -R "$SK/assets/template/." "$DEST/"
mkdir -p "$DEST/public/sfx" "$DEST/out"
cp "$FONT" "$DEST/public/PlusJakartaSans.ttf"
cp "$LIGHT" "$DEST/public/logo-light.png"
cp "$DARK" "$DEST/public/logo-dark.png"
cp "$MARK" "$DEST/public/marca.png"
cp "$SFXD"/*.wav "$DEST/public/sfx/"
[ -z "${MOTION_LOGO_LIGHT:-}" ] && echo "aviso: logos são placeholders \"SUA MARCA\"; defina MOTION_LOGO_LIGHT, MOTION_LOGO_DARK e MOTION_MARK ou troque os PNG em $DEST/public/"

echo "→ npm ci (Remotion 4.0.484 travado no lockfile)"
(cd "$DEST" && npm ci --no-audit --no-fund --loglevel=error)

"$PY" "$DEST/scripts/track.py"
echo
echo "pronto: $DEST"
echo "  1. reescreva $DEST/src/timeline.json (cenas, cortes na batida, cues), $DEST/src/scenes.tsx e BRAND/C em $DEST/src/lib.tsx"
echo "  2. $SK/scripts/qa.sh $DEST      # prévia + folhas de revisão"
echo "  3. $SK/scripts/final.sh $DEST <nome>"
