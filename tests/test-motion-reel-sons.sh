#!/usr/bin/env bash
# Sons declarados pela cena e SFX alinhado pelo pico (C6) na motion-reel.
#
# Até o lote 7 o track_cinema.py espelhava à mão, em Python, o tempo de cada animação das cenas
# (SFX_BY_TYPE + scripts/tempos.py): mudou a cena, o som ficava no quadro velho. Agora:
#   1. toda cena do SCENES tem entrada no SONS do src/sons.mjs (vazia vale), e só elas;
#   2. o track_cinema.py não tem mais o SFX_BY_TYPE nem o tempos.py, e lê os sons pelo Node;
#   3. a cena e o som usam os mesmos tempos (DESK_ENVIA, RANKING_PICO, temposMorph…);
#   4. com `impacto`, o pico do WAV cai no quadro pedido (± 1 amostra): WAV sintético com o pico
#      conhecido; sem `impacto`, o som começa no quadro (filme antigo igual);
#   5. node ausente ou sons.mjs quebrado: o track_cinema.py para com mensagem.
# Uso: bash tests/test-motion-reel-sons.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SK="$RAIZ/skills/motion-reel"
[ -d "$SK" ] || SK="$RAIZ/plugin/skills/motion-reel"
A="$SK/assets/template"
[ -f "$A/scripts/track_cinema.py" ] || { echo "template não encontrado em $A"; exit 2; }
command -v node >/dev/null || { echo "node ausente"; exit 2; }
falhas=0
check() { if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"; else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/motion-sons.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

echo "1. toda cena do SCENES declara os sons"
node --input-type=module - "$A" > "$TMP/cenas.log" 2>&1 <<'JS'
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
const A = process.argv[2];
const tsx = fs.readFileSync(path.join(A, "src/film-scenes.tsx"), "utf8");
let bloco = tsx.slice(tsx.indexOf("export const SCENES"));
bloco = bloco.slice(bloco.indexOf("{") + 1, bloco.indexOf("};"));
const tipos = [...bloco.matchAll(/(\w+)\s*:\s*(\w+)/g)].map((m) => m[1]);
const { SONS } = await import(pathToFileURL(path.join(A, "src/sons.mjs")).href);
for (const t of tipos) console.log("tem", t, typeof SONS[t] === "function" ? "ok" : "fail");
for (const t of Object.keys(SONS)) console.log("sobra", t, tipos.includes(t) ? "ok" : "fail");
JS
CENAS="$(awk '$1=="tem"{print $2}' "$TMP/cenas.log" | tr '\n' ' ')"
check "li as cenas do SCENES (${CENAS:0:40}…)" "$([ -n "$CENAS" ] && echo ok || echo fail)"
while read -r k t st; do
  case "$k" in tem) check "SONS tem $t" "$st" ;; sobra) check "SONS.$t é cena do SCENES" "$st" ;; esac
done < "$TMP/cenas.log"
/usr/bin/grep -q "Error" "$TMP/cenas.log" && { sed 's/^/        /' "$TMP/cenas.log"; check "sons.mjs carrega" fail; }

echo "2. sem espelho em Python"
TC="$A/scripts/track_cinema.py"
check "track_cinema.py sem SFX_BY_TYPE" "$(/usr/bin/grep -q 'SFX_BY_TYPE' "$TC" && echo fail || echo ok)"
check "track_cinema.py sem import tempos" "$(/usr/bin/grep -qE '^import tempos|^from tempos' "$TC" && echo fail || echo ok)"
check "scripts/tempos.py removido" "$([ -e "$A/scripts/tempos.py" ] && echo fail || echo ok)"
check "track_cinema.py chama o scripts/sons.mjs" "$(/usr/bin/grep -q 'scripts/sons.mjs' "$TC" && echo ok || echo fail)"
check "o node é chamado com encoding utf-8 (Windows)" "$(/usr/bin/grep -q 'encoding="utf-8"' "$TC" && echo ok || echo fail)"

