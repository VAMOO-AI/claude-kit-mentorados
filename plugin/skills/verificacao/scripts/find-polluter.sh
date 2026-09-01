#!/usr/bin/env bash
# Bisseção: qual arquivo de teste cria o arquivo/diretório que não devia existir?
#
#   find-polluter.sh <caminho-que-nao-devia-existir> <glob-dos-testes> [comando-do-runner]
#   find-polluter.sh '.git/index.lock' 'src/**/*.test.ts'
#   find-polluter.sh 'tmp/out.json' 'e2e/*.spec.ts' 'npx playwright test'
#
# Sem o terceiro argumento, o runner é detectado: bun.lock → `bun test`,
# vitest no package.json → `npx vitest run`, senão `npm test --`.
# Roda os arquivos um a um, em ordem, e para no primeiro que produz o alvo.
set -uo pipefail

[ $# -ge 2 ] || { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
ALVO="$1"; PADRAO="$2"; RUNNER="${3:-}"

if [ -e "$ALVO" ]; then
  echo "o alvo '$ALVO' já existe antes de rodar qualquer teste — remova e rode de novo"; exit 2
fi

if [ -z "$RUNNER" ]; then
  if [ -f bun.lock ] || [ -f bun.lockb ]; then RUNNER="bun test"
  elif grep -q '"vitest"' package.json 2>/dev/null; then RUNNER="npx vitest run"
  else RUNNER="npm test --"; fi
fi

shopt -s globstar nullglob
ARQUIVOS=( $PADRAO )
shopt -u globstar nullglob
TOTAL=${#ARQUIVOS[@]}
[ "$TOTAL" -gt 0 ] || { echo "nenhum arquivo casa com '$PADRAO'"; exit 2; }

echo "runner: $RUNNER · $TOTAL arquivo(s) · alvo: $ALVO"
i=0
for f in "${ARQUIVOS[@]}"; do
  i=$((i+1))
  printf '[%d/%d] %s\n' "$i" "$TOTAL" "$f"
  $RUNNER "$f" >/dev/null 2>&1 || true
  if [ -e "$ALVO" ]; then
    echo
    echo "POLUIDOR: $f"
    echo "criou:    $ALVO"
    ls -la "$ALVO" 2>/dev/null
    echo
    echo "próximo passo: $RUNNER $f   # roda só ele e confirme; o fix é no afterEach dele"
    exit 1
  fi
done

echo "nenhum arquivo isolado criou '$ALVO' — a sujeira depende da ordem ou de dois testes juntos"
exit 0
