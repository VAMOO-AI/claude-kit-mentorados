#!/usr/bin/env bash
# O frontmatter de cada plugin/agents/*.md é o que o Claude Code lê para rotear e configurar
# o subagente. Sem `name` ou `description` o agente não aparece para o `subagent_type`; um
# `effort` com valor inválido não vira erro visível.
#
# Subagente sem `effort:` herda o effort da sessão: quem trabalha em max paga max em todo
# revisor e todo lote despachado. Decisão de 28/09/2026: o `revisor` e o `executor` do kit
# rodam em `effort: medium`, que no Opus 5.5 é o padrão.
#
# Uso: bash tests/test-agentes-frontmatter.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
DIR="$RAIZ/plugin/agents"
[ -d "$DIR" ] || { echo "plugin/agents/ não encontrado em $RAIZ"; exit 2; }

falhas=0
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

# campo <arquivo> <chave>: valor da chave no frontmatter (entre os dois primeiros ---)
campo() {
  awk -v k="$2" '
    NR==1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v; exit }
  ' "$1"
}

for f in "$DIR"/*.md; do
  n="plugin/agents/$(basename "$f")"
  [ "$(head -1 "$f")" = "---" ] || { falha "$n começa com frontmatter"; continue; }
  [ -n "$(campo "$f" name)" ]        && ok "$n tem name"        || falha "$n tem name"
  [ -n "$(campo "$f" description)" ] && ok "$n tem description" || falha "$n tem description"
  e="$(campo "$f" effort)"
  case "$e" in
    ""|low|medium|high|xhigh|max) ok "$n effort válido (${e:-herda da sessão})" ;;
    *) falha "$n effort '$e' fora de low|medium|high|xhigh|max" ;;
  esac
done

for a in revisor executor; do
  f="$DIR/$a.md"
  if [ ! -f "$f" ]; then falha "plugin/agents/$a.md existe"; continue; fi
  [ "$(campo "$f" name)" = "$a" ] && ok "plugin/agents/$a.md name: $a" || falha "plugin/agents/$a.md name: $a"
  [ "$(campo "$f" effort)" = medium ] && ok "plugin/agents/$a.md effort: medium" \
    || falha "plugin/agents/$a.md effort: medium (tem '$(campo "$f" effort)')"
done

echo
if [ "$falhas" -eq 0 ]; then echo "PASSOU"; exit 0; fi
echo "FALHOU ($falhas)"; exit 1
