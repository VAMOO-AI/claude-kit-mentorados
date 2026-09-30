#!/usr/bin/env bash
# Imprime um python com numpy (a trilha precisa). Ordem: $MOTION_PY, python3.
for c in "${MOTION_PY:-}" python3; do
  [ -n "$c" ] && "$c" -c "import numpy" 2>/dev/null && { command -v "$c" || echo "$c"; exit 0; }
done
echo "!! nenhum python com numpy: python3 -m venv ~/.venvs/motion && ~/.venvs/motion/bin/pip install numpy; export MOTION_PY=~/.venvs/motion/bin/python" >&2
exit 1
