#!/usr/bin/env bash
# O final.sh da motion-reel reprova o MP4 entregue quando o áudio sai fora do alvo.
#
# Até a 0.48.0 o final.sh normalizava para −14 LUFS e só imprimia o resultado: um
# integrado de −20 ou um pico acima de −1 dBTP saía como "entrega" sem ninguém ver.
# A folha de contato também só existia para a prévia a 50% do qa.sh, nunca para o MP4
# final.
#
# Este teste gera MP4s sintéticos (tom de 1 kHz em volume conhecido, AAC 48 kHz como o
# final) e roda só a etapa de verificação (`final.sh --verificar <mp4>`), sem Remotion:
#   1. −14 LUFS passa, e saem a folha e o loudness por segundo;
#   2. −20 LUFS reprova, citando o integrado;
#   3. integrado no alvo com um estalo acima de −1 dBTP reprova, citando o pico;
#   4. o mesmo mix do caso 3 passa depois do `final.sh --encodar` (limiter de pico verdadeiro);
#      com legenda, o MP4 sai com a faixa mov_text em português;
#   5. cena parada de 2,5 s e quadro preto de 0,8 s viram aviso com o trecho, sem reprovar;
#   6. staging: render que falha não toca no MP4 bom; reprovado vira <nome>-reprovado.mp4 e o
#      bom fica; aprovado entra no lugar e sai a faixa de 12 quadros de cada transição, em que uma
#      emenda de 1 px aparece. O Remotion, o tsc e a trilha são falsos (npx e python falsos no PATH);
#   7. revisar.sh: faixa com todos os quadros do trecho, recorte em resolução cheia e número inválido
#      recusado (sem eval).
#
# Uso: bash tests/test-motion-reel-final-verificar.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
FINAL="$RAIZ/plugin/skills/motion-reel/scripts/final.sh"
[ -f "$FINAL" ] || { echo "final.sh não encontrado em $FINAL"; exit 2; }
command -v ffmpeg >/dev/null 2>&1 || { echo "pulado: sem ffmpeg no PATH"; exit 0; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/out"
# fixture <nome> <expressão do aevalsrc> [filtro de vídeo]: 4 s de vídeo 9:16 em movimento + áudio estéreo
fixture() {
  ffmpeg -loglevel error -y -f lavfi -i "testsrc2=s=540x960:r=30:d=4" \
    -f lavfi -i "aevalsrc=$2|$2:s=48000:d=4" ${3:+-vf "$3"} -c:v libx264 -pix_fmt yuv420p \
    -c:a aac -b:a 320k -ar 48000 -shortest "$TMP/out/$1.mp4"
}
# 0.2 de amplitude em 1 kHz mede −14 LUFS; 0.1 mede −20; o estalo de 20 ms soma 0.75 (pico ~−0.4 dBTP)
fixture alvo  '0.2*sin(2*PI*1000*t)'
fixture baixo '0.1*sin(2*PI*1000*t)'
fixture pico  '0.2*sin(2*PI*1000*t)+0.75*between(t\,2\,2.02)*sin(2*PI*1000*t)'

roda() { # roda <nome> → grava saída em $TMP/<nome>.log e devolve o exit
  bash "$FINAL" --verificar "$TMP/out/$1.mp4" > "$TMP/$1.log" 2>&1
}

roda alvo; rc=$?
check "−14 LUFS passa (exit $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "folha de contato do final existe e não está vazia" "$([ -s "$TMP/out/alvo-folha.jpg" ] && echo ok || echo fail)"
check "loudness por segundo existe" "$([ -s "$TMP/out/alvo-loudness.txt" ] && echo ok || echo fail)"
check "loudness lista os segundos mais altos e mais baixos" \
  "$(/usr/bin/grep -q 'mais altos' "$TMP/out/alvo-loudness.txt" 2>/dev/null && /usr/bin/grep -q 'mais baixos' "$TMP/out/alvo-loudness.txt" && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/alvo.log"

roda baixo; rc=$?
check "−20 LUFS reprova com exit 1 (veio $rc)" "$([ "$rc" = 1 ] && echo ok || echo fail)"
check "a reprovação de −20 cita o integrado" "$(/usr/bin/grep -q 'REPROVADO.*integrado' "$TMP/baixo.log" && echo ok || echo fail)"
[ "$rc" = 1 ] || sed 's/^/        /' "$TMP/baixo.log"

roda pico; rc=$?
check "pico acima de −1 dBTP reprova com exit 1 (veio $rc)" "$([ "$rc" = 1 ] && echo ok || echo fail)"
check "a reprovação do pico cita o pico" "$(/usr/bin/grep -q 'REPROVADO.*pico' "$TMP/pico.log" && echo ok || echo fail)"
check "o caso do pico não reprova pelo integrado" "$(/usr/bin/grep -q 'REPROVADO.*integrado' "$TMP/pico.log" && echo fail || echo ok)"
[ "$rc" = 1 ] || sed 's/^/        /' "$TMP/pico.log"

check "áudio no alvo e vídeo em movimento não dão aviso de vídeo" "$(/usr/bin/grep -q 'ATENÇÃO' "$TMP/alvo.log" && echo fail || echo ok)"

echo "4. limiter de pico verdadeiro e legenda embutida"
printf '1\n00:00:00,500 --> 00:00:01,800\nSegunda, nove da manhã.\n' > "$TMP/fala.srt"
bash "$FINAL" --encodar "$TMP/out/pico.mp4" "$TMP/out/pico-final.mp4" "$TMP/fala.srt" > "$TMP/enc.log" 2>&1; rc=$?
check "--encodar sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/enc.log"
roda pico-final; rc=$?
check "o mix que reprovava pelo pico passa depois do encode (exit $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/pico-final.log"
sub="$(ffprobe -v error -select_streams s -show_entries stream=codec_name:stream_tags=language -of csv=p=0 "$TMP/out/pico-final.mp4" 2>/dev/null)"
check "a legenda vai como faixa mov_text em português (veio '$sub')" "$([ "$sub" = "mov_text,por" ] && echo ok || echo fail)"

echo "5. cena parada e quadro preto"
fixture parado '0.2*sin(2*PI*1000*t)' "trim=end=1.5,tpad=stop_mode=clone:stop_duration=2.5"
fixture preto '0.2*sin(2*PI*1000*t)' "drawbox=c=black:t=fill:enable='between(t,1.5,2.3)'"
roda parado; rc=$?
check "cena parada não reprova (exit $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "cena parada vira aviso com o trecho" "$(/usr/bin/grep -q 'ATENÇÃO: cena parada de 1.5 s' "$TMP/parado.log" && echo ok || echo fail)"
[ "$rc" = 0 ] && /usr/bin/grep -q 'cena parada de 1.5' "$TMP/parado.log" || sed 's/^/        /' "$TMP/parado.log"
roda preto; rc=$?
check "quadro preto não reprova (exit $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "quadro preto vira aviso com o trecho" "$(/usr/bin/grep -q 'ATENÇÃO: quadro preto de 1.5 s' "$TMP/preto.log" && echo ok || echo fail)"
[ "$rc" = 0 ] && /usr/bin/grep -q 'preto de 1.5' "$TMP/preto.log" || sed 's/^/        /' "$TMP/preto.log"

echo "6. staging, reprovado ao lado do bom e faixa das transições"
P="$TMP/projeto com espaço"; mkdir -p "$P/scripts" "$P/src" "$TMP/bin"
printf 'pass\n' > "$P/scripts/track.py"
printf '{"fps": 30, "scenes": [{"id": "a", "cut": 0, "in": "cut", "d": 0}, {"id": "b", "cut": 30, "in": "glitch", "d": 10}]}\n' > "$P/src/timeline.json"
# 16:9 navy, com uma emenda de 1 px branca em x=960 nos quadros 28 a 33 (em volta do corte 30)
ffmpeg -loglevel error -y -f lavfi -i "color=c=navy:s=1920x1080:r=30:d=2" -f lavfi -i "aevalsrc=0.2*sin(2*PI*1000*t)|0.2*sin(2*PI*1000*t):s=48000:d=2" \
  -vf "drawbox=x=960:y=0:w=1:h=1080:c=white:t=fill:enable='between(n,28,33)'" -c:v libx264 -pix_fmt yuvj420p -crf 10 -c:a aac -b:a 320k -shortest "$TMP/raw-bom.mp4"
# cliques de 5 ms: o loudnorm não chega em −14 sem passar do pico, e o limiter segura o pico;
# o integrado sai baixo mesmo depois do encode (reprova)
CLIQUE='if(lt(mod(t\,0.5)\,0.005)\,0.9*sin(2*PI*1000*t)\,0)'
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=s=540x960:r=30:d=4" -f lavfi -i "aevalsrc=$CLIQUE|$CLIQUE:s=48000:d=4" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 320k -shortest "$TMP/raw-ruim.mp4"
cat > "$TMP/bin/npx" <<'SH'
#!/usr/bin/env bash
[ "$1" = tsc ] && exit 0
[ -n "${RENDER_FALHA:-}" ] && { echo "render falso falhou" >&2; exit 1; }
cp "$RAW_FIXTURE" "$5"
SH
cat > "$TMP/bin/python-falso" <<'SH'
#!/usr/bin/env bash
[ "$1" = -c ] && [ "$2" = "import numpy" ] && exit 0
exec python3 "$@"
SH
chmod +x "$TMP/bin/npx" "$TMP/bin/python-falso"
final() { PATH="$TMP/bin:$PATH" MOTION_PY="$TMP/bin/python-falso" bash "$FINAL" "$P" filme Reel > "$TMP/$1.log" 2>&1; }
RAW_FIXTURE="$TMP/raw-bom.mp4" final f1; rc=$?
check "1º final aprovado sai 0 (veio $rc)" "$([ "$rc" = 0 ] && [ -f "$P/out/filme.mp4" ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/f1.log"
check "não sobra a pasta de staging" "$(ls -d "$P/out/.staging-"* >/dev/null 2>&1 && echo fail || echo ok)"
H1="$(cksum < "$P/out/filme.mp4")"
RENDER_FALHA=1 final f2; rc=$?
check "render que falha sai com erro (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
check "render que falha não toca no MP4 bom" "$([ "$(cksum < "$P/out/filme.mp4")" = "$H1" ] && echo ok || echo fail)"
RAW_FIXTURE="$TMP/raw-ruim.mp4" final f3; rc=$?
check "mix reprovado sai 1 (veio $rc)" "$([ "$rc" = 1 ] && echo ok || echo fail)"
check "o reprovado fica em filme-reprovado.mp4" "$([ -f "$P/out/filme-reprovado.mp4" ] && echo ok || echo fail)"
check "o MP4 bom continua intacto" "$([ "$(cksum < "$P/out/filme.mp4")" = "$H1" ] && echo ok || echo fail)"
RAW_FIXTURE="$TMP/raw-bom.mp4" final f4; rc=$?
check "aprovado de novo limpa o reprovado" "$([ "$rc" = 0 ] && [ ! -f "$P/out/filme-reprovado.mp4" ] && echo ok || echo fail)"
STRIP="$P/out/filme-transicoes/01-b.jpg"
check "faixa da transição existe" "$([ -s "$STRIP" ] && echo ok || echo fail)"
ymax() { ffmpeg -hide_banner -i "$STRIP" -vf "crop=$1,signalstats,metadata=print:key=lavfi.signalstats.YMAX" -f null - 2>&1 | /usr/bin/grep -o 'YMAX=[0-9]*' | head -1 | cut -d= -f2; }
# grade 4×3 de quadros 960×540 com 4 px entre eles: o 5º quadro (n=28) é a 1ª coluna da 2ª linha
LIMPO="$(ymax 940:520:10:10)"; EMENDA="$(ymax 940:520:10:554)"
check "a emenda de 1 px aparece na faixa (luma máx. $EMENDA com emenda, $LIMPO sem)" \
  "$([ -n "$EMENDA" ] && [ -n "$LIMPO" ] && [ "$EMENDA" -gt $((LIMPO + 40)) ] && echo ok || echo fail)"

echo "7. revisar.sh: faixa e recorte"
REV="$(dirname "$FINAL")/revisar.sh"
bash "$REV" faixa "$TMP/out/alvo.mp4" 0.5 1.5 > "$TMP/r1.log" 2>&1; rc=$?
check "faixa sai 0 e conta 30 quadros (exit $rc)" "$([ "$rc" = 0 ] && /usr/bin/grep -q '30 quadros' "$TMP/r1.log" && [ -s "$TMP/out/alvo-faixa-0.5-1.5.jpg" ] && echo ok || echo fail)"
bash "$REV" recorte "$TMP/out/alvo.mp4" 1 10 20 100 50 > "$TMP/r2.log" 2>&1; rc=$?
dim="$(ffprobe -v error -show_entries stream=width,height -of csv=p=0 "$TMP/out/alvo-recorte-1.png" 2>/dev/null)"
check "recorte em resolução cheia, do tamanho pedido (veio '$dim')" "$([ "$rc" = 0 ] && [ "$dim" = "100,50" ] && echo ok || echo fail)"
bash "$REV" recorte "$TMP/out/alvo.mp4" '1;touch x' > "$TMP/r3.log" 2>&1; rc=$?
check "tempo que não é número recusa (exit $rc)" "$([ "$rc" = 2 ] && /usr/bin/grep -q 'precisa ser um número' "$TMP/r3.log" && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
