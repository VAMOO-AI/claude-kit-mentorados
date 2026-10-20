#!/usr/bin/env bash
# Revisão de um MP4 em três zooms, mais a faixa de cada transição. Tudo sai ao lado do MP4.
#   revisar.sh faixa <mp4> <início_s> <fim_s>          todos os quadros do trecho numa grade
#                                                     (<nome>-faixa-<início>-<fim>.jpg)
#   revisar.sh recorte <mp4> <t_s> [x y largura altura] um quadro em resolução cheia, sem reduzir
#                                                     (<nome>-recorte-<t>.png); sem caixa, o quadro inteiro
#   revisar.sh transicoes <mp4> <timeline.json>       12 quadros seguidos em volta de cada corte
#                                                     (<nome>-transicoes/NN-<cena>.jpg), em meia resolução
# O zoom geral é a folha de contato que o final.sh já grava (<nome>-folha.jpg).
# Os números entram validados (sem eval); a faixa e o recorte leem o MP4, não a prévia a 50%.
set -euo pipefail

num() { [[ "$2" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "!! $1 precisa ser um número (veio '$2')"; exit 2; }; }
mp4() { [ -f "$1" ] || { echo "!! não achei $1"; exit 2; }; }
fps_de() { # fps do vídeo em decimal (30000/1001 → 29.97)
  ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1:nk=1 "$1" |
    awk -F/ '{ printf "%.6f", ($2 ? $1 / $2 : $1) }'
}

faixa() {
  local MP4="$1" A="$2" B="$3" FPS N COLS W H D NOME
  mp4 "$MP4"; num início "$A"; num fim "$B"
  awk -v a="$A" -v b="$B" 'BEGIN { exit !(b > a) }' || { echo "!! o fim ($B) precisa vir depois do início ($A)"; exit 2; }
  FPS="$(fps_de "$MP4")"
  N="$(awk -v a="$A" -v b="$B" -v f="$FPS" 'BEGIN { n = int((b - a) * f + 0.5); print (n < 1 ? 1 : n) }')"
  [ "$N" -le 240 ] || { echo "!! trecho de $N quadros: a faixa é para até 8 s (240 quadros); divida o trecho"; exit 2; }
  read -r W H <<< "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of default=nw=1:nk=1 "$MP4" | tr '\n' ' ')"
  if [ "$H" -gt "$W" ]; then COLS=10; else COLS=6; fi
  D="$(dirname "$MP4")"; NOME="$(basename "$MP4" .mp4)-faixa-$A-$B.jpg"
  # -ss antes do -i com reencode é exato no quadro; a grade cabe o trecho todo numa imagem
  ffmpeg -loglevel error -y -ss "$A" -i "$MP4" \
    -vf "trim=end_frame=$N,scale=$([ "$H" -gt "$W" ] && echo 216 || echo 384):-2:flags=area,tile=${COLS}x$(( (N + COLS - 1) / COLS )):padding=3:color=gray,scale=out_range=full,format=yuvj420p" \
    -frames:v 1 "$D/$NOME"
  echo "faixa ($N quadros, $A s a $B s): $D/$NOME"
}

recorte() {
  local MP4="$1" T="$2" X="${3:-}" Y="${4:-}" W="${5:-}" H="${6:-}" D NOME VF=""
  mp4 "$MP4"; num tempo "$T"
  if [ -n "$X" ]; then
    for v in X Y W H; do num "$v" "${!v:-}"; done
    VF="crop=$W:$H:$X:$Y"
  fi
  D="$(dirname "$MP4")"; NOME="$(basename "$MP4" .mp4)-recorte-$T.png"
  ffmpeg -loglevel error -y -ss "$T" -i "$MP4" -frames:v 1 ${VF:+-vf "$VF"} "$D/$NOME"
  echo "recorte em resolução cheia: $D/$NOME"
}

transicoes() {
  local MP4="$1" TL="$2" D DIR FPS W H TW COLS LISTA i id cut
  mp4 "$MP4"; [ -f "$TL" ] || { echo "!! não achei $TL"; exit 2; }
  D="$(dirname "$MP4")"; DIR="$D/$(basename "$MP4" .mp4)-transicoes"
  rm -rf "$DIR"; mkdir -p "$DIR"
  FPS="$(fps_de "$MP4")"
  read -r W H <<< "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of default=nw=1:nk=1 "$MP4" | tr '\n' ' ')"
  # meia resolução com flags=area: uma emenda de 1 px vira uma linha de meia intensidade, que aparece
  if [ "$H" -gt "$W" ]; then COLS=6; else COLS=4; fi
  TW=$(( W / 2 ))
  LISTA="$(node -e '
const d = require(process.argv[1]);
d.scenes.slice(1).forEach((s) => { if (s.in !== "cut" || s.d) console.log(`${s.id} ${s.cut}`) });' "$TL")"
  i=0
  while read -r id cut; do
    [ -n "$id" ] || continue
    i=$((i + 1))
    # 12 quadros: do corte − 6 ao corte + 5. O −0,5 quadro no -ss pega o quadro exato do início.
    ffmpeg -loglevel error -y -ss "$(awk -v c="$cut" -v f="$FPS" 'BEGIN { a = c - 6; if (a < 0) a = 0; printf "%.6f", (a - 0.5 < 0 ? 0 : (a - 0.5) / f) }')" \
      -i "$MP4" \
      -vf "trim=end_frame=12,scale=$TW:-2:flags=area,tile=${COLS}x$(( 12 / COLS )):padding=4:color=gray,scale=out_range=full,format=yuvj420p" \
      -frames:v 1 "$DIR/$(printf '%02d' "$i")-$id.jpg"
  done <<< "$LISTA"
  echo "transições ($i, 12 quadros cada, do corte − 6 ao corte + 5): $DIR/"
}

case "${1:-}" in
  faixa) [ "$#" = 4 ] || { echo "uso: revisar.sh faixa <mp4> <início_s> <fim_s>"; exit 2; }; faixa "$2" "$3" "$4" ;;
  recorte) [ "$#" = 3 ] || [ "$#" = 7 ] || { echo "uso: revisar.sh recorte <mp4> <t_s> [x y largura altura]"; exit 2; }; shift; recorte "$@" ;;
  transicoes) [ "$#" = 3 ] || { echo "uso: revisar.sh transicoes <mp4> <timeline.json>"; exit 2; }; transicoes "$2" "$3" ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
