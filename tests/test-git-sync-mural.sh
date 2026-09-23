#!/usr/bin/env bash
# Prova do mural da equipe no plugin/skills/git-sync/scripts/git-sync.sh.
#
# O relatório enxerga branch, PR e divergência — nunca o que a outra pessoa precisa
# dizer. Num repo de duas pessoas, o MEMORY.md mudou de formato na main enquanto um PR
# aberto tocava o mesmo arquivo: o aviso só existia na cabeça de quem fez a mudança, e
# o git-sync da outra pessoa reportava "5 atrás" sem dizer que o merge não seria o
# append de sempre.
#
# Os ramos que importam:
#   - repo sem mural: a seção não aparece (quem não adotou não paga nada);
#   - mural com '## Ativos' vazio: não vira aviso (mural zerado é mural em paz);
#   - mural com entrada ativa: sai na seção, entra no contador de avisos, e o que está
#     sob '## Resolvidos' NÃO vaza junto;
#   - AVISOS.md na raiz também é mural.
#
# Uso: bash tests/test-git-sync-mural.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/git-sync/scripts/git-sync.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitsync-mural.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando antes de tocar em /"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

check() { # <esperado-regex> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep -qE "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}

ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"
git init -q --bare "$ORIGIN"
git init -q "$CLONE"
cd "$CLONE" || exit 2
git config user.email t@t; git config user.name t; git config commit.gpgsign false
echo base > base.txt; git add base.txt; git commit -qm base
git branch -M main; git remote add origin "$ORIGIN"; git push -qu origin main

rodar() { bash "$SCRIPT" --status-only --no-pr --no-team --cwd "$CLONE" 2>&1; }
publicar() { git add -A >/dev/null; git commit -qm "$1" >/dev/null; git push -q origin main; }

echo "== repo sem mural =="
out="$(rodar)"
refute 'mural da equipe' 'seção não aparece em repo que não adotou' "$out"
check  'nenhum — pode trabalhar' 'nenhum aviso inventado' "$out"

echo "== mural com Ativos vazio =="
mkdir -p "$CLONE/.context/docs"
printf '# Avisos da equipe\n\n## Ativos\n\n## Resolvidos\n\n### 01/01 — alguem — coisa antiga\n' \
  > "$CLONE/.context/docs/avisos-da-equipe.md"
publicar mural
out="$(rodar)"
refute 'mural da equipe' 'mural zerado não vira seção' "$out"
refute 'coisa antiga' 'histórico resolvido não vaza' "$out"
check  'nenhum — pode trabalhar' 'mural zerado não vira aviso' "$out"

echo "== mural com entrada ativa =="
printf '# Avisos da equipe\n\n## Ativos\n\n### 17/09 — fulano — nao mexa no arquivo X\n\n## Resolvidos\n\n### 01/01 — alguem — coisa antiga\n' \
  > "$CLONE/.context/docs/avisos-da-equipe.md"
publicar ativo
out="$(rodar)"
check  '### mural da equipe' 'seção aparece' "$out"
check  'nao mexa no arquivo X' 'entrada ativa sai no relatório' "$out"
refute 'coisa antiga' 'o que já foi resolvido não vaza junto' "$out"
check  '! mural da equipe em .context/docs/avisos-da-equipe.md' 'entra na seção de avisos' "$out"
check  'ATENÇÃO: [0-9]+ aviso' 'conta no total que bloqueia o início' "$out"

echo "== caminho alternativo AVISOS.md na raiz =="
rm "$CLONE/.context/docs/avisos-da-equipe.md"
printf '# Avisos\n\n## Ativos\n\n### hoje — fulano — aviso da raiz\n' > "$CLONE/AVISOS.md"
publicar raiz
out="$(rodar)"
check  'mural da equipe \(AVISOS.md\)' 'acha o mural na raiz' "$out"
check  'aviso da raiz' 'imprime a entrada' "$out"

if [ "$falhas" -eq 0 ]; then echo "OK — mural da equipe"; else echo "FALHAS: $falhas"; fi
exit "$falhas"
