#!/usr/bin/env bash
# A fonte principal que falha derruba o render da motion-reel, com mensagem; a serifada não.
#
# Até a 0.56 o useFont do lib.tsx fazia console.error e seguia: sem o PlusJakartaSans.ttf em
# public/, o filme inteiro saía em system-ui e ninguém via. Render real com o Remotion:
#   1. com as duas fontes, o still sai;
#   2. sem a fonte principal, o render falha e cita o arquivo;
#   3. sem a serifada, o still sai (cai no Georgia).
#
# Precisa de um projeto já instalado (o new.sh roda o npm ci): o teste copia o projeto sem o
# node_modules, liga o node_modules dele e põe o src/lib.tsx da skill em teste.
# Uso: MOTION_RENDER_REAL=1 MOTION_PROJETO=<projeto com node_modules> bash tests/test-motion-reel-fonte.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
LIB="$RAIZ/skills/motion-reel/assets/template/src/lib.tsx"
[ -f "$LIB" ] || LIB="$RAIZ/plugin/skills/motion-reel/assets/template/src/lib.tsx"
[ -f "$LIB" ] || { echo "lib.tsx não encontrado em $RAIZ"; exit 2; }
[ "${MOTION_RENDER_REAL:-}" = 1 ] || { echo "pulado: render real só com MOTION_RENDER_REAL=1"; exit 0; }
PROJ="${MOTION_PROJETO:?MOTION_PROJETO=<projeto criado pelo new.sh>}"
[ -d "$PROJ/node_modules/remotion" ] || { echo "$PROJ sem node_modules: rode o new.sh"; exit 2; }

falhas=0
check() { if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"; else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/motion-fonte.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

copia() { # copia <pasta>: projeto sem node_modules, com o lib.tsx em teste
  mkdir -p "$1"
  (cd "$PROJ" && tar --exclude=./node_modules --exclude=./out -cf - .) | (cd "$1" && tar -xf -)
  ln -s "$PROJ/node_modules" "$1/node_modules"
  cp "$LIB" "$1/src/lib.tsx"
}
still() { # still <pasta> <log>
  (cd "$1" && npx remotion still src/index.tsx Master169 "$1/out/q.png" --frame=20 --scale=0.25 --log=error) > "$2" 2>&1
}

echo "1. com as duas fontes"
copia "$TMP/ok"; still "$TMP/ok" "$TMP/1.log"; rc=$?
check "o still sai (exit $rc)" "$([ "$rc" = 0 ] && [ -s "$TMP/ok/out/q.png" ] && echo ok || echo fail)"
[ "$rc" = 0 ] || tail -5 "$TMP/1.log" | sed 's/^/        /'

echo "2. sem a fonte principal"
copia "$TMP/sem"; rm -f "$TMP/sem/public/PlusJakartaSans.ttf"; still "$TMP/sem" "$TMP/2.log"; rc=$?
check "o render falha (exit $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
check "a mensagem cita o arquivo que falta" "$(/usr/bin/grep -q 'fonte principal não carregou: public/PlusJakartaSans.ttf' "$TMP/2.log" && echo ok || echo fail)"

echo "3. sem a serifada"
copia "$TMP/serif"; rm -f "$TMP/serif/public/serif-italic.ttf"; still "$TMP/serif" "$TMP/3.log"; rc=$?
check "o still sai mesmo assim (exit $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
