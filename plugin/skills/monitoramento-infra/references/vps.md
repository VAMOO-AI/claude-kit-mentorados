# VPS com Docker: o que derruba, como medir, como provar que voltou

Aprendido numa frota de VPS (Ubuntu 22.04/24.04, Docker Swarm de nó único, Traefik
v3, n8n, Chatwoot, Portainer, netdata), em incidente real e em manutenção
preventiva. Vale para Hostinger, Hetzner, DigitalOcean ou qualquer VPS com essa
stack. **Rode o diagnóstico antes de qualquer receita:** se a sua VPS não tem
Swarm, Traefik ou netdata, metade deste arquivo não se aplica, e aplicar às cegas
quebra o que estava funcionando.

Tudo aqui mexe em produção. Antes de cada comando que muda estado: backup do
arquivo, janela combinada com quem usa o sistema e o caminho de volta escrito.

## Diagnóstico (sempre primeiro)

```bash
echo "=== DOCKER ==="
docker version --format \
  "Server: {{.Server.Version}} | MinAPI: {{.Server.MinAPIVersion}}"
apt list --upgradable 2>/dev/null | grep -E "docker-ce|containerd"
echo "=== TRAEFIK ==="
docker service ls --format "{{.Name}}\t{{.Image}}" | grep -i traefik
echo "=== QUEM MONTA O docker.sock ==="
for c in $(docker ps -q); do
  docker inspect -f '{{.Name}} {{range .Mounts}}{{.Source}} {{end}}' "$c" \
    | grep docker.sock
done
echo "=== ATUALIZAÇÃO AUTOMÁTICA ==="
systemctl is-enabled unattended-upgrades
grep -E "Start-Date|docker" /var/log/apt/history.log | tail -10
echo "=== NETDATA ==="
docker ps --format '{{.Names}} {{.Image}}' | grep -i netdata
```

**Veredito:**

| O que o diagnóstico mostrou | O que fazer |
|---|---|
| Docker < 29 e `docker-ce` na lista de upgrade | preventivo: Traefik ≥ v3.5 **antes** do upgrade, e `apt-mark hold` |
| Docker ≥ 29 e Traefik v3.1–v3.4 | emergência: já caiu ou cai no próximo restart |
| Traefik ≥ v3.5 e `docker.sock` montado nele | só falta o hardening de segurança (socket proxy) |
| `dockerd`/`containerd` com CPU alta e netdata rodando | seção "CPU alta do daemon" antes de mexer em versão |

## As três bombas-relógio

### 1. Docker 29 + Traefik antigo = 404 em todas as rotas

O Docker 29 subiu a `MinAPIVersion` de 1.24 para 1.44. O cliente do Traefik v3.1
fala uma versão antiga, é recusado, o provider do Swarm para de descobrir os
serviços e **todas as rotas viram 404** — com os containers rodando normais.
Quem olha `docker service ls` vê tudo verde e não entende.

O gatilho costuma ser o `unattended-upgrades` (ligado por padrão em várias
imagens de VPS), que roda de madrugada e atualiza o Docker junto com o resto.
Ninguém mexeu, e o site caiu.

### 2. `docker.sock` montado direto no Traefik

Montar `/var/run/docker.sock` num container é dar root no host para ele. Uma
falha que permita escapar do Traefik — o único container exposto à internet —
vira controle da máquina inteira.

### 3. netdata a 1 segundo contra o daemon do Docker

O coletor `docker` do netdata não define `update_every` na config de fábrica e
herda o global de **1 segundo**. Onde cada varredura da API do Docker custa mais
de 1s, o coletor roda encostado e põe `dockerd` + `containerd` em **70–95% de um
core, permanente**. O log denuncia:

```
skipping data collection: previous run is still in progress
for 1.006s (interval 1s)   plugin=go.d collector=docker job=local
```

