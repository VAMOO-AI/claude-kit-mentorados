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
#
# Quem lê o payload é o node, pelo scripts/hookjson.js, como nos outros hooks do plugin.
# Até 0.34.0 era o jq, que não é pré-requisito do kit: sem ele o hook saía calado e a
# regra não chegava.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd)/hookjson.js"
[ -f "$H" ] || H="$HOME/.claude/scripts/hookjson.js"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$H" ] || exit 0

CONF="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/hooks/path-rules.conf"
[ -f "$CONF" ] || exit 0

# Um node só para os quatro campos, um por linha (e nenhum outro na chamada). O último sai cru e poderia ter quebra
# de linha, mas caminho de arquivo não tem.
info="$(node "$H" session_id cwd tool_input.file_path tool_input.notebook_path)"
{ IFS= read -r sessao; IFS= read -r cwd; IFS= read -r caminho; IFS= read -r notebook; } <<<"$info"
[ -n "$caminho" ] || caminho="$notebook"
[ -n "$caminho" ] || exit 0

# O glob do .conf é casado contra caminho absoluto. Caminho relativo ("supabase/
# migrations/x.sql") não casa com nenhum padrão "*/..." e a regra sumiria calada —
# a versão silenciosa do buraco que os guards de commit tinham ao ler o path cru.
# O "~" e o "/./" casam por acaso hoje (o "*" cobre os dois), mas só enquanto todo
# padrão começar com "*/": normalizar aqui é o que segura um padrão absoluto.
# No Windows o caminho chega como C:\Users\...: a barra invertida vira "/" antes de
# tudo (sem ela nenhum "*/..." casa) e "C:/" conta como absoluto. Até 0.53.8 o "C:..."
# ganhava o cwd na frente e a regra sumia calada para quem usa Windows.
caminho="${caminho//\\//}"; cwd="${cwd//\\//}"
case "$caminho" in
  '~')   caminho="$HOME" ;;
  '~/'*) caminho="$HOME/${caminho#'~/'}" ;;
  /*|[[:alpha:]]:/*) ;;
  *)     [ -n "$cwd" ] && caminho="$cwd/$caminho" ;;
esac
while case "$caminho" in */./*) true ;; *) false ;; esac; do
  caminho="${caminho%%/./*}/${caminho#*/./}"
done

[ -n "$sessao" ] || sessao="sem-sessao"

ESTADO="$HOME/.claude/state/path-rules"
mkdir -p "$ESTADO" 2>/dev/null || exit 0
find "$ESTADO" -type f -mtime +7 -delete 2>/dev/null   # sessão de uma semana atrás não volta
marcas="$ESTADO/$sessao"

# As regras vêm do conf do kit e, depois, do path-rules.local.conf da máquina, se existir: é
# onde mora o que é da casa (o kit do time instala o dele, e quem usa o plugin pode ter o
# seu). Linha local com o mesmo glob de uma do kit troca o texto dela, e o texto "-" a tira.
LOCAL="$HOME/.claude/hooks/path-rules.local.conf"
padroes=(); textos=()
carrega() { # <arquivo>
  local linha padrao texto i
  while IFS= read -r linha || [ -n "$linha" ]; do
    case "$linha" in ''|'#'*) continue ;; esac
    case "$linha" in *'|'*) ;; *) continue ;; esac
    # Apara os espaços sem abrir processo: com o node lendo o payload, dois sed por linha
    # do conf levavam o hook de ~40 para ~65 ms em todo Read/Edit/Write.
    padrao="${linha%%|*}"; padrao="${padrao#"${padrao%%[![:space:]]*}"}"; padrao="${padrao%"${padrao##*[![:space:]]}"}"
    texto="${linha#*|}";   texto="${texto#"${texto%%[![:space:]]*}"}"; texto="${texto%"${texto##*[![:space:]]}"}"
    [ -n "$padrao" ] && [ -n "$texto" ] || continue
    i=0
    while [ "$i" -lt "${#padroes[@]}" ]; do
      [ "${padroes[$i]}" = "$padrao" ] && break
      i=$((i+1))
    done
    padroes[$i]="$padrao"; textos[$i]="$texto"
  done < "$1"
}
carrega "$CONF"
[ -f "$LOCAL" ] && carrega "$LOCAL"

regras=""
i=0
while [ "$i" -lt "${#padroes[@]}" ]; do
  padrao="${padroes[$i]}"; texto="${textos[$i]}"; i=$((i+1))
  [ "$texto" = "-" ] && continue
  # `~/` no padrão é o home de quem roda, e só ele: `~/.claude/settings.json` não casa o
  # settings de projeto (B1 da avaliação de 20/10). O pedaço do $HOME casa literal (entre
  # aspas); o resto é glob.
  # shellcheck disable=SC2254  # o padrão é glob de propósito
  case "$padrao" in
    '~/'*) case "$caminho" in "${HOME%/}"/${padrao#'~/'}) ;; *) continue ;; esac ;;
    *)     case "$caminho" in $padrao) ;; *) continue ;; esac ;;
  esac
  grep -qxF -- "$padrao" "$marcas" 2>/dev/null && continue

  printf '%s\n' "$padrao" >> "$marcas"
  regras="${regras}- ${texto}"$'\n'
done

[ -n "$regras" ] || exit 0

# JSON montado em bash, sem um segundo node (invariante 4 do #241): escapa a barra
# invertida, as aspas e os controles que um texto de regra ou um caminho podem ter.
json_str() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}' \
  "$(json_str "Regra deste caminho ($caminho):"$'\n'"$regras")"
exit 0
