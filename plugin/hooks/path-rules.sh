#!/bin/bash
# PreToolUse em Edit|Write|Read|NotebookEdit: injeta a regra do lugar onde o agente
# acabou de encostar, e só nesse momento.
#
# Por que existe: a tabela de roteamento do CLAUDE.md fica no contexto de TODA
# request, custe ela sendo usada ou não. Regra amarrada a caminho é a que mais
# sofre com isso — "migration pede db-query.sh" não interessa em nenhuma sessão que
# não toca supabase/migrations/. Aqui ela chega quando (e se) o arquivo aparece.
#
# Dispara UMA vez por regra por sessão: o barato é lembrar, o caro é repetir em
# cada um dos 30 edits seguintes — cada tool call relê a conversa inteira.
#
# Regras em hooks/path-rules.conf (ao lado deste arquivo), uma por linha, "glob | texto". Nada bloqueia: o hook
# só acrescenta contexto (additionalContext), nunca nega a ferramenta.
command -v jq >/dev/null 2>&1 || exit 0

CONF="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/hooks/path-rules.conf"
[ -f "$CONF" ] || exit 0

entrada=$(cat)
caminho=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$entrada" 2>/dev/null)
[ -n "$caminho" ] || exit 0

# O glob do .conf é casado contra caminho absoluto. Caminho relativo ("supabase/
# migrations/x.sql") não casa com nenhum padrão "*/..." e a regra sumiria calada —
# a versão silenciosa do buraco que os guards de commit tinham ao ler o path cru.
# O "~" e o "/./" casam por acaso hoje (o "*" cobre os dois), mas só enquanto todo
# padrão começar com "*/": normalizar aqui é o que segura um padrão absoluto.
cwd=$(jq -r '.cwd // empty' <<<"$entrada" 2>/dev/null)
case "$caminho" in
  '~')   caminho="$HOME" ;;
  '~/'*) caminho="$HOME/${caminho#'~/'}" ;;
  /*)    ;;
  *)     [ -n "$cwd" ] && caminho="$cwd/$caminho" ;;
esac
while case "$caminho" in */./*) true ;; *) false ;; esac; do
  caminho="${caminho%%/./*}/${caminho#*/./}"
done

sessao=$(jq -r '.session_id // empty' <<<"$entrada" 2>/dev/null)
[ -n "$sessao" ] || sessao="sem-sessao"

ESTADO="$HOME/.claude/state/path-rules"
mkdir -p "$ESTADO" 2>/dev/null || exit 0
find "$ESTADO" -type f -mtime +7 -delete 2>/dev/null   # sessão de uma semana atrás não volta
marcas="$ESTADO/$sessao"

regras=""
while IFS= read -r linha || [ -n "$linha" ]; do
  case "$linha" in ''|'#'*) continue ;; esac
  case "$linha" in *'|'*) ;; *) continue ;; esac

  padrao=$(printf '%s' "${linha%%|*}" | sed 's/[[:space:]]*$//; s/^[[:space:]]*//')
  texto=$(printf '%s' "${linha#*|}"   | sed 's/^[[:space:]]*//')
  [ -n "$padrao" ] && [ -n "$texto" ] || continue

  # shellcheck disable=SC2254  # o padrão é glob de propósito
  case "$caminho" in $padrao) ;; *) continue ;; esac
  grep -qxF -- "$padrao" "$marcas" 2>/dev/null && continue

  printf '%s\n' "$padrao" >> "$marcas"
  regras="${regras}- ${texto}"$'\n'
done < "$CONF"

[ -n "$regras" ] || exit 0

jq -n --arg ctx "Regra deste caminho ($caminho):"$'\n'"$regras" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
exit 0
