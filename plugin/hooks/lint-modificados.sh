#!/usr/bin/env bash
# Lint dos arquivos JS/TS que esta sessão editou, em duas pontas:
#
#   lint-modificados.sh anota   PostToolUse [Edit|Write]: anota o file_path em
#                               ~/.claude/.cache/lint-sessao/<session_id> e sai.
#   lint-modificados.sh         Stop: roda o eslint, SEM --fix, no que foi anotado.
#
# O hook não corrige: devolve o erro para o modelo corrigir (decisão D6 de 09/11/2026). Até a
# 0.90 ele rodava `eslint --fix`, que reescreve arquivo fora do turno: a mudança não aparecia
# no diff que o modelo descreveu, podia cair no meio de um trabalho da pessoa no editor, e o
# que o --fix não resolvia virava só um aviso na tela. Agora, havendo erro, o Stop sai com
# `{"decision":"block","reason":…}`: o Claude Code não encerra o turno e entrega o motivo ao
# modelo (doc de hooks, "Stop decision control"), que edita os arquivos pelo caminho normal.
#
# Sem loop: o payload traz `stop_hook_active: true` quando o Claude já está continuando por
# causa de um Stop hook. Nesse caso o hook não bloqueia de novo; se o erro continua, vira
# aviso para a pessoa (systemMessage) e o turno encerra. O arquivo que reprovou volta para a
# lista no bloqueio, para o Stop seguinte conferir o que o modelo fez mesmo que a correção
# não tenha passado pelo Edit.
#
# Até a 0.35 o PostToolUse rodava o eslint direto, em async. Agora a edição só é anotada
# (síncrono, sem eslint) e o lint acontece uma vez, no fim do turno.
#
# A lista vem da sessão, e não do git, porque o git não sabe quem mexeu: com duas sessões no
# mesmo clone, o modelo seria mandado corrigir o arquivo que a outra está editando.
# Limite aceito: edição feita pelo Bash (sed, heredoc, redirecionamento) não passa pelo
# matcher [Edit|Write], não entra na lista e não é lintada aqui.
#
# O eslint é o node_modules/.bin/eslint mais próximo do arquivo, sem passar da raiz git
# dele: em monorepo pega o do pacote, e worktree sem node_modules não herda o do clone
# principal. Roda uma vez por projeto, a partir de onde está instalado, com cache em
# ~/.claude/.cache/eslint/ (o do projeto sujaria o repo). Teto de 20 arquivos por Stop;
# o resto fica para o próximo. Só erro segura o Stop: warning (eslint sai 0) passa calado.
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

# Um node só para os dois campos: o primeiro numa linha, o último cru.
info=$(node "$H" stop_hook_active session_id 2>/dev/null) || exit 0
JA_SEGUROU=0; [ "${info%%$'\n'*}" = true ] && JA_SEGUROU=1
SESSAO=$(printf '%s' "${info#*$'\n'}" | tr -cd 'A-Za-z0-9_-')
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
REPROVADOS=""
lint_projeto() { # lint_projeto <diretório> <arquivo>...
  local dir=$1 saida f
  shift
  saida=$(cd "$dir" && "$dir/node_modules/.bin/eslint" --cache --cache-location "$CACHE/" "$@" 2>&1) && return 0
  PENDENTES=$((PENDENTES + $#))
  RELATORIO="${RELATORIO}${saida}"$'\n'
  for f in "$@"; do REPROVADOS="${REPROVADOS}${f}"$'\n'; done
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

# JSON montado em bash, sem node: escapa barra, aspas e quebra de linha, e tira o controle
# que sobrar (cor ANSI de um eslint com FORCE_COLOR quebraria o JSON inteiro).
json_str() {
  local t
  t=$(printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037')
  t="${t//\\/\\\\}"; t="${t//\"/\\\"}"
  t="${t//$'\n'/\\n}"; t="${t//$'\r'/\\r}"; t="${t//$'\t'/\\t}"
  printf '%s' "$t"
}
# O relatório vai para o contexto do modelo: 40 linhas bastam para ele achar o arquivo e a
# regra, e o resto ele vê rodando o eslint.
CORPO=$(printf '%s' "$RELATORIO" | tail -n 40)

if [ "$JA_SEGUROU" = 0 ]; then
  # O que reprovou volta para a lista: o Stop seguinte confere de novo.
  printf '%s' "$REPROVADOS" >> "$LISTA" 2>/dev/null
  motivo="$(printf 'ESLint reprovou %d arquivo(s) que você editou nesta sessão. Corrija os erros abaixo editando os arquivos antes de encerrar o turno (este hook não aplica --fix). Se algum erro não for seu ou não tiver conserto agora, diga isso à pessoa em vez de silenciar a regra.\n\n' "$PENDENTES"; printf '%s' "$CORPO")"
  printf '{"decision":"block","reason":"%s"}\n' "$(json_str "$motivo")"
  exit 0
fi
# Já segurou uma vez neste Stop e o erro continua: não segura de novo. O stdout de um Stop
# vai para o debug log (B5 da avaliação de 20/10), então o aviso sai como systemMessage,
# que a interface mostra para a pessoa.
aviso="$(printf 'lint pendente em %d arquivo(s) tocado(s) nesta sessão (o modelo foi avisado e o erro continua):\n' "$PENDENTES"; printf '%s' "$CORPO" | tail -n 15)"
printf '{"systemMessage":"%s"}\n' "$(json_str "$aviso")"
exit 0
