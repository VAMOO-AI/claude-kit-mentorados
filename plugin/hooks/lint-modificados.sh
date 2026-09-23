#!/usr/bin/env bash
# Lint dos arquivos JS/TS que esta sessão editou, em duas pontas:
#
#   lint-modificados.sh anota   PostToolUse [Edit|Write]: anota o file_path em
#                               ~/.claude/.cache/lint-sessao/<session_id> e sai.
#   lint-modificados.sh         Stop: roda eslint --fix no que foi anotado.
#
# Até a 0.35 o PostToolUse rodava o eslint --fix direto, em async: o --fix podia gravar
# por cima da edição seguinte, que já estava em andamento. Agora a edição só é anotada
# (síncrono, sem eslint) e o lint acontece uma vez, no fim do turno.
#
# A lista vem da sessão, e não do git, porque o git não sabe quem mexeu: com duas
# sessões no mesmo clone, o --fix cairia também no arquivo que a outra está editando.
# Limite aceito: edição feita pelo Bash (sed, heredoc, redirecionamento) não passa pelo
# matcher [Edit|Write], não entra na lista e não é lintada aqui.
#
# O eslint é o node_modules/.bin/eslint mais próximo do arquivo, sem passar da raiz git
# dele: em monorepo pega o do pacote, e worktree sem node_modules não herda o do clone
# principal. Roda uma vez por projeto, a partir de onde está instalado, com cache em
# ~/.claude/.cache/eslint/ (o do projeto sujaria o repo). Teto de 20 arquivos por Stop;
# o resto fica para o próximo. Nunca bloqueia: erro que o --fix não resolve vira aviso.
#
# Lê o payload via node (sem jq). bash 3.2 (macOS): sem mapfile, sem array vazio sob `set -u`.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || { cat >/dev/null 2>&1; exit 0; }
[ -f "$H" ] || { cat >/dev/null 2>&1; exit 0; }

DIR="$HOME/.claude/.cache/lint-sessao"

if [ "${1:-}" = anota ]; then
  info=$(node "$H" session_id tool_input.file_path 2>/dev/null) || exit 0
  s=$(printf '%s\n' "$info" | sed -n 1p | tr -cd 'A-Za-z0-9_-')
  f=$(printf '%s\n' "$info" | sed -n 2p)
  [ -n "$s" ] && [ -n "$f" ] || exit 0
  mkdir -p "$DIR" 2>/dev/null && printf '%s\n' "$f" >> "$DIR/$s" 2>/dev/null
  exit 0
fi

SESSAO=$(node "$H" session_id 2>/dev/null | tr -cd 'A-Za-z0-9_-') || exit 0
[ -n "$SESSAO" ] || exit 0

LISTA="$DIR/$SESSAO"
[ -s "$LISTA" ] || exit 0

find "$DIR" -type f -mtime +7 -delete 2>/dev/null   # sessão de uma semana atrás não volta
TOMADA="$LISTA.$$"
mv -f "$LISTA" "$TOMADA" 2>/dev/null || exit 0
trap 'rm -f "$TOMADA"' EXIT

TETO=${LINT_MODIFICADOS_TETO:-20}
case "$TETO" in ''|*[!0-9]*|0) TETO=20 ;; esac
CACHE="$HOME/.claude/.cache/eslint"
mkdir -p "$CACHE" 2>/dev/null || exit 0

LINTAVEIS=$(
  sort -u "$TOMADA" | grep -Ei '^/.*\.(js|jsx|ts|tsx|mjs|cjs)$' |
    while IFS= read -r arquivo; do [ -f "$arquivo" ] && printf '%s\n' "$arquivo"; done
)
[ -n "$LINTAVEIS" ] || exit 0

# O que passou do teto volta para a lista e sai no próximo Stop.
LOTE=$(printf '%s\n' "$LINTAVEIS" | head -n "$TETO")
RESTO=$(printf '%s\n' "$LINTAVEIS" | sed "1,${TETO}d")
[ -n "$RESTO" ] && printf '%s\n' "$RESTO" >> "$LISTA"

# Imprime "<diretório do eslint>\t<arquivo>", os dois em caminho físico: o git devolve
# a raiz sem symlink, e o eslint ignora arquivo fora do diretório de onde roda.
par_de() { # par_de <arquivo>
  local d topo arquivo
  d=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || return 1
  arquivo="$d/$(basename "$1")"
  topo=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || return 1
  while :; do
    [ -x "$d/node_modules/.bin/eslint" ] && { printf '%s\t%s\n' "$d" "$arquivo"; return 0; }
    [ "$d" = "$topo" ] && return 1
    case "$d" in "$topo"/*) d=$(dirname "$d") ;; *) return 1 ;; esac
  done
}

PARES=$(
  printf '%s\n' "$LOTE" | while IFS= read -r arquivo; do par_de "$arquivo"; done | sort
)
[ -n "$PARES" ] || exit 0

PENDENTES=0
RELATORIO=""
lint_projeto() { # lint_projeto <diretório> <arquivo>...
  local dir=$1 saida
  shift
  saida=$(cd "$dir" && "$dir/node_modules/.bin/eslint" --fix --cache --cache-location "$CACHE/" "$@" 2>&1) && return 0
  PENDENTES=$((PENDENTES + $#))
  RELATORIO="${RELATORIO}${saida}"$'\n'
}

atual=""
set --
while IFS=$'\t' read -r projeto arquivo; do
  [ -n "$projeto" ] || continue
  if [ -n "$atual" ] && [ "$projeto" != "$atual" ]; then
    lint_projeto "$atual" "$@"
    set --
  fi
  atual=$projeto
  set -- "$@" "$arquivo"
done <<< "$PARES"
[ -n "$atual" ] && lint_projeto "$atual" "$@"

[ "$PENDENTES" -eq 0 ] && exit 0
printf 'lint pendente em %d arquivo(s) tocado(s) nesta sessão:\n' "$PENDENTES"
printf '%s' "$RELATORIO" | tail -n 15
exit 0
