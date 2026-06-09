---
name: vps-hardening-clientes
description: Use ao diagnosticar ou prevenir queda de VPS de cliente que roda Docker Swarm + Traefik (típico setup Hostinger/Hetzner/DigitalOcean com n8n, Chatwoot, Portainer, Minio, Qdrant). Trigger phrases - "vps caiu", "vps do cliente", "traefik 404", "rotas caíram", "hostinger reboot", "docker upgrade", "n8n caiu", "portainer caiu", "hardening vps", "vps preventivo". Cobre o bug Docker 27→29 que mata Traefik v3.1 com 404 cascade, hardening estilo Cliente A/Cliente B, e o passo-a-passo de aplicação via Termius.
---

# VPS Hardening (estilo Cliente A/Cliente B) — Receita anti Docker 29

Aprendido em produção: **Cliente A** (incidente real maio/2026) e **Cliente B** (preventivo maio/2026). Mesma stack Hostinger Ubuntu 24.04 + Docker Swarm + Traefik + n8n/Chatwoot/Portainer.

## Quando aplicar

Toda VPS de cliente que tenha **TODAS** as características abaixo:
- Ubuntu 22.04+ (com `unattended-upgrades` ativo por default da Hostinger)
- Docker Swarm em manager-único
- Traefik v3.x como ingress (versão < 3.5 = vulnerável)
- Docker-CE instalado via apt (repo oficial Docker)
- Acesso ao Docker daemon via `unix:///var/run/docker.sock` no Traefik

Se identificar essa stack, aplique o hardening **antes** de detonar — é questão de dias até `apt upgrade` rodar.

## As 2 bombas-relógio

### Bomba 1 — Docker 27→29 + Traefik v3.1
Docker 29.x bumpou `MinAPIVersion` de 1.24 → 1.44. Cliente Go do Traefik v3.1 fala v1.24, é rejeitado, **provider swarm para de descobrir services → 404 em todas as rotas**. Sintoma na Cliente A: site caiu, n8n inacessível, mas docker services rodando normais.

Catalisador: `unattended-upgrades` da Hostinger roda diário ~07:00 UTC. Se o upgrade do Docker entrar no batch, detona automaticamente.

### Bomba 2 — docker.sock direto no Traefik
Container Traefik com `/var/run/docker.sock:/var/run/docker.sock` é equivalente a dar root no host. Qualquer CVE que permita escape do Traefik → game over.

## Diagnóstico (rodar primeiro, sempre)

Antes de aplicar fix preventivo, confirme a stack via Termius:

```bash
echo "=== DOCKER ==="
docker version --format "Server: {{.Server.Version}} | MinAPI: {{.Server.MinAPIVersion}}"
apt list --upgradable 2>/dev/null | grep -E "docker-ce|containerd"
echo "=== TRAEFIK ==="
docker service ls --format "{{.Name}}\t{{.Image}}" | grep -i traefik
docker service inspect $(docker service ls --format '{{.Name}}' | grep traefik) \
  --format 'Mounts: {{range .Spec.TaskTemplate.ContainerSpec.Mounts}}{{.Source}} {{end}}
Network: {{range .Spec.TaskTemplate.Networks}}{{.Target}} {{end}}'
echo "=== TRAEFIK CONFIG ==="
find /opt /root -name "traefik.yml" 2>/dev/null
echo "=== STACK FILES ==="
find /opt /root -name "stack.yml" -o -name "docker-compose*.yml" 2>/dev/null
echo "=== UNATTENDED ==="
grep -E "Start-Date|docker" /var/log/apt/history.log | tail -10
```

**Veredito:**
- Docker `< 29` E `docker-ce upgradable` listado → **preventivo necessário**
- Docker `>= 29` E Traefik `v3.1`/`v3.2`/`v3.3`/`v3.4` → **emergência, já caiu ou vai cair**
- Traefik `v3.5+` E `docker.sock` ainda montado → **só falta hardening de segurança**

## Receita de hardening (5 camadas)

1. **Upgrade Traefik v3.1 → v3.5** (compatível com Docker 29)
2. **Cria `docker-socket-proxy`** (nginx) que reescreve `/v1.X/` e expõe socket via TCP
3. **Aponta Traefik** pro proxy via `tcp://docker-socket-proxy:2375` em vez do socket direto
4. **Remove** mount do `docker.sock` no Traefik (hardening segurança)
5. **`apt-mark hold`** + **blacklist em `/etc/apt/apt.conf.d/51unattended-upgrades-docker`** (cinto + suspensório)

## Aplicação via Termius (lições de produção)

⚠️ **Termius bracketed-paste quebra linhas longas durante paste.** Empíricamente:
- Linhas `>80` chars são cortadas no meio
- Heredocs com terminator (`<<'EOF'`) falham porque a linha do `EOF` recebe indent de 2 espaços
- `printf '%s\n' arg1 arg2 ...` em linha única falha pelo mesmo motivo

