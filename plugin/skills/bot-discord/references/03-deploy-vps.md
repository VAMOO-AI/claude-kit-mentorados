# 03 — Docker, VPS e operação

## Dockerfile

```dockerfile
FROM node:22-alpine
WORKDIR /app

COPY package.json package-lock.json ./
# npm install, não npm ci: deps nativas opcionais (@emnapi/*, sharp, etc.) resolvem
# diferente entre macOS e linux/amd64 e o lockfile quebra o `ci` no build.
RUN npm install --no-audit --no-fund

# Copie src/ INTEIRO. ARMADILHA Nº 3, com incidente real: lista seletiva de COPY
# ("só src/lib/discord", "só os arquivos usados") defasa em silêncio — um import novo
# pra fora da lista faz a imagem BUILDAR VERDE e o container morrer em loop com
# ERR_MODULE_NOT_FOUND, com o bot fora do ar. Copiar alguns MB a mais é grátis.
COPY src/ ./src/
COPY tsconfig.json ./

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD pgrep -f "tsx" > /dev/null || exit 1

CMD ["npx", "tsx", "src/bot/index.ts"]
```

`.dockerignore`:

```
node_modules
.git
.env
.env.*
*.log
```

## docker-compose.yml

```yaml
services:
  meu-bot:
    build: { context: ., dockerfile: Dockerfile }
    image: meu-bot:latest
    container_name: meu-bot
    restart: always
    env_file: .env
    environment:
      - TZ=America/Sao_Paulo
    logging:
      driver: json-file
      options: { max-size: "10m", max-file: "3" }   # sem isso o log enche o disco da VPS
```

`env_file: .env` é melhor que listar `environment:` item a item: variável nova entra em **um**
lugar só. Se você for obrigado a usar a lista explícita (é o caso do Swarm), lembre que **toda
env nova tem que entrar em dois lugares** — no `.env` e no compose. É fonte clássica de
"configurei e não pegou".

## Preparar a VPS (uma vez)

```bash
ssh <USUARIO>@<IP_DA_VPS>

curl -fsSL https://get.docker.com | sh
docker --version && docker compose version

# usuário não-root para rodar o bot (recomendado)
adduser --disabled-password --gecos "" botuser && usermod -aG docker botuser
```

Bot de Discord é **saída pura** — conecta no gateway por WSS. Não precisa abrir porta, nem
domínio, nem proxy reverso. Com firewall ativo, só a 22 (SSH) precisa de entrada. Só muda se o
bot também expuser webhook ou painel HTTP.

Isso vale para o bot. Se a mesma VPS roda **outros** containers com porta publicada, o ufw
fechado não os protege — ver "Firewall: porta publicada pelo Docker passa por cima do ufw", no
fim deste arquivo.

## Código na VPS — use git

```bash
ssh <USUARIO>@<IP_DA_VPS>
mkdir -p /opt/<BOT> && cd /opt/<BOT>
git clone <URL_DO_REPO> .       # deploy key ou PAT read-only — nunca a senha da conta
```

Deploy passa a ser uma linha:

```bash
ssh <USUARIO>@<IP_DA_VPS> 'cd /opt/<BOT> && git pull && docker compose up -d --build'
```

> **Plano B — VPS sem credencial de git.** Dá para empurrar o código por SSH:
> `tar czf - src package.json package-lock.json tsconfig.json | ssh <USUARIO>@<IP> "cd /opt/<BOT> && tar xzf -"`.
> Funciona, mas você perde o histórico e "o que está rodando lá" vira adivinhação — e o `tar` do
> macOS ainda leva arquivos `._*` de metadados junto (`find . -name "._*" -delete` depois).
> Só use se não houver alternativa; o default é git.

## O `.env` na VPS

```bash
ssh <USUARIO>@<IP_DA_VPS>
cd /opt/<BOT>
nano .env          # cole os valores reais
chmod 600 .env     # só o dono lê
```

O `.env` **nunca** vai pro git, nem em repo privado. O `.env.example` vai sempre, com as chaves
vazias. Guarde uma cópia dos valores num gerenciador de senhas (1Password, Bitwarden), não num
arquivo solto no Desktop.

