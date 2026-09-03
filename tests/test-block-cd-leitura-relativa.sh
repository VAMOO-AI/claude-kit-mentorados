#!/usr/bin/env bash
# Prova de regressão do plugin/hooks/block-cd-leitura-relativa.sh.
#
# O caso que originou o hook (03/09/2026): o Claude Code recusou
# `cd /abs && grep -n "cargos" src/lib/tipos.ts | head -40` dizendo que a pasta "cannot
# be determined here" e que há regra Read() em deny, então "only you can approve". O
# pedido de autorização vinha do próprio harness, não de hook, e aparecia até no modo
# bypass. O hook converte esse pedido num bloqueio que o Claude lê e conserta sozinho.
#
# O risco do hook é o contrário: barrar comando legítimo. Por isso a metade "não pode
# bloquear" é maior que a que bloqueia.
#
# Uso: bash tests/test-block-cd-leitura-relativa.sh [caminho-do-hook]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/block-cd-leitura-relativa.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node ausente"; exit 2; }

falhas=0
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cdrel.XXXXXX")
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

roda() {
  CMD="$1" node -e 'process.stdout.write(JSON.stringify({session_id:"teste",cwd:"/tmp",permission_mode:"bypassPermissions",tool_input:{command:process.env.CMD}}))' \
    | bash "$HOOK" >/dev/null 2>"$TMP/err"
  echo $?
}
check() { # check <bloqueia|passa> <descrição> <comando>
  local rc; rc=$(roda "$3")
  local esperado=0; [ "$1" = bloqueia ] && esperado=2
  if [ "$rc" = "$esperado" ]; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (esperado rc=%s, veio rc=%s)\n' "$2" "$esperado" "$rc"; falhas=$((falhas+1)); fi
}

NL=$'\n'
D=/Users/eu/projetos/meu-app

echo "== tem que bloquear (é o que pedia autorização ao usuário) =="
check bloqueia "o caso medido: grep com caminho relativo depois de cd" \
                                              "cd $D && grep -n \"cargos\" src/lib/tipos.ts | head -40"
check bloqueia "cat de arquivo relativo depois de cd"        "cd $D && cat package.json"
check bloqueia "head de arquivo relativo depois de cd"       "cd $D && head -40 notas.txt"
check bloqueia "sed com script entre aspas e arquivo relativo" \
                                              "cd $D && sed -n '1,5p' src/lib/x.ts"
check bloqueia "cd com variável — a pasta segue indeterminável" \
                                              'cd "$PROJ/app" && cat src/x.ts'
check bloqueia "jq lendo arquivo relativo"                   "cd $D && jq -r '.version' package.json"
check bloqueia "leitura no terceiro comando da cadeia"       "cd $D && npm ci && wc -l src/index.ts"

echo
echo "== não pode bloquear (falso positivo aqui vira atrito novo) =="
check passa "mesmo comando com caminho ABSOLUTO"             "cd $D && grep -n \"cargos\" $D/src/lib/tipos.ts | head -40"
check passa "leitura relativa SEM cd (o harness resolve a pasta)" \
                                              "grep -n cargos src/lib/tipos.ts"
check passa "cd + comando que não lê arquivo"                "cd $D && npm test"
check passa "cd + git (git não é leitura de arquivo)"        "cd $D && git status --short"
check passa "cd + grep recursivo na pasta atual"             "cd $D && grep -rn \"cargos\" ."
check passa "padrão entre aspas com barra não é caminho"     "cd $D && grep -rn \"foo/bar\" $D"
check passa "argumento sem barra e sem extensão não é caminho" \
                                              "cd $D && grep -c cargos arquivo"
check passa "escotilha CD_LEITURA_OK=1"                      "CD_LEITURA_OK=1 cd $D && cat package.json"
check passa "corpo de heredoc é conteúdo, não comando" \
                                              "cat > s.sh <<'EOF'${NL}cd $D && grep foo src/a.ts${NL}EOF"
check passa "cd sozinho"                                     "cd $D"
# 03/09: o hook barrou dois comandos legítimos da sessão que o escreveu. O separador de
# palavras quebra em espaços, então argumento entre aspas COM espaço chegava partido e o
# pedaço do meio, com barra dentro, passava por caminho. Trecho entre aspas nunca é caminho.
check passa "expressão de sed entre aspas com espaço e barra" \
                                              "cd $D && sed -n '1,5p; s/a b/c/' $D/x.ts"
check passa "sed -i é escrita no arquivo, não a leitura que escala" \
                                              "cd $D && sed -i '' \"s/a b/c/\" plugin/x.json"
check passa "corpo de --body com várias linhas citando comandos" \
                                              "cd $D && gh pr create --body \"linha um${NL}sed -i '' s/a/b/ plugin/x.json${NL}grep -n foo src/y.ts${NL}fim\""
check passa "padrão de busca entre aspas com espaço e barra" \
                                              "cd $D && grep -n \"foo / bar\" $D/x.ts"

echo
echo "== a mensagem tem que ensinar o conserto =="
roda "cd $D && cat package.json" >/dev/null
if grep -qF "$D/package.json" "$TMP/err"; then printf '  ok    %s\n' "sugere o caminho absoluto pronto"
else printf '  FALHA %s (veio: %s)\n' "sugere o caminho absoluto pronto" "$(cat "$TMP/err")"; falhas=$((falhas+1)); fi
if grep -qF 'CD_LEITURA_OK=1' "$TMP/err"; then printf '  ok    %s\n' "aponta a escotilha"
else printf '  FALHA %s\n' "aponta a escotilha"; falhas=$((falhas+1)); fi

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
