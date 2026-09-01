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

**Sem CI para a imagem do bot?** Então o `Dockerfile` só é exercitado no deploy manual, e ele
apodrece calado: um `COPY` que virou obsoleto continua passando no build e só falha no boot.
Ou você builda a imagem no CI a cada PR, ou trata a verificação pós-deploy como parte do deploy —
não como algo que se faz "quando dá".
