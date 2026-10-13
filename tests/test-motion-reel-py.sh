#!/usr/bin/env bash
# py.sh da motion-reel: acha o venv que a própria mensagem de erro ensina a criar.
#
# A mensagem manda criar ~/.venvs/motion com numpy, mas o py.sh só tentava $MOTION_PY e
# python3; sem exportar a variável em toda sessão, o new.sh falhava num Mac cujo python3
# não tem numpy. Este teste usa HOME temporário e pythons falsos no PATH:
#
#   1. sem MOTION_PY, acha $HOME/.venvs/motion/bin/python antes do python3 sem numpy;
#   2. no Windows (Git Bash) o venv tem outro layout: acha .venvs/motion/Scripts/python.exe;
#   3. MOTION_PY continua tendo prioridade;
#   4. sem venv e sem numpy, sai 1 com a mesma mensagem de como criar o venv.
#
# Uso: bash tests/test-motion-reel-py.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
PYSH="$RAIZ/plugin/skills/motion-reel/scripts/py.sh"
[ -f "$PYSH" ] || { echo "py.sh não encontrado em $PYSH"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/motion-py.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
falso() { # falso <caminho> <0|1>: python falso cujo "import numpy" sai com o código dado
  mkdir -p "$(dirname "$1")"; printf '#!/usr/bin/env bash\nexit %s\n' "$2" > "$1"; chmod +x "$1"
}
falso "$TMP/bin/python3" 1                        # python3 do sistema sem numpy
falso "$TMP/home/.venvs/motion/bin/python" 0      # venv criado como a mensagem ensina
falso "$TMP/win/.venvs/motion/Scripts/python.exe" 0  # o mesmo venv criado no Windows
falso "$TMP/outro/python" 0                       # MOTION_PY explícito
mkdir -p "$TMP/vazio"                             # HOME sem venv
PATHT="$TMP/bin:/usr/bin:/bin"

out="$(env -u MOTION_PY HOME="$TMP/home" PATH="$PATHT" bash "$PYSH" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "$TMP/home/.venvs/motion/bin/python" ] && r=ok || r=fail
check "sem MOTION_PY acha o venv fixo (rc=$rc, saída: $out)" $r

out="$(env -u MOTION_PY HOME="$TMP/win" PATH="$PATHT" bash "$PYSH" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "$TMP/win/.venvs/motion/Scripts/python.exe" ] && r=ok || r=fail
check "no layout do Windows acha Scripts/python.exe (rc=$rc, saída: $out)" $r

out="$(MOTION_PY="$TMP/outro/python" HOME="$TMP/home" PATH="$PATHT" bash "$PYSH" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "$TMP/outro/python" ] && r=ok || r=fail
check "MOTION_PY tem prioridade (rc=$rc, saída: $out)" $r

out="$(env -u MOTION_PY HOME="$TMP/vazio" PATH="$PATHT" bash "$PYSH" 2>&1)"; rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | /usr/bin/grep -qF 'python3 -m venv ~/.venvs/motion' && r=ok || r=fail
check "sem venv nem numpy sai 1 e ensina a criar o venv (rc=$rc)" $r

[ "$falhas" -eq 0 ] && { echo "OK: py.sh acha o venv fixo"; exit 0; }
echo "$falhas falha(s)"; exit 1