Não é carga: na frota, um host com 25 containers estava em 1,5% e outro com 14
em 95%. E **um reboot basta para o host tombar nesse estado** — um estava em 0,9%
antes do reboot e voltou em 95,5%.

## Receita de hardening (Traefik + socket proxy + hold)

1. Traefik v3.1 → **v3.5** (fala a API do Docker 29).
2. Um `docker-socket-proxy` (nginx) que só deixa passar `GET`/`HEAD` e reescreve
   `/v1.X/` — o Traefik nunca mais toca o socket.
3. Traefik apontado para `tcp://docker-socket-proxy:2375`.
4. Mount do `docker.sock` removido do Traefik.
5. `apt-mark hold` nos pacotes do Docker **e** blacklist no `unattended-upgrades`
   (cinto e suspensório: o hold sozinho já foi desfeito por upgrade manual).

O script pronto está em [../assets/fix-vps-hardening.sh](../assets/fix-vps-hardening.sh):
faz backup com timestamp, sobe o proxy, troca o Traefik, testa as rotas e **faz
rollback sozinho** se mais de duas falharem. Ajuste `DOMAIN_BASE` e a lista de
subdomínios antes de rodar.

### Colando script por terminal SSH (Termius e afins)

O bracketed-paste de alguns clientes SSH quebra script longo no meio:
- linha com mais de ~80 caracteres é cortada;
- heredoc falha porque a linha do `EOF` recebe indentação;
- `printf '%s\n' a b c ...` numa linha só falha pelo mesmo motivo.

Por isso o script do `assets/` segue regras de formato: toda linha < 75
caracteres, comando longo quebrado com `\`, arquivo multilinha escrito com
`echo '...' >> $F` repetido. Para levar ao servidor: `nano /tmp/fix.sh`, colar,
salvar, `bash /tmp/fix.sh`.

### Pegadinhas da aplicação

| Sintoma | Causa | Saída |
|---|---|---|
| `deploy.labels must be a mapping` | `labels:` vazio no `stack.yml` | apagar a linha (`sed -i '/^[[:space:]]*labels:[[:space:]]*$/d'`) |
| "command not found" no meio do script | heredoc com `EOF` indentado | `echo >> $F` repetido |
| `flag needs an argument: --mount` | `docker service create` numa linha só | quebrar em várias linhas com `\` |
| SSH dá timeout só para você | `ufw` bloqueando o seu IP | liberar o IP, ou executar pelo console da VPS |
| Certificado íntegro e browser com `ERR_SSL` | DNS suspenso no registrador | olhar o NS do domínio antes de mexer no Traefik |

### Rollback

```bash
TS=<timestamp-do-fix>
TD=/opt/docker/swarm/traefik      # onde o seu stack do Traefik mora
cp $TD/traefik.yml.bak-$TS $TD/traefik.yml
cp $TD/stack.yml.bak-$TS   $TD/stack.yml
cd $TD && docker stack deploy -c stack.yml traefik
docker service rm docker-socket-proxy
```

### Validação pós-fix

```bash
docker service ls | grep -E "traefik|docker-socket-proxy"
# Traefik SEM docker.sock (a saída não pode listar o socket)
docker service inspect <servico-do-traefik> --format \
  '{{range .Spec.TaskTemplate.ContainerSpec.Mounts}}{{.Source}} {{end}}'