**Regras de ouro pra script colável:**
- Toda linha do `.sh` **< 75 chars** (margem pro wrap do Termius)
- Comandos compostos: usar `\` em line continuation, NUNCA tudo em uma linha
- Arquivos multi-linha: usar **`echo 'linha' >> $F`** repetido (não printf, não heredoc)
- Editar o script via **`nano /tmp/fix.sh`** (mais robusto que `cat >` ou `wget`)

## Script de hardening — template

Disponível em `assets/fix-vps-hardening.sh` (próximo a este SKILL.md). Estrutura:

```
[1/9] BACKUP (3 arquivos .bak-$TS)
[2/9] NGINX CONFIG (18 linhas echo append)
[3/9] DEPLOY docker-socket-proxy (service create + wait READY 1/1)
[4/9] EDIT traefik.yml (sed endpoint)
[5/9] EDIT stack.yml (sed image v3.5, remove docker.sock, FIX labels vazio)
[6/9] DEPLOY TRAEFIK v3.5 (stack deploy + wait 1/1)
[7/9] VALIDATE (curl 7+ rotas, FAIL counter, rollback automático se >2 falhas)
[8/9] APT HOLD + blacklist unattended
[9/9] RESUMO
```

## Pegadinhas conhecidas

| Pegadinha | Sintoma | Fix |
|---|---|---|
| `labels:` vazio em stack.yml | `deploy.labels must be a mapping` | `sed -i '/^[[:space:]]*labels:[[:space:]]*$/d'` |
| Heredoc com EOF indentado | "command not found" no meio | Substituir por múltiplos `echo >> $F` |
| Linha `docker service create` em 1 linha | `flag needs an argument: --mount` | Quebrar em 8 linhas com `\` |
| ufw bloqueia IP do dev | SSH timeout só pro dev | Liberar IP CGNAT do dev, ou guiar via Termius |
| Cert acme.json íntegro mas browser ERR_SSL | DNS suspenso, IP fantasma respondendo | Olhar NS → se `dns-suspended.com`, é problema de registrar (verificação WHOIS / pagamento) |

## Rollback

Backups em `/opt/docker/swarm/traefik/*.bak-$TS`. Comando único:

```bash
TS=<timestamp-do-fix>
TD=/opt/docker/swarm/traefik
cp $TD/traefik.yml.bak-$TS $TD/traefik.yml
cp $TD/stack.yml.bak-$TS   $TD/stack.yml
cd $TD && docker stack deploy -c stack.yml traefik
docker service rm docker-socket-proxy
```

## Validação pós-fix (checklist)

```bash
# 1. Services rodando v3.5 + nginx-proxy
docker service ls | grep -E "traefik|docker-socket-proxy"
# 2. Traefik SEM docker.sock montado
docker service inspect traefik_traefik --format '{{range .Spec.TaskTemplate.ContainerSpec.Mounts}}{{.Source}}
{{end}}'
# 3. Todas as rotas 200/302
for H in n8n portainer chat minio qdrant rabbitmq status; do
  curl -sk -o /dev/null -w "$H -> %{http_code}\n" \
    -H "Host: $H.SEUDOMINIO.com" https://localhost/
done
# 4. apt hold + blacklist
apt-mark showhold | grep docker
cat /etc/apt/apt.conf.d/51unattended-upgrades-docker
# 5. Docker continua na versão segura
docker version --format "{{.Server.Version}}"  # esperado: 27.x
```

## Quando atualizar Docker pra 29 manualmente no futuro

Quando quiser realmente subir o Docker (após confirmar Traefik v3.5 compatível):

```bash
apt-mark unhold docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
apt update && apt upgrade -y
# Traefik v3.5 fala MinAPI 1.44 — vai funcionar.
# nginx-proxy é safety-net redundante mas inofensivo.
```

## Histórico de aplicações

- **Cliente A** (`clientea.exemplo.com` ou similar) — 2026-05-12 — **emergencial** (já tinha caído)
- **Cliente B** (`clienteb.exemplo.com`, srvXXXXXX Hostinger) — 2026-05-14 — **preventivo** (Docker ainda 27.5.1)

## Próximas VPS a auditar

Toda VPS com mesma stack do Cliente A/Cliente B. Quando aparecer cliente novo com:
- Hostinger + Docker Swarm + Traefik v3.x + n8n/Chatwoot
- Rodar diagnóstico do início deste documento
- Aplicar receita se Docker ainda em 27.x

## Nota

Os casos "Cliente A" e "Cliente B" são exemplos reais de produção (anonimizados): um foi aplicação emergencial (VPS já caída por Docker 29) e o outro preventivo (Docker ainda em 27.x). A receita é a mesma nos dois cenários — muda só a urgência.
