#!/usr/bin/env bash
# Prova do plugin/skills/monitoramento-infra/assets/boot-guard.sh com um Swarm de mentira.
#
# O guard roda sozinho depois de cada boot de uma VPS com Docker Swarm + Traefik e
# reata service que voltou "1/1" fora da overlay (netns só com lo) ou sem escutar a
# porta publicada em mode host. Aqui `docker`, `nsenter`, `ss`, `curl`, `flock`,
# `timeout`, `uptime` e `sleep` são stubs no PATH: o teste roda no Mac e no CI sem
# Docker e sem root. O stub do docker grava cada chamada, e o teste exige que ele
# tenha sido chamado: se o script voltar a sobrescrever o PATH, o docker de verdade
# do runner responderia no lugar e o teste passaria por acaso.
#
# Casos: reata na ordem padrão (dado -> proxy -> app); ORDEM_TIERS muda a ordem;
# host saudável não reata nada; --dry-run só relata; start-first em dado não é
# forçado; label boot-guard=ignore fica de fora; ORDEM_TIERS inválida sai 2.
#
# Uso: bash tests/test-boot-guard.sh [caminho-do-script]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
S="${1:-$RAIZ/plugin/skills/monitoramento-infra/assets/boot-guard.sh}"
[ -f "$S" ] || { echo "script não encontrado: $S"; exit 2; }
bash -n "$S" || { echo "bash -n reprovou $S"; exit 1; }

falhas=0
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bootguard.XXXXXX")
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

# ------------------------------------------------------------------ stubs
STUB="$TMP/bin"
mkdir -p "$STUB"

# Estado do Swarm falso em $FAKE/svc/<nome>/: image, replicas, pid, ifaces, nets,
# ports (host mode, "443/tcp"), order, ignore, tier, host (rota do Traefik).
# Porta que escuta no host: arquivo $FAKE/listen/<n>.
cat > "$STUB/docker" <<'SH'
#!/usr/bin/env bash
F="$FAKE"
echo "$*" >> "$F/docker.log"
lista() { ls "$F/svc"; }
le() { [ -f "$F/svc/$1/$2" ] && cat "$F/svc/$1/$2"; return 0; }
case "$1" in
  info) exit 0 ;;
  ps)
    if [ "${3:-}" = --filter ]; then
      echo "${4#label=com.docker.swarm.service.name=}"
    else
      lista
    fi ;;
  inspect)
    fmt=$3; shift 3
    for id in "$@"; do
      case "$fmt" in
        *NetworkMode*) echo "/$id.1.abc|overlay|$(le "$id" pid)|$id" ;;
        *Health*) le "$id" health ;;
      esac
    done ;;
  network) echo "id-${5}" ;;
  service)
    case "$2" in
      ls)
        if [ "${3:-}" = -q ]; then lista; exit 0; fi
        for s in $(lista); do
          case "$4" in
            *Replicas*) echo "$s $(le "$s" replicas)" ;;
            *) echo "$s" ;;
          esac
        done ;;
      inspect)
        fmt=$4; s=$5
        case "$fmt" in
          *boot-guard.tier*) le "$s" tier ;;
          *'"boot-guard"'*) [ -f "$F/svc/$s/ignore" ] && echo ignore ;;
          *UpdateConfig*) le "$s" order ;;
          *ContainerSpec.Image*) le "$s" image ;;
          *Endpoint.Ports*) le "$s" ports ;;
          *TaskTemplate.Networks*) le "$s" nets ;;
          *'json .Spec.Labels'*)
            h=$(le "$s" host)
            if [ -n "$h" ]; then
              printf '{"traefik.http.routers.r.rule":"Host(`%s`)"}{}\n' "$h"
            else
              echo '{}{}'
            fi ;;
        esac ;;
      update)
        s="${!#}"
        echo "$s" >> "$F/updates.log"
        echo "eth0 lo" > "$F/svc/$s/ifaces"
        for p in $(le "$s" ports); do : > "$F/listen/${p%/*}"; done ;;
    esac ;;
esac
exit 0
SH

cat > "$STUB/nsenter" <<'SH'
#!/usr/bin/env bash
for s in $(ls "$FAKE/svc"); do
  [ "$(cat "$FAKE/svc/$s/pid")" = "$2" ] || continue
  for i in $(cat "$FAKE/svc/$s/ifaces"); do
    echo "1: $i    inet 10.0.0.1/24 scope global $i"
  done
done
SH

cat > "$STUB/ss" <<'SH'
#!/usr/bin/env bash
for n in $(printf '%s\n' "$@" | grep -oE ':[0-9]+' | tr -d :); do
  [ -f "$FAKE/listen/$n" ] && echo "LISTEN 0 4096 0.0.0.0:$n 0.0.0.0:* users:((\"docker-proxy\"))"
done
exit 0
SH

cat > "$STUB/curl" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/curl.log"
case "$*" in *http_code*) printf 200 ;; esac
exit 0
SH

