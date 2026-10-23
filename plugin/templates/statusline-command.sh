#!/bin/bash
# Claude Code statusline — wrapper cross-platform (macOS + Windows/Git Bash).
# A lógica vive em scripts/statusline.js: painel de até 7 linhas ou a linha única do modo
# curto (~/.claude/statusline-modo, que o kit-setup grava). O stdin do Claude Code passa
# direto. Se o node quebrar, a barra mostra [statusline] em vez de sumir.
node "$HOME/.claude/scripts/statusline.js" 2>/dev/null || printf "[statusline]"
