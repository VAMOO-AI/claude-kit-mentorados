#!/usr/bin/env bash
# Prova de regressão do cache de dispositivo do plugin/hooks/notify-stop.sh.
#
# O hook Stop roda a cada fim de turno e, até 0.18.0, chamava `system_profiler
# SPAudioDataType` toda vez (1 a 3 s) só para gravar no log para onde o som foi.
# Agora o resultado fica em ~/.claude/.cache/notify-stop/output-device por 10 min.
# O que precisa continuar valendo: a 1ª chamada consulta e grava; a 2ª lê do cache
# e NÃO consulta; cache velho é consultado de novo; e o log continua registrando
# o dispositivo nos dois casos.
#
# O `system_profiler` é falso (só existe no macOS; no CI é Ubuntu) e conta quantas
# vezes foi chamado. `osascript` e `afplay` também são falsos, para o teste não
# tocar som nem abrir notificação na máquina de quem roda.
#
# Uso: bash tests/test-notify-stop-cache.sh [caminho-do-hook]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/notify-stop.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/notify-stop.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"   # o TMPDIR do macOS termina em "/"
trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/system_profiler" <<EOF
#!/usr/bin/env bash
echo x >> "$TMP/chamadas"
cat <<'SAIDA'
Audio:

    Devices:

        MacBook Pro Microphone:

          Default Input Device: Yes
          Input Channels: 1
          Transport: Built-in

        Fone de Teste:

          Default Output Device: Yes
          Default System Output Device: Yes
          Output Channels: 2
          Transport: Bluetooth
SAIDA
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/osascript"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/afplay"
chmod +x "$BIN/system_profiler" "$BIN/osascript" "$BIN/afplay"

FAKE_HOME="$TMP/home"; mkdir -p "$FAKE_HOME"
CACHE="$FAKE_HOME/.claude/.cache/notify-stop/output-device"
LOG="$FAKE_HOME/.claude/logs/notify-stop.log"

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
chamadas() { [ -f "$TMP/chamadas" ] && wc -l < "$TMP/chamadas" | tr -d ' ' || echo 0; }
roda() { printf '{"hook_event_name":"Stop"}' | HOME="$FAKE_HOME" CLAUDE_STOP_QUIET=1 PATH="$BIN:/usr/bin:/bin" bash "$HOOK" >/dev/null 2>&1; }

echo "== 1ª chamada: consulta e grava o cache =="
roda; codigo=$?
check "exit 0"                                   "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
check "system_profiler chamado 1 vez"            "$([ "$(chamadas)" = 1 ] && echo ok || echo fail)"
check "cache gravado com o dispositivo"          "$([ "$(cat "$CACHE" 2>/dev/null)" = "Fone de Teste" ] && echo ok || echo fail)"
check "log registra saida=Fone de Teste"         "$(grep -q 'saida=Fone de Teste' "$LOG" 2>/dev/null && echo ok || echo fail)"

echo "== 2ª chamada: lê do cache, não consulta =="
roda
check "system_profiler continua em 1 chamada"    "$([ "$(chamadas)" = 1 ] && echo ok || echo fail)"
check "log tem 2 linhas, as duas com o dispositivo" \
  "$([ "$(grep -c 'saida=Fone de Teste' "$LOG" 2>/dev/null)" = 2 ] && echo ok || echo fail)"

echo "== cache velho (>10 min): consulta de novo =="
touch -t 202001010000 "$CACHE"
roda
check "system_profiler chamado de novo (2)"      "$([ "$(chamadas)" = 2 ] && echo ok || echo fail)"
check "cache renovado (mtime recente)"           "$([ -n "$(find "$CACHE" -mmin -1 2>/dev/null)" ] && echo ok || echo fail)"

echo "== sem system_profiler (Linux): não quebra, loga '?' =="
rm -rf "$FAKE_HOME/.claude/.cache" "$TMP/chamadas"
SEM="$TMP/bin-linux"; mkdir -p "$SEM"; cp "$BIN/osascript" "$BIN/afplay" "$SEM/"
printf '{"hook_event_name":"Stop"}' | HOME="$FAKE_HOME" CLAUDE_STOP_QUIET=1 PATH="$SEM:/usr/bin:/bin" bash "$HOOK" >/dev/null 2>&1; codigo=$?
check "exit 0"                                   "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
check "não cria cache sem ter o que cachear"     "$([ ! -e "$CACHE" ] && echo ok || echo fail)"
check "log registra saida=?"                     "$(tail -n 1 "$LOG" 2>/dev/null | grep -q 'saida=?' && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
