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
  # `model`: alias, ID completo ou `inherit` (https://code.claude.com/docs/en/sub-agents.md,
  # "Choose a model", lido em 22/11/2026). Valor fora disso não vira erro visível.
  m="$(campo "$f" model)"
  case "$m" in
    ""|inherit|sonnet|opus|haiku|fable|claude-*) ok "$n model válido (${m:-herda da sessão})" ;;
    *) falha "$n model '$m' fora de sonnet|opus|haiku|fable|inherit|claude-<id>" ;;
  esac
done

for a in revisor executor; do
  f="$DIR/$a.md"
  if [ ! -f "$f" ]; then falha "plugin/agents/$a.md existe"; continue; fi
  [ "$(campo "$f" name)" = "$a" ] && ok "plugin/agents/$a.md name: $a" || falha "plugin/agents/$a.md name: $a"
  [ "$(campo "$f" effort)" = medium ] && ok "plugin/agents/$a.md effort: medium" \
    || falha "plugin/agents/$a.md effort: medium (tem '$(campo "$f" effort)')"
done

# Modelo (22/11/2026): subagente sem `model:` roda no modelo da sessão, e em 7 dias 98% das
# requisições de subagente saíram no modelo mais caro (3.983 de 4.070). O `executor` (lote de
# implementação com scope contract) fixa `sonnet`; o `revisor` segue sem `model`, no modelo da
# sessão, porque revisão adversarial é onde o modelo maior paga.
[ "$(campo "$DIR/executor.md" model)" = sonnet ] && ok "plugin/agents/executor.md model: sonnet" \
  || falha "plugin/agents/executor.md model: sonnet (tem '$(campo "$DIR/executor.md" model)')"
[ -z "$(campo "$DIR/revisor.md" model)" ] && ok "plugin/agents/revisor.md sem model: herda o da sessão" \
  || falha "plugin/agents/revisor.md sem model: herda o da sessão (tem '$(campo "$DIR/revisor.md" model)')"
ORQ="$RAIZ/plugin/skills/orquestracao/SKILL.md"
grep -qE '`model` menor' "$ORQ" && grep -qE 'revisão adversarial fica no modelo da sessão' "$ORQ" \
  && ok "orquestracao: diz que modelo vai em cada tipo de dispatch" \
  || falha "orquestracao: diz que modelo vai em cada tipo de dispatch"

# O subagentes.md não chega ao contexto do subagente (é lido pela conversa principal): o que
# o revisor precisa em todo review mora no plugin/agents/revisor.md. O executor abre PR, então
# o push da branch do lote é dele; force push e o resto do que é destrutivo, não (#246, item 5).
tem() { grep -qF -- "$2" "$DIR/$1" && ok "plugin/agents/$1: $3" || falha "plugin/agents/$1: $3"; }
tem revisor.md "grep -rnE '(^|[[:space:]]|[([{>|])!\`'" "traz a varredura de interpolação em SKILL.md"
tem revisor.md "check-then-set" "traz as cinco categorias que revisor costuma pular"
tem revisor.md "git diff origin/main...HEAD" "traz o alvo padrão do review"
tem executor.md "git push -u origin <branch do lote>" "autoriza o push da branch do lote"
grep -qiE 'force[ -]push' "$DIR/executor.md" && ok "plugin/agents/executor.md: force push segue proibido" \
  || falha "plugin/agents/executor.md: force push segue proibido"
# PR que ainda vai receber push nasce rascunho, e sai do rascunho antes do watch do CI: num repo
# que pula rascunho, o watch esperaria checks que nunca vêm (skill `ship`, "Push e PR").
tem executor.md "gh pr create --draft" "abre em rascunho o PR que ainda vai receber push"
tem executor.md "gh pr ready" "tira o PR do rascunho antes de esperar o CI"
SUB="$RAIZ/plugin/templates/subagentes.md"
grep -qF 'Exceção: o `executor`' "$SUB" && ok "subagentes.md: abre a exceção do push do executor" \
  || falha "subagentes.md: abre a exceção do push do executor"

echo
if [ "$falhas" -eq 0 ]; then echo "PASSOU"; exit 0; fi
echo "FALHOU ($falhas)"; exit 1
