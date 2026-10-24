#!/usr/bin/env bash
# PR em rascunho e CI. Há repos que não rodam CI em PR rascunho (os jobs saem SKIPPED) e só
# rodam ao marcar "Ready for review". Num PR rascunho, a ship §2b esperaria checks que nunca
# vêm, ou leria SKIPPED como verde. Este teste exige que a §2b tire o PR do rascunho antes do
# watch e que a §2 abra em rascunho o PR que ainda vai receber push.
#
# Veio do kit do time na F7 (lote 4), quando a ship de lá saiu. A metade que olhava o
# agents/executor.md do time não veio: o executor daqui é outro arquivo, fora deste lote.
#
# Uso: bash tests/test-ship-rascunho.sh [caminho-da-SKILL.md]
set -uo pipefail
SHIP="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/ship/SKILL.md}"
[ -f "$SHIP" ] || { echo "ship/SKILL.md não encontrado: $SHIP"; exit 2; }

falhas=0
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

# secao <prefixo do título>: do "### <prefixo>" até o próximo "## " ou "### "
secao() { awk -v t="$1" 'index($0, t) == 1 { dentro = 1; next } dentro && /^##/ { exit } dentro' "$SHIP"; }

S2=$(awk '/^## 2\. / { dentro = 1; next } dentro && /^##/ { exit } dentro' "$SHIP")
S2B=$(secao "### 2b.")

echo "== ship §2: PR que ainda vai receber push nasce rascunho =="
grep -qF -- "--draft" <<<"$S2" && ok "§2 cita gh pr create --draft" || falha "§2 cita gh pr create --draft"

echo "== ship §2b: rascunho sai antes do watch =="
grep -qF "isDraft" <<<"$S2B" && ok "§2b confere isDraft" || falha "§2b confere isDraft"
grep -qF "gh pr ready" <<<"$S2B" && ok "§2b roda gh pr ready" || falha "§2b roda gh pr ready"
pronto=$(grep -nF "gh pr ready" <<<"$S2B" | head -1 | cut -d: -f1)
watch=$(grep -nF "gh pr checks <n> --watch" <<<"$S2B" | head -1 | cut -d: -f1)
[ -n "$pronto" ] && [ -n "$watch" ] && [ "$pronto" -lt "$watch" ] \
  && ok "§2b: gh pr ready vem antes do watch" || falha "§2b: gh pr ready vem antes do watch"
grep -qF "SKIPPED" <<<"$S2B" && ok "§2b diz que SKIPPED do rascunho não é verde" \
  || falha "§2b diz que SKIPPED do rascunho não é verde"
grep -qF "run novo" <<<"$S2B" && ok "§2b confirma que o run novo apareceu antes do watch" \
  || falha "§2b confirma que o run novo apareceu antes do watch"

echo
if [ "$falhas" -eq 0 ]; then echo "PASSOU"; exit 0; fi
echo "FALHOU ($falhas)"; exit 1
