#!/usr/bin/env bash
# Prova de regressão do hooks/path-rules.sh (PreToolUse em Edit|Write|Read|NotebookEdit).
#
# O que precisa continuar valendo: a regra chega uma vez por sessão, chega pelo
# caminho certo, e o hook NUNCA bloqueia a ferramenta (só acrescenta contexto).
#
# E sem jq: todo caso roda o hook com um PATH do qual o jq foi tirado. Até 0.34.0 o
# hook lia o payload com jq e, sem ele, saía calado — a regra simplesmente não chegava
# para quem não tinha jq instalado, que não é pré-requisito do kit. Hoje quem lê é o
# node, pelo scripts/hookjson.js, como nos outros hooks do plugin.
#
# Uso: bash tests/test-path-rules.sh [caminho-do-hook]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${1:-$RAIZ/plugin/hooks/path-rules.sh}"
CONF_REAL="$RAIZ/plugin/hooks/path-rules.conf"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
[ -f "$CONF_REAL" ] || { echo "conf não encontrado: $CONF_REAL"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }

FAKE=$(mktemp -d)
trap 'rm -rf "$FAKE"' EXIT
mkdir -p "$FAKE/hooks"
cp "$CONF_REAL" "$FAKE/hooks/path-rules.conf"

# O PATH de sempre, menos o jq: cada pasta do PATH que tem jq vira uma cópia feita de
# links, sem ele. Tirar a pasta inteira levaria junto sed, grep e find (no macOS o jq
# mora em /usr/bin).
SEM_JQ=""; n=0; resto="$PATH:"
while [ -n "$resto" ]; do
  d="${resto%%:*}"; resto="${resto#*:}"
  [ -n "$d" ] || continue
  if [ -e "$d/jq" ]; then
    n=$((n+1)); mkdir -p "$FAKE/sem-jq/$n"
    ln -s "$d"/* "$FAKE/sem-jq/$n/" 2>/dev/null
    rm -f "$FAKE/sem-jq/$n/jq"
    d="$FAKE/sem-jq/$n"
  fi
  SEM_JQ="${SEM_JQ:+$SEM_JQ:}$d"
done

falhas=0
saida=""; codigo=0
roda() { # roda <sessao> <caminho> [cwd] [file_path|notebook_path]
  local payload
  payload=$(S="$1" F="$2" C="${3:-}" K="${4:-file_path}" node -e '
    const e = process.env, entrada = {};
    entrada[e.K] = e.F;
    process.stdout.write(JSON.stringify({
      session_id: e.S, hook_event_name: "PreToolUse", cwd: e.C, tool_input: entrada,
      tool_name: e.K === "notebook_path" ? "NotebookEdit" : "Edit",
    }));')
  saida=$(HOME="$FAKE" CLAUDE_PLUGIN_ROOT="$FAKE" PATH="$SEM_JQ" bash "$HOOK" <<<"$payload" 2>/dev/null)
  codigo=$?
}
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
tem() { printf '%s' "$saida" | grep -q "$1" && echo ok || echo fail; }
vazio() { [ -z "$saida" ] && echo ok || echo fail; }
formato_pretooluse() {
  node -e '
    const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const h = j.hookSpecificOutput || {};
    process.exit(h.hookEventName === "PreToolUse" && typeof h.additionalContext === "string" ? 0 : 1);
  ' <<<"$saida" >/dev/null 2>&1 && echo ok || echo fail
}

# --- o hook roda sem jq -------------------------------------------------------
check "jq fora do PATH em que o hook roda"  "$( (PATH="$SEM_JQ"; command -v jq >/dev/null 2>&1) && echo fail || echo ok)"
check "node continua nesse PATH"            "$( (PATH="$SEM_JQ"; command -v node >/dev/null 2>&1) && echo ok || echo fail)"

# --- injeta na primeira vez, pelo caminho certo -----------------------------
roda s1 /Users/x/PROJ/supabase/migrations/001_init.sql
check "migration injeta a regra"            "$(tem 'irreversível')"
check "sai como additionalContext"          "$(tem 'additionalContext')"
check "não devolve permissionDecision"      "$(printf '%s' "$saida" | grep -q permissionDecision && echo fail || echo ok)"
check "não bloqueia (exit 0)"               "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
# A regra de migration tem aspas no texto: é o caso que quebraria um JSON montado à mão.
check "saída é JSON válido, no formato do PreToolUse" "$(formato_pretooluse)"

# --- uma vez por sessão, e não mais -----------------------------------------
roda s1 /Users/x/PROJ/supabase/migrations/002_outra.sql
check "não repete a mesma regra na sessão"  "$(vazio)"
roda s2 /Users/x/PROJ/supabase/migrations/001_init.sql
check "sessão nova recebe de novo"          "$(tem 'irreversível')"

# --- cada caminho traz a sua regra ------------------------------------------
roda s3 /Users/x/PROJ/supabase/functions/webhook/index.ts
check "edge function traz a regra do verify_jwt" "$(tem 'verify_jwt')"
roda s3 /Users/x/PROJ/.env
check ".env traz a regra de rotação"        "$(tem 'rotacione')"
roda s3 /Users/x/PROJ/package.json
check "package.json lembra do audit"        "$(tem 'audit')"

# --- settings.json: a regra não pode mentir sobre o kit ---------------------
# Até 0.34.0 ela dizia que o arquivo "é sobrescrito" quando o kit atualiza e mandava
# hook para o settings.local.json. No plugin, o /kit-vamoo:setup mescla. E o glob casa
# também com o .claude/settings.json de projeto, que vai para o git.
roda s8 /Users/x/.claude/settings.json
check "settings.json global: o setup mescla"         "$(tem 'mescla')"
check "settings.json global: não diz 'é sobrescrito'" "$(printf '%s' "$saida" | grep -q 'é sobrescrito' && echo fail || echo ok)"
roda s9 /Users/x/PROJ/.claude/settings.json
check "settings.json de projeto: o pessoal vai no settings.local.json do projeto" "$(tem 'settings.local.json do projeto')"

# --- caminho que não chega absoluto ainda casa ------------------------------
# Regra que some calada é pior que regra que não existe: ninguém percebe a falta.
roda c1 '~/PROJ/supabase/migrations/001.sql'
check "caminho com ~ é expandido"              "$(tem 'irreversível')"
roda c2 supabase/migrations/001.sql /Users/x/PROJ
check "caminho relativo resolve pelo cwd"      "$(tem 'irreversível')"
roda c3 ./supabase/migrations/001.sql /Users/x/PROJ
check "./ no meio não atrapalha"               "$(tem 'irreversível')"
roda c4 supabase/migrations/001.sql
check "relativo sem cwd não injeta nem quebra" "$([ "$(vazio)" = ok ] && [ "$codigo" -eq 0 ] && echo ok || echo fail)"

# --- silêncio onde tem que ser silêncio -------------------------------------
roda s4 /Users/x/PROJ/src/App.tsx
check "caminho sem regra não injeta nada"   "$(vazio)"
# Com o conf no lugar: sem ele o hook sairia antes de olhar o payload, e o caso passaria
# por outro motivo.
saida=$(HOME="$FAKE" CLAUDE_PLUGIN_ROOT="$FAKE" PATH="$SEM_JQ" bash "$HOOK" <<<'{"session_id":"s5","tool_input":{}}' 2>/dev/null)
check "payload sem file_path não injeta"    "$(vazio)"
rm -f "$FAKE/hooks/path-rules.conf"
roda s6 /Users/x/PROJ/supabase/migrations/001_init.sql
check "sem conf o hook sai limpo"           "$(vazio)"
check "sem conf ainda é exit 0"             "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"

# --- duas regras no mesmo caminho vêm juntas --------------------------------
printf '%s\n' \
  '*/tmp/alvo/* | primeira regra' \
  '*/alvo/arquivo.txt | segunda regra' > "$FAKE/hooks/path-rules.conf"
roda s7 /tmp/alvo/arquivo.txt
check "duas regras casando vêm juntas"      "$([ "$(tem 'primeira regra')" = ok ] && [ "$(tem 'segunda regra')" = ok ] && echo ok || echo fail)"

# --- NotebookEdit manda notebook_path, não file_path ------------------------
roda s10 /tmp/alvo/analise.ipynb "" notebook_path
check "notebook_path também traz a regra"   "$(tem 'primeira regra')"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
