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
#   3. integrado no alvo com um estalo acima de −1 dBTP reprova, citando o pico.
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
# fixture <nome> <expressão do aevalsrc>: 4 s de vídeo 9:16 + áudio estéreo
fixture() {
  ffmpeg -loglevel error -y -f lavfi -i "color=c=navy:s=540x960:r=30:d=4" \
    -f lavfi -i "aevalsrc=$2|$2:s=48000:d=4" -c:v libx264 -pix_fmt yuv420p \
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

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
