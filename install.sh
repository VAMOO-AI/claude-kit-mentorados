#!/usr/bin/env bash
#
# Claude Starter Kit — instalador
# Copia CLAUDE.md, agents.md, statusline, skills, comandos e settings.json
# pro seu ~/.claude e instala o MCP dotcontext (servidor 'dotcontext').
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

KIT_VERSION="0.5.0"
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

say "Instalando o Claude Starter Kit v$KIT_VERSION em: $CLAUDE_DIR"
if [ -f "$MANIFEST" ]; then
  PREV_VERSION="$(awk '/^kit /{print $2; exit}' "$MANIFEST" 2>/dev/null)"
  [ -n "${PREV_VERSION:-}" ] && [ "$PREV_VERSION" != "$KIT_VERSION" ] && \
    say "Atualizando de $PREV_VERSION → $KIT_VERSION (reinstalação completa: conserta hooks/skills antigos)"
fi
say "Backup do que já existir em:        $BACKUP_DIR"
run mkdir -p "$CLAUDE_DIR"

# --- CLAUDE.md ---
backup "CLAUDE.md"
run cp "$KIT_DIR/templates/CLAUDE-global.md" "$CLAUDE_DIR/CLAUDE.md"
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
NEW_MANIFEST="kit $KIT_VERSION $STAMP"$'\n'
for skill_dir in "$KIT_DIR/skills"/*/; do
  skill_name="$(basename "$skill_dir")"
  sync_dir "skills/$skill_name" "$skill_dir"
  NEW_MANIFEST+="skill/$skill_name"$'\n'
done
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

# --- hooks (guard-rails de git: proteção de commit na main + confirmação de comandos perigosos + lint/typecheck) ---
run mkdir -p "$CLAUDE_DIR/hooks"
for hook_file in "$KIT_DIR/hooks"/*; do
  [ -e "$hook_file" ] || continue
  hook_name="$(basename "$hook_file")"
  backup "hooks/$hook_name"
  run cp "$hook_file" "$CLAUDE_DIR/hooks/$hook_name"
  run chmod +x "$CLAUDE_DIR/hooks/$hook_name"
  NEW_MANIFEST+="hook/$hook_name"$'\n'
done
ok "hooks instalados (bloqueio de commit na main, confirmação de rm -rf/DROP/push --force, lint/typecheck)"

# --- scripts (avisos de branch/worktree, limpeza de worktree, barra de status, helper JSON) ---
run mkdir -p "$CLAUDE_DIR/scripts"
for script_file in "$KIT_DIR/scripts"/*; do
  [ -e "$script_file" ] || continue
  script_name="$(basename "$script_file")"
  backup "scripts/$script_name"
  run cp "$script_file" "$CLAUDE_DIR/scripts/$script_name"
  run chmod +x "$CLAUDE_DIR/scripts/$script_name"
  NEW_MANIFEST+="script/$script_name"$'\n'
done
ok "scripts instalados (avisos de branch/worktree + barra de status git/GitHub)"

# --- settings.json (sobrescreve COM backup — reinstalação completa conserta o legado,
#     ex: remove hook tsc antigo que travava cada edição. Sua versão anterior fica no
#     backup; se você tinha permissions/env custom, reaplique a partir de lá) ---
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  backup "settings.json"
  warn "settings.json sobrescrito pelo do kit (sua versão anterior está no backup)."
  warn "  Tinha permissions/env custom? Reaplique a partir de $BACKUP_DIR/settings.json"
fi
run cp "$KIT_DIR/settings.json" "$CLAUDE_DIR/settings.json"
run rm -f "$CLAUDE_DIR/settings.kit.json"   # limpa resíduo de instaladores antigos
ok "settings.json instalado"
NEW_MANIFEST+="file/settings.json"$'\n'

# node é essencial: a barra de status e os hooks (proteção de commit, avisos de branch/worktree,
# lint/typecheck) rodam em node. Os hooks leem o JSON do Claude Code via node — não precisam de jq.
if ! command -v node >/dev/null 2>&1; then
  warn "node não encontrado — a barra de status e os hooks não vão funcionar sem ele."
  warn "  Instale o Node.js LTS: https://nodejs.org   (macOS com brew: brew install node)"
fi
if ! command -v gh >/dev/null 2>&1; then
  warn "gh (GitHub CLI) não encontrado — a barra mostrará 'gh✗' e não verá PRs."
  warn "  Instale: https://cli.github.com   •   depois rode: gh auth login"
fi

# --- Fantasmas: itens que uma instalação anterior colocou mas saíram do kit ---
# (skill/hook/script/command/file órfão → remove com backup. É isto que CONSERTA o
#  legado numa reinstalação — ex: o hook typecheck.sh antigo some de quem já o tinha.)
if [ -f "$MANIFEST" ]; then
  while IFS= read -r line; do
    case "$line" in
      skill/*)   rel="skills/${line#skill/}";     src="$KIT_DIR/skills/${line#skill/}" ;;
      hook/*)    rel="hooks/${line#hook/}";        src="$KIT_DIR/hooks/${line#hook/}" ;;
      script/*)  rel="scripts/${line#script/}";    src="$KIT_DIR/scripts/${line#script/}" ;;
      command/*) rel="commands/${line#command/}";  src="$KIT_DIR/commands/${line#command/}" ;;
      file/*)    rel="${line#file/}";              src="$KIT_DIR/${line#file/}" ;;
      *) continue ;;
    esac
    if [ ! -e "$src" ] && [ -e "$CLAUDE_DIR/$rel" ]; then
      backup "$rel"
      run rm -rf "$CLAUDE_DIR/$rel"
      warn "'$rel' saiu do kit — removi (cópia no backup)"
    fi
  done < "$MANIFEST"
fi

# --- manifesto (registra o que esta instalação colocou em ~/.claude) ---
if [ "$DRY_RUN" -eq 0 ]; then
  printf '%s' "$NEW_MANIFEST" > "$MANIFEST"
fi

# --- ctx7 (motor da skill find-docs) ---
if [ "$DRY_RUN" -eq 1 ]; then
  say "[dry-run] pularia instalação de ctx7 e MCP dotcontext"
else
  if command -v npm >/dev/null 2>&1; then
    say "Instalando o ctx7 (busca de documentação oficial)..."
    npm install -g ctx7@latest >/dev/null 2>&1 && ok "ctx7 instalado" \
      || warn "Não consegui instalar o ctx7 global. A skill ainda funciona via 'npx ctx7@latest'."
  else
    warn "npm não encontrado — instale o Node.js. A skill find-docs precisa dele."
  fi

  # --- MCP dotcontext (servidor 'dotcontext') ---
  if command -v claude >/dev/null 2>&1; then
    # Migração: se existir o server legado 'ai-context' (dotcontext foi renomeado), remove pra não ficar com 2
    if claude mcp list 2>/dev/null | grep -q "ai-context"; then
      claude mcp remove ai-context 2>/dev/null || true
      ok "MCP legado 'ai-context' removido (agora é 'dotcontext')"
    fi
    if claude mcp list 2>/dev/null | grep -q "dotcontext"; then
      ok "MCP dotcontext já estava instalado"
    else
      say "Instalando o MCP dotcontext..."
      claude mcp add dotcontext --scope user -- npx -y @dotcontext/mcp@latest
      ok "MCP dotcontext instalado"
    fi
  else
    warn "Comando 'claude' não encontrado no PATH."
    warn "Instale o MCP manualmente depois com:"
    warn "  claude mcp add dotcontext --scope user -- npx -y @dotcontext/mcp@latest"
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
say "Por fim: abra ~/.claude/CLAUDE.md e preencha os campos <entre-colchetes> com os seus dados."