echo "3. a cena e o som leem os mesmos tempos"
check "desk envia em DESK_ENVIA (cena)" "$(/usr/bin/grep -q 'const send = DESK_ENVIA' "$A/src/film-scenes.tsx" && echo ok || echo fail)"
check "pico do ranking em RANKING_PICO (cena)" "$(/usr/bin/grep -q 'const pico = a + RANKING_PICO' "$A/src/scenes-extras.tsx" && echo ok || echo fail)"
check "o Cta desenha as pílulas pelo pilulasCta" "$(/usr/bin/grep -q 'pilulasCta(p)' "$A/src/film-scenes.tsx" && echo ok || echo fail)"
BT="$A/scripts/build-timeline.py"
check "build-timeline.py grava o tl-*.json em UTF-8 (o track_cinema lê em UTF-8; Windows)" "$(/usr/bin/grep -q 'write_text(json.dumps(tl, ensure_ascii=False, indent=1) + "\\n", encoding="utf-8")' "$BT" && echo ok || echo fail)"
check "build-timeline.py lê film.json e vo.json em UTF-8" "$([ "$(/usr/bin/grep -c 'read_text(encoding="utf-8")' "$BT")" -ge 3 ] && echo ok || echo fail)"
check "film-base reexporta bt/first/hitAt do tempos.mjs" "$(/usr/bin/grep -q 'export { bt, first, hitAt }' "$A/src/film-base.tsx" && echo ok || echo fail)"
node --input-type=module - "$A" > "$TMP/tempos.log" 2>&1 <<'JS'
import path from "node:path";
import { pathToFileURL } from "node:url";
const A = process.argv[2];
const t = await import(pathToFileURL(path.join(A, "src/tempos.mjs")).href);
const { SONS } = await import(pathToFileURL(path.join(A, "src/sons.mjs")).href);
const ok = (n, c) => console.log(n, c ? "ok" : "fail");
const s = { beats: [], ends: [] };
const desk = SONS.desk(s, { click: true, prompt: "a", reply: "b" });
ok("desk-clique-no-contato", desk.some((x) => x.sfx === "soft-click" && x.impacto && x.f === t.DESK_ENVIA - 1));
ok("desk-envio", desk.some((x) => x.sfx === "dry-pop" && x.f === t.DESK_ENVIA));
const rk = SONS.ranking(s, { items: [{ v: 1 }, { v: 2 }, { v: 3 }] });
const ent = t.temposRanking(3, [], t.first(s), 15);
ok("ranking-golpe-no-pico", rk.some((x) => x.sfx === "low-hit" && x.impacto && x.f === ent[2] + t.RANKING_PICO));
const mo = SONS.morph(s, { states: [{ label: "a" }, { label: "b" }] });
ok("morph-nas-trocas", JSON.stringify(mo.filter((x) => x.sfx !== "paper-tap").map((x) => x.f + 1)) === JSON.stringify(t.temposMorph(2, [], t.first(s), 30, true)));
ok("swap-null-vale-ausente", SONS.swap(s, { at: null }).some((x) => x.f === 45 + 18));
const sv = { beats: [0, 70], ends: [50, 130] };
const pc = t.pilulasCta(sv);
const cta = SONS.cta(sv, { q2: "x", pill2: "y" }).map((x) => x.f);
ok("cta-som-nas-pilulas", JSON.stringify(cta) === JSON.stringify([pc.p1, pc.p2]) && pc.p1 === 25 && pc.p2 === 103);
ok("cta-sem-q2-sem-2a-pilula", SONS.cta(sv, { pill2: "y" }).length === 1);
JS
for k in desk-clique-no-contato desk-envio ranking-golpe-no-pico morph-nas-trocas swap-null-vale-ausente cta-som-nas-pilulas cta-sem-q2-sem-2a-pilula; do
  check "sons.mjs: $k" "$(/usr/bin/grep -qx "$k ok" "$TMP/tempos.log" && echo ok || echo fail)"
done

echo "4. impacto: o pico do WAV cai no quadro"
PY="$("$SK/scripts/py.sh" 2>/dev/null)" || PY=""
if [ -z "$PY" ] || ! "$PY" -c 'import numpy' 2>/dev/null; then
  echo "  pulado: sem python com numpy"
else
  P="$TMP/proj"; mkdir -p "$P/src" "$P/scripts" "$P/public/sfx"
  cp "$TC" "$A/scripts/sons.mjs" "$P/scripts/"; cp "$A/src/sons.mjs" "$A/src/tempos.mjs" "$P/src/"
  "$PY" - "$P" <<'PY'
