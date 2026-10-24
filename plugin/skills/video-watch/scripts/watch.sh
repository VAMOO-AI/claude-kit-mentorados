#!/usr/bin/env bash
# Baixa um vídeo, extrai frames-chave e transcreve o áudio para consumo do agente.
#
# uso: watch.sh <url-ou-arquivo> [--out DIR] [--frames N] [--lang pt] [--interval SEG] [--no-audio]
set -euo pipefail

MODEL="${WHISPER_MODEL:-$HOME/.cache/whisper-cpp/models/ggml-large-v3-turbo.bin}"
SRC=""; OUT=""; MAX_FRAMES=16; LANG="pt"; INTERVAL=""; DO_AUDIO=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)      OUT="$2"; shift 2 ;;
    --frames)   MAX_FRAMES="$2"; shift 2 ;;
    --lang)     LANG="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --no-audio) DO_AUDIO=0; shift ;;
    *)          SRC="$1"; shift ;;
  esac
done
[[ -n "$SRC" ]] || { echo "uso: watch.sh <url-ou-arquivo> [--out DIR] [--frames N] [--lang pt]" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${OUT:-${TMPDIR:-/tmp}/video-watch/$(date +%s)-$$}"
mkdir -p "$OUT/frames"

# 1. resolver + baixar
if [[ -f "$SRC" ]]; then
  VIDEO="$SRC"
else
  DIRECT="$(python3 "$SCRIPT_DIR/resolve-url.py" "$SRC")"
  VIDEO="$OUT/video.mp4"
  echo "→ baixando…" >&2
  curl -sL -A "Mozilla/5.0" -o "$VIDEO" "$DIRECT"
fi

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO" | cut -d. -f1)
# cut: o ffprobe 9 inclui um side_data_list vazio no stream e o csv saía "1920x1080x"
SIZE=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$VIDEO" | head -1 | cut -dx -f1,2)
HAS_AUDIO=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$VIDEO" | head -1)

# 2. frames — corte de cena primeiro; se render pouco, cai para intervalo fixo
# out_range=full + yuvj420p: quando o select não deixa passar frame nenhum (vídeo estático), o
# ffmpeg 9 abre o mjpeg no EOF com o range do vídeo (tv) e falha com "Non full-range YUV"
# -fps_mode substitui -vsync (removido no ffmpeg 9; existe desde o 5.1)
if [[ -z "$INTERVAL" ]]; then
  ffmpeg -v error -i "$VIDEO" -vf "select='gt(scene,0.25)',scale='min(1280,iw)':-2:out_range=full,format=yuvj420p" \
         -fps_mode vfr -frames:v "$MAX_FRAMES" -q:v 4 \
         -frame_pts 0 "$OUT/frames/scene-%02d.jpg" </dev/null
fi
COUNT=$(ls "$OUT/frames" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$COUNT" -lt 4 ]]; then
  rm -f "$OUT"/frames/*.jpg
  STEP="${INTERVAL:-$(( DUR / MAX_FRAMES + 1 ))}"
  ffmpeg -v error -i "$VIDEO" -vf "fps=1/$STEP,scale='min(1280,iw)':-2:out_range=full,format=yuvj420p" \
         -frames:v "$MAX_FRAMES" -q:v 4 "$OUT/frames/t-%02d.jpg" </dev/null
  FRAME_MODE="intervalo de ${STEP}s"
else
  FRAME_MODE="corte de cena"
fi

# 3. transcrição
TRANSCRIPT=""
if [[ "$DO_AUDIO" == "1" && -n "$HAS_AUDIO" ]]; then
  if [[ ! -f "$MODEL" ]]; then
    echo "!! modelo whisper ausente: $MODEL" >&2
  else
    ffmpeg -v error -i "$VIDEO" -ar 16000 -ac 1 -c:a pcm_s16le "$OUT/audio.wav" -y </dev/null
    echo "→ transcrevendo…" >&2
    # -mc 0: sem contexto entre janelas — evita o loop de repetição do whisper em silêncio
    whisper-cli -m "$MODEL" -f "$OUT/audio.wav" -l "$LANG" -np -nt -mc 0 \
                -otxt -of "$OUT/transcript" >/dev/null 2>&1
    [[ -s "$OUT/transcript.txt" ]] && TRANSCRIPT="$OUT/transcript.txt"
  fi
fi

# 4. relatório para o agente
{
  echo "duração: ${DUR}s | resolução: $SIZE | áudio: $([[ -n "$HAS_AUDIO" ]] && echo sim || echo não)"
  echo "frames ($FRAME_MODE):"
  ls "$OUT"/frames/*.jpg 2>/dev/null || echo "  (nenhum)"
  if [[ -n "$TRANSCRIPT" ]]; then
    echo "transcript: $TRANSCRIPT"
  elif [[ "$DO_AUDIO" == "0" ]]; then
    echo "transcript: — (pulado: --no-audio)"
  elif [[ -z "$HAS_AUDIO" ]]; then
    echo "transcript: — (vídeo sem faixa de áudio)"
  else
    echo "transcript: — (falhou)"
  fi
} | tee "$OUT/index.txt"
