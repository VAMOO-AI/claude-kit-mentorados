#!/usr/bin/env bash
# O roteiro humano devolve resposta de gente — não a linha seguinte do próprio roteiro.
#
# O primeiro bug do plugin/scripts/hitl-loop.sh (no kit do time, antes do porte) foi
# esse: com o roteiro entrando por stdin (`done < "$ROTEIRO"`), o fd 0 do processo VIRA
# o roteiro, e o `read` da resposta colhia a próxima diretiva como se a pessoa tivesse
# digitado. A saída era `TOCOU=captura ERRO Cole o erro` — plausível o bastante para o
# agente registrar como evidência. Por isso o caso das duas capturas seguidas é o
# primeiro daqui e não sai.
#
# O outro modo de falha é silencioso e pior: resposta em branco virar "verificado".
# Enter vazio tem que reprovar com o nome da variável que ficou sem resposta.
#
# O script roda com o mesmo bash que roda este teste ($BASH): `/bin/bash tests/...`
# no macOS exercita o bash 3.2 que o mentorado tem.
#
# Uso: bash tests/test-hitl-loop.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
HITL="$RAIZ/plugin/scripts/hitl-loop.sh"
[ -f "$HITL" ] || { echo "script não encontrado: $HITL"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/hitl.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

roda() { # roda <roteiro> <respostas> [args...] — grava saída em $TMP/saida.txt, ecoa o exit
  local roteiro="$1" respostas="$2"; shift 2
  printf '%s' "$respostas" | HITL_TESTE=1 "${BASH:-bash}" "$HITL" "$roteiro" "$@" > "$TMP/saida.txt" 2>&1
  echo $?
}

echo "== duas capturas seguidas: a resposta é da pessoa, não do roteiro =="
cat > "$TMP/duas.txt" <<'TXT'
captura TOCOU O áudio tocou? (s/n)
captura ERRO Cole o erro do console (ou 'nenhum')
TXT
rc="$(roda "$TMP/duas.txt" 's
nenhum
')"
check "sai 0 com as duas respondidas" "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "TOCOU recebe 's', não a linha 'captura ERRO ...'" \
  "$(grep -qx 'TOCOU=s' "$TMP/saida.txt" && echo ok || echo fail)"
check "ERRO recebe 'nenhum'" \
  "$(grep -qx 'ERRO=nenhum' "$TMP/saida.txt" && echo ok || echo fail)"
check "nenhuma variável capturou texto de diretiva" \
  "$(grep -q '=captura ' "$TMP/saida.txt" && echo fail || echo ok)"

cat > "$TMP/roteiro.txt" <<'TXT'
# um comentário é ignorado
passo Abra o app e entre com a conta de teste

captura TOCOU O áudio tocou? (s/n)
captura ERRO Cole o erro do console (ou 'nenhum')
TXT

echo "== fluxo com passo, comentário e linha vazia =="
rc="$(roda "$TMP/roteiro.txt" '
s
nenhum
')"
check "sai 0 quando tudo foi respondido" "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "o Enter do passo não vira resposta da captura" \
  "$(grep -qx 'TOCOU=s' "$TMP/saida.txt" && grep -qx 'ERRO=nenhum' "$TMP/saida.txt" && echo ok || echo fail)"
check "comentário e linha vazia não viram pergunta" \
  "$([ "$(grep -c '^>>> ' "$TMP/saida.txt")" = 3 ] && echo ok || echo fail)"

echo "== resposta em branco não é evidência =="
rc="$(roda "$TMP/roteiro.txt" '


')"
check "sai 1 quando alguém só deu Enter"        "$([ "$rc" = 1 ] && echo ok || echo fail)"
check "e diz qual variável ficou sem resposta"  "$(grep -q 'TOCOU ficou sem resposta' "$TMP/saida.txt" && echo ok || echo fail)"

echo "== exit 0 é 'respondido', não 'passou' =="
rc="$(roda "$TMP/duas.txt" 'n
TypeError: play() failed
')"
check "resposta 'n' ainda sai 0 — o veredito é do valor" "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "e o valor chega intacto"                          "$(grep -qx 'TOCOU=n' "$TMP/saida.txt" && echo ok || echo fail)"

echo "== roteiro só com passos =="
printf 'passo Abra o app\npasso Feche o app\n' > "$TMP/so-passos.txt"
rc="$(roda "$TMP/so-passos.txt" '

')"
check "sai 0 sem nenhuma captura (array vazio no bash 3.2)" "$([ "$rc" = 0 ] && echo ok || echo fail)"

echo "== roteiro malformado para de vez, não improvisa =="
printf 'pergunta O que aconteceu?\n' > "$TMP/ruim.txt"
rc="$(roda "$TMP/ruim.txt" '')"
check "diretiva desconhecida sai 2"          "$([ "$rc" = 2 ] && echo ok || echo fail)"
check "e nomeia a linha"                     "$(grep -q 'linha 1' "$TMP/saida.txt" && echo ok || echo fail)"

printf 'captura SOZINHA\n' > "$TMP/sem-pergunta.txt"
rc="$(roda "$TMP/sem-pergunta.txt" '')"
check "captura sem pergunta sai 2"           "$([ "$rc" = 2 ] && echo ok || echo fail)"

printf '# só comentário\n\n' > "$TMP/vazio.txt"
rc="$(roda "$TMP/vazio.txt" '')"
check "roteiro sem passo nem captura sai 2"  "$([ "$rc" = 2 ] && echo ok || echo fail)"

rc="$(roda "$TMP/nao-existe.txt" '')"
check "roteiro inexistente sai 2"            "$([ "$rc" = 2 ] && echo ok || echo fail)"

echo "== --saida grava o capturado para o agente ler =="
rc="$(roda "$TMP/roteiro.txt" '
n
TypeError: play() failed
' --saida "$TMP/capturado.txt")"
check "sai 0"                                 "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "o arquivo tem as duas variáveis"       "$([ -f "$TMP/capturado.txt" ] && grep -qx 'TOCOU=n' "$TMP/capturado.txt" && grep -q '^ERRO=TypeError' "$TMP/capturado.txt" && echo ok || echo fail)"

# Só dá para provar onde não há terminal (CI, Bash do agente). Num terminal de verdade
# o script ficaria esperando resposta, então o caso é pulado.
if ! (exec </dev/tty) 2>/dev/null; then
  echo "== sem terminal para antes de perguntar, não colhe resposta vazia =="
  printf 'captura CHEGOU A notificação chegou? (s/n)\n' > "$TMP/sem-tty.txt"
  "${BASH:-bash}" "$HITL" "$TMP/sem-tty.txt" < /dev/null > "$TMP/saida.txt" 2>&1
  rc=$?
  check "sai 2"                                 "$([ "$rc" = 2 ] && echo ok || echo fail)"
  check "e diz que falta terminal"              "$(grep -q 'sem terminal interativo' "$TMP/saida.txt" && echo ok || echo fail)"
  check "sem chegar à pergunta"                 "$(grep -q 'CHEGOU' "$TMP/saida.txt" && echo fail || echo ok)"
fi

echo "== -h mostra o uso sem vazar código =="
"${BASH:-bash}" "$HITL" -h > "$TMP/help.txt" 2>&1
check "o help traz o uso"                     "$(grep -q 'Uso' "$TMP/help.txt" && echo ok || echo fail)"
check "e para antes do set -uo pipefail"      "$(grep -q 'set -uo' "$TMP/help.txt" && echo fail || echo ok)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
