#!/usr/bin/env bash
# Empacota uma skill do plugin em downloads/<nome>.zip, para quem instala a skill
# avulsa (sem o plugin) baixar por um link fixo do GitHub.
#
# O zip é determinístico: arquivos em ordem, data fixa e sem .DS_Store/__MACOSX.
# Rodar de novo sem mudar a skill gera os mesmos bytes, e é isso que o
# tests/test-downloads-zip.sh confere: zip velho em relação à pasta reprova o CI.
#
# Ferramenta de quem mantém o kit: fica em scripts/ na raiz, fora do plugin/.
#
# Uso:
#   bash scripts/empacotar-skill.sh mcp-sistema            # grava downloads/mcp-sistema.zip
#   bash scripts/empacotar-skill.sh mcp-sistema /tmp/x.zip # grava em outro caminho
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
NOME="${1:-}"
[ -n "$NOME" ] || { echo "uso: $0 <skill> [saida.zip]" >&2; exit 2; }
SRC="$RAIZ/plugin/skills/$NOME"
[ -f "$SRC/SKILL.md" ] || { echo "✗ skill não encontrada: plugin/skills/$NOME/SKILL.md" >&2; exit 1; }
OUT="${2:-$RAIZ/downloads/$NOME.zip}"
mkdir -p "$(dirname "$OUT")"

python3 - "$SRC" "$NOME" "$OUT" <<'PY'
import os, sys, zipfile
src, nome, out = sys.argv[1:4]
IGNORA = {".DS_Store", "__pycache__", "__MACOSX"}
arquivos = []
for raiz, dirs, files in os.walk(src):
    dirs[:] = sorted(d for d in dirs if d not in IGNORA)
    for f in sorted(files):
        if f in IGNORA or f.endswith(".pyc"):
            continue
        arquivos.append(os.path.join(raiz, f))
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for p in arquivos:
        info = zipfile.ZipInfo(os.path.join(nome, os.path.relpath(p, src)), date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = (0o755 if os.access(p, os.X_OK) else 0o644) << 16
        with open(p, "rb") as fh:
            z.writestr(info, fh.read())
print(f"✓ {out} ({len(arquivos)} arquivos)")
PY
