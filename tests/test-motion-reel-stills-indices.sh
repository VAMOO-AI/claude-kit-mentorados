#!/usr/bin/env bash
# stills.mjs da motion-reel: os índices das cenas aceitam espaço e vírgula.
#
# O SKILL.md sugere `stills.mjs <comp> 0.2,0.8 0.4 <índices>` e quem lê escreve `0,2`
# como as frações; o script só aceitava `0 2` e, com vírgula, não renderizava nada sem
# avisar. Este teste roda o stills.mjs de verdade com o Remotion e o ffmpeg falsos
# (renderStill só anota o quadro), sem bundle nem render:
#
#   1. `0,2`, `0 2` e `0, ,2` renderizam os mesmos quadros;
#   2. índice que não é número ou passa do total de cenas recusa com mensagem clara;
#   3. fração fora de [0, 1] (`0,2` no lugar das frações, querendo índices) recusa e mostra a
#      forma certa, em vez de renderizar a fração 2 sem avisar.
#
# Uso: bash tests/test-motion-reel-stills-indices.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ST="$RAIZ/plugin/skills/motion-reel/assets/template/scripts/stills.mjs"
[ -f "$ST" ] || { echo "stills.mjs não encontrado em $ST"; exit 2; }
command -v node >/dev/null || { echo "node ausente"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/motion-stills.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"; mkdir -p "$P/scripts" "$P/src" "$TMP/bin"
cp "$ST" "$P/scripts/stills.mjs"
# 4 cenas de 100 quadros: com frac 0.5 a cena i cai no quadro i*100+50.
cat > "$P/src/tl-master.json" <<'J'
{"total": 400, "scenes": [{"cut": 0, "len": 100}, {"cut": 100, "len": 100}, {"cut": 200, "len": 100}, {"cut": 300, "len": 100}]}
J
for m in bundler renderer; do
  mkdir -p "$P/node_modules/@remotion/$m"
  printf '{"name":"@remotion/%s","type":"module","main":"index.js"}\n' "$m" > "$P/node_modules/@remotion/$m/package.json"
done
echo 'export async function bundle() { return "serve-url"; }' > "$P/node_modules/@remotion/bundler/index.js"
cat > "$P/node_modules/@remotion/renderer/index.js" <<'J'
import fs from "node:fs";
export async function selectComposition() { return { width: 1920, height: 1080 }; }
export async function renderStill({ output, frame }) {
  fs.appendFileSync(process.env.FRAMES_LOG, `${frame}\n`);
  fs.writeFileSync(output, "");
}
J
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/ffmpeg"; chmod +x "$TMP/bin/ffmpeg"
export PATH="$TMP/bin:$PATH"

roda() { # roda <nome> <args...>: grava quadros em $TMP/<nome>.frames e a saída em $TMP/<nome>.out
  local nome="$1"; shift
  : > "$TMP/$nome.frames"
  FRAMES_LOG="$TMP/$nome.frames" node "$P/scripts/stills.mjs" Master169 0.5 0.4 "$@" > "$TMP/$nome.out" 2>&1
  echo $? > "$TMP/$nome.rc"
}
quadros() { tr '\n' ' ' < "$TMP/$1.frames"; }

roda virgula 0,2
roda espaco 0 2
roda vazios "0, ,2"
roda todos
roda letra 0,x
roda fora 0,9

esperado="50 250 "
[ "$(quadros virgula)" = "$esperado" ] && r=ok || r=fail
check "0,2 renderiza as cenas 0 e 2 (veio: '$(quadros virgula)')" $r
[ "$(quadros espaco)" = "$esperado" ] && r=ok || r=fail
check "0 2 renderiza as cenas 0 e 2 (veio: '$(quadros espaco)')" $r
[ "$(quadros vazios)" = "$esperado" ] && r=ok || r=fail
check "'0, ,2' ignora os vazios (veio: '$(quadros vazios)')" $r
[ "$(quadros todos)" = "50 150 250 350 " ] && r=ok || r=fail
check "sem índices renderiza todas as cenas (veio: '$(quadros todos)')" $r

for caso in letra fora; do
  rc="$(cat "$TMP/$caso.rc")"
  [ "$rc" != 0 ] && [ ! -s "$TMP/$caso.frames" ] && /usr/bin/grep -q 'índice inválido' "$TMP/$caso.out" && r=ok || r=fail
  check "$caso: recusa antes de renderizar, com mensagem (rc=$rc; $(head -c 160 "$TMP/$caso.out" | tr '\n' ' '))" $r
done

: > "$TMP/frac.frames"
FRAMES_LOG="$TMP/frac.frames" node "$P/scripts/stills.mjs" Master169 0,2 > "$TMP/frac.out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ ! -s "$TMP/frac.frames" ] && /usr/bin/grep -q 'fração' "$TMP/frac.out" && /usr/bin/grep -qF '0.2,0.8 0.4 0,2' "$TMP/frac.out" && r=ok || r=fail
check "fração 0,2 recusa antes de renderizar e mostra a forma dos índices (rc=$rc; $(head -c 200 "$TMP/frac.out" | tr '\n' ' '))" $r

[ "$falhas" -eq 0 ] && { echo "OK: stills.mjs aceita índices com espaço e vírgula"; exit 0; }
echo "$falhas falha(s)"; exit 1
