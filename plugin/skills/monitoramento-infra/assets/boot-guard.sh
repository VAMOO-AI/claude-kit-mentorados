#!/usr/bin/env bash
# boot-guard — depois de cada boot, reata service do Docker Swarm que subiu
# fora da overlay (netns só com lo) ou sem escutar a porta em mode host.
#
# Por que existe: reboot iniciado pelo provedor (manutenção, hypervisor) não
# passa pela sua checagem manual. O Traefik pode voltar "1/1 Running" sem
# nada em 80/443, e os sites ficam fora até alguém reclamar.
#
# Uso:
#   boot-guard.sh            o timer chama assim (90s após o boot)
#   boot-guard.sh --agora    pula a espera de estabilização
#   boot-guard.sh --dry-run  só detecta e relata (implica --agora)
#
# Config opcional, arquivo de variáveis (chmod 600). Padrão:
#   /etc/boot-guard/boot-guard.env
# Outra pasta: Environment=BOOT_GUARD_CONF=/etc/<sua-pasta>/boot-guard.env
# na unit. Variáveis aceitas (todas opcionais):
#   NOME=<nome-do-host>                   aparece no alerta e no journal
#   NTFY_URL=https://ntfy.sh/<topico>     sem isto, fica só no journal
#   NTFY_TOKEN=<token>                    se o tópico pede token
#   ORDEM_TIERS="dado proxy app"          ordem de reatar
#   IMAGENS_DADO="redis* postgres* ..."   imagens que contam como dado
#   IMAGENS_PROXY="traefik*"              imagens que contam como proxy
#   ESPERA_DOCKER=600 ESPERA_SWARM=600 FOLGA=60 PASSADAS=3
#
# Labels no service:
#   boot-guard=ignore        fica de fora
#   boot-guard.tier=<tier>   força o tier (dado, proxy ou app)
#
# Saída: 0 = host são no fim; 1 = ainda há service sem rede, sem porta,
# incompleto ou pulado (a unit fica failed e aparece em systemctl --failed);
# 2 = uso ou config inválida.
#
# Compatível com bash 3.2 de propósito (o teste roda no Mac): array vazio
# sempre expandido com ${a[@]+"${a[@]}"}.

set -uo pipefail
# acrescenta, não sobrescreve: quem chama decide o que vem primeiro
PATH="${PATH:-/usr/bin:/bin}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin"

DRY=0
AGORA=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1; AGORA=1 ;;
    --agora) AGORA=1 ;;
    *) echo "uso: $0 [--agora] [--dry-run]" >&2; exit 2 ;;
  esac
done

CONF=${BOOT_GUARD_CONF:-/etc/boot-guard/boot-guard.env}
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"
NOME=${NOME:-$(hostname)}
NTFY_URL=${NTFY_URL:-}
NTFY_TOKEN=${NTFY_TOKEN:-}
ESPERA_DOCKER=${ESPERA_DOCKER:-600}
ESPERA_SWARM=${ESPERA_SWARM:-600}
FOLGA=${FOLGA:-60}
PASSADAS=${PASSADAS:-3}
ORDEM_TIERS=${ORDEM_TIERS:-dado proxy app}
IMAGENS_DADO=${IMAGENS_DADO:-redis* valkey* keydb* postgres* pgvector* \
mysql* mariadb* mongo* rabbitmq* qdrant* minio* elasticsearch* \
clickhouse* docker-socket-proxy*}
IMAGENS_PROXY=${IMAGENS_PROXY:-traefik*}

# ORDEM_TIERS: só dado, proxy e app, sem repetir. Tier esquecido vai no fim.
ORDEM=""
for t in $ORDEM_TIERS; do
  case "$t" in
    dado|proxy|app) ;;
    *) echo "ORDEM_TIERS: tier '$t' desconhecido (use dado, proxy, app)" >&2
       exit 2 ;;
  esac
  case " $ORDEM " in *" $t "*) continue ;; esac
  ORDEM="$ORDEM $t"
done
for t in dado proxy app; do
  case " $ORDEM " in *" $t "*) ;; *) ORDEM="$ORDEM $t" ;; esac