import json, sys, wave, pathlib
import numpy as np
P = pathlib.Path(sys.argv[1]); SR = 48000
t = np.arange(int(0.4 * SR)) / SR
x = 0.8 * np.exp(-((t - 0.1) / 0.002) ** 2)          # pulso com o pico em 100 ms (4800 amostras)
for nm in ("teste", "soft-click", "dry-pop", "paper-tap", "soft-chime", "low-hit", "soft-whoosh", "short-rise"):
    w = wave.open(str(P / f"public/sfx/{nm}.wav"), "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((x * 32767).astype(np.int16).tobytes()); w.close()
cena = {"id": "statement-0", "type": "statement", "cut": 0, "in": "cut", "d": 0, "len": 90, "beats": [], "ends": [],
        "vo": [], "mark": None, "energy": 1, "origin": None, "props": {},
        "cues": [{"at": 30, "sfx": "teste", "impacto": True}, {"at": 60, "sfx": "teste"}]}
desk = dict(cena, id="desk-1", type="desk", cut=90, cues=[], mark="hit", props={"click": True, "prompt": "a", "reply": "b"})
json.dump({"name": "master", "fps": 30, "total": 180, "letterbox": None, "motionBlur": None, "scenes": [cena, desk]},
          open(P / "src/tl-master.json", "w"))
PY
  "$PY" "$P/scripts/track_cinema.py" master --eventos > "$TMP/ev.json" 2> "$TMP/ev.err"; rc=$?
  check "--eventos sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
  [ "$rc" = 0 ] || sed 's/^/        /' "$TMP/ev.err"
  "$PY" - "$TMP/ev.json" > "$TMP/ev.log" 2>&1 <<'PY'
import json, sys
ev = json.load(open(sys.argv[1])); SR, FPS = 48000, 30
def q(f): return f * SR // FPS
cue_imp = [e for e in ev if e["sfx"] == "teste" and abs(e["t"] + 4800 - q(30)) <= 1]
cue_ini = [e for e in ev if e["sfx"] == "teste" and e["t"] == q(60)]
clique = [e for e in ev if e["sfx"] == "soft-click" and e["g"] == 0.6]
print("cue-impacto", "ok" if cue_imp and abs(cue_imp[0]["pico"] - q(30)) <= 1 else "fail")
print("cue-sem-impacto-comeca-no-quadro", "ok" if cue_ini else "fail")
golpe = [e for e in ev if e["sfx"] == "low-hit" and e["g"] == 0.6]
print("golpe-do-mark-no-corte", "ok" if golpe and abs(golpe[0]["pico"] - q(90)) <= 1 and abs(golpe[0]["t"] + 4800 - q(90)) <= 1 else "fail")
print("clique-do-desk-no-contato", "ok" if clique and abs(clique[0]["pico"] - q(90 + 23)) <= 1 else "fail")
PY
  for k in cue-impacto cue-sem-impacto-comeca-no-quadro golpe-do-mark-no-corte clique-do-desk-no-contato; do
    check "$k" "$(/usr/bin/grep -qx "$k ok" "$TMP/ev.log" && echo ok || echo fail)"
  done

  echo "5. sem node ou com sons.mjs quebrado, para com mensagem"
  echo 'export const SONS = ;' > "$P/src/sons.mjs"
  "$PY" "$P/scripts/track_cinema.py" master --eventos > /dev/null 2> "$TMP/q.err"; rc=$?
  check "sons.mjs quebrado: sai com erro (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
  check "a mensagem cita o src/sons.mjs" "$(/usr/bin/grep -q 'src/sons.mjs' "$TMP/q.err" && echo ok || echo fail)"
  mkdir -p "$TMP/semnode"; ln -s "$(command -v dirname)" "$TMP/semnode/dirname"
  PATH="$TMP/semnode" "$PY" "$P/scripts/track_cinema.py" master --eventos > /dev/null 2> "$TMP/n.err"; rc=$?
  check "sem node: sai com erro (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
  check "a mensagem diz que falta o node" "$(/usr/bin/grep -q 'node não encontrado' "$TMP/n.err" && echo ok || echo fail)"
fi

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
