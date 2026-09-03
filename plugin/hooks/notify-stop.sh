#!/usr/bin/env bash
#
# Aviso sonoro + notificação no fim do turno (hook Stop).
#
# Antes isto era inline no settings.json como `afplay ... & exit 0`. Em background o
# som depende do processo sobreviver ao fim do hook, e quando o harness encerra o
# processo do hook o afplay morre junto no mesmo grupo — sem erro, sem som. Aqui toca
# em foreground com teto de tempo: o turno atrasa ~1s e o som sai sempre.
#
# O log distingue os dois diagnósticos que de fora parecem iguais: "o hook não
# disparou" e "disparou e o som não saiu".
#
# Env: CLAUDE_STOP_SOUND (arquivo), CLAUDE_STOP_SOUND_SECS (teto), CLAUDE_STOP_QUIET=1 (mudo)
set -u

SOUND="${CLAUDE_STOP_SOUND:-/System/Library/Sounds/Glass.aiff}"
MAXSEC="${CLAUDE_STOP_SOUND_SECS:-1.2}"
LOG="$HOME/.claude/logs/notify-stop.log"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

rc="skip"
if [ "${CLAUDE_STOP_QUIET:-0}" != "1" ] && command -v afplay >/dev/null 2>&1 && [ -f "$SOUND" ]; then
  afplay -t "$MAXSEC" "$SOUND" >/dev/null 2>&1
  rc=$?
fi

printf '%s afplay=%s sound=%s cwd=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$rc" "$(basename "$SOUND")" "$PWD" >> "$LOG" 2>/dev/null || true

# Log de uma linha por turno cresce devagar, mas cresce; corta sem precisar de cron.
if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 500 ]; then
  tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
fi

command -v osascript >/dev/null 2>&1 && \
  osascript -e 'display notification "Claude terminou a resposta" with title "Claude Code"' >/dev/null 2>&1 &

exit 0
