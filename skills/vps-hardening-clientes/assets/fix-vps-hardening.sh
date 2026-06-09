#!/bin/bash
# VPS Hardening — receita Cliente A/Cliente B
# Aplicar em VPS Hostinger/Hetzner/DigitalOcean com Docker Swarm + Traefik
# Validado em: Cliente A (emergencial 2026-05-12), Cliente B (preventivo 2026-05-14)
#
# REGRAS DE FORMATO (não quebrar):
# - Toda linha < 75 chars (Termius bracketed-paste corta acima disso)
# - Sem heredoc (EOF com indent quebra)
# - Sem printf '%s\n' multi-arg gigante
# - docker service create em múltiplas linhas com \
#
# USO:
#   1. ssh root@VPS
#   2. nano /tmp/fix-vps.sh   (cola este conteúdo)
#   3. Ctrl+O, Enter, Ctrl+X
#   4. bash /tmp/fix-vps.sh
#
# ANTES DE RODAR: ajustar variável DOMAIN_BASE e lista de subdomínios em [7]

set -e
TS=$(date +%Y%m%d-%H%M%S)
TD=/opt/docker/swarm/traefik
F=$TD/nginx-docker-proxy.conf
S=/var/run/docker.sock
T=traefik_traefik
D=docker-socket-proxy
DOMAIN_BASE=clienteb.exemplo.com  # <-- AJUSTAR pra cada cliente

echo "[1/9] BACKUP TS=$TS"
cp $TD/traefik.yml $TD/traefik.yml.bak-$TS
cp $TD/stack.yml $TD/stack.yml.bak-$TS
cp $TD/.env $TD/.env.bak-$TS 2>/dev/null || true

echo "[2/9] NGINX CONFIG"
> $F
echo 'user root;' >> $F
echo 'events {}' >> $F
echo 'http {' >> $F
echo '  upstream docker_sock {' >> $F
echo '    server unix:/var/run/docker.sock;' >> $F
echo '  }' >> $F
echo '  server {' >> $F
echo '    listen 2375;' >> $F
echo '    location ~ "^/v[0-9.]+/(.*)$" {' >> $F
echo '      limit_except GET HEAD { deny all; }' >> $F
echo '      proxy_pass http://docker_sock/$1$is_args$args;' >> $F
echo '      proxy_set_header Host docker;' >> $F
echo '    }' >> $F
echo '    location / {' >> $F
echo '      limit_except GET HEAD { deny all; }' >> $F
echo '      proxy_pass http://docker_sock;' >> $F
echo '      proxy_set_header Host docker;' >> $F
echo '    }' >> $F
echo '  }' >> $F
echo '}' >> $F
echo "  $(wc -l < $F) linhas"

echo "[3/9] DEPLOY docker-socket-proxy"
docker service rm $D 2>/dev/null || true
sleep 2
docker service create \
  --name $D \
  --network proxy \
  --mount type=bind,source=$S,target=$S,readonly \
  --mount type=bind,source=$F,target=/etc/nginx/nginx.conf,readonly \
  --constraint node.role==manager \
  --replicas 1 \
  nginx:alpine > /dev/null
for i in $(seq 1 30); do
  REP=$(docker service ls -f name=$D --format "{{.Replicas}}")
  if [ "$REP" = "1/1" ]; then echo "  READY $REP"; break; fi
  sleep 2
done

echo "[4/9] EDIT traefik.yml"
OLD='unix:///var/run/docker.sock'
NEW='tcp://docker-socket-proxy:2375'
sed -i "s|$OLD|$NEW|" $TD/traefik.yml
grep endpoint $TD/traefik.yml

echo "[5/9] EDIT stack.yml"
# image upgrade
sed -i 's|traefik:v3.1|traefik:v3.5|' $TD/stack.yml
# remove docker.sock mount
sed -i '\|/var/run/docker.sock:/var/run/docker.sock|d' $TD/stack.yml
# fix labels vazio (causa "deploy.labels must be a mapping")
sed -i '/^[[:space:]]*labels:[[:space:]]*$/d' $TD/stack.yml
grep -E 'image:|docker.sock' $TD/stack.yml || true

echo "[6/9] DEPLOY TRAEFIK v3.5"
cd $TD
docker stack deploy -c stack.yml traefik
FMT='{{.Image}}/{{.Replicas}}'
for i in $(seq 1 45); do
  L=$(docker service ls -f name=$T --format "$FMT")
  if echo "$L" | grep -q "traefik:v3.5/1/1"; then
    echo "  OK $L"
    break
  fi
  sleep 2
done

echo "[7/9] VALIDATE"
sleep 3
FAIL=0
W='%{http_code}'
URL='https://localhost/'
# AJUSTAR lista de subdomínios pra cada cliente
for H in n8n portainer chat minio qdrant rabbitmq status; do
  HD="Host: ${H}.${DOMAIN_BASE}"
  CODE=$(curl -sk -o /dev/null -w "$W" -H "$HD" "$URL" -m 5)
  echo "  $H -> $CODE"
  case $CODE in
    200|301|302|307|308|401|403) ;;
    *) FAIL=$((FAIL+1));;
  esac
done
echo "Falhas: $FAIL"
if [ $FAIL -gt 2 ]; then
  echo "ROLLBACK"
  docker service rollback $T || true
  cp $TD/traefik.yml.bak-$TS $TD/traefik.yml
  cp $TD/stack.yml.bak-$TS $TD/stack.yml
  docker service rm $D 2>/dev/null || true
  exit 1
fi

echo "[8/9] APT HOLD"
apt-mark hold docker-ce docker-ce-cli containerd.io
apt-mark hold docker-buildx-plugin docker-compose-plugin
A=/etc/apt/apt.conf.d/51unattended-upgrades-docker
> $A
echo 'Unattended-Upgrade::Package-Blacklist {' >> $A
echo '  "docker-ce";' >> $A
echo '  "docker-ce-cli";' >> $A
echo '  "containerd.io";' >> $A
echo '  "docker-buildx-plugin";' >> $A
echo '  "docker-compose-plugin";' >> $A
echo '};' >> $A
apt-mark showhold

echo "[9/9] RESUMO"
SFMT="table {{.Name}}\t{{.Replicas}}\t{{.Image}}"
docker service ls --format "$SFMT" | grep -E "traefik|socket"
VFMT="Docker {{.Server.Version}} MinAPI {{.Server.MinAPIVersion}}"
docker version --format "$VFMT"
echo "DONE — Backups em $TD/*.bak-$TS"
