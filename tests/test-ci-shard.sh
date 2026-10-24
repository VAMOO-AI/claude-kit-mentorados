#!/usr/bin/env bash
# Todo teste roda em algum shard do macOS, e em um só?
#
# O job macos do ci.yml divide tests/test-*.sh em shards pelo .github/scripts/ci-shard.sh.
# Errar a divisão não fica vermelho: a suíte que cai fora de todo shard simplesmente não roda
# no Mac, e a que cai em dois roda duas vezes. Este teste prova, na lista real e numa de
# mentira, que a união dos shards é a lista inteira e que nenhum par de shards se sobrepõe. E
# confere que o número de shards da matriz do ci.yml é o mesmo que ele passa ao script.
#
# Uso: bash tests/test-ci-shard.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
S="$RAIZ/.github/scripts/ci-shard.sh"
CI="$RAIZ/.github/workflows/ci.yml"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
falhas=0
check() { if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"; else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi; }
[ -f "$S" ] || { echo "  FALHA $S não existe"; exit 1; }

# uniao <n> <raiz> <prefixo>: grava a lista inteira e cada shard, e confere união e disjunção.
uniao() {
  n="$1"; r="$2"; p="$3"
  (cd "$r" && ls tests/test-*.sh) | LC_ALL=C sort > "$tmp/$p.todos"
  : > "$tmp/$p.uniao"; rc=0
  i=0
  while [ "$i" -lt "$n" ]; do
    bash "$S" "$i" "$n" "$r" > "$tmp/$p.$i" || rc=1
    cat "$tmp/$p.$i" >> "$tmp/$p.uniao"
    i=$((i+1))
  done
  check "$p: o script sai 0 nos $n shards" "$([ "$rc" = 0 ] && echo ok || echo fail)"
  check "$p: a união dos $n shards é a lista inteira ($(wc -l < "$tmp/$p.todos" | tr -d ' ') suítes)" \
    "$(LC_ALL=C sort "$tmp/$p.uniao" | cmp -s - "$tmp/$p.todos" && echo ok || echo fail)"
  check "$p: nenhuma suíte cai em dois shards" \
    "$([ -z "$(LC_ALL=C sort "$tmp/$p.uniao" | uniq -d)" ] && echo ok || echo fail)"
}

echo "== lista de mentira (7 suítes, 3 shards) =="
mkdir -p "$tmp/f/tests"
for t in a b-c b.d cleanup cleanup-head-pr z x; do : > "$tmp/f/tests/test-$t.sh"; done
uniao 3 "$tmp/f" falsa
check "falsa: shard 0 pega o 1º, o 4º e o 7º na ordem de bytes" \
  "$([ "$(tr '\n' ' ' < "$tmp/falsa.0")" = "tests/test-a.sh tests/test-cleanup-head-pr.sh tests/test-z.sh " ] && echo ok || echo fail)"
check "falsa: a mesma entrada dá a mesma divisão" \
  "$(bash "$S" 1 3 "$tmp/f" | cmp -s - "$tmp/falsa.1" && echo ok || echo fail)"
bash "$S" 3 3 "$tmp/f" >/dev/null 2>&1; rc=$?
check "índice fora da faixa (3 de 3) sai 2" "$([ "$rc" = 2 ] && echo ok || echo fail)"

echo "== lista real =="
n_ci="$(awk '/^  macos:/{m=1} m && /shard: \[/{gsub(/[^0-9,]/,""); print split($0, a, ","); exit}' "$CI")"
check "a matriz do job macos declara os shards (veio ${n_ci:-nada})" "$([ -n "$n_ci" ] && [ "$n_ci" -ge 2 ] && echo ok || echo fail)"
check "o job macos passa ao ci-shard.sh o mesmo total da matriz ($n_ci)" \
  "$(grep -qF "ci-shard.sh \"\${{ matrix.shard }}\" ${n_ci:-x}" "$CI" && echo ok || echo fail)"
uniao "${n_ci:-3}" "$RAIZ" real

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
