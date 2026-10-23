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
# O payload é montado no bash e chega ao hook pelo stdin, sem passar por variável de
# ambiente para o node: no Git Bash o MSYS reescreve /tmp/... em C:/.../Temp/... ao
# chamar programa nativo, e o caminho mudava antes de chegar ao hook. Os caminhos daqui
# não têm aspas; a barra invertida (caminho Windows) é dobrada para o JSON ser válido.
roda() { # roda <sessao> <caminho> [cwd] [file_path|notebook_path]
  local payload k="${4:-file_path}" ferramenta=Edit c="$2" d="${3:-}"
  [ "$k" = notebook_path ] && ferramenta=NotebookEdit
  c="${c//\\/\\\\}"; d="${d//\\/\\\\}"
  c="${c//\"/\\\"}"
  payload=$(printf '{"session_id":"%s","hook_event_name":"PreToolUse","cwd":"%s","tool_input":{"%s":"%s"},"tool_name":"%s"}' \
    "$1" "$d" "$k" "$c" "$ferramenta")
  saida=$(HOME="$FAKE" CLAUDE_PLUGIN_ROOT="$FAKE" PATH="$SEM_JQ" bash "$HOOK" <<<"$payload" 2>/dev/null)
  codigo=$?
}
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
tem() { printf '%s' "$saida" | grep >/dev/null "$1" && echo ok || echo fail; }
tem_literal() { printf '%s' "$saida" | grep >/dev/null -F -- "$1" && echo ok || echo fail; }
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
check "não devolve permissionDecision"      "$(printf '%s' "$saida" | grep >/dev/null permissionDecision && echo fail || echo ok)"
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
check "settings.json global: não diz 'é sobrescrito'" "$(printf '%s' "$saida" | grep >/dev/null 'é sobrescrito' && echo fail || echo ok)"
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

# --- caminho no formato Windows ---------------------------------------------
# O Claude Code no Windows manda C:\Users\... com barra invertida. Até 0.53.8 o hook só
# tratava "/*" como absoluto: o "C:\..." ganhava o cwd na frente e os globs "*/..." do
# conf não casavam com "\", então a regra sumia calada. Com "C:/..." e cwd ela chegava,
# mas com o caminho dobrado (C:/Users/x/PROJ/C:/Users/x/PROJ/.env).
roda w1 'C:\Users\x\PROJ\supabase\migrations\001.sql'
check "Windows com \\, sem cwd: migration injeta"           "$(tem 'irreversível')"
roda w2 'C:\Users\x\PROJ\supabase\migrations\001.sql' 'C:\Users\x\PROJ'
check "Windows com \\ e cwd: migration injeta"              "$(tem 'irreversível')"
check "…e o caminho não sai dobrado"                         "$(tem_literal 'deste caminho (C:/Users/x/PROJ/supabase/migrations/001.sql)')"
roda w3 'C:/Users/x/PROJ/.env'
check "Windows com /, sem cwd: .env injeta"                  "$(tem 'rotacione')"
roda w4 'C:/Users/x/PROJ/.env' 'C:/Users/x/PROJ'
check "Windows com / e cwd: .env injeta"                     "$(tem 'rotacione')"
check "…e o caminho não sai dobrado"                         "$(tem_literal 'deste caminho (C:/Users/x/PROJ/.env)')"
roda w5 'supabase\functions\webhook\index.ts' 'C:\Users\x\PROJ'
check "relativo com \\ resolve pelo cwd Windows"            "$(tem_literal 'deste caminho (C:/Users/x/PROJ/supabase/functions/webhook/index.ts)')"
roda w6 'd:\proj\package.json' 'C:\Users\x'
check "drive minúsculo é absoluto"                           "$(tem_literal 'deste caminho (d:/proj/package.json)')"

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

