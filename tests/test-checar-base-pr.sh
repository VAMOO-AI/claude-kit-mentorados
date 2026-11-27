#!/usr/bin/env bash
# scripts/checar-base-pr.sh reprova PR aberto contra o stable, e o CI chama o script.
#
# Uso: bash tests/test-checar-base-pr.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$RAIZ/scripts/checar-base-pr.sh"
CI="$RAIZ/.github/workflows/ci.yml"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

# roda <base> → preenche $saida e $rc
roda() { saida="$(bash "$SCRIPT" "$@" 2>&1)"; rc=$?; }

echo "== base stable reprova e diz o conserto =="
roda stable
[ "$rc" -eq 1 ] && ok "stable sai 1" || falha "stable saiu $rc, esperado 1"
case "$saida" in *"--base main"*) ok "a mensagem manda usar --base main" ;; *) falha "sem --base main na mensagem: $saida" ;; esac
case "$saida" in *"promover-stable.sh"*) ok "a mensagem aponta o promover-stable.sh" ;; *) falha "sem promover-stable.sh na mensagem" ;; esac

echo "== as outras bases passam =="
roda main
[ "$rc" -eq 0 ] && ok "main sai 0" || falha "main saiu $rc, esperado 0"
roda feat/empilhado
[ "$rc" -eq 0 ] && ok "branch de feature (PR empilhado) sai 0" || falha "feat/empilhado saiu $rc, esperado 0"
roda stable-antigo
[ "$rc" -eq 0 ] && ok "nome que só começa com stable sai 0" || falha "stable-antigo saiu $rc, esperado 0"

echo "== sem base é erro de uso, não aprovação =="
roda
[ "$rc" -eq 2 ] && ok "sem argumento sai 2" || falha "sem argumento saiu $rc, esperado 2"
roda ""
[ "$rc" -eq 2 ] && ok "base vazia sai 2" || falha "base vazia saiu $rc, esperado 2"

echo "== o CI chama o script com a base do PR, por variável de ambiente =="
/usr/bin/grep -q 'scripts/checar-base-pr.sh "\$BASE_REF"' "$CI" 2>/dev/null \
  && ok "ci.yml roda o script com \$BASE_REF" || falha "ci.yml não roda scripts/checar-base-pr.sh \"\$BASE_REF\""
/usr/bin/grep -q 'BASE_REF: \${{ github.base_ref }}' "$CI" 2>/dev/null \
  && ok "a base chega por env, não interpolada no shell" || falha "ci.yml não passa BASE_REF por env"

echo
[ "$falhas" -eq 0 ] && { echo "tudo ok"; exit 0; }
echo "$falhas falha(s)"; exit 1
