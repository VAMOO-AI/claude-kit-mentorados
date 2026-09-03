#!/usr/bin/env bash
# O corpo da release sai certo do CHANGELOG?
#
# `.github/scripts/changelog-bloco.sh` recorta o bloco de UMA versão para o
# release.yml publicar. Errar aqui não quebra nada na hora: a release sai com o
# texto da versão errada, ou com dois blocos colados, e só alguém lendo percebe.
#
# Uso: bash tests/test-changelog-bloco.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$RAIZ/.github/scripts/changelog-bloco.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

cat > "$tmp/CHANGELOG.md" <<'FIM'
# Changelog

Texto de abertura que não pertence a versão nenhuma.

## [1.2.0] — 2026-01-03

### Adicionado
- topo

## [1.1.0]

### Corrigido
- meio, linha 1
- meio, linha 2

### Alterado
- meio, outra seção

## [1.0.0]

### Adicionado
- fundo
FIM

esperado="$(printf '### Corrigido\n- meio, linha 1\n- meio, linha 2\n\n### Alterado\n- meio, outra seção')"
saida="$(bash "$SCRIPT" 1.1.0 "$tmp/CHANGELOG.md")"
check "bloco do meio sai inteiro, sem cabeçalho e sem o vizinho" "$([ "$saida" = "$esperado" ] && echo ok || echo fail)"

saida="$(bash "$SCRIPT" 1.2.0 "$tmp/CHANGELOG.md")"
check "bloco do topo (cabeçalho com data) sai só ele" "$([ "$saida" = "$(printf '### Adicionado\n- topo')" ] && echo ok || echo fail)"

saida="$(bash "$SCRIPT" 1.0.0 "$tmp/CHANGELOG.md")"
check "bloco do fim (sem próximo cabeçalho) vai até o fim do arquivo" "$([ "$saida" = "$(printf '### Adicionado\n- fundo')" ] && echo ok || echo fail)"

saida="$(bash "$SCRIPT" 9.9.9 "$tmp/CHANGELOG.md" 2>/dev/null)"; codigo=$?
check "versão sem bloco: sai 1 e não imprime nada" "$([ "$codigo" = 1 ] && [ -z "$saida" ] && echo ok || echo fail)"

saida="$(bash "$SCRIPT" 1.1 "$tmp/CHANGELOG.md" 2>/dev/null)"; codigo=$?
check "prefixo de versão (1.1) não casa com 1.1.0" "$([ "$codigo" = 1 ] && [ -z "$saida" ] && echo ok || echo fail)"

# E no CHANGELOG de verdade: a versão que o plugin declara tem bloco, e o bloco
# não arrasta cabeçalho de outra versão.
v_plugin="$(python3 -c "import json;print(json.load(open('$RAIZ/plugin/.claude-plugin/plugin.json'))['version'])")"
saida="$(bash "$SCRIPT" "$v_plugin" "$RAIZ/CHANGELOG.md")"; codigo=$?
check "CHANGELOG real: a versão do plugin ($v_plugin) tem bloco" "$([ "$codigo" = 0 ] && [ -n "$saida" ] && echo ok || echo fail)"
check "CHANGELOG real: o bloco começa em '### ' e não contém outro '## ['" \
  "$(printf '%s\n' "$saida" | head -1 | grep -q '^### ' && ! printf '%s\n' "$saida" | grep -q '^## \[' && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
