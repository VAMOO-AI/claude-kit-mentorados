# QA via Webhook Injection, Common Mistakes & Fixes, Testing Patterns

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

## QA de Agente IA via Injeção de Webhook (testar bugs do agente automaticamente)

Para verificar se o agente reproduz um bug reportado (alucina catálogo, confirma horário indevidamente, repete saudação) **sem depender de alguém digitar no WhatsApp** e **sem enviar mensagem a ninguém real**:

1. **Injete o payload no webhook** com o MESMO formato que o provider manda (extraia um payload real de uma execução: `runData["Webhook"][0].data.main[0][0].json.body` → template; troque `message.text`/`content`, `message.chatid`, `chat.phone`, `messageid`, `pushName`).
2. **Use números INVÁLIDOS como remetente** (DDD `00`, ex.: `5500000000001`): o agente processa e tenta responder, mas o `/send` falha (número inexistente) → **não atinge ninguém**. O Guard/agente já rodou; é só inspecionar.
3. **Inspecione** `GET /executions?includeData=true`: extraia as `flags` do node Guard e o array de `messages` da resposta. A execução real (com debounce) dura segundos — filtre por DURAÇÃO (a que passou pelo agente) ou pelo node Guard ter executado, não por `finished` (pode estar `error` por causa do send que falhou).
4. **Cuidado com race + memoryBufferWindow:** para testar continuidade/saudação, espace as mensagens MAIS que o tempo de processamento (debounce 8s + agente ~10s = ~18s; injetar a 11s gera race onde o turn N lê estado do turn N-1 antes dele persistir). E o bug de "re-saudação no meio da conversa" só aparece DEPOIS de passar do `contextWindowLength` do buffer (>8 turnos) — teste com conversa LONGA, não 2 turnos.
5. **Limpe os leads/mensagens de teste** depois (`DELETE WHERE phone LIKE '<prefixo de teste>%'`) — a injeção popula `<agente>_leads`/`_messages`.

Para rodar isso como suíte de regressão, com lead simulado conversando por muitos turnos, checagens em código e juiz: [qa-simulada.md](qa-simulada.md).

⚠️ **Campos de data no payload: use o formato do provider (ISO/string), NÃO epoch-millis numérico**. Um Switch/IF que compara o campo como `dateTime` (ex.: debounce `tempo before $now.minus(Ns)`) quebra com `Conversion error: the string '...' can't be converted to a dateTime`. É bug do **payload de teste**, não do workflow — em produção o provider manda o formato certo. Sintoma: a execução de teste passa pelo dedup/normaliza e morre num Switch de tempo.

### Continuidade/saudação: derive de fonte PERSISTENTE, nunca de `staticData` volátil

Bug clássico (o cliente reporta que o agente "re-saúda como se zerasse a janela"): o flag "já cumprimentei" (`saudacao_enviada`) vinha do `convState` em `$getWorkflowStaticData` (volátil — sofre race entre turnos rápidos E some em restart do n8n) + o "Resumir Histórico (OpenAI)" retornava `SEM_HISTORICO` mesmo havendo mensagens. Resultado: o agente "esquece" que já falou e se reapresenta no meio da conversa.

**FIX:** dar ao agente um sinal de continuidade **determinístico** lido do **histórico persistente** (a tabela `<agente>_messages` via o node "Memória Antiga"): no node que monta a entrada, `var histCount = $('Memória Antiga').all().length; var jaConversou = histCount > 1;` e injete no prompt uma linha que força "se há histórico → é PROIBIDO se reapresentar". Não confie só no buffer de N turnos (some após N) nem no staticData (volátil). `<agente>_messages` grava cedo e sobrevive a restart, então `histCount` é a fonte robusta.

⚠️ **`> 1`, NÃO `> 0` (bug real):** se o node "Log Entrada" (INSERT da msg atual em `<agente>_messages`) roda ANTES do "Memória Antiga" (`Log Entrada → Memória Antiga`), o `histCount` JÁ inclui o turno atual. Com `> 0` o `jaConversou` fica SEMPRE true → o agente **nunca se apresenta, nem ao lead novo** (1ª msg → histCount=1). Use `> 1` (existe histórico ALÉM do turno atual) — ou leia Memória Antiga ANTES do Log Entrada. O mesmo +1 contamina o gate de qualquer prepend "[conversa já em andamento]".