## Subir

```bash
ssh <USUARIO>@<IP_DA_VPS> 'cd /opt/<BOT> && docker compose up -d --build'
ssh <USUARIO>@<IP_DA_VPS> 'cd /opt/<BOT> && docker compose logs -f --tail 50'
```

Depois disso, **a Fase 9 do SKILL.md é obrigatória** — build verde não prova que o bot subiu.

## Opcional — VPS que já roda Docker Swarm

Só faça assim se o usuário **já** usa Swarm (n8n, Traefik, Portainer na mesma máquina). Os
gotchas abaixo são reais e custaram tempo de bot fora do ar:

- **Swarm ignora `build:`.** É preciso buildar a imagem à mão e atualizar o serviço:
  ```bash
  docker build -t <BOT>:latest . \
    && docker service update --force --image <BOT>:latest <STACK>_<SERVICO>
  ```
- **`env_file` não vale em stack.** Carregue o env antes do deploy:
  ```bash
  set -a && source .env && set +a && docker stack deploy -c docker-compose.yml <STACK>
  ```
  e a lista `environment:` do compose passa a ser explícita (env nova = editar `.env` **e** o compose).
  Aplicar uma variável sem rebuildar: `docker service update --env-add VAR="$VAR" --force <STACK>_<SERVICO>`.
- **`service update` derruba a task antiga antes de a nova subir.** Imagem quebrada = bot fora
  do ar até o próximo build. É exatamente por isso que a verificação pós-deploy não é opcional.
- Logs no Swarm: `docker service logs -f <STACK>_<SERVICO>` e `docker service ps <STACK>_<SERVICO> --no-trunc`.

### Depois de reiniciar a VPS: `1/1 Running` não prova que o serviço tem rede

Em Swarm, reiniciar o host reinicia os containers, e um service pode voltar **`1/1 Running` e
fora da rede overlay**. O sintoma despista porque aparece em outro lugar: a app entra em crash
loop com `getaddrinfo: Name does not resolve` quando quem ficou sem rede foi o **Redis** dela.

`docker inspect` não ajuda — mostra `invalid IP` tanto em container são quanto em quebrado. O que
separa um do outro é olhar as interfaces dentro do netns do container (precisa de root):

```bash
for cid in $(docker ps -q); do
  set -- $(docker inspect -f '{{.HostConfig.NetworkMode}} {{.State.Pid}} {{.Name}}' "$cid")
  modo=$1; pid=$2; nome=${3#/}; svc=${nome%%.*}   # task do Swarm: <STACK>_<SERVICO>.1.<id>
  case "$modo" in none|host) continue ;; esac
  [ -n "$pid" ] && [ "$pid" != 0 ] || continue
  ifaces=$(sudo nsenter -t "$pid" -n ip -4 -o addr show | awk '{print $2}' | sort -u | tr '\n' ',')
  case "$ifaces" in
    '')  echo "NÃO MEDIDO $svc (o nsenter falhou — rodou sem root?)" ;;
    lo,) echo "SEM REDE   $svc" ;;
  esac
done
```

Saída vazia é o que você quer. `SEM REDE` = subiu só com `lo`. `NÃO MEDIDO` **não** é verde: sem
root o `nsenter` falha, a lista de interfaces vem vazia, e um detector que tratasse vazio como
"ok" diria que está tudo bem sem ter olhado nada.

Para reatar: `docker service update --force --no-resolve-image <STACK>_<SERVICO>`. **Trate a
dependência antes da vítima** — reiniciar a app em loop não resolve nada enquanto o Redis (ou o
banco) dela estiver fora da rede.

E não use a rota HTTP como prova de que voltou. Um **401** vem do basic auth do proxy reverso
(Traefik, Caddy, nginx) sem tocar no container de trás: um serviço quebrado passa por saudável
porque "a rota respondeu". Checagem de rota só vale com o detector acima ao lado.

## Operação do dia a dia

