#!/usr/bin/env bash
# Prova de regressão do passo "4. Skills do time no Codex" do scripts/codex-optimize.sh.
#
# Nem toda entrada de [[skills.config]] tem `path`: as skills de plugin entram por
# `name` (ex.: name = "kit-vamoo:source-command-explicar"). O passo 4 fazia s['path']
# e quebrava com KeyError: 'path' no config.toml real de 15/10/2026 (2 de 686 entradas).
# Contra a main, os casos "sem path" falham.
#
# Roda só o modo diagnóstico, contra um CODEX_HOME temporário — nunca o ~/.codex real.
# Uso: bash tests/test-codex-optimize-skills.sh [caminho-do-script]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/codex-optimize.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Recorta só a saída do passo 4 (até o cabeçalho do passo 5).
passo4() { # <conteúdo do config.toml>
  rm -rf "$TMP/codex"; mkdir -p "$TMP/codex"
  printf '%s' "$1" > "$TMP/codex/config.toml"
  CODEX_HOME="$TMP/codex" bash "$SCRIPT" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
    | awk '/^4\. Skills/{p=1} /^5\. /{p=0} p'
}
tem() { # <descrição> <saída> <trecho esperado>
  case "$2" in *"$3"*) printf '  ok    %s\n' "$1" ;;
    *) printf '  FALHA %s (faltou: %s)\n' "$1" "$3"; falhas=$((falhas+1)) ;; esac
}
nao_tem() { # <descrição> <saída> <trecho proibido>
  case "$2" in *"$3"*) printf '  FALHA %s (apareceu: %s)\n' "$1" "$3"; falhas=$((falhas+1)) ;;
    *) printf '  ok    %s\n' "$1" ;; esac
}

echo "== entrada sem path (skill de plugin, por name) =="
out=$(passo4 '[[skills.config]]
path = "/x/skills/find-docs/SKILL.md"
enabled = false

[[skills.config]]
name = "kit-vamoo:source-command-explicar"
enabled = false

[[skills.config]]
name = "kit-vamoo:source-command-ligada"
enabled = true

[[skills.config]]
enabled = false
')
nao_tem "não quebra com KeyError"            "$out" "Traceback"
tem     "conta as 3 desligadas"              "$out" "3 skill(s) com enabled = false"
tem     "mostra a desligada por path"        "$out" "/x/skills/find-docs/SKILL.md"
tem     "mostra a desligada por name"        "$out" "kit-vamoo:source-command-explicar"
nao_tem "não lista a ligada"                 "$out" "kit-vamoo:source-command-ligada"
tem     "entrada sem path nem name aparece"  "$out" "(sem path nem name)"

echo "== formato antigo continua igual =="
out=$(passo4 '[[skills.config]]
path = "/x/a/SKILL.md"
enabled = true
')
tem "todas ligadas" "$out" "todas as 1 registradas estão ligadas"

out=$(passo4 'model = "x"
')
tem "nenhuma registrada" "$out" "nenhuma skill registrada"

echo
[ "$falhas" = 0 ] && { echo "tudo ok"; exit 0; }
echo "$falhas falha(s)"; exit 1
