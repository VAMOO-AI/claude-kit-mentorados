#!/usr/bin/env bash
#
# Aviso sonoro + notificação no fim do turno (hook Stop).
#
# Antes isto era inline no settings.json como `afplay ... & exit 0`. Em background o
# aviso depende do processo sobreviver ao fim do hook, e quando o harness encerra o
# processo do hook o filho morre junto no mesmo grupo — sem erro, sem som. Aqui os
# dois avisos rodam em foreground: a notificação volta em ~100ms e o som tem teto de
# tempo, então o turno atrasa ~1s e o aviso sai sempre.
#
# O log distingue os dois diagnósticos que de fora parecem iguais: "o hook não
# disparou" e "disparou e o aviso não chegou" — este último costuma ser saída de
# áudio (fone Bluetooth pareado leva o som embora com afplay devolvendo 0).
#
# Env: CLAUDE_STOP_SOUND (arquivo), CLAUDE_STOP_SOUND_SECS (teto), CLAUDE_STOP_QUIET=1 (mudo)
set -u

SOUND="${CLAUDE_STOP_SOUND:-/System/Library/Sounds/Glass.aiff}"
MAXSEC="${CLAUDE_STOP_SOUND_SECS:-1.2}"
LOG="$HOME/.claude/logs/notify-stop.log"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

command -v osascript >/dev/null 2>&1 && \
  osascript -e 'display notification "Claude terminou a resposta" with title "Claude Code"' >/dev/null 2>&1

rc="skip"
if [ "${CLAUDE_STOP_QUIET:-0}" != "1" ] && command -v afplay >/dev/null 2>&1 && [ -f "$SOUND" ]; then
  afplay -t "$MAXSEC" "$SOUND" >/dev/null 2>&1
  rc=$?
fi

# `saida` é o dispositivo para onde o som foi: exit 0 com fone pareado é som que
# tocou onde ninguém estava ouvindo, e o log é o único lugar onde isso aparece.
saida="$(system_profiler SPAudioDataType 2>/dev/null | awk '/^ +[A-Za-z].*:$/{d=$0} /Default Output Device: Yes/{gsub(/^ +| *:$/,"",d); print d; exit}')"
printf '%s afplay=%s sound=%s saida=%s cwd=%s\n' \
  "$(date '+%Y-%m-%dT%H:%M:%S')" "$rc" "$(basename "$SOUND")" "${saida:-?}" "$PWD" >> "$LOG" 2>/dev/null || true

# Log de uma linha por turno cresce devagar, mas cresce; corta sem precisar de cron.
if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 500 ]; then
  tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
fi

exit 0
