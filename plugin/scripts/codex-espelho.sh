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
# Skills (I9): o Codex e os outros harnesses leem ~/.codex/skills e ~/.agents/skills, onde há
# links como git-sync -> ~/.claude/skills/git-sync. Quando a skill sai de ~/.claude/skills (F7:
# ela passa a vir só do plugin), o link fica pendurado. Para cada entrada <x> com par em
# plugin/skills/<x>:
#   - link pendurado para ~/.claude/skills/<x> → vira CÓPIA de plugin/skills/<x> com o marcador
#     .kit-vamoo-espelho (a versão dentro). Nunca link para o cache: invariante 2;
#   - pasta com o marcador (espelhada antes) → trocada pela versão nova;
#   - pasta sem o marcador → é da pessoa: não toca, só avisa numa linha;
#   - link vivo, ou para outro lugar → fica. Entrada nova nunca é criada.
#
# Só trabalha quando a versão do plugin muda (a espelhada fica em ${CLAUDE_PLUGIN_DATA}, ou em
# ~/.claude/.cache/kit-vamoo sem ele). Copia também o hookjson.js para ~/.codex/scripts, que é
# por onde o guard copiado lê o payload. Fala uma linha por assunto quando age; senão, silêncio.
# Sem ~/.codex/hooks, ~/.codex/skills e ~/.agents/skills, sai sem gravar nada.
# Roda também na máquina do time (sem a guarda de convidado no hooks.json): o kit do time não
# registra este espelho, e um guard já igual ao que o update.sh copiou não é reescrito.
# CODEX_HOME aponta outra pasta (é o que a suíte usa). Fail-open: qualquer erro, exit 0.
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
AGENTS_SKILLS="$HOME/.agents/skills"
[ -d "$CODEX_DIR/hooks" ] || [ -d "$CODEX_DIR/skills" ] || [ -d "$AGENTS_SKILLS" ] || exit 0
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" || exit 0
[ -f "$RAIZ/.claude-plugin/plugin.json" ] || exit 0
VER=$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' "$RAIZ/.claude-plugin/plugin.json" | head -1)
[ -n "$VER" ] || exit 0
ESTADO_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/.cache/kit-vamoo}"
ESTADO="$ESTADO_DIR/codex-espelho.versao"
anterior=""; { IFS= read -r anterior < "$ESTADO"; } 2>/dev/null
[ "$anterior" = "$VER" ] && exit 0

n=0; algum=0
if [ -d "$CODEX_DIR/hooks" ]; then
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
fi

MARCA=.kit-vamoo-espelho
ns=0; nm=0; minhas=""
for base in "$CODEX_DIR/skills" "$AGENTS_SKILLS"; do
  [ -d "$base" ] || continue
  for e in "$base"/*; do
    # O glob devolve o link pendurado, mas o -e dele é falso: o -L é que o segura aqui.
    [ -e "$e" ] || [ -L "$e" ] || continue
    x="${e##*/}"; src="$RAIZ/skills/$x"
    [ -f "$src/SKILL.md" ] || continue
    if [ -L "$e" ]; then
      [ -e "$e" ] && continue                       # link vivo: fica
      alvo="$(readlink "$e" 2>/dev/null)"; alvo="${alvo%/}"
      [ "$alvo" = "$HOME/.claude/skills/$x" ] || continue
    elif [ -d "$e" ]; then
      if [ -f "$e/$MARCA" ]; then
        m=""; { IFS= read -r m < "$e/$MARCA"; } 2>/dev/null
        [ "$m" = "$VER" ] && continue
      else
        nm=$((nm+1)); [ "$nm" -le 3 ] && minhas="$minhas${minhas:+, }${base#"$HOME"/}/$x"
        continue
      fi
    else
      continue
    fi
    # Monta ao lado e troca com dois mv: quem lê a skill nunca a vê pela metade. -L: a cópia
    # leva o conteúdo, nunca um link para dentro do cache versionado.
    novo="$base/.$x.kit-vamoo.$$"; velho="$base/.$x.velho.$$"
    rm -rf "$novo" 2>/dev/null
    if cp -RL "$src" "$novo" 2>/dev/null && printf '%s\n' "$VER" > "$novo/$MARCA" 2>/dev/null; then
      if mv "$e" "$velho" 2>/dev/null; then
        if mv "$novo" "$e" 2>/dev/null; then ns=$((ns+1)); rm -rf "$velho" 2>/dev/null
        else mv "$velho" "$e" 2>/dev/null; fi
      fi
    fi
    rm -rf "$novo" 2>/dev/null
  done
done

mkdir -p "$ESTADO_DIR" 2>/dev/null && printf '%s\n' "$VER" > "$ESTADO" 2>/dev/null
[ "$n" -gt 0 ] && echo "kit-vamoo: $n guard(s) do Codex em $CODEX_DIR/hooks atualizados para a $VER."
[ "$ns" -gt 0 ] && echo "kit-vamoo: $ns skill(s) em ~/.codex/skills e ~/.agents/skills espelhadas do plugin na $VER (cópia com $MARCA)."
[ "$nm" -gt 0 ] && echo "kit-vamoo: $nm pasta(s) de skill sem $MARCA ficam como estão, são suas ($minhas$([ "$nm" -gt 3 ] && echo ', ...'))."
exit 0
