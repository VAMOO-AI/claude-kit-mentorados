#!/usr/bin/env bash
# Imprime o bloco de UMA versão do CHANGELOG: tudo entre `## [<versão>]` e o
# próximo `## [`, sem o próprio cabeçalho e sem as linhas em branco das pontas.
#
# É o corpo da GitHub Release que o release.yml publica. Vive num arquivo, e não
# inline no workflow, para o teste (tests/test-changelog-bloco.sh) rodar
# exatamente o que o CI roda.
#
# Uso: changelog-bloco.sh <versão> [CHANGELOG.md]   → bloco no stdout
# Sai 1, sem nada no stdout, quando a versão não tem bloco no arquivo.
set -uo pipefail
versao="${1:?uso: changelog-bloco.sh <versão> [CHANGELOG.md]}"
arquivo="${2:-CHANGELOG.md}"
[ -f "$arquivo" ] || { echo "$arquivo não encontrado" >&2; exit 2; }

# index() em vez de regex: a versão tem pontos, e o "]" garante que "0.1" não
# casa com "0.19.0". O $( ) come as linhas em branco do fim; as do começo, o awk.
bloco="$(awk -v v="$versao" '
  /^## \[/ {
    if (dentro) exit
    if (index($0, "## [" v "]") == 1) { dentro = 1; next }
  }
  dentro && !comecou && /^[[:space:]]*$/ { next }
  dentro { comecou = 1; print }
' "$arquivo")"

[ -n "$bloco" ] || { echo "CHANGELOG sem bloco para a versão $versao" >&2; exit 1; }
printf '%s\n' "$bloco"