⚠️ **Cuidado com sinal volátil EAGER paralelo:** se houver um `greetingDerived`/`saudacao_enviada` derivado do `convState` que liga "sim" quando a msg ATUAL gera facts/stage/intent (`factsKeys>0 || stage!=='inicio' || intent!=='outro'`), ele trava a apresentação do 1º contato sozinho — esses termos vêm da classificação do turno corrente (eager). Use só sinais de turnos ANTERIORES (`greeting_sent`, `last_bot.length>0`) + o `jaConversou` persistente.

⚠️ **Guard que strippa saudação NÃO pode strippar IDENTIDADE:** se o Guard tem `stripGreeting` que em turno ≥2 remove frases de saudação, garanta que o `isGreetingSentence` NÃO case "sou a <nome>"/"me chamo <nome>" — senão a resposta de identidade ("Sou a Bia, da equipe do Sr. Silva") é mutilada (o split por `.` quebra no "Sr." e sobra "Silva 😊", parecendo que o bot É o dono). Identidade ≠ saudação.

**`#RESET` virar "simular lead novo" (não só "limpar contexto"):** zerar sessionId/buffer NÃO basta — "Memória Antiga" lê por phone e ignora o reset. Filtrar a query: `... AND created_at > to_timestamp($2::double precision / 1000.0) ...` com `queryReplacement` ARRAY `[phone, resetTimestamp]`; expor o `resetTimestamp` (do `$getWorkflowStaticData['reset_'+phone]`) no node que alimenta a query; e no "Executar Reset" limpar as chaves por-phone NÃO-sessionId (`stage_/sentiment_/obj_<phone>`), senão `currentStage = classification.stage || prevStage` herda estado velho. Filtrar a Memória Antiga (chokepoint) torna histCount E o resumo reset-aware de uma vez. (Reset persiste no staticData mesmo em queue mode.)

---

---

## Common Mistakes & Fixes

