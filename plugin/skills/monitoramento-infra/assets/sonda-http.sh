#!/usr/bin/env bash
# Sonda HTTP mínima com alerta no ntfy: antiflap, recovery só de quem foi
# avisado, lembrete enquanto continua fora e heartbeat externo.
#
# Rode FORA da máquina que ela vigia (outra VPS, um Raspberry, o cron de
# um serviço externo). Sonda na mesma VPS do sistema morre junto com ele.
#
# Uso:  NTFY_URL=https://ntfy.sh/<topico> ALVOS=/opt/sonda/alvos.txt \
#         bash sonda-http.sh
# Cron: */5 * * * * /usr/bin/flock -n /tmp/sonda.lock \
#         /opt/sonda/sonda-http.sh >> /var/log/sonda.log 2>&1
#
# alvos.txt — uma linha por alvo:  <nome> <url> [status,aceitos]
#   site  https://meusite.com.br
#   n8n   https://n8n.meudominio.com/healthz
#   painel https://painel.meudominio.com 200,401
#
# Variáveis:
#   NTFY_URL       URL completa do tópico (obrigatória; é credencial: fora do git)
#   NTFY_TOKEN     token tk_... se o tópico for protegido (opcional)
#   ALVOS          arquivo de alvos (padrão: alvos.txt ao lado do script)
#   ESTADO         pasta de estado (padrão: /var/tmp/sonda-http)
#   LIMIAR         falhas seguidas até avisar (padrão: 2)
#   LEMBRETE_H     horas entre lembretes de "ainda fora" (padrão: 24; 0 desliga)
#   HEARTBEAT_URL  URL pingada ao fim de cada rodada (healthchecks.io etc.)
#   TIMEOUT        segundos por requisição (padrão: 10)
set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
ALVOS="${ALVOS:-$AQUI/alvos.txt}"
ESTADO="${ESTADO:-/var/tmp/sonda-http}"
LIMIAR="${LIMIAR:-2}"
LEMBRETE_H="${LEMBRETE_H:-24}"
TIMEOUT="${TIMEOUT:-10}"
: "${NTFY_URL:?defina NTFY_URL (https://ntfy.sh/<topico>)}"
[ -f "$ALVOS" ] || { echo "arquivo de alvos não existe: $ALVOS"; exit 2; }
mkdir -p "$ESTADO" && chmod 700 "$ESTADO"

NTFY_RAIZ="${NTFY_URL%/*}"
NTFY_TOPICO="${NTFY_URL##*/}"
agora=$(date -u +%s)

