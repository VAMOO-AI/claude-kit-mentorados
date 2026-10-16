# O que sondar em cada coisa (e o que engana)

Cada tipo de alvo tem um jeito próprio de parecer saudável estando quebrado. O
que segue é o que já enganou uma sonda em produção.

## Site / API (HTTP)

- Defina os status aceitos por alvo. Serviço atrás de basic auth responde 401 e
  está vivo; site que redireciona responde 301/302.
- Mas 401 do Traefik prova que **o roteamento** está de pé, não que o backend
  responde. Para backend, sonde uma rota que toca o banco (`/healthz` que faz
  `select 1`), ou o netns do container (ver [vps.md](vps.md)).
- Timeout curto (10s), segunda tentativa só sem resposta, guarda de checker cego
  e limiar 2 — tudo isso está no [`assets/sonda-http.sh`](../assets/sonda-http.sh).
- Projeto Supabase de outra org, sem token: um alvo HTTP em `/rest/v1/` com
  status esperado `401` cobre "projeto fora do ar". Não cobre senha errada.

## n8n

**Execução que falhou** é o sinal óbvio: `GET /api/v1/executions?status=error`.
Os sinais que a sonda óbvia perde:

- **Fluxo que parou de rodar é invisível.** "Quais execuções falharam" não vê
  fluxo parado, e o silêncio ainda conta como recuperação. Detecte **mudos**:
  fluxo ativo com gatilho de agenda e sem execução há mais que N× o intervalo dele.
  A página de execuções precisa cobrir a janela inteira, e lane muda entra na
  conta de "com erro agora", senão flapa.
- **`EXECUTIONS_DATA_SAVE_ON_SUCCESS=none` torna o silêncio ambíguo.** Execução
  bem-sucedida não é salva, então "nenhuma execução" pode ser "tudo certo". Num
  caso real, 10 fluxos viraram "mudos" no mesmo minuto — o minuto do redeploy.
  Julgue fluxo a fluxo pelo `settings.saveDataSuccessExecution`; prova de vida vem
  do efeito colateral (a linha gravada, a mensagem enviada) ou de uma sonda
  descartável com `saveDataSuccessExecution: 'all'`.
- **Pool de conexão default é 2.** 299 execuções com `timeout exceeded when trying
  to connect` e `runData: {}`: uma conexão presa travava metade do pool.
  `DB_POSTGRESDB_POOL_SIZE=10`. O alerta mostra o fluxo falhando; o quebrado é o
  worker — leia o log do container. Reiniciar não reprocessa o que se perdeu.
- **Credencial apontando para o IP público da própria VPS** dá timeout de ~42s
  por tentativa (a 5432 não está publicada). Use o nome do serviço na rede
  overlay (`postgres:5432`). A mensagem de erro sugere "Retry on Fail" — conserto
  errado.
- **Duas credenciais para o mesmo banco são uma só.** Resetar a senha para
  consertar uma derrubou a outra, que rodava a cada minuto, e a operação parou 8h.
  Copie a senha que funciona; não resete. Depois de muitas falhas de auth, o
  pooler entra em circuit breaker e o erro persiste por minutos depois do
  conserto — a **mudança** da mensagem de erro é a confirmação de que pegou.
- **O último erro não é a causa.** Num fluxo com `Wait`, o erro final apareceu
  depois de 371 voltas de um loop de debounce. Conte execuções por node primeiro.
- **Tempestade:** n8n fora derruba todos os fluxos de uma vez. Agrupe (ver
  [arquitetura-monitor.md](arquitetura-monitor.md#6-dedup-e-agrupamento-uma-causa-uma-mensagem)).
- **Sondar sem tocar produção:** workflow descartável com Schedule de 1 min
  (schedule ativado pela API dispara; webhook não), leia
  `/executions?includeData=true`, depois desative e apague.
- **Monitore o banco certo.** Uma sonda mostrava 16 lanes `up` enquanto o banco
  que sustentava a operação era outro, fora do inventário. Varra os workflows por
  `https?://([a-z0-9]+)\.supabase\.co` para descobrir o que cada instância usa.

## VPS (Portainer / Docker)

- O Portainer aceita `X-API-Key` (token `ptr_...`); login de usuário da UI não
  serve para sonda. `GET /api/endpoints/<id>/docker/_ping` diz se o daemon responde.
- **Liste os containers essenciais de cada VPS.** Alvo sem essa lista não vê
  worker do n8n caído — o Portainer está de pé e o `_ping` responde.
- Postgres sem porta publicada se consulta por `exec` via API do Portainer
  (`/endpoints/<id>/docker/containers/<id>/exec` e depois `/exec/<id>/start`).
- Atrás da overlay, todo cliente aparece com o mesmo `client_addr` no
  `pg_stat_activity` (SNAT). Quem separa é `application_name` e `query`.
- O que derruba a VPS em si (Docker 29, netdata, reboot, firewall) está em
  [vps.md](vps.md). Netdata é ótimo para **ver**; para **avisar**, use uma sonda
  de fora — a VPS que caiu não manda alerta.

## WhatsApp (instância UAZAPI / Evolution / similar)

- **A prova de saúde é mensagem chegando**, não um 200 no envio. Instância pode
  aceitar envio e não receber nada.
- 88–89% das quedas de instância duram um ciclo (o aparelho reconectando sozinho).
  Limiar 2 ou carência de ~6 min.
- Fixe a **causa original** da queda (o motivo de desconexão que o provedor
  informa) na abertura do incidente; tentativa de reconexão sobrescreve.
- Canal oficial (WABA / BSP) "Conectado" no painel e morto: HTTP 200 com o erro
  no corpo. A sonda lê o corpo; rate limit e instabilidade viram `degraded`.
- **O aviso não sai pela instância que caiu.** Nem pelo mesmo servidor.
- **Código de pareamento nunca vai no alerta.**
- Descubra de onde vem a mensagem antes de mexer: mudar o limiar de um monitor
  não cala o alerta que vem de **outro** (um watcher antigo no n8n, por exemplo).
- Escada de reconexão, motivos de queda e o watcher fora de banda:
  `/kit-vamoo:n8n-workflow-agent` (referência de UAZAPI).

## Vercel (deploy)

- Estado de deploy que a sonda não conhece vira `degraded` com o nome do estado.
  `BLOCKED` já saiu `up`.
- Limiar 1: deploy barrado é evento discreto.

## Job agendado (cron, rotina, fluxo diário)

- **Monitore o silêncio, não o status.** "Está ativo" mente; o alerta certo é
  "nenhuma execução bem-sucedida nas últimas N horas".
- O jeito mais simples: **heartbeat** (dead man's switch). O job pinga uma URL
  ao terminar; o serviço de heartbeat (healthchecks.io, Better Stack, Cronitor…)
  avisa quando o ping **não** chega. É o único jeito de saber que o próprio
  monitor parou — por isso a `sonda-http.sh` tem `HEARTBEAT_URL`.
