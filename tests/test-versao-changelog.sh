#!/usr/bin/env bash
# As versões do kit dizem todas a mesma coisa?
#
# São QUATRO lugares: plugin.json, plugin/scripts/kit-setup.sh, install.sh e o
# topo do CHANGELOG. O CI já compara os três primeiros entre si; o que faltava é
# o CHANGELOG e a detecção de versão repetida.
#
# O modo silencioso de quebrar: dois PRs abertos ao mesmo tempo bumpam para a
# MESMA versão. Quem mergeia depois não vê conflito — o git auto-mergeia linha
# idêntica — e o bump do segundo vira no-op. O kit anuncia uma versão que já
# saiu, e o Claude Code, que decide baixar a atualização pela `version` do
# plugin.json, não baixa nada.
#
# Em 01/09/2026 este repo passou por uma variante disso: um bump subiu
# plugin.json e install.sh e esqueceu o kit-setup.sh, porque quem bumpou
# procurou o arquivo na raiz e ele mora em plugin/scripts/.
#
# Uso: bash tests/test-versao-changelog.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
for f in install.sh CHANGELOG.md plugin/.claude-plugin/plugin.json plugin/scripts/kit-setup.sh; do
  [ -f "$RAIZ/$f" ] || { echo "$f não encontrado em $RAIZ"; exit 2; }
done

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

v_plugin=$(python3 -c "import json;print(json.load(open('$RAIZ/plugin/.claude-plugin/plugin.json'))['version'])" 2>/dev/null)
v_setup=$(awk -F'"' '/^KIT_VERSION=/{print $2; exit}' "$RAIZ/plugin/scripts/kit-setup.sh")
v_inst=$(awk -F'"' '/^KIT_VERSION=/{print $2; exit}' "$RAIZ/install.sh")
topo=$(grep -m1 '^## \[' "$RAIZ/CHANGELOG.md" | sed 's/^## \[\([^]]*\)\].*/\1/')
todas=$(grep '^## \[' "$RAIZ/CHANGELOG.md" | sed 's/^## \[\([^]]*\)\].*/\1/')
repetidas=$(printf '%s\n' "$todas" | sort | uniq -d)

check "plugin.json declara version"   "$([ -n "$v_plugin" ] && echo ok || echo fail)"
check "kit-setup.sh declara KIT_VERSION" "$([ -n "$v_setup" ] && echo ok || echo fail)"
check "install.sh declara KIT_VERSION"   "$([ -n "$v_inst" ] && echo ok || echo fail)"
check "CHANGELOG tem versão no topo"     "$([ -n "$topo" ] && echo ok || echo fail)"

if [ "$v_plugin" = "$v_setup" ] && [ "$v_plugin" = "$v_inst" ]; then
  check "plugin.json, kit-setup.sh e install.sh batem ($v_plugin)" ok
else
  check "plugin.json ($v_plugin), kit-setup.sh ($v_setup) e install.sh ($v_inst) batem" fail
  echo "        → o kit-setup.sh mora em plugin/scripts/, não na raiz — é o que costuma ficar pra trás"
fi

if [ "$v_plugin" = "$topo" ]; then
  check "versão do plugin ($v_plugin) e topo do CHANGELOG batem" ok
else
  check "versão do plugin ($v_plugin) e topo do CHANGELOG ($topo) batem" fail
  echo "        → sem a entrada no CHANGELOG ninguém sabe o que mudou nesta versão"
fi

if [ -z "$repetidas" ]; then
  check "nenhuma versão aparece duas vezes no CHANGELOG" ok
else
  check "nenhuma versão aparece duas vezes no CHANGELOG" fail
  printf '        → repetida(s): %s\n' "$(printf '%s' "$repetidas" | tr '\n' ' ')"
  echo "        → sinal de dois PRs que bumparam para a mesma versão"
fi

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
