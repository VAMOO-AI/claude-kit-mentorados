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
#      e o filme de lançamento (presets/lancamento.json) vira timeline na batida nos dois formatos;
#   6. a apresentação pessoal (presets/apresentacao.json, 15 s) e o lançamento de app
#      (presets/lancamento-app.json, 30 s) também: cenas novas com props, som e vocabulário,
#      timeline na batida nos dois formatos, e a galeria lista os presets;
#   7. as cenas avulsas (sem preset) estão no SCENES com props, som, vocabulário e exemplo na galeria.
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
for pr in lancamento apresentacao lancamento-app; do check "lista cita o preset $pr" "$(tem "$TMP/lista.log" "$pr.json")"; done
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
for pr in lancamento apresentacao lancamento-app; do check "a página cita o preset $pr" "$(tem "$G/index.html" "$pr.json")"; done
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
# Cena pode morar em outro src/*.tsx (importado no SCENES): o // props: é procurado em todos.
presets_src() { # presets_src <types...> → "<type> props|som ok|fail"
"$PY" - "$A/src" "$A/src/sons.mjs" "$@" <<'PY'
import pathlib, re, sys
src = pathlib.Path(sys.argv[1])
tsx = (src / "film-scenes.tsx").read_text(encoding="utf-8")
sons = open(sys.argv[2], encoding="utf-8").read()
bloco = tsx[tsx.index("export const SCENES"):]
mapa = dict(re.findall(r"(\w+)\s*:\s*(\w+)", bloco[bloco.index("{") + 1:bloco.index("};")]))
linhas = [l for f in sorted(src.glob("*.tsx")) for l in f.read_text(encoding="utf-8").splitlines() + [""]]
for tipo in sys.argv[3:]:
    comp = mapa.get(tipo, "?")
    i = next((k for k, l in enumerate(linhas) if l.startswith(f"export const {comp}:")), None)
    acima = []
    while i and linhas[i - 1].startswith("//"):
        i -= 1; acima.append(linhas[i])
    print(f"{tipo} props", "ok" if any(l.startswith("// props:") for l in acima) else "fail")
    print(f"{tipo} som", "ok" if re.search(rf"^  {tipo}: \(", sons, re.M) else "fail")
PY
}
presets_src $PRESETS > "$TMP/presets-src.log" 2>&1
for c in $PRESETS; do
  check "$c tem // props: acima do componente" "$(/usr/bin/grep -qx "$c props ok" "$TMP/presets-src.log" && echo ok || echo fail)"
  check "$c declara o som no src/sons.mjs" "$(/usr/bin/grep -qx "$c som ok" "$TMP/presets-src.log" && echo ok || echo fail)"
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
film = json.loads((raiz / "film.json").read_text(encoding="utf-8"))
tl = {n: json.loads((raiz / f"src/tl-{n}.json").read_text(encoding="utf-8")) for n in ("master", "reel")}
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

