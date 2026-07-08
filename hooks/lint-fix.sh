#!/usr/bin/env bash
# PostToolUse(Edit|Write): roda `eslint --fix` no arquivo salvo, se for JS/TS.
# Silencioso e best-effort — nunca falha o hook. Lê o caminho via node (sem jq).
H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
f="$(cat | node "$H" tool_input.file_path)"
case "$f" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs)
    (cd "$(dirname "$f")" && npm exec --no -- eslint --fix "$f") 2>/dev/null || true
    ;;
esac
exit 0