apt-mark showhold | grep docker
cat /etc/apt/apt.conf.d/51unattended-upgrades-docker
docker version --format "{{.Server.Version}}"   # a mesma do diagnóstico
```

Quando quiser subir o Docker de propósito, com o Traefik já em v3.5: corrija o
intervalo do netdata **antes** (seção abaixo), depois `apt-mark unhold` nos cinco
pacotes e `apt upgrade`.

## CPU alta de `dockerd`/`containerd`: medir antes de culpar

Nessa caça a causa foi atribuída errado duas vezes (primeiro a steal time do
hypervisor, depois a uma regressão do Docker ≥ 29.4). Separe o que é medido do
que é inferência — é isso que impede a próxima pessoa de caçar a causa errada.

**Medido.** Docker ≥ 29.4 apareceu com 71–179% de CPU de daemon em vários hosts, e
o downgrade para 29.1.x baixou a maioria. Mas parar o netdata derrubou host de
~85% para ~2%, e um host **já em 29.1.x**, com a config de fábrica de 1s, mediu
**184,5%** com overrun no log — e 8,8% com o intervalo corrigido.

**Inferência (não provada).** O intervalo do coletor pode explicar tudo sozinho, e
a versão do Docker ser pista falsa: o coletor pergunta a cada 1s, e o que muda
entre versões é quanto **custa** responder. O downgrade não "consertou o Docker" —
deixou a varredura rápida de novo, e o intervalo de 1s cabe nela.

**Consequência prática:** corrija o intervalo do coletor antes de mexer em versão.
É reversível, não pede janela e não reinicia container de ninguém.

### Meça por jiffies, numa janela de 60s

```bash
jif(){ awk '{print $14+$15}' /proc/$1/stat; }   # utime + stime
pd=$(pgrep -x dockerd | head -1); pc=$(pgrep -x containerd | head -1)
a=$(( $(jif $pd) + $(jif $pc) )); sleep 60
b=$(( $(jif $pd) + $(jif $pc) ))
# CLK_TCK=100 (padrão do Linux; confira com getconf CLK_TCK)
awk -v d=$(( b - a )) 'BEGIN{printf "daemon=%.1f%%\n", d/60}'
```

Por que não `top` nem `ps`, e por que 60s:

- **`ps -eo pcpu` é média da vida do processo**, não instantâneo. Processo recém
  nascido aparece com 40–100% e não significa nada — foi assim que o `systemd`
  virou suspeito.
- **Cada login SSH cria um `user@0.service`.** Uma rajada de comandos SSH curtos
  enche o journal e imita churn do PID 1. É você mesmo provocando.
- **Steal (`st`) é real e oscila** (35% → 6% em minutos no mesmo host). Some a CPU
  do daemon antes de culpar o hypervisor.
- **Amostra curta mente.** O mesmo host, em minutos seguidos: 2,7%, 15,3%, 31,0%,
  46,2% em janelas de 12–15s, e 8,8% em 60s. Leitura baixa em janela curta produz
  "está corrigido" quando não está. Conclusão tirada de 10–15s é não medida.
- **Warm-up:** logo depois de `docker restart netdata` a CPU sobe (a descoberta de
  serviços refaz tudo). Espere ~2 min antes de medir.
- **Janela suja de log:** `docker logs netdata --since 5m` pode pegar a config
  anterior. Conte overrun só desde o restart.

### Inventário não acha a causa; strace + bisect acha

Na frota, todas estas hipóteses foram medidas e **falsificadas** (existiam iguais
nos hosts limpos): versão do Docker, versão do containerd, presença do netdata,
socket proxy, agente do Portainer, snapshotter `overlayfs`, tamanho do store de
imagens, estado do Swarm, número de containers.

```bash
# perfil de syscalls do containerd (6s): procure erro em 100% das chamadas
pc=$(pgrep -x containerd | head -1)
strace -c -f -p $pc & sleep 6; kill -INT %1; wait
# quais arquivos ele relê (4s)
strace -f -e trace=openat -p $pc 2>&1 & sleep 4; kill -INT %1; wait
```

Blobs de `/var/lib/containerd/io.containerd.content.v1.content/blobs/` relidos em
loop = alguém varrendo imagens sem parar. Se o socket proxy bloqueia imagens, não
é o Traefik; sobra quem monta o socket direto. Pare o suspeito mais barato, meça,
religue:

```bash
docker stop netdata; sleep 5   # meça aqui
docker start netdata
```

Resultado medido: 83,3% → 2,6% e 86,7% → 1,1%.

### Correção: intervalo do coletor, não desligar o netdata

| intervalo | CPU do daemon | overrun |
|---|---|---|
| 1s (fábrica) | 85–184% | constante |
| 10s | 5–13% | zero |
| 30s | 1–9% | zero |

O intervalo certo é o menor que mantém o overrun em zero com folga. O resíduo de
5–13% é uma varredura por intervalo: é o preço do monitoramento, não sobra de bug.

Grave pelo **host**, no volume de config do netdata:

```bash
d=$(docker volume inspect netdataconfig --format '{{.Mountpoint}}')
mkdir -p "$d/go.d"
echo 'update_every: 30' > "$d/go.d/docker.conf"
echo 'jobs:' >> "$d/go.d/docker.conf"
echo '  - name: local' >> "$d/go.d/docker.conf"
echo "    address: 'unix:///var/run/docker.sock'" >> "$d/go.d/docker.conf"
echo '    timeout: 5' >> "$d/go.d/docker.conf"
echo '    collect_container_size: no' >> "$d/go.d/docker.conf"
docker restart netdata
```

⚠️ **Nunca escreva isso com `docker exec` sem `-i`.** Sem stdin, o `cat >` recebe
EOF, grava **arquivo vazio** e isso **desliga o coletor**. A CPU cai pelo motivo
errado e o monitoramento morre calado. Prova que separa "corrigido" de
"desligado":

```bash
docker logs netdata --since 2m | grep 'collector=docker job=local'
# quer ver: config_source="user/file reader" e interval 30s
#           (stock/file reader = o seu arquivo não está sendo lido)
docker exec netdata curl -s localhost:19999/api/v1/charts | grep -c 'docker\.'
# > 0 = os gráficos do Docker continuam existindo
```

O volume sobrevive a reboot. Mas se o netdata foi criado com `docker run` avulso
(sem compose, sem nada que o provisione), recriar sem `-v netdataconfig:/etc/netdata`
perde a correção. Descubra quem cria o container.

## n8n: o banco de execuções que incha

Volume alto de execuções × `runData` salvo (100–200 KB cada) × retenção de 14
dias = GBs no Postgres do n8n, que pesam na VPS inteira. Medir pela API, sem SSH:
`GET /api/v1/executions?workflowId=<id>&limit=250` e veja quantas horas as 250
cobrem.

- `EXECUTIONS_DATA_PRUNE=true` (padrão nas versões recentes)
- `EXECUTIONS_DATA_MAX_AGE` — horas de retenção (padrão 336 → **72** costuma bastar)
- `EXECUTIONS_DATA_PRUNE_MAX_COUNT` — teto (padrão 10000 → **5000**)
- alavanca extra, que custa debug: `EXECUTIONS_DATA_SAVE_ON_SUCCESS=none`

**Em queue mode o pruning roda só no processo main** (o do editor). Basta mudar o
env dele: workers e webhooks seguem no ar, só a UI reinicia.

```bash
docker service update \
  --env-add EXECUTIONS_DATA_MAX_AGE=72 \
  --env-add EXECUTIONS_DATA_PRUNE_MAX_COUNT=5000 \
  <servico-do-editor>
