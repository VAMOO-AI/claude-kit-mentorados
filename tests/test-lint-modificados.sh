#!/usr/bin/env bash
# Prova do plugin/hooks/lint-modificados.sh e do registro dele no plugin/hooks/hooks.json.
#
# O que o teste garante:
#   - o eslint saiu do PostToolUse [Edit|Write]: lá só fica o `anota`, síncrono, que
#     grava o file_path em ~/.claude/.cache/lint-sessao/<sessão>. O --fix async de antes
#     podia gravar por cima da edição seguinte;
#   - o Stop linta só o que esta sessão anotou. Arquivo modificado no mesmo clone por
#     outra sessão fica intocado, mesmo aparecendo no git. Edição feita pelo Bash não
#     entra na lista e não é lintada: é o custo aceito para o --fix não cair em arquivo
#     alheio;
#   - eslint mais próximo do arquivo até a raiz git, um lote por projeto, teto por Stop,
#     e nunca bloqueia.
#
# Uso: bash tests/test-lint-modificados.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
HOOK="$RAIZ/plugin/hooks/lint-modificados.sh"
HOOKS_JSON="$RAIZ/plugin/hooks/hooks.json"
[ -f "$HOOKS_JSON" ] || { echo "hooks.json não encontrado: $HOOKS_JSON"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }
# Rodado de uma sessão com a escotilha aberta, herdaria o KIT_VAMOO_HOOKS=1 à toa.
unset KIT_VAMOO_HOOKS

falhas=0
TMP=$(mktemp -d "${TMPDIR:-/tmp}/lint-modificados.XXXXXX")
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)   # o git devolve caminho físico (/private/var no macOS)
FAKE="$TMP/home"
LISTAS="$FAKE/.claude/.cache/lint-sessao"
mkdir -p "$LISTAS"
ESLINT_LOG="$TMP/eslint.log"

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
consta()     { grep -qF -- "$1" "$ESLINT_LOG" 2>/dev/null; }
check()      { if consta "$2"; then ok "$1"; else falha "$1 (não achei $2 no log)"; fi; }
check_nao()  { if consta "$2"; then falha "$1 (achei $2 e não devia)"; else ok "$1"; fi; }
novo_log()   { : > "$ESLINT_LOG"; }

eslint_falso() { # eslint_falso <dir>: instala <dir>/node_modules/.bin/eslint
  mkdir -p "$1/node_modules/.bin"
  cat > "$1/node_modules/.bin/eslint" <<'FAKE'
#!/usr/bin/env bash
# eslint falso: anota de onde rodou e os argumentos; sai com ESLINT_EXIT
{ printf 'cwd=%s\n' "$(pwd -P)"; for a in "$@"; do printf '%s\n' "$a"; done; } >> "$ESLINT_LOG"
[ "${ESLINT_EXIT:-0}" -ne 0 ] && echo "erro de lint inventado"
exit "${ESLINT_EXIT:-0}"
FAKE
  chmod +x "$1/node_modules/.bin/eslint"
}

repo() { # repo <dir>: repo git com um commit
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  printf 'node_modules/\n.claude-worktrees/\n' > "$1/.gitignore"
  git -C "$1" add .gitignore; git -C "$1" commit -qm base
}

anota() { printf '%s\n' "$2" >> "$LISTAS/$1"; }   # anota <sessão> <arquivo>

json() { # json <sessão> <cwd> [file_path] → payload de hook, montado pelo node
  S="$1" C="$2" F="${3:-}" node -e '
    const p = { session_id: process.env.S, cwd: process.env.C, hook_event_name: "Stop", stop_hook_active: false };
    if (process.env.F) p.tool_input = { file_path: process.env.F };
    process.stdout.write(JSON.stringify(p));' </dev/null
}

roda() { # roda <sessão> <cwd>: stdout do hook em $saida, código em $codigo
  local payload
  payload=$(json "$1" "$2")
  if [ ! -f "$HOOK" ]; then saida="hook ausente"; codigo=127; return; fi
  saida=$(cd "$2" && printf '%s' "$payload" | HOME="$FAKE" ESLINT_LOG="$ESLINT_LOG" \
    ESLINT_EXIT="${ESLINT_EXIT:-0}" LINT_MODIFICADOS_TETO="${LINT_MODIFICADOS_TETO:-20}" bash "$HOOK" 2>&1)
  codigo=$?
}

echo "== registro no hooks.json =="
# Um evento, matcher, async, timeout e comando por linha, separados por TAB.
node -e '
  const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  for (const [evento, grupos] of Object.entries(j.hooks || {}))
    for (const g of grupos)
      for (const h of g.hooks || [])
        console.log([evento, g.matcher || "", h.async === undefined ? "-" : String(h.async),
                     h.timeout === undefined ? "-" : String(h.timeout), h.command || ""].join("\t"));
' "$HOOKS_JSON" > "$TMP/registro" || { echo "hooks.json ilegível"; exit 2; }
TAB="$(printf '\t')"

