#!/usr/bin/env bash
# Briefing de motion, leitura e explicativo da motion-reel (lote 4 do plano de motion):
#   1. references/briefing-motion.md tem as cinco partes, o mapa conteúdo → cena, os reads e o
#      checklist, e o SKILL.md manda começar por ele;
#   2. o build-timeline.py grava `read` em cada cena e avisa leitura curta (2,5 palavras/s + 0,5 s)
#      só na cena que não cabe; a lista `read` do film.json manda na contagem; a moldura de UI
#      (sessão, arquivos, painel) não conta;
#   3. presets/explicativo.json: 5 cenas que existem no SCENES (problema, o que faz, 3 passos,
#      prova, nome), 16:9 + corte 9:16, sem voz, na batida, ~20 s, sem leitura curta, citado no
#      SKILL.md e na lista da galeria;
#   4. a doutrina de motion é o padrão: cena sem `in` herda a corrente (`current`, padrão whip),
#      lib.tsx exporta SETTLE, EXIT, POP, ANTIC e hitStop, o Breathe fica só no fim, o clímax do
#      numbers é opcional (focus: "last") e o statement aceita lineFracs.
#
# Uso: bash tests/test-motion-reel-briefing.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SK="$RAIZ/plugin/skills/motion-reel"
A="$SK/assets/template"
PY="$(command -v python3)" || { echo "python3 ausente"; exit 2; }
[ -f "$A/scripts/build-timeline.py" ] || { echo "build-timeline.py não encontrado em $A"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
tem() { /usr/bin/grep -qF -- "$2" "$1" 2>/dev/null && echo ok || echo fail; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/motion-briefing.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

echo "1. briefing-motion.md"
B="$SK/references/briefing-motion.md"
check "o arquivo existe" "$([ -f "$B" ] && echo ok || echo fail)"
for parte in "## 1. Entradas" "## 2. Direção" "## 3. Estrutura" "## 4. Construção" "## 5. Armadilhas" "**Proibidos**" \
             "### Mapa conteúdo → cena" "### Reads" "### Checklist do storyboard" "2,5 palavras/s + 0,5 s" \
             "Final que rima com a abertura" "Transição motivada" "Evento em toda cena"; do
  check "tem \"$parte\"" "$(tem "$B" "$parte")"
done
for par in "número:numbers" "lista ou passos:rows" "frase:statement" "uso do produto:desk"; do
  check "mapa: ${par%%:*} → ${par#*:}" "$(/usr/bin/grep -E "^\| ${par%%:*} \|" "$B" 2>/dev/null | /usr/bin/grep -qF "\`${par#*:}\`" && echo ok || echo fail)"
done
check "intensidade em número (px, %, ms)" "$(/usr/bin/grep -E '^\| moderada' "$B" 2>/dev/null | /usr/bin/grep -q 'px.*%.*ms' && echo ok || echo fail)"
check "SKILL.md manda começar pelo briefing" "$(tem "$SK/SKILL.md" "references/briefing-motion.md")"
# Depois de uma compactação só o começo do SKILL.md volta (tests/test-skill-tamanho.sh): o
# passo que precisa do detalhe tem de apontar a reference em que ele mora.
for r in briefing-e-projeto roteiro-e-cenas qa-e-entrega template linguagem-visual; do
  check "SKILL.md aponta references/$r.md" "$(tem "$SK/SKILL.md" "references/$r.md")"
done

echo "2. leitura curta no build-timeline.py"
Z="$TMP/leitura"; mkdir -p "$Z/src" "$Z/scripts"
cp "$A/scripts/build-timeline.py" "$Z/scripts/"
cat > "$Z/film.json" <<'JSON'
{"master": [
 {"type": "statement", "vo": [], "min": 45, "props": {"bg": "night", "groups": [{"beat": 0, "lines": ["Uma frase longa demais para caber", "em um segundo e meio de tela, com folga nenhuma."]}]}},
 {"type": "statement", "vo": [], "min": 120, "props": {"bg": "paper", "groups": [{"beat": 0, "lines": ["Cabe."]}]}},
 {"type": "desk", "vo": [], "min": 90, "props": {"session": "UMA SESSÃO COM MUITAS PALAVRAS NO NOME", "prompt": "monta", "reply": "Pronto.",
   "files": [["um/arquivo/longo.md", 3], ["outro/arquivo/longo.md", 4]], "working": "Trabalhando em muitas coisas ao mesmo tempo agora"}},
 {"type": "statement", "vo": [], "min": 45, "read": ["Só isto."], "props": {"bg": "night", "groups": [{"beat": 0, "lines": ["Texto decorativo comprido que não precisa ser lido inteiro agora"]}]}}
]}
JSON
"$PY" "$Z/scripts/build-timeline.py" > "$TMP/leitura.log" 2>&1; rc=$?
check "roda (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "avisa leitura curta" "$(tem "$TMP/leitura.log" "leitura curta")"
check "o aviso cita a cena longa (statement-0)" "$(tem "$TMP/leitura.log" "statement-0 (")"
check "a cena folgada não entra no aviso" "$(/usr/bin/grep -qF "statement-1 (" "$TMP/leitura.log" && echo fail || echo ok)"
check "a moldura de UI do desk não conta" "$(/usr/bin/grep -qF "desk-2 (" "$TMP/leitura.log" && echo fail || echo ok)"
check "a lista read do film.json manda na contagem" "$(/usr/bin/grep -qF "statement-3 (" "$TMP/leitura.log" && echo fail || echo ok)"
"$PY" - "$Z/src/tl-master.json" > "$TMP/read.log" 2>&1 <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))["scenes"]
print("campo", "ok" if all(set(c.get("read", {})) == {"words", "need", "secs"} for c in s) else "fail")
print("conta", "ok" if s[0]["read"]["words"] == 16 and s[0]["read"]["need"] == 6.9 and s[0]["read"]["secs"] == 1.5 else "fail")
print("desk", "ok" if s[2]["read"]["words"] == 2 else "fail")
print("lista", "ok" if s[3]["read"]["words"] == 2 else "fail")
PY
for k in "campo:toda cena da timeline traz read {words, need, secs}" "conta:16 palavras pedem 6,9 s numa cena de 1,5 s" \
         "desk:o desk conta só pedido e resposta" "lista:a cena com read conta só a lista"; do
  check "${k#*:}" "$(/usr/bin/grep -qx "${k%%:*} ok" "$TMP/read.log" && echo ok || echo fail)"
done

echo "3. preset explicativo"
CENAS="$("$PY" - "$A/src/film-scenes.tsx" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
bloco = t[t.index("export const SCENES"):]
bloco = bloco[bloco.index("{") + 1:bloco.index("};")]
print(" ".join(k for k, _ in re.findall(r"(\w+)\s*:\s*(\w+)", bloco)))
PY
)"
check "SKILL.md cita presets/explicativo.json" "$(tem "$SK/SKILL.md" "presets/explicativo.json")"
E="$TMP/explicativo"; mkdir -p "$E/src" "$E/scripts"
cp "$A/scripts/build-timeline.py" "$E/scripts/"
cp "$A/presets/explicativo.json" "$E/film.json" 2>/dev/null
"$PY" "$E/scripts/build-timeline.py" > "$TMP/explicativo.log" 2>&1; rc=$?
check "vira timeline nos dois formatos (veio $rc)" "$([ "$rc" = 0 ] && [ -f "$E/src/tl-master.json" ] && [ -f "$E/src/tl-reel.json" ] && echo ok || echo fail)"
check "sem aviso de leitura curta" "$(/usr/bin/grep -qF "leitura curta" "$TMP/explicativo.log" && echo fail || echo ok)"
"$PY" - "$E" "$CENAS" > "$TMP/explicativo-tl.log" 2>&1 <<'PY'
import json, pathlib, sys
raiz, cenas = pathlib.Path(sys.argv[1]), sys.argv[2].split()
film = json.loads((raiz / "film.json").read_text(encoding="utf-8"))
tl = {n: json.loads((raiz / f"src/tl-{n}.json").read_text(encoding="utf-8")) for n in ("master", "reel")}
tipos = {n: [s["type"] for s in film[n]] for n in ("master", "reel")}
print("cinco", "ok" if len(tipos["master"]) == 5 else "fail")
print("tipos", "ok" if all(t in cenas for n in tipos for t in tipos[n]) else "fail")
print("ordem", "ok" if tipos["master"] == ["statement", "title", "beats", "glass", "logo3d"] else "fail")
print("corte", "ok" if set(tipos["reel"]) <= set(tipos["master"]) else "fail")
print("batida", "ok" if all(s["cut"] % 15 == 0 for n in tl for s in tl[n]["scenes"]) and all(tl[n]["total"] % 15 == 0 for n in tl) else "fail")
print("sem-voz", "ok" if all(not s.get("vo") for n in tipos for s in film[n]) else "fail")
print("duracao", "ok" if all(18 <= tl[n]["total"] / 30 <= 23 for n in tl) else "fail")
prova = [s for s in film["master"] if s["type"] == "glass"]
print("fonte", "ok" if prova and "fonte" in json.dumps(prova[0]["props"], ensure_ascii=False) else "fail")
print("sobre", "ok" if film.get("sobre") else "fail")
PY
for k in "cinco:cinco cenas" "tipos:toda cena existe no SCENES" "ordem:problema, o que faz, 3 passos, prova, nome" \
         "corte:o reel é corte do master" "batida:todo corte cai na batida (múltiplo de 15)" "sem-voz:sem fala (o ritmo é da trilha)" \
         "duracao:dura ~20 s nos dois formatos" "fonte:a prova mostra a fonte do número" "sobre:tem a linha sobre que a galeria lista"; do
  check "${k#*:}" "$(/usr/bin/grep -qx "${k%%:*} ok" "$TMP/explicativo-tl.log" && echo ok || echo fail)"
done
"$PY" "$SK/scripts/galeria.py" --lista > "$TMP/lista.log" 2>&1
check "a lista da galeria cita o explicativo" "$(tem "$TMP/lista.log" "explicativo.json")"

echo "4. doutrina de motion como padrão (corrente, constantes, Breathe só no fim, clímax opcional)"
C4="$TMP/corrente"; mkdir -p "$C4/src" "$C4/scripts"
cp "$A/scripts/build-timeline.py" "$C4/scripts/"
cat > "$C4/film.json" <<'JSON'
{"master": [
 {"type": "statement", "vo": [], "min": 60, "props": {"groups": [{"beat": 0, "lines": ["Um."]}]}},
 {"type": "statement", "vo": [], "min": 60, "props": {"groups": [{"beat": 0, "lines": ["Dois."]}]}},
 {"type": "statement", "vo": [], "min": 60, "props": {"groups": [{"beat": 0, "lines": ["Três."]}]}},
 {"type": "outro", "vo": [], "min": 60, "in": "ink", "props": {"name": "X"}}
]}
JSON
"$PY" "$C4/scripts/build-timeline.py" > "$TMP/corrente.log" 2>&1
check "sem current, a cena sem in herda whip" "$("$PY" -c 'import json,sys; s=json.load(open(sys.argv[1]))["scenes"]; print("ok" if [c["in"] for c in s] == ["cut", "whip", "whip", "ink"] else "fail")' "$C4/src/tl-master.json" 2>/dev/null || echo fail)"
"$PY" -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["current"]="push"; json.dump(d, open(p,"w"))' "$C4/film.json"
"$PY" "$C4/scripts/build-timeline.py" > /dev/null 2>&1
check "current: push vale para toda cena sem in; o in explícito fica" "$("$PY" -c 'import json,sys; s=json.load(open(sys.argv[1]))["scenes"]; print("ok" if [c["in"] for c in s] == ["cut", "push", "push", "ink"] else "fail")' "$C4/src/tl-master.json" 2>/dev/null || echo fail)"
"$PY" -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["current"]="voa"; json.dump(d, open(p,"w"))' "$C4/film.json"
"$PY" "$C4/scripts/build-timeline.py" > "$TMP/corrente-ruim.log" 2>&1; rc=$?
check "corrente que não existe recusa (veio $rc)" "$([ "$rc" != 0 ] && /usr/bin/grep -qF "corrente 'voa'" "$TMP/corrente-ruim.log" && echo ok || echo fail)"
for k in "export const SETTLE" "export const EXIT" "export const POP" "export const ANTIC" "export const hitStop" "ease = EASE"; do
  check "lib.tsx: $k" "$(tem "$A/src/lib.tsx" "$k")"
done
check "Film.tsx: Breathe só por props.breathe ou no outro/logo3d" "$(/usr/bin/grep -qF 's.props.breathe ?? BREATHE_BY_TYPE.has(s.type)' "$A/src/Film.tsx" && /usr/bin/grep -qF 'new Set(["outro", "logo3d"])' "$A/src/Film.tsx" && echo ok || echo fail)"
check "numbers: clímax só com focus: \"last\"" "$(tem "$A/src/film-scenes.tsx" 'p.focus === "last"')"
check "statement: lineFracs" "$(tem "$A/src/film-scenes.tsx" "g.lineFracs")"
check "outro: fade de 16 quadros com EXIT" "$(tem "$A/src/film-scenes.tsx" "[p.len - 16, p.len], [1, 0], EXIT")"
check "transicoes.md: repita a corrente" "$(tem "$SK/references/transicoes.md" "Repita a corrente; varie só com motivo")"
check "vocabulario.md: doutrina como padrão, sem cor de foco" "$(tem "$SK/references/vocabulario.md" "sem cor de foco no clímax")"

echo "5. achados da revisão do lote 4"
# lineFracs validado pelo build-timeline; focus/breathe fora da leitura; cut não vale como corrente;
# o exemplo e os presets saem sem aviso de leitura curta; a 1ª linha do statement segue first(p).
L5="$TMP/linefracs"; mkdir -p "$L5/src" "$L5/scripts"; cp "$A/scripts/build-timeline.py" "$L5/scripts/"
lf() { # lf <groups json> → exit do build-timeline
  printf '{"master": [{"type": "statement", "vo": [], "min": 60, "props": {"groups": %s}}]}' "$1" > "$L5/film.json"
  "$PY" "$L5/scripts/build-timeline.py" > "$TMP/lf.log" 2>&1
}
check "lineFracs certo passa (veio $?)" "$([ "$(lf '[{"beat": 0, "lines": ["A", "B"], "lineFracs": [0, 0.6]}]'; echo $?)" = 0 ] && echo ok || echo fail)"
for caso in 'fora de [0, 1]:[{"beat": 0, "lines": ["A", "B"], "lineFracs": [0, 1.4]}]' \
            'fora de ordem:[{"beat": 0, "lines": ["A", "B"], "lineFracs": [0.6, 0.2]}]' \
            'antes do frac do grupo:[{"beat": 0, "frac": 0.5, "lines": ["A", "B"], "lineFracs": [0.3, 0.8]}]' \
            'próximo grupo:[{"beat": 0, "lines": ["A", "B"], "lineFracs": [0, 0.6]}, {"beat": 0, "frac": 0.45, "lines": ["C"]}]' \
            'um número por linha:[{"beat": 0, "lines": ["A", "B"], "lineFracs": [0]}]'; do
  lf "${caso#*:}"; rc=$?
  check "lineFracs recusa: ${caso%%:*} (veio $rc)" "$([ "$rc" != 0 ] && /usr/bin/grep -qF "${caso%%:*}" "$TMP/lf.log" && echo ok || echo fail)"
done
printf '{"master": [{"type": "numbers", "vo": [], "min": 90, "props": {"focus": "last", "breathe": true, "items": [{"v": 3, "label": "cliques"}]}}]}' > "$L5/film.json"
"$PY" "$L5/scripts/build-timeline.py" > /dev/null 2>&1
check "focus e breathe não contam na leitura" "$("$PY" -c 'import json,sys; print("ok" if json.load(open(sys.argv[1]))["scenes"][0]["read"]["words"] == 2 else "fail")' "$L5/src/tl-master.json" 2>/dev/null || echo fail)"
printf '{"current": "cut", "master": [{"type": "statement", "vo": [], "min": 60, "props": {"groups": [{"beat": 0, "lines": ["A"]}]}}]}' > "$L5/film.json"
"$PY" "$L5/scripts/build-timeline.py" > "$TMP/cut.log" 2>&1; rc=$?
check "current: cut recusa dizendo que cut é transição mas não corrente" "$([ "$rc" != 0 ] && /usr/bin/grep -qF "não vale como corrente" "$TMP/cut.log" && echo ok || echo fail)"
for f in film.json presets/lancamento.json presets/apresentacao.json presets/lancamento-app.json presets/explicativo.json; do
  Z5="$TMP/sem-aviso"; rm -rf "$Z5"; mkdir -p "$Z5/src" "$Z5/scripts"; cp "$A/scripts/build-timeline.py" "$Z5/scripts/"; cp "$A/$f" "$Z5/film.json"
  [ "$f" = film.json ] && cp "$A/vo.json" "$Z5/"
  "$PY" "$Z5/scripts/build-timeline.py" > "$TMP/sem-aviso.log" 2>&1
  check "$f sai sem aviso de leitura curta" "$(/usr/bin/grep -qF "leitura curta" "$TMP/sem-aviso.log" && echo fail || echo ok)"
done
check "statement: a 1ª linha com lineFracs fica na entrada do grupo (first)" "$(tem "$A/src/film-scenes.tsx" 'lf !== undefined && li > 0 && lf > (g.frac ?? 0)')"

echo
if [ "$falhas" = 0 ]; then echo "tudo ok"; else echo "$falhas falha(s)"; fi
[ "$falhas" = 0 ]
