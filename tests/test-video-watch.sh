#!/usr/bin/env bash
# O watch.sh da video-watch extrai frames e diz por que o transcript não veio?
#
# Os casos são os que já enganaram: vídeo estático que o corte de cena não pega (cai
# para intervalo fixo; no ffmpeg 9 é aí que o mjpeg falhava com "Non full-range YUV"),
# vídeo mudo, --no-audio, e modelo whisper ausente, que não pode abortar o script nem
# sumir calado. O whisper nunca roda aqui: o modelo tem 1,5 GB.
#
# Sem ffmpeg, a parte de vídeo sai "pulado" com exit 0 (o job macOS roda todo
# tests/test-*.sh); no job com ffmpeg do CI ela precisa rodar de verdade.
#
# Uso: bash tests/test-video-watch.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SK="$RAIZ/plugin/skills/video-watch"
W="$SK/scripts/watch.sh"
R="$SK/scripts/resolve-url.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
falhas=0
check() { # check <descrição> <0|outro>
  if [ "$2" -eq 0 ]; then printf '  ok    %s\n' "$1"; else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

echo "== scripts e skill =="
[ -x "$W" ]; check "watch.sh existe e é executável" $?
[ -x "$R" ]; check "resolve-url.py existe e é executável" $?
[ -f "$W" ] && { bash -n "$W"; check "watch.sh: bash -n" $?; }
if [ -f "$SK/SKILL.md" ]; then
  grep -q '^disable-model-invocation: true' "$SK/SKILL.md"; check "skill só-slash (disable-model-invocation)" $?
  ! grep -rqE '~/\.claude/skills/' "$SK"; check "nenhum caminho de ~/.claude/skills (no plugin é \${CLAUDE_PLUGIN_ROOT})" $?
else
  check "plugin/skills/video-watch/SKILL.md existe" 1
fi

echo "== resolve-url.py: arquivo e link direto passam sem rede =="
if [ -f "$R" ]; then
  for u in /tmp/gravacao.mp4 file:///tmp/gravacao.mov https://exemplo.invalid/v/arquivo.MP4 https://exemplo.invalid/v/arquivo.webm; do
    out=$(python3 -I "$R" "$u" 2>&1); [ "$out" = "$u" ]; check "passa direto: $u" $?
  done
  python3 -I "$R" >/dev/null 2>&1; [ $? -ne 0 ]; check "sem argumento reprova" $?
fi

echo "== watch.sh sem argumento =="
if [ -f "$W" ]; then
  bash "$W" >/dev/null 2>"$TMP/uso.err"; rc=$?
  [ "$rc" = 1 ] && grep -q '^uso: watch.sh' "$TMP/uso.err"; check "sai 1 com a linha de uso" $?
fi

if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  echo "pulado: ffmpeg/ffprobe ausentes, a parte de vídeo não rodou"
  echo
  if [ "$falhas" -eq 0 ]; then echo "tudo verde (sem a parte de vídeo)"; exit 0; fi
  echo "$falhas falha(s)"; exit 1
fi
[ -f "$W" ] || { echo "$falhas falha(s)"; exit 1; }

echo "== vídeo de verdade (ffmpeg $(ffmpeg -version | head -1 | awk '{print $3}')) =="
# 6 s de tela parada: o corte de cena não acha nada e o script cai para intervalo fixo.
ffmpeg -v error -f lavfi -i "color=c=navy:s=320x240:d=6" -pix_fmt yuv420p "$TMP/mudo.mp4" </dev/null
# a mesma tela com um tom de 440 Hz: tem faixa de áudio.
ffmpeg -v error -f lavfi -i "color=c=navy:s=320x240:d=6" -f lavfi -i "sine=frequency=440:duration=6" \
  -pix_fmt yuv420p -shortest "$TMP/som.mp4" </dev/null

roda() { # roda <saida> <args...> — index.txt em <saida>, stderr em <saida>.err
  local out="$1"; shift
  WHISPER_MODEL="$TMP/nao-existe.bin" bash "$W" "$@" --out "$out" >/dev/null 2>"$out.err"
}

roda "$TMP/a" "$TMP/mudo.mp4"; rc=$?
check "vídeo estático e mudo: sai 0 (veio $rc)" $rc
grep -q '^frames (intervalo de' "$TMP/a/index.txt" 2>/dev/null; check "cai para intervalo fixo" $?
n=$(ls "$TMP/a/frames/"*.jpg 2>/dev/null | wc -l | tr -d ' ')
[ "${n:-0}" -ge 1 ]; check "extraiu frame ($n)" $?
grep -q '^duração: 6s | resolução: 320x240 | áudio: não' "$TMP/a/index.txt" 2>/dev/null; check "índice com duração, resolução e áudio: não" $?
grep -q 'transcript: — (vídeo sem faixa de áudio)' "$TMP/a/index.txt" 2>/dev/null; check "diz que o vídeo não tem áudio" $?

roda "$TMP/b" "$TMP/som.mp4"; rc=$?
check "com áudio e sem modelo: não aborta (veio $rc)" $rc
grep -q '!! modelo whisper ausente' "$TMP/b.err"; check "avisa do modelo ausente no stderr" $?
grep -q 'transcript: — (falhou)' "$TMP/b/index.txt" 2>/dev/null; check "índice fecha com transcript: — (falhou)" $?
n=$(ls "$TMP/b/frames/"*.jpg 2>/dev/null | wc -l | tr -d ' ')
[ "${n:-0}" -ge 1 ]; check "os frames saem mesmo sem transcript ($n)" $?

roda "$TMP/c" "$TMP/som.mp4" --no-audio; rc=$?
check "--no-audio: sai 0" $rc
grep -q 'transcript: — (pulado: --no-audio)' "$TMP/c/index.txt" 2>/dev/null; check "--no-audio pula a transcrição e diz isso" $?
! grep -q 'modelo whisper ausente' "$TMP/c.err"; check "--no-audio nem procura o modelo" $?

roda "$TMP/d" "$TMP/mudo.mp4" --interval 2 --frames 2; rc=$?
n=$(ls "$TMP/d/frames/"*.jpg 2>/dev/null | wc -l | tr -d ' ')
[ "$rc" = 0 ] && [ "$n" = 2 ] && grep -q '^frames (intervalo de 2s)' "$TMP/d/index.txt"
check "--interval 2 --frames 2: 2 frames, intervalo de 2s ($n)" $?

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; exit 0; fi
echo "$falhas falha(s)"; exit 1
