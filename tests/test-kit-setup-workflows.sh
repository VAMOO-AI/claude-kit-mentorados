#!/usr/bin/env bash
# O kit-setup.sh não copia mais os workflows do plugin para ~/.claude/workflows/, e tira a
# cópia que as versões até a 0.90 punham lá.
#
# O Claude Code carrega a pasta workflows/ do plugin sozinho (vira /kit-vamoo:<nome>). A cópia
# em ~/.claude/workflows/ fazia o mesmo workflow aparecer duas vezes, como `kit-vamoo:audit-multidim`
# e como `audit-multidim`. O setup só remove a cópia igual, byte a byte, à do plugin: arquivo
# diferente é edição da pessoa (ou versão antiga) e fica, com aviso. O .keep-local vale aqui
# como em todo o resto.
#
# Uso: bash tests/test-kit-setup-workflows.sh [caminho-do-kit-setup.sh]
set -uo pipefail
SETUP="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/kit-setup.sh}"
[ -f "$SETUP" ] || { echo "script não encontrado: $SETUP"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "sem node — pulando"; exit 0; }
WF="$(cd "$(dirname "$SETUP")/.." && pwd)/workflows/audit-multidim.js"
[ -f "$WF" ] || { echo "workflow do plugin não encontrado: $WF"; exit 2; }

HOME_REAL="$HOME"
falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit-setup-workflows.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

roda_setup() { # roda_setup <home> [args] — saída em <home>.log
  local h="$1"; shift
  case "$h" in
    "$TMP"/*) ;;
    *) echo "GUARDA: HOME '$h' não está sob o temporário — abortando"; exit 2 ;;
  esac
  [ "$h/.claude" = "$HOME_REAL/.claude" ] && { echo "GUARDA: destino é o ~/.claude real — abortando"; exit 2; }
  HOME="$h" bash "$SETUP" "$@" >"$h.log" 2>&1
}

echo "== (a) instalação nova: o setup não cria a cópia =="
A="$TMP/a"; mkdir -p "$A/.claude"
roda_setup "$A"
[ -e "$A/.claude/workflows/audit-multidim.js" ] \
  && falha "o setup copiou o workflow para ~/.claude/workflows (duplica o do plugin)" \
  || ok "sem cópia em ~/.claude/workflows"

echo "== (b) quem já tinha a cópia igual à do plugin: sai, com backup =="
B="$TMP/b"; mkdir -p "$B/.claude/workflows"
cp "$WF" "$B/.claude/workflows/audit-multidim.js"
roda_setup "$B"
[ -e "$B/.claude/workflows/audit-multidim.js" ] \
  && falha "a cópia igual à do plugin ficou" || ok "a cópia igual à do plugin saiu"
if find "$B/.claude" -path '*backup*' -name audit-multidim.js 2>/dev/null | grep -q .; then
  ok "ficou backup da cópia removida"
else
  falha "a cópia saiu sem backup"
fi

echo "== (b0) dry-run não remove =="
B0="$TMP/b0"; mkdir -p "$B0/.claude/workflows"
cp "$WF" "$B0/.claude/workflows/audit-multidim.js"
roda_setup "$B0" --dry-run
[ -e "$B0/.claude/workflows/audit-multidim.js" ] \
  && ok "o dry-run não tocou na cópia" || falha "o dry-run apagou a cópia"

echo "== (c) cópia diferente da do plugin: fica, com aviso =="
C="$TMP/c"; mkdir -p "$C/.claude/workflows"
printf '// editado pela pessoa\n' > "$C/.claude/workflows/audit-multidim.js"
roda_setup "$C"
[ "$(cat "$C/.claude/workflows/audit-multidim.js")" = "// editado pela pessoa" ] \
  && ok "o arquivo editado ficou como estava" || falha "o setup mexeu no arquivo editado"
grep -q "workflows/audit-multidim.js" "$C.log" \
  && ok "o setup avisa que o arquivo ficou" || falha "o setup não avisa do arquivo que ficou"

echo "== (d) workflow de outra origem na mesma pasta não é tocado =="
D="$TMP/d"; mkdir -p "$D/.claude/workflows"
cp "$WF" "$D/.claude/workflows/audit-multidim.js"
printf '// meu\n' > "$D/.claude/workflows/meu-workflow.js"
roda_setup "$D"
[ -f "$D/.claude/workflows/meu-workflow.js" ] \
  && ok "o workflow da pessoa ficou" || falha "o setup apagou um workflow que não é do kit"

echo "== (e) .keep-local segura a cópia =="
E="$TMP/e"; mkdir -p "$E/.claude/workflows"
cp "$WF" "$E/.claude/workflows/audit-multidim.js"
printf 'workflows/audit-multidim.js\n' > "$E/.claude/.keep-local"
roda_setup "$E"
[ -f "$E/.claude/workflows/audit-multidim.js" ] \
  && ok "a cópia no .keep-local ficou" || falha "o setup removeu arquivo do .keep-local"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
