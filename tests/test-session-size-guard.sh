#!/usr/bin/env bash
# Prova do plugin/hooks/session-size-guard.sh: mede o contexto real do último turno (input +
# cache_read + cache_creation do último usage de assistente no transcript) e avisa nas
# faixas de 150K e 300K e, dali em diante, a cada +100K (400K, 500K, …). Uma vez por faixa,
# um aviso só num salto de várias, e a faixa avisada acompanha a queda do /compact: o aviso
# volta quando o contexto cresce de novo até a faixa seguinte.
#
# O aviso é para a pessoa, não para o modelo: cada linha sai com o prefixo `@usuario `, que
# o pre-prompt.sh troca por systemMessage (o test-pre-prompt.sh cobre esse caminho). E o
# texto diz quantos tokens cada passo relê, sem prometer economia em dinheiro.
#
# Porte do test-session-size-guard.sh do kit do time (#236). Aqui o payload e o transcript
# são lidos por node, não por jq, e não há o marcador do usage-weekly, que só existe lá.
#
# Uso: bash tests/test-session-size-guard.sh [caminho-do-hook]
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/session-size-guard.sh}"
[ -f "$HOOK" ] || { echo "hook não encontrado: $HOOK"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }

falhas=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
CACHE="$HOME/.claude/.cache"

tp() { printf '%s/%s.jsonl' "$TMP" "$1"; }
linha() { printf '%s\n' "$2" >> "$(tp "$1")"; } # <sid> <linha crua no fim do transcript>
turno() { # <sid> <ctx>: mais um prompt e uma resposta cujo usage soma <ctx> tokens de contexto
  linha "$1" '{"type":"user","isSidechain":false,"message":{"role":"user","content":"segue"}}'
  linha "$1" "$(printf '{"type":"assistant","isSidechain":false,"message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":2,"cache_creation_input_tokens":1000,"cache_read_input_tokens":%d,"output_tokens":300,"service_tier":"standard"}}}' $(( $2 - 1002 )))"
}
COMPACT='{"type":"system","subtype":"compact_boundary","isSidechain":false,"compactMetadata":{"trigger":"manual","preTokens":480000,"postTokens":30000}}'
run() { # <sid> [transcript]: stdout do hook; o stderr fica em $TMP/err
  SID="$1" TP="${2:-$(tp "$1")}" node -e 'process.stdout.write(JSON.stringify({session_id:process.env.SID,transcript_path:process.env.TP}))' \
    | bash "$HOOK" 2>"$TMP/err"
  cat "$TMP/err" >> "$TMP/err-todos"
}
check() { # <regex-ou-vazio> <descrição> <saída>
  local ok=0
  if [ -z "$1" ]; then [ -z "$3" ] && ok=1
  else printf '%s' "$3" | grep -q -- "$1" && ok=1; fi
  if [ "$ok" = 1 ]; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (veio: %s)\n' "$2" "${3:-<vazio>}"; falhas=$((falhas+1)); fi
}
avisos() { printf '%s\n' "$1" | grep -c '^@usuario '; }
PARA_PESSOA='^@usuario .*K tokens'
# sem_dinheiro <faixa> <aviso>: o texto fala em tokens, sem "barato" nem "custo".
sem_dinheiro() {
  if [ -n "$2" ] && ! printf '%s' "$2" | grep -qiE 'barat|custo'; then
    printf '  ok    faixa %s: fala em tokens, não em dinheiro\n' "$1"
  else printf '  FALHA faixa %s: sem aviso ou com promessa de dinheiro (veio: %s)\n' "$1" "${2:-<vazio>}"; falhas=$((falhas+1)); fi
}