printf '#!/bin/sh\nexit 0\n' > "$STUB/flock"
printf '#!/bin/sh\nexit 0\n' > "$STUB/sleep"
printf '#!/bin/sh\nshift\nexec "$@"\n' > "$STUB/timeout"
printf '#!/bin/sh\necho "2026-01-01 00:00:00"\n' > "$STUB/uptime"
chmod +x "$STUB"/*

# ------------------------------------------------------------------ fixtures
svc() { # svc <caso> <nome> <image> <pid> <ifaces> [ports]
  local d="$TMP/$1/svc/$2"
  mkdir -p "$d" "$TMP/$1/listen"
  echo "$3" > "$d/image"; echo 1/1 > "$d/replicas"; echo "$4" > "$d/pid"
  echo "$5" > "$d/ifaces"; echo rede-app > "$d/nets"
  [ -n "${6:-}" ] && echo "$6" > "$d/ports"
  return 0
}

quebrado() { # o cenário do incidente: dado sem rede, proxy sem porta, app são
  svc "$1" app-web ghcr.io/exemplo/app:1.0 103 "eth0 lo"
  echo app.exemplo.com > "$TMP/$1/svc/app-web/host"
  svc "$1" cache-redis redis:7-alpine 101 "lo"
  svc "$1" borda-traefik traefik:v3.5 102 "eth0 lo" "443/tcp"
}

saudavel() {
  quebrado "$1"
  echo "eth0 lo" > "$TMP/$1/svc/cache-redis/ifaces"
  : > "$TMP/$1/listen/443"
}

roda() { # roda <caso> [env=...] -- [args]  -> $TMP/<caso>/out e /rc
  local caso=$1; shift
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ "${1:-}" = -- ] && shift
  local F="$TMP/$caso"
  : > "$F/docker.log"; : > "$F/updates.log"
  env PATH="$STUB:$PATH" FAKE="$F" BOOT_GUARD_CONF="$F/nao-existe.env" \
    BOOT_GUARD_LOCK="$F/lock" ${envs[@]+"${envs[@]}"} \
    bash "$S" "$@" > "$F/out" 2>&1
  echo $? > "$F/rc"
}

rc()      { cat "$TMP/$1/rc"; }
updates() { paste -sd' ' - < "$TMP/$1/updates.log"; }
tem()     { grep -qF -- "$2" "$TMP/$1/out"; }
mostra()  { sed 's/^/        | /' "$TMP/$1/out"; }

confere() { # confere <caso> <descrição> <condição...>
  local caso=$1 d=$2; shift 2
  if "$@"; then ok "$d"; else falha "$d"; mostra "$caso"; fi
}

usou_stub() { [ -s "$TMP/$1/docker.log" ]; }

echo "boot-guard: $S"

# 1. reata na ordem padrão
quebrado padrao
roda padrao -- --agora
confere padrao "o stub do docker foi chamado (PATH não sobrescrito)" usou_stub padrao
confere padrao "reata dado antes do proxy (ordem padrão)" \
  test "$(updates padrao)" = "cache-redis borda-traefik"
confere padrao "sai 0 quando tudo voltou" test "$(rc padrao)" = 0
confere padrao "o log diz o tier de cada reatado" \
  tem padrao "reatando cache-redis (tier dado)"
confere padrao "app são não é reatado" \
  bash -c "! grep -qx app-web '$TMP/padrao/updates.log'"
confere padrao "a tabela de netns aponta o SEM-REDE" tem padrao "SEM-REDE"

# 2. ORDEM_TIERS muda a ordem
quebrado ordem
roda ordem ORDEM_TIERS="proxy dado app" -- --agora
confere ordem "ORDEM_TIERS=\"proxy dado app\" reata o proxy primeiro" \
  test "$(updates ordem)" = "borda-traefik cache-redis"

# 3. host saudável
saudavel sao
roda sao NTFY_URL="https://ntfy.exemplo/<topico>" -- --agora
confere sao "saudável: nenhum service reatado" test -z "$(updates sao)"
confere sao "saudável: sai 0" test "$(rc sao)" = 0
confere sao "saudável: diz que não havia nada" \
  tem sao "nenhum service sem rede ou sem porta"
confere sao "saudável fora do boot: não publica alerta" \
  bash -c "! grep -q ntfy '$TMP/sao/curl.log' 2>/dev/null"

# 4. dry-run
quebrado dry
roda dry NTFY_URL="https://ntfy.exemplo/<topico>" -- --dry-run
confere dry "dry-run não chama service update" test -z "$(updates dry)"
confere dry "dry-run relata o que reataria" tem dry "DRY-RUN: reataria cache-redis"
confere dry "dry-run sai 1 com o host ainda quebrado" test "$(rc dry)" = 1
confere dry "dry-run não publica alerta" \
  bash -c "! grep -q ntfy '$TMP/dry/curl.log' 2>/dev/null"

# 5. start-first em dado não é forçado
quebrado sf
echo start-first > "$TMP/sf/svc/cache-redis/order"
roda sf -- --agora
confere sf "start-first em dado: não reata o banco" \
  bash -c "! grep -qx cache-redis '$TMP/sf/updates.log'"
confere sf "start-first em dado: relata PULADO" tem sf "PULADO cache-redis"
confere sf "start-first em dado: sai 1" test "$(rc sf)" = 1

# 6. label boot-guard=ignore
quebrado ign
: > "$TMP/ign/svc/cache-redis/ignore"
roda ign -- --agora
confere ign "label boot-guard=ignore fica de fora" \
  bash -c "! grep -qx cache-redis '$TMP/ign/updates.log'"
confere ign "o proxy segue sendo reatado" \
  test "$(updates ign)" = "borda-traefik"

# 7. label boot-guard.tier vence a imagem
quebrado lbl
echo app > "$TMP/lbl/svc/cache-redis/tier"
roda lbl -- --agora
confere lbl "label boot-guard.tier=app manda o redis para o fim" \
  test "$(updates lbl)" = "borda-traefik cache-redis"

# 8. ORDEM_TIERS inválida
quebrado inv
roda inv ORDEM_TIERS="dado banco app" -- --agora
confere inv "ORDEM_TIERS com tier desconhecido sai 2" test "$(rc inv)" = 2
confere inv "e não toca em nada" test -z "$(updates inv)"

echo
if [ "$falhas" -eq 0 ]; then
  echo "boot-guard: tudo certo"
  exit 0
fi
echo "boot-guard: $falhas falha(s)"
exit 1