| Erro | Solução |
|---|---|
| PUT workflow sem `name` | Sempre inclua `wf.name` |
| `settings` com props extras | Só `{ executionOrder: 'v1' }` |
| Template literal aninhado em Code Node (crase dentro do `${}`) | Array + `join`; o simples roda, e concatenação com `+` é convenção do kit (regra 1 do `code-node.md`) |
| Chatwoot webhook loop | `private: true` (nota interna) ou, para outgoing público, `source_id: n8n-...` + filtro no Processar Evento Chatwoot |
| Chatwoot labels sobrescritos | GET labels → union → POST (merge semântico) |
| Chatwoot não envia headers | Usar `?token=` query param |
| `assignee_changed` no Chatwoot | Não existe — usar `conversation_updated` |
| Status lookup falha | Dual lookup: message_id → provider_message_id |
| Dispatch tracking race condition | Insert ANTES de retornar response |
| Duplicate dispatch_sent | Ignore erro 23505 (idempotente) |
| Reply sem dispatch anterior | Insert novo registro (graceful) |
| Timezone errada no resumo | Calcular startOfDay com offset BRT (UTC-3) |
| Chatwoot messageCount inflado | É lifetime, não só hoje (trade-off aceito) |
| Schedule trigger não dispara | Desativar/reativar workflow pela UI do N8N |
| Cron conflito | Offset de minutos (ex: `:05` vs `:00`) |
| Follow-up repetido | Verificar existência de dispatch `modo: "followup"` após updated_at |
| ElevenLabs billing error | Nó "Verificar TTS" checa mimeType antes de enviar |
| Audio sem phone | Buscar de múltiplas fontes (msg, chat, webhook) |
| Payload UAZAPI flat | UAZAPI envia aninhado: `body.message.chatid` |
| Header UAZAPI `AdminToken` | Usar `token` (lowercase) |
| Mock de test desalinhado | Se a rota usa o helper de auth que aceita segredo no header OU na query, o mock do módulo de auth tem que incluir essa função também |
| Type error ao mockar o helper genérico que casa lead por telefone | Cast do mock com `as never` em testes |
| Past template activity query | Usar `.or()` com 3 flags separadas (read_at, replied_at, delivered_at) |
| Template `header_handle` retorna "Media upload error" | Não usar URL `scontent.whatsapp.net` direto — cachear em storage público próprio |
| `{{ JSON.stringify() }}` inline em jsonBody quebra | Usar Code node + single-expression body `={{ JSON.stringify($json) }}` |
| Webhook trigger não usa workflow novo após PUT | Fora de queue mode: deactivate+activate. Em queue mode o ciclo não recupera (webhook 404 com `active:true`) — só o Publish no editor (não é universal: em alguns n8n 2.x em queue mode o PUT manteve o webhook; teste com workflow-sonda); ver `n8n-api.md` § Webhook Trigger NÃO REGISTRA |
| Webhook não cria execution mas retorna 200 | Host errado — usar webhook receiver host, não editor host |
| `POST /mcp/<path>` ou `/form/<path>` dá "Cannot POST" (Express), mas `/mcp-test/<path>` responde "webhook not registered" | O proxy do queue mode só roteia `/webhook/*` para o worker. MCP stateless sobre Webhook comum; ver `n8n-api.md` § O proxy só roteia `/webhook/*` |
| Whisper volta 400 "Unrecognized file format" / agente responde "[áudio que não consegui transcrever]" para todo áudio | Binário sem extensão no nome (link da UAZAPI `/files/<hash>`). Code node renomeando para `audio.mp3` antes do HTTP; ver `integrations-misc.md` § OpenAI Whisper |
| Agente chama tool de sub-workflow e fica sem resultado | Sub-workflow devolve a saída do ÚLTIMO nó executado; ramo que termina em Switch/IF sem ligação devolve vazio. Ver § Sub-workflow como tool, abaixo |
| Áudio inbound >~1min: `media_url` NULL, UI "Mídia indisponível", n8n `Ingerir Mídia` = `not having enough compute resources` | Transcode opus→mp3 **no sync** da edge OOMa (arquivo ~120KB ainda estoura RAM). Fix: upload `.ogg` na resposta + `EdgeRuntime.waitUntil` pra mp3/Whisper; n8n passa `inbound_id`, timeout 300s. Ver `/kit-vamoo:whatsapp-inbox-stack` gotcha #9. Pill "IA leu: Categoria · Nome" = extração lead, não Whisper |
| Áudio do agente não aparece no Chatwoot | NotificaMe channel mirror só faz INCOMING; postar outgoing via multipart explicit + source_id |
| Loop infinito Chatwoot ↔ N8N | `source_id: n8n-...` + filter no Processar Evento Chatwoot |
| AI agent thanks-spiral com outro bot | Loop Detector + counter staticData + Redis pause 7d |
| Templates não aparecem no app WhatsApp Business (coexistence) | By design Meta — só aparecem no CRM espelho, nunca no app |
| Switch2 dedup filtra teste como "stale" | Use phone fresco — buffer Redis tem mensagens antigas com message_id ≠ atual |
| Redis node sem credencial | Adicionar `credentials: { redis: { id, name } }` no node spec do PUT |
| Vercel env value tem `\n` literal no fim | Cleanup com `raw.endsWith('\\n') ? raw.slice(0,-2) : raw` |
| Bucket Supabase Storage criado mas sem RLS | Bucket público (`public: true`) já permite read; service role bypassa RLS para writes |
| Labels de janela SQL com ±3h shift | `AT TIME ZONE` aplicado 2x — remover o segundo do `to_char` (valor já está em local time) |
| Postgres node downstream duplica queries | Fan-out via items do Code node — usar N HTTP nodes paralelos em vez de N items |
| Balões de mensagem chegam fora de ordem (3-1-2) | Wait com delay proporcional ao texto num fan-out de N items — balão curto chega primeiro. Fix: `splitInBatches` loop (1 por vez) + `delay` nativo UAZAPI |
| Stage do Pipedrive aparece como "Stage 4" sem nome | `STAGE_NAMES` hardcoded incompleto — fetch via `GET /stages?pipeline_id=X` antes do build |
| JSON do workflow vira escape hell com SQL+JS inline | Separar em `src/sql/<feature>/*.sql` + `scripts/<feature>/code-*.js` + `build-workflow.js` que monta o JSON |
| Agente de qualificação re-pergunta estado já preenchido / qualifica em duplicidade / trata um tipo de lead com o roteiro do outro | Ler estado (UTM/faixa) ANTES do roteiro + idempotência por lead + ramificar os dois tipos de lead com roteiros diferentes (ex.: quem vende vs quem compra). Sinal de alerta no log: cliente pergunta "é um robô?" |
| `queryReplacement` desalinha params / messageId numa coluna timestamp / texto truncado na vírgula / **cron reenvia (flood)** | CSV split por vírgula quebra com QUALQUER texto livre. Trocar `={{a}},={{b}}` por ARRAY `={{ [a, b] }}` (mantém executeQuery) ou `operation:insert`+defineBelow |
| Schedule trigger não dispara após PUT, mas webhook dá 404 | Schedule de workflow NOVO ativado **via API DISPARA** (≠ webhook). Use isso p/ rodar SQL/DDL ad-hoc via workflow schedule temp quando não há connection Postgres local |
| Precisa rodar DDL/SQL mas não tem `SUPABASE_DB_URL` local | Workflow temp `Schedule(1min)→Postgres(executeQuery)` c/ a cred do n8n; multi-statement terminando em SELECT (CREATE/UPDATE 0-rows trava o encadeamento) |
| Agente re-saúda "como se zerasse a janela" no meio da conversa | Continuidade vinha de `staticData` volátil + Resumir Histórico=SEM_HISTORICO. Derivar `jaConversou` do histórico PERSISTENTE (`$('Memória Antiga').all().length > 1` quando o Log Entrada grava antes — ver § Continuidade/saudação) e forçar no prompt |
| Testar bug do agente sem mandar msg a ninguém | Injetar payload no webhook com número DDD `00` (inválido); o agente processa, o `/send` falha, inspeciona Guard flags via `/executions?includeData`. Testar saudação exige conversa LONGA (>buffer) e espaçar > tempo de processamento (evitar race) |

