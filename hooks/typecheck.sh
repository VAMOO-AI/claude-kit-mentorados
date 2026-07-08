#!/usr/bin/env bash
# PostToolUse(Edit|Write): roda `tsc --noEmit` no projeto quando um .ts/.tsx é salvo.
# Mostra os primeiros erros de tipo (best-effort). Lê o caminho via node (sem jq).
H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
f="$(cat | node "$H" tool_input.file_path)"
case "$f" in
  *.ts|*.tsx)
    R="$(git -C "$(dirname "$f")" rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$R" ] && [ -f "$R/tsconfig.json" ] && (cd "$R" && npm exec --no -- tsc --noEmit 2>&1 | head -30)
    ;;
esac
true
