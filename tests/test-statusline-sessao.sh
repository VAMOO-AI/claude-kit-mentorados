#!/usr/bin/env bash
# A barra de status mostra o comprimento da sessão a partir de 600 linhas de transcript
# (a régua do session-size-guard) e não quebra quando não há transcript.
#
# A barra é o que a pessoa olha o dia inteiro, e o wrapper esconde erro
# (`|| printf '[statusline]'`): quebrar aqui não aparece como erro, aparece como barra
# sumida. Por isso o teste roda o .js direto e vigia o stderr.
#
# Uso: bash tests/test-statusline-sessao.sh [caminho-do-statusline.js]
set -uo pipefail
SL="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/statusline.js}"
[ -f "$SL" ] || { echo "statusline não encontrado: $SL"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }

falhas=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
linhas() { : > "$TMP/tr.jsonl"; local i=0; while [ "$i" -lt "$1" ]; do echo '{}' >> "$TMP/tr.jsonl"; i=$((i+1)); done; }
render() { TP="${1:-}" node -e 'process.stdout.write(JSON.stringify({transcript_path:process.env.TP||undefined,workspace:{current_dir:process.env.HOME},context_window:{current_usage:{input_tokens:1000}}}))' \
    | node "$SL" 2>>"$TMP/err" | sed 's/\x1b\[[0-9;]*m//g'; }

linhas 100; s="$(render "$TMP/tr.jsonl")"
printf '%s' "$s" | grep -q 'ses:' && falha "apareceu abaixo da primeira faixa: $s" || ok "100 linhas: sem indicador"
printf '%s' "$s" | grep -q 'ctx:' && ok "o resto da barra continua saindo" || falha "barra vazia: $s"

linhas 700;  s="$(render "$TMP/tr.jsonl")"
printf '%s' "$s" | grep -q 'ses:700 /clear?' && ok "700 linhas: contagem + /clear?" || falha "faixa 600 errada: $s"
linhas 1300; s="$(render "$TMP/tr.jsonl")"
printf '%s' "$s" | grep -q 'ses:1.3k /compact' && ok "1.300 linhas: abreviado + /compact" || falha "faixa 1.200 errada: $s"
linhas 2500; s="$(render "$TMP/tr.jsonl")"
printf '%s' "$s" | grep -q 'ses:2.5k maratona' && ok "2.500 linhas: faixa das maratonas" || falha "faixa 2.000 errada: $s"

s="$(render "$TMP/nao-existe.jsonl")"
printf '%s' "$s" | grep -q 'ctx:' && ok "transcript inexistente: barra normal" || falha "quebrou sem transcript: $s"
s="$(render)"
printf '%s' "$s" | grep -q 'ctx:' && ok "payload sem transcript_path: barra normal" || falha "quebrou sem o campo: $s"
[ -s "$TMP/err" ] && falha "o .js escreveu em stderr: $(head -3 "$TMP/err")" || ok "nenhum erro em stderr"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
