#!/usr/bin/env bash
# Render final + conversão para yuv420p (o Remotion entrega yuvj420p, faixa cheia) + áudio
# normalizado para redes sociais (loudnorm I=-14 LUFS + limiter de pico verdadeiro em -1,5 dBTP),
# AAC 320k a 48 kHz.
# Uso: final.sh <projeto> <nome-do-arquivo> [Reel|Master169|Reel916]   (padrão: Reel)
#      final.sh --verificar <arquivo.mp4>              (só a verificação, sem renderizar)
#      final.sh --encodar <cru.mp4> <saida.mp4> [legenda.srt]   (só o encode, sem renderizar)
#      final.sh --video <arquivo.mp4>                  (só o aviso de cena parada e quadro preto)
# Tudo sai primeiro em out/.staging-<nome>/: render ou encode que falha não toca no <nome>.mp4 que
# já estava em out/. Aprovado, o MP4 entra no lugar; reprovado, vira <nome>-reprovado.mp4 e o bom fica.
# Depois do render, verifica o MP4 ENTREGUE: folha de contato (<nome>-folha.jpg, 2 fps),
# loudness por segundo (<nome>-loudness.txt), reprovação (exit 1) se o integrado sair de
# −14 ±1 LUFS ou o pico passar de −1 dBTP, e aviso de cena parada (≥ 2 s) ou quadro preto (≥ 0,5 s).
# No Film sai também <nome>.srt (falas do vo.json no tempo da voz), embutido como faixa no 16:9.
# A faixa de 12 quadros em volta de cada transição vai para <nome>-transicoes/ (revisar.sh).
# Arquivo > 30 MB ganha também <nome>-leve.mp4 (metade da resolução), só se o principal passar:
# o envio de arquivo para o celular/web tem teto de 30 MB.
set -euo pipefail

parado_e_preto() { # parado_e_preto <mp4> <duração>: avisa cena parada ≥ 2 s e quadro preto ≥ 0,5 s
  # Aviso, não reprovação: um cartão final segurado de propósito também para. Confira o trecho.
  # pix_th=0.05 + pic_th=0.999: só conta quadro com 99,9% dos pixels abaixo de 5% de luma. A
  # assinatura (símbolo e logo pequenos sobre o fundo night) ocupa menos de 2% da tela e não é preto.
  ffmpeg -hide_banner -nostats -i "$1" -an -vf "scale=320:-2,freezedetect=n=-60dB:d=2,blackdetect=d=0.5:pix_th=0.05:pic_th=0.999" -f null - 2>&1 |
    awk -v dur="$2" '
      /freeze_start:/ { a = $NF + 0; aberto = 1 }
      /freeze_end:/ { printf "!! ATENÇÃO: cena parada de %.1f s a %.1f s (nada se mexe por %.1f s)\n", a, $NF, $NF - a; aberto = 0; n++ }
      /black_start:/ { match($0, /black_start:[0-9.]+/); i = substr($0, RSTART + 12, RLENGTH - 12)
                       match($0, /black_end:[0-9.]+/); e = substr($0, RSTART + 10, RLENGTH - 10)
                       printf "!! ATENÇÃO: quadro preto de %.1f s a %.1f s\n", i, e; n++ }
      END {
        if (aberto) { printf "!! ATENÇÃO: cena parada de %.1f s até o fim (%.1f s)\n", a, dur; n++ }
        if (n) print "   (confira na folha ou com revisar.sh faixa; parado de propósito, como um cartão final, pode ficar)"
        else print "vídeo: sem cena parada nem quadro preto"
      }'
}

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
  [ -n "${STG:-}" ] || { echo "folha do final: $D/$N-folha.jpg"; echo "loudness por segundo: $D/$N-loudness.txt"; }
  parado_e_preto "$MP4" "$DUR"
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
        printf "!! REPROVADO: pico de %.1f dBTP acima de -1. Baixe o SFX ou o golpe da trilha no segundo do \"pico mais alto\" (no loudness.txt) e rode o final.sh de novo.\n", TP
        r = 1
      }
      if (!r) print "áudio aprovado: integrado e pico dentro do alvo"
      exit r
    }' "$D/$N-loudness.txt"
}

encodar() { # encodar <cru.mp4> <saida.mp4> [legenda.srt]
  local RAW="$1" OUT="$2" SRT="${3:-}" MEAS LOG
  # loudnorm em duas passadas: a 1ª mede, a 2ª aplica linear. Numa passada só o filtro é dinâmico
  # e erra o alvo em ~1 LU em trilha sem voz.
  MEAS="$(ffmpeg -hide_banner -i "$RAW" -af "loudnorm=$LN:print_format=json" -vn -f null - 2>&1 | "$PY" -c '
import json, sys
t = sys.stdin.read(); j = json.JSONDecoder().raw_decode(t[t.rindex("{"):])[0]
print("measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s" % tuple(j[k] for k in ("input_i", "input_tp", "input_lra", "input_thresh", "target_offset")))')"
  # Limiter depois do loudnorm, a 4x a taxa (aproxima o pico verdadeiro): o loudnorm linear não
  # segura um SFX que estoura, e o AAC ainda sobe uns décimos
  # (overshoot), por isso o teto fica em -1,5 e a verificação mede o MP4 contra -1.
  LOG="$(ffmpeg -hide_banner -nostats -y -i "$RAW" ${SRT:+-i "$SRT"} -map 0:v:0 -map "0:a?" ${SRT:+-map 1:s -c:s mov_text -metadata:s:s:0 language=por} \
    -vf "scale=in_range=full:out_range=tv,format=yuv420p" \
    -c:v libx264 -crf 17 -preset slow -profile:v high -movflags +faststart \
    -af "loudnorm=$LN:$MEAS:linear=true:print_format=summary,aresample=192000,alimiter=limit=$LIMITE:level=false:attack=5:release=50:latency=1,aresample=48000" \
    -ar 48000 -c:a aac -b:a 320k "$OUT" 2>&1)" || { printf '%s\n' "$LOG" | tail -20; echo "!! o encode falhou"; return 1; }
  printf '%s\n' "$LOG" | /usr/bin/grep -i "normalization type" | sed 's/^ */loudnorm: /' || true
}

