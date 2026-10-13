#!/usr/bin/env bash
# Os zips de downloads/ batem com a skill do plugin?
#
# downloads/<nome>.zip é o link fixo para quem instala uma skill avulsa, sem o
# plugin. Zip commitado envelhece calado: a skill muda no plugin e o zip continua
# entregando a versão antiga. Aqui cada zip é regerado pelo scripts/empacotar-skill.sh
# e comparado byte a byte; qualquer diferença reprova com o comando que conserta.
#
# Uso: bash tests/test-downloads-zip.sh
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FALHOU=0

check() { # descricao, condicao (0 = ok)
  if [ "$2" -eq 0 ]; then echo "  ok    $1"; else echo "  FALHA $1"; FALHOU=1; fi
}

echo "== empacotar-skill.sh =="
bash "$RAIZ/scripts/empacotar-skill.sh" mcp-sistema "$TMP/a.zip" >/dev/null
bash "$RAIZ/scripts/empacotar-skill.sh" mcp-sistema "$TMP/b.zip" >/dev/null
cmp -s "$TMP/a.zip" "$TMP/b.zip"; check "duas execuções geram os mesmos bytes" $?
python3 -c "
import sys, zipfile
n = zipfile.ZipFile(sys.argv[1]).namelist()
assert 'mcp-sistema/SKILL.md' in n, n
assert all(x.startswith('mcp-sistema/') for x in n), n
assert not any('.DS_Store' in x or '__MACOSX' in x for x in n), n
" "$TMP/a.zip" 2>/dev/null; check "pasta da skill na raiz, SKILL.md dentro, sem lixo do Finder" $?
bash "$RAIZ/scripts/empacotar-skill.sh" nao-existe "$TMP/x.zip" >/dev/null 2>&1
[ $? -ne 0 ]; check "skill inexistente reprova" $?

echo "== downloads/ em dia com plugin/skills/ =="
achou=0
for z in "$RAIZ"/downloads/*.zip; do
  [ -e "$z" ] || continue
  achou=1
  nome="$(basename "$z" .zip)"
  if [ ! -f "$RAIZ/plugin/skills/$nome/SKILL.md" ]; then
    check "$nome.zip tem skill correspondente em plugin/skills/" 1
    continue
  fi
  bash "$RAIZ/scripts/empacotar-skill.sh" "$nome" "$TMP/$nome.zip" >/dev/null
  if cmp -s "$z" "$TMP/$nome.zip"; then
    check "$nome.zip igual à pasta da skill" 0
  else
    check "$nome.zip igual à pasta da skill (rode: bash scripts/empacotar-skill.sh $nome)" 1
  fi
done
[ "$achou" -eq 1 ]; check "há pelo menos um zip em downloads/" $?

echo
if [ "$FALHOU" -eq 0 ]; then echo "tudo verde"; else echo "FALHOU"; fi
exit "$FALHOU"
