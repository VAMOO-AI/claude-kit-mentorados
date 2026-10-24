#!/usr/bin/env bash
# Imprime as suítes (tests/test-*.sh) do shard <i> de <n>, uma por linha.
#
# O job macos do ci.yml roda a suíte inteira dividida em <n> shards em paralelo. A divisão é
# determinística: a lista em ordem de bytes (LC_ALL=C, igual no macOS e no Ubuntu; o glob
# ordena pelo locale, e o glibc em en_US ignora "-" e "." no primeiro nível) e o índice
# módulo <n>. Teste novo entra num shard sem ninguém editar nada.
# O tests/test-ci-shard.sh prova que a união dos shards é a lista inteira, sem repetição.
#
# Uso: ci-shard.sh <i> <n> [raiz-do-repo]   (0 <= i < n)
set -uo pipefail
i="${1:?uso: ci-shard.sh <i> <n> [raiz]}"
n="${2:?uso: ci-shard.sh <i> <n> [raiz]}"
raiz="${3:-$(cd "$(dirname "$0")/../.." && pwd)}"
case "$i$n" in *[!0-9]*) echo "i e n são inteiros" >&2; exit 2 ;; esac
[ "$n" -ge 1 ] && [ "$i" -lt "$n" ] || { echo "precisa 0 <= i < n (veio i=$i n=$n)" >&2; exit 2; }
(cd "$raiz" && ls tests/test-*.sh) | LC_ALL=C sort | awk -v i="$i" -v n="$n" '(NR - 1) % n == i'
