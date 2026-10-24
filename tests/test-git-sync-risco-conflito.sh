#!/usr/bin/env bash
# Prova do "risco de conflito" do modo time no plugin/skills/git-sync/scripts/git-sync.sh.
#
# O falso positivo que o kit do time mediu em 17/09/2026: a branch tinha a merge-base
# EXATAMENTE no tip de origin/main (já continha o PR mergeado 12h antes), e o relatório
# mandou "sincronize com origin/main antes de mexer nestes: 9 arquivos". Sincronizar era
# impossível: a branch já estava sincronizada.
#
# A causa lá era um fallback para a janela de atividade: com a base no tip, o lado "deles"
# (`diff base..origin/main`) é vazio POR CONSTRUÇÃO, e o script caía na lista de tudo que a
# default tocou nos últimos N dias, commits que a sua branch JÁ CONTÉM. Quem corrige o PR que
# acabou de entrar mexe nos mesmos arquivos dele, então todo arquivo seu colidia consigo mesmo.
# O script daqui nunca teve esse fallback; esta suíte é a guarda para ele não entrar.
#
# Se a sua base contém o commit, o conteúdo dele já está no seu arquivo: não existe conflito
# a evitar, e "sincronize antes de mexer" é conselho que não se pode seguir.
#
# Os ramos que importam:
#   - base == tip da default: nunca sobreposição, mesmo mexendo no que a default tocou, e a
#     seção diz que não há nada a sincronizar;
#   - base ATRÁS da default, arquivo tocado dos dois lados: sobreposição de verdade;
#   - base atrás, arquivos disjuntos: sem sobreposição.
#
# Uso: bash tests/test-git-sync-risco-conflito.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/git-sync/scripts/git-sync.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gitsync-risco.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando antes de tocar em /"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

check() { # <esperado-regex> <descrição> <saída>
  if printf '%s' "$3" | grep >/dev/null -E "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não casou: %s)\n' "$2" "$1"; falhas=$((falhas+1)); fi
}
refute() { # <regex-proibido> <descrição> <saída>
  if printf '%s' "$3" | grep >/dev/null -E "$1"; then printf '  FALHA %s (apareceu: %s)\n' "$2" "$1"; falhas=$((falhas+1))
  else printf '  ok    %s\n' "$2"; fi
}
# só a seção do risco: o "⚠" e o "sincronize" não podem vir de outro canto do relatório
risco() { printf '%s\n' "$1" | awk '/^--- risco de conflito/ { d = 1; print; next } d && /^(---|###|-{20,})/ { exit } d'; }

ORIGIN="$TMP/origin.git"; CLONE="$TMP/clone"
git init -q --bare "$ORIGIN"
git init -q "$CLONE"
cd "$CLONE" || exit 2
git config user.email t@t; git config user.name t; git config commit.gpgsign false
mkdir -p src
echo base > src/kpis.ts
echo base > src/outro.ts
git add src; git commit -qm base
git branch -M main; git remote add origin "$ORIGIN"; git push -qu origin main

# O commit da default: o análogo do PR mergeado 12h antes.
echo "feature da outra pessoa" >> src/kpis.ts
git commit -qam "feat: mexe no kpis.ts"
git push -q origin main

# Modo time precisa de 2+ autores na default para ligar sozinho; aqui vai forçado.
rodar() { env -u GH_TOKEN -u GITHUB_TOKEN bash "$SCRIPT" --status-only --no-pr --no-gh --team --cwd "$CLONE" 2>&1; }

echo "== base == tip da default: nada a sincronizar =="
git checkout -q -b fix/em-cima-do-tip
echo "meu fix" >> src/kpis.ts
git commit -qam "fix: corrige o que a feature introduziu"
OUT="$(risco "$(rodar)")"
check  'risco de conflito'                         "a seção de risco aparece"                      "$OUT"
refute '⚠'                                         "branch em cima do tip não acusa sobreposição" "$OUT"
check  'em dia com origin/main — nada a sincronizar' "a seção diz que não há nada a sincronizar"   "$OUT"

echo
echo "== base ATRÁS da default: sobreposição de verdade continua aparecendo =="
git checkout -q -b fix/atras-mesmo-arquivo main~1
echo "meu fix" >> src/kpis.ts
git commit -qam "fix: mexe no mesmo arquivo, a partir de uma base velha"
OUT="$(risco "$(rodar)")"
check  '⚠ src/kpis\.ts'                            "base atrás + mesmo arquivo acusa sobreposição" "$OUT"
check  'sincronize com origin/main'                "manda sincronizar antes de mexer"              "$OUT"
refute 'nada a sincronizar'                        "não diz que está em dia"                       "$OUT"

echo
echo "== base atrás, arquivos disjuntos: sem sobreposição =="
git checkout -q -b fix/atras-outro-arquivo main~1
echo "meu fix" >> src/outro.ts
git commit -qam "fix: mexe em arquivo que a default não tocou"
OUT="$(risco "$(rodar)")"
refute '⚠'                                         "arquivos disjuntos não acusam sobreposição"    "$OUT"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
