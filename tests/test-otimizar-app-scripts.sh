#!/usr/bin/env bash
# Os scripts CDP da otimizar-app rodam e o --compare do layout-snapshot decide certo?
#
# O runtime-bench e o layout-snapshot abrem o Chrome headless, que o CI não tem. O que dá
# para provar sem Chrome é o que mais engana quando quebra: o --compare. É ele que diz
# "0 diferenças" no relatório de "o visual ficou igual"; se passar a aprovar uma caixa
# que mudou, a prova de "sem mudança visual" vira carimbo.
#
# Uso: bash tests/test-otimizar-app-scripts.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
S="$RAIZ/plugin/skills/otimizar-app/scripts"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
falhas=0
check() { # check <descrição> <0|outro>
  if [ "$2" -eq 0 ]; then printf '  ok    %s\n' "$1"; else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
command -v node >/dev/null 2>&1 || { echo "node ausente"; exit 2; }

echo "== os scripts existem e a sintaxe passa =="
for f in cdp.mjs runtime-bench.mjs layout-snapshot.mjs; do
  if [ -f "$S/$f" ]; then node --check "$S/$f" 2>/dev/null; check "$f: node --check" $?
  else check "$f existe em plugin/skills/otimizar-app/scripts/" 1; fi
done

echo "== uso sem URL sai 2, sem abrir o Chrome =="
for f in runtime-bench.mjs layout-snapshot.mjs; do
  [ -f "$S/$f" ] || { check "$f: uso sem URL sai 2" 1; continue; }
  CHROME=/nao/existe node "$S/$f" >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ]; check "$f: uso sem URL sai 2 (veio $rc)" $?
done

echo "== layout-snapshot --compare =="
cat > "$TMP/a.json" <<'JSON'
{"altura":2000,"caixas":[
 {"chave":"HEADER \"\"","top":0,"left":0,"w":1440,"h":80},
 {"chave":"H1 \"Título\"","top":120,"left":40,"w":800,"h":60},
 {"chave":"IMG \"hero\"","top":200,"left":40,"w":600,"h":400}]}
JSON
cp "$TMP/a.json" "$TMP/igual.json"
# a mesma página com 1px de diferença: fica dentro da tolerância padrão (2px)
sed 's/"top":120/"top":121/' "$TMP/a.json" > "$TMP/1px.json"
# um bloco de 150px inserido acima do título: título e imagem descem, a página cresce
python3 - "$TMP/a.json" "$TMP/bloco.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for c in d["caixas"]:
    if c["top"] >= 100: c["top"] += 150
d["altura"] += 150
d["caixas"].insert(1, {"chave": "SECTION \"novo\"", "top": 100, "left": 0, "w": 1440, "h": 150})
json.dump(d, open(sys.argv[2], "w"))
PY
python3 - "$TMP/a.json" "$TMP/sumiu.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["caixas"] = [c for c in d["caixas"] if not c["chave"].startswith("IMG")]
json.dump(d, open(sys.argv[2], "w"))
PY

cmp_() { node "$S/layout-snapshot.mjs" --compare "$@" 2>&1; }
if [ -f "$S/layout-snapshot.mjs" ]; then
  out=$(cmp_ "$TMP/a.json" "$TMP/igual.json"); rc=$?
  [ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^0 diferenças (3 caixas'; check "mesma página: 0 diferenças, sai 0" $?
  out=$(cmp_ "$TMP/a.json" "$TMP/1px.json"); rc=$?
  [ "$rc" = 0 ]; check "1px dentro da tolerância padrão: sai 0" $?
  out=$(cmp_ "$TMP/a.json" "$TMP/1px.json" --tol 0); rc=$?
  [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'mudou.*top 120→121'; check "--tol 0 acusa o 1px e sai 1" $?
  out=$(cmp_ "$TMP/a.json" "$TMP/bloco.json"); rc=$?
  [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'altura da página  2000 → 2150' \
    && printf '%s' "$out" | grep -q '^novo    SECTION' && printf '%s' "$out" | grep -q 'mudou   IMG'
  check "bloco de 150px inserido: altura, caixa nova e caixa que desceu, sai 1" $?
  out=$(cmp_ "$TMP/a.json" "$TMP/sumiu.json"); rc=$?
  [ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^sumiu   IMG'; check "caixa que sumiu é acusada, sai 1" $?
else
  check "layout-snapshot.mjs existe para o --compare" 1
fi

echo "== a skill aponta para os scripts que existem =="
SK="$RAIZ/plugin/skills/otimizar-app"
if [ -f "$SK/SKILL.md" ]; then
  refs=$(grep -rhoE 'skills/otimizar-app/scripts/[a-z-]+\.mjs' "$SK" | sort -u)
  ok=0; for r in $refs; do [ -f "$RAIZ/plugin/$r" ] || { echo "        ausente: $r"; ok=1; }; done
  [ -n "$refs" ] || ok=1
  check "todo caminho de script citado existe ($(printf '%s\n' "$refs" | grep -c .) citados)" $ok
  ! grep -rqE '~/\.claude/skills/' "$SK"; check "nenhum caminho de ~/.claude/skills (no plugin é \${CLAUDE_PLUGIN_ROOT})" $?
else
  check "plugin/skills/otimizar-app/SKILL.md existe" 1
fi

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; exit 0; fi
echo "$falhas falha(s)"; exit 1
