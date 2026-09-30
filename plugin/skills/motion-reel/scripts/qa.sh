#!/usr/bin/env bash
# QA de um projeto motion-reel: tsc, trilha, prévia em meia resolução e folhas de revisão.
# Uso: qa.sh <projeto>
# Saídas em <projeto>/out/: preview.mp4, sheet-N.jpg (2 fps), transitions.jpg (início/meio/fim
# de cada transição), safe.jpg (1 fps com a guia segura do Reel em vermelho).
set -euo pipefail
SK="$(cd "$(dirname "$0")/.." && pwd)"
P="$(cd "${1:?uso: qa.sh <projeto>}" && pwd)"; O="$P/out"; mkdir -p "$O"
TL="$P/src/timeline.json"

echo "→ timeline"
node -e '
const d=require(process.argv[1]); const beat=d.fps*60/((d.music||{}).bpm||120); let bad=0;
d.scenes.forEach(s=>{ if(s.cut%beat){bad++;console.log(`  !! ${s.id}: corte ${s.cut} fora da batida (múltiplo de ${beat})`)} });
if(!bad) console.log(`  cortes na batida (${beat} frames)`);' "$TL"

echo "→ tsc"; (cd "$P" && npx tsc --noEmit -p "$P") && echo "  TSC_OK"
echo "→ trilha"; "$("$SK/scripts/py.sh")" "$P/scripts/track.py"
echo "→ prévia 50%"
(cd "$P" && npx remotion render "$P/src/index.tsx" Reel "$O/preview.mp4" --scale=0.5 --log=error)

rm -f "$O"/sheet-*.jpg "$O"/tr-*.jpg
ffmpeg -loglevel error -y -i "$O/preview.mp4" -vf "fps=2,scale=200:-1,tile=8x4:padding=4:color=gray" "$O/sheet-%d.jpg"
# Guia segura (tokens.json do Reel): esq 90, dir 180, topo 180, base 320 → em 50%.
ffmpeg -loglevel error -y -i "$O/preview.mp4" -vf "fps=1,drawbox=x=45:y=90:w=405:h=710:color=red@0.9:t=2,scale=180:-1,tile=9x4:padding=3:color=gray" -frames:v 1 "$O/safe.jpg"

FR="$(node -e '
const d=require(process.argv[1]); const out=[];
d.scenes.slice(1).forEach(s=>{const h=(s.d||0)/2; if(!h) return; out.push(s.cut-h+2,s.cut-2,s.cut+1,s.cut+h-1)});
console.log(out.join(" "))' "$TL")"
i=0
for fr in $FR; do
  i=$((i+1)); ffmpeg -loglevel error -y -i "$O/preview.mp4" -vf "select=eq(n\,$fr)" -frames:v 1 "$O/tr-$(printf %02d $i).jpg"
done
[ "$i" -gt 0 ] && ffmpeg -loglevel error -y -i "$O/tr-%02d.jpg" -vf "scale=150:-1,tile=8x6:padding=3:color=gray" -frames:v 1 "$O/transitions.jpg"
rm -f "$O"/tr-*.jpg
echo "→ revise: $(ls "$O"/sheet-*.jpg "$O"/transitions.jpg "$O"/safe.jpg | tr '\n' ' ')"