echo "== faixas de 150K e 300K =="
turno s1 100000; check ""                    "100K: silêncio"                               "$(run s1)"
turno s1 160000; a150=$(run s1)
check "tarefa atual acabou"  "160K: aviso da faixa de 150K"                                  "$a150"
check "~160K tokens"         "…com o número real"                                            "$a150"
check "$PARA_PESSOA"         "…com o prefixo @usuario"                                       "$a150"
check "^@usuario 📊 "        "…e o emoji da faixa (📊)"                                       "$a150"
turno s1 250000; check ""                    "250K: mesma faixa, silêncio"                  "$(run s1)"
turno s1 312000; a300=$(run s1)
check "Rode /compact agora"  "312K: aviso da faixa de 300K"                                  "$a300"
check "~312K tokens"         "…com o número real"                                            "$a300"
check "^@usuario ⚠️ "        "…e o emoji da faixa (⚠️)"                                        "$a300"
check "$PARA_PESSOA"         "…com o prefixo @usuario"                                       "$a300"
turno s1 390000; check ""                    "390K: mesma faixa, silêncio"                  "$(run s1)"

echo "== fronteira exata de 150K =="
turno b1 149999; check ""                    "149.999: silêncio"                            "$(run b1)"
turno b1 150000; out=$(run b1)
check "^@usuario 📊 "        "150.000: aviso da faixa de 150K"                               "$out"
check "~150K tokens"         "…com o número real"                                            "$out"