# --- `~/` no padrão é o home de quem roda, e só ele (B1 da avaliação de 20/10) ----------
# `*/.claude/settings.json` casa o global e o de cada projeto. Regra que só vale para o
# global se escreve `~/.claude/settings.json`: o pedaço do $HOME casa literal.
printf '%s\n' '~/.claude/settings.json | regra-do-global' > "$FAKE/hooks/path-rules.conf"
roda b1 "$FAKE/.claude/settings.json"
check "~/ casa o settings do home"                    "$(tem 'regra-do-global')"
roda b2 /Users/x/PROJ/.claude/settings.json
check "~/ não casa o settings de projeto"              "$(vazio)"
roda b3 .claude/settings.json "$FAKE"
check "relativo que resolve no home casa o ~/"         "$(tem 'regra-do-global')"
roda b4 "$FAKE/WORKSPACES/app/.claude/settings.json"
check "projeto dentro do home não casa o ~/"           "$(vazio)"

# --- o path-rules.local.conf da máquina soma, troca ou tira regra ------------------------
# É onde mora o que é da casa (o kit do time instala o dele; o mentorado pode ter o seu).
# Mesmo glob do conf do kit: a linha local troca o texto; texto "-" tira a regra.
printf '%s\n' '*/alvo/a.txt | regra-do-kit' '*/alvo/b.txt | regra-que-sai' '*/alvo/c.txt | regra-trocada' > "$FAKE/hooks/path-rules.conf"
mkdir -p "$FAKE/.claude/hooks"
printf '%s\n' '# regras da casa' '*/alvo/d.txt | regra-da-casa' '*/alvo/b.txt | -' '*/alvo/c.txt | texto-da-casa' > "$FAKE/.claude/hooks/path-rules.local.conf"
roda l1 /tmp/alvo/a.txt;  check "local não apaga a regra do kit que ele não cita" "$(tem 'regra-do-kit')"
roda l2 /tmp/alvo/d.txt;  check "local acrescenta regra"                          "$(tem 'regra-da-casa')"
roda l3 /tmp/alvo/b.txt;  check "local com '-' tira a regra do kit"               "$(vazio)"
roda l4 /tmp/alvo/c.txt;  check "local com o mesmo glob troca o texto"            "$([ "$(tem 'texto-da-casa')" = ok ] && [ "$(tem 'regra-trocada')" = fail ] && echo ok || echo fail)"
rm -f "$FAKE/.claude/hooks/path-rules.local.conf"
roda l5 /tmp/alvo/d.txt;  check "sem o local, só o conf do kit"                    "$(vazio)"

# --- JSON montado sem node: aspas, barra invertida e tab escapados -----------------------
printf '%s\n' '*/alvo/* | texto com "aspas", barra \ invertida e	tab' > "$FAKE/hooks/path-rules.conf"
roda j1 '/tmp/alvo/arq "x".txt'
check "aspas e barra invertida: JSON válido"           "$(formato_pretooluse)"
check "…e o texto chega inteiro"                        "$(printf '%s' "$saida" | node -e 'const s=JSON.parse(require("fs").readFileSync(0,"utf8")).hookSpecificOutput.additionalContext; process.exit(s.includes("\"aspas\", barra \\ invertida e\ttab") && s.includes("arq \"x\".txt") ? 0 : 1)' && echo ok || echo fail)"

# --- um node por chamada (invariante 4 do #241) ------------------------------------------
NODE_REAL="$(command -v node)"; mkdir -p "$FAKE/conta"
printf '#!/bin/sh\necho x >> "%s/conta/chamadas"\nexec "%s" "$@"\n' "$FAKE" "$NODE_REAL" > "$FAKE/conta/node"; chmod +x "$FAKE/conta/node"
: > "$FAKE/conta/chamadas"
payload='{"session_id":"n1","cwd":"/tmp","tool_input":{"file_path":"/tmp/alvo/x.txt"}}'
saida=$(HOME="$FAKE" CLAUDE_PLUGIN_ROOT="$FAKE" PATH="$FAKE/conta:$SEM_JQ" bash "$HOOK" <<<"$payload" 2>/dev/null)
check "regra que casa: um node só"                      "$([ "$(wc -l < "$FAKE/conta/chamadas" | tr -d ' ')" = 1 ] && [ "$(tem 'aspas')" = ok ] && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
