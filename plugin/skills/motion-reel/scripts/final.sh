#!/usr/bin/env bash
# Render final 1080×1920 + conversão para yuv420p (o Remotion entrega yuvj420p, faixa cheia).
# Uso: final.sh <projeto> <nome-do-arquivo>
set -euo pipefail
SK="$(cd "$(dirname "$0")/.." && pwd)"
P="$(cd "${1:?uso: final.sh <projeto> <nome>}" && pwd)"; NAME="${2:?nome do arquivo}"; O="$P/out"; mkdir -p "$O"
"$("$SK/scripts/py.sh")" "$P/scripts/track.py"
(cd "$P" && npx tsc --noEmit -p "$P" && npx remotion render "$P/src/index.tsx" Reel "$O/raw.mp4" --codec=h264 --crf=16 --audio-codec=aac --log=error)
ffmpeg -loglevel error -y -i "$O/raw.mp4" -vf "scale=in_range=full:out_range=tv,format=yuv420p" \
  -c:v libx264 -crf 17 -preset slow -profile:v high -movflags +faststart -c:a copy "$O/$NAME.mp4"
rm -f "$O/raw.mp4"
ffprobe -v error -show_entries stream=codec_name,pix_fmt,width,height,r_frame_rate,sample_rate -show_entries format=duration,size -of compact "$O/$NAME.mp4"
ffmpeg -hide_banner -i "$O/$NAME.mp4" -af volumedetect -vn -f null - 2>&1 | grep -E "max_volume|mean_volume"
echo "entrega: $O/$NAME.mp4"
