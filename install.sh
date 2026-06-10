#!/usr/bin/env bash
#
# Claude Starter Kit — instalador
# Copia CLAUDE.md, agents.md, statusline, skills, comandos e settings.json
# pro seu ~/.claude e instala o MCP dot-context (ai-context).
#
# Antes de sobrescrever QUALQUER coisa, salva uma cópia em
# ~/.claude/backup-kit-<data>/ — pra desinstalar, basta restaurar de lá.
#
# Uso:
#   bash install.sh                    # instala
#   bash install.sh --dry-run          # só mostra o que faria, não toca em nada
#   bash install.sh --backup-dir DIR   # backup em outro lugar
#
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CLAUDE_DIR/backup-kit-$STAMP"
MANIFEST="$CLAUDE_DIR/.kit-manifest"
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --backup-dir) BACKUP_DIR="${2:?--backup-dir precisa de um caminho}"; shift ;;
    *) echo "Opção desconhecida: $1 (use --dry-run ou --backup-dir DIR)" >&2; exit 1 ;;
  esac
  shift
done

say()  { printf '\033[1;36m›\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$1"; }

# Em dry-run, só imprime o que faria. Fora dele, executa.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

# Salva uma cópia de $1 (arquivo ou pasta dentro de ~/.claude) no backup,
# preservando o caminho relativo. Não faz nada se o alvo não existir.
backup() {
  local target="$1"
  [ -e "$CLAUDE_DIR/$target" ] || return 0
  run mkdir -p "$BACKUP_DIR/$(dirname "$target")"
  run cp -R "$CLAUDE_DIR/$target" "$BACKUP_DIR/$target"
}

# Substitui a pasta ~/.claude/$1 pela versão do kit (sync determinístico:
# arquivos removidos do kit somem da cópia instalada — sem "skill fantasma").
sync_dir() {
  local target="$1" src="$2"
  backup "$target"
  run rm -rf "$CLAUDE_DIR/$target"
  run mkdir -p "$(dirname "$CLAUDE_DIR/$target")"
  run cp -R "$src" "$CLAUDE_DIR/$target"
}

if [ "$DRY_RUN" -eq 1 ]; then
  say "MODO DRY-RUN: nada será modificado. Ações que seriam executadas:"
fi

say "Instalando o Claude Starter Kit em: $CLAUDE_DIR"
say "Backup do que já existir em:        $BACKUP_DIR"
run mkdir -p "$CLAUDE_DIR"

# --- CLAUDE.md ---
backup "CLAUDE.md"
run cp "$KIT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
ok "CLAUDE.md instalado  (edite os <campos> com seus dados depois)"

# --- agents.md ---
backup "agents.md"
run cp "$KIT_DIR/AGENTS.md" "$CLAUDE_DIR/agents.md"
ok "agents.md instalado"

# --- statusline (barra com diretório/git/contexto) ---
backup "statusline-command.sh"
run cp "$KIT_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
run chmod +x "$CLAUDE_DIR/statusline-command.sh"
ok "statusline instalada"

# --- skills ---
# Só mexe nas skills QUE VÊM DO KIT. Skills suas que não são do kit ficam intactas.
run mkdir -p "$CLAUDE_DIR/skills"
NEW_MANIFEST="kit $STAMP"$'\n'
for skill_dir in "$KIT_DIR/skills"/*/; do
  skill_name="$(basename "$skill_dir")"
  sync_dir "skills/$skill_name" "$skill_dir"
  NEW_MANIFEST+="skill/$skill_name"$'\n'
done
# Skill fantasma: estava no manifesto de uma instalação anterior, mas saiu do kit.
if [ -f "$MANIFEST" ]; then
  while IFS= read -r line; do
    case "$line" in
      skill/*)
        old_skill="${line#skill/}"
        if [ ! -d "$KIT_DIR/skills/$old_skill" ] && [ -d "$CLAUDE_DIR/skills/$old_skill" ]; then
          backup "skills/$old_skill"
          run rm -rf "$CLAUDE_DIR/skills/$old_skill"
          warn "skill '$old_skill' saiu do kit — removi (cópia no backup)"
        fi
        ;;
    esac
  done < "$MANIFEST"
fi
ok "skills instaladas ($(ls -d "$KIT_DIR/skills"/*/ | wc -l | tr -d ' ') skills)"

# --- slash commands (/revisar, /explicar) ---
run mkdir -p "$CLAUDE_DIR/commands"
for cmd_file in "$KIT_DIR/commands"/*; do
  cmd_name="$(basename "$cmd_file")"
  backup "commands/$cmd_name"
  run cp "$cmd_file" "$CLAUDE_DIR/commands/$cmd_name"
  NEW_MANIFEST+="command/$cmd_name"$'\n'
done
ok "comandos instalados (/revisar, /explicar)"

# --- settings.json (NÃO sobrescreve se já existir — deixa pra você mesclar) ---
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  run cp "$KIT_DIR/settings.json" "$CLAUDE_DIR/settings.kit.json"
  warn "Você já tem um settings.json. Não sobrescrevi."
  warn "O modelo do kit foi salvo em settings.kit.json — compare e mescle à mão."
else
  run cp "$KIT_DIR/settings.json" "$CLAUDE_DIR/settings.json"
  ok "settings.json instalado"
fi

# --- manifesto (registra o que esta instalação colocou em ~/.claude) ---
if [ "$DRY_RUN" -eq 0 ]; then
  printf '%s' "$NEW_MANIFEST" > "$MANIFEST"
fi

# --- ctx7 (motor da skill find-docs) ---
if [ "$DRY_RUN" -eq 1 ]; then
  say "[dry-run] pularia instalação de ctx7 e MCP ai-context"
else
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
fi

echo
if [ "$DRY_RUN" -eq 1 ]; then
  ok "Dry-run concluído — nada foi modificado."
  exit 0
fi
ok "Kit instalado!"
if [ -d "$BACKUP_DIR" ]; then
  say "Seus arquivos antigos estão em: $BACKUP_DIR"
fi
echo
say "FALTA 1 PASSO MANUAL — instalar o plugin superpowers (dentro do Claude Code):"
echo "    1) Abra o Claude Code e rode:  /plugin marketplace add anthropics/claude-plugins-official"
echo "    2) Depois rode:                /plugin install superpowers@claude-plugins-official"
echo
say "Por fim: abra ~/.claude/CLAUDE.md e preencha os campos <entre-colchetes> com os seus dados."
