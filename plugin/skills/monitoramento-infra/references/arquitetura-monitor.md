# Arquitetura de um monitor que as pessoas continuam lendo

Este é o desenho de um monitor que roda em produção vigiando sites, n8n,
Supabase, VPS (Portainer), Vercel e instâncias de WhatsApp de vários clientes.
Os números que aparecem aqui vieram de lá. Cada regra existe porque a versão
anterior dela gerou alarme falso, calou uma queda real ou derrubou o próprio
banco que o monitor usava.

Monitor ruim não falha calado: ele **treina a pessoa a ignorar o canal**. No
pior mês foram 890 mensagens num grupo de WhatsApp, 94 de 97 incidentes de um
tipo abriram com uma falha só, e a frase do time foi "já nem dou atenção". A
partir daí, uma queda real é mais uma notificação no meio do barulho. O
objetivo de tudo abaixo é que cada alerta valha a leitura.

## As peças

```
pg_cron ──► sonda (edge function) ──► INSERT checks ──► trigger avalia
                                                          │
                                         incidente abre/fecha, conta falhas
                                                          │
                                       enfileira entrega (fila de deliveries)
                                                          │
pg_cron ──► dispatch ──► agrupa, deduplica, monta texto ──► ntfy / WhatsApp / e-mail
pg_cron ──► selfcheck (1x/dia) ──► "o monitor está cego?" ──► ntfy direto
```

| Tabela | Papel |
|---|---|
| `targets` | o que se vigia: tipo (`http`, `n8n`, `supabase`...), config, `failure_threshold`, `last_status` |
| `checks` | uma amostra por sonda: `status` (`up`/`down`/`degraded`), `error_message`, `lane`, `meta` |
| `incidents` | um aberto por (alvo, lane), `failure_count`, `notified`, `closed_at` |
| `alert_rules` | quem recebe o quê: escopo, status que disparam, `notify_on` (`open`/`recovery`/`both`), prioridade, janela de dedup |
| `alert_destinations` | canal (`ntfy`, `whatsapp_group`, `email`) e endereço — **tópico ntfy mora aqui, não no código** |
| `alert_deliveries` | a fila: `queued` → `sent`/`failed`/`skipped`, tentativas |

**Lane** é a sub-entidade dentro de um alvo: o fluxo dentro do n8n, a instância
dentro do provedor de WhatsApp, o serviço dentro do Supabase. O índice que
garante "um incidente aberto por lane":

```sql
create unique index incidents_um_aberto_por_lane
  on incidents (target_id, coalesce(lane, ''))
  where closed_at is null;
```

Se a função que avalia o check só preserva a lane para uma lista fixa de tipos,
**tipo novo fora da lista junta todas as lanes num incidente só** — o primeiro
fluxo quebrado abre, o segundo some dentro dele. Mantenha essa lista junto com
o código da sonda nova.

Cada sonda é função pura (`lib.ts`, testável com payload real gravado de
produção) + I/O fino (`index.ts`). O env é lido no entry, não no lib, para o
teste importar sem segredo.

## 1. Antiflap: um ciclo não prova queda

Medido em 30 dias: a maioria dos incidentes fechava em menos de 10 minutos e um
dia teve pico de 48 mensagens. O incidente abria na primeira falha.

- **Limiar por tipo, não global.** Sonda de rede e de API externa (HTTP,
  Portainer, Supabase, provedor de WhatsApp) é amostra: exige **2** seguidas.
  Sonda de evento discreto (execução que falhou, deploy barrado) usa **1**,
  porque o segundo evento pode nunca vir.
- **Default por tipo num trigger `BEFORE INSERT/UPDATE`**, mais um `UPDATE` do
  que já existe. Migration que só ajusta os alvos de hoje deixa todo alvo novo no
  default antigo da coluna — num caso real, 26 de 55 alvos continuaram alertando
  no primeiro timeout.
- **Enfileire o aviso com `failure_count = threshold`, igualdade.** Sai uma vez
  por queda. Incidente aberto não re-alerta; quem insiste é o lembrete.
- **Separe o canal pela severidade.** O canal que acorda (WhatsApp, prioridade
  máxima no ntfy) recebe `down`. `degraded` vai para o canal de detalhe.

Latência de 10–20 min para confirmar foi aceita de propósito, em troca de o
canal continuar sendo lido. Se doer, a saída é **reconsultar a lane suspeita
~30s depois no mesmo ciclo**, não baixar o limiar.

Buraco conhecido do limiar por falhas seguidas: lane que alterna down/up fica
muda para sempre. O remédio é contar **aberturas por lane numa janela**, não
baixar o limiar.

## 2. Cegueira não é queda

Seis projetos de quatro organizações "caíram" no mesmo minuto. Era a API de
gestão do provedor respondendo 5xx — os projetos estavam no ar.

