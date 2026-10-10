#!/usr/bin/env bash
# Cria um projeto motion-reel novo: copia o template, os assets, instala e gera as trilhas.
# Uso: new.sh [--logo-light <png>] [--logo-dark <png>] [--mark <png>] <pasta-destino>
# As flags valem o mesmo que MOTION_LOGO_LIGHT / MOTION_LOGO_DARK / MOTION_MARK e têm prioridade;
# prefira as flags: a pré-aprovação da skill (allowed-tools) não casa com VAR=... antes do comando.
# Fonte (Plus Jakarta Sans, OFL) e os 7 SFX vêm empacotados na skill. Os logos padrão são
# placeholders "SUA MARCA": aponte os seus com MOTION_LOGO_LIGHT (para fundo claro),
# MOTION_LOGO_DARK (para fundo escuro) e MOTION_MARK (símbolo). MOTION_FONT e MOTION_SFX_DIR
# trocam fonte e banco de efeitos.
# O projeto sai com as 3 composições renderizáveis: Reel (exemplo 9:16 guiado pela música) e
# Master169/Reel916 (Film de exemplo, sem narração ainda: durações estimadas pelo texto).
set -euo pipefail
SK="$(cd "$(dirname "$0")/.." && pwd)"
USO="uso: new.sh [--logo-light <png>] [--logo-dark <png>] [--mark <png>] <pasta-destino>"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --logo-light) MOTION_LOGO_LIGHT="${2:?$USO}"; shift 2 ;;
    --logo-dark) MOTION_LOGO_DARK="${2:?$USO}"; shift 2 ;;
    --mark) MOTION_MARK="${2:?$USO}"; shift 2 ;;
    -*) echo "!! opção desconhecida: $1 ($USO)"; exit 1 ;;
    *) break ;;
  esac
done
DEST="${1:?$USO}"
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
command -v ffmpeg > /dev/null || echo "aviso: ffmpeg ausente; o qa.sh, o final.sh e o corte da narração precisam dele (brew install ffmpeg)"
PY="$("$SK/scripts/py.sh")"

mkdir -p "$DEST"; DEST="$(cd "$DEST" && pwd)"
cp -R "$SK/assets/template/." "$DEST/"
mkdir -p "$DEST/public/sfx" "$DEST/out"
cp "$FONT" "$DEST/public/PlusJakartaSans.ttf"
cp "$LIGHT" "$DEST/public/logo-light.png"
cp "$DARK" "$DEST/public/logo-dark.png"
cp "$MARK" "$DEST/public/marca.png"
cp "$SFXD"/*.wav "$DEST/public/sfx/"
[ -z "${MOTION_LOGO_LIGHT:-}" ] && echo "aviso: logos são placeholders \"SUA MARCA\"; passe --logo-light, --logo-dark e --mark ou troque os PNG em $DEST/public/"

echo "→ npm ci (Remotion 4.0.484 travado no lockfile)"
(cd "$DEST" && npm ci --no-audit --no-fund --loglevel=error)

"$PY" "$DEST/scripts/grain.py"
"$PY" "$DEST/scripts/track.py"
"$PY" "$DEST/scripts/track_cinema.py" master
"$PY" "$DEST/scripts/track_cinema.py" reel
echo
echo "pronto: $DEST"
echo "  Reel (música manda):  reescreva src/timeline.json, src/scenes.tsx e BRAND/C em src/lib.tsx"
echo "  Film (voz manda):     reescreva film.json + vo.json + blocks.json; cenas em src/film-scenes.tsx"
echo "  revisar:  $SK/scripts/qa.sh $DEST [Reel|Master169|Reel916]"
echo "  entregar: $SK/scripts/final.sh $DEST <nome> [Reel|Master169|Reel916]"
