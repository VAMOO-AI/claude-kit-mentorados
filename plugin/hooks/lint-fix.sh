#!/usr/bin/env bash
# PostToolUse(Edit|Write): roda `eslint --fix` no arquivo salvo, se for JS/TS.
# Silencioso e best-effort — nunca falha o hook. Lê o caminho via node (sem jq).
#
# `--cache` porque o turno ESPERA por isto: medido em 04/09/2026, uma rodada custa
# 0,5–1,2 s por arquivo, e o hook dispara em toda edição de JS/TS. O cache fica em
# ~/.claude/.cache/eslint/ (o do projeto sujaria o repo de quem está aprendendo).
# No hooks.json a entrada é "async": o resultado do lint não muda o que o agente faz
# em seguida, então não há por que segurar o turno.
# Resolve o helper ao lado do próprio script (funciona rodando do plugin) e,
# se não achar, cai pro ~/.claude de quem instalou pelo install.sh.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0
f="$(cat | node "$H" tool_input.file_path)"
case "$f" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs)
    mkdir -p "$HOME/.claude/.cache/eslint" 2>/dev/null
    (cd "$(dirname "$f")" && npm exec --no -- eslint --fix --cache --cache-location "$HOME/.claude/.cache/eslint/" "$f") 2>/dev/null || true
    ;;
esac
exit 0