| A API que mede respondeu | O que gravar |
|---|---|
| 5xx, 429, 408, timeout (1º ciclo) | **nada** |
| idem, a partir do 2º ciclo | `degraded` com `<api>_indisponivel` e há quantos minutos o monitor está cego |
| 401, 403, 404 | `down` na hora: credencial ou alvo quebrado é problema seu e tem que gritar |
| status que a sonda não conhece | `degraded` nomeando o status. **Nunca `up` silencioso** (deploy `BLOCKED` saiu `up` por isso) |
| métrica ausente | `NaN` / "sem métrica". Nunca `up`, nunca zero |

**Guarda do checker.** Uma invocação da sonda HTTP perdeu a saída de rede: 19
sites "caíram" em sequência, todos com latência de exatos 10.001 ms, enquanto
outra invocação gravava `up` para os mesmos sites. Regra que resolveu:

- pool de ~6 requisições simultâneas, segunda tentativa só quando não veio
  resposta nenhuma;
- com 5+ alvos e 60%+ sem resposta, quem caiu foi o checker: o ciclo não grava;
- **teto de 10 min para essa supressão**, senão uma queda real de tudo cala o
  monitor;
- cortar o ciclo depois de ~8 falhas sem resposta.

O [`assets/sonda-http.sh`](../assets/sonda-http.sh) implementa a guarda com o teto.

## 3. Antes de ligar um alerta, olhe o payload cru

- `realtime.db_connected: false` aparecia em 6 de 7 projetos. Era ausência de
  assinante, não banco fora.
- Backup `PENDING` é backup rodando.
- Serviço atrás de basic auth (Traefik dashboard, RabbitMQ, Qdrant) responde
  401: ficaram dias em `down` falso, ~1.400 falhas cada — e, com o incidente
  aberto, **uma queda real não alertaria**. `expected_status: [200,301,302,401,403]`
  para esses. (O outro lado: 401 prova que o Traefik roteia, **não** que o
  backend está vivo — ver [vps.md](vps.md).)
- Canal oficial de WhatsApp "Conectado" no painel e morto: a API responde HTTP
  200 com o erro no corpo. Sonda HTTP não serve; precisa ler o corpo.

Rode um ciclo real, olhe o que deu `down` e só então ligue o alerta.

## 4. Recovery honesto

Um fluxo diário recebeu "✅ RECUPERADO" com a senha do banco ainda inválida. A
sonda fechava o incidente por silêncio: 60 min sem erro novo. Mas o fluxo só
roda uma vez por dia.

- **Fechar é incondicional; notificar a volta, não.** Todo `up` fecha o
  incidente (senão a próxima falha nunca alerta, porque o índice acha o aberto).
  O "voltou" só sai com **evidência**: a sonda mediu o estado ou viu uma execução
  bem-sucedida. Grave `meta.recuperado_por` e `recovery_confirmado`.
- **Sonda orientada a evento precisa de critério de silêncio** para fechar
  (`recovery_after_minutes`), senão o incidente fica aberto para sempre e cala a
  próxima falha. Sonda que mede estado emite o estado completo a cada ciclo,
  inclusive os `up`.
- **Carência antes de fechar por evidência.** Fluxo que erra a cada 6–9 min e
  acerta no meio fechou e reabriu 20 vezes num dia. Feche só depois de ~15 min
  sem erro novo.
- **Pares sempre pares.** Todo canal que recebeu a queda recebe a volta
  (um grupo teve 20 aberturas num dia e nenhuma baixa, porque a regra era
  `notify_on='open'`). E o contrário: **só avisa a volta quem recebeu a queda,
  naquele destino**. Entrega enfileirada não é mensagem enviada — 14 "RECUPERADO"
  órfãos em 30 dias, porque a abertura tinha morrido no dedup. Case por destino,
  não por regra (o mesmo destino costuma ter uma regra de abertura e outra de volta).
- **Fixe a causa original na abertura.** Uma tentativa de reconexão que expira
  troca "401" por "QR Code timeout" no último erro, e quem lê o lembrete corrige
  a coisa errada.

## 5. Lembrete: uma mensagem não segura uma falha de dias

437 falhas em três dias, **uma** mensagem laranja, e três dias de leads fora da
roleta comercial.

- Lane crítica de receita: lembrete a cada **2h**, sem silêncio de madrugada
  (decisão consciente).
- Instância de WhatsApp fora: a cada **24h** (é número parado esperando
  reconexão). Só `down` conta; `degraded` é o provedor religando sozinho.
- Blip de instância de WhatsApp: 88–89% das quedas duravam um ciclo de 5 min
  (o próprio aparelho reconectando). Limiar 2, ou carência de ~6 min desde o
  último `connected`. Lembrete e volta só saem se a queda foi anunciada.

## 6. Dedup e agrupamento: uma causa, uma mensagem

- **Escopo do dedup = a entidade que abre incidente**: `(regra, evento, alvo,
  lane)`, mais a **assinatura do erro** (nome do node que falhou, ou o texto com
  números trocados por `#`). Por regra+tipo, engoliu 393 de 782 entregas em 30
  dias. Por `incident_id`, não sobrevive a flap (339 envios contra 6 supressões).
  A assinatura deixa passar defeito novo na mesma lane.
