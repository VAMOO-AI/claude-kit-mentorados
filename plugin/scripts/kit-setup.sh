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
# Tudo que o script toca ganha cópia em ~/.claude/backup-kit-<data>/ antes; ficam
# os 3 backups mais recentes. O que você tem em ~/.claude e não quer ver removido
# vai em ~/.claude/.keep-local (um caminho por linha, relativo a ~/.claude, `#`
# comenta, glob simples: `skills/meu-*`). Protege contra remoção — o kit continua
# instalando e atualizando o que é dele.
#
set -euo pipefail

KIT_VERSION="0.22.0"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$PLUGIN_ROOT/templates"
CLAUDE_DIR="$HOME/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CLAUDE_DIR/backup-kit-$STAMP"
MANTER_BACKUPS=3
MANIFEST="$CLAUDE_DIR/.kit-manifest"
KEEP_LOCAL="$CLAUDE_DIR/.keep-local"
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

# protegido <caminho relativo a ~/.claude>: está no .keep-local?
# Cada linha do arquivo é um padrão de `case` (glob simples: * ? [..]); casa o
# caminho inteiro ou uma pasta acima dele — `skills/minha-skill` protege a skill,
# `skills/meu-*` protege todas as suas, `scripts` protege a pasta inteira.
protegido() {
  local rel="$1" linha pat
  [ -f "$KEEP_LOCAL" ] || return 1
  while IFS= read -r linha || [ -n "$linha" ]; do
    pat="${linha%%#*}"                       # comentário até o fim da linha
    pat="${pat#"${pat%%[![:space:]]*}"}"     # espaços à esquerda
    pat="${pat%"${pat##*[![:space:]]}"}"     # e à direita
    pat="${pat#./}"; pat="${pat%/}"
    [ -n "$pat" ] || continue
    # shellcheck disable=SC2254  # o glob é do usuário e tem que expandir
    case "$rel" in $pat|$pat/*) return 0 ;; esac
  done < "$KEEP_LOCAL"
  return 1
}

# Cada execução cria um backup-kit-<data>; sem rotação, ~/.claude acumula um por
# atualização. O nome carrega a data (AAAAMMDD-HHMMSS), então ordem alfabética
# reversa é do mais novo pro mais velho — o desta execução está sempre no topo.
rotaciona_backups() {
  local d n=0 antigos
  # O `true` no fim do grupo importa: sem nenhum backup o glob não casa, o `for`
  # termina em 1 e, com set -e + pipefail, a atribuição derrubava o script — a
  # primeira instalação numa máquina limpa morria calada antes do "Pronto.".
  antigos="$({ for d in "$CLAUDE_DIR"/backup-kit-*/; do [ -d "$d" ] && printf '%s\n' "${d%/}"; done; true; } \
             | sort -r | tail -n +"$((MANTER_BACKUPS + 1))")"
  [ -n "$antigos" ] || return 0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    run rm -rf "$d"
    n=$((n + 1))
  done <<< "$antigos"
  say "$n backup(s) antigo(s) removido(s) — ficam os $MANTER_BACKUPS mais recentes"
  return 0
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
  n=0; m=0
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
    [ -e "$CLAUDE_DIR/$rel" ] || continue
    # O manifesto lista o que o instalador antigo copiou, mas quem editou a
    # cópia (ou tem algo com o mesmo nome) perde trabalho seu. O .keep-local
    # é a palavra final: o que está lá fica.
    if protegido "$rel"; then
      warn "mantido (está no .keep-local): $rel"
      m=$((m + 1))
      continue
    fi
    backup "$rel"
    run rm -rf "$CLAUDE_DIR/$rel"
    n=$((n + 1))
  done < "$MANIFEST"
  [ "$DRY" -eq 0 ] && rm -f "$MANIFEST"
  ok "$n item(ns) da instalação antiga removido(s) (cópia no backup)"
  [ "$m" -gt 0 ] && ok "$m item(ns) mantido(s) pelo ~/.claude/.keep-local"
fi

rotaciona_backups

echo
if [ "$DRY" -eq 1 ]; then ok "Dry-run concluído — nada foi modificado."; exit 0; fi
ok "Pronto."
[ -d "$BACKUP_DIR" ] && say "Seus arquivos antigos: $BACKUP_DIR"
say "Agora abra ~/.claude/CLAUDE.md e preencha os campos <entre-colchetes>."
say "Reinicie o Claude Code pra barra de status aparecer."
