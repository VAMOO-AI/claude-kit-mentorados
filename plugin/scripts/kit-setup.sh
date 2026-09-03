#!/usr/bin/env bash
#
# Instala o que um plugin do Claude Code NÃO consegue declarar sozinho.
#
# Um plugin entrega skills, comandos, hooks e MCP. Mas o `settings.json` de
# plugin só aceita as chaves `agent` e `subagentStatusLine` — ou seja, ele não
# instala o CLAUDE.md global, a barra de status, o idioma nem a lista de
# permissões. É justamente o miolo do kit. Este script fecha esse buraco.
#
# Roda por dois caminhos e faz a mesma coisa nos dois:
#   • skill /kit-vamoo:setup  (depois do /plugin install)
#   • install.sh              (quem prefere o terminal)
#
#   bash kit-setup.sh              # instala
#   bash kit-setup.sh --dry-run    # mostra o que faria, não toca em nada
#   bash kit-setup.sh --force      # sobrescreve o CLAUDE.md que já existir
#
set -euo pipefail

KIT_VERSION="0.17.2"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$PLUGIN_ROOT/templates"
CLAUDE_DIR="$HOME/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CLAUDE_DIR/backup-kit-$STAMP"
MANIFEST="$CLAUDE_DIR/.kit-manifest"
DRY=0
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --force)   FORCE=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "opção desconhecida: $1" >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '\033[1;36m›\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$1"; }

run() { if [ "$DRY" -eq 1 ]; then echo "  [dry-run] $*"; else "$@"; fi; }

backup() {
  local alvo="$1"
  [ -e "$CLAUDE_DIR/$alvo" ] || return 0
  run mkdir -p "$BACKUP_DIR/$(dirname "$alvo")"
  run cp -R "$CLAUDE_DIR/$alvo" "$BACKUP_DIR/$alvo"
}

[ -d "$TPL" ] || { echo "não achei $TPL — o plugin está incompleto." >&2; exit 1; }
command -v node >/dev/null 2>&1 || {
  warn "node não encontrado — a barra de status e os hooks não funcionam sem ele."
  warn "  Instale o Node.js LTS: https://nodejs.org   (macOS: brew install node)"
}

[ "$DRY" -eq 1 ] && say "MODO DRY-RUN: nada será modificado."
say "Kit v$KIT_VERSION — completando a instalação em $CLAUDE_DIR"
run mkdir -p "$CLAUDE_DIR" "$CLAUDE_DIR/scripts"

# ── CLAUDE.md: é SEU arquivo. Não sobrescreve sem mandado explícito ──────────
if [ -f "$CLAUDE_DIR/CLAUDE.md" ] && [ "$FORCE" -eq 0 ]; then
  run cp "$TPL/CLAUDE-global.md" "$CLAUDE_DIR/CLAUDE.kit.md"
  warn "Você já tem um CLAUDE.md — não mexi nele."
  warn "  O modelo do kit ficou em ~/.claude/CLAUDE.kit.md pra você comparar."
  warn "  Pra trocar pelo do kit: bash kit-setup.sh --force"
else
  backup "CLAUDE.md"
  run cp "$TPL/CLAUDE-global.md" "$CLAUDE_DIR/CLAUDE.md"
  ok "CLAUDE.md instalado  (preencha os <campos> com os seus dados)"
fi

backup "agents.md"
run cp "$TPL/agents.md" "$CLAUDE_DIR/agents.md"
ok "agents.md instalado"

# ── Barra de status ─────────────────────────────────────────────────────────
# Cópia, não link: a barra continua funcionando quando o plugin for atualizado
# ou movido. Rodar o setup de novo atualiza a cópia.
backup "statusline-command.sh"
run cp "$TPL/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
run chmod +x "$CLAUDE_DIR/statusline-command.sh"
backup "scripts/statusline.js"
run cp "$PLUGIN_ROOT/scripts/statusline.js" "$CLAUDE_DIR/scripts/statusline.js"
run cp "$PLUGIN_ROOT/scripts/hookjson.js" "$CLAUDE_DIR/scripts/hookjson.js"
run cp "$PLUGIN_ROOT/scripts/merge-settings.js" "$CLAUDE_DIR/scripts/merge-settings.js"
ok "barra de status instalada (diretório, branch, ↑↓, gh, PR, contexto)"

# ── settings.json: MESCLA, nunca sobrescreve ────────────────────────────────
# O instalador antigo sobrescrevia e quem tinha permissions/env customizados
# perdia tudo com um aviso fácil de não ver. Agora as suas chaves ganham: o kit
# só preenche o que está faltando, e a lista `allow` é a união das duas.
backup "settings.json"
if [ "$DRY" -eq 1 ]; then
  echo "  [dry-run] mesclaria $TPL/settings.json em $CLAUDE_DIR/settings.json"
elif command -v node >/dev/null 2>&1; then
  node "$PLUGIN_ROOT/scripts/merge-settings.js" "$TPL/settings.json" "$CLAUDE_DIR/settings.json"
  ok "settings.json mesclado (as suas chaves foram preservadas)"
else
  warn "sem node — não deu pra mesclar o settings.json. Modelo em $TPL/settings.json"
fi
run rm -f "$CLAUDE_DIR/settings.kit.json"

# ── Fantasmas: o que o kit antigo espalhou em ~/.claude e agora vem do plugin ─
# Sem isso o aluno fica com a skill duas vezes (a de ~/.claude e a do plugin) e
# com o hook rodando em dobro — inclusive a versão velha, já corrigida.
if [ -f "$MANIFEST" ]; then
  say "Removendo o que a instalação antiga deixou (agora vem do plugin)…"
  n=0
  while IFS= read -r linha; do
    case "$linha" in
      skill/*)   rel="skills/${linha#skill/}" ;;
      hook/*)    rel="hooks/${linha#hook/}" ;;
      command/*) rel="commands/${linha#command/}" ;;
      script/*)
        # statusline.js e hookjson.js continuam em ~/.claude — são deste script.
        nome="${linha#script/}"
        case "$nome" in statusline.js|hookjson.js) continue ;; esac
        rel="scripts/$nome" ;;
      *) continue ;;
    esac
    if [ -e "$CLAUDE_DIR/$rel" ]; then
      backup "$rel"
      run rm -rf "$CLAUDE_DIR/$rel"
      n=$((n + 1))
    fi
  done < "$MANIFEST"
  [ "$DRY" -eq 0 ] && rm -f "$MANIFEST"
  ok "$n item(ns) da instalação antiga removido(s) (cópia no backup)"
fi

echo
if [ "$DRY" -eq 1 ]; then ok "Dry-run concluído — nada foi modificado."; exit 0; fi
ok "Pronto."
[ -d "$BACKUP_DIR" ] && say "Seus arquivos antigos: $BACKUP_DIR"
say "Agora abra ~/.claude/CLAUDE.md e preencha os campos <entre-colchetes>."
say "Reinicie o Claude Code pra barra de status aparecer."
