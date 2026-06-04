#!/usr/bin/env bash
#
# Claude Starter Kit — instalador
# Copia CLAUDE.md, agents.md e settings.json pro seu ~/.claude
# e instala o MCP dot-context (ai-context). Faz backup do que já existir.
#
# Uso:  bash install.sh
#
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"

say()  { printf '\033[1;36m›\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$1"; }

say "Instalando o Claude Starter Kit em: $CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR"

# --- CLAUDE.md (sobrescreve, com backup do antigo) ---
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  cp "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.bak-$STAMP"
  warn "Você já tinha um CLAUDE.md — salvei o antigo em CLAUDE.md.bak-$STAMP"
fi
cp "$KIT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
ok "CLAUDE.md instalado  (edite os <campos> com seus dados depois)"

# --- agents.md (sobrescreve, com backup do antigo) ---
if [ -f "$CLAUDE_DIR/agents.md" ]; then
  cp "$CLAUDE_DIR/agents.md" "$CLAUDE_DIR/agents.md.bak-$STAMP"
  warn "Você já tinha um agents.md — salvei o antigo em agents.md.bak-$STAMP"
fi
cp "$KIT_DIR/AGENTS.md" "$CLAUDE_DIR/agents.md"
ok "agents.md instalado"

# --- statusline (barra com diretório/git/contexto) ---
cp "$KIT_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"
ok "statusline instalada"

# --- skills (find-docs etc.) ---
mkdir -p "$CLAUDE_DIR/skills"
cp -R "$KIT_DIR/skills/." "$CLAUDE_DIR/skills/"
ok "skills instaladas (find-docs)"

# --- slash commands (/revisar, /explicar) ---
mkdir -p "$CLAUDE_DIR/commands"
cp -R "$KIT_DIR/commands/." "$CLAUDE_DIR/commands/"
ok "comandos instalados (/revisar, /explicar)"

# --- settings.json (NÃO sobrescreve se já existir — deixa pra você mesclar) ---
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  cp "$KIT_DIR/settings.json" "$CLAUDE_DIR/settings.kit.json"
  warn "Você já tem um settings.json. Não sobrescrevi."
  warn "O modelo do kit foi salvo em settings.kit.json — compare e mescle à mão."
else
  cp "$KIT_DIR/settings.json" "$CLAUDE_DIR/settings.json"
  ok "settings.json instalado"
fi

# --- ctx7 (motor da skill find-docs) ---
if command -v npm >/dev/null 2>&1; then
  say "Instalando o ctx7 (busca de documentação oficial)..."
  npm install -g ctx7@latest >/dev/null 2>&1 && ok "ctx7 instalado" \
    || warn "Não consegui instalar o ctx7 global. A skill ainda funciona via 'npx ctx7@latest'."
else
  warn "npm não encontrado — instale o Node.js. A skill find-docs precisa dele."
fi

# --- MCP dot-context (ai-context) ---
if command -v claude >/dev/null 2>&1; then
  if claude mcp list 2>/dev/null | grep -q "ai-context"; then
    ok "MCP ai-context (dot-context) já estava instalado"
  else
    say "Instalando o MCP dot-context (ai-context)..."
    claude mcp add ai-context --scope user -- npx -y @ai-coders/context@latest mcp
    ok "MCP ai-context instalado"
  fi
else
  warn "Comando 'claude' não encontrado no PATH."
  warn "Instale o MCP manualmente depois com:"
  warn "  claude mcp add ai-context --scope user -- npx -y @ai-coders/context@latest mcp"
fi

echo
ok "Kit instalado!"
echo
say "FALTA 1 PASSO MANUAL — instalar o plugin superpowers (dentro do Claude Code):"
echo "    1) Abra o Claude Code e rode:  /plugin marketplace add anthropics/claude-plugins-official"
echo "    2) Depois rode:                /plugin install superpowers@claude-plugins-official"
echo
say "Por fim: abra ~/.claude/CLAUDE.md e preencha os campos <entre-colchetes> com os seus dados."