done
ORDEM=${ORDEM# }

LOCK=${BOOT_GUARD_LOCK:-/run/boot-guard.lock}
exec 9>"$LOCK" || { echo "não consegui abrir $LOCK"; exit 1; }
flock -n 9 || { echo "outra execução em andamento; saindo"; exit 0; }

T0=$(date +%s)
log() { printf '[+%4ss] %s\n' "$(( $(date +%s) - T0 ))" "$*"; }

# ---------------------------------------------------------------- espera

espera_docker() {
  local fim=$(( T0 + ESPERA_DOCKER ))
  until docker info >/dev/null 2>&1; do
    [ "$(date +%s)" -ge "$fim" ] && return 1
    sleep 5
  done
}

swarm_pronto() {
  [ "$(docker info -f '{{.Swarm.LocalNodeState}}' 2>/dev/null)" = active ] &&
    docker node ls --format '{{.Self}} {{.Status}}' 2>/dev/null |
      grep -q '^true Ready$'
}

# service com réplica faltando (ignora 0/0 e job concluído)
incompletos() {
  docker service ls --format '{{.Name}} {{.Replicas}}' 2>/dev/null |
    awk '/completed/ {next}
         { split($2, r, "/"); if (r[2]+0 > 0 && r[1]+0 != r[2]+0) print $1 }'
}

espera_swarm() {
  local fim=$(( $(date +%s) + ESPERA_SWARM )) estaveis=0 falta
  until swarm_pronto; do
    [ "$(date +%s)" -ge "$fim" ] && { log "swarm não ficou pronto"; return 1; }
    sleep 5
  done
  log "swarm ativo e node Ready"
  # duas leituras seguidas sem réplica faltando = estável. Vítima em crash
  # loop nunca estabiliza: vencido o teto, segue para o detector assim mesmo.
  while :; do
    falta=$(incompletos)
    if [ -z "$falta" ]; then
      estaveis=$(( estaveis + 1 ))
      [ "$estaveis" -ge 2 ] && { log "réplicas completas"; return 0; }
    else
      estaveis=0
    fi
    if [ "$(date +%s)" -ge "$fim" ]; then
      log "teto de espera; ainda incompletos: $(echo "$falta" | paste -sd' ' -)"
      return 0
    fi
    sleep 15
  done
}

# ---------------------------------------------------------------- detecção

ignorado() {
  [ "$(docker service inspect -f \
    '{{index .Spec.Labels "boot-guard"}}' "$1" 2>/dev/null)" = ignore ]
}

# Detector de netns: container fora de host/none cujo netns só tem lo
# subiu fora da overlay. Preenche SEMREDE (services) e, com $1=tabela,
# imprime a tabela completa (é a prova no journal).
varre() {
  local tabela=${1:-} ids nome modo pid svc ifaces estado
  SEMREDE=()
  ids=$(docker ps -q)
  [ -z "$ids" ] && return 0
  [ "$tabela" = tabela ] &&
    log "netns por container (container | service | ifaces | estado):"
  while IFS='|' read -r nome modo pid svc; do
    nome=${nome#/}
    [ "$svc" = "<no value>" ] && svc=""
    case "$modo" in
      none|host) estado="pulado ($modo)"; ifaces="-" ;;
      *)
        if [ -z "$pid" ] || [ "$pid" = 0 ]; then
          estado="sem pid"; ifaces="-"
        else
          ifaces=$(nsenter -t "$pid" -n ip -4 -o addr show 2>/dev/null |
            awk '{print $2}' | sort -u | paste -sd, -)
          if [ "$ifaces" = lo ]; then
            estado=SEM-REDE
            if [ -n "$svc" ]; then
              SEMREDE+=("$svc")
            else
              estado="SEM-REDE (fora do swarm, só relato)"
            fi
          elif [ -z "$ifaces" ]; then
            estado="netns ilegível"; ifaces="-"
          else
            estado=ok
          fi
        fi ;;
    esac
    [ "$tabela" = tabela ] && log "  $nome | ${svc:--} | $ifaces | $estado"
  done < <(docker inspect -f \
    '{{.Name}}|{{.HostConfig.NetworkMode}}|{{.State.Pid}}|{{index .Config.Labels "com.docker.swarm.service.name"}}' \
    $ids 2>/dev/null)
  return 0
}