if awk -F"$TAB" '$1=="PostToolUse" && ($5 ~ /eslint/ || $5 ~ /lint-fix/)' "$TMP/registro" | grep -q .; then
  falha "o eslint ainda roda no PostToolUse"
else
  ok "o eslint saiu do PostToolUse"
fi
awk -F"$TAB" '$1=="PostToolUse" && $2=="Edit|Write"' "$TMP/registro" > "$TMP/reg-linhas"
REG=""
if [ "$(grep -c . "$TMP/reg-linhas")" = 1 ] && [ "$(cut -f3 "$TMP/reg-linhas")" = "-" ] \
   && grep -qF 'lint-modificados.sh" anota' "$TMP/reg-linhas"; then
  REG=$(cut -f5- "$TMP/reg-linhas")
  ok "PostToolUse [Edit|Write] tem só o anota, síncrono"
else
  falha "PostToolUse [Edit|Write] deveria ter um único comando, o anota, sem async"
fi
STOP=$(awk -F"$TAB" '$1=="Stop" && $5 ~ /lint-modificados\.sh"$/' "$TMP/registro")
if [ -n "$STOP" ] && [ "$(printf '%s' "$STOP" | cut -f3)" = "-" ] && [ "$(printf '%s' "$STOP" | cut -f4)" != "-" ]; then
  ok "Stop registra o lint-modificados.sh, síncrono e com timeout"
else
  falha "Stop sem o lint-modificados.sh (ou async, ou sem timeout)"
fi
[ -f "$HOOK" ] && ok "plugin/hooks/lint-modificados.sh existe" || falha "plugin/hooks/lint-modificados.sh não existe"

echo "== o Stop linta só o que a sessão anotou =="
A="$TMP/a"; repo "$A"; eslint_falso "$A"
echo "export const alheio = 1" > "$A/alheio.ts"
git -C "$A" add alheio.ts; git -C "$A" commit -qm alheio
echo "export const alheio = 2" > "$A/alheio.ts"   # modificado por "outra sessão"

# 1) sem lista: sai rápido, sem eslint, mesmo com arquivo modificado no git
novo_log; roda s0 "$A"
check_nao "sem lista da sessão o eslint não roda" "cwd="
[ "$codigo" -eq 0 ] && ok "sem lista sai 0" || falha "sem lista saiu $codigo"

# 2) só a lista da sessão conta
echo "export const minha = 1" > "$A/minha.ts"
anota s1 "$A/minha.ts"
novo_log; roda s1 "$A"
check     "arquivo da lista é lintado"                        "$A/minha.ts"
check_nao "arquivo modificado fora da lista fica intocado"    "alheio.ts"
check     "passa --fix"                                       "--fix"
check     "usa o cache em ~/.claude/.cache/eslint/"           "$FAKE/.claude/.cache/eslint/"
[ -e "$LISTAS/s1" ] && falha "entradas processadas continuam na lista" || ok "entradas processadas saem da lista"

# 3) o que não é lintável cai sem chamar o eslint
anota s2 "$A/sumiu.ts"
echo "# doc" > "$A/LEIA.md"; anota s2 "$A/LEIA.md"
anota s2 "relativo.ts"
novo_log; roda s2 "$A"
check_nao "arquivo que não existe mais é ignorado"   "sumiu.ts"
check_nao "arquivo que não é JS/TS é ignorado"       "LEIA.md"
check_nao "caminho relativo é ignorado"              "relativo.ts"
[ -e "$LISTAS/s2" ] && falha "lista sem nada lintável não foi limpa" || ok "lista sem nada lintável é limpa"

echo "== eslint mais próximo, um lote por projeto =="
# 4) agrupado por projeto: um eslint por projeto, rodando de onde ele está instalado
B="$TMP/b"; repo "$B"; eslint_falso "$B/app"      # monorepo: eslint só no pacote
mkdir -p "$B/app/src"; echo "export const b = 1" > "$B/app/src/b.ts"
echo "export const a2 = 1" > "$A/a2.ts"
anota s3 "$B/app/src/b.ts"; anota s3 "$A/a2.ts"; anota s3 "$A/minha.ts"
novo_log; roda s3 "$A"
chamadas=$(awk '/^cwd=/{if (c) print c; c=$0; next} {c=c" "$0} END{if (c) print c}' "$ESLINT_LOG")
n=$(printf '%s\n' "$chamadas" | grep -c '^cwd=')
[ "$n" -eq 2 ] && ok "dois projetos, duas chamadas" || falha "dois projetos deram $n chamada(s)"
printf '%s\n' "$chamadas" | grep "^cwd=$A " | grep -qF "$A/a2.ts" \
  && printf '%s\n' "$chamadas" | grep "^cwd=$A " | grep -qF "$A/minha.ts" \
  && ok "os dois arquivos de a vão juntos, rodando da raiz de a" || falha "lote do projeto a"
