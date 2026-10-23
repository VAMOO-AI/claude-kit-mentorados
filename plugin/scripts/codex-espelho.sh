#!/usr/bin/env bash
# codex-espelho.sh — SessionStart: leva para o ~/.codex a versão do plugin dos guards que a
# pessoa JÁ pôs lá (pelo codex-optimize.sh ou à mão). Nunca instala guard novo: ter ou não o
# hook no Codex continua sendo decisão de quem roda o codex-optimize.
#
# Por que existe: o Codex roda os hooks de ~/.codex/hooks, e nada pode apontar para o cache
# versionado do plugin (invariante 2 do núcleo único, #241): o cache muda de caminho a cada
# versão e a velha é apagada 14 dias depois. Então o guard é COPIADO, e a cópia envelhecia: em
# 04/09/2026 o ~/.codex do time tinha guards de 13/07, sem o parser de heredoc.
#
# Só trabalha quando a versão do plugin muda (a espelhada fica em ${CLAUDE_PLUGIN_DATA}, ou em
# ~/.claude/.cache/kit-vamoo sem ele). Copia também o hookjson.js para ~/.codex/scripts, que é
# por onde o guard copiado lê o payload. Fala uma linha quando atualiza; senão, silêncio.
# CODEX_HOME aponta outra pasta (é o que a suíte usa). Fail-open: qualquer erro, exit 0.
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
[ -d "$CODEX_DIR/hooks" ] || exit 0
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" || exit 0
[ -f "$RAIZ/.claude-plugin/plugin.json" ] || exit 0
VER=$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' "$RAIZ/.claude-plugin/plugin.json" | head -1)
[ -n "$VER" ] || exit 0
ESTADO_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/.cache/kit-vamoo}"
ESTADO="$ESTADO_DIR/codex-espelho.versao"
anterior=""; { IFS= read -r anterior < "$ESTADO"; } 2>/dev/null
[ "$anterior" = "$VER" ] && exit 0

n=0; algum=0
for h in block-main-commit.sh check-careful.sh block-parallel-clone-switch.sh \
         block-delete-branch-with-children.sh block-cd-leitura-relativa.sh rtk-codex.sh; do
  [ -f "$CODEX_DIR/hooks/$h" ] && [ -f "$RAIZ/hooks/$h" ] || continue
  algum=1
  cmp -s "$RAIZ/hooks/$h" "$CODEX_DIR/hooks/$h" && continue
  # Escreve ao lado e move: o Codex aberto nunca lê o guard pela metade.
  cp "$RAIZ/hooks/$h" "$CODEX_DIR/hooks/.$h.$$" 2>/dev/null \
    && chmod +x "$CODEX_DIR/hooks/.$h.$$" \
    && mv -f "$CODEX_DIR/hooks/.$h.$$" "$CODEX_DIR/hooks/$h" 2>/dev/null && n=$((n+1))
  rm -f "$CODEX_DIR/hooks/.$h.$$" 2>/dev/null
done
if [ "$algum" = 1 ] && [ -f "$RAIZ/scripts/hookjson.js" ] \
   && ! cmp -s "$RAIZ/scripts/hookjson.js" "$CODEX_DIR/scripts/hookjson.js" 2>/dev/null; then
  mkdir -p "$CODEX_DIR/scripts" 2>/dev/null && cp "$RAIZ/scripts/hookjson.js" "$CODEX_DIR/scripts/hookjson.js" 2>/dev/null
fi
mkdir -p "$ESTADO_DIR" 2>/dev/null && printf '%s\n' "$VER" > "$ESTADO" 2>/dev/null
[ "$n" -gt 0 ] && echo "kit-vamoo: $n guard(s) do Codex em $CODEX_DIR/hooks atualizados para a $VER."
exit 0
