#!/usr/bin/env bash
# Prova do scan de skills de projeto e do hook que avisa na abertura da sessão.
#
# O que precisa continuar valendo:
#  · o scan conta chars de description e linhas de corpo, e reprova o que cobra sem
#    servir (name ≠ pasta, corpo vazio, sem description);
#  · projeto dentro do teto sai calado — aviso que aparece sempre é aviso que ninguém lê;
#  · o hook fala UMA VEZ por mudança, não uma por sessão (o /clear re-dispara o
#    SessionStart, e o `npx skills add` de ontem não pode virar o mesmo parágrafo
#    em todas as aberturas);
#  · o hook lê o payload por node, nunca por jq — jq não é pré-requisito de mentorado.
#
# Uso: bash tests/test-skills-projeto.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SCAN="$RAIZ/plugin/scripts/skills-projeto-scan.sh"
HOOK="$RAIZ/plugin/hooks/warn-skills-projeto.sh"
SKILL="$RAIZ/plugin/skills/skills-projeto/SKILL.md"
for f in "$SCAN" "$HOOK" "$SKILL"; do
  [ -f "$f" ] || { echo "não encontrado: $f"; exit 2; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/skills-projeto.XXXXXX")"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
FAKE_HOME="$TMP/home"; mkdir -p "$FAKE_HOME"

falhas=0
check() { if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
          else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi; }

# skill <projeto> <pasta> <name> <description> <linhas-de-corpo>
skill() {
  local d="$1/.claude/skills/$2"; mkdir -p "$d"
  { printf -- '---\nname: %s\ndescription: %s\n---\n\n# %s\n' "$3" "$4" "$2"
    local i=0; while [ "$i" -lt "${5:-0}" ]; do printf 'linha de corpo %s\n' "$i"; i=$((i+1)); done
  } > "$d/SKILL.md"
}
roda_hook() { # roda_hook <projeto>
  printf '{"session_id":"s1","hook_event_name":"SessionStart","cwd":"%s"}' "$1" \
    | HOME="$FAKE_HOME" bash "$HOOK" 2>/dev/null
}

echo "== projeto sem .claude/skills: nem o scan nem o hook falam =="
VAZIO="$TMP/sem-skills"; mkdir -p "$VAZIO"
saida="$(bash "$SCAN" "$VAZIO")"; codigo=$?
check "scan sai 0 em projeto sem skills"   "$([ $codigo -eq 0 ] && echo ok || echo fail)"
check "scan cala em projeto sem skills"    "$([ -z "$saida" ] && echo ok || echo fail)"
saida="$(roda_hook "$VAZIO")"; codigo=$?
check "hook sai 0 em projeto sem skills"   "$([ $codigo -eq 0 ] && echo ok || echo fail)"
check "hook cala em projeto sem skills"    "$([ -z "$saida" ] && echo ok || echo fail)"

echo "== projeto dentro do teto: tabela sim, alarme não =="
BOM="$TMP/bom"
skill "$BOM" deploy-staging deploy-staging "Use ao subir para staging, quando o build passa local e falha no CI." 20
skill "$BOM" webhook-stripe webhook-stripe "Use ao mexer no webhook de pagamento: assinatura, retentativa, idempotência." 30
saida="$(bash "$SCAN" "$BOM")"; codigo=$?
check "scan sai 0 dentro do teto"          "$([ $codigo -eq 0 ] && echo ok || echo fail)"
check "diz que está dentro do teto"        "$(printf '%s' "$saida" | grep -q 'dentro do teto' && echo ok || echo fail)"
check "lista as duas skills"               "$([ "$(printf '%s\n' "$saida" | grep -c '^\(deploy-staging\|webhook-stripe\) ')" = 2 ] && echo ok || echo fail)"
check "mostra o custo estimado por request" "$(printf '%s' "$saida" | grep -q 'tokens por request' && echo ok || echo fail)"
saida="$(roda_hook "$BOM")"
check "hook cala com projeto dentro do teto" "$([ -z "$saida" ] && echo ok || echo fail)"

echo "== name em Title Case não roteia — e o scan diz isso =="
QUEBRADO="$TMP/quebrado"
skill "$QUEBRADO" refactoring Refactoring "Refatoração de código." 10
saida="$(bash "$SCAN" "$QUEBRADO")"; codigo=$?
check "scan sai 1 com skill que não roteia" "$([ $codigo -eq 1 ] && echo ok || echo fail)"
check "aponta name ≠ pasta"                 "$(printf '%s' "$saida" | grep -q 'não roteia' && echo ok || echo fail)"
check "nomeia a skill quebrada"             "$(printf '%s' "$saida" | grep -q 'refactoring' && echo ok || echo fail)"

echo "== casca (corpo vazio) cobra e não ensina: também reprova =="
CASCA="$TMP/casca"
skill "$CASCA" testes testes "Ajuda com testes." 0
saida="$(bash "$SCAN" "$CASCA")"; codigo=$?
check "scan sai 1 com casca"                "$([ $codigo -eq 1 ] && echo ok || echo fail)"
check "chama a casca pelo nome"             "$(printf '%s' "$saida" | grep -q 'casca' && echo ok || echo fail)"

echo "== skill sem description: o modelo não tem como saber quando usar =="
SEMD="$TMP/sem-description"; d="$SEMD/.claude/skills/orfa"; mkdir -p "$d"
printf -- '---\nname: orfa\n---\n\ncorpo\ncom\nvárias\nlinhas\nde texto\n' > "$d/SKILL.md"
saida="$(bash "$SCAN" "$SEMD")"; codigo=$?
check "scan sai 1 sem description"          "$([ $codigo -eq 1 ] && echo ok || echo fail)"
check "diz que falta description"           "$(printf '%s' "$saida" | grep -q 'sem description' && echo ok || echo fail)"

echo "== acima do teto de skills: o total é o alarme, não a skill individual =="
MUITAS="$TMP/muitas"
i=1; while [ "$i" -le 9 ]; do
  skill "$MUITAS" "skill-$i" "skill-$i" "Use quando o caso $i aparecer no projeto." 10
  i=$((i+1))
done
saida="$(bash "$SCAN" "$MUITAS")"; codigo=$?
check "scan sai 1 acima do teto de skills"  "$([ $codigo -eq 1 ] && echo ok || echo fail)"
check "nenhuma skill individual foi acusada" "$(printf '%s' "$saida" | grep -q 'cobram sem servir' && echo fail || echo ok)"
resumo="$(bash "$SCAN" "$MUITAS" --resumo)"
check "resumo do hook aparece acima do teto" "$(printf '%s' "$resumo" | grep -q 'TODA request' && echo ok || echo fail)"

echo "== acima do teto de chars, com poucas skills =="
GORDA="$TMP/gorda"
# Cinco descriptions de ~450 chars: nenhuma sozinha passa do teto individual (500),
# mas o total passa dos 2.000 — que é o caso que o teto por skill não pega.
longa="Use quando $(printf 'o fluxo de cobrança falhar e for preciso reprocessar, %.0s' $(seq 1 8))enfim."
i=1; while [ "$i" -le 5 ]; do skill "$GORDA" "area-$i" "area-$i" "$longa" 10; i=$((i+1)); done
saida="$(bash "$SCAN" "$GORDA")"; codigo=$?
check "scan sai 1 acima do teto de chars"   "$([ $codigo -eq 1 ] && echo ok || echo fail)"
check "mostra o teto na saída"              "$(printf '%s' "$saida" | grep -q 'teto: 8 skills / 2000 chars' && echo ok || echo fail)"

echo "== teto configurável (é orçamento, não lei da física) =="
saida="$(TETO_SKILLS=20 TETO_CHARS=99999 TETO_UMA=99999 bash "$SCAN" "$MUITAS")"; codigo=$?
check "com teto maior, o mesmo projeto passa" "$([ $codigo -eq 0 ] && echo ok || echo fail)"

echo "== o hook fala uma vez por mudança, não uma por sessão =="
rm -rf "$FAKE_HOME"; mkdir -p "$FAKE_HOME"
s1="$(roda_hook "$MUITAS")"
s2="$(roda_hook "$MUITAS")"
s3="$(roda_hook "$MUITAS")"
check "primeira abertura avisa"             "$(printf '%s' "$s1" | grep -q 'skills deste projeto' && echo ok || echo fail)"
check "o aviso diz quanto custa por request" "$(printf '%s' "$s1" | grep -q 'TODA request' && echo ok || echo fail)"
check "/clear e /compact seguintes calam"   "$([ -z "$s2" ] && [ -z "$s3" ] && echo ok || echo fail)"

echo "== instalou mais uma skill: o hook volta a falar =="
sleep 1   # mtime de segundo inteiro
skill "$MUITAS" skill-nova skill-nova "Use quando o caso novo aparecer." 10
s4="$(roda_hook "$MUITAS")"
check "skill nova reabre o aviso"           "$(printf '%s' "$s4" | grep -q 'skills deste projeto' && echo ok || echo fail)"
s5="$(roda_hook "$MUITAS")"
check "e depois cala de novo"               "$([ -z "$s5" ] && echo ok || echo fail)"

echo "== o hook nunca derruba a abertura da sessão =="
codigo=0; roda_hook "$MUITAS" >/dev/null 2>&1 || codigo=$?
check "hook sai 0 mesmo com projeto estourado" "$([ $codigo -eq 0 ] && echo ok || echo fail)"
saida="$(printf 'isso não é json' | HOME="$FAKE_HOME" bash "$HOOK" 2>/dev/null)"; codigo=$?
check "payload inválido não quebra o hook"  "$([ $codigo -eq 0 ] && echo ok || echo fail)"

echo "== jq é proibido neste kit =="
sem_comentario() { grep -v '^[[:space:]]*#' "$1"; }
check "o hook não chama jq"                 "$(sem_comentario "$HOOK" | grep -q '\bjq\b' && echo fail || echo ok)"
check "o scan não chama jq"                 "$(sem_comentario "$SCAN" | grep -q '\bjq\b' && echo fail || echo ok)"
check "o hook lê o payload pelo hookjson.js" "$(grep -q 'hookjson.js' "$HOOK" && echo ok || echo fail)"

echo "== a skill diz o que este kit decidiu não fazer =="
check "a skill não manda gerar skill"       "$(grep -q 'Não gere skill' "$SKILL" && echo ok || echo fail)"
check "a skill avisa do npx skills add"     "$(grep -q 'npx skills add' "$SKILL" && echo ok || echo fail)"
check "a skill avisa que SKILL.md de terceiro pode executar shell" \
  "$(grep -q 'executa shell' "$SKILL" && echo ok || echo fail)"
check "a skill manda registrar em docs/skills.md quando não há .context" \
  "$(grep -q 'docs/skills.md' "$SKILL" && echo ok || echo fail)"
check "o teste de pressão é nota, não gate" "$(grep -q 'nota, não gate' "$SKILL" && echo ok || echo fail)"

echo
[ "$falhas" -eq 0 ] && { echo "tudo verde"; exit 0; }
echo "$falhas falha(s)"; exit 1
