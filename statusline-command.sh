#!/bin/bash
# Claude Code statusline — wrapper cross-platform (macOS + Windows/Git Bash).
# A lógica vive em scripts/statusline.js (mostra diretório, branch, dirty,
# ahead/behind, GitHub conectado e PR aberto). O stdin do Claude Code passa direto.
exec node "$HOME/.claude/scripts/statusline.js"