```

Stack gerenciada pelo Portainer **reverte** esse `service update` no próximo
"Update the stack": fixe o env também no YAML da stack. O backlog some sozinho no
primeiro ciclo; apagar execução pela API é destrutivo e quase nunca necessário.

## Reboot em Swarm: rota em 200 não prova que voltou

Em Swarm, reiniciar o host reinicia os containers. Depois do boot, um service
pode aparecer **`1/1 Running` e estar fora da rede overlay**:

| O que aparece | O que era |
|---|---|
| Traefik 1/1, mas 80/443 não escutam no host | subiu sem publicar a porta |
| container com só a interface `lo` | sem rede nenhuma |
| Chatwoot em crash loop com `Name does not resolve` | **vítima**: o Redis dele estava fora da rede |
| rota responde **401** e parece saudável | é o basic auth do Traefik respondendo, **sem tocar o backend** |

`docker inspect` mostra `invalid IP` em container são e em quebrado — não serve.
O que separa é o namespace de rede:

```bash
for cid in $(docker ps -q); do
  read -r nome modo pid < <(docker inspect \
    -f '{{.Name}} {{.HostConfig.NetworkMode}} {{.State.Pid}}' "$cid")
  case "$modo" in none|host) continue;; esac
  [ -z "$pid" ] || [ "$pid" = 0 ] && continue
  ifaces=$(nsenter -t "$pid" -n ip -4 -o addr show 2>/dev/null \
    | awk '{print $2}' | sort -u | tr '\n' ',')
  [ "$ifaces" = "lo," ] && echo "SEM-REDE ${nome#/}"
