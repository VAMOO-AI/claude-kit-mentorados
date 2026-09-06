#!/usr/bin/env bash
# As versões do kit dizem todas a mesma coisa?
#
# São CINCO lugares: plugin.json, plugin/scripts/kit-setup.sh, install.sh, o topo
# do CHANGELOG e o topo do plugin/novidades.txt. O CI já compara os três
# primeiros entre si; o que faltava é o CHANGELOG e a detecção de versão repetida.
#
# O quinto entrou junto com o aviso de novidades do SessionStart: bumpar e
# esquecer a linha do novidades.txt não quebra nada visível — o aviso
# simplesmente não conta a versão nova a ninguém, que é exatamente o silêncio
# que ele existe para acabar.
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
# Em 03/09/2026, outra: três cabeçalhos (0.13.0, 0.14.0, 0.15.0) sumiram do
# CHANGELOG porque cada PR resolveu o conflito do topo trocando o `## [x.y.z]`
# do vizinho pelo seu em vez de inserir acima. Versão repetida não pega isso —
# a versão engolida SOME. O que sobra é o sintoma: o bloco de cima fica com a
# mesma `### Seção` duas vezes. Daí os dois checks do fim.
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

NOVIDADES="$RAIZ/plugin/novidades.txt"
v_plugin=$(python3 -c "import json;print(json.load(open('$RAIZ/plugin/.claude-plugin/plugin.json'))['version'])" 2>/dev/null)
v_setup=$(awk -F'"' '/^KIT_VERSION=/{print $2; exit}' "$RAIZ/plugin/scripts/kit-setup.sh")
v_inst=$(awk -F'"' '/^KIT_VERSION=/{print $2; exit}' "$RAIZ/install.sh")
topo=$(grep -m1 '^## \[' "$RAIZ/CHANGELOG.md" | sed 's/^## \[\([^]]*\)\].*/\1/')
# Primeira linha de dado do novidades.txt (comentário e linha vazia não contam),
# campo antes do primeiro "|".
topo_novidades=$(awk -F'|' '/^[[:space:]]*#/ {next} /^[[:space:]]*$/ {next} {gsub(/[[:space:]]/,"",$1); print $1; exit}' "$NOVIDADES" 2>/dev/null)
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

if [ ! -f "$NOVIDADES" ]; then
  check "plugin/novidades.txt existe" fail
  echo "        → sem ele o aviso de novidades do SessionStart cala em toda sessão"
elif [ "$v_plugin" = "$topo_novidades" ]; then
  check "versão do plugin ($v_plugin) e topo do novidades.txt batem" ok
else
  check "versão do plugin ($v_plugin) e topo do novidades.txt ($topo_novidades) batem" fail
  echo "        → o aviso do SessionStart só conta versão que está no novidades.txt:"
  echo "          sem a linha, quem atualizar não fica sabendo que esta versão saiu"
fi

# Formato de cada linha do novidades.txt: <versão>|<resumo>[|setup]. A regra estava só
# no cabeçalho do arquivo — e o arquivo é editado à mão a cada release. O hook lê com
# `IFS='|' read -r v resumo flag`: um "|" dentro do resumo trunca o resumo E empurra o
# resto para o 3º campo, então `2.0.0|resumo com | pipe no meio|setup` vira flag
# " pipe no meio|setup", que não é "setup" — a linha do /kit-vamoo:setup some sem erro
# nenhum, num aviso que existe justamente para acabar com silêncio.
if [ -f "$NOVIDADES" ]; then
  # Mesmo predicado de "linha que não é dado" do topo_novidades acima: dois extratores
  # discordando do que é comentário é a deriva que este teste existe para não ter.
  campos=$(awk -F'|' '/^[[:space:]]*#/ {next} /^[[:space:]]*$/ {next}
    NF < 2 || NF > 3 { printf "linha %d: %d campo(s) — %s\n", NR, NF, $0 }' "$NOVIDADES")
  if [ -z "$campos" ]; then
    check "toda linha do novidades.txt tem 2 ou 3 campos (| não vale dentro do resumo)" ok
  else
    check "toda linha do novidades.txt tem 2 ou 3 campos (| não vale dentro do resumo)" fail
    printf '%s\n' "$campos" | sed 's/^/        → /'
    echo "        → o hook lê com IFS='|' read -r v resumo flag: um | a mais trunca o"
    echo "          resumo e empurra o resto pro 3º campo — a flag setup morre calada"
  fi

  flag_torta=$(awk -F'|' '/^[[:space:]]*#/ {next} /^[[:space:]]*$/ {next}
    NF == 3 { f = $3; gsub(/[[:space:]]/, "", f)
              if (f != "setup") printf "linha %d: 3º campo \"%s\"\n", NR, f }' "$NOVIDADES")
  if [ -z "$flag_torta" ]; then
    check "3º campo, quando existe, é exatamente \"setup\"" ok
  else
    check "3º campo, quando existe, é exatamente \"setup\"" fail
    printf '%s\n' "$flag_torta" | sed 's/^/        → /'
    echo "        → o hook compara com = setup: qualquer outra coisa é ignorada em silêncio"
  fi
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

# Mesma seção duas vezes no mesmo bloco = cabeçalho engolido num merge.
secoes_repetidas=$(awk '
  /^## \[/ { v = $0; sub(/^## \[/, "", v); sub(/\].*/, "", v); next }
  /^### / && v != "" { n[v "\t" $0]++ }
  END { for (k in n) if (n[k] > 1) { split(k, p, "\t"); print p[1] ": " p[2] " x" n[k] } }
' "$RAIZ/CHANGELOG.md" | sort)
if [ -z "$secoes_repetidas" ]; then
  check "nenhum bloco de versão repete a mesma seção (### X duas vezes)" ok
else
  check "nenhum bloco de versão repete a mesma seção (### X duas vezes)" fail
  printf '%s\n' "$secoes_repetidas" | sed 's/^/        → /'
  echo "        → cabeçalho ## [x.y.z] engolido num merge: o bloco de cima absorveu o de baixo"
fi

# Cada cabeçalho tem que ser menor que o de cima. Fora de ordem é bloco colado no
# meio do arquivo, ou entrada nova escrita embaixo de uma antiga.
fora_de_ordem=$(printf '%s\n' "$todas" | awk '
  function cmp(a, b,   x, y, na, nb, n, i, d) {
    na = split(a, x, "."); nb = split(b, y, "."); n = (na > nb) ? na : nb
    for (i = 1; i <= n; i++) { d = (x[i] + 0) - (y[i] + 0); if (d != 0) return d }
    return 0
  }
  NR > 1 && cmp(ant, $0) <= 0 { print ant " → " $0 }
  { ant = $0 }
')
if [ -z "$fora_de_ordem" ]; then
  check "cabeçalhos ## [x.y.z] em ordem estritamente decrescente" ok
else
  check "cabeçalhos ## [x.y.z] em ordem estritamente decrescente" fail
  printf '%s\n' "$fora_de_ordem" | sed 's/^/        → /'
fi

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