```bash
# logs ao vivo
ssh <USUARIO>@<IP_DA_VPS> 'cd /opt/<BOT> && docker compose logs -f'

# reiniciar sem mudar código
ssh <USUARIO>@<IP_DA_VPS> 'cd /opt/<BOT> && docker compose restart'

# deploy de código novo (e depois SEMPRE a verificação da Fase 9)
ssh <USUARIO>@<IP_DA_VPS> 'cd /opt/<BOT> && git pull && docker compose up -d --build'

# liberar um usuário na allowlist — sem deploy de código
ssh <USUARIO>@<IP_DA_VPS> 'cd /opt/<BOT> && nano .env && docker compose up -d'

# disco (imagem antiga acumula e enche a VPS)
ssh <USUARIO>@<IP_DA_VPS> 'docker system df && docker image prune -f'
```

**Backup:** o que precisa de backup é o **banco** e o **`.env`** — o código está no git. Se a VPS
morrer, com esses dois você reconstrói tudo em 15 minutos.

**Tamanho do backup não prova nada.** Um dump de 29 KB comprimido parece truncado e pode estar
perfeito — num caso real eram 90 tabelas e 4.099 linhas. Confira o conteúdo, não os bytes:

```bash
f=<ARQUIVO>.sql.gz
gzip -t "$f" && echo "gzip ok"
zcat "$f" | grep -c '^CREATE TABLE'                                       # tabelas
zcat "$f" | grep -c '^COPY '                                              # tabelas com dados
zcat "$f" | awk '/^COPY /{f=1;next} /^\\\.$/{f=0} f{n++} END{print n+0}'  # linhas de dados
```

Isso vale para dump em texto (`pg_dump` padrão, depois `gzip`). Se o dump é no formato custom
(`pg_dump -Fc`), a conferência é pelo índice: `pg_restore -l <ARQUIVO>.dump | grep -c 'TABLE DATA'`.

**Sem CI para a imagem do bot?** Então o `Dockerfile` só é exercitado no deploy manual, e ele
apodrece calado: um `COPY` que virou obsoleto continua passando no build e só falha no boot.
Ou você builda a imagem no CI a cada PR, ou trata a verificação pós-deploy como parte do deploy —
não como algo que se faz "quando dá".

## VPS com CPU alta sem motivo aparente

A VPS do bot costuma dividir a máquina com outras coisas (n8n, painel, monitoramento). Quando
tudo fica lento, o culpado muitas vezes é um vizinho — e o primeiro erro é medir errado.

### Meça por jiffies, não por `ps %CPU`

`ps -eo pcpu` é a média da **vida inteira** do processo, não o uso de agora. Um processo com
`ELAPSED=0` aparece com 40–100% e não significa nada — foi assim que o `systemd` já entrou como
suspeito numa investigação. Meça o que o processo gastou numa janela:

```bash
jif(){ awk '{print $14+$15}' /proc/$1/stat; }   # utime+stime, em ticks
pid=$(pgrep -x dockerd | head -1)
a=$(jif $pid); sleep 10; b=$(jif $pid)
awk -v d=$(( b - a )) -v hz=$(getconf CLK_TCK) 'BEGIN{printf "%.1f%% de um core\n", d*100/hz/10}'
```

(O `getconf CLK_TCK` quase sempre dá 100, e aí a conta vira `d/10`. Não assuma — confira.)

Outra pegadinha: cada login SSH cria um `user@0.service` (um gerenciador de sessão com ~20
units). Uma rajada de comandos SSH curtos enche o journal e parece que o PID 1 está agitado.
Não confunda com o que você mesmo está provocando ao investigar.

### O suspeito clássico: netdata perguntando ao Docker a cada 1 segundo

Se a VPS tem **netdata** em container, o coletor `docker` dele não define `update_every` na
config que vem de fábrica e herda o global de **1 segundo**. Onde cada varredura da API do Docker
custa mais de 1s, o coletor roda encostado, sem parar, e põe `dockerd` + `containerd` em 70–95% de
um core. Não depende de carga: host com poucos containers pode estar pior que host cheio. O log
do netdata denuncia:

