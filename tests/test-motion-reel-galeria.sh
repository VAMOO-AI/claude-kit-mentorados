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
#   4. pasta sem projeto recusa;
#   5. os presets (logo3d, launch, beats, glass) estão no SCENES com props, som e vocabulário,
#      e o filme de lançamento (presets/lancamento.json) vira timeline na batida nos dois formatos.
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
# Terminal do Windows em cp1252: "→" e "×" da listagem não podem derrubar o script.
PYTHONIOENCODING=cp1252 "$PY" "$GAL" --lista > "$TMP/lista-cp1252.log" 2>&1; rc=$?
check "--lista com stdout cp1252 sai 0 sem UnicodeEncodeError (veio $rc)" "$([ "$rc" = 0 ] && ! /usr/bin/grep -q 'UnicodeEncodeError' "$TMP/lista-cp1252.log" && echo ok || echo fail)"

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

echo "5. presets: logo 3D, filme de lançamento e vidro"
# Cada preset é cena do SCENES (o film.json escolhe pelo type), com o comentário de props que a
# galeria mostra, som próprio no track_cinema.py e linha no vocabulário. O filme de lançamento é
# um film.json pronto (presets/lancamento.json): master 16:9 e corte 9:16 com as mesmas cenas,
# sem voz, todo corte na batida.
PRESETS="logo3d launch beats glass"
for c in $PRESETS; do
  check "SCENES registra $c" "$(echo " $CENAS " | /usr/bin/grep -qF " $c " && echo ok || echo fail)"
  check "vocabulario.md documenta $c" "$(tem "$SK/references/vocabulario.md" "| \`$c\` |")"
done
"$PY" - "$A/src/film-scenes.tsx" "$A/scripts/track_cinema.py" $PRESETS > "$TMP/presets-src.log" 2>&1 <<'PY'
import re, sys
tsx, track = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
bloco = tsx[tsx.index("export const SCENES"):]
mapa = dict(re.findall(r"(\w+)\s*:\s*(\w+)", bloco[bloco.index("{") + 1:bloco.index("};")]))
sfx = track[track.index("SFX_BY_TYPE = {"):]
sfx = sfx[:sfx.index("}") + 1]
linhas = tsx.splitlines()
for tipo in sys.argv[3:]:
    comp = mapa.get(tipo, "?")
    i = next((k for k, l in enumerate(linhas) if l.startswith(f"export const {comp}:")), None)
    acima = []
    while i and linhas[i - 1].startswith("//"):
        i -= 1; acima.append(linhas[i])
    print(f"{tipo} props", "ok" if any(l.startswith("// props:") for l in acima) else "fail")
    print(f"{tipo} som", "ok" if f'"{tipo}":' in sfx else "fail")
PY
for c in $PRESETS; do
  check "$c tem // props: acima do componente" "$(/usr/bin/grep -qx "$c props ok" "$TMP/presets-src.log" && echo ok || echo fail)"
  check "$c tem som próprio no SFX_BY_TYPE" "$(/usr/bin/grep -qx "$c som ok" "$TMP/presets-src.log" && echo ok || echo fail)"
done
check "SKILL.md cita os presets" "$(tem "$SK/SKILL.md" "presets/lancamento.json")"

# Marca neutra: o kit é de quem instala. Os presets pintam com a paleta C do lib.tsx (a da
# pessoa) e o logo3d empilha o marca.png dela, com o PNG trocável por prop; cor fixa (hex ou
# rgb que não seja branco/preto) dentro de um preset vira a cor de outra marca em toda peça.
"$PY" - "$A/src/film-scenes.tsx" > "$TMP/presets-cor.log" 2>&1 <<'PY'
import re, sys
tsx = open(sys.argv[1], encoding="utf-8").read()
ini = tsx.index("presets: lançamento")
fim = tsx.index("export const SCENES")
bloco = tsx[ini:fim]
fixas = re.findall(r"#[0-9a-fA-F]{3,8}\b", bloco)
fixas += [m for m in re.findall(r"rgba?\(\s*\d+\s*,\s*\d+\s*,\s*\d+", bloco)
          if re.sub(r"\s", "", m) not in ("rgba(255,255,255", "rgba(0,0,0", "rgb(255,255,255", "rgb(0,0,0")]
print("cor", "ok" if not fixas else "fail " + " ".join(fixas))
logo = bloco[bloco.index("export const Logo3D"):]
print("mark", "ok" if re.search(r'staticFile\(p\.mark \?\? "marca\.png"\)', logo) else "fail")
PY
check "presets sem cor fixa: tudo vem da paleta C ($(head -1 "$TMP/presets-cor.log"))" "$(/usr/bin/grep -qx 'cor ok' "$TMP/presets-cor.log" && echo ok || echo fail)"
check "logo3d empilha o marca.png da pessoa, trocável pela prop mark" "$(/usr/bin/grep -qx 'mark ok' "$TMP/presets-cor.log" && echo ok || echo fail)"

LZ="$TMP/lancamento"; mkdir -p "$LZ/src" "$LZ/scripts"
cp "$A/scripts/build-timeline.py" "$LZ/scripts/"
cp "$A/presets/lancamento.json" "$LZ/film.json" 2>/dev/null
"$PY" "$LZ/scripts/build-timeline.py" > "$TMP/lanc.log" 2>&1; rc=$?
check "o lançamento vira timeline nos dois formatos (veio $rc)" "$([ "$rc" = 0 ] && [ -f "$LZ/src/tl-master.json" ] && [ -f "$LZ/src/tl-reel.json" ] && echo ok || echo fail)"
"$PY" - "$LZ" "$CENAS" > "$TMP/lanc-tl.log" 2>&1 <<'PY'
import json, pathlib, sys
raiz, cenas = pathlib.Path(sys.argv[1]), sys.argv[2].split()
film = json.loads((raiz / "film.json").read_text())
tl = {n: json.loads((raiz / f"src/tl-{n}.json").read_text()) for n in ("master", "reel")}
tipos = {n: [s["type"] for s in film[n]] for n in ("master", "reel")}
print("tipos", "ok" if all(t in cenas for n in tipos for t in tipos[n]) else "fail")
print("ordem", "ok" if tipos["master"][:2] == ["launch", "beats"] and tipos["master"][-1] == "logo3d" else "fail")
print("corte", "ok" if set(tipos["reel"]) <= set(tipos["master"]) else "fail")
print("batida", "ok" if all(s["cut"] % 15 == 0 for n in tl for s in tl[n]["scenes"]) and all(tl[n]["total"] % 15 == 0 for n in tl) else "fail")
print("sem-voz", "ok" if all(not s.get("vo") for n in tipos for s in film[n]) else "fail")
PY
for k in "tipos:toda cena do lançamento existe no SCENES" "ordem:abre com launch e beats e assina com logo3d" \
         "corte:o reel é corte do master" "batida:todo corte cai na batida (múltiplo de 15)" "sem-voz:sem fala (o ritmo é da trilha)"; do
  check "${k#*:}" "$(/usr/bin/grep -qx "${k%%:*} ok" "$TMP/lanc-tl.log" && echo ok || echo fail)"
done

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