printf '%s\n' "$chamadas" | grep "^cwd=$B/app " | grep -qF "$B/app/src/b.ts" \
  && ok "monorepo: roda o eslint do pacote, a partir do pacote" || falha "lote do pacote b/app"

# 5) worktree sem node_modules não sobe até o eslint do clone principal
git -C "$A" worktree add -q "$A/.claude-worktrees/wt" -b wt 2>/dev/null
echo "export const w = 1" > "$A/.claude-worktrees/wt/w.ts"
anota s4 "$A/.claude-worktrees/wt/w.ts"
novo_log; roda s4 "$A/.claude-worktrees/wt"
check_nao "worktree sem eslint próprio não usa o do clone principal" "w.ts"

# 5b) fora de repo git não roda, mesmo com eslint no diretório
S="$TMP/solto"; mkdir -p "$S"; eslint_falso "$S"; echo "export const s = 1" > "$S/s.ts"
anota s4b "$S/s.ts"
novo_log; roda s4b "$S"
check_nao "fora de repo git o eslint não roda" "s.ts"

echo "== nunca bloqueia, teto, sessão saneada =="
# 6) erro que o --fix não resolve vira aviso, não bloqueio
anota s5 "$A/minha.ts"
novo_log; ESLINT_EXIT=1 roda s5 "$A"
if [ "$codigo" -eq 0 ] && printf '%s' "$saida" | grep -q "lint pendente"; then
  ok "erro de lint vira aviso, não bloqueio"
else
  falha "erro de lint vira aviso (codigo=$codigo saida=$saida)"
fi

# 7) teto por Stop: o que passou do teto fica para o próximo
for i in 1 2 3 4 5; do echo "export const f$i = $i" > "$A/f$i.ts"; anota s6 "$A/f$i.ts"; done
novo_log; LINT_MODIFICADOS_TETO=2 roda s6 "$A"
n=$(grep -c '/f[0-9]\.ts$' "$ESLINT_LOG")
sobra=$(grep -c . "$LISTAS/s6" 2>/dev/null)
[ "$n" -eq 2 ] && ok "teto respeitado ($n)" || falha "teto de 2 lintou $n"
[ "$sobra" = 3 ] && ok "o resto fica na lista para o próximo Stop" || falha "sobrou '$sobra' na lista, esperado 3"

# 8) session_id do payload não escapa do diretório das listas
anota fora "$A/minha.ts"; mv "$LISTAS/fora" "$FAKE/.claude/.cache/fora"
novo_log; roda "../fora" "$A"
check_nao "session_id com ../ não lê fora de lint-sessao" "minha.ts"
[ -e "$FAKE/.claude/.cache/fora" ] && ok "arquivo fora de lint-sessao continua lá" || falha "hook consumiu arquivo fora de lint-sessao"

echo "== o comando do PostToolUse alimenta a lista que o Stop lê =="
# 9) o comando exato do hooks.json, com a guarda, como o harness roda
if [ -z "$REG" ]; then
  falha "sem o comando anota no hooks.json, o registrador não pôde ser exercitado"
else
  mkdir -p "$A/com espaço"; echo "export const r = 1" > "$A/com espaço/r.ts"
  for shell in sh bash; do
    rm -f "$LISTAS/reg"
    json reg "$A" "$A/com espaço/r.ts" > "$TMP/payload-reg.json"
    ( cd "$A" && HOME="$FAKE" CLAUDE_PLUGIN_ROOT="$RAIZ/plugin" "$shell" -c "$REG" \
        <"$TMP/payload-reg.json" >"$TMP/reg.out" 2>&1 ); rc=$?
    if [ "$rc" -eq 0 ] && [ "$(cat "$LISTAS/reg" 2>/dev/null)" = "$A/com espaço/r.ts" ] && [ ! -s "$TMP/reg.out" ]; then
      ok "anota grava o file_path, calado ($shell)"
    else
      falha "anota grava o file_path ($shell: rc=$rc, lista='$(cat "$LISTAS/reg" 2>/dev/null)', saída='$(cat "$TMP/reg.out")')"
    fi
  done
  json reg-vazio "$A" > "$TMP/payload-vazio.json"
  ( HOME="$FAKE" CLAUDE_PLUGIN_ROOT="$RAIZ/plugin" sh -c "$REG" <"$TMP/payload-vazio.json" >/dev/null 2>&1 ); rc=$?
  [ "$rc" -eq 0 ] && [ ! -e "$LISTAS/reg-vazio" ] && ok "sem file_path não anota e sai 0" || falha "sem file_path (rc=$rc)"
  printf 'lixo' > "$TMP/payload-lixo"
  ( HOME="$FAKE" CLAUDE_PLUGIN_ROOT="$RAIZ/plugin" sh -c "$REG" <"$TMP/payload-lixo" >/dev/null 2>&1 ); rc=$?
  [ "$rc" -eq 0 ] && ok "payload inválido sai 0" || falha "payload inválido saiu $rc"
  novo_log; roda reg "$A"
  check "Stop linta o que o anota gravou" "$A/com espaço/r.ts"
fi

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