# Porta publicada em mode host que não escuta no host (o Traefik "1/1"
# sem 80/443). Preenche SEMPORTA.
checa_portas() {
  local s portas p num proto ativos
  SEMPORTA=()
  ativos=$(docker service ls --format '{{.Name}} {{.Replicas}}' |
    awk '{ split($2, r, "/"); if (r[2]+0 > 0) print $1 }')
  for s in $ativos; do
    portas=$(docker service inspect -f \
      '{{range .Endpoint.Ports}}{{if eq (printf "%s" .PublishMode) "host"}}{{.PublishedPort}}/{{.Protocol}} {{end}}{{end}}' \
      "$s" 2>/dev/null)
    for p in $portas; do
      num=${p%/*}; proto=${p#*/}
      if [ "$proto" = udp ]; then
        ss -Hlnu "sport = :$num" | grep -q . && continue
      else
        ss -Hlnt "sport = :$num" | grep -q . && continue
      fi
      log "SEM-PORTA $s: $p publicada em mode host e nada escuta"
      SEMPORTA+=("$s")
    done
  done
  return 0
}

casa_imagem() { # casa_imagem <imagem> <lista de globs>
  local g
  for g in $2; do
    # shellcheck disable=SC2254
    case "$1" in $g) return 0 ;; esac
  done
  return 1
}

# dado = dependência (banco, cache, fila, socket proxy), proxy = borda,
# app = o resto. A label boot-guard.tier vence a imagem.
tier() {
  local img lbl
  lbl=$(docker service inspect -f \
    '{{index .Spec.Labels "boot-guard.tier"}}' "$1" 2>/dev/null)
  case "$lbl" in dado|proxy|app) echo "$lbl"; return ;; esac
  case "$1" in *socket-proxy*|*socket_proxy*) echo dado; return ;; esac
  img=$(docker service inspect -f \
    '{{.Spec.TaskTemplate.ContainerSpec.Image}}' "$1" 2>/dev/null)
  img=${img%%@*}
  img=${img##*/}
  if casa_imagem "$img" "$IMAGENS_DADO"; then echo dado
  elif casa_imagem "$img" "$IMAGENS_PROXY"; then echo proxy
  else echo app
  fi
}

# ---------------------------------------------------------------- conserto

REATADOS=()
PULADOS=()

ja_reatado() {
  printf '%s\n' ${REATADOS[@]+"${REATADOS[@]}"} | grep -qx "$1"
}

reata() {
  local svc=$1 t=$2 ordem rc
  if ignorado "$svc"; then
    log "ignorado $svc (label boot-guard=ignore)"
    return 0
  fi
  ordem=$(docker service inspect -f \
    '{{if .Spec.UpdateConfig}}{{.Spec.UpdateConfig.Order}}{{end}}' \
    "$svc" 2>/dev/null)
  # start-first em banco sobe um segundo processo no mesmo volume; no
  # proxy disputa 80/443. Nesses o guard não força: só avisa.
  if [ "$ordem" = start-first ] && [ "$t" != app ]; then
    log "PULADO $svc: update_config.order=start-first em tier $t"
    PULADOS+=("$svc")
    return 0
  fi
  if [ "$DRY" = 1 ]; then
    log "DRY-RUN: reataria $svc (tier $t)"
    return 0
  fi
  log "reatando $svc (tier $t): docker service update --force --no-resolve-image"
  timeout 240 docker service update --force --no-resolve-image \
    --detach=false -q "$svc" >/dev/null 2>&1
  rc=$?
  log "  $svc rc=$rc"
  REATADOS+=("$svc")
}

rede_ids() {
  local n
  for n in $(docker service inspect -f \
    '{{range .Spec.TaskTemplate.Networks}}{{.Target}} {{end}}' "$1" 2>/dev/null); do
    docker network inspect -f '{{.Id}}' "$n" 2>/dev/null
  done | sort -u
}

doente() {  # réplica faltando ou container unhealthy em 3 leituras (20s)
  local svc=$1 i c
  for i in 1 2 3; do
    incompletos | grep -qx "$svc" && return 0
    for c in $(docker ps -q --filter "label=com.docker.swarm.service.name=$svc"); do
      [ "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$c")" = unhealthy ] &&
        return 0
    done
    [ "$i" -lt 3 ] && sleep 10
  done
  return 1
}