echo "== depois dos 300K, de novo a cada +100K =="
turno s1 400000; a400=$(run s1)
check "maratona"             "400K: avisa de novo"                                           "$a400"
check "~400K tokens"         "…com o número real"                                            "$a400"
check "^@usuario 🚨 "        "…e o emoji da faixa (🚨)"                                       "$a400"
check "$PARA_PESSOA"         "…com o prefixo @usuario"                                       "$a400"
turno s1 480000; check ""                    "480K: mesma faixa, silêncio"                  "$(run s1)"
turno s1 512000; out2=$(run s1)
check "~512K tokens"         "512K: avisa de novo, com o número de agora"                    "$out2"
check "^igual$"              "…e o mesmo texto do aviso de 400K"                              "$([ "${a400//400K/N}" = "${out2//512K/N}" ] && echo igual || echo diferente)"

echo "== salto de várias faixas: um aviso só =="
turno s1 830000; out=$(run s1)
check "^1$"                  "512K → 830K: um aviso só, não um por faixa pulada"             "$(avisos "$out")"
check "~830K tokens"         "…com o número de agora"                                        "$out"
turno s1 850000; check ""                    "850K: já avisou a faixa de 800K, silêncio"    "$(run s1)"
turno s2 420000; out=$(run s2)
check "^1$"                  "sessão que chega já com 420K: um aviso só"                      "$(avisos "$out")"
check "maratona"             "…o da faixa de 400K"                                            "$out"

echo "== /compact: a faixa acompanha a queda =="
linha s1 "$COMPACT"; turno s1 180000
check ""                     "compact que derruba 850K para 180K: silêncio"                   "$(run s1)"
turno s1 260000; check ""                    "260K: cresce dentro da faixa de 150K, silêncio" "$(run s1)"
turno s1 300000; check "Rode /compact agora" "300K: chega na faixa seguinte, avisa"         "$(run s1)"
turno s3 160000; run s3 >/dev/null
turno s3 310000; linha s3 "$COMPACT"
check ""                     "compact depois da última resposta: silêncio (o usage de antes é velho)" "$(run s3)"
turno s3 180000; check ""                    "primeiro turno depois dele (180K, faixa já avisada): silêncio" "$(run s3)"
linha s3 "$COMPACT"; turno s3 105000
check ""                     "outro compact, 105K: silêncio"                                  "$(run s3)"
turno s3 160000; check "tarefa atual acabou" "cresce de novo até 150K: avisa de novo"      "$(run s3)"
turno s3 305000; check "Rode /compact agora" "…e até 300K"                                  "$(run s3)"

echo "== usage que não é o contexto do turno =="
# Com o advisor, o usage de cima soma as iterações: 410K para um contexto de 206K.
linha s4 '{"type":"assistant","isSidechain":false,"message":{"model":"claude-opus-5-5","usage":{"input_tokens":6,"cache_creation_input_tokens":2000,"cache_read_input_tokens":408130,"output_tokens":900,"iterations":[{"type":"message","input_tokens":2,"cache_creation_input_tokens":1000,"cache_read_input_tokens":202750},{"type":"advisor_message","input_tokens":1,"cache_read_input_tokens":197715},{"type":"message","input_tokens":4,"cache_creation_input_tokens":1000,"cache_read_input_tokens":205380}]}}}'
out=$(run s4)
check "~206K tokens"         "advisor: vale a última iteração message (206K), não a soma (410K)" "$out"
check "tarefa atual acabou"  "…e a faixa é a de 150K"                                         "$out"
# Modelo de fallback responde numa iteração "fallback_message": ela é o contexto do turno.
# Aqui: message 205K, advisor 190K, fallback 312K, e o usage de cima 517K.
linha s10 '{"type":"assistant","isSidechain":false,"message":{"model":"claude-opus-5-5","usage":{"input_tokens":6,"cache_creation_input_tokens":2000,"cache_read_input_tokens":515000,"output_tokens":900,"iterations":[{"type":"message","input_tokens":2,"cache_creation_input_tokens":1000,"cache_read_input_tokens":204000},{"type":"advisor_message","input_tokens":1,"cache_read_input_tokens":190000},{"type":"fallback_message","input_tokens":4,"cache_creation_input_tokens":1000,"cache_read_input_tokens":311000}]}}}'
out=$(run s10)
check "~312K tokens"         "fallback: vale a última iteração fallback_message (312K)"       "$out"
check "^@usuario ⚠️ "        "…e a faixa é a de 300K"                                         "$out"
# Iteração de compaction não é o contexto do turno, nem sendo a última.
linha s11 '{"type":"assistant","isSidechain":false,"message":{"model":"claude-opus-5-5","usage":{"input_tokens":5002,"cache_creation_input_tokens":1000,"cache_read_input_tokens":159000,"output_tokens":300,"iterations":[{"type":"message","input_tokens":2,"cache_creation_input_tokens":1000,"cache_read_input_tokens":159000},{"type":"compaction","input_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}]}}}'
check "~160K tokens"         "compaction como última iteração: vale a message (160K)"         "$(run s11)"
turno s5 310000; run s5 >/dev/null
linha s5 '{"type":"assistant","isSidechain":false,"message":{"model":"<synthetic>","content":[{"type":"text","text":"limite atingido"}],"usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"iterations":null}}}'
check ""                     "resposta <synthetic> de usage zerado: não é turno, silêncio"    "$(run s5)"
turno s5 320000; check ""                    "…e não derruba a faixa: 320K não repete o aviso" "$(run s5)"
linha s5 '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":620000}}}'
check ""                     "linha de subagente (isSidechain) não conta"                     "$(run s5)"

echo "== sem usage: silêncio (falha-aberta) =="
yes '{"x":1}' | head -n 3000 > "$(tp s6)"
check ""                     "3.000 linhas sem usage: silêncio"                               "$(run s6)"
linha s7 '{"type":"user","message":{"role":"user","content":"oi"}}'
check ""                     "sessão nova, só o primeiro prompt: silêncio"                    "$(run s7)"
check ""                     "transcript inexistente: silêncio"                               "$(run s8 "$TMP/nao-existe.jsonl")"

echo "== só o fim do transcript =="
# A janela começa no meio desta linha de 600 KB: a linha partida não pode derrubar a leitura.
linha s9 "{\"type\":\"user\",\"message\":{\"content\":\"$(head -c 600000 /dev/zero | tr '\0' x)\"}}"
turno s9 320000
check "~320K tokens"         "linha partida no começo da janela: lê o último usage mesmo assim" "$(run s9)"
# A janela são os últimos 256 KB: usage atrás de 400 KB sem usage fica fora, atrás de 200 KB
# fica dentro.
sem_usage() { linha "$1" "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"$(head -c $(( $2 * 1024 )) /dev/zero | tr '\0' x)\"}}"; }
turno j1 320000; sem_usage j1 400
check ""                     "usage seguido de 400 KB sem usage: silêncio (fora da janela)"   "$(run j1)"
turno j2 320000; sem_usage j2 200
check "~320K tokens"         "usage seguido de 200 KB sem usage: avisa (dentro da janela)"    "$(run j2)"

echo "== caminho e leitura do transcript =="
# No Windows (Git Bash) o caminho tem barra invertida, e ela tem que chegar intacta.
BS="$TMP"'/C:\Users\pessoa'; mkdir -p "$BS"
turno w1 160000; mv "$(tp w1)" "$BS/t.jsonl"
check "~160K tokens"         "transcript em caminho com barra invertida: avisa"               "$(run w1 "$BS/t.jsonl")"
if [ "$(id -u)" != 0 ]; then
  turno w2 160000; chmod 000 "$(tp w2)"
  check ""                   "transcript sem permissão de leitura (000): silêncio"            "$(run w2)"
  check ""                   "…sem erro no stderr"                                            "$(cat "$TMP/err")"
  chmod 600 "$(tp w2)"
fi

echo "== estado que não persiste: silêncio, nunca um aviso a cada prompt =="
# 700 linhas antes do turno: o hook anterior, que contava linhas, também avisaria aqui.
longa() { yes '{"type":"file-history-snapshot"}' | head -n 700 > "$(tp "$1")"; turno "$1" 320000; }
if [ "$(id -u)" != 0 ]; then
  HOME="$TMP/h-e1"; mkdir -p "$HOME"; longa e1; run e1 >/dev/null
  find "$HOME/.claude/.cache" -type f -exec chmod 000 {} +
  check ""                   "estado sem permissão (000): silêncio"                           "$(run e1)"
  check ""                   "…sem erro no stderr"                                            "$(cat "$TMP/err")"
  check ""                   "…e no prompt seguinte também"                                   "$(run e1)"
  HOME="$TMP/h-e2"; mkdir -p "$HOME"; longa e2; run e2 >/dev/null
  find "$HOME/.claude/.cache" -type f -exec chmod 200 {} +
  check ""                   "estado que grava mas não se lê (200): silêncio"                 "$(run e2)"
  check ""                   "…e no prompt seguinte também"                                   "$(run e2)"
else
  echo "  (root: pulei os casos de permissão, que root ignora)"
fi
HOME="$TMP/h-e3"; mkdir -p "$HOME/.claude"; : > "$HOME/.claude/.cache"; longa e3
check ""                     "pasta de cache impossível de criar: silêncio"                   "$(run e3)"
check ""                     "…sem erro no stderr"                                            "$(cat "$TMP/err")"
check ""                     "…e no prompt seguinte também"                                   "$(run e3)"
HOME="$TMP/home"

echo "== session_id que vira caminho: recusado =="
longa ok
check ""                     "session_id com barra (../fora): silêncio"                       "$(run '../fora' "$(tp ok)")"
check "^nada$"               "…e nada gravado fora da pasta de estado"                        "$([ -e "$CACHE/fora" ] && echo gravou || echo nada)"
check ""                     "session_id que começa com ponto (.oculto): silêncio"            "$(run '.oculto' "$(tp ok)")"
check ""                     "session_id '..': silêncio"                                      "$(run '..' "$(tp ok)")"

echo
echo "== o aviso vai para a pessoa, em tokens =="
sem_dinheiro 150 "$a150"
sem_dinheiro 300 "$a300"
sem_dinheiro 400 "$a400"

echo
check ""                     "nenhuma execução escreveu no stderr"                            "$(cat "$TMP/err-todos" 2>/dev/null)"
echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