- **Tempestade de lanes.** Um n8n caiu 48 min e gerou 31 incidentes, 202
  entregas e 136 envios. Com 5+ lanes no mesmo ciclo, a sonda emite um check de
  host; o dispatch agrupa a partir de 3 numa mensagem que lista as lanes (até 8 e
  "…e mais N"). Incidente **sem** lane nunca agrupa: três VPS caindo são três
  quedas. Emita o `up` do host depois dessa decisão, senão troca fan-out por flap.
- **Linha de host carrega só o estado do host.** Com o rollup das lanes nela, cada
  queda alertava duas vezes por canal. O status agregado vai para
  `targets.last_status` num `UPDATE` explícito depois do lote — trigger
  `FOR EACH ROW` deixaria lá o status da última linha.
- **Um erro isolado não é estado.** Uma API de terceiro piscou 1 min: 8 fluxos
  abriram lane, 48 mensagens. Lane de execução só alerta se não houve sucesso
  depois do erro, ou se houve 2+ erros em 15 min mesmo com sucesso no meio. **Se
  a consulta de confirmação falhar, alerte**: falha do monitor não pode calar.
- No PostgREST, filtro em recurso embutido sem `!inner` filtra só o objeto
  aninhado, não as linhas. Um dedup "funcionando" que não deduplicava nada.

Mantenha a linha de cada entrega absorvida (`skipped`) na fila: histórico, dedup
e retry dependem dela.

## 7. Quem vigia o vigia

Um DELETE pela UI apagou o único alvo de um tipo. A sonda passou três dias
respondendo `{"targets": 0}` — sucesso — e uma instância de WhatsApp caiu sem
ninguém saber. **Lista vazia é o sucesso mais silencioso que existe.**

- **Selfcheck diário** que procura "tipo com regra de alerta ativa e zero alvo
  ativo" e fala **direto** com o ntfy, fora da fila (a fila exige incidente, que
  exige alvo, que é justamente o que falta). Repete todo dia enquanto o buraco
  existir: é raro, acionável e não some sozinho.
- **Soft-delete ou pausa**, não DELETE. `ON DELETE CASCADE` leva checks,
  incidentes e entregas junto — a prova do que existia some.
- **Arquivar tem que fechar.** Um `archive()` que só setava `archived_at` deixou
  38 lanes travadas para sempre: o índice parcial olha `closed_at`.
- **Fechar passivo antigo direto na tabela**, sem passar por check — senão sai
  "RECUPERADO" de coisa de meses atrás.
- **Instância morta cega o host.** Lane `down` eterna fixa o `last_status` em
  `down` e a tela para de sinalizar o resto. Tenha uma lista de ignorados.
- O que o selfcheck **não** cobre, e precisa de heartbeat externo: o próprio
  banco do monitor fora, o pg_cron falhando, o pg_net recebendo 401. Ver
  [supabase-cron.md](supabase-cron.md) e o `HEARTBEAT_URL` da sonda.

## 8. O monitor não pode derrubar o que vigia

O banco caiu duas vezes por causa do próprio monitor:

- **~110 mil amostras por dia, 0,3% com informação nova**, e cada INSERT
  disparando trigger e realtime. Regra: grave amostra só quando o estado muda,
  quando há erro ou 1x por hora (trigger `BEFORE INSERT` que descarta o resto).
  Sonda a cada 10 min, retenção de 7 dias nos checks, índice por `ts` (consulta
  de mais de 60s caiu para 38 ms). Desempate por `id`: linhas do mesmo INSERT em
  lote nascem com o mesmo `ts`.
- O `interval_seconds` do alvo acompanha a agenda da cron, senão a tela acusa
  "coleta atrasada" de um alvo saudável.
- O lado pg_net (tabela de respostas inchada sem autovacuum) está em
  [supabase-cron.md](supabase-cron.md).

## 9. Ações automáticas: mínimas e opt-in

Reset automático de uma instância é opt-in, **uma vez por incidente**, só para
causa "sem motivo" ou "outro". Nunca em logout, ban, pareamento expirado ou
sessão duplicada — ali o reset piora. Reconexão por código só no clique de uma
pessoa. E **código de pareamento nunca vai no alerta**: ele passaria por grupo,
ntfy e e-mail.

## Checklist antes de dizer "o monitor está pronto"

- [ ] Cada tipo tem limiar próprio, aplicado por trigger a alvo novo.
- [ ] 5xx/timeout da API medidora não vira `down`; 401/403 vira.
- [ ] Status desconhecido vira `degraded`, nunca `up`.
- [ ] Rodei um ciclo real e li o payload cru de tudo que deu `down`.
- [ ] Recovery só com evidência; fechar continua incondicional.
- [ ] Todo canal que recebe a queda recebe a volta, e só quem recebeu a queda.
- [ ] Lembrete para o que é crítico.
- [ ] Dedup por lane + assinatura do erro; tempestade vira uma mensagem.
- [ ] Selfcheck de "zero alvo" fora da fila, e heartbeat externo para o resto.
- [ ] O alerta sai por canal que não depende do que caiu.
- [ ] Amostra só quando muda, retenção e índice por tempo.
- [ ] Provoquei uma queda de verdade (alvo apontado para porta fechada) e a
      mensagem chegou no celular — e a volta também.
