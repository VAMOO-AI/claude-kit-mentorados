#!/usr/bin/env bash
# Render final + conversão para yuv420p (o Remotion entrega yuvj420p, faixa cheia) + áudio
# normalizado para redes sociais (loudnorm I=-14 LUFS, pico -1 dBTP), AAC 320k a 48 kHz.
# Uso: final.sh <projeto> <nome-do-arquivo> [Reel|Master169|Reel916]   (padrão: Reel)
#      final.sh --verificar <arquivo.mp4>   (só a verificação, sem renderizar)
# Depois do render, verifica o MP4 ENTREGUE: folha de contato (<nome>-folha.jpg, 2 fps),
# loudness por segundo (<nome>-loudness.txt) e reprovação (exit 1) se o integrado sair de
# −14 ±1 LUFS ou o pico passar de −1 dBTP.
# Arquivo > 30 MB ganha também <nome>-leve.mp4 (metade da resolução), só se o principal passar:
# o envio de arquivo para o celular/web tem teto de 30 MB.
set -euo pipefail

verificar() { # verificar <arquivo.mp4> → grava folha e loudness ao lado; exit 1 se reprovar
  local MP4="$1" D N DUR W H COLS TW FRAMES ROWS LOG
  [ -f "$MP4" ] || { echo "!! não achei $MP4"; return 2; }
  D="$(dirname "$MP4")"; N="$(basename "$MP4" .mp4)"
  read -r W H DUR <<< "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height:format=duration \
    -of default=nw=1:nk=1 "$MP4" | tr '\n' ' ')"
  # Folha única: a grade cresce com a duração para caber tudo num JPEG só.
  if [ "$H" -gt "$W" ]; then COLS=10; TW=108; else COLS=6; TW=240; fi
  FRAMES="$(awk -v d="$DUR" 'BEGIN { print int(d * 2) + 1 }')"; ROWS=$(( (FRAMES + COLS - 1) / COLS ))
  # scale=out_range=full,format=yuvj420p: o final é yuv420p em range tv e o mjpeg do ffmpeg 9
  # recusa ("Non full-range YUV")
  ffmpeg -loglevel error -y -i "$MP4" -vf "fps=2,scale=$TW:-2,tile=${COLS}x$ROWS:padding=3:color=gray,scale=out_range=full,format=yuvj420p" \
    -frames:v 1 "$D/$N-folha.jpg"
  # Uma passada do ebur128: o log traz M (momentâneo, 400 ms) e o pico de cada bloco de 100 ms, e
  # o resumo no fim traz o integrado e o pico verdadeiro.
  LOG="$(ffmpeg -hide_banner -nostats -i "$MP4" -vn -af ebur128=peak=true -f null - 2>&1)"
  printf '%s\n' "$LOG" | awk -v arq="$N.mp4" '
    function db(x) { return (x == "-inf" || x == "") ? -200 : x + 0 }
    / t: [0-9.]+ .* M:/ {
      match($0, / t: *[0-9.]+/); t = substr($0, RSTART + 3, RLENGTH - 3) + 0; s = int(t)
      match($0, /M: *[-0-9.inf]+/); m = db(substr($0, RSTART + 2, RLENGTH - 2))
      match($0, /FTPK: *[-0-9.inf]+ +[-0-9.inf]+/); split(substr($0, RSTART + 5, RLENGTH - 5), pk, " ")
      p = db(pk[1]) > db(pk[2]) ? db(pk[1]) : db(pk[2])
      if (s > ultimo) ultimo = s
      if (!(s in pico) || p > pico[s]) pico[s] = p
      if (!tem || p > pmax) { pmax = p; spmax = s; tem = 1 }
      if (m > -70) { pot[s] += 10 ^ (m / 10); n[s]++ }
      next
    }
    /^ +I: +[-0-9.inf]+ LUFS/ { I = db($2) }
    /^ +Peak: +[-0-9.inf]+ dBFS/ { TP = db($2) }
    END {
      ok = 1
      printf "arquivo: %s\nintegrado: %.1f LUFS (alvo -14 ±1)\npico verdadeiro: %.1f dBTP (teto -1)\n", arq, I, TP
      for (s = 0; s <= ultimo; s++) if (n[s]) { L[s] = 10 * log(pot[s] / n[s]) / log(10); ord[++k] = s }
      for (i = 2; i <= k; i++) { v = ord[i]; for (j = i - 1; j >= 1 && L[ord[j]] < L[v]; j--) ord[j + 1] = ord[j]; ord[j + 1] = v }
      lim = k < 3 ? k : 3
      printf "\nsegundos mais altos:"; for (i = 1; i <= lim; i++) printf " %ds (%.1f LUFS, pico %.1f)", ord[i], L[ord[i]], pico[ord[i]]
      printf "\nsegundos mais baixos:"; for (i = k; i > k - lim; i--) printf " %ds (%.1f LUFS)", ord[i], L[ord[i]]
      printf "\npico mais alto: %ds (%.1f dBTP)", spmax, pmax
      sil = ""; for (s = 0; s <= ultimo; s++) if (!n[s]) sil = sil " " s "s"
      if (sil != "") printf "\nsilêncio:%s", sil
      printf "\n\npor segundo (LUFS momentâneo médio, pico do segundo em dBTP):\n"
      for (s = 0; s <= ultimo; s++) if (n[s]) printf "%4ds  %6.1f  %6.1f\n", s, L[s], pico[s]; else printf "%4ds  silêncio\n", s
    }' > "$D/$N-loudness.txt"
  sed -n '2,3p;5,8p' "$D/$N-loudness.txt"
  echo "folha do final: $D/$N-folha.jpg"; echo "loudness por segundo: $D/$N-loudness.txt"
  awk -v f="$D/$N-loudness.txt" '
    /^integrado:/ { I = $2 + 0 } /^pico verdadeiro:/ { TP = $3 + 0 }
    END {
      r = 0
      if (I < -15 || I > -13) {
        printf "!! REPROVADO: integrado de %.1f LUFS fora de -14 ±1. ", I
        if (I < -15) print "Saiu baixo: trilha com silêncio longo ou faixa dinâmica grande demais para o loudnorm linear. Suba a voz ou a trilha no mix (track.py / track_cinema.py), encurte silêncios e rode o final.sh de novo."
        else print "Saiu alto: baixe a trilha e os SFX no mix (track.py / track_cinema.py) e rode o final.sh de novo."
        r = 1
      }
      if (TP > -1) {
        printf "!! REPROVADO: pico de %.1f dBTP acima de -1. Baixe o SFX ou o golpe da trilha no segundo do "pico mais alto" (em %s) e rode o final.sh de novo.\n", TP, f
        r = 1
      }
      if (!r) print "áudio aprovado: integrado e pico dentro do alvo"
      exit r
    }' "$D/$N-loudness.txt"
}

if [ "${1:-}" = --verificar ]; then verificar "${2:?uso: final.sh --verificar <arquivo.mp4>}"; exit; fi

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
verificar "$O/$NAME.mp4" || { echo "!! $O/$NAME.mp4 foi gerado mas está REPROVADO: não entregue. Ajuste e rode o final.sh de novo."; exit 1; }
if [ "$(wc -c < "$O/$NAME.mp4")" -gt 30000000 ]; then
  ffmpeg -loglevel error -y -i "$O/$NAME.mp4" -vf "scale=iw/2:-2" -c:v libx264 -crf 28 -preset medium -movflags +faststart -c:a aac -b:a 128k "$O/$NAME-leve.mp4"
  echo "leve (para o celular): $O/$NAME-leve.mp4 ($(($(wc -c < "$O/$NAME-leve.mp4") / 1000000)) MB)"
fi
echo "entrega: $O/$NAME.mp4"
