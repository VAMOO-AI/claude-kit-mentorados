#!/usr/bin/env bash
# Prova de regressão do plugin/hooks/pre-bash.sh, o dispatcher do PreToolUse(Bash).
#
# Até a 0.25.0 eram cinco entries no hooks.json, cada um um processo `sh` mais um
# `bash <hook>`: ~140 ms por chamada Bash só de processo. O dispatcher lê o payload uma vez e entrega
# aos cinco em subshell — e tem que devolver EXATAMENTE o que a cadeia antiga devolvia:
# o exit 2 (com stderr) do primeiro hook que bloqueia, o `ask` do check-careful, a
# reescrita do rtk no stdout, e nada quando nenhum hook fala.
#
# Cada caso passa pelo DISPATCHER, não pelo hook direto — é a única forma de pegar um
# `# gatilho:` que ficou estreito demais e passou a pular um hook que deveria bloquear.
#
# Uso: bash tests/test-pre-bash.sh [caminho-do-dispatcher]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/pre-bash.sh}"
[ -f "$HOOK" ] || { echo "dispatcher não encontrado: $HOOK"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }
HOOKS_DIR="$(cd "$(dirname "$HOOK")" && pwd)"
SCRIPTS_DIR="$(cd "$HOOKS_DIR/../scripts" && pwd)"
# Hook do plugin resolve o hookjson.js em ../scripts. Pasta de hooks avulsa (os casos de
# "hook ausente" abaixo) só funciona com o helper ao lado — senão o hook sai 0 fail-open
# e o teste aprovaria um dispatcher que não chamou ninguém.
árvore() { mkdir -p "$1/hooks" "$1/scripts"; cp "$SCRIPTS_DIR/hookjson.js" "$1/scripts/"; printf '%s' "$1/hooks"; }

falhas=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

MAIN="$TMP/main"; mkdir -p "$MAIN"; git -C "$MAIN" init -q -b main 2>/dev/null
FEAT="$TMP/feat"; mkdir -p "$FEAT"; git -C "$FEAT" init -q -b feat/x 2>/dev/null
# clone principal com OUTRA sessão ativa (marker <30min) num HOME falso
CLONE="$TMP/clone"; mkdir -p "$CLONE"; git -C "$CLONE" init -q -b main 2>/dev/null
H=$(printf '%s' "$(git -C "$CLONE" rev-parse --show-toplevel)" | shasum | awk '{print $1}')
HOME_OUTRA="$TMP/home-outra"; mkdir -p "$HOME_OUTRA/.claude/.cache/repo-sessions/$H"
touch "$HOME_OUTRA/.claude/.cache/repo-sessions/$H/outra-sessao"

COMMIT='git commit -q -m x'

# roda <comando> <cwd> [modo] [home] [pasta-de-hooks] → imprime o rc; stdout em $TMP/out, stderr em $TMP/err
roda() {
  C="$1" D="$2" MODO="${3:-default}" node -e 'process.stdout.write(JSON.stringify({session_id:"sessao-teste",cwd:process.env.D,permission_mode:process.env.MODO,tool_input:{command:process.env.C}}))' \
    | HOME="${4:-$HOME}" TMPDIR="$TMP" PRE_BASH_HOOKS_DIR="${5:-}" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"
  echo $?
}
# TMPDIR aponta para o temporário do teste: o aviso de bypass do check-careful é uma vez
# por sessão, com marker em $TMPDIR — sem isolar, a 2ª execução da suíte roda muda.
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
espera_rc() { [ "$1" = "$2" ] && ok "$3" || falha "$3 (esperado rc=$1, veio rc=$2)"; }
contem()     { grep -qF -- "$2" "$1" && ok "$3" || falha "$3 (não achei '$2' em: $(cat "$1"))"; }
nao_contem() { grep -qF -- "$2" "$1" && falha "$3 (achei '$2')" || ok "$3"; }

echo "== comando inocente passa em silêncio =="
rc=$(roda 'ls -la src' "$FEAT")
espera_rc 0 "$rc" "ls -la sai 0"
[ -s "$TMP/out" ] && falha "stdout deveria estar vazio: $(cat "$TMP/out")" || ok "stdout vazio (nenhum hook tinha o que dizer)"
[ -s "$TMP/err" ] && falha "stderr deveria estar vazio: $(cat "$TMP/err")" || ok "stderr vazio"

echo
echo "== bloqueio: o exit 2 e o stderr do hook chegam intactos, e nada roda depois =="
rc=$(roda "$COMMIT" "$MAIN")
espera_rc 2 "$rc" "commit em main sai 2 (block-main-commit)"
contem "$TMP/err" "cairia na branch 'main'" "stderr traz a mensagem do block-main-commit"
rc=$(roda "$COMMIT" "$FEAT")
espera_rc 0 "$rc" "o mesmo commit em feature branch passa"
for c in 'git checkout main' 'git switch -c feat/y' 'git reset --hard HEAD~1' 'git stash'; do
  rc=$(roda "$c" "$CLONE" default "$HOME_OUTRA")
  espera_rc 2 "$rc" "'$c' no clone com outra sessão ativa sai 2 (block-parallel-clone-switch)"
done
contem "$TMP/err" "CLONE PRINCIPAL" "stderr traz a mensagem do block-parallel-clone-switch"
rc=$(roda 'git stash list' "$CLONE" default "$HOME_OUTRA")
espera_rc 0 "$rc" "stash list (read-only) passa"
rc=$(roda 'cd /Users/x/proj/app && cat package.json' "$FEAT")
espera_rc 2 "$rc" "leitura relativa depois de cd sai 2 (block-cd-leitura-relativa)"
contem "$TMP/err" "caminho relativo" "stderr traz a mensagem do block-cd-leitura-relativa"
rc=$(roda 'cd /Users/x/proj/app && cat /Users/x/proj/app/package.json' "$FEAT")
espera_rc 0 "$rc" "a mesma leitura com caminho absoluto passa"