done
```

Reatar: `docker service update --force --no-resolve-image <servico>`. **Trate a
dependência antes da vítima** — reiniciar o Chatwoot em loop não adianta enquanto
o Redis dele estiver sem rede.

### Sequência por host (pare na primeira regressão)

1. Baseline de rotas **fresco, deste host**, imediatamente antes.
2. `nohup sh -c "sleep 2; systemctl reboot" &` — o SSH volta limpo.
3. Espere o SSH (teto ~7 min) e depois `docker service ls` sem réplica incompleta.
4. Detector de netns acima + reatar o que subiu sem rede.
5. Mais ~50s: Chatwoot/Rails e n8n levam ~90s para responder. 502 nesse
   intervalo é normal.
6. Compare com o baseline: regressão é só o que **era 2xx/3xx e deixou de ser**
   (401/403/404 estáveis são basic auth ou serviço desativado).
7. Saúde: `/var/run/reboot-required`, `systemctl --failed`, swap, service incompleto.

Perdeu o baseline? O próprio Traefik devolve todas as rotas:

```bash
for s in $(docker service ls -q); do
  docker service inspect --format \
    '{{json .Spec.Labels}}{{json .Spec.TaskTemplate.ContainerSpec.Labels}}' $s
done | grep -oE 'Host\(`[^`]+`\)' | grep -oE '`[^`]+`' | tr -d '`' | sort -u
```

Meça com `curl --resolve <rota>:443:<ip-do-host>` para bater no host certo sem
depender de DNS. Na frota isso achou bem mais rotas que a lista "oficial".

## Firewall: porta do Docker passa por cima do ufw

O `ufw` liberando só 22/80/443 **não fecha** porta publicada por container: o
Docker escreve as próprias regras de iptables antes das do `ufw`, e o
`docker-proxy` segue escutando em `0.0.0.0` nas portas de serviço (5678 do n8n,
9443 do Portainer, 6333 do Qdrant, 15672 do RabbitMQ, 19999 do netdata…). Quem
fecha são regras na chain `DOCKER-USER`, e essas **não sobrevivem a reboot
sozinhas** — precisam de uma unidade systemd oneshot com `After=docker.service`.

```bash
systemctl is-enabled <sua-unidade-de-firewall>    # precisa dizer "enabled"
# DE FORA da VPS, depois de um boot — o único teste que vale:
for p in 22 80 443 3000 5678 5672 6333 8000 9443 15672 19999; do
  nc -z -G 4 <ip-da-vps> $p 2>/dev/null && echo "$p ABERTA"
