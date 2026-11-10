#!/usr/bin/env bash
# scripts/promover-stable.sh só avança o canal estável, e só com --push.
#
# Uso: bash tests/test-promover-stable.sh
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/promover-stable.sh"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/promover-stable.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# Remote de mentira: main com três releases, stable parado na primeira.
git init -q --bare "$TMP/remoto.git"
git init -q -b main "$TMP/clone"
g() { git -C "$TMP/clone" -c user.name=t -c user.email=t@t.invalid "$@"; }
g remote add origin "$TMP/remoto.git"
for v in 0.1.0 0.2.0 0.3.0; do
  echo "$v" > "$TMP/clone/versao"; g add versao; g commit -q -m "release: $v"; g tag "v$v"
done
g push -q origin main --tags
g push -q origin "v0.1.0^{commit}:refs/heads/stable"
remoto() { git -C "$TMP/remoto.git" rev-parse "$1^{commit}"; }
roda() { ( cd "$TMP/clone" && bash "$SCRIPT" "$@" ) > "$TMP/out" 2>&1; echo $?; }

echo "== sem --push: confere e não envia =="
rc=$(roda 0.2.0)
[ "$rc" = 0 ] && ok "sai 0" || falha "sai 0 (veio $rc: $(cat "$TMP/out"))"
[ "$(remoto stable)" = "$(remoto v0.1.0)" ] && ok "o stable não saiu do lugar" || falha "o stable andou sem --push"
grep -q "Nada foi enviado" "$TMP/out" && ok "diz que nada foi enviado" || falha "não diz que nada foi enviado"

echo "== com --push: avança até a tag =="
rc=$(roda 0.2.0 --push)
[ "$rc" = 0 ] && ok "sai 0" || falha "sai 0 (veio $rc: $(cat "$TMP/out"))"
[ "$(remoto stable)" = "$(remoto v0.2.0)" ] && ok "o stable está em v0.2.0" || falha "o stable não chegou em v0.2.0"
[ "$(remoto main)" = "$(remoto v0.3.0)" ] && ok "a main não foi tocada" || falha "a main mudou"

echo "== já está na versão: não faz nada =="
rc=$(roda 0.2.0 --push)
[ "$rc" = 0 ] && grep -q "já está em v0.2.0" "$TMP/out" && ok "diz que já está" || falha "não reconhece que já está (rc=$rc)"

echo "== voltar o canal é recusado =="
rc=$(roda 0.1.0 --push)
[ "$rc" != 0 ] && ok "sai diferente de 0" || falha "aceitou voltar o stable"
[ "$(remoto stable)" = "$(remoto v0.2.0)" ] && ok "o stable ficou em v0.2.0" || falha "o stable voltou"

echo "== tag que não existe e argumento ruim =="
rc=$(roda 9.9.9 --push); [ "$rc" != 0 ] && ok "tag inexistente é recusada" || falha "aceitou tag inexistente"
rc=$(roda abc);          [ "$rc" = 2 ] && ok "versão malformada sai 2" || falha "versão malformada veio rc=$rc"
rc=$(roda 0.3.0 --force); [ "$rc" = 2 ] && ok "flag desconhecida sai 2" || falha "flag desconhecida veio rc=$rc"
[ "$(remoto stable)" = "$(remoto v0.2.0)" ] && ok "nenhum dos três mexeu no stable" || falha "o stable mudou"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
