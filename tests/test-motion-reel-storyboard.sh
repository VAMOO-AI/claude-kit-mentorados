#!/usr/bin/env bash
# Storyboard da motion-reel: um quadro por cena do film.json, para aprovar antes de
# construir, de voz paga e do render final. Fora do estúdio não há central: a saída é
# out/storyboard/index.html e out/storyboard/storyboard.md.
#
# O Remotion não roda aqui. `--sem-stills` prova a página e a tabela com um film.json
# mínimo. Sem a flag, `node` é falso no PATH (grava um PNG por índice) e o python que
# o py.sh escolhe é falso (registra PYTHONUTF8 e segue no python3 de verdade).
#
# Uso: bash tests/test-motion-reel-storyboard.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SK="$RAIZ/plugin/skills/motion-reel"
SB="$SK/scripts/storyboard.py"
[ -f "$SB" ] || { echo "storyboard.py não encontrado em $SB"; exit 2; }
PY="$(command -v python3)" || { echo "python3 ausente"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
tem() { /usr/bin/grep -qF -- "$2" "$1" 2>/dev/null && echo ok || echo fail; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/motion-storyboard.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
export NODE_LOG="$TMP/node.log" PY_LOG="$TMP/py.log" PY_REAL="$PY"
: > "$NODE_LOG"; : > "$PY_LOG"

cat > "$BIN/node" <<'SH'
#!/usr/bin/env bash
echo "node $*" >> "$NODE_LOG"
[ -n "${FALHA:-}" ] && exit 1
comp="$2"
mkdir -p "out/stills-$comp"
i=0
shift 4
for idx in "$@"; do
  printf 'STILL:%s' "$idx" > "out/stills-$comp/$(printf '%03d' "$i").png"
  i=$((i + 1))
done
[ -n "${FOLHA:-}" ] && exit 1
exit 0
SH
cat > "$BIN/python-motion" <<'PY'
#!/usr/bin/env python3
import os, sys
if len(sys.argv) >= 3 and sys.argv[1] == "-c" and "numpy" in sys.argv[2]:
    sys.exit(0)
with open(os.environ["PY_LOG"], "a", encoding="utf-8") as log:
    log.write("PYTHONUTF8=" + os.environ.get("PYTHONUTF8", "") + "\n")
    log.write(" ".join(sys.argv) + "\n")
os.execv(os.environ["PY_REAL"], [os.environ["PY_REAL"], *sys.argv[1:]])
PY
chmod +x "$BIN/node" "$BIN/python-motion"

filme() { # filme <pasta>
  mkdir -p "$1"
  cat > "$1/film.json" <<'JSON'
{
  "master": [
    {"type": "title", "vo": ["a1"], "props": {"line1": "Olá <mundo>", "line2": "Na | tela"}},
    {"type": "outro", "vo": [], "min": 90, "props": {"name": "Até logo"}}
  ],
  "reel": [
    {"type": "title", "vo": ["a1"], "props": {"line1": "Olá <mundo>", "line2": "Na | tela"}}
  ]
}
JSON
  cat > "$1/vo.json" <<'JSON'
{"lines": [{"id": "a1", "text": "Uma fala com ação."}]}
JSON
}

echo "1. pasta sem film.json"
mkdir -p "$TMP/vazia"
PATH="$BIN:$PATH" "$PY" "$SB" "$TMP/vazia" > "$TMP/vazia.log" 2>&1; rc=$?
check "recusa (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
check "aponta o new.sh" "$(tem "$TMP/vazia.log" 'new.sh')"

echo "2. --sem-stills: página e tabela, sem node e sem voz"
P="$TMP/pasta com espaço ção/motion"
filme "$P"
hashes() { "$PY" -c 'import hashlib, sys
for f in sys.argv[1:]: print(hashlib.sha256(open(f, "rb").read()).hexdigest())' "$P/film.json" "$P/vo.json"; }
ANTES="$(hashes)"
: > "$NODE_LOG"; : > "$PY_LOG"
PATH="$BIN:$PATH" MOTION_PY="$BIN/python-motion" "$PY" "$SB" "$P" --sem-stills > "$TMP/sem.log" 2>&1; rc=$?
check "sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/sem.log"
S="$P/out/storyboard"
check "index.html e storyboard.md" "$([ -f "$S/index.html" ] && [ -f "$S/storyboard.md" ] && echo ok || echo fail)"
check "miniatura da cena 01" "$([ -f "$S/cena-01.png" ] && echo ok || echo fail)"
check "html: número, tipo e miniatura" "$(tem "$S/index.html" 'cena-01.png')"
check "html: tipo title" "$(tem "$S/index.html" 'title')"
check "html escapa o texto na tela" "$(tem "$S/index.html" 'Olá &lt;mundo&gt;')"
check "html não deixa <mundo> cru" "$(/usr/bin/grep -qF '<mundo>' "$S/index.html" && echo fail || echo ok)"
check "html traz a fala" "$(tem "$S/index.html" 'Uma fala com ação.')"
check "html traz a duração estimada" "$(tem "$S/index.html" '2,0 s')"
check "o reel não inclui a cena outro" "$(/usr/bin/grep -qF 'Até logo' "$S/index.html" && echo fail || echo ok)"
check "tabela com cabeçalho" "$(tem "$S/storyboard.md" '| Cena | Tipo | Duração estimada | Texto na tela | Fala | Ajuste |')"
check "tabela escapa o pipe do texto" "$(tem "$S/storyboard.md" 'Na \| tela')"
check "tabela traz a fala" "$(tem "$S/storyboard.md" 'Uma fala com ação.')"
check "film.json e vo.json iguais" "$([ "$(hashes)" = "$ANTES" ] && echo ok || echo fail)"
check "não chamou o node" "$([ ! -s "$NODE_LOG" ] && echo ok || echo fail)"
check "não gerou voz" "$([ ! -d "$P/public/vo" ] && ! /usr/bin/grep -qE 'eleven|voz\.py' "$TMP/sem.log" && echo ok || echo fail)"
check "diz que não gera voz" "$(tem "$TMP/sem.log" 'sem voz')"

echo "3. --composicao Master169 no mesmo roteiro"
PATH="$BIN:$PATH" "$PY" "$SB" "$P" --sem-stills --composicao Master169 > "$TMP/master.log" 2>&1; rc=$?
check "sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/master.log"
check "cena 02 outro" "$(tem "$S/storyboard.md" '| 02 | outro | 3,0 s |')"
check "texto da cena 02" "$(tem "$S/index.html" 'Até logo')"
check "miniatura da cena 02" "$([ -f "$S/cena-02.png" ] && echo ok || echo fail)"
check "duração da primeira cena continua 2,0 s" "$(tem "$S/storyboard.md" '| 01 | title | 2,0 s |')"

echo "4. composição inválida e formato vazio"
PATH="$BIN:$PATH" "$PY" "$SB" "$P" --composicao Foo > "$TMP/foo.log" 2>&1; rc=$?
check "composição Foo recusa (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
mkdir -p "$TMP/so-master"
printf '%s\n' '{"master": [{"type": "title", "props": {"line1": "Só 16:9"}}]}' > "$TMP/so-master/film.json"
PATH="$BIN:$PATH" "$PY" "$SB" "$TMP/so-master" --sem-stills > "$TMP/so-master.log" 2>&1; rc=$?
check "Reel sem cenas no film.json recusa (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"

echo "5. utf-8 com stdout em cp1252"
PYTHONIOENCODING=cp1252 PATH="$BIN:$PATH" "$PY" "$SB" "$P" --sem-stills > "$TMP/cp.log" 2>&1; rc=$?
check "sai 0 sem UnicodeEncodeError (veio $rc)" "$([ "$rc" = 0 ] && ! /usr/bin/grep -q 'UnicodeEncodeError' "$TMP/cp.log" && echo ok || echo fail)"

echo "6. stills do projeto, pelo py.sh, sem gastar voz"
R="$TMP/render/motion"
filme "$R"
mkdir -p "$R/scripts" "$R/src"
cp "$SK/assets/template/scripts/build-timeline.py" "$R/scripts/"
cp "$SK/assets/template/scripts/stills.mjs" "$R/scripts/"
: > "$NODE_LOG"; : > "$PY_LOG"
PATH="$BIN:$PATH" MOTION_PY="$BIN/python-motion" "$PY" "$SB" "$R" --composicao Reel > "$TMP/render.log" 2>&1; rc=$?
check "sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/render.log"
check "build-timeline rodou com PYTHONUTF8=1" "$(tem "$PY_LOG" 'PYTHONUTF8=1')"
check "build-timeline foi o python do py.sh" "$(tem "$PY_LOG" 'build-timeline.py')"
check "node recebeu o stills.mjs e a composição Reel916" "$(tem "$NODE_LOG" 'scripts/stills.mjs Reel916')"
check "o png é o quadro do projeto, não um placeholder" "$(tem "$R/out/storyboard/cena-01.png" 'STILL:0')"
check "não gerou voz" "$([ ! -d "$R/public/vo" ] && echo ok || echo fail)"
ESPERADO="$("$PY" -c 'import hashlib, pathlib, sys
raiz = pathlib.Path(sys.argv[1])
print(hashlib.sha256((raiz / "film.json").read_bytes()).hexdigest())
print(hashlib.sha256((raiz / "vo.json").read_bytes()).hexdigest())' "$P")"
AGORA="$("$PY" -c 'import hashlib, pathlib, sys
raiz = pathlib.Path(sys.argv[1])
print(hashlib.sha256((raiz / "film.json").read_bytes()).hexdigest())
print(hashlib.sha256((raiz / "vo.json").read_bytes()).hexdigest())' "$R")"
check "film.json e vo.json do render iguais ao roteiro" "$([ "$AGORA" = "$ESPERADO" ] && echo ok || echo fail)"

echo "7. quadro que não sai"
: > "$NODE_LOG"
FALHA=1 PATH="$BIN:$PATH" MOTION_PY="$BIN/python-motion" "$PY" "$SB" "$R" > "$TMP/falha.log" 2>&1; rc=$?
unset FALHA
check "sai com erro (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
check "diz que o quadro não saiu" "$(tem "$TMP/falha.log" 'não saíram')"

echo "8. folha de contato falha e os quadros ficam"
: > "$NODE_LOG"
FOLHA=1 PATH="$BIN:$PATH" MOTION_PY="$BIN/python-motion" "$PY" "$SB" "$R" > "$TMP/folha.log" 2>&1; rc=$?
unset FOLHA
check "sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/folha.log"
check "avisa a folha" "$(tem "$TMP/folha.log" 'folha')"
check "o quadro ficou" "$(tem "$R/out/storyboard/cena-01.png" 'STILL:0')"

echo "9. a skill manda aprovar antes de voz paga e do render"
check "passo Storyboard antes de construir" "$(tem "$SK/SKILL.md" 'Storyboard antes de construir')"
check "allowed-tools inclui storyboard.py" "$(tem "$SK/SKILL.md" 'scripts/storyboard.py *)')"
check "voz paga só depois da aprovação" "$(tem "$SK/SKILL.md" 'Voz paga e o render final só')"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
