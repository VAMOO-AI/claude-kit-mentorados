#!/usr/bin/env bash
# Galeria da motion-reel: o galeria.py mostra tudo o que o template já tem (cada cena do SCENES
# do film-scenes.tsx, cada transição do D do build-timeline.py e cada cena do Reel) com a marca
# do projeto, para escolher antes de roteirizar, sem estragar o roteiro da pessoa.
#
# O render do Remotion não roda aqui: `node` é falso no PATH, lê o job e grava um PNG por item.
#   1. --lista (sem projeto) cita toda cena, toda transição e toda cena do Reel;
#   2. a galeria tem um quadro de cada uma, a página cita todos e escapa o nome da marca;
#      film.json, vo.json e tl-reel.json saem byte a byte iguais; nada de script ou job sobra;
#   3. render que falha sai com erro e mesmo assim devolve o tl-reel.json;
#   4. pasta sem projeto recusa.
#
# Uso: bash tests/test-motion-reel-galeria.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SK="$RAIZ/plugin/skills/motion-reel"
GAL="$SK/scripts/galeria.py"
[ -f "$GAL" ] || { echo "galeria.py não encontrado em $GAL"; exit 2; }
PY="$(command -v python3)" || { echo "python3 ausente"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
tem() { /usr/bin/grep -qF -- "$2" "$1" 2>/dev/null && echo ok || echo fail; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/motion-galeria.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
export NODE_LOG="$TMP/node.log"; : > "$NODE_LOG"
cat > "$BIN/node" <<'SH'
#!/usr/bin/env bash
echo "node $*" >> "$NODE_LOG"
[ -n "${FALHA:-}" ] && exit 1
python3 -c 'import json, pathlib, sys
job = json.load(open(sys.argv[1], encoding="utf-8"))
for it in job["itens"]:
    pathlib.Path(job["saida"], it["nome"] + ".png").write_bytes(b"\x89PNG")' "$2"
SH
chmod +x "$BIN/node"

# O que o template tem, lido aqui sem o galeria.py: o teste não confia na mesma regex.
A="$SK/assets/template"
CENAS="$("$PY" - "$A/src/film-scenes.tsx" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
bloco = t[t.index("export const SCENES"):]
bloco = bloco[bloco.index("{") + 1:bloco.index("};")]
print(" ".join(k for k, _ in re.findall(r"(\w+)\s*:\s*(\w+)", bloco)))
PY
)"
TRANS="$("$PY" - "$A/scripts/build-timeline.py" <<'PY'
import ast, sys
for linha in open(sys.argv[1], encoding="utf-8"):
    if linha.startswith("D = "):
        print(" ".join(k for k in ast.literal_eval(linha[4:]) if k != "cut"))
PY
)"
REEL="$("$PY" -c 'import json, sys; print(" ".join(s["id"] for s in json.load(open(sys.argv[1]))["scenes"]))' "$A/src/timeline.json")"
[ -n "$CENAS" ] && [ -n "$TRANS" ] && [ -n "$REEL" ] || { echo "não li cenas/transições do template"; exit 2; }

echo "1. --lista sem projeto"
"$PY" "$GAL" --lista > "$TMP/lista.log" 2>&1; rc=$?
check "sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
for c in $CENAS $TRANS $REEL; do check "lista cita $c" "$(tem "$TMP/lista.log" "$c")"; done

echo "2. galeria de um projeto"
P="$TMP/pasta com espaço ção/motion"; mkdir -p "$P/src" "$P/scripts"
cp "$A/film.json" "$A/vo.json" "$P/"
cp "$A/src/film-scenes.tsx" "$A/src/index.tsx" "$A/src/timeline.json" "$A/src/tl-reel.json" "$P/src/"
cp "$A/scripts/build-timeline.py" "$P/scripts/"
sed 's/export const BRAND = "Sua Marca"/export const BRAND = "Ateliê <Ana>"/' "$A/src/lib.tsx" > "$P/src/lib.tsx"
hashes() { (cd "$P" && "$PY" -c 'import hashlib, sys
for f in sys.argv[1:]: print(f, hashlib.sha256(open(f, "rb").read()).hexdigest())' film.json vo.json src/tl-reel.json); }
ANTES="$(hashes)"
PATH="$BIN:$PATH" "$PY" "$GAL" "$P" > "$TMP/gal.log" 2>&1; rc=$?
check "sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/gal.log"
G="$P/out/galeria"
for c in $CENAS; do
  check "quadro e card da cena $c" "$([ -f "$G/cena-$c.png" ] && /usr/bin/grep -qF "src=\"cena-$c.png\"" "$G/index.html" && echo ok || echo fail)"
done
for t in $TRANS; do
  check "quadro e card da transição $t" "$([ -f "$G/transicao-$t.png" ] && /usr/bin/grep -qF "src=\"transicao-$t.png\"" "$G/index.html" && echo ok || echo fail)"
done
for r in $REEL; do
  check "quadro e card do Reel $r" "$([ -f "$G/reel-$r.png" ] && /usr/bin/grep -qF "src=\"reel-$r.png\"" "$G/index.html" && echo ok || echo fail)"
done
check "a página escapa o nome da marca" "$(tem "$G/index.html" 'Ateliê &lt;Ana&gt;')"
check "um render só (um bundle)" "$([ "$(/usr/bin/grep -c '^node' "$NODE_LOG")" = 1 ] && echo ok || echo fail)"
check "film.json, vo.json e tl-reel.json iguais" "$([ "$(hashes)" = "$ANTES" ] && echo ok || echo fail)"
check "script e job de render não sobram" "$(ls "$P/out/"galeria-* >/dev/null 2>&1 && echo fail || echo ok)"

echo "3. render que falha devolve o roteiro"
FALHA=1 PATH="$BIN:$PATH" "$PY" "$GAL" "$P" > "$TMP/falha.log" 2>&1; rc=$?
check "sai com erro (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
check "diz que a galeria não renderizou" "$(tem "$TMP/falha.log" 'não renderizou')"
check "film.json, vo.json e tl-reel.json iguais" "$([ "$(hashes)" = "$ANTES" ] && echo ok || echo fail)"
check "script e job de render não sobram" "$(ls "$P/out/"galeria-* >/dev/null 2>&1 && echo fail || echo ok)"

echo "4. pasta sem projeto"
mkdir -p "$TMP/vazia"
PATH="$BIN:$PATH" "$PY" "$GAL" "$TMP/vazia" > "$TMP/vazia.log" 2>&1; rc=$?
check "recusa (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
check "aponta o new.sh" "$(tem "$TMP/vazia.log" 'new.sh')"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
