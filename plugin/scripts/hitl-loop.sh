#!/usr/bin/env bash
# O agente não consegue clicar, ouvir nem ver — mas pode conduzir quem consegue.
#
# Tem verificação que o agente não fecha sozinho: "o áudio toca no celular?",
# "a notificação chegou no aparelho?", "o PDF sai certo na impressora?". Pedido
# em prosa no meio da resposta volta em texto solto e não vira evidência de nada.
# Este script conduz o roteiro no terminal de quem está na frente da máquina e
# devolve as respostas em KEY=VALUE, que o agente lê como dado.
#
# O roteiro é um ARQUIVO que o agente escreve; este script não se edita.
# Duas diretivas, uma por linha (linha vazia e linha com # são ignoradas):
#
#   passo <instrução>              → mostra e espera Enter
#   captura <VAR> <pergunta>       → mostra, lê a resposta e guarda em VAR
#
# Uso (no terminal da pessoa, com caminhos absolutos):
#   bash /caminho/do/plugin/scripts/hitl-loop.sh /tmp/roteiro.txt --saida /tmp/capturado.txt
#
# Exemplo de roteiro:
#   passo Abra o app no celular e entre com a conta de teste
#   captura CHEGOU Dispare o lembrete pelo painel. A notificação chegou? (s/n)
#   captura ERRO Se não chegou, cole o erro do console (ou 'nenhum')
#
# Exit 0 = todas as perguntas tiveram resposta — NÃO quer dizer que passou.
# CHEGOU=n com exit 0 é reprovação; quem decide é quem lê os valores.
# Exit 1 = alguma captura ficou em branco. Exit 2 = roteiro ou uso inválido.
#
# Origem: hitl-loop.template.sh da coleção afonsoft/skills (MIT), via o kit do
# time. Lá o roteiro fica dentro do script; aqui é arquivo à parte.
set -uo pipefail

ajuda() { sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# -h vem antes de ler o roteiro: como primeiro argumento ele virava o nome do arquivo.
case "${1:-}" in -h|--help) ajuda ;; esac

ROTEIRO="${1:-}"
SAIDA=""
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --saida) SAIDA="${2:-}"; shift 2 ;;
    -h|--help) ajuda ;;
    *) echo "opção desconhecida: $1"; exit 2 ;;
  esac
done

[ -n "$ROTEIRO" ] || { echo "uso: $0 <roteiro.txt> [--saida <arquivo>]"; exit 2; }
[ -f "$ROTEIRO" ] || { echo "roteiro não encontrado: $ROTEIRO"; exit 2; }

# Sem terminal não há humano para responder: melhor parar do que colher resposta
# vazia e o agente tratar isso como "verificado".
#
# As respostas vêm do /dev/tty para funcionar mesmo com a saída redirecionada.
# HITL_TESTE=1 troca a origem para stdin — é o que deixa tests/test-hitl-loop.sh
# exercitar o fluxo.
ENTRADA="/dev/tty"
if [ -n "${HITL_TESTE:-}" ]; then
  ENTRADA="/dev/stdin"
elif [ ! -t 0 ] && [ ! -r /dev/tty ]; then
  echo "FALHA: sem terminal interativo — este script precisa de alguém para responder."
  exit 2
fi

VARS=()
VALORES=()
n_passos=0

printf '\n=== roteiro: %s ===\n' "$ROTEIRO"

# O roteiro entra por um descritor próprio (fd 3), não por stdin: com `done < arquivo`
# o fd 0 do processo VIRA o roteiro, e aí `read < /dev/stdin` colhe a próxima linha do
# roteiro como se fosse resposta da pessoa. Foi o primeiro bug deste script.
linha_num=0
while IFS= read -r linha <&3 || [ -n "$linha" ]; do
  linha_num=$((linha_num + 1))
  case "$linha" in
    ''|'#'*) continue ;;
  esac

  diretiva="${linha%% *}"
  resto="${linha#* }"

  case "$diretiva" in
    passo)
      n_passos=$((n_passos + 1))
      printf '\n>>> %s\n' "$resto"
      read -r -p "    [Enter quando terminar] " _ < "$ENTRADA" || true
      ;;
    captura)
      var="${resto%% *}"
      pergunta="${resto#* }"
      if [ -z "$var" ] || [ "$var" = "$pergunta" ]; then
        echo "FALHA: linha $linha_num — 'captura' precisa de VAR e pergunta"
        exit 2
      fi
      printf '\n>>> %s\n' "$pergunta"
      resposta=""
      read -r -p "    > " resposta < "$ENTRADA" || true
      VARS+=("$var")
      VALORES+=("$resposta")
      ;;
    *)
      echo "FALHA: linha $linha_num — diretiva desconhecida '$diretiva' (use 'passo' ou 'captura')"
      exit 2
      ;;
  esac
done 3< "$ROTEIRO"

if [ "${#VARS[@]}" -eq 0 ] && [ "$n_passos" -eq 0 ]; then
  echo "FALHA: roteiro sem nenhum passo ou captura"
  exit 2
fi

emite() {
  printf -- '--- capturado ---\n'
  local i
  for i in "${!VARS[@]}"; do
    printf '%s=%s\n' "${VARS[$i]}" "${VALORES[$i]}"
  done
}

printf '\n'
emite
[ -n "$SAIDA" ] && { emite > "$SAIDA"; printf '\n(gravado em %s)\n' "$SAIDA"; }

# Resposta em branco não é evidência: o agente precisa saber que ficou sem
# resposta em vez de assumir que passou.
for i in "${!VARS[@]}"; do
  [ -n "${VALORES[$i]}" ] || { printf '\nFALHA: %s ficou sem resposta\n' "${VARS[$i]}"; exit 1; }
done
exit 0