echo "6. presets: apresentação pessoal e lançamento de app"
# Mesmo molde do lançamento: cada cena nova no SCENES com // props: (em qualquer src/*.tsx), som
# próprio e linha no vocabulário; cada preset vira timeline na batida nos dois formatos, sem voz,
# com a duração prometida (15 s e 30 s, ±1 s) e uma linha "sobre" que a galeria lista.
NOVAS="pillname orbit highlights follow appline assemble"
presets_src $NOVAS > "$TMP/novas-src.log" 2>&1
for c in $NOVAS; do
  check "SCENES registra $c" "$(echo " $CENAS " | /usr/bin/grep -qF " $c " && echo ok || echo fail)"
  check "vocabulario.md documenta $c" "$(tem "$SK/references/vocabulario.md" "| \`$c\` |")"
  check "$c tem // props: acima do componente" "$(/usr/bin/grep -qx "$c props ok" "$TMP/novas-src.log" && echo ok || echo fail)"
  check "$c declara o som no src/sons.mjs" "$(/usr/bin/grep -qx "$c som ok" "$TMP/novas-src.log" && echo ok || echo fail)"
done
for par in apresentacao:15 lancamento-app:30; do
  pr="${par%%:*}"; seg="${par#*:}"
  check "SKILL.md cita presets/$pr.json" "$(tem "$SK/SKILL.md" "presets/$pr.json")"
  Z="$TMP/preset-$pr"; mkdir -p "$Z/src" "$Z/scripts"
  cp "$A/scripts/build-timeline.py" "$Z/scripts/"
  cp "$A/presets/$pr.json" "$Z/film.json" 2>/dev/null
  "$PY" "$Z/scripts/build-timeline.py" > "$TMP/$pr.log" 2>&1; rc=$?
  check "$pr vira timeline nos dois formatos (veio $rc)" "$([ "$rc" = 0 ] && [ -f "$Z/src/tl-master.json" ] && [ -f "$Z/src/tl-reel.json" ] && echo ok || echo fail)"
  "$PY" - "$Z" "$CENAS" "$seg" > "$TMP/$pr-tl.log" 2>&1 <<'PY'
import json, pathlib, sys
raiz, cenas, seg = pathlib.Path(sys.argv[1]), sys.argv[2].split(), int(sys.argv[3])
film = json.loads((raiz / "film.json").read_text(encoding="utf-8"))
tl = {n: json.loads((raiz / f"src/tl-{n}.json").read_text(encoding="utf-8")) for n in ("master", "reel")}
tipos = {n: [s["type"] for s in film[n]] for n in ("master", "reel")}
print("tipos", "ok" if all(t in cenas for n in tipos for t in tipos[n]) else "fail")
print("batida", "ok" if all(s["cut"] % 15 == 0 for n in tl for s in tl[n]["scenes"]) else "fail")
print("sem-voz", "ok" if all(not s.get("vo") for n in tipos for s in film[n]) else "fail")
print("duracao", "ok" if all(abs(tl[n]["total"] / 30 - seg) <= 1 for n in tl) else "fail")
print("sobre", "ok" if film.get("sobre") else "fail")
PY
  for k in "tipos:toda cena existe no SCENES" "batida:todo corte cai na batida" "sem-voz:sem fala" \
           "duracao:dura ${seg} s (±1) nos dois formatos" "sobre:tem a linha sobre que a galeria lista"; do
    check "$pr: ${k#*:}" "$(/usr/bin/grep -qx "${k%%:*} ok" "$TMP/$pr-tl.log" && echo ok || echo fail)"
  done
done

echo "7. cenas avulsas (troca de frase, forma que morfa, mapa, ranking e comparação)"
# Cena nova sem preset: está no SCENES com // props:, som próprio e linha no vocabulário, e a
# galeria tira o exemplo dela do EXEMPLOS do galeria.py (o quadro de cada uma é conferido no 2).
AVULSAS="swap morph map ranking versus"
presets_src $AVULSAS > "$TMP/avulsas-src.log" 2>&1
for c in $AVULSAS; do
  check "SCENES registra $c" "$(echo " $CENAS " | /usr/bin/grep -qF " $c " && echo ok || echo fail)"
  check "vocabulario.md documenta $c" "$(tem "$SK/references/vocabulario.md" "| \`$c\` |")"
  check "$c tem // props: acima do componente" "$(/usr/bin/grep -qx "$c props ok" "$TMP/avulsas-src.log" && echo ok || echo fail)"
  check "$c declara o som no src/sons.mjs" "$(/usr/bin/grep -qx "$c som ok" "$TMP/avulsas-src.log" && echo ok || echo fail)"
  check "galeria.py tem exemplo de $c" "$(tem "$GAL" "\"$c\": {")"
done

echo "8. cursor com clique no desk"
# O Cursor do desktop.tsx (trajeto em curva, aperto a 85%, onda de 300 ms) entra no desk por
# `click`; o botão de enviar muda de estado e o clique tem som (1 quadro antes do contato).
check "desktop.tsx exporta o Cursor" "$(tem "$A/src/desktop.tsx" "export const Cursor:")"
check "o desk aceita click?" "$(/usr/bin/grep -q '^// props: kicker?, prompt.*click?' "$A/src/film-scenes.tsx" && echo ok || echo fail)"
check "o Composer tem o estado ocupado" "$(tem "$A/src/desktop.tsx" "busy?: boolean")"
check "o som do desk toca o clique" "$(/usr/bin/grep -A6 '^  desk: (s, p)' "$A/src/sons.mjs" | /usr/bin/grep -q 'p.click' && echo ok || echo fail)"
check "vocabulario.md documenta o Cursor" "$(tem "$SK/references/vocabulario.md" "\`Cursor\`")"

echo "9. motion blur real nas transições rápidas (opt-in no film.json)"
# "motionBlur": true vira {samples: 8, shutter: 180} na timeline; objeto passa com os valores
# dele; sem a chave, null; valor fora da faixa recusa. O Film.tsx usa o CameraMotionBlur.
MB="$TMP/motionblur"; mkdir -p "$MB/src" "$MB/scripts"; cp "$A/scripts/build-timeline.py" "$MB/scripts/"
mb() { # mb <valor json ou -> → imprime o motionBlur do tl-master.json, ou ERRO
  "$PY" - "$MB/film.json" "$1" <<'PY'
import json, sys
film = {"master": [{"type": "statement", "props": {"groups": []}}, {"type": "statement", "in": "whip", "props": {"groups": []}}]}
if sys.argv[2] != "-":
    film["motionBlur"] = json.loads(sys.argv[2])
json.dump(film, open(sys.argv[1], "w"))
PY
  if "$PY" "$MB/scripts/build-timeline.py" master > "$TMP/mb.log" 2>&1; then
    "$PY" -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1])).get("motionBlur", "ausente")))' "$MB/src/tl-master.json"
  else echo ERRO; fi
}
check "true vira samples 8 e shutter 180" "$([ "$(mb true)" = '{"samples": 8, "shutter": 180}' ] && echo ok || echo fail)"
check "objeto passa com os valores dele" "$([ "$(mb '{"samples": 4, "shutter": 90}')" = '{"samples": 4, "shutter": 90}' ] && echo ok || echo fail)"
check "sem a chave, null" "$([ "$(mb -)" = 'null' ] && echo ok || echo fail)"
check "false, null" "$([ "$(mb false)" = 'null' ] && echo ok || echo fail)"
check "samples fora da faixa recusa" "$([ "$(mb '{"samples": 40}')" = ERRO ] && echo ok || echo fail)"
check "shutter fora da faixa recusa" "$([ "$(mb '{"shutter": 400}')" = ERRO ] && echo ok || echo fail)"
check "o Film.tsx usa o CameraMotionBlur" "$(tem "$A/src/Film.tsx" 'CameraMotionBlur')"
check "vocabulario.md documenta o motionBlur" "$(tem "$SK/references/vocabulario.md" '`motionBlur`')"

echo "11. contas das cenas avulsas (revisão do lote 5)"
# As regras puras moram em src/tempos.mjs (Node roda sem compilar); a cena e o som (src/sons.mjs,
# C6) usam as mesmas funções, sem espelho em Python.
TM="$A/src/tempos.mjs"
if [ -f "$TM" ] && command -v node >/dev/null; then
  node --input-type=module - "$TM" > "$TMP/tempos-js.log" 2>&1 <<'JS'
const m = await import(process.argv[2]);
const ok = (nome, cond) => console.log(nome, cond ? "ok" : "fail");
// morph com voz: 8 estados, falas a cada 45 quadros, loop → crescente e a volta depois da última
const fal = [0, 45, 90, 135, 180, 225, 270, 315];
const mo = m.temposMorph(8, fal, -8, 30, true);
ok("morph-crescente", mo.every((v, i) => i === 0 || v >= mo[i - 1] + m.GAP_MORPH));
ok("morph-volta-depois-da-ultima-fala", mo[8] > 315 - 4);
// menos falas que estados: continua a partir da última fala, nunca para trás
const mo2 = m.temposMorph(4, [0, 100], -8, 30, true);
ok("morph-poucas-falas", JSON.stringify(mo2) === JSON.stringify([-8, 96, 126, 156, 186]));
// ranking: 4 posições, só 2 falas → o 1º entra por último
const rk = m.temposRanking(4, [0, 60], -8, 15);
ok("ranking-crescente-1o-por-ultimo", rk.every((v, i) => i === 0 || v > rk[i - 1]) && rk[3] === Math.max(...rk));
ok("ranking-continua-da-ultima-fala", JSON.stringify(rk) === JSON.stringify([-2, 56, 71, 86]));
// ordena antes de cortar: 7 itens, o maior por último
const it = [1, 2, 3, 4, 5, 6, 99].map((v) => ({ label: `x${v}`, v }));
ok("ranking-ordena-antes-de-cortar", m.ordenarRanking(it, false)[0].v === 99 && m.ordenarRanking(it, false).length === 6);
ok("ranking-low", m.ordenarRanking(it, true)[0].v === 1);
// letras NFC e palavras inteiras
ok("letras-nfc", m.letras("Idéia").length === 5);
const ch = m.letras("Ideia solta que virou plano pronto");
ok("palavras-inteiras", JSON.stringify(m.palavras(ch).map(([a, b]) => ch.slice(a, b).join(""))) ===
  JSON.stringify(["Ideia", " ", "solta", " ", "que", " ", "virou", " ", "plano", " ", "pronto"]));
// número com decimais em pt-BR e proporção pelo maior real
ok("decimais", m.decimaisDe(4.5) === 1 && m.decimaisDe(1250000) === 0 && m.fmtNum(4.5, 1) === "4,5");
ok("maior-real", m.maiorValor([0.2, 0.5]) === 0.5 && m.maiorValor([0, -1]) === 1);
// número do versus cabe na coluna do 9:16 (385 px)
const it2 = { v: 1250000, prefix: "R$ " };
const fs = m.corpoNumero(it2, 385, 104);
ok("versus-numero-cabe", fs * (0.62 * (m.fmtNum(1250000).length + 0.6 * 3) + 0.12) <= 385 && fs < 104);
// mapa: uma parada (ou paradas iguais) sem região nunca vira ponto único
ok("mapa-uma-parada", m.enquadramento([[-46, -23]], false).length >= 3);
ok("mapa-paradas-iguais", m.enquadramento([[-46, -23], [-46, -23]], false).length >= 3);
ok("mapa-vazio", m.enquadramento([], false).length >= 2);
ok("mapa-com-regiao", m.enquadramento([[-46, -23]], true).length === 1);
JS
else echo "sem tempos.mjs ou sem node" > "$TMP/tempos-js.log"; fi
for k in morph-crescente morph-volta-depois-da-ultima-fala morph-poucas-falas ranking-crescente-1o-por-ultimo \
         ranking-continua-da-ultima-fala ranking-ordena-antes-de-cortar ranking-low letras-nfc palavras-inteiras \
         decimais maior-real versus-numero-cabe mapa-uma-parada mapa-paradas-iguais mapa-vazio mapa-com-regiao; do
  check "tempos.mjs: $k" "$(/usr/bin/grep -qx "$k ok" "$TMP/tempos-js.log" && echo ok || echo fail)"
done
# as cenas e o som usam as funções (não uma cópia da conta)
X="$A/src/scenes-extras.tsx"; MP="$A/src/scenes-mapa.tsx"; TC="$A/scripts/track_cinema.py"
for f in temposMorph temposRanking ordenarRanking letras palavras corpoNumeroMedido maiorValor; do
  check "scenes-extras.tsx usa $f" "$(/usr/bin/grep -q "$f(" "$X" && echo ok || echo fail)"
done
check "scenes-mapa.tsx usa enquadramento" "$(/usr/bin/grep -q 'enquadramento(' "$MP" && echo ok || echo fail)"
check "scenes-mapa.tsx recusa região que não existe" "$(/usr/bin/grep -q 'não existe no Natural Earth' "$MP" && echo ok || echo fail)"
check "a régua quebra só entre palavras (nowrap por palavra)" "$(/usr/bin/grep -q 'whiteSpace: "nowrap"' "$X" && /usr/bin/grep -q 'palavras(' "$X" && echo ok || echo fail)"
for f in temposMorph temposRanking trocaSwap; do
  check "sons.mjs usa $f" "$(/usr/bin/grep -q "$f(" "$A/src/sons.mjs" && echo ok || echo fail)"
done
check "Counter aceita decimais" "$(/usr/bin/grep -q 'decimals' "$A/src/lib.tsx" && echo ok || echo fail)"
check "Spin chama o useContext antes do return antecipado" "$("$PY" - "$A/src/transitions.tsx" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
spin = t[t.index("const Spin"):t.index("const EchoTrail")]
print("ok" if "useContext" in spin and spin.index("useContext") < spin.index("if (presentationProgress") else "fail")
PY
)"
# validação no build-timeline.py
BV="$TMP/valida"; mkdir -p "$BV/src" "$BV/scripts" "$BV/node_modules/world-atlas"; cp "$A/scripts/build-timeline.py" "$BV/scripts/"
printf '{"objects":{"countries":{"geometries":[{"properties":{"name":"Brazil"}}]}}}' > "$BV/node_modules/world-atlas/countries-110m.json"
bv() { # bv <cena json> → OK ou ERRO
  "$PY" -c 'import json, sys; json.dump({"master": [json.loads(sys.argv[2])]}, open(sys.argv[1], "w"))' "$BV/film.json" "$1"
  "$PY" "$BV/scripts/build-timeline.py" master > "$TMP/bv.log" 2>&1 && echo OK || echo ERRO
}
check "map com 1 parada e sem região recusa" "$([ "$(bv '{"type":"map","props":{"route":[{"at":[1,2]}]}}')" = ERRO ] && echo ok || echo fail)"
check "map com paradas iguais recusa" "$([ "$(bv '{"type":"map","props":{"route":[{"at":[1,2]},{"at":[1,2]}]}}')" = ERRO ] && echo ok || echo fail)"
check "map com 7 paradas recusa" "$([ "$(bv '{"type":"map","props":{"route":[{"at":[1,1]},{"at":[2,2]},{"at":[3,3]},{"at":[4,4]},{"at":[5,5]},{"at":[6,6]},{"at":[7,7]}]}}')" = ERRO ] && echo ok || echo fail)"
check "map com região que não existe recusa" "$([ "$(bv '{"type":"map","props":{"region":"Brasil","route":[]}}')" = ERRO ] && echo ok || echo fail)"
check "map com região e sem rota passa" "$([ "$(bv '{"type":"map","props":{"region":"Brazil"}}')" = OK ] && echo ok || echo fail)"
check "map com 2 paradas passa" "$([ "$(bv '{"type":"map","props":{"route":[{"at":[1,1]},{"at":[2,2]}]}}')" = OK ] && echo ok || echo fail)"
check "morph sem estados recusa" "$([ "$(bv '{"type":"morph","props":{"states":[]}}')" = ERRO ] && echo ok || echo fail)"
check "morph com 9 estados recusa" "$([ "$(bv '{"type":"morph","props":{"states":[{"label":"a"},{"label":"a"},{"label":"a"},{"label":"a"},{"label":"a"},{"label":"a"},{"label":"a"},{"label":"a"},{"label":"a"}]}}')" = ERRO ] && echo ok || echo fail)"
check "a mensagem do morph diz o limite" "$(/usr/bin/grep -q '1 a 8' "$TMP/bv.log" && echo ok || echo fail)"
check "motionBlur.shutter true recusa" "$([ "$(mb '{"shutter": true}')" = ERRO ] && echo ok || echo fail)"
check "motionBlur.shutter 0,5 recusa" "$([ "$(mb '{"shutter": 0.5}')" = ERRO ] && echo ok || echo fail)"
check "motionBlur aceita shutterAngle" "$([ "$(mb '{"shutterAngle": 90}')" = '{"samples": 8, "shutter": 90}' ] && echo ok || echo fail)"
check "motionBlur recusa chave desconhecida" "$([ "$(mb '{"amostras": 4}')" = ERRO ] && echo ok || echo fail)"

echo "10. dependências do template: nenhuma sem uso"
# Toda dependência do package.json é importada em src/ ou scripts/ do template, ou está na lista
# abaixo com o motivo; o package-lock.json lista as mesmas dependências diretas.
"$PY" - "$A" > "$TMP/deps.log" 2>&1 <<'PY'
import json, pathlib, re, sys
raiz = pathlib.Path(sys.argv[1])
fora = {
    "@remotion/cli": "o npx remotion render/studio do qa.sh, do final.sh e do package.json",
    "@remotion/bundler": "o render da galeria e o stills.mjs",
    "@remotion/renderer": "o render da galeria e o stills.mjs",
    "react-dom": "par do react, carregado pelo Remotion",
    "fast-uri": "versão mínima travada de dependência indireta (segurança)",
}
pkg = json.loads((raiz / "package.json").read_text())
deps = pkg.get("dependencies", {})
codigo = "\n".join(p.read_text(encoding="utf-8") for d in ("src", "scripts") for p in (raiz / d).rglob("*") if p.suffix in (".ts", ".tsx", ".mjs", ".js"))
for dep in sorted(deps):
    usa = re.search(r"""from ["']%s(?:/[^"']*)?["']""" % re.escape(dep), codigo)
    print(dep, "ok" if usa or dep in fora else "sem-uso")
lock = json.loads((raiz / "package-lock.json").read_text())["packages"][""]
print("lock", "ok" if lock.get("dependencies") == deps and lock.get("devDependencies") == pkg.get("devDependencies") else "diverge")
PY
while read -r dep st; do
  if [ "$dep" = lock ]; then check "o package-lock.json lista as mesmas dependências diretas" "$([ "$st" = ok ] && echo ok || echo fail)"
  else check "$dep tem uso (ou motivo na lista)" "$([ "$st" = ok ] && echo ok || echo fail)"; fi
done < "$TMP/deps.log"

echo "12. bancada de pior caso (--pior-caso)"
# presets/pior-caso.json traz textos no limite documentado e no limite + 1; não é preset de filme:
# fica fora da lista e dos exemplos. A galeria --pior-caso renderiza cada cena dele em 9:16 e 16:9
# e o Grande do Reel com cada palavra, num bundle só, e devolve os tl-*.json do projeto.
PC="$A/presets/pior-caso.json"
"$PY" - "$PC" > "$TMP/pc.log" 2>&1 <<'PY'
import json, sys, unicodedata
d = json.load(open(sys.argv[1], encoding="utf-8"))
m = d["master"]
tipos = [c["type"] for c in m]
print("grande-limite", "ok" if [len(w) for w in d.get("grande", [])] == [7, 8] else "fail")
sw = sorted(len(c["props"]["from"]) for c in m if c["type"] == "swap")
print("swap-limite", "ok" if sw == [16, 17] and all(len(c["props"]["from"]) == len(c["props"]["to"]) for c in m if c["type"] == "swap") else "fail")
rk = sorted(len(c["props"]["items"]) for c in m if c["type"] == "ranking")
print("ranking-6-e-1", "ok" if rk == [1, 6] else "fail")
real = [it for c in m for it in (c["props"].get("items") or [c["props"].get("left", {}), c["props"].get("right", {})]) if isinstance(it, dict)]
print("real-milhar-centavos", "ok" if any(it.get("prefix") == "R$ " and it.get("v", 0) >= 1000 and it.get("v") % 1 for it in real) else "fail")
nome = [c["props"]["name"] for c in m if c["type"] == "chapter"]
print("nome-acento-caixa-alta", "ok" if nome and nome[0].isupper() and " " in nome[0] and any(unicodedata.decomposition(ch) for ch in nome[0]) else "fail")
print("desk-comando-longo", "ok" if any(len(c["props"].get("prompt", "")) > 100 for c in m if c["type"] == "desk") else "fail")
PY
for k in grande-limite swap-limite ranking-6-e-1 real-milhar-centavos nome-acento-caixa-alta desk-comando-longo; do
  check "pior-caso.json: $k" "$(/usr/bin/grep -qx "$k ok" "$TMP/pc.log" && echo ok || echo fail)"
done
check "--lista não oferece o pior-caso como preset" "$(/usr/bin/grep -qF 'pior-caso.json' "$TMP/lista.log" && echo fail || echo ok)"
check "a página da galeria não oferece o pior-caso" "$(/usr/bin/grep -qF 'pior-caso.json' "$G/index.html" && echo fail || echo ok)"
cp "$A/src/timeline.json" "$P/src/timeline.json"; cp "$A/src/tl-master.json" "$P/src/tl-master.json" 2>/dev/null
hashes2() { (cd "$P" && "$PY" -c 'import hashlib, sys, os
for f in sys.argv[1:]: print(f, hashlib.sha256(open(f, "rb").read()).hexdigest() if os.path.exists(f) else "-")' film.json src/tl-reel.json src/tl-master.json); }
ANTES2="$(hashes2)"; : > "$NODE_LOG"
PATH="$BIN:$PATH" "$PY" "$GAL" "$P" --pior-caso > "$TMP/pior.log" 2>&1; rc=$?
check "--pior-caso sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/pior.log"
PG="$P/out/galeria-pior-caso"
NM="$("$PY" -c 'import json, sys; print(len(json.load(open(sys.argv[1]))["master"]))' "$PC")"
for fmt in reel master; do
  check "um quadro por cena em $fmt ($NM)" "$([ "$(ls "$PG"/pior-$fmt-*.png 2>/dev/null | wc -l | tr -d ' ')" = "$NM" ] && echo ok || echo fail)"
done
check "o Grande com cada palavra" "$([ -f "$PG/pior-grande-0.png" ] && [ -f "$PG/pior-grande-1.png" ] && echo ok || echo fail)"
check "a página mostra cada quadro com a guia" "$([ "$(/usr/bin/grep -c '<i style="left:' "$PG/index.html")" = "$(ls "$PG"/*.png | wc -l | tr -d ' ')" ] && echo ok || echo fail)"
check "um render só (um bundle)" "$([ "$(/usr/bin/grep -c '^node' "$NODE_LOG")" = 1 ] && echo ok || echo fail)"
check "film.json e tl-*.json iguais" "$([ "$(hashes2)" = "$ANTES2" ] && echo ok || echo fail)"
check "SKILL.md cita a bancada" "$(tem "$SK/SKILL.md" "--pior-caso")"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
