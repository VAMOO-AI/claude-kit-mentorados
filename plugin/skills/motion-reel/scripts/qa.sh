#!/usr/bin/env bash
# QA de um projeto motion-reel: tsc, trilha, prévia em meia resolução e folhas de revisão.
# Uso: qa.sh <projeto> [Reel|Master169|Reel916]   (padrão: Reel)
# Saídas em <projeto>/out/qa-<comp>/: preview.mp4, sheet-N.jpg (2 fps), transitions-N.jpg
# (início/meio/fim de cada transição) e safe.jpg (1 fps com a guia segura em vermelho).
set -euo pipefail
SK="$(cd "$(dirname "$0")/.." && pwd)"
P="$(cd "${1:?uso: qa.sh <projeto> [Reel|Master169|Reel916]}" && pwd)"; COMP="${2:-Reel}"
O="$P/out/qa-$COMP"; mkdir -p "$O"
PY="$("$SK/scripts/py.sh")"

case "$COMP" in
  Reel)
    TL="$P/src/timeline.json"
    echo "→ timeline"
    node -e '
const d=require(process.argv[1]); const beat=d.fps*60/((d.music||{}).bpm||120); let bad=0;
d.scenes.forEach(s=>{ if(s.cut%beat){bad++;console.log(`  !! ${s.id}: corte ${s.cut} fora da batida (múltiplo de ${beat})`)} });
if(!bad) console.log(`  cortes na batida (${beat} frames)`);' "$TL"
    echo "→ trilha"; "$PY" "$P/scripts/track.py"
    # Guia do Reel (botões do Instagram): esq 90, dir 180, topo 180, base 320 → em 50%.
    SAFE="drawbox=x=45:y=90:w=405:h=710:color=red@0.9:t=2,scale=180:-1,tile=9x4:padding=3:color=gray" ;;
  Master169|Reel916)
    NAME="$([ "$COMP" = Master169 ] && echo master || echo reel)"; TL="$P/src/tl-$NAME.json"
    echo "→ timeline (film.json + vo)"; "$PY" "$P/scripts/build-timeline.py" "$NAME"
    echo "→ trilha"; "$PY" "$P/scripts/track_cinema.py" "$NAME"
    # A guia do useL() (film-scenes.tsx), em 50%. 16:9: 120/120/96/96 · 9:16: 90/180/200/340
    # (20 px dentro da guia do Instagram em cima e embaixo).
    if [ "$COMP" = Master169 ]; then
      SAFE="drawbox=x=60:y=48:w=840:h=444:color=red@0.9:t=2,scale=240:-1,tile=6x6:padding=3:color=gray"
    else
      SAFE="drawbox=x=45:y=100:w=405:h=690:color=red@0.9:t=2,scale=180:-1,tile=9x4:padding=3:color=gray"
    fi ;;
  *) echo "!! composição desconhecida: $COMP (Reel, Master169 ou Reel916)"; exit 1 ;;
esac

echo "→ tsc"; (cd "$P" && npx tsc --noEmit -p "$P") && echo "  TSC_OK"
echo "→ prévia 50%"
(cd "$P" && npx remotion render "$P/src/index.tsx" "$COMP" "$O/preview.mp4" --scale=0.5 --log=error)

rm -f "$O"/sheet-*.jpg "$O"/tr-*.jpg "$O"/transitions-*.jpg
TILE="$([ "$COMP" = Master169 ] && echo "scale=320:-1,tile=5x6" || echo "scale=200:-1,tile=8x4")"
ffmpeg -loglevel error -y -i "$O/preview.mp4" -vf "fps=2,$TILE:padding=4:color=gray" "$O/sheet-%d.jpg"
ffmpeg -loglevel error -y -i "$O/preview.mp4" -vf "fps=1,$SAFE" -frames:v 1 "$O/safe.jpg"

# Quadros de cada transição (início, meio-1, meio+1, fim), extraídos em lotes de 24: um
# select com centenas de eq() estoura o tamanho de expressão do ffmpeg.
FR="$(node -e '
const d=require(process.argv[1]); const out=[];
d.scenes.slice(1).forEach(s=>{const h=(s.d||0)/2; if(!h) return; out.push(s.cut-h+2,s.cut-2,s.cut+1,s.cut+h-1)});
console.log(out.join(" "))' "$TL")"
set -- $FR
i=0
while [ "$#" -gt 0 ]; do
  sel=""; k=0
  while [ "$#" -gt 0 ] && [ "$k" -lt 24 ]; do sel="${sel:+$sel+}eq(n\\,$1)"; shift; k=$((k+1)); done
  # format=yuvj420p: lote sem frame nenhum faz o mjpeg do ffmpeg 9 abrir no EOF com range tv e
  # falhar ("Non full-range YUV"), o que derruba a QA pelo set -e
  ffmpeg -loglevel error -y -i "$O/preview.mp4" -vf "select=$sel,scale=out_range=full,format=yuvj420p" -fps_mode vfr -start_number "$i" "$O/tr-%03d.jpg"
  i=$((i+k))
done
# conta o que saiu, não o que foi pedido: lote fora da duração do vídeo não gera arquivo
ls "$O"/tr-*.jpg >/dev/null 2>&1 && ffmpeg -loglevel error -y -i "$O/tr-%03d.jpg" -vf "scale=150:-1,tile=8x6:padding=3:color=gray" "$O/transitions-%d.jpg"
rm -f "$O"/tr-*.jpg
echo "→ revise: $(ls "$O"/sheet-*.jpg "$O"/transitions-*.jpg "$O"/safe.jpg 2>/dev/null | tr '\n' ' ')"
[ "$COMP" != Reel ] && echo "  quadro por cena sem render inteiro: (cd $P && node scripts/stills.mjs $COMP 0.2,0.8)"
exit 0