```
skipping data collection: previous run is still in progress
for 1.006s (interval 1s)   plugin=go.d collector=docker job=local
```

Para confirmar antes de mexer: `docker stop netdata`, meça por jiffies, `docker start netdata`.

A correção é aumentar o intervalo do coletor, não desligar o monitoramento. Grave o arquivo
**pelo host**, dentro do volume de config do netdata (`netdataconfig` na instalação oficial em
Docker). A pasta do volume é do root, por isso `sudo tee` — `sudo cat > arquivo` não funciona,
porque quem abre o arquivo é o seu shell, sem sudo:

```bash
d=$(docker volume inspect netdataconfig --format '{{.Mountpoint}}')
sudo mkdir -p "$d/go.d"
sudo tee "$d/go.d/docker.conf" > /dev/null <<'CONF'
update_every: 30
jobs:
  - name: local
    address: 'unix:///var/run/docker.sock'
    timeout: 5
    collect_container_size: no
CONF
docker restart netdata
```

Com `update_every: 30`, medido em dois hosts: ~85% → ~2%, com os gráficos do Docker ainda vivos.

**Nunca grave isso com `docker exec` sem `-i`.** Sem `-i` o container não recebe stdin: o
`cat > arquivo` lá dentro recebe fim de arquivo na hora e grava um arquivo **vazio**. No netdata,
isso desligou o coletor em vez de mudar o intervalo — a CPU caiu, parecia resolvido, e o
monitoramento do Docker tinha morrido calado. Vale para qualquer "gravar config dentro de
container".

Por isso a verificação precisa separar "corrigido" de "desligado":

```bash
docker logs netdata --since 2m 2>&1 | grep 'collector=docker'
# quer ver: config_source="user/file reader" e interval 30s
#           (stock/file reader = o seu arquivo não está sendo lido)
docker exec netdata curl -s localhost:19999/api/v1/charts | grep -c 'docker\.'
# maior que 0 = os gráficos do Docker continuam existindo
```

O arquivo mora no volume, então sobrevive a reboot e a `docker restart`. Mas se alguém recriar o
container do netdata sem montar esse volume, a correção some — confira quem cria o container.

## Firewall: porta publicada pelo Docker passa por cima do ufw

Porta publicada por Docker (`ports:` no compose, `-p` no `docker run`) **não passa pelo ufw**: o
Docker escreve as próprias regras de iptables, e o serviço fica acessível de fora mesmo com o ufw
dizendo que só a 22 está aberta.

- **Para um serviço novo, em compose comum:** publique só no loopback quando ninguém de fora
  precisa acessar — `ports: ["127.0.0.1:5678:5678"]`. (Em Swarm isso não existe: ali a porta
  publicada vale para todas as interfaces.)
- **Quem fecha de fato** são regras na chain `DOCKER-USER`, e elas **não sobrevivem a reboot
  sozinhas**. Se você tem essas regras num script, registre uma unit que roda depois do Docker:

  ```ini
  # /etc/systemd/system/<fw-portas>.service
  [Unit]
  Description=Regras DOCKER-USER depois do Docker
  After=docker.service
  Requires=docker.service

  [Service]
  Type=oneshot
  ExecStart=<CAMINHO_DO_SEU_SCRIPT_DE_FIREWALL>
  RemainAfterExit=yes

  [Install]
  WantedBy=multi-user.target
  ```

  `sudo systemctl enable <fw-portas>` e confira que `systemctl is-enabled <fw-portas>` diz
  `enabled`. Procurando se já existe algo assim? `grep -r DOCKER-USER /etc` não acha script que
  mora em `/usr/local/sbin` — procure lá também.
- **O teste que vale é de fora, depois de um reboot.** `iptables -S` por dentro mostra a regra, não
  mostra se ela voltou depois do boot. Da sua máquina:

  ```bash
  for p in <PORTAS_QUE_DEVEM_ESTAR_FECHADAS>; do
    nc -z -w 4 <IP_DA_VPS> $p 2>/dev/null && echo "$p ABERTA"
  done
  ```

  Saída vazia = fechadas. Rode de novo depois do próximo reboot.
