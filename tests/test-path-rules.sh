#!/usr/bin/env bash
# Prova de regressão do hooks/path-rules.sh (PreToolUse em Edit|Write|Read|NotebookEdit).
#
# O que precisa continuar valendo: a regra chega uma vez por sessão, chega pelo
# caminho certo, e o hook NUNCA bloqueia a ferramenta (só acrescenta contexto).
#
# Uso: bash tests/test-path-rules.sh [caminho-do-hook]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${1:-$RAIZ/plugin/hooks/path-rules.sh}"
CONF_REAL="$RAIZ/plugin/hooks/path-rules.conf"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
[ -f "$CONF_REAL" ] || { echo "conf não encontrado: $CONF_REAL"; exit 2; }

FAKE=$(mktemp -d)
trap 'rm -rf "$FAKE"' EXIT
mkdir -p "$FAKE/hooks"
cp "$CONF_REAL" "$FAKE/hooks/path-rules.conf"

falhas=0
saida=""; codigo=0
roda() { # roda <sessao> <caminho> [cwd]
  local payload
  payload=$(jq -n --arg s "$1" --arg f "$2" --arg c "${3:-}" \
    '{session_id:$s,hook_event_name:"PreToolUse",tool_name:"Edit",cwd:$c,tool_input:{file_path:$f}}')
  saida=$(printf '%s' "$payload" | HOME="$FAKE" CLAUDE_PLUGIN_ROOT="$FAKE" bash "$HOOK" 2>/dev/null)
  codigo=$?
}
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
tem() { printf '%s' "$saida" | grep -q "$1" && echo ok || echo fail; }
vazio() { [ -z "$saida" ] && echo ok || echo fail; }

# --- injeta na primeira vez, pelo caminho certo -----------------------------
roda s1 /Users/x/PROJ/supabase/migrations/001_init.sql
check "migration injeta a regra"            "$(tem 'irreversível')"
check "sai como additionalContext"          "$(tem 'additionalContext')"
check "não devolve permissionDecision"      "$(printf '%s' "$saida" | grep -q permissionDecision && echo fail || echo ok)"
check "não bloqueia (exit 0)"               "$([ "$codigo" -eq 0 ] && echo ok || echo fail)"
check "saída é JSON válido"                 "$(printf '%s' "$saida" | jq -e . >/dev/null 2>&1 && echo ok || echo fail)"

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
saida=$(jq -n '{session_id:"s5",tool_input:{}}' | HOME="$FAKE" bash "$HOOK" 2>/dev/null)
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

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
