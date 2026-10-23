#!/usr/bin/env bash
# O modo da barra (0.77.0): painel de até 7 linhas ou a linha única de antes. Quem decide é a
# configuração, ~/.claude/statusline-modo, que o kit-setup grava com `--statusline
# curto|painel`. Instalação nova sem a opção fica no painel, sem gravar nada. Quem já tinha a
# barra (scripts/statusline.js instalado) e nunca escolheu ganha `curto`: ninguém tem a barra
# trocada sem pedir. Escolha gravada fica de um setup para o outro.
#
# E o wrapper: o statusline-command.sh passa o stdin para o .js e, se o node quebrar, mostra
# `[statusline]` em vez de barra sumida.
#
# Uso: bash tests/test-kit-setup-statusline.sh [caminho-do-kit-setup.sh]
set -uo pipefail
SETUP="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/kit-setup.sh}"
[ -f "$SETUP" ] || { echo "script não encontrado: $SETUP"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "sem node — pulando"; exit 0; }

HOME_REAL="$HOME"
falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit-setup-statusline.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
unset CLAUDE_STATUSLINE_MODO CLAUDE_WHO

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

roda_setup() { # roda_setup <home> [args] — saída em <home>.log, devolve o exit
  local h="$1"; shift
  case "$h" in
    "$TMP"/*) ;;
    *) echo "GUARDA: HOME '$h' não está sob o temporário — abortando"; exit 2 ;;
  esac
  [ "$h/.claude" = "$HOME_REAL/.claude" ] && { echo "GUARDA: destino é o ~/.claude real — abortando"; exit 2; }
  HOME="$h" bash "$SETUP" "$@" >"$h.log" 2>&1
}
modo() { head -1 "$1/.claude/statusline-modo" 2>/dev/null; }
ja_tinha_barra() { mkdir -p "$1/.claude/scripts"; printf '// barra de antes\n' > "$1/.claude/scripts/statusline.js"; }

echo "== qual modo o setup grava =="
A="$TMP/novo"; mkdir -p "$A"
roda_setup "$A"
[ ! -e "$A/.claude/statusline-modo" ] && ok "instalação nova sem a opção: não grava (fica no painel)" || falha "instalação nova gravou o modo '$(modo "$A")'"

B="$TMP/upgrade"; ja_tinha_barra "$B"
roda_setup "$B"
[ "$(modo "$B")" = curto ] && ok "quem já tinha a barra e nunca escolheu: grava curto" || falha "upgrade gravou '$(modo "$B")', esperado curto"
roda_setup "$B"
[ "$(modo "$B")" = curto ] && ok "rodar de novo mantém curto" || falha "segunda rodada mudou para '$(modo "$B")'"

C="$TMP/upgrade-painel"; ja_tinha_barra "$C"
roda_setup "$C" --statusline painel
[ "$(modo "$C")" = painel ] && ok "--statusline painel no upgrade: grava painel" || falha "gravou '$(modo "$C")', esperado painel"
roda_setup "$C"
[ "$(modo "$C")" = painel ] && ok "escolha gravada fica no setup seguinte" || falha "setup sem opção trocou para '$(modo "$C")'"

D="$TMP/igual"; mkdir -p "$D"
roda_setup "$D" --statusline=curto
[ "$(modo "$D")" = curto ] && ok "--statusline=curto também vale" || falha "gravou '$(modo "$D")', esperado curto"

E="$TMP/invalido"; mkdir -p "$E"
roda_setup "$E" --statusline grande; rc=$?
[ "$rc" -eq 2 ] && ok "valor inválido sai 2" || falha "valor inválido saiu $rc"
[ ! -e "$E/.claude/statusline-modo" ] && ok "valor inválido não grava" || falha "valor inválido gravou '$(modo "$E")'"
grep -q 'curto|painel' "$E.log" && ok "a mensagem diz os valores aceitos" || falha "a mensagem não diz curto|painel: $(cat "$E.log")"

F="$TMP/dry"; ja_tinha_barra "$F"
roda_setup "$F" --dry-run --statusline painel
[ ! -e "$F/.claude/statusline-modo" ] && ok "--dry-run não grava o modo" || falha "--dry-run gravou '$(modo "$F")'"

echo "== o wrapper =="
P='{"session_id":"s1","model":{"display_name":"Opus 5.5"},"workspace":{"current_dir":"/tmp"},"cost":{"total_cost_usd":1.2,"total_duration_ms":60000}}'
saida="$(cd "$TMP" && printf '%s' "$P" | HOME="$A" bash "$A/.claude/statusline-command.sh")"
case "$saida" in *"Opus 5.5"*) ok "o stdin chega ao .js (painel mostra o modelo)" ;; *) falha "saída sem o modelo: $saida" ;; esac
[ "$(printf '%s\n' "$saida" | wc -l | tr -d ' ')" -gt 1 ] && ok "sem modo gravado, painel (mais de uma linha)" || falha "sem modo gravado saiu uma linha só"

saida="$(cd "$TMP" && printf '%s' "$P" | HOME="$B" bash "$B/.claude/statusline-command.sh")"
[ "$(printf '%s\n' "$saida" | wc -l | tr -d ' ')" -eq 1 ] && ok "modo curto gravado: uma linha" || falha "modo curto saiu $(printf '%s\n' "$saida" | wc -l) linhas"

printf 'process.exit(3)\n' > "$A/.claude/scripts/statusline.js"
saida="$(printf '%s' "$P" | HOME="$A" bash "$A/.claude/statusline-command.sh" 2>&1)"; rc=$?
[ "$saida" = "[statusline]" ] && [ "$rc" -eq 0 ] && ok "node quebrado: mostra [statusline] e sai 0" || falha "node quebrado: rc=$rc saída='$saida'"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
