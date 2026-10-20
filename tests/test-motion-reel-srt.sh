#!/usr/bin/env bash
# Legenda do Film da motion-reel: o srt.py tira o texto do vo.json e o tempo da timeline + WAV.
#
# Cada fala começa em (cut + beats[i]) / fps, o ponto em que o track_cinema.py põe a voz, e dura o
# WAV dela. Sem WAV o tempo seria estimado, e legenda com tempo inventado não se entrega.
#   1. tempos e texto (grafia da tela, não a pronúncia do say);
#   2. fala sem WAV recusa com exit 1 e sem arquivo;
#   3. filme sem fala sai com exit 3 e sem arquivo.
# Uso: bash tests/test-motion-reel-srt.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SRT="$RAIZ/skills/motion-reel/scripts/srt.py"
[ -f "$SRT" ] || SRT="$RAIZ/plugin/skills/motion-reel/scripts/srt.py"
[ -f "$SRT" ] || { echo "srt.py não encontrado em $RAIZ"; exit 2; }
PY="$(command -v python3)" || { echo "python3 ausente"; exit 2; }

falhas=0
check() { if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"; else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/motion-srt.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/pasta com espaço ção"; mkdir -p "$P/src" "$P/public/vo"
printf '{"lines": [{"id": "a1", "text": "O Claude confere."}, {"id": "a2", "text": "Sem copiar."}, {"id": "b1", "text": "Pronto em 2 minutos."}]}\n' > "$P/vo.json"
# cena 1 no corte 0 (falas em 6 e 50), cena 2 no corte 90 (fala em 6): 30 fps
printf '{"fps": 30, "total": 150, "scenes": [{"cut": 0, "beats": [6, 50], "vo": ["a1", "a2"]}, {"cut": 90, "beats": [6], "vo": ["b1"]}]}\n' > "$P/src/tl-master.json"
wav() { "$PY" -c 'import sys, wave
w = wave.open(sys.argv[1], "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000)
w.writeframes(b"\0\0" * int(48000 * float(sys.argv[2]))); w.close()' "$P/public/vo/$1.wav" "$2"; }
wav a1 1.2; wav a2 0.5; wav b1 1.5

echo "1. tempos e texto"
"$PY" "$SRT" "$P" master "$TMP/m.srt" > "$TMP/1.log" 2>&1; rc=$?
check "sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
esperado="$(printf '1\n00:00:00,200 --> 00:00:01,400\nO Claude confere.\n\n2\n00:00:01,667 --> 00:00:02,167\nSem copiar.\n\n3\n00:00:03,200 --> 00:00:04,700\nPronto em 2 minutos.')"
check "SRT com o tempo da voz e o texto da tela" "$([ "$(cat "$TMP/m.srt" 2>/dev/null)" = "$esperado" ] && echo ok || echo fail)"
[ "$(cat "$TMP/m.srt" 2>/dev/null)" = "$esperado" ] || sed 's/^/        /' "$TMP/m.srt"

echo "2. fala sem WAV"
rm "$P/public/vo/a2.wav"
"$PY" "$SRT" "$P" master "$TMP/s.srt" > "$TMP/2.log" 2>&1; rc=$?
check "recusa com exit 1 (veio $rc)" "$([ "$rc" = 1 ] && echo ok || echo fail)"
check "não grava o arquivo" "$([ -e "$TMP/s.srt" ] && echo fail || echo ok)"
check "cita a fala sem WAV" "$(/usr/bin/grep -q 'a2' "$TMP/2.log" && echo ok || echo fail)"

echo "3. filme sem fala"
printf '{"fps": 30, "total": 60, "scenes": [{"cut": 0, "beats": [], "vo": []}]}\n' > "$P/src/tl-reel.json"
"$PY" "$SRT" "$P" reel "$TMP/r.srt" > "$TMP/3.log" 2>&1; rc=$?
check "sai com exit 3 (veio $rc)" "$([ "$rc" = 3 ] && echo ok || echo fail)"
check "não grava o arquivo" "$([ -e "$TMP/r.srt" ] && echo fail || echo ok)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