---

---

## Sub-workflow como tool: devolve o último nó executado

Execute Workflow e Call n8n Workflow Tool devolvem ao chamador a saída do **último nó executado** no sub-workflow. Um ramo que termina num Switch ou IF sem nada ligado na saída tomada devolve vazio, e o agente fica sem resultado de tool (sintoma: a tool "roda" na execução do sub-workflow, mas o agente responde como se ela não tivesse retornado nada). Fix: todo ramo termina num nó que monta a resposta, como um Set ou Code com `{ ok, mensagem }`, inclusive os ramos de erro e de "nada a fazer".

## Testing Patterns

### Mock de Chatwoot config

```typescript
// nomes ilustrativos: use os do seu módulo do Chatwoot
vi.mock("<módulo do Chatwoot>", () => ({
  lerConfigChatwoot: vi.fn(),
  lerAtividadeDoDia: vi.fn(),
}));
// Default: não configurado (config rejeitada = o caminho "Chatwoot ausente")
vi.mocked(lerConfigChatwoot).mockRejectedValue(new Error("Not configured"));
```

### Mock de webhook auth

```typescript
// nomes ilustrativos: use os do seu módulo de auth HTTP
vi.mock("<módulo de auth HTTP>", () => ({
  authPorHeader: vi.fn(),
  authPorHeaderOuQuery: vi.fn(),  // OBRIGATÓRIO se a rota do webhook do Chatwoot usa a variante com query param
  montarCors: vi.fn((_o, _h, methods) => ({...})),
  mensagemDeErro: vi.fn((e, f) => e instanceof Error ? e.message : f),
}));
```

### Mock do helper que casa lead por telefone

```typescript
// nome ilustrativo: use o do seu helper de telefone
// Função genérica — cast com `as never` para evitar type error
vi.mocked(casarLeadPorTelefone).mockReturnValue({ id: "lead-1", telefone: "..." } as never);
```

### Mock de Supabase (Proxy-based fluent chain)

```typescript
function createMockSupabase(defaultResult = { data: [], error: null }) {
  const fromFn = vi.fn(() => new Proxy({}, {
    get(_target, prop) {
      if (prop === 'then') return undefined;
      return (...args) => { /* return self or result */ };
    }
  }));
  return { from: fromFn };
}
```

### Matriz de estado de agente conversacional (não só happy path)

Agente de qualificação alucina re-perguntando/duplicando quando o estado JÁ vem preenchido. Antes de marcar "pronto", rode a matriz de estado — não só o lead novo do caminho feliz:

- Lead com UTM/faixa de investimento já preenchida → NÃO pode re-perguntar.
- Lead já qualificado → qualificação idempotente (não duplica).
- Dois tipos de lead com roteiros diferentes (ex.: quem vende vs quem compra) → cada um no seu roteiro; um não é tratado como o outro.
- Multi-destinatário (ex: escalação de vendedor ausente): asserir que TODOS os N destinatários receberam, não só o primeiro — "alerta pra 1 de N" = falha.
- Tom: saudar → apresentar → responder a pergunta → só então encaminhar; sem repetir "o especialista vai confirmar". Sinal de alerta no log: cliente pergunta se está falando com robô.