# Vítima: app que divide rede com uma dependência reatada e continua doente
# (um app em crash loop com "Name does not resolve" porque o Redis dele
# estava fora da rede).
trata_vitimas() {
  local redes_dep s r alvo
  redes_dep=$(for s in "$@"; do rede_ids "$s"; done | sort -u)
  [ -z "$redes_dep" ] && return 0
  log "dependência reatada; esperando 90s antes de olhar as vítimas"
  [ "$DRY" = 1 ] || sleep 90
  for s in $(docker service ls --format '{{.Name}}'); do
    [ "$(tier "$s")" = app ] || continue
    ja_reatado "$s" && continue
    alvo=0
    for r in $(rede_ids "$s"); do
      echo "$redes_dep" | grep -qx "$r" && { alvo=1; break; }
    done
    [ "$alvo" = 1 ] || continue
    if doente "$s"; then
      log "VÍTIMA $s: divide rede com dependência reatada e segue doente"
      reata "$s" app
    fi
  done
}

# ---------------------------------------------------------------- rotas

rotas() {
  local s
  for s in $(docker service ls -q); do
    docker service inspect --format \
      '{{json .Spec.Labels}}{{json .Spec.TaskTemplate.ContainerSpec.Labels}}' "$s"
  done | grep -oE 'Host\(`[^`]+`\)' | grep -oE '`[^`]+`' | tr -d '`' | sort -u
}

codigo() {
  curl -sk -o /dev/null -w '%{http_code}' -m 10 \
    --resolve "$1:443:127.0.0.1" "https://$1/" 2>/dev/null
}

# Rota que devolve 000/5xx pelo proxy local. Só relato: 401/403/404
# estáveis são basic auth ou serviço desligado, não falha.
checa_rotas() {
  local h c todas ruins=() reruins=()
  ROTAS_RUINS=()
  todas=$(rotas)
  for h in $todas; do
    c=$(codigo "$h")
    case "$c" in 000|5*) ruins+=("$h") ;; esac
  done
  if [ "${#ruins[@]}" -gt 0 ] && [ "$DRY" = 0 ]; then
    log "${#ruins[@]} rota(s) com 000/5xx; nova leitura em 60s (apps pesados levam ~90s)"
    sleep 60
  fi
  for h in ${ruins[@]+"${ruins[@]}"}; do
    c=$(codigo "$h")
    case "$c" in 000|5*) reruins+=("$h=$c") ;; esac
  done
  ROTAS_RUINS=(${reruins[@]+"${reruins[@]}"})
  log "rotas: $(echo "$todas" | grep -c .) no proxy, ${#ROTAS_RUINS[@]} com 000/5xx${ROTAS_RUINS[0]+: ${ROTAS_RUINS[*]}}"
}

# ---------------------------------------------------------------- alerta

avisa() {
  local prio=$1 msg=$2 auth=()
  if [ -z "$NTFY_URL" ]; then
    log "alerta: sem canal (NTFY_URL vazio em $CONF); fica só no journal"
    return 0
  fi
  if [ "$DRY" = 1 ]; then
    log "DRY-RUN: avisaria no ntfy (prioridade $prio)"
    return 0
  fi
  [ -n "$NTFY_TOKEN" ] && auth=(-H "Authorization: Bearer $NTFY_TOKEN")
  if curl -fsS -m 15 --retry 4 --retry-delay 15 --retry-all-errors \
      ${auth[@]+"${auth[@]}"} -H "Title: boot-guard $NOME" -H "Priority: $prio" \
      --data-binary "$msg" "$NTFY_URL" >/dev/null 2>&1; then
    log "alerta enviado (prioridade $prio)"
  else
    log "alerta FALHOU ao publicar no ntfy"
  fi
}

ss_web() {
  ss -Hltnp '( sport = :80 or sport = :443 )' | awk '{print $4, $6}'
}

# ---------------------------------------------------------------- main

MODO=boot
[ "$AGORA" = 1 ] && MODO=agora
[ "$DRY" = 1 ] && MODO=dry-run
# timer OnBootSec ativado com o host já de pé dispara na hora: não é boot
if [ "$MODO" = boot ]; then
  UP=$(cut -d. -f1 /proc/uptime)
  if [ "$UP" -gt 1800 ]; then
    MODO=fora-do-boot
    AGORA=1
  fi
fi
BOOT=$(uptime -s 2>/dev/null)
log "== boot-guard $NOME | boot $BOOT | modo $MODO | ordem $ORDEM"

