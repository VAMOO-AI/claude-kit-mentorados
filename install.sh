#!/usr/bin/env bash
#
# Claude Starter Kit — instalador pelo terminal.
#
# O caminho recomendado NÃO precisa de terminal nenhum. Dentro do Claude Code:
#
#     /plugin marketplace add VAMOO-AI/claude-kit-mentorados
#     /plugin install kit-vamoo@vamoo-ai
#     /kit-vamoo:setup
#
# Este script existe pra quem prefere o terminal, ou pra instalar a partir de um
# clone local (sem rede, numa aula, com o repo já baixado). Ele faz exatamente a
# mesma coisa que os três comandos acima:
#
#   1. registra este diretório como marketplace e instala o plugin
#      (skills, comandos, hooks de git e o MCP dotcontext)
#   2. roda o kit-setup.sh, que instala o que um plugin não consegue declarar:
#      CLAUDE.md global, barra de status e preferências
#
#   bash install.sh              # instala
#   bash install.sh --dry-run    # mostra o que faria, não toca em nada
#
set -euo pipefail

KIT_VERSION="0.10.0"
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE="vamoo-ai"
PLUGIN="kit-vamoo"
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Opção desconhecida: $1 (use --dry-run)" >&2; exit 1 ;;
  esac
  shift
done

say()  { printf '\033[1;36m›\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$1"; }

say "Claude Starter Kit v$KIT_VERSION"
[ "$DRY" -eq 1 ] && say "MODO DRY-RUN: nada será modificado."

# ── 1. plugin (skills, comandos, hooks, MCP) ────────────────────────────────
if ! command -v claude >/dev/null 2>&1; then
  warn "Comando 'claude' não encontrado no PATH."
  warn "  Instale o Claude Code antes: https://claude.com/claude-code"
  warn "  Vou seguir só com a parte 2 (CLAUDE.md, barra de status, preferências)."
elif [ "$DRY" -eq 1 ]; then
  echo "  [dry-run] claude plugin marketplace add \"$KIT_DIR\""
  echo "  [dry-run] claude plugin install $PLUGIN@$MARKETPLACE"
else
  say "Registrando o marketplace e instalando o plugin…"
  claude plugin marketplace add "$KIT_DIR" 2>&1 | tail -1
  claude plugin install "$PLUGIN@$MARKETPLACE" 2>&1 | tail -1
  ok "plugin instalado ($(ls -d "$KIT_DIR/plugin/skills"/*/ | wc -l | tr -d ' ') skills, 2 comandos, guard-rails de git, MCP dotcontext)"
fi

# ── 2. o que o plugin não consegue instalar ─────────────────────────────────
echo
if [ "$DRY" -eq 1 ]; then
  bash "$KIT_DIR/plugin/scripts/kit-setup.sh" --dry-run
else
  bash "$KIT_DIR/plugin/scripts/kit-setup.sh"
fi

# ── 3. ctx7 (motor da skill find-docs) ──────────────────────────────────────
echo
if [ "$DRY" -eq 1 ]; then
  say "[dry-run] pularia a instalação do ctx7"
elif command -v npm >/dev/null 2>&1; then
  say "Instalando o ctx7 (busca de documentação oficial)…"
  npm install -g ctx7@latest >/dev/null 2>&1 && ok "ctx7 instalado" \
    || warn "Não consegui instalar o ctx7 global. A skill funciona via 'npx ctx7@latest'."
else
  warn "npm não encontrado — instale o Node.js LTS. A skill find-docs precisa dele."
fi

command -v gh >/dev/null 2>&1 || {
  warn "gh (GitHub CLI) não encontrado — a barra mostrará 'gh✗' e não verá PRs."
  warn "  Instale: https://cli.github.com   •   depois: gh auth login"
}

echo
[ "$DRY" -eq 1 ] && { ok "Dry-run concluído — nada foi modificado."; exit 0; }
ok "Kit instalado! Reinicie o Claude Code."
