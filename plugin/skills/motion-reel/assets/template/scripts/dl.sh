#!/usr/bin/env bash
# Baixa o MP3 de um bloco de narração → out/vo-blocks/<bloco>.mp3 e imprime a duração.
# Uso: dl.sh <bloco> '<url-assinada-completa>'   (aspas simples: a URL tem & e %)
# A URL assinada do ElevenLabs (media[].url do conector) EXPIRA EM 2 HORAS: baixe assim que
# a geração terminar. 403 aqui quase sempre é URL vencida — gere o bloco de novo.
set -euo pipefail
P="$(cd "$(dirname "$0")/.." && pwd)"
B="${1:?uso: dl.sh <bloco> <url>}"; U="${2:?uso: dl.sh <bloco> <url>}"
mkdir -p "$P/out/vo-blocks"
if curl -sSf -o "$P/out/vo-blocks/$B.mp3" "$U"; then
  echo "$B ok $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$P/out/vo-blocks/$B.mp3")s"
else
  echo "$B FALHOU (URL vencida? ela vale 2 h)"; exit 1
fi