if [ "$AGORA" = 0 ]; then
  if ! espera_docker; then
    log "FALHA: dockerd não respondeu em ${ESPERA_DOCKER}s"
    avisa 5 "$NOME voltou de boot ($BOOT) e o dockerd não respondeu em ${ESPERA_DOCKER}s."
    exit 1
  fi
  log "dockerd respondeu"
  espera_swarm
  log "folga de ${FOLGA}s antes do detector"
  sleep "$FOLGA"
else
  docker info >/dev/null 2>&1 || { log "FALHA: dockerd não responde"; exit 1; }
fi

[ "$DRY" = 1 ] && PASSADAS=1
for passada in $(seq 1 "$PASSADAS"); do
  log "-- passada $passada/$PASSADAS"
  if [ "$passada" = 1 ]; then varre tabela; else varre; fi
  checa_portas
  alvos=$(printf '%s\n' ${SEMREDE[@]+"${SEMREDE[@]}"} \
    ${SEMPORTA[@]+"${SEMPORTA[@]}"} | grep . | sort -u)
  if [ -z "$alvos" ]; then
    log "nenhum service sem rede ou sem porta"
    break
  fi
  log "alvos: $(echo "$alvos" | paste -sd' ' -)"
  deps_reatadas=()
  for t in $ORDEM; do
    for s in $alvos; do
      [ "$(tier "$s")" = "$t" ] || continue
      antes=${#REATADOS[@]}
      reata "$s" "$t"
      [ "$t" = dado ] && [ "${#REATADOS[@]}" -gt "$antes" ] &&
        deps_reatadas+=("$s")
    done
    if [ "$t" = dado ] && [ "${#deps_reatadas[@]}" -gt 0 ]; then
      log "tier dado reatado; 20s para as dependências subirem"
      sleep 20
    fi
  done
  [ "${#deps_reatadas[@]}" -gt 0 ] && trata_vitimas "${deps_reatadas[@]}"
  [ "$DRY" = 1 ] && break
  log "45s para convergir antes de redetectar"
  sleep 45
done

# ---------------------------------------------------------------- prova final

log "-- estado final"
varre tabela
checa_portas
FALTAM=$(incompletos)
log "ss 80/443:"
WEB=$(ss_web)
if [ -n "$WEB" ]; then
  while read -r l; do log "  $l"; done <<< "$WEB"
else
  log "  (nada escuta em 80/443)"
fi
checa_rotas

uniq_lista() { printf '%s\n' "$@" | sort -u | paste -sd' ' -; }
PROBLEMAS=()
[ "${#SEMREDE[@]}" -gt 0 ] &&
  PROBLEMAS+=("sem rede: $(uniq_lista "${SEMREDE[@]}")")
[ "${#SEMPORTA[@]}" -gt 0 ] &&
  PROBLEMAS+=("sem porta: $(uniq_lista "${SEMPORTA[@]}")")
[ -n "$FALTAM" ] &&
  PROBLEMAS+=("incompletos: $(echo "$FALTAM" | paste -sd' ' -)")
[ "${#PULADOS[@]}" -gt 0 ] &&
  PROBLEMAS+=("pulados (start-first): ${PULADOS[*]}")

RESUMO="$NOME boot $BOOT."
[ "${#REATADOS[@]}" -gt 0 ] && RESUMO+=" Reatados: ${REATADOS[*]}."
[ "${#PROBLEMAS[@]}" -gt 0 ] &&
  RESUMO+=" AINDA QUEBRADO: $(printf '%s; ' "${PROBLEMAS[@]}")"
[ "${#ROTAS_RUINS[@]}" -gt 0 ] && RESUMO+=" Rotas 000/5xx: ${ROTAS_RUINS[*]}."
[ "${#REATADOS[@]}" -eq 0 ] && [ "${#PROBLEMAS[@]}" -eq 0 ] &&
  RESUMO+=" Nada a reatar."
log "RESUMO: $RESUMO"

if [ "${#PROBLEMAS[@]}" -gt 0 ]; then
  avisa 5 "$RESUMO"
  exit 1
elif [ "${#REATADOS[@]}" -gt 0 ] || [ "${#ROTAS_RUINS[@]}" -gt 0 ]; then
  avisa 4 "$RESUMO"
elif [ "$MODO" = boot ]; then
  # reboot que ninguém pediu precisa ser visto mesmo quando volta são
  avisa 2 "$RESUMO"
fi
exit 0