done
```

(`-G` é o timeout do `nc` do macOS; no Linux use `-w 4`.) Procurando o script que
restaura as regras? `grep -r DOCKER-USER /etc` não acha se ele mora em
`/usr/local/sbin`, `/opt` ou `/srv` — procure lá antes de concluir que nada persiste.

## Backup: tamanho não prova nada

Um dump de 29 KB comprimido parece truncado e pode estar perfeito. Confira conteúdo:

```bash
gzip -t "$f" && echo "gzip ok"
zcat "$f" | grep -c '^CREATE TABLE'
zcat "$f" | grep -c '^COPY '
zcat "$f" | awk '/^COPY /{f=1;next} /^\\\.$/{f=0} f{n++} END{print n+0}'  # linhas de dado
```

E o teste que fecha: **restaurar** num banco descartável, de vez em quando.

- Script de backup que só dumpa container cujo nome casa "postgres" deixa de fora
  Qdrant, MinIO e qualquer outro banco. Qdrant tem snapshot por API
  (`POST /collections/<c>/snapshots`).
- Contando arquivos "de hoje" numa frota com fuso misto, use `date -u`. Com
  `date` local, um host em UTC-3 casa os dumps de ontem e você "descobre" uma
  execução que nunca houve.
- Confira onde o cron do dump mora de verdade: `/etc/cron.d/` **e** `crontab -l` do
  root. Auditoria que olha um lugar só conclui que o host não tem backup.

### Backup cruzado entre VPS: `rrsync -wo` não impede apagar

Padrão comum para uma VPS empurrar o backup para outra:

```
restrict,command="/usr/bin/rrsync -wo /opt/backup/cofre/<origem>" ssh-ed25519 ...
```

Isso bloqueia shell, leitura de volta e fuga do diretório. **Mas `--delete`
passa**: com um diretório de origem vazio, `rsync --delete` apaga o histórico no
destino com `rc=0`. Uma origem comprometida apaga o próprio backup, e o backup
cruzado vira espelho.

A trava é uma palavra, **`-no-del`**:

```
restrict,command="/usr/bin/rrsync -wo -no-del /opt/backup/cofre/<origem>" ssh-...
```

O destino passa a recusar com `option --delete has been disabled on this server`.
Testes para cada par origem → destino, antes de confiar:

```bash
E="ssh -i /root/.ssh/<chave> -o IdentitiesOnly=yes -o BatchMode=yes"
$E root@<destino> 'id'                                   # DEVE falhar
rsync -e "$E" -az root@<destino>:/ /tmp/x/               # DEVE falhar (leitura)
rsync -e "$E" -az /tmp/canario.txt root@<destino>:/      # DEVE funcionar
rsync -e "$E" -az /tmp/canario.txt root@<destino>:../x/  # DEVE falhar
mkdir -p /tmp/vazio
rsync -e "$E" -az --dry-run --delete /tmp/vazio/ root@<destino>:/  # DEVE falhar
```

O `--delete` vai com `--dry-run` de propósito: se a trava falhar, o teste real
apagaria backup.

**`rsync -a` propaga o modo do diretório de origem.** Origem em 755 achata o cofre
do destino para 755 a cada envio — dump de banco legível por qualquer usuário
local. `chmod 700` só no destino volta no próximo envio; aperte a **origem**, e
cada envio passa a reforçar o 700.

O `rrsync` atual não tem `-no-overwrite`: dump já depositado ainda pode ser
sobrescrito com o mesmo nome. A defesa é a rotação ser do destino e o nome do
arquivo levar data.

## Acesso SSH

- VPS endurecida aceita **só chave**. Senha root guardada em planilha não abre
  nada — e não deveria existir em planilha.
- No 1Password, o agente SSH **só serve item da categoria "SSH Key"**. Chave salva
  como documento deixa `ssh-add -l` vazio e parece que não há chave.
- `ssh-add -l` lê `SSH_AUTH_SOCK`; se o `~/.ssh/config` aponta `IdentityAgent`
  para outro socket, teste com esse socket antes de concluir que o agente está vazio.
- `known_hosts` com chave antiga dá alarme de MITM em host legítimo depois de
  reinstalar a VPS. Confirme o IP e o reverse DNS do provedor antes de apagar a linha.
- Comando que imprime chave privada no terminal (`op item create`, por exemplo)
  e caiu em log = chave vazada: gere outra, instale, remova a antiga do
  `authorized_keys` e confirme `Permission denied` com ela.
- Chave de emergência no cofre; o dia a dia usa uma chave de operação separada.
