#!/usr/bin/env bash
# Render final + conversão para yuv420p (o Remotion entrega yuvj420p, faixa cheia) + áudio
# normalizado para redes sociais (loudnorm I=-14 LUFS, pico -1 dBTP), AAC 320k a 48 kHz.
# Uso: final.sh <projeto> <nome-do-arquivo> [Reel|Master169|Reel916]   (padrão: Reel)
# Arquivo > 30 MB ganha também <nome>-leve.mp4 (metade da resolução): o envio de arquivo para o
# celular/web tem teto de 30 MB.
set -euo pipefail
SK="$(cd "$(dirname "$0")/.." && pwd)"
P="$(cd "${1:?uso: final.sh <projeto> <nome> [Reel|Master169|Reel916]}" && pwd)"; NAME="${2:?nome do arquivo}"
COMP="${3:-Reel}"; O="$P/out"; mkdir -p "$O"
PY="$("$SK/scripts/py.sh")"
case "$COMP" in
  Reel) "$PY" "$P/scripts/track.py" ;;
  Master169|Reel916)
    TLN="$([ "$COMP" = Master169 ] && echo master || echo reel)"
    "$PY" "$P/scripts/build-timeline.py" "$TLN"
    "$PY" "$P/scripts/track_cinema.py" "$TLN" ;;
  *) echo "!! composição desconhecida: $COMP (Reel, Master169 ou Reel916)"; exit 1 ;;
esac
(cd "$P" && npx tsc --noEmit -p "$P" && npx remotion render "$P/src/index.tsx" "$COMP" "$O/raw-$COMP.mp4" --codec=h264 --crf=16 --audio-codec=aac --log=error)
# loudnorm em duas passadas: a 1ª mede, a 2ª aplica linear. Numa passada só o filtro é dinâmico
# e erra o alvo em ~1 LU em trilha sem voz.
LN="I=-14:TP=-1:LRA=11"
MEAS="$(ffmpeg -hide_banner -i "$O/raw-$COMP.mp4" -af "loudnorm=$LN:print_format=json" -vn -f null - 2>&1 | "$PY" -c '
import json, sys
t = sys.stdin.read(); j = json.JSONDecoder().raw_decode(t[t.rindex("{"):])[0]
print("measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s" % tuple(j[k] for k in ("input_i", "input_tp", "input_lra", "input_thresh", "target_offset")))')"
ffmpeg -loglevel error -y -i "$O/raw-$COMP.mp4" -vf "scale=in_range=full:out_range=tv,format=yuv420p" \
  -c:v libx264 -crf 17 -preset slow -profile:v high -movflags +faststart \
  -af "loudnorm=$LN:$MEAS:linear=true" -ar 48000 -c:a aac -b:a 320k "$O/$NAME.mp4"
rm -f "$O/raw-$COMP.mp4"
ffprobe -v error -show_entries stream=codec_name,pix_fmt,width,height,r_frame_rate,sample_rate -show_entries format=duration,size -of compact "$O/$NAME.mp4"
ffmpeg -hide_banner -i "$O/$NAME.mp4" -af ebur128=peak=true -f null - 2>&1 | grep -E "^\s+(I|Peak):" | tail -2
if [ "$(wc -c < "$O/$NAME.mp4")" -gt 30000000 ]; then
  ffmpeg -loglevel error -y -i "$O/$NAME.mp4" -vf "scale=iw/2:-2" -c:v libx264 -crf 28 -preset medium -movflags +faststart -c:a aac -b:a 128k "$O/$NAME-leve.mp4"
  echo "leve (para o celular): $O/$NAME-leve.mp4 ($(($(wc -c < "$O/$NAME-leve.mp4") / 1000000)) MB)"
fi
echo "entrega: $O/$NAME.mp4"