json() { # escapa para string JSON (barra, aspas, quebra de linha)
  local s=${1//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}
  printf '"%s"' "$s"
}

avisa() { # avisa <prioridade 1-5> <tag> <título> <mensagem> [link]
  # JSON na raiz do servidor: o título aceita acento e emoji, o que
  # header HTTP não garante em todo cliente.
  local corpo
  corpo="{\"topic\":$(json "$NTFY_TOPICO"),\"priority\":$1"
  corpo+=",\"tags\":[$(json "$2")],\"title\":$(json "$3")"
  corpo+=",\"message\":$(json "$4")"
  [ -n "${5:-}" ] && corpo+=",\"click\":$(json "$5")"
  corpo+="}"
  local auth=()
  [ -n "${NTFY_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $NTFY_TOKEN")
  if ! curl -fsS -m 10 ${auth[@]+"${auth[@]}"} -H 'Content-Type: application/json' \
       -d "$corpo" "$NTFY_RAIZ" > /dev/null; then
    echo "$(date -u +%FT%TZ) FALHA ao avisar no ntfy: $3"
    return 1
  fi
}

sonda() { # sonda <url> → imprime o código HTTP (000 = sem resposta)
  local c
  c=$(curl -s -o /dev/null -w '%{http_code}' -m "$TIMEOUT" "$1")
  # segunda tentativa só quando não veio resposta nenhuma
  [ "$c" = 000 ] && sleep 3 && \
    c=$(curl -s -o /dev/null -w '%{http_code}' -m "$TIMEOUT" "$1")
  echo "$c"
}

# 1ª passada: mede tudo antes de decidir qualquer coisa
nomes=(); urls=(); aceitos=(); codigos=()
while read -r nome url ok _; do
  case "$nome" in ''|\#*) continue;; esac
  nomes+=("$nome"); urls+=("$url"); aceitos+=("${ok:-200,301,302}")
done < "$ALVOS"
total=${#nomes[@]}
[ "$total" -gt 0 ] || { echo "nenhum alvo em $ALVOS"; exit 2; }
sem_resposta=0
for i in "${!nomes[@]}"; do
  codigos[$i]=$(sonda "${urls[$i]}")
  [ "${codigos[$i]}" = 000 ] && sem_resposta=$((sem_resposta + 1))
done

# Guarda do checker: com 5+ alvos e 60%+ sem resposta, quem caiu foi a
# rede DESTA máquina. Não grava nada — mas só por 10 min, senão uma
# queda real de tudo cala a sonda para sempre.
if [ "$total" -ge 5 ] && [ $((sem_resposta * 100 / total)) -ge 60 ]; then
  desde=$(cat "$ESTADO/.cego" 2>/dev/null || echo "$agora")
  echo "$desde" > "$ESTADO/.cego"
  if [ $((agora - desde)) -lt 600 ]; then
    echo "$(date -u +%FT%TZ) $sem_resposta/$total sem resposta: checker cego"
    exit 0
  fi
else
  rm -f "$ESTADO/.cego"
fi

for i in "${!nomes[@]}"; do
  nome=${nomes[$i]}; url=${urls[$i]}; c=${codigos[$i]}
  f="$ESTADO/$nome"
  falhas=0; avisado=0; desde=0; lembrete=0; causa=""
  # shellcheck disable=SC1090
  [ -f "$f" ] && . "$f"

  if [[ ",${aceitos[$i]}," == *",$c,"* ]]; then
    if [ "$avisado" = 1 ]; then
      fora=$(( (agora - desde) / 60 ))
      avisa 3 white_check_mark "✅ RECUPERADO · $nome" \
        "$nome respondeu $c depois de ${fora} min fora. Causa: $causa" "$url"
    fi
    rm -f "$f"
    continue
  fi

  falhas=$((falhas + 1))
  if [ "$falhas" = 1 ]; then  # a causa fica a da abertura
    desde=$agora; causa="HTTP $c"
    [ "$c" = 000 ] && causa="sem resposta em ${TIMEOUT}s"
  fi
  if [ "$avisado" = 0 ] && [ "$falhas" -ge "$LIMIAR" ]; then
    # avisa uma vez por queda (e tenta de novo se o ntfy falhou);
    # quem insiste depois é o lembrete
    avisa 5 rotating_light "🔴 FORA · $nome" \
      "$nome falhou ${falhas}x seguidas ($causa)." "$url" \
      && avisado=1 && lembrete=$agora
  elif [ "$avisado" = 1 ] && [ "$LEMBRETE_H" -gt 0 ] && \
       [ $((agora - lembrete)) -ge $((LEMBRETE_H * 3600)) ]; then
    fora=$(( (agora - desde) / 3600 ))
    avisa 4 warning "🔴 AINDA FORA · $nome" \
      "$nome continua fora há ${fora}h ($causa)." "$url" && lembrete=$agora
  fi
  printf 'falhas=%s\navisado=%s\ndesde=%s\nlembrete=%s\ncausa=%q\n' \
    "$falhas" "$avisado" "$desde" "$lembrete" "$causa" > "$f"
done

# Quem vigia o vigia: o heartbeat externo grita quando ESTE ping some.
[ -n "${HEARTBEAT_URL:-}" ] && curl -fsS -m 10 "$HEARTBEAT_URL" > /dev/null
exit 0