echo
echo "== o ask do check-careful atravessa a cadeia =="
rc=$(roda 'rm -rf ~/lixo-inexistente' "$TMP")
espera_rc 0 "$rc" "rm -rf em ~ fora de bypass sai 0"
contem "$TMP/out" '"permissionDecision":"ask"' "stdout traz o ask do check-careful"
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$TMP/out" 2>/dev/null \
  && ok "stdout é um JSON válido" || falha "stdout não é JSON: $(cat "$TMP/out")"
rc=$(roda 'rm -rf ~/lixo-inexistente' "$TMP" bypassPermissions)
espera_rc 0 "$rc" "em bypass o comando passa"
nao_contem "$TMP/out" '"permissionDecision":"ask"' "em bypass não há confirmação"
contem "$TMP/out" 'CAREFUL_ON=1' "…e o hook diz como trazê-la de volta nesta sessão"

echo
echo "== hook ausente é pulado; sem hook nenhum, sai 0 calado =="
SO_UM="$(árvore "$TMP/so-um")"; cp "$HOOKS_DIR/block-cd-leitura-relativa.sh" "$SO_UM/"
rc=$(roda "$COMMIT" "$MAIN" default "$HOME" "$SO_UM")
espera_rc 0 "$rc" "sem block-main-commit instalado, o commit em main passa pelo dispatcher"
rc=$(roda 'cd /Users/x/app && cat package.json' "$FEAT" default "$HOME" "$SO_UM")
espera_rc 2 "$rc" "…e o hook que existe segue bloqueando"
VAZIO="$(árvore "$TMP/vazio")"
rc=$(roda 'ls' "$FEAT" default "$HOME" "$VAZIO")
espera_rc 0 "$rc" "pasta sem nenhum hook sai 0"
[ -s "$TMP/out" ] && falha "stdout deveria estar vazio" || ok "stdout vazio"

echo
echo "== cadeia: o primeiro código ≠ 0 encerra, com o stdout e o stderr dele =="
FALSOS="$(árvore "$TMP/falsos")"
printf '%s\n' '#!/bin/bash' 'cat >/dev/null' 'echo saida-do-primeiro' 'echo erro-do-primeiro >&2' 'exit 1' > "$FALSOS/check-careful.sh"
printf '%s\n' '#!/bin/bash' 'cat >/dev/null' 'echo NAO-DEVIA-RODAR' 'exit 0' > "$FALSOS/block-cd-leitura-relativa.sh"
rc=$(roda 'ls' "$FEAT" default "$HOME" "$FALSOS")
espera_rc 1 "$rc" "exit 1 do hook vira exit 1 da cadeia"
contem "$TMP/out" 'saida-do-primeiro' "stdout do hook que saiu ≠ 0 é repassado"
contem "$TMP/err" 'erro-do-primeiro' "stderr do hook que saiu ≠ 0 é repassado"
nao_contem "$TMP/out" 'NAO-DEVIA-RODAR' "o hook seguinte não roda"

echo
echo "== o JSON do check-careful é repassado como o harness recebia =="
FUSAO="$(árvore "$TMP/fusao")"
printf '%s\n' '#!/bin/bash' 'cat >/dev/null' \
  'echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"[careful] teste\"}}"' > "$FUSAO/check-careful.sh"
rc=$(roda 'ls' "$FEAT" default "$HOME" "$FUSAO")
espera_rc 0 "$rc" "hook com exit 0 que fala → cadeia sai 0"
dec=$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).hookSpecificOutput.permissionDecision))' "$TMP/out" 2>/dev/null)
[ "$dec" = ask ] && ok "o ask chega intacto no stdout" || falha "decisão veio '$dec'"

echo
echo "== gatilho: o hook só abre quando a palavra dele está no payload =="
GAT="$(árvore "$TMP/gatilho")"
printf '%s\n' '#!/bin/bash' '# gatilho: commit' 'cat >/dev/null' 'echo gatilho-casou >&2' 'exit 2' > "$GAT/block-main-commit.sh"
rc=$(roda 'ls -la' "$FEAT" default "$HOME" "$GAT")
espera_rc 0 "$rc" "sem a palavra, o hook nem é aberto"
rc=$(roda 'echo commit' "$FEAT" default "$HOME" "$GAT")
espera_rc 2 "$rc" "com a palavra, o hook roda e decide"
# A linha de gatilho de cada hook real tem que cobrir o que ele bloqueia. Apagar a linha
# só deixa o hook mais lento; estreitá-la quebra os casos de bloqueio acima.
for par in 'block-main-commit.sh|commit' 'block-parallel-clone-switch.sh|checkout switch reset stash' 'block-delete-branch-with-children.sh|merge' 'block-cd-leitura-relativa.sh|cd'; do
  f="${par%%|*}"; g="${par#*|}"
  grep -qF "# gatilho: $g" "$HOOKS_DIR/$f" && ok "$f declara '# gatilho: $g'" || falha "$f sem '# gatilho: $g'"
done

echo
echo "== fail-open =="
rc=$(printf '' | bash "$HOOK" >/dev/null 2>&1; echo $?)
espera_rc 0 "$rc" "payload vazio sai 0"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