LN="I=-14:TP=-1:LRA=11"
LIMITE=0.8414  # -1,5 dBTP em amplitude linear (10^(-1,5/20))
SK="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" = --verificar ]; then verificar "${2:?uso: final.sh --verificar <arquivo.mp4>}"; exit; fi
if [ "${1:-}" = --video ]; then
  V="${2:?uso: final.sh --video <arquivo.mp4>}"; [ -f "$V" ] || { echo "!! não achei $V"; exit 2; }
  parado_e_preto "$V" "$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$V")"; exit
fi
if [ "${1:-}" = --encodar ]; then
  PY="$("$SK/scripts/py.sh" 2>/dev/null || command -v python3)"  # só lê o JSON do loudnorm
  encodar "${2:?uso: final.sh --encodar <cru.mp4> <saida.mp4> [legenda.srt]}" "${3:?saída}" "${4:-}"; exit
fi

P="$(cd "${1:?uso: final.sh <projeto> <nome> [Reel|Master169|Reel916]}" && pwd)"; NAME="${2:?nome do arquivo}"
COMP="${3:-Reel}"; O="$P/out"; mkdir -p "$O"
PY="$("$SK/scripts/py.sh")"
case "$COMP" in
  Reel) "$PY" "$P/scripts/track.py"; TL="$P/src/timeline.json" ;;
  Master169|Reel916)
    TLN="$([ "$COMP" = Master169 ] && echo master || echo reel)"; TL="$P/src/tl-$TLN.json"
    "$PY" "$P/scripts/build-timeline.py" "$TLN"
    "$PY" "$P/scripts/track_cinema.py" "$TLN" ;;
  *) echo "!! composição desconhecida: $COMP (Reel, Master169 ou Reel916)"; exit 1 ;;
esac
STG="$O/.staging-$NAME"; rm -rf "$STG"; mkdir -p "$STG"
trap 'rm -rf "$STG"' EXIT
(cd "$P" && npx tsc --noEmit -p "$P" && npx remotion render "$P/src/index.tsx" "$COMP" "$STG/raw.mp4" --codec=h264 --crf=16 --audio-codec=aac --log=error)
SRT=""
if [ "$COMP" != Reel ]; then
  rc=0; "$PY" "$SK/scripts/srt.py" "$P" "$TLN" "$STG/$NAME.srt" || rc=$?
  [ "$rc" = 0 ] && SRT="$STG/$NAME.srt"
  [ "$rc" = 1 ] && echo "   (o MP4 sai sem legenda)"
fi
# A legenda vai como faixa só no 16:9 (player de site e YouTube); o 9:16 recebe o .srt ao lado.
encodar "$STG/raw.mp4" "$STG/$NAME.mp4" "$([ "$COMP" = Master169 ] && echo "$SRT")"
rm -f "$STG/raw.mp4"
ffprobe -v error -show_entries stream=codec_name,pix_fmt,width,height,r_frame_rate,sample_rate -show_entries format=duration,size -of compact "$STG/$NAME.mp4"
if ! verificar "$STG/$NAME.mp4"; then
  for x in .mp4 -folha.jpg -loudness.txt; do [ ! -f "$STG/$NAME$x" ] || mv -f "$STG/$NAME$x" "$O/$NAME-reprovado$x"; done
  echo "!! REPROVADO: o novo ficou em $O/$NAME-reprovado.mp4 e não se entrega (folha e loudness com o mesmo nome)."
  [ -f "$O/$NAME.mp4" ] && echo "   O $O/$NAME.mp4 anterior continua lá, intacto."
  echo "   Ajuste e rode o final.sh de novo."
  exit 1
fi
for x in .mp4 -folha.jpg -loudness.txt .srt; do [ -f "$STG/$NAME$x" ] && mv -f "$STG/$NAME$x" "$O/$NAME$x"; done
[ -n "$SRT" ] || rm -f "$O/$NAME.srt"
rm -f "$O/$NAME-reprovado.mp4" "$O/$NAME-reprovado-folha.jpg" "$O/$NAME-reprovado-loudness.txt" "$O/$NAME-leve.mp4"
echo "folha do final: $O/$NAME-folha.jpg · loudness por segundo: $O/$NAME-loudness.txt"
bash "$SK/scripts/revisar.sh" transicoes "$O/$NAME.mp4" "$TL"
[ -n "$SRT" ] && echo "legenda: $O/$NAME.srt$([ "$COMP" = Master169 ] && echo ' (também embutida no MP4)')"
if [ "$(wc -c < "$O/$NAME.mp4")" -gt 30000000 ]; then
  ffmpeg -loglevel error -y -i "$O/$NAME.mp4" -vf "scale=iw/2:-2" -c:v libx264 -crf 28 -preset medium -movflags +faststart -c:a aac -b:a 128k "$O/$NAME-leve.mp4"
  echo "leve (para o celular): $O/$NAME-leve.mp4 ($(($(wc -c < "$O/$NAME-leve.mp4") / 1000000)) MB)"
fi
echo "entrega: $O/$NAME.mp4"
