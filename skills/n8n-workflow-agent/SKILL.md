---
name: n8n-workflow-agent
description: Use when building, editing, debugging, or deploying n8n workflows that use WhatsApp agents — covers n8n API, Code Node rules, UAZAPI, Chatwoot, NotificaMe, dispatch pipeline, client pipeline, daily summary, ElevenLabs TTS, Redis pausa, and common pitfalls learned from production incidents
---

# n8n Workflow Agent — Full WhatsApp Automation Stack

## Overview

Reference skill for building and maintaining WhatsApp AI agent systems. Covers:
- **n8n**: API, Code Nodes, workflow patterns
- **UAZAPI**: WhatsApp provider (internal alerts, media)
- **NotificaMe**: WhatsApp provider (client-facing templates)
- **Chatwoot**: Omnichannel CRM (mirror, labels, transfer, activity)
- **Dispatch Pipeline**: dispatch backend (or n8n itself) → N8N → NotificaMe → webhook callbacks
- **Client Pipeline**: Stage advancement (contatado → visualizado → interagiu → qualificado → transferido)
- **Daily Summary**: Aggregated daily report via UAZAPI
- **ElevenLabs**: TTS for audio responses
- **Redis**: Pausa IA, debounce

Born from production — every rule prevented or fixed a real bug.

---

## Layout Visual — Linhas Retas (REGRA DURA — NUNCA QUEBRAR)

**NUNCA criar nodes com conexões que se cruzam.** Isso é inegociável. Workflows são lidos visualmente por humanos. **Linhas que se cruzam = caos cognitivo = rejeição imediata.** Canvas limpo com chains retas é o padrão esperado — confirmado em produção.

Ao posicionar nodes via API (`node.position = [x, y]`), SEMPRE calcular coordenadas para garantir zero cruzamentos. Se um workflow simples (linear) não tem branches, todos os nodes ficam na mesma Y com X crescente.

### Regras

1. **Chain linear horizontal:** mesma coordenada Y. Se A→B→C, mantém Y constante, varia só X. Espaçamento mínimo 220px em X.
2. **Branches paralelas em Y separados:** quando um Switch/IF cria N branches, distribui em Y crescente (ex: branch[0] Y=400, branch[1] Y=600, branch[2] Y=800). Cada branch corre horizontal nessa Y dela.
3. **Branches que convergem:** quando 2+ branches voltam pro mesmo node downstream, escolhe a Y do branch principal e roteia visualmente em "L" (canto reto), nunca em diagonal.
4. **Não puxa linha pra trás:** se um node referencia outro upstream via `$('Foo').first()`, mantém a conexão visual fluindo pra direita. Pra trás é só pra Wait/Loop com retorno explícito.
5. **Sub-fluxos verticais quando branches são muitas:** se Switch tem 4+ branches, considera empilhar verticalmente em colunas alinhadas (canvas vira grid).
6. **Hierarquia Y por tipo de operação:** Y baixo = caminho feliz; Y alto = error handling, skip branches, alerts. Mantém consistente no workflow inteiro.

### Anti-pattern (causa cruzamento)

- Mover um node "pra cima" geometricamente quando o anterior está embaixo → cria diagonal que cruza outras chains
- Mesma Y pra branches paralelas (todas em 400) → ramais sobrepostos
- Posicionar Set/Code "auxiliar" longe do node que consome → linha longa atravessa outras

### Ao editar via API

`node.position = [x, y]` é onde o n8n renderiza. Quando script adiciona um node novo no meio de uma chain, **calcula a posição assim**:

```python
# Insere node entre A e B
new_x = nodeA["position"][0] + 220
new_y = nodeA["position"][1]   # mesma Y de A
# Depois shifta B (e tudo a partir dele) +220 em X pra abrir espaço
```

Sem isso, fica empilhado em cima ou cruzando. Após PUT, drag+save no UI **preserva** as coordenadas (não auto-relayouta) — então responsabilidade do script colocar certo já.

---

## Build Pattern: Workflows Complexos a partir de Source Files

Quando o workflow tem **muitas SQL queries grandes + vários Code nodes com lógica de formatação**, editar o JSON do workflow direto vira escape hell (strings com newlines, aspas, etc.). Pattern alternativo: **gerar o JSON via build script** que lê arquivos source isolados.

### Estrutura

```
src/sql/<feature>/
  01-query-a.sql                    # cada query em arquivo próprio (testável via psql)
  02-query-b.sql
  03-...
scripts/<feature>/
  code-format-msg.js                # cada Code node em JS importável (testável via Node + module.exports)
  code-process-x.js
  test-format-msg.js                # unit tests em Node puro com mock $input
  build-workflow.js                 # lê SQLs + JS, monta workflow JSON
wf-<feature>.json                   # OUTPUT do build (committed, mas regenerável)
```

### Anatomia do `build-workflow.js`

```javascript
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '../..');
function sql(name) { return fs.readFileSync(path.join(ROOT, 'src/sql/<feature>', name), 'utf8'); }
function js(name)  { return fs.readFileSync(path.join(ROOT, 'scripts/<feature>', name), 'utf8'); }

// Strip Node-only `module.exports` block (n8n Code node não aceita)
function stripExports(code) {
  return code.replace(/\nif \(typeof module[\s\S]*$/m, '');
}

const nodes = [
  { id: '...', name: 'Query A', type: 'n8n-nodes-base.postgres', typeVersion: 2.6,
    position: [x, y], parameters: { operation: 'executeQuery', query: sql('01-query-a.sql'), options: {} },
    credentials: { postgres: CRED_POSTGRES } },
  { id: '...', name: 'Format X', type: 'n8n-nodes-base.code', typeVersion: 2,
    position: [x, y], parameters: { language: 'javaScript', jsCode: [
      stripExports(js('code-format-msg.js')),
      '',
      'var d = { input: $("UpstreamNode").first().json.resumo };',
      'return [{ json: { text: formatMsg(d) } }];'
    ].join('\n') } },
];

const connections = { /* node-name keyed */ };

fs.writeFileSync(path.join(ROOT, 'wf-<feature>.json'),
  JSON.stringify({ name: '...', nodes, connections, settings: { executionOrder: 'v1' }, staticData: null }, null, 2) + '\n');
```

### JS module dual-mode (testável + n8n-compatível)

```javascript
function formatMsg(d) {
  // ... lógica
  return text;
}

// Export para Node tests (n8n ignora este bloco)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = formatMsg;
}
```

No build script, `stripExports()` remove o bloco antes de embutir no `jsCode`.

### Benefícios

- **SQL testável solo:** `./scripts/db-query.sh -f src/sql/<feature>/01-query.sql --output json | jq`
- **JS testável solo:** `node scripts/<feature>/test-format-msg.js` com mock de `$input`
- **TDD real:** test failing → impl → test passing → commit por arquivo
- **Diffs legíveis:** cada commit toca 1 SQL ou 1 JS, não um JSON monolítico
- **Reuso:** mesma SQL/JS pode entrar em 2+ workflows

### Quando NÃO usar

- Workflows com <5 nodes ou só nodes nativos do n8n (Set, IF, HTTP) — overhead não compensa
- Quando a equipe edita só pela UI do n8n — build script vira fonte concorrente
- Protótipos descartáveis

---

## n8n API

### Endpoints

```
Base: https://<your-n8n-editor-host>    # ex: https://n8n.example.com
Header: X-N8N-API-KEY: <jwt-token>

GET    /api/v1/workflows/{id}          — ler workflow
PUT    /api/v1/workflows/{id}          — atualizar (REQUER campo `name`)
POST   /api/v1/workflows/{id}/activate — ativar
POST   /api/v1/workflows/{id}/deactivate
GET    /api/v1/executions?workflowId={id}&limit=5
GET    /api/v1/executions/{execId}
```

### PUT Payload (unica fonte de bugs recorrentes)

```js
{
  name: wf.name,           // OBRIGATORIO — sem isso da 400
  nodes: wf.nodes,
  connections: wf.connections,
  settings: { executionOrder: 'v1' }  // SO ISSO — nada de binaryMode, availableInMCP
}
```

**Armadilha:** Se copiar `wf.settings` direto do GET, inclui props extras que causam erro silencioso. Sempre recrie manualmente.

### Script Pattern (Node.js puro, sem deps)

```js
var https = require('https');
function apiCall(method, path, body) {
  return new Promise(function(resolve, reject) {
    var bodyStr = body ? JSON.stringify(body) : '';
    var options = {
      hostname: HOST, path: path, method: method,
      headers: { 'X-N8N-API-KEY': API_KEY, 'Content-Type': 'application/json' }
    };
    if (body) options.headers['Content-Length'] = Buffer.byteLength(bodyStr);
    var req = https.request(options, function(res) {
      var data = '';
      res.on('data', function(chunk) { data += chunk; });
      res.on('end', function() {
        try { resolve(JSON.parse(data)); }
        catch(e) { reject(new Error('Parse: ' + data.substring(0, 500))); }
      });
    });
    req.on('error', reject);
    if (body) req.write(bodyStr);
    req.end();
  });
}
```

### Workflow Versioning Guard

Workflows podem reverter. **Sempre** cheque node count antes/depois:

```js
console.log('Nodes ANTES:', wf.nodes.length);
console.log('Nodes DEPOIS:', payload.nodes.length);
console.log('Nodes CONFIRMADO:', result.nodes.length);
```

### Schedule Trigger Caveat

Schedule triggers no N8N podem não re-registrar após updates via API. Se um cron não disparar, desativar/reativar o workflow **pela interface do N8N**.

**MAS — schedule trigger de workflow NOVO, ativado via API, DISPARA** (confirmado em produção, sessão <agente> 2026-06-06, mesmo deploy queue-mode onde webhook dá 404). Diferença prática: o roteador HTTP de webhooks não recebe o evento de registro via API, mas o agendador interno de schedules sim. `minutesInterval: 1` ativado via API disparou em ~15-60s (alinha ao minuto cheio).

### Rodar SQL/DDL ad-hoc sem connection direta ao Postgres (padrão "n8n como executor")

Quando você só tem a **credencial Postgres dentro do n8n** (sem `SUPABASE_DB_URL` local), rode SQL via um **workflow temporário schedule** (já que schedule via API dispara — ver acima):

1. POST `/workflows` com `Schedule(minutesInterval:1) → Postgres(executeQuery, credentials da cred existente)`. Extraia o credential id de qualquer node Postgres de um workflow exportado.
2. `POST /activate` → o schedule dispara em ~15-60s.
3. Leia o resultado em `GET /executions?workflowId=X&includeData=true` (campo `runData["NodeName"][0].data.main[0]`).
4. `POST /deactivate` + `DELETE /workflows/{id}` (limpeza).

**DDL via executeQuery trava o encadeamento:** `CREATE TABLE`/`UPDATE` que afetam 0 rows emitem **0 items** → nodes downstream não rodam (ver "executeQuery retornando 0 rows"). Para um setup multi-statement (CREATE + CREATE + INSERT + verificação), use **UM** Postgres node com todos os statements separados por `;` terminando num **`SELECT`** — o node retorna o resultado do último statement (sempre ≥1 row) e nada trava. Backfill/DDL idempotentes (`IF NOT EXISTS`, `ON CONFLICT DO NOTHING`) tornam re-runs seguros se o schedule disparar 2x antes do delete.

### Workflow Reload after API PUT (CRÍTICO)

**Mesmo problema atinge webhook triggers em alguns casos.** Após `PUT /workflows/{id}`, o N8N pode continuar servindo execuções com a definição anterior em cache. Se uma nova node adicionada não aparecer no `runData` mesmo o `connections` mostrando que ela está wirada, force reload via API:

```js
await apiCall('POST', '/api/v1/workflows/' + WORKFLOW_ID + '/deactivate');
await new Promise(r => setTimeout(r, 1500));
await apiCall('POST', '/api/v1/workflows/' + WORKFLOW_ID + '/activate');
```

**Sintomas do bug:** runData mostra `Resposta → Check Transferencia` direto, pulando a node nova que você inseriu entre as duas. Solution: deactivate+reactivate cycle.

### Webhook Trigger NÃO REGISTRA via API (n8n self-hosted em queue mode)

Em deploys self-hosted com queue mode (main + webhook worker separados), workflows **criados ou atualizados via API REST** ficam com `active=true` no DB mas o roteador HTTP retorna **404 "webhook not registered"**. O deactivate+activate cycle acima TAMBÉM falha — não dispara o pubsub event que avisa o webhook worker pra recarregar rotas.

**Sintoma:**
```bash
curl -X POST .../api/v1/workflows/{id}/activate → 200, active=true
curl -X POST .../webhook/<path> → 404 "not registered"
```

**Diagnóstico rápido:** se um workflow ATIVADO PELA UI no mesmo deploy responde mas o criado-via-API não, é esse bug.

**Fix confirmado em produção:**
1. Abrir o workflow no editor n8n UI
2. **Arrastar qualquer nó** (move diff real — Cmd+S sem diff não basta)
3. Salvar (Cmd+S) → toast "Workflow saved" aparece
4. Webhook fica online imediatamente

**Implicação grave para iteração:** cada `PUT /workflows/{id}` via API desregistra o webhook. Após qualquer PUT, repetir o ritual drag+save no UI. Estratégia: minimizar PUTs (consolidar mudanças num único push) ou migrar pra editar no UI direto após o setup inicial.

### Hosts: Editor vs Webhook Receiver

**Editor/API** (para CRUD de workflows, executions): `https://<your-n8n-editor-host>`
**Webhook receiver** (para disparar workflows): `https://<your-n8n-webhook-host>`

Em deploys com queue mode, são SUBDOMÍNIOS DIFERENTES. Disparar webhook no host do editor retorna 200 fake mas não cria execution. Use o `webhookUrl` que aparece em uma execução real para confirmar o host correto:

```bash
# Verificar host real:
curl ".../api/v1/executions/{id}?includeData=true" | jq '.data.resultData.runData.Webhook1[0].data.main[0][0].json.webhookUrl'
```

### Verificar config-version mismatch

```js
// Comparar version IDs antes/depois do PUT
console.log('versionId:', wf.versionId);
console.log('activeVersionId:', wf.activeVersionId);
// Se diferentes → workflow tem mudanças não publicadas, reload necessário
```

---

## Code Node Rules (CRITICO)

### 1. NUNCA use template literals (backticks)

n8n interpreta `$input`, `$json`, `$()` como expressoes internas.

```js
// ERRADO
var url = `https://api.com/${id}`;
// CERTO
var url = 'https://api.com/' + id;
```

### 2. Use `var` em vez de `const`/`let`

### 3. Sem optional chaining (`?.`) nem spread (`...`)

```js
// ERRADO
var x = obj?.nested?.value;
// CERTO
var x = (obj && obj.nested && obj.nested.value) || '';
```

### 4. `$json` vs `$('NodeName')`

- `$json` = output do node ANTERIOR (conectado)
- `$('NodeName').first().json` = output de qualquer node upstream pelo nome

### 4b. `.first()` em node com múltiplos outputs (CRÍTICO)

**`$('NodeName').first()` lê APENAS de `main[0]`.** Se o node referenciado tem múltiplas saídas (Switch/IF/Code com N branches), `.first()` ignora as outras.

**Sintoma:** node retorna `[]` (vazio) silenciosamente quando o branch tomado não é o output 0. Fluxo aborta no `if (!tm) return []`.

**Caso real:** node `Tipo Mensagem` com 3 outputs (texto / audio / imagem). Buffer downstream lia `$('Tipo Mensagem').first().json` — funcionava pra texto (main[0]), mas pra audio (main[1]) retornava undefined. O agente nunca respondeu áudio porque o buffer abortava.

**Fix:** ler de cada branch destino (que tem o item materializado) com fallback:

```js
var tm = null;
try { var x = $('Set Texto Audio').first().json; if (x && x.phone && x.msgId) tm = x; } catch(e){}
if (!tm) { try { var x = $('Set Texto Imagem').first().json; if (x && x.phone && x.msgId) tm = x; } catch(e){} }
if (!tm) { try { var x = $('Tipo Mensagem').first().json; if (x && x.phone && x.msgId) tm = x; } catch(e){} }
if (!tm || !tm.phone || !tm.msgId) return [];
```

**Diagnóstico rápido:** se um node downstream de um Switch/IF retorna `data.main[[]]` (vazio) em execuções específicas, suspeite de `.first()` num node multi-output upstream.

### 5. jsCode em scripts externos: arrays de strings

```js
var code = [
  'var data = $input.first().json;',
  'return [{ json: { phone: phone } }];'
].join('\n');
node.parameters.jsCode = code;
```

### 6. JSON.stringify no body de HTTP requests

Emoji, aspas, newlines quebram JSON inline. Sempre serialize:

```js
var bodyStr = JSON.stringify({ number: phone, text: mensagem });
```

---

## HTTP Node `jsonBody` Pitfalls (CRÍTICO)

### Inline `{{ JSON.stringify(...) }}` causa double-escaping

**SINTOMA:** API destino retorna `{"error":"invalid syntax"}`. O response do node mostra que o campo virou string em vez de array/object. Ex: `"contents": "[{\"type\":\"template\"...}]"` em vez de `"contents": [{...}]`.

**ROOT CAUSE:** Quando o `jsonBody` é uma string template (começa com `=` e contém `{...}` JSON literal com `{{ }}` interpolations no meio), o N8N evaluator:
1. Avalia cada `{{ JSON.stringify(arr) }}` → retorna string `[{"a":1}]`
2. **Insere essa string AS-IS no template, MAS dentro do contexto JSON** → vira `"[{\"a\":1}]"` quando o body final é parseado.
3. API recebe componente como STRING, não como array.

**ERRADO** (template com inline stringify):
```
={
  "contents": {{ JSON.stringify($json.headerImageUrl ? [{type:'header',parameters:[...]}] : []) }}
}
```

**CERTO** (Code node + single-expression body):
1. Code node `Build Body` retorna o objeto completo
2. HTTP node usa `jsonBody: ={{ JSON.stringify($json) }}` (expressão única, não template)

```js
// Code node "Build Body"
var body = $('Webhook').first().json.body;
var components = [];
if (body.headerImageUrl) {
  components.push({
    type: 'header',
    parameters: [{ type: 'image', image: { link: body.headerImageUrl } }]
  });
}
return [{ json: {
  from: 'channel-id',
  to: body.telefone,
  contents: [{ type: 'template', template: { name: body.templateId, components: components } }]
}}];
```

```
// HTTP node jsonBody (single expression — N8N serializa o input completo)
={{ JSON.stringify($json) }}
```

**Por que funciona:** Quando o `jsonBody` é UMA expressão única (não um template literal com `{...}` ao redor), o N8N evaluator pega o resultado da expressão e usa diretamente como body. Sem segunda camada de escape.

**Regra:** Se você precisa montar JSON com lógica condicional (arrays, objects condicionais), SEMPRE use Code node + single-expression body. NUNCA template inline com `{{ JSON.stringify(...) }}`.

### Multipart Form Upload com Binário (HTTP node)

Para upload de arquivo binário (áudio, imagem) via multipart:

**Setup do node:**
- `method`: POST
- `sendBody`: true
- `contentType`: `multipart-form-data`
- `bodyParameters.parameters[]`: lista mista de text + binary

**Cada parameter:**
```js
// Text field
{ parameterType: 'formData', name: 'content', value: 'texto qualquer' }

// Binary field — referencia binary key do item atual
{ parameterType: 'formBinaryData', name: 'attachments[]', inputDataFieldName: 'data' }
```

**Como o binário chega no item:** o node ANTERIOR precisa fazer um GET com `responseFormat: 'file'` e `outputPropertyName: 'data'`:

```js
// Node "Download File" (httpRequest)
{
  method: 'GET',
  url: '={{ $json.publicFileUrl }}',
  options: {
    response: {
      response: {
        responseFormat: 'file',
        outputPropertyName: 'data'  // → item.binary.data
      }
    }
  }
}
```

Aí o multipart node consome `inputDataFieldName: 'data'` para anexar.

**Pattern:** `Upload to storage → Download as binary → Multipart POST to destination`. Permite re-encaminhar arquivos entre serviços sem manter base64 na memory.

### "Missing required fields" — `genericCredentialType` + `specifyBody: "json"` (CRÍTICO)

**SINTOMA:** API destino retorna 400/422 `{"error":"Missing required fields"}` ou similar. Inspecionando o `runData`, o `content-length` da request é absurdamente pequeno (~36 bytes) — o body não foi enviado, foi a expressão crua.

**ROOT CAUSE:** dois campos faltando na config do node HTTP Request v4.x quando se usa credencial HTTP customizada (UAZAPI, Resend, Chatwoot, qualquer API com header `token`/`Authorization`):

```jsonc
// ❌ ERRADO — auth pattern de service built-in (Slack, etc) + sem specifyBody
{
  "authentication": "predefinedCredentialType",
  "nodeCredentialType": "httpHeaderAuth",
  "contentType": "json",
  "jsonBody": "={{ JSON.stringify({...}) }}"
}

// ✅ CERTO
{
  "authentication": "genericCredentialType",
  "genericAuthType": "httpHeaderAuth",
  "sendBody": true,
  "specifyBody": "json",
  "jsonBody": "={{ JSON.stringify({...}) }}"
}
```

`predefinedCredentialType` + `nodeCredentialType` é só para services com type-id próprio no n8n (Slack, Google, etc). Para custom header auth, sempre `genericCredentialType` + `genericAuthType`.

**`specifyBody: "json"` é OBRIGATÓRIO** quando `contentType` é JSON. Sem ele, o n8n não serializa o `jsonBody` e o request sai vazio. Se você está copiando configs de workflow exportado via API, esse campo às vezes some na exportação — sempre conferir.

**Diagnóstico rápido:** se o n8n exec mostra status 400/422 com erro "missing field" mas a request foi 200 via curl com o mesmo body, é esse pattern.

---

## PostgreSQL Pitfalls

### `AT TIME ZONE` double-conversion em janelas (CRÍTICO)

**SINTOMA:** queries de janela temporal retornam labels/timestamps com horário shiftado em ±N horas (tipicamente ±3h pra timezone Brasil).

**ROOT CAUSE:** `AT TIME ZONE` se comporta diferente conforme o tipo do operando:

| Operando | Comportamento |
|---|---|
| `timestamptz AT TIME ZONE 'X'` | **Converte** pra zone X, retorna `timestamp WITHOUT zone` com valor local em X |
| `timestamp AT TIME ZONE 'X'` | **Interpreta** o valor como já estando em zone X, retorna `timestamptz` (UTC) |

A confusão acontece quando você encadeia em queries de janela:

```sql
-- 1º AT TIME ZONE: NOW() é timestamptz, converte pra SP-local, retorna timestamp sem zone
WITH janela AS (
  SELECT date_trunc('hour', NOW() AT TIME ZONE 'America/Sao_Paulo') - INTERVAL '1 day' AS inicio
)
-- 'inicio' aqui = timestamp SEM zone, valor 08:00 SP-local

-- ERRADO: aplicar AT TIME ZONE de novo no to_char shifta ±3h
SELECT to_char(inicio AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24:MI') FROM janela
-- Output: "27/05 11:00" (shiftou: interpretou 08:00 SP como input, converteu pra 11:00 UTC)

-- CERTO: valor já está em SP-local, só formatar
SELECT to_char(inicio, 'DD/MM HH24:MI') FROM janela
-- Output: "27/05 08:00"
```

**Regra:**
- Use `AT TIME ZONE` UMA VEZ pra converter `timestamptz` → `timestamp without zone` (valor local).
- Depois disso, NÃO reaplique — formate direto com `to_char`.
- **Exceção legítima do 2º AT TIME ZONE:** quando você precisa COMPARAR um `timestamp without zone` (já local) com uma coluna `timestamptz`:
  ```sql
  WHERE l.created_at >= (j.inicio AT TIME ZONE 'America/Sao_Paulo')
  -- j.inicio é timestamp sem zone (SP-local) → AT TIME ZONE converte pra timestamptz pra comparar com created_at
  ```

### `json_build_object` + n8n Postgres node — shape do output

`SELECT json_build_object(...) AS resumo` retorna 1 row, 1 column. No n8n Postgres node, o output fica wrapped: `$('NodeName').first().json` = `{ resumo: {...} }`. Acesse via `.first().json.resumo`, NÃO direto.

Quando testando via `psql -t -A`, o output é o JSON value puro (sem wrap de row). **Comportamento divergente entre teste local e produção n8n** — vale lembrar:

```bash
# Teste local
psql ... -t -A -f query.sql | jq '.kpis'        # acessa direto

# No n8n Code node
var data = $('Postgres Node').first().json.resumo.kpis;  // precisa do .resumo
```

### `executeQuery` retornando 0 rows para o downstream (CRÍTICO)

**SINTOMA:** workflow "success" mas só rodou até o node Postgres — Decide Action / IFs / branches a seguir nunca executam. Sem erro, sem warning. Inspecionando `runData`, o último node executado é o Postgres.

**ROOT CAUSE:** quando `operation: "executeQuery"` retorna **0 rows**, o Postgres node emite 0 items. n8n não tem o que passar adiante, então downstream não roda. Branches que dependem de "estado anterior pode ser vazio" (state machines, dedup lookups, "primeira vez") quebram silenciosamente.

**FIX:** força a query a sempre retornar 1 row (com nulls se vazio) via CTE + scalar subqueries:

```sql
-- ❌ ERRADO — retorna 0 rows se ninguém logou ainda
SELECT status_atual, evento, disparado_em
FROM public.ultimo_estado_alerta('cliente_a');

-- ✅ CERTO — sempre 1 row, campos NULL se vazio
WITH ult AS (SELECT * FROM public.ultimo_estado_alerta('cliente_a'))
SELECT
  (SELECT status_atual  FROM ult) AS status_atual,
  (SELECT evento        FROM ult) AS evento,
  (SELECT disparado_em  FROM ult) AS disparado_em;
```

No Decide Action seguinte, tratar nulls explicitamente:
```js
var last = $input.first().json;
var lastStatus = last && last.status_atual ? last.status_atual : null;
```

### `queryReplacement` CSV split quebra com QUALQUER texto que tenha vírgula (CRÍTICO — causou flood real)

**SINTOMA:** INSERT desalinha os parâmetros — o valor de uma coluna acaba noutra. Variações: `invalid input syntax for type json`/`malformed array literal` (text[]/JSONB), OU `invalid input syntax for type timestamp/integer: "<lixo>"` quando um valor de texto empurra os params seguintes (ex.: um messageId cai numa coluna timestamp), OU o texto é **truncado na primeira vírgula** silenciosamente.

**ROOT CAUSE:** `options.queryReplacement` no formato `={{ a }},={{ b }},={{ c }}` é **CSV split por vírgula**. NÃO são só arrays/JSONB — **qualquer valor de texto livre com vírgula** (mensagem do cliente, `followText` de um follow-up, `pushName` "Maria, Silva") vira múltiplos campos e desalinha tudo a partir dali. Caso real (sessão <agente> follow-up 2026-06-06): o `content` do follow-up tinha vírgulas → o `uazapi_message_id` caiu na coluna `anchor_at` (timestamp) → INSERT do log falhou → idempotência quebrou → **cron reenviou o mesmo touchpoint a cada tick (flood)**.

**FIX A — ARRAY numa única expressão (mais simples, mantém `executeQuery`; preferido p/ UPSERT/CTE/RETURNING):**
```jsonc
// ❌ CSV: vírgula no texto desalinha
"queryReplacement": "={{ $json.phone }},={{ $json.next_tp }},={{ $json.followText }},={{ $json.msgId }}"
// ✅ ARRAY: cada elemento é UM parâmetro, vírgulas internas preservadas
"queryReplacement": "={{ [$json.phone, $json.next_tp, $json.followText, $json.msgId] }}"
```
Comprovado: `content` "Bom dia, Maria, teste, com, virgulas!" gravou íntegro. Vale também p/ `$('Node').first().json.campo` dentro do array. Se só UM valor é texto-livre, basta o array; se houver text[]/JSONB de verdade, use o Fix B.

**FIX B — `operation: "insert"` com `mappingMode: "defineBelow"`** (n8n escapa por coluna; melhor p/ text[]/JSONB, mas NÃO suporta ON CONFLICT/CTE):

```jsonc
{
  "operation": "insert",
  "schema": { "__rl": true, "value": "public", "mode": "list" },
  "table":  { "__rl": true, "value": "alertas_uazapi", "mode": "list" },
  "columns": {
    "mappingMode": "defineBelow",
    "value": {
      "cliente":      "={{ $json.cliente }}",
      "canais_ok":    "={{ $json.canais_ok || [] }}",       // array JS → text[]
      "detalhes":     "={{ JSON.stringify($json.detalhes || {}) }}"  // string JSON → JSONB
    }
  }
}
```

Use `executeQuery` só para SELECT, UPDATE simples sem JSONB, ou quando precisa de SQL real (CTEs, RETURNING).

### Supabase pooler URL para n8n self-hosted (IPv4)

**SINTOMA:** Postgres node erra com `connect ENETUNREACH 2600:...` ou `getaddrinfo ENOTFOUND`. Conectado em `db.<ref>.supabase.co:5432` (direct).

**ROOT CAUSE:** o host direto do Supabase resolve só pra IPv6 desde 2026. Containers n8n self-hosted (incluindo n8n.cloud, Railway, Hostinger Docker) geralmente não têm IPv6 outbound. Precisa usar o pooler Supavisor.

**FIX:** trocar pra pooler regional + user com sufixo do ref:

```
host:     aws-1-<region>.pooler.supabase.com   (ex: aws-1-sa-east-1.pooler.supabase.com)
port:     6543                                  (transaction pooler) ou 5432 (session pooler)
user:     postgres.<ref>                        (ex: postgres.ckzqlngaanjeqlnjoxqq)
password: <db password>
ssl:      omitir, usar allowUnauthorizedCerts: true (self-signed cert do pooler)
```

**Como descobrir a região + connection string oficial:**
```bash
curl "https://api.supabase.com/v1/projects/<ref>/config/database/pooler" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN"
# → {db_host, db_port, db_user, connection_string, pool_mode}
```

n8n credencial Postgres:
```jsonc
{
  "host": "aws-1-sa-east-1.pooler.supabase.com",
  "port": 6543,
  "database": "postgres",
  "user": "postgres.ckzqlngaanjeqlnjoxqq",
  "password": "<senha>",
  "allowUnauthorizedCerts": true,   // pooler usa self-signed
  "sshTunnel": false
}
```

Se também precisar via psql local (n8n já funciona): `psql "postgresql://postgres.<ref>:<pass>@aws-1-<region>.pooler.supabase.com:6543/postgres"`.

---

## Multi-destination Workflows (Fan-out Anti-pattern)

**Cenário:** mesmo conteúdo precisa ser enviado pra N destinos (ex.: WhatsApp pra Maria + João, email pra 3 stakeholders, etc.).

### Anti-pattern: fan-out via items do Code node

Tentação: fazer o Code node de formatação retornar N items (1 por destino):

```javascript
// ERRADO: Code "Format Message" retornando N items
var destinos = ['5547999999999', '5511988888888'];
return destinos.map(function(n) {
  return { json: { number: n, text: 'mensagem' } };
});
```

**Por que falha:** o HTTP Send downstream roda N vezes (✓ correto), mas QUALQUER node downstream depois disso também processa N items. Postgres queries duplicam, IFs avaliam por item, etc. Bug silencioso de duplicação.

```
[Format Message N items] → [HTTP Send N runs ✓] → [Postgres Query N runs ❌] → [IF N evals ❌] → ...
```

### Pattern correto: N HTTP nodes paralelos

Format retorna 1 item. N HTTP nodes em paralelo consomem o mesmo item, cada um com `number` hardcoded:

```
[Format Message 1 item]
  ├→ [HTTP Send Destino A — number hardcoded] (terminal)
  ├→ [HTTP Send Destino B — number hardcoded] (terminal)
  └→ [Next node downstream — 1 item ✓]
```

Em `connections`, fan-out vai no MESMO `main[0]` array:

```javascript
'Format Message': { main: [[
  { node: 'HTTP Send Destino A',  type: 'main', index: 0 },
  { node: 'HTTP Send Destino B',  type: 'main', index: 0 },
  { node: 'Next Downstream Node', type: 'main', index: 0 }
]] }
```

### Build script helper

Pra gerar N HTTP send nodes programaticamente:

```javascript
const DESTINOS = ['5547999999999', '5511988888888'];

const sendNodes = DESTINOS.map((number, i) => ({
  id: 'send-' + i,
  name: 'Enviar Msg ' + (i === 0 ? 'A' : 'B'),  // ou label do destino
  type: 'n8n-nodes-base.httpRequest',
  typeVersion: 4.2,
  position: [X, BASE_Y + i * 200],  // Y staggered pra não cruzar
  parameters: {
    method: 'POST',
    url: 'https://provider/send',
    sendBody: true, contentType: 'json', specifyBody: 'json',
    jsonBody: '={{ JSON.stringify({ number: ' + JSON.stringify(number) + ', text: $json.text }) }}',
    options: { timeout: 15000, response: { response: { neverError: true, responseFormat: 'json' } } }
  },
  retryOnFail: true, maxTries: 3, waitBetweenTries: 3000,
  credentials: { httpHeaderAuth: CRED_PROVIDER },
  onError: 'continueRegularOutput'
}));
```

### Trade-off

- **Pro:** clareza arquitetural, fácil debug por destino, posições visuais distintas.
- **Con:** adicionar 3º destino requer novo node no build script.
- **Quando aceitar fan-out via items:** se TODO downstream depois do send for terminal (não houver continuação do workflow). Aí múltiplos items não atrapalham.

---

## Ordem de Balões Múltiplos (Wait com delay variável EMBARALHA — CRÍTICO)

**Cenário:** agente IA retorna `{messages: [balão1, balão2, balão3]}` e o workflow envia cada balão como mensagem WhatsApp separada (saudação → apresentação → pergunta). A ORDEM importa — saudação precisa chegar antes da pergunta.

### Anti-pattern (real, cometido na <agente> (Cliente B) até 2026-06-01): fan-out de N items num Wait com delay proporcional ao texto

```
📨 Dividir Mensagens (N items) → ⏱️ Wait (amount = text.length * 0.025) → 📤 Enviar UAZAPI
```

**Por que embaralha:** os N items entram no Wait **ao mesmo tempo**, e cada um espera seu próprio tempo **a partir do mesmo instante** (delay absoluto, NÃO cumulativo). Como o tempo é proporcional ao tamanho do texto, **o balão mais curto dispara primeiro**.

**Sintoma real:** 3 balões enviados, chegam na ordem 3-1-2 porque a pergunta (texto curto) tinha o menor delay:

| Balão | Texto | len | delay | Chegada |
|---|---|---|---|---|
| 3 (pergunta) | "Você já é paciente...?" | 77 | 1,93s | 1º ❌ |
| 1 (saudação) | "Olá! Seja bem-vindo..." | 105 | 2,63s | 2º |
| 2 (apresentação) | "Vou te ajudar..." | 111 | 2,78s | 3º |

A ordem de chegada = ordenação por tamanho de texto. Diagnóstico: se a permutação observada bate com sort-by-length, é esse bug (previsão, não coincidência).

### Fix correto: loop sequencial com `splitInBatches`

```
📨 Dividir Mensagens (+typing_ms por balão)
   → 🔁 Loop Chunks (splitInBatches v3, batch=1)
       ├─[out 0 = done]→ Logger / log final (roda 1x)
       └─[out 1 = loop]→ 📤 Enviar UAZAPI → ⏱️ Wait 1s (fixo) → volta pro Loop Chunks
```

**Por que é o fix certo (não só *um* fix):** só **um item flui por vez**, então a ordem é garantida INDEPENDENTE de como o n8n trata o Wait em batches. Remove toda dependência da semântica do Wait multi-item.

**Connections (splitInBatches v3):** `out 0 = done`, `out 1 = loop`. Erro clássico é inverter — o branch de envio é o **out 1**, o de finalização é o **out 0**.

```js
'🔁 Loop Chunks': { main: [
  [ { node: 'Logger', type: 'main', index: 0 } ],          // out 0 = done (1x)
  [ { node: '📤 Enviar UAZAPI', type: 'main', index: 0 } ] // out 1 = loop body
] },
'📤 Enviar UAZAPI': { main: [[ { node: '⏱️ Wait 1s', type: 'main', index: 0 } /*, log por-item*/ ]] },
'⏱️ Wait 1s': { main: [[ { node: '🔁 Loop Chunks', type: 'main', index: 0 } ]] }  // loop-back
```

**Logging:** se um node de log grava **uma linha por balão** (`$json.text` do item atual), ele fica DENTRO do loop body (off Enviar UAZAPI). Se grava o resumo **1x por turno**, vai no branch done (out 0).

### "digitando…" nativo da UAZAPI em vez de travar o workflow

Não use o Wait do n8n pra simular digitação — ele bloqueia o workflow e não mostra "digitando…" no WhatsApp. Use o parâmetro `delay` (ms) no payload `/send/text`, calculado no Dividir:

```js
var typingMsPerChar = 35, typingMin = 1200, typingMax = 6000;
return messages.map(function(msg, index) {
  var text = (msg && msg.text) ? msg.text : msg;
  var dur = Math.min(typingMax, Math.max(typingMin, String(text).length * typingMsPerChar));
  return { json: { text: text, phoneNumber: phoneNumber, typing_ms: dur, /* ... */ } };
});
```

```
// 📤 Enviar UAZAPI jsonBody
={{ JSON.stringify({ number: $json.phoneNumber, text: $json.text, delay: $json.typing_ms }) }}
```

O `delay` faz a UAZAPI exibir "digitando…" por essa duração ANTES de enviar — natural e por balão. O `⏱️ Wait 1s` do loop vira só um pacer fixo entre envios. Sempre adicionar `retryOnFail: true, maxTries: 3` no Enviar — sem isso, um balão que falha some calado.

### Alternativa lighter-touch (delay cumulativo, sem loop)

Calcular no Dividir um delay **cumulativo** (`balão[i].delay = soma dos anteriores + o próprio`), monotônico crescente por índice → dispara em ordem. Menos nodes, mas ainda depende da semântica do Wait multi-item (frágil). Prefira o loop.

---

## UAZAPI (WhatsApp — Alertas Internos)

```
Base: https://<your-instance>.uazapi.com
Header: token: <instance-token>  (NÃO AdminToken — header `token` lowercase)

POST /send/text      — { number, text }
POST /send/media     — { number, type, file (base64 com prefix) }
POST /message/download — { id, return_link: true }
POST /chat/archive   — { number, archive: true }
GET  /instance/status
POST /message/find   — { messageid } → status delivery (Pending/Sent/Delivered/Read)
GET  /webhook        — lista webhook subscribers (multi)
```

### UAZAPI é Baileys, NÃO Meta Cloud API (regra dura)

UAZAPI usa o protocolo **Multi-Device do WhatsApp Web (Baileys)**, API **não-oficial**. Implicações práticas que confundem mesmo quem conhece a Cloud API oficial:

- **NÃO** há `reachout_timelock` da Meta. Pode enviar pra qualquer número a qualquer hora sem janela de 24h, sem template aprovado, sem opt-in prévio. O fluxo natural é `status: "Pending" → "Sent" → "Delivered" → "Read"` em segundos.
- **NÃO** há message templates. Cada `/send/text` é livre.
- **Risco real é da WhatsApp (não da Meta Business)** — bloqueio por volume/spam pattern do próprio app. Mitigar com aquecimento gradual de número novo (5-7 dias mandando msgs casuais antes de bulk).
- **`isBusiness: true`** no `/instance/status` significa apenas que a CONTA WhatsApp é Business (com perfil comercial visível). Não habilita features da Cloud API — segue sendo Baileys.
- Diagnóstico "mensagem não chega": NUNCA atribuir a regra Meta de 24h. Causas reais: número não tem WhatsApp ativo, conta bloqueada pelo WhatsApp por spam, Multi-Device da instância caiu (`lastDisconnect` recente), ou usuário só não notou (`/message/find` mostra status real).

### Phone normalization — leading 9 do mobile brasileiro (CRÍTICO)

WhatsApp normaliza números móveis brasileiros removendo o `9` extra do prefix. Exemplo: você manda `/send/text` com `number: "5547991234567"` (13 dígitos, com 9 do mobile) e o webhook retorna `chatid: "554791234567@s.whatsapp.net"` (12 dígitos, sem o 9).

| Forma | Quando aparece |
|---|---|
| `5547991234567` (13 dig, com 9) | Como você envia no body `/send/text`. Usuário tipicamente fornece nesse formato. |
| `554791234567` (12 dig, sem 9) | Como UAZAPI devolve no `chatid`, no webhook payload, e nos chats do Baileys. |

**Implicação grave:** filtros tipo `BLOCKED_PHONES`, dedup keys (`PAUSA_<agente>_<phone>`, `DEDUP_<phone>`), e qualquer lookup por phone precisam usar a versão **normalizada (sem o 9)** porque é o que o `chatid` retorna ao webhook. Se você popular essas keys com a versão de 13 dígitos, o filtro nunca casa.

Padrão de extração no Code node (consistente com o resto da skill):
```js
var rawPhone = msg.chatid ? msg.chatid.replace(/@.*$/, '') : (chat.phone || '');
var phone = rawPhone.replace(/\D/g, '');  // já vem normalizado (sem 9) do chatid
```

Se você precisa ENVIAR pra um número que veio no formato normalizado de 12 dígitos, pode mandar assim — UAZAPI aceita os dois formatos no `/send/text`.

### Quando usar UAZAPI vs NotificaMe

| Uso | Provider | Motivo |
|-----|----------|--------|
| Alertas internos (resumo diário, transferência) | **UAZAPI** | Envio livre sem template |
| Mensagens client-facing (SDR, nutrição, follow-up) | **NotificaMe** | Templates aprovados Meta |
| TTS/áudio para cliente | **NotificaMe** | Integra com Chatwoot canal |
| Espelhamento CRM | **Chatwoot** | Via NotificaMe integration |

### Múltiplos webhooks por instância (CRÍTICO)

UAZAPI aceita **múltiplos webhook subscribers** numa mesma instância (ex: workflow agente IA + workflow mirror Chatwoot). MAS:

- **`GET /webhook`** retorna **array** com todos os subscribers (cada um com `id`, `url`, `events`, `excludeMessages`).
- **`POST /webhook`** via API REST **NÃO cria um novo subscriber** — ele faz **upsert single-by-instance** (sobrescreve o array inteiro pra ter só 1 entry, mesmo enviando `id` ausente / URL diferente).
- **Único jeito de adicionar 2º+ webhook:** painel admin da instância (`uazapi.dev` → Configurar Webhooks → botão **"Salvar com um novo"**). Lá cada save gera um `id` distinto.

**Implicação prática:** se você for testar a API `POST /webhook` em prod sem cuidado, **vai desativar o webhook ativo do agente** (sintoma: agente para de responder). Sempre ter rollback pronto:
```bash
curl -X GET https://<inst>.uazapi.com/webhook -H "token: $TOKEN" > /tmp/webhook-backup.json
# se sobrescrever, restaurar com POST do entry original
```

### `excludeMessages` flags (CRÍTICO)

| Flag | Efeito |
|---|---|
| `wasSentByApi` | **Não dispara webhook pra mensagens enviadas pela própria API** (suprime echo de `fromMe=true`). Use no webhook do agente IA pra ele não receber as próprias respostas. |
| `isGroupYes` | Suprime mensagens de grupos `@g.us`. Quase sempre desejável. |

**Pro mirror Chatwoot espelhar `outgoing` da IA**, o webhook do mirror precisa **NÃO** ter `wasSentByApi` (caso contrário não recebe `fromMe=true` da resposta da IA, e o admin não vê no Chatwoot o que a IA respondeu). Configure no painel UAZAPI separadamente do webhook principal do agente.

### Payload Webhook Inbound UAZAPI (CRITICO)

**NUNCA assuma formato flat.** UAZAPI envia aninhado:

```json
{
  "chat": {
    "phone": "+55 47 9923-0173",
    "wa_chatid": "554791234567@s.whatsapp.net",
    "name": "Nome do Contato"
  },
  "message": {
    "chatid": "554791234567@s.whatsapp.net",
    "text": "Conteúdo",
    "content": "Conteúdo",
    "fromMe": false,
    "messageType": "Conversation",
    "messageid": "2A25C97D16C0C0D29B5F",
    "mediaType": "", "mediaUrl": "", "caption": ""
  }
}
```

### Extrair dados do payload UAZAPI

```js
var msg = body.message || {};
var chat = body.chat || {};
var rawPhone = msg.chatid ? msg.chatid.replace(/@.*$/, '') : (chat.phone || '');
var phone = rawPhone.replace(/\D/g, '');
var texto = msg.text || msg.content || '';
var fromMe = msg.fromMe === true;
var messageId = msg.messageid || '';
var msgType = (msg.messageType || '').toLowerCase();
```

### Normalizar tipos de mensagem UAZAPI

| messageType | Tipo interno | Tratamento |
|---|---|---|
| `text`, `conversation` | texto | Direto pro agente |
| `audioMessage`, `audio` | audio | Transcrever |
| `imageMessage`, `image` | imagem | Vision ou auto-reply |
| `stickerMessage`, `sticker` | imagem | Download UAZAPI + processar |
| `reactionMessage` | texto | `[Cliente reagiu com {emoji}]` |
| `videoMessage` | texto | `[Video enviado pelo cliente]` |
| `documentMessage` | texto | `[Documento: {nome}]` |
| `locationMessage` | texto | `[Localizacao compartilhada]` |

### Reply/Quote context

```js
if (msg.quoted && typeof msg.quoted === 'object' && msg.quoted.text) {
  var quotedText = msg.quoted.text.substring(0, 200);
  conteudo = '[Respondendo a: "' + quotedText + '"]\n' + conteudo;
}
```

---

## Out-of-Band Uptime Watcher (REGRA DURA)

**Princípio:** o canal de notificação de "X caiu" NUNCA pode ser o próprio X. Watcher de UAZAPI de cliente vai em **n8n + UAZAPI de OUTRO tenant** (tipicamente o n8n da Sua Empresa com instância UAZAPI da própria Sua Empresa). Notificação out-of-band.

**Anti-pattern (real, cometido na Cliente A até 2026-05-28):** schedule trigger no mesmo n8n do cliente → `GET suaempresa.uazapi.com/instance/status` (UAZAPI do cliente) → IF disconnected → `POST suaempresa.uazapi.com/send/text` (mesma UAZAPI caída). Dependência circular: quando UAZAPI cai, `/send/text` também cai. Zero alerta.

### Topologia

```
n8n Sua Empresa  ── Schedule 5min ──┐
(infra externa)                  ↓
                  GET <cliente>.uazapi.com/instance/status
                                 ↓ (probe usa token DO CLIENTE)
                        ┌────────┴────────┐
                     connected      ≠ connected
                                 ↓
                  Postgres Sua Empresa: read last_state
                                 ↓
                       Decide: queda / lembrete / recovery / probe_falha
                                 ↓ fan-out paralelo 3 canais
                ┌────────────────┼────────────────┐
                ↓                ↓                ↓
        WhatsApp                Email           Push
        (UAZAPI Sua Empresa)       (Resend)        (ntfy.sh)
                                 ↓
                        Postgres Sua Empresa: log execution
```

### State machine + dedup (Postgres, não Redis)

Tabela `alertas_uazapi` em Postgres centraliza estado. Função `ultimo_estado_alerta(cliente)` retorna o último registro. State machine no Code node "Decide Action":

| last_status | current_status | age_min | evento | shouldFanout |
|---|---|---|---|---|
| `null` | `connected` | — | `baseline` | false (1ª vez já online) |
| `null` | `disconnected` | — | `queda` | true (1ª vez já offline — alerta imediato) |
| `connected` | `connected` | — | `baseline` | false (sem mudança) |
| `connected` | `disconnected` | — | `queda` | true (transição) |
| `disconnected` | `disconnected` | <30 | `lembrete` | false (dedup) |
| `disconnected` | `disconnected` | ≥30 | `lembrete` | true (re-alerta a cada 30min) |
| qualquer | `connected` (vindo de !connected) | — | `recovery` | true |
| probe HTTP 5xx/timeout | — | — | `probe_falha` | true (dedup 30min igual) |

Dedup em Postgres (lookup do último row) é mais simples e visível que Redis TTL pra esse caso — também sobrevive a restart do n8n.

### Channel fan-out com `neverError: true` + collector

Cada canal HTTP tem `neverError: true` pra que falha em um não mate os outros. Node collector após o Merge agrega quais canais deram 2xx vs falha, grava em `canais_ok[]` / `canais_falha[]` no log:

```js
function ok(resp) { return resp && resp.statusCode >= 200 && resp.statusCode < 300; }
var canais_ok = [];
var canais_falha = [];
if (ok(wa)) canais_ok.push('whatsapp'); else canais_falha.push('whatsapp');
if (ok(em)) canais_ok.push('email');    else canais_falha.push('email');
if (ok(pu)) canais_ok.push('push');     else canais_falha.push('push');
```

### Tripla redundância obrigatória

Sempre 3 canais (não 1, não 2). Razões reais por que cada um pode falhar isoladamente:

| Canal | Falha típica |
|---|---|
| WhatsApp (UAZAPI Sua Empresa) | Mesma host do cliente cair junto (multi-tenant `suaempresa.uazapi.com`); número Business novo sem warmup; destinatário com WhatsApp off |
| Email (Resend/SES) | DNS bloqueando, spam folder, MX problem |
| Push (ntfy.sh) | App push desinstalado, token de subscriber expirado |

Pelo menos 1 dos 3 chega em ~100% dos cenários reais.

### Gotcha: ntfy.sh Title header não aceita Unicode

`Title:` header é RFC-7230 (ASCII strict). Mandar emoji direto:
```
Title: ⚠️ UAZAPI CLIENTE A desconectada
```
retorna `Invalid character in header content ["title"]`. Mover emoji pro **body** (que é UTF-8 livre) ou strip-and-encode na expressão:
```
Title: UAZAPI CLIENTE A desconectada    ← ASCII puro no header
body:  ⚠️ Detalhes aqui...           ← emoji vai no body
```

Tags do ntfy (`Tags: warning,rotating_light`) podem usar nomes de emoji curtos — renderiza no app.

### Tabela schema (referência)

```sql
CREATE TABLE alertas_uazapi (
  id BIGSERIAL PRIMARY KEY,
  cliente         TEXT NOT NULL,
  uazapi_url      TEXT NOT NULL,
  status_atual    TEXT NOT NULL,
  status_anterior TEXT,
  evento          TEXT NOT NULL CHECK (evento IN ('baseline','queda','lembrete','recovery','probe_falha')),
  disparado_em    TIMESTAMPTZ NOT NULL DEFAULT now(),
  canais_ok       TEXT[] NOT NULL DEFAULT '{}',
  canais_falha    TEXT[] NOT NULL DEFAULT '{}',
  detalhes        JSONB NOT NULL DEFAULT '{}'
);
CREATE INDEX idx_alertas_uazapi_cliente_recente ON alertas_uazapi(cliente, disparado_em DESC);
```

Função wrapper pra usar com o pattern de `WITH ult AS (...)` (ver PostgreSQL Pitfalls "0 rows breaks downstream"):
```sql
CREATE OR REPLACE FUNCTION ultimo_estado_alerta(p_cliente TEXT)
RETURNS TABLE (status_atual TEXT, evento TEXT, disparado_em TIMESTAMPTZ)
LANGUAGE sql STABLE AS $$
  SELECT status_atual, evento, disparado_em
  FROM alertas_uazapi WHERE cliente = p_cliente
  ORDER BY disparado_em DESC LIMIT 1;
$$;
```

---

## NotificaMe (WhatsApp — Client-Facing)

```
Base: https://api.notificame.com.br/v1/channels/whatsapp
Header: X-Api-Token: <api-token>

POST /messages — enviar mensagem/template
```

### Payload de envio

```js
{
  from: channelId,     // ID do canal NotificaMe
  to: telefone,        // formato: 5547999001122
  contents: [{ type: "text", text: "mensagem" }]
}
```

### Integração com N8N

O N8N recebe leads via webhook, envia templates via NotificaMe, e NotificaMe faz callback com status:
- **SENT** → mensagem aceita pelo WhatsApp
- **DELIVERED** → entregue no dispositivo
- **READ** → lida pelo cliente
- **FAILED/REJECTED/ERROR** → falhou

### Provider Message ID

NotificaMe retorna um `message_id` no envio. Callbacks de status usam esse ID. Porém, o dispatch_tracking pode ter sido criado com um `message_id` diferente (do N8N). Sempre suporte lookup duplo:

```
1. Busca por message_id
2. Fallback: busca por provider_message_id
```

### Template com header IMAGE — `header_handle` Caveat (CRÍTICO)

Quando você lê templates via `GET /v1/templates/{channel_token}`, templates com header IMAGE retornam:

```json
{
  "name": "esteiras_e_transportadores",
  "components": [
    {
      "type": "HEADER",
      "format": "IMAGE",
      "example": {
        "header_handle": ["https://scontent.whatsapp.net/v/t61.../...png?...&oh=...&oe=..."]
      }
    },
    { "type": "BODY", "text": "..." }
  ]
}
```

**ARMADILHA:** O `header_handle` é uma URL **assinada interna do CDN do Meta**, usada APENAS como exemplo durante review do template. Quando você passa essa URL como `link` no payload de envio:

```json
{
  "type": "image",
  "image": { "link": "https://scontent.whatsapp.net/..." }  // ❌ NÃO refetchável
}
```

NotificaMe **aceita inicialmente** (callback SENT, retorna message_id), mas ~7 segundos depois o callback FAILED chega com `error_message: "Media upload error"`. Meta tenta baixar a imagem do `header_handle` e falha porque a URL é assinada para um contexto específico, não publicamente refetchável.

**SOLUÇÃO: Cachear em storage público próprio**

Arquitetura: download do `header_handle` 1x → re-host em bucket público (ex: Supabase Storage) → cache key com hash do source URL para auto-invalidação:

```typescript
// Helper que resolve URL pública refetchável
async function getCachedTemplateImageUrl(
  supabase: SupabaseClient,
  config: NotificameConfig,
  templateName: string,
): Promise<string | null> {
  // 1. Resolve header_handle via NotificaMe API
  const sourceUrl = await getTemplateHeaderImageUrl(config, templateName);
  if (!sourceUrl) return null;

  // 2. Cache key embute hash do source → auto-invalida quando Meta atualiza
  const sourceHash = createHash("sha1").update(sourceUrl).digest("hex").slice(0, 8);
  const safeName = templateName.replace(/[^a-zA-Z0-9_-]/g, "_");
  const fileNamePrefix = `${safeName}-${sourceHash}`;

  // 3. Cache hit?
  const { data: existing } = await supabase.storage
    .from("whatsapp-template-images")
    .list("", { search: fileNamePrefix, limit: 1 });
  if (existing && existing.length > 0) {
    const cached = existing.find((f) => f.name.startsWith(fileNamePrefix));
    if (cached) {
      return supabase.storage.from(BUCKET).getPublicUrl(cached.name).data.publicUrl;
    }
  }

  // 4. Cache miss → download + upload
  const res = await fetch(sourceUrl);
  const buffer = Buffer.from(await res.arrayBuffer());
  const fileName = `${fileNamePrefix}.png`;
  await supabase.storage
    .from("whatsapp-template-images")
    .upload(fileName, buffer, { contentType: "image/png", upsert: true });

  return supabase.storage.from(BUCKET).getPublicUrl(fileName).data.publicUrl;
}
```

**Bucket setup (Supabase):**
```sql
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('whatsapp-template-images', 'whatsapp-template-images', true, 5242880,
  ARRAY['image/png','image/jpeg','image/webp']::text[])
ON CONFLICT (id) DO NOTHING;
```

**Latência:**
- Cache miss (1ª vez): ~500-1500ms (download + upload)
- Cache hit: ~50-100ms (list + getPublicUrl)
- Self-service: qualquer template novo aprovado funciona sem editar workflow/DB/UI

**Por que hash sufix:** Quando o `header_handle` muda (Meta rotaciona ou template é editado), o hash muda → novo arquivo é criado → URL antiga continua válida (lixo a ser limpado depois) e nova é gerada automaticamente. Sem cache invalidation manual.

---

## Chatwoot (CRM)

```
Base: https://<your-chatwoot-host>
Header: api_access_token: <account-token>
Account: <account-id>

POST /api/v1/accounts/{id}/conversations/{conv_id}/messages
GET  /api/v1/accounts/{id}/contacts/search?q={phone}
POST /api/v1/accounts/{id}/contacts
GET  /api/v1/accounts/{id}/conversations?page={n}
POST /api/v1/accounts/{id}/webhooks
```

### Config (Supabase `integrations` table)

```typescript
interface ChatwootConfig {
  server_url: string   // https://<your-chatwoot-host>
  api_key: string      // api_access_token
  account_id: string   // numeric, as string (ex: "1", "2")
}
```

### Contato: Find or Create

```
1. searchContact(phone) → GET /contacts/search?q=+{digits}   ← '+' prefix OBRIGATÓRIO
2. Se não existe → createContact({ inbox_id, phone_number: "+{digits}", name })
   (POST /contacts com inbox_id já cria a contact_inbox; NÃO chamar POST /contact_inboxes em seguida — duplica)
```

**Gotcha:** `GET /contacts/search?q=554733221100` retorna `payload: []` mesmo com o contato existindo. **Precisa do `+` prefix:** `?q=%2B554733221100`. Sem isso, o pipeline tenta criar de novo e o Chatwoot retorna 422 `["phone_number"]` (already taken). Sintoma de loop de Create Contact após o 1º run.

**Alternativa mais robusta — `/contacts/filter` (match exato):**

```bash
POST /api/v1/accounts/{acct}/contacts/filter?include=contact_inboxes
Content-Type: application/json
{
  "payload": [{
    "attribute_key": "phone_number",
    "filter_operator": "equal_to",
    "values": ["+554733221100"],
    "attribute_model": "standard"
  }]
}
```

Match exato instantâneo, sem depender do índice de search (que pode ter lag após create). Use quando o pipeline puder rodar logo após um create.

⚠️ **Pitfall no n8n HTTP node:** ao usar `/contacts/filter` com `jsonBody: "={{ JSON.stringify({...}) }}"`, o request pode chegar com body vazio/escapado errado no Chatwoot self-hosted (mesmo retornando 200). Sintoma: `payload: []` mesmo com contato existente. Workaround: voltar pra `GET /contacts/search?q=+<digits>` (funciona via `queryParameters`).

### Conversa: Find or Create

```
1. GET conversas do contato → prefere status="open"
2. Se não existe → findWhatsAppInboxId() → POST nova conversa
3. Inbox cache com TTL 5min
```

### Labels — MERGE SEMÂNTICO (crítico)

Chatwoot SUBSTITUI labels no POST (não appenda). Pattern obrigatório:

```typescript
// 1. Buscar labels atuais
const current = await getConversationLabels(config, conversationId);
// 2. Union com novos
const merged = [...new Set([...current, ...newLabels])];
// 3. POST merged
await setConversationLabels(config, conversationId, merged);
```

**Bug real:** Se você fizer POST direto com novos labels, remove todos os existentes.

### Labels do Sistema

| Label | Aplicado quando |
|-------|----------------|
| `prospeccao` | Dispatch SDR |
| `nutricao` | Dispatch nutrição |
| `interagiu` | Cliente responde mensagem |
| `visualizado` | Cliente lê mensagem |
| `pausar_ia` | Transferido para humano |
| `qualificado` | Lead qualificado |
| `transferido` | Transfer executado |

### Messages — Private Flag (previne loop)

```js
// OBRIGATORIO: private: true em mensagens do agente
{
  content: mensagemDoAgente,
  message_type: 'outgoing',
  private: true  // Sem isso, Chatwoot reenvia como webhook → loop infinito
}
```

### Mirror de Dispatch

Quando um dispatch (template) é enviado via N8N — seja por backend intermediário ou pelo próprio workflow:
1. `findOrCreateContact()` no Chatwoot
2. `findOrCreateConversation()`
3. Envia nota privada com info do template
4. Adiciona label (`prospeccao` ou `nutricao`)

### Mirror de OUTGOING (mensagem do agente IA) — CRÍTICO

**NotificaMe channel→Chatwoot integration espelha apenas mensagens INCOMING.** Mensagens enviadas pela API (pelo N8N → NotificaMe) **NÃO** aparecem automaticamente no Chatwoot. Se você quer ver o que o agente IA enviou, precisa postar explicitamente.

**Padrão antigo (insuficiente):** postar uma `nota privada` (`private: true`) com o texto. Funciona mas:
- Texto aparece como nota interna (visual diferente, não parece mensagem)
- Áudios/imagens não aparecem nunca (só o texto da resposta)
- Agentes humanos não conseguem ouvir o áudio que a IA enviou

**Padrão novo (recomendado):** postar como **mensagem outgoing PÚBLICA** com `source_id` único + (se for mídia) anexo via multipart upload.

#### A) Loop guard com `source_id`

Postar `private: false` no Chatwoot dispara webhook `message_created` → seu workflow N8N → `Processar Evento Chatwoot`. Se essa node tem lógica "outgoing + !private → reenviar via WhatsApp" (para manual agent typing), ela cria **loop infinito**: workflow posta → webhook chega → workflow reenvia → repete.

**Solução:** marcar a mensagem com `source_id: "n8n-{tipo}-{messageId}"` e adicionar guard no event handler:

```js
// Processar Evento Chatwoot — adicionar filtro source_id
var sourceId = body.source_id || "";
var isFromN8n = typeof sourceId === "string" && sourceId.indexOf("n8n-") === 0;

if (isOutgoing && !isPrivate && content && inboxId === SEU_INBOX && !isFromN8n) {
  // só reenvia se NÃO for mensagem que nós mesmos postamos
  return [{ json: { action: "send_agent_message", ... } }];
}
```

Chatwoot preserva `source_id` no payload do webhook. Verificado: msg criada via API com `source_id: n8n-test-123` retorna o mesmo source_id no GET e no webhook event.

#### B) Multipart upload de áudio (mensagem pública com anexo)

Para áudio aparecer como mensagem pública com player no Chatwoot, fazer multipart POST:

```bash
POST /api/v1/accounts/{id}/conversations/{conv_id}/messages
Content-Type: multipart/form-data

Fields:
- content: "🎤 [transcrição/legenda]"
- message_type: outgoing
- private: false
- source_id: n8n-audio-{messageId}
- attachments[]: <binário do arquivo>
```

Chatwoot aceita o arquivo, salva no Active Storage, retorna o objeto da mensagem com `attachments[].data_url` apontando para o CDN. O áudio fica reproduzível na UI.

**Topologia N8N completa para audio mirror:**

```
Enviar Audio NotificaMe (existing) → Salvar Resposta IA (existing)
                                   → Chatwoot - Busca Contato → Busca Conversa → Nota Privada (existing, mantém)
                                   → [NEW] Download Audio Bin (HTTP GET responseFormat:file) → [NEW] Chatwoot Audio Público (multipart POST)
```

Os 3 ramos paralelos da `Enviar Audio NotificaMe` rodam independente. O download usa `Upload Audio Supabase.first().json.Key` para construir a URL pública. O multipart POST referencia `Chatwoot - Busca Conversa.first().json.payload.sort((a,b) => b.id - a.id)[0].id` para o conv id.

### Coexistence: templates não aparecem no app WhatsApp Business

**Confirmado por docs Meta + Respond.io:** templates enviados via Cloud API (NotificaMe → Meta → WhatsApp) **NÃO sincronizam para o histórico do app WhatsApp Business**, mesmo com coexistence ativo. É by design — templates só podem ser disparados pela API, não pelo app.

**Implicação:** se um agente humano usa o app WhatsApp Business e quer ver os templates que a IA disparou, ele PRECISA olhar no Chatwoot (ou outro CRM espelho), nunca no app. Isso reforça a necessidade do "Mirror de OUTGOING" acima.

### Transfer para Humano

```
1. Detecta transferência (tag [TRANSFERIR_PARA_HUMANO], JSON, frases confirmativas)
2. applyTransferLabels() → ["pausar_ia", "qualificado", "transferido"]
3. Envia resumo do lead como nota privada (só agentes veem)
4. Redis: SET PAUSA_{AGENTE}_{phone} TTL 3600
```

**Frases que NÃO disparam:** "Posso transferir", "transferir para" (genérico)
**Frases que DISPARAM:** "vou te conectar", "vou te transferir", "estou transferindo"

### Webhook Registration

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "api_access_token: {TOKEN}" \
  "https://<your-chatwoot-host>/api/v1/accounts/<account_id>/webhooks" \
  -d '{"url": "https://app.example.com/api/chatwoot-webhook?token={SECRET}",
       "subscriptions": ["message_created","conversation_created","conversation_updated","conversation_status_changed"]}'
```

**Nota:** `assignee_changed` NÃO é evento válido no Chatwoot. Transferências vêm via `conversation_updated`.

### Webhook Auth no App

Chatwoot não envia custom headers → usar query param `?token={SECRET}`:

```typescript
validateWebhookSecretOrQuery(headers, url, envVar)
// 1. Tenta header x-webhook-secret / Authorization Bearer
// 2. Fallback: query param ?token=
// 3. Comparação timing-safe (crypto.timingSafeEqual)
```

Rota do webhook faz fallback duplo:
```
1. Tenta CHATWOOT_WEBHOOK_SECRET
2. Se falha, tenta WEBHOOK_SECRET
3. Se ambos falham → 401
```

### getChatwootActivityToday (Daily Summary)

Pagina conversations (25/página, max 10 páginas), filtra `last_activity_at >= startOfDay`. Retorna `{ nome, telefone, messageCount, lastActivity }`.

**Caveat:** `messageCount` é lifetime, não só hoje (trade-off performance).

### Caching

```typescript
inboxCache: { id, expiresAt }  // TTL 5min
agentCache: { agents, expiresAt }  // TTL 5min
```

### Timeout

Todos os fetch Chatwoot: `AbortController` + `setTimeout(FETCH_TIMEOUT_MS)` (default 5000ms).

---

## Pipedrive Integration

### API basics

```
Base:    https://<your-company>.pipedrive.com/api/v1
Auth:    ?api_token=<token> (query param) OU Authorization: Bearer (OAuth)
Pipeline: identificado por numeric ID, NÃO por nome
```

### Discover IDs antes de hardcode (CRÍTICO)

**SINTOMA:** tool ou workflow tem `STAGE_NAMES = { 79: 'Qualificação', 80: 'Distribuição' }` hardcoded, mas o stage real do deal não aparece corretamente no resumo (vira "Stage 81" sem nome).

**ROOT CAUSE:** o pipeline tem mais stages do que os 2-3 documentados na tool. Stages novos foram adicionados via UI Pipedrive mas o mapping no código não foi atualizado.

**Pattern:** antes de hardcodear, descobrir stages reais via API:

```bash
TOKEN="$(grep ^PIPEDRIVE_API_TOKEN .env.local | cut -d= -f2- | tr -d '"')"
PIPELINE_ID="$(grep ^PIPEDRIVE_PIPELINE_ID .env.local | cut -d= -f2- | tr -d '"')"
curl -s "https://<your-company>.pipedrive.com/api/v1/stages?pipeline_id=${PIPELINE_ID}&api_token=${TOKEN}" \
  | jq -r '.data[] | "  " + (.id|tostring) + ": \"" + .name + "\","'
```

Output direto pra copy-paste no `STAGE_NAMES`:
```
  72: "Novo Lead",
  73: "Sem Contato",
  79: "Qualificação",
  80: "Distribuição",
  ...
```

**Alternativa cacheada:** se o pipeline muda, considere fetchar stages dinamicamente uma vez por execução do workflow e cachear em static data — mas pra workflows de baixa frequência (cron diário), hardcode mapped + redocumentar quando mudar é mais simples.

### Pipelines: NÃO use o nome

`pipeline_id` é numérico e estável. **Não tente buscar por nome** (`pipeline=My Pipeline`) — a API não suporta isso de forma confiável. Sempre passe o ID:

```bash
# Listar todos os pipelines pra descobrir o ID
curl -s "https://<your-company>.pipedrive.com/api/v1/pipelines?api_token=${TOKEN}" | jq '.data[] | {id, name}'
```

Salvar `PIPEDRIVE_PIPELINE_ID=<n>` em `.env.local` por projeto.

### `GET /deals/{id}` response shape

```json
{
  "success": true,
  "data": {
    "id": 4521,
    "title": "...",
    "stage_id": 80,
    "value": 8000000,
    "currency": "BRL",
    "status": "open",       // open | won | lost | deleted
    "user_id": { "id": 12, "name": "Silvio Telles", "email": "..." },
    "owner_name": "Silvio Telles",   // expandido em alguns casos
    "person_id": { "name": "...", "phone": [...] }
  }
}
```

Owner pode vir como `data.owner_name` (string) OU `data.user_id.name` (object). Resolva com fallback:

```javascript
var ownerName = null;
if (deal.owner_name) ownerName = deal.owner_name;
else if (deal.user_id && deal.user_id.name) ownerName = deal.user_id.name;
```

### Custom fields (Deal e Person)

Pipedrive expõe custom fields como HASHES (não nomes) na response. Pra mapear, fetch `GET /dealFields` ou `GET /personFields` uma vez e salve o mapping. Hash é estável por organização — não muda.

### Rate limits

Pipedrive permite ~80 req/s no plano padrão. Pra workflows que iteram deals (ex.: enriquecer N qualifs no resumo diário), use `Split In Batches (size=1)` com pequena espera se N > 50. Pra N < 20, sem preocupação.

### Stages won/lost

Verifique `deal.status` antes de mostrar stage:
```javascript
if (deal.status === 'won')  show '🏆 GANHO'
if (deal.status === 'lost') show '❌ PERDIDO'
// status 'deleted' não retorna no GET (404)
```

---

## Dispatch Pipeline (Fluxo Completo)

> **Nota:** este pipeline assume um **backend intermediário** (ex.: app Next.js) que gerencia `dispatch_tracking` e callbacks. Em projetos **n8n self-contained**, toda essa lógica pode viver dentro do próprio workflow (Postgres node + Tool do AI Agent disparando UAZAPI/NotificaMe direto). Confirme a arquitetura do projeto atual antes de assumir esta topologia.

### Arquitetura (variante com backend)

```
Dispatch backend (ex: rota /bulk-sdr)
  → POST N8N webhook (por lead)
    → N8N envia template via NotificaMe
      → NotificaMe callback: dispatch_sent (com message_id)
        → backend salva em dispatch_tracking
          → Mirror para Chatwoot (fire-and-forget)
      → NotificaMe status callbacks: SENT, DELIVERED, READ, FAILED
        → backend atualiza dispatch_tracking
          → Auto-avança client pipeline
```

### 1. Dispatch (bulk-sdr route)

```typescript
// Input
{ leads: [{ id, nome, telefone, empresa, cargo }], mode: "sdr"|"nutricao", templateId?, template_name? }

// Server-side dedup
Se template_name informado → verifica dispatch_tracking existente com sent_at + !failed_at → skip

// Retry
MAX_RETRIES = 2 (3 tentativas total)
RETRYABLE_STATUSES = [408, 429, 500, 502, 503, 504]
Backoff: BATCH_DELAY_MS * (attempt + 1) * 2

// Tracking síncrono (CRÍTICO)
Insere dispatch_tracking ANTES de retornar response
→ Deve completar antes do callback SENT (~1-2s)
```

### 2. Dispatch Sent Callback (whatsapp-webhook)

```typescript
// Atomic upsert
1. UPDATE dispatch_tracking SET message_id WHERE telefone = X AND message_id IS NULL (ORDER BY created_at DESC LIMIT 1)
2. Se nenhum atualizado → INSERT novo registro
3. Ignore erro 23505 (unique constraint = idempotente)
```

### 3. Status Update Callbacks

```
SENT      → sent_at = timestamp
DELIVERED → delivered_at = timestamp
READ      → read_at = timestamp → avança para "visualizado" + label Chatwoot
FAILED    → failed_at = timestamp + error_message
REJECTED  → same as FAILED
ERROR     → same as FAILED
```

**Lookup duplo:** Tenta `message_id` primeiro, fallback `provider_message_id`.

### 4. Message Received (cliente respondeu)

```
1. Busca dispatch mais recente para o telefone → marca replied_at
2. Infere delivered_at e read_at = now (não responde sem ler)
3. Avança para "interagiu"
4. NÃO espelha para Chatwoot (NotificaMe já faz via integração canal)
```

### Zod Schemas

```typescript
statusUpdateSchema:  { type, message_id, provider_message_id?, status, timestamp?, error_message? }
messageReceivedSchema: { type, telefone, nome?, empresa?, message_text? }
dispatchSentSchema:  { type, message_id, lead_id?, telefone, template_name?, mode?, is_customer? }
```

---

## Client Pipeline

### Stage Hierarchy (só avança, nunca retroage)

```
cadastrado < contatado < visualizado < interagiu < qualificado < transferido
```

### advanceClientStage(leadId, targetStage)

```
1. Busca lead → valida is_customer === true
2. Compara ordem: current vs target
3. Só avança se target > current (ignora silenciosamente se igual ou menor)
4. Update: client_stage_id + updated_at
5. Se stage é "qualificado" ou "transferido" → sendPipelineAlert()
```

### advanceClientByPhone(phone, targetStage)

```
1. Query leads WHERE is_customer = true
2. matchLeadByPhone() (normaliza e compara variantes)
3. Chama advanceClientStage()
```

### Auto-avanço por evento

| Evento | Target Stage |
|--------|-------------|
| dispatch_sent SENT/DELIVERED | contatado |
| status_update READ | visualizado |
| message_received (reply) | interagiu |
| Chatwoot assignee change | transferido |

### Pipeline Alert

Disparado em `qualificado` e `transferido`:
- Monta resumo do lead (dados + notes + dispatches + intenção detectada)
- Envia via UAZAPI para phones de alerta
- Fire-and-forget (`.catch()` silencioso)

### Keyword-based Intent Detection

```
"interesse/quero/gostaria" → "Demonstrou interesse"
"preço/valor/custo/orçamento" → "Perguntou sobre preço"
"reunião/agendar/conversar" → "Quer agendar reunião"
"não + interesse/momento" → "Sem interesse no momento"
```

---

## Daily Summary

Duas variantes possíveis — verifique qual o projeto atual usa antes de descrever o fluxo.

### Variante A — Backend gera o resumo

```
Endpoint: POST /api/cron/daily-summary
Auth:     CRON_SECRET (Vercel) ou WEBHOOK_SECRET (N8N)
```

```
Schedule N8N (cron BRT)
  → POST /api/cron/daily-summary (backend agrega dados, retorna messageText)
    → Code node formata para UAZAPI (1 item por número destino)
      → POST <your-instance>.uazapi.com/send/text
```

### Variante B — N8N self-contained

```
Schedule N8N (cron BRT)
  → Postgres node: query agregando tabelas do projeto
  → Code node formata texto do resumo
  → HTTP POST <your-instance>.uazapi.com/send/text → número(s) de alerta
  → (opcional) Postgres node: INSERT em tabela de auditoria
```

Nesse caso não há backend chamado — todo o resumo vive dentro do workflow.

**Cron offset:** se houver outro cron disparando no mesmo horário (ex.: Follow-Up), use offset de minutos (`:05` vs `:00`) pra evitar contention.

### 4 Seções do Resumo

1. **📨 Disparos de Hoje** — total, enviados, entregues, lidos, respondidos, falharam + taxas (%)
2. **📬 Templates Anteriores — Atividade Hoje** — dispatches antigos com read/reply/delivered hoje + lista de quem interagiu
3. **💬 Interações do Dia** — merge lead_notes + Chatwoot API, dedup por telefone, top 15 clientes
4. **📈 Movimentações do Pipeline** — novos leads + contagem por stage + lista de transferidos/qualificados

### Timezone (CRÍTICO)

```typescript
// Brasília UTC-3
const brasiliaOffset = -3 * 60;
const brasiliaTime = new Date(now.getTime() + (brasiliaOffset + now.getTimezoneOffset()) * 60000);
const startOfDay = new Date(
  Date.UTC(brasiliaTime.getFullYear(), brasiliaTime.getMonth(), brasiliaTime.getDate()) - brasiliaOffset * 60000,
).toISOString();
```

### Merge de Interações (Dedup)

```
1. Query lead_notes (type = "whatsapp", created_at >= startOfDay)
2. Query Chatwoot API (getChatwootActivityToday)
3. Merge by telefone (lead_notes tem prioridade)
4. Sort by messageCount DESC
```

### Chatwoot opcional

Se Chatwoot não configurado → continua só com lead_notes (try/catch silencioso).

---

## Follow-Up Automático

### Regras

- **Alvo:** Clientes em stage `"interagiu"` com `updated_at < 2h atrás`
- **Idempotência:** Verifica se já existe dispatch `mode: "followup"` após `client.updated_at`
- **Business hours:** Seg-Sex, 8h-18h BRT apenas
- **Frequência:** 1x por período de silêncio
- **Envio:** Via N8N webhook com `mode: "followup"` → NotificaMe

### Cron

N8N: `*/30 11-21 * * 1-5` (cada 30min, seg-sex, 8h-18h BRT)
Vercel: backup (menos frequente)

### Cadência multi-touchpoint (24/48/72h) SEM CRM — âncora própria

Um agente com CRM (ex. Cliente A) acopla a cadência aos **stages do Pipedrive** (75→76→77→78 = máquina de estados). Quando o agente NÃO tem CRM (ex.: <agente>, que só tem `<agente>_messages`), ancore numa **tabela de estado própria** (`<agente>_leads`) que depois vira a ponte p/ o CRM futuro (Kommo etc.):

- **Âncora = `last_inbound_at`** (última msg do PACIENTE). Silêncio = `now - last_inbound_at`. Thresholds crescentes de uma âncora ÚNICA: TP1≥24h, TP2≥48h, TP3≥72h (NÃO gaps cumulativos).
- **Elegível** só quem tem `status='ativo'` E `last_outbound_at >= last_inbound_at` (o agente respondeu por último; o paciente que sumiu — senão você cobra quem ESTÁ esperando resposta).
- **Idempotência por rodada de silêncio:** tabela `<agente>_followup_log(phone, touchpoint, status, content, anchor_at)`. Conta follows com `created_at >= last_inbound_at` (a âncora atual). Quando o paciente responde, a âncora avança → a cadência reinicia limpa, sem apagar nada. `next_tp = sent_na_rodada + 1`; para após TP3 (`status='encerrado'`).
- **NÃO logar o follow enviado no histórico como `inbound`** — só `last_inbound_at` é a âncora. Pode espelhar como `assistant` p/ memória sem afetar a âncora.
- **Sinal de saída do funil:** no ramo de transferência do workflow principal, gravar `status='transferido'` na tabela de estado — senão o cron manda "você sumiu" pra quem já foi pra recepção (gera nova reclamação).
- **Go-live seguro:** backfill marca os leads pré-existentes como `encerrado` (baseline), sem disparo retroativo; o UPSERT inbound reativa pra `ativo` quando o paciente voltar a falar.
- **A query de candidatos pode calcular tudo** (silêncio, sent_count, next_tp, histórico recente via `string_agg`) num SELECT só com subqueries LATERAL — evita o merge-após-Postgres-node que perde o contexto do lead.

---

## QA de Agente IA via Injeção de Webhook (testar bugs do agente automaticamente)

Para verificar se o agente reproduz um bug reportado (alucina catálogo, confirma horário indevidamente, repete saudação) **sem depender de alguém digitar no WhatsApp** e **sem enviar mensagem a ninguém real**:

1. **Injete o payload no webhook** com o MESMO formato que o provider manda (extraia um payload real de uma execução: `runData["Webhook"][0].data.main[0][0].json.body` → template; troque `message.text`/`content`, `message.chatid`, `chat.phone`, `messageid`, `pushName`).
2. **Use números INVÁLIDOS como remetente** (DDD `00`, ex.: `5500000000001`): o agente processa e tenta responder, mas o `/send` falha (número inexistente) → **não atinge ninguém**. O Guard/agente já rodou; é só inspecionar.
3. **Inspecione** `GET /executions?includeData=true`: extraia as `flags` do node Guard e o array de `messages` da resposta. A execução real (com debounce) dura segundos — filtre por DURAÇÃO (a que passou pelo agente) ou pelo node Guard ter executado, não por `finished` (pode estar `error` por causa do send que falhou).
4. **Cuidado com race + memoryBufferWindow:** para testar continuidade/saudação, espace as mensagens MAIS que o tempo de processamento (debounce 8s + agente ~10s = ~18s; injetar a 11s gera race onde o turn N lê estado do turn N-1 antes dele persistir). E o bug de "re-saudação no meio da conversa" só aparece DEPOIS de passar do `contextWindowLength` do buffer (>8 turnos) — teste com conversa LONGA, não 2 turnos.
5. **Limpe os leads/mensagens de teste** depois (`DELETE WHERE phone LIKE '<prefixo de teste>%'`) — a injeção popula `<agente>_leads`/`_messages`.

### Continuidade/saudação: derive de fonte PERSISTENTE, nunca de `staticData` volátil

Bug clássico (<agente>, imgs do cliente "re-saúda como se zerasse a janela"): o flag "já cumprimentei" (`saudacao_enviada`) vinha do `convState` em `$getWorkflowStaticData` (volátil — sofre race entre turnos rápidos E some em restart do n8n) + o "Resumir Histórico (OpenAI)" retornava `SEM_HISTORICO` mesmo havendo mensagens. Resultado: o agente "esquece" que já falou e se reapresenta no meio da conversa.

**FIX:** dar ao agente um sinal de continuidade **determinístico** lido do **histórico persistente** (a tabela `<agente>_messages` via o node "Memória Antiga"): no node que monta a entrada, `var histCount = $('Memória Antiga').all().length; var jaConversou = histCount > 1;` e injete no prompt uma linha que força "se há histórico → é PROIBIDO se reapresentar". Não confie só no buffer de N turnos (some após N) nem no staticData (volátil). `lia_messages` grava cedo e sobrevive a restart, então `histCount` é a fonte robusta.

⚠️ **`> 1`, NÃO `> 0` (bug real, <agente> 2026-06-06):** se o node "Log Entrada" (INSERT da msg atual em `<agente>_messages`) roda ANTES do "Memória Antiga" (`Log Entrada → Memória Antiga`), o `histCount` JÁ inclui o turno atual. Com `> 0` o `jaConversou` fica SEMPRE true → o agente **nunca se apresenta, nem ao paciente novo** (1ª msg → histCount=1). Use `> 1` (existe histórico ALÉM do turno atual) — ou leia Memória Antiga ANTES do Log Entrada. O mesmo +1 contamina o gate de qualquer prepend "[conversa já em andamento]".

⚠️ **Cuidado com sinal volátil EAGER paralelo:** se houver um `greetingDerived`/`saudacao_enviada` derivado do `convState` que liga "sim" quando a msg ATUAL gera facts/stage/intent (`factsKeys>0 || stage!=='inicio' || intent!=='outro'`), ele trava a apresentação do 1º contato sozinho — esses termos vêm da classificação do turno corrente (eager). Use só sinais de turnos ANTERIORES (`greeting_sent`, `last_bot.length>0`) + o `jaConversou` persistente.

⚠️ **Guard que strippa saudação NÃO pode strippar IDENTIDADE:** se o Guard tem `stripGreeting` que em turno ≥2 remove frases de saudação, garanta que o `isGreetingSentence` NÃO case "sou a <nome>"/"me chamo <nome>" — senão a resposta de identidade ("Sou a <agente>, da equipe da Dra. <nome>") é mutilada (o split por `.` quebra no "Dra." e sobra "<nome> 😊", parecendo que o bot É a médica). Identidade ≠ saudação.

**`#RESET` virar "simular paciente novo" (não só "limpar contexto"):** zerar sessionId/buffer NÃO basta — "Memória Antiga" lê por phone e ignora o reset. Filtrar a query: `... AND created_at > to_timestamp($2::double precision / 1000.0) ...` com `queryReplacement` ARRAY `[phone, resetTimestamp]`; expor o `resetTimestamp` (do `$getWorkflowStaticData['reset_'+phone]`) no node que alimenta a query; e no "Executar Reset" limpar as chaves por-phone NÃO-sessionId (`stage_/sentiment_/obj_<phone>`), senão `currentStage = classification.stage || prevStage` herda estado velho. Filtrar a Memória Antiga (chokepoint) torna histCount E o resumo reset-aware de uma vez. (Reset persiste no staticData mesmo em queue mode.)

---

## Keep-Alive (Meta 24h Window)

```typescript
// N mensagens casuais predefinidas, random selection
// Adapte voz/persona ao agente do projeto.
const messages = [
  "Oi! Aqui é o <agente> da <empresa>. Alguma novidade sobre <tópico>?",
  "E aí, tudo bem? <agente> aqui da <empresa>. Precisa de algo em <área>?",
  // ...
];
```

Acionado em horários estratégicos (ex.: 8h e 18h BRT). Propósito: manter janela gratuita Meta WhatsApp (24h) ativa enquanto não há interação orgânica.

---

## ElevenLabs (TTS)

```
POST https://api.elevenlabs.io/v1/text-to-speech/{voiceId}
Header: xi-api-key: <key>
Body: { text, model_id, voice_settings }
```

### Preparar texto para TTS

- Remover URLs, emojis, asteriscos (markdown bold), `[TRANSFERIR_PARA_HUMANO]`
- Remover tags HTML/SSML, risadas (haha, kkk, rsrs)
- Humanizar: "voce" → "ce", "para" → "pra", "estou" → "to"

### Lógica de quando responder em áudio

1. Cliente mandou áudio → responde com áudio
2. Cliente pediu áudio via regex → responde com áudio
3. A cada 3 interações de texto → counter via `$getWorkflowStaticData('global')`

### Cadeia TTS

```
Responder em Áudio? → Preparar TTS (limpa texto) → ElevenLabs TTS
  → Verificar TTS (checa mimeType=audio/mpeg, senão PARA)
    → Extrair Base64 → Enviar Áudio WhatsApp (NotificaMe)
```

**Armadilha:** Se ElevenLabs retorna JSON (erro billing) em vez de audio/mpeg, o nó "Verificar TTS" deve parar a cadeia (senão envia "áudio" inválido).

### Voice IDs

Cada projeto tem sua própria voz cadastrada no ElevenLabs. Estrutura:

| Campo | Onde encontrar |
|---|---|
| Voice ID | ElevenLabs dashboard → Voice Library → copy ID |
| Model | `eleven_multilingual_v2` (estável, multi-idioma) ou `eleven_v3` (mais expressivo) |

Salve o Voice ID em env var do n8n (ex: `ELEVENLABS_VOICE_ID`) — não hard-code no workflow.

---

## Redis (Pausa IA + Debounce)

### Pausa IA

```
Key: PAUSA_{AGENTE}_{phone}
Value: "1"
TTL: 3600 (1h default)
```

Verificar no início do fluxo. Se key existe → não processa (humano assumiu).

### Debounce + Concatenação

```js
// Save
staticData['debounce_' + phone] = messageId;
var msgs = staticData['concat_' + phone] ? JSON.parse(staticData['concat_' + phone]) : [];
msgs.push(data.message);
if (msgs.length > 5) msgs.shift();
staticData['concat_' + phone] = JSON.stringify(msgs);

// Wait 2-4s, then Verify
if (staticData['debounce_' + phone] !== messageId) {
  return [{ json: { isValidMessage: false, reason: 'debounce' } }];
}
var combined = JSON.parse(staticData['concat_' + phone] || '[]').join(' ').trim();
delete staticData['concat_' + phone];
```

---

## Anti-Loop Detector (Spiral de Agradecimento)

**Cenário:** o cliente do outro lado pode ser outro bot/IA comercial ou um agente humano usando script. Eles entram em ciclo de "obrigado / por nada / fico à disposição / valeu", e o seu agente IA responde indefinidamente — queimando janela do WhatsApp e gerando interações inúteis.

### Defesa em camadas

**Camada 1 (prompt):** instruir o agente IA a não repetir agradecimentos. Adicionar seção `<anti_loop_agradecimento>` no system prompt:

```
REGRA DURA:
- Se sua última resposta foi cordialidade vazia E o lead respondeu com OUTRA cordialidade,
  NÃO responda com mais um "obrigado". Em vez disso:
    a) Avance com algo concreto (pergunta, agendamento, próximo passo), OU
    b) Encerre com UMA frase final tipo "Por nada, fico por aqui — quando precisar
       de algo concreto, é só me chamar. Abraço!" e NÃO responda mais.

LIMITE NUMÉRICO: nunca mais que 2 mensagens consecutivas que sejam apenas
agradecimento. Na 3ª, ou avança ou encerra — nunca mais um "obrigado" puro.
```

Não confiável sozinho — LLMs derrapam em conversas longas.

**Camada 2 (workflow):** Code node de detecção + IF + Redis pause (hard limit).

### Topologia

```
Resposta → [NEW] Loop Detector → [NEW] Loop Goodbye? IF
                                  → true (count >= 3) → Redis Set Pausa Loop (TTL 7d) → Check Transferencia
                                  → false → Check Transferencia
```

`Check Transferencia` recebe de ambos os branches. O fluxo segue normal — quando count atinge o limite, a node detector REPLACE a resposta com mensagem de despedida E ativa Redis pause antes de enviar.

### Loop Detector (Code node)

```js
// Detect thanks-spiral and replace response with goodbye + activate Redis pause.
// Counter persisted in workflow staticData (per phone).
var input = $input.first().json || {};
var staticData;
try { staticData = $getWorkflowStaticData("global"); } catch (e) { staticData = {}; }

var phone = "";
try { phone = $("Normaliza").first().json.lead.numero || ""; } catch (e) { phone = ""; }

// Extract response array (handle multiple formats)
function extractRespostaArray(item) {
  if (!item) return [];
  if (Array.isArray(item.resposta)) return item.resposta;
  if (typeof item.resposta === "string") return [item.resposta];
  return [];
}
var arr = extractRespostaArray(input);
var combined = arr.join(" ").toLowerCase().trim();

// Patterns for "thanks-only" responses (PT-BR; adapt for your language)
var thanksRegex = /^(\s*[\.,!]*\s*)*(obrigad|valeu|sem problema|conte comigo|fico (a|à) disposi|estou (a|à) disposi|por nada|de nada|imagina|tamb(é|e)m agrade|agrade(c|ç)o|tudo certo|combinado|fico no aguardo|igualmente|abra(c|ç)o)/i;
var isThanks = combined.length > 0 && combined.length < 280 && thanksRegex.test(combined);

var key = "thanksLoop_" + phone;
var count = staticData[key] || 0;
var loopGoodbye = false;

if (isThanks) {
  count = count + 1;
  staticData[key] = count;
  if (count >= 3) {
    loopGoodbye = true;
    staticData[key] = 0;  // reset after triggering
  }
} else {
  // Reset on any non-thanks response
  staticData[key] = 0;
}

if (loopGoodbye) {
  var goodbye = "Por nada, sempre à disposição! Vou ficar por aqui — quando tiver alguma demanda concreta, é só me chamar. Abraço! 🤝";
  input.resposta = [goodbye];
  input.output = goodbye;
}

input.loopGoodbye = loopGoodbye;
input.thanksCount = staticData[key] || 0;
return [{ json: input }];
```

### IF + Redis pause

```js
// Loop Goodbye? (IF node)
{ leftValue: "={{ $json.loopGoodbye }}", rightValue: true, operator: { type: 'boolean', operation: 'equals' } }
```

```js
// Redis Set Pausa Loop (Redis node)
{
  operation: 'set',
  key: '=PAUSA_{{ $("Normaliza").first().json.lead.numero }}',
  value: 'true',
  keyType: 'string',
  expire: true,
  ttl: 604800,  // 7 days
}
```

### Comportamento

| Evento | Ação |
|---|---|
| 1ª resposta com thanks-only | passa normal (count=1) |
| 2ª thanks-only consecutiva | passa normal (count=2) |
| 3ª thanks-only consecutiva | resposta substituída por goodbye, Redis pause 7d ativado, mensagem enviada normal, depois silêncio total |
| Qualquer non-thanks | counter reseta |

**Por que count=3 dispara goodbye:** o usuário quer "máximo 2 agradecimentos". A 3ª seria a "uma a mais" — a gente força essa 3ª virar o goodbye final em vez de mais um "obrigado".

**Counter scope:** `staticData['thanksLoop_' + phone]` é por workflow + por phone. Persistido entre execuções via N8N static data. Sobrevive a re-deploys do workflow.

---

## Dedup de Mensagens

UAZAPI pode enviar o mesmo webhook 2+ vezes:

```js
var fs = require('fs');
var lockFile = '/tmp/dedup_' + messageId + '.lock';
try {
  fs.writeFileSync(lockFile, '1', { flag: 'wx' }); // wx = fail if exists
} catch(e) {
  return [{ json: { skip: true, reason: 'duplicate' } }];
}
```

---

## Webhook Auth Patterns

### Timing-Safe Comparison (OBRIGATÓRIO)

```typescript
import { timingSafeEqual } from "crypto";
// Compara tamanho primeiro, depois bytes — previne timing attacks
```

### Patterns por webhook

| Webhook | Auth | Env Var |
|---------|------|---------|
| WhatsApp/NotificaMe | Header `x-webhook-secret` ou `Authorization: Bearer` | `WEBHOOK_SECRET` |
| Chatwoot | Query param `?token=` (fallback header) | `CHATWOOT_WEBHOOK_SECRET` → `WEBHOOK_SECRET` |
| Cron (Vercel/N8N) | `Authorization: Bearer` | `CRON_SECRET` → `WEBHOOK_SECRET` |

---

## API Route Pattern (Next.js)

### Estrutura padrão

```typescript
import { createJsonHelper, createOptionsHandler, handleApiError } from "@/server/api-utils";

const METHODS = ["POST", "OPTIONS"];
const json = createJsonHelper(METHODS);
export const OPTIONS = createOptionsHandler(METHODS);

export async function POST(req: NextRequest) {
  try {
    // 1. Auth
    // 2. Parse body (Zod)
    // 3. Business logic
    // 4. Return json(req, data, 200)
  } catch (error) {
    return handleApiError(req, error, "service-name", json);
  }
}
```

### CORS

```typescript
// Automatic via createJsonHelper → buildCorsHeaders
Access-Control-Allow-Methods: POST, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
Vary: Origin
```

### Error Mapping (handleApiError)

```
"Unauthorized access" / "Missing authorization" → 401
"Forbidden" → 403
"not configured" / "not active" → 404
Default → 500
```

---

## Supabase Storage (Public CDN para Mídia)

Pattern para hospedar arquivos públicos refetcháveis (template images, áudios do agente IA, etc.) sem depender de CDN externo.

### Setup do bucket público

```sql
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('whatsapp-template-images', 'whatsapp-template-images', true, 5242880,
  ARRAY['image/png','image/jpeg','image/webp']::text[])
ON CONFLICT (id) DO NOTHING;
```

**Public bucket** = SELECT público sem policy explícita. Service role bypassa RLS para INSERT/UPDATE/DELETE.

### Criar bucket via API (sem SQL)

```bash
curl -X POST "https://{ref}.supabase.co/storage/v1/bucket" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"id":"my-bucket","name":"my-bucket","public":true,"file_size_limit":5242880,"allowed_mime_types":["image/png"]}'
```

### Upload + getPublicUrl

```ts
// Backend (Node, supabase-js)
await supabase.storage
  .from('my-bucket')
  .upload(fileName, buffer, { contentType: 'image/png', upsert: true });

const { data } = supabase.storage
  .from('my-bucket')
  .getPublicUrl(fileName);
// → https://{ref}.supabase.co/storage/v1/object/public/my-bucket/{fileName}
```

```bash
# Direct API (binary upload)
curl -X POST "https://{ref}.supabase.co/storage/v1/object/my-bucket/file.png" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: image/png" \
  -H "x-upsert: true" \
  --data-binary @/path/to/file.png
```

### Vercel env extraction (gotcha)

`vercel env pull /tmp/file` salva valores entre aspas. Valores JWT podem vir com `\n` literal no final (escape do CLI). Sempre limpar:

```js
const m = dotenv.match(/^SUPABASE_SERVICE_ROLE_KEY="([^"]+)"/m);
let key = m[1];
if (key.endsWith('\\n')) key = key.slice(0, -2);  // strip literal \n
```

### Smoke test pattern

```bash
# 1. List buckets
curl ".../storage/v1/bucket" -H "apikey: $K" -H "Authorization: Bearer $K"

# 2. Create
curl -X POST ".../storage/v1/bucket" -H "apikey: $K" -d '{"id":"test","name":"test","public":true}'

# 3. Upload
curl -X POST ".../storage/v1/object/test/file.png" -H "Authorization: Bearer $K" -H "Content-Type: image/png" --data-binary @file.png

# 4. Public fetch (no auth)
curl ".../storage/v1/object/public/test/file.png"

# 5. Cleanup
curl -X DELETE ".../storage/v1/object/test/file.png" -H "Authorization: Bearer $K"
```

### Quando usar

| Caso | Storage | Por quê |
|---|---|---|
| Template header image (Meta CDN URL) | Supabase Storage | header_handle não refetchável |
| Áudio TTS pra reenviar via API | Supabase Storage | URL pública durável |
| Anexos Chatwoot → reuso | Supabase Storage | Active Storage URLs expiram |
| Avatar de contato | Supabase Storage | Upload via UI |
| Imagens de UI (estáticas) | `/public` Next.js | Sem upload runtime |

---

## Database Schema (dispatch_tracking)

```sql
dispatch_tracking:
  id, created_at, telefone, nome, empresa,
  message_id (unique), provider_message_id,
  template_name, mode ("sdr"|"nutricao"|"followup"),
  is_customer, lead_id,
  sent_at, delivered_at, read_at, replied_at, failed_at,
  error_message
```

### Queries importantes

```sql
-- Dedup antes de dispatch
SELECT telefone FROM dispatch_tracking
WHERE template_name = $1 AND sent_at IS NOT NULL AND failed_at IS NULL

-- Status update (lookup duplo)
UPDATE dispatch_tracking SET sent_at = $2
WHERE message_id = $1
-- Fallback:
WHERE provider_message_id = $1

-- Past activity (daily summary)
SELECT * FROM dispatch_tracking
WHERE created_at < $startOfDay
AND (read_at >= $startOfDay OR replied_at >= $startOfDay OR delivered_at >= $startOfDay)

-- Follow-up candidates
SELECT * FROM leads
WHERE is_customer = true AND client_stage_id = 'interagiu' AND updated_at < $2hAgo
```

---

## Workflow Architecture (Fluxo Típico N8N)

```
Webhook UAZAPI
  → Normalizar Entrada (Code Node)
  → IF skip? (grupo, fromMe)
  → IF audio? (sim → transcrever → set texto)
  → Dedup (lock file)
  → IF pausa IA? (Redis check)
  → Debounce Save → Wait 3s → Debounce Verify
  → AI Agent (LangChain + GPT-4o + Postgres Memory)
  → Validar JSON resposta
  → IF transferir? (sim → notificar admin + pausa Redis + Chatwoot labels)
  → IF audio response? (TTS ElevenLabs)
  → Split Out Mensagens → Loop → Enviar UAZAPI/NotificaMe
  → Registrar Chatwoot (private: true)
```

---

## Dependency Matrix

```
chatwoot-webhook route
  ├→ validateWebhookSecretOrQuery (http.ts)
  ├→ advanceClientByPhone (client-pipeline.ts)
  ├→ getChatwootConfig, applyTransferLabels, addLabelsToConversation (chatwoot.ts)
  ├→ buildLeadSummary (alerts.ts)
  └→ matchLeadByPhone (lib/phone.ts)

whatsapp-webhook route
  ├→ validateWebhookSecret (http.ts)
  ├→ advanceClientStage, advanceClientByPhone (client-pipeline.ts)
  ├→ getChatwootConfig, mirrorDispatchToChatwoot, findConversationByPhone (chatwoot.ts)
  └→ Zod schemas

bulk-sdr route
  ├→ authenticateRequest, getActiveIntegrationConfig (server/supabase.ts)
  ├→ normalizePhone (lib/phone.ts)
  └→ mirrorDispatchToChatwoot (chatwoot.ts)

daily-summary cron
  ├→ validateCronSecret (http.ts)
  └→ sendDailySummary (alerts.ts → chatwoot.ts)

client-pipeline.ts
  ├→ matchLeadByPhone (lib/phone.ts)
  ├→ sendPipelineAlert (alerts.ts)
  └→ getChatwootConfig, applyTransferLabels (chatwoot.ts)
```

---

## Common Mistakes & Fixes

| Erro | Solução |
|---|---|
| PUT workflow sem `name` | Sempre inclua `wf.name` |
| `settings` com props extras | Só `{ executionOrder: 'v1' }` |
| Template literals em Code Node | Concatenação com `+` |
| Chatwoot webhook loop | `private: true` na mensagem |
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
| Follow-up repetido | Verificar existência de dispatch `mode: "followup"` após updated_at |
| ElevenLabs billing error | Nó "Verificar TTS" checa mimeType antes de enviar |
| Audio sem phone | Buscar de múltiplas fontes (msg, chat, webhook) |
| Payload UAZAPI flat | UAZAPI envia aninhado: `body.message.chatid` |
| Header UAZAPI `AdminToken` | Usar `token` (lowercase) |
| Mock de test desalinhado | Se route usa `validateWebhookSecretOrQuery`, mock deve incluir essa função |
| matchLeadByPhone type error | Cast mock com `as never` em testes |
| Past template activity query | Usar `.or()` com 3 flags separadas (read_at, replied_at, delivered_at) |
| Template `header_handle` retorna "Media upload error" | Não usar URL `scontent.whatsapp.net` direto — cachear em storage público próprio |
| `{{ JSON.stringify() }}` inline em jsonBody quebra | Usar Code node + single-expression body `={{ JSON.stringify($json) }}` |
| Webhook trigger não usa workflow novo após PUT | Force reload via deactivate+activate |
| Webhook não cria execution mas retorna 200 | Host errado — usar webhook receiver host, não editor host |
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
| Stage do Pipedrive aparece como "Stage 81" sem nome | `STAGE_NAMES` hardcoded incompleto — fetch via `GET /stages?pipeline_id=X` antes do build |
| JSON do workflow vira escape hell com SQL+JS inline | Separar em `src/sql/<feature>/*.sql` + `scripts/<feature>/code-*.js` + `build-workflow.js` que monta o JSON |
| Agente de qualificação re-pergunta estado já preenchido / qualifica em duplicidade / trata captação como compra | Ler estado (UTM/faixa) ANTES do roteiro + idempotência por lead + ramificar captação vs comprador. Sinal de alerta no log: cliente pergunta "é um robô?" |
| `queryReplacement` desalinha params / messageId numa coluna timestamp / texto truncado na vírgula / **cron reenvia (flood)** | CSV split por vírgula quebra com QUALQUER texto livre. Trocar `={{a}},={{b}}` por ARRAY `={{ [a, b] }}` (mantém executeQuery) ou `operation:insert`+defineBelow |
| Schedule trigger não dispara após PUT, mas webhook dá 404 | Schedule de workflow NOVO ativado **via API DISPARA** (≠ webhook). Use isso p/ rodar SQL/DDL ad-hoc via workflow schedule temp quando não há connection Postgres local |
| Precisa rodar DDL/SQL mas não tem `SUPABASE_DB_URL` local | Workflow temp `Schedule(1min)→Postgres(executeQuery)` c/ a cred do n8n; multi-statement terminando em SELECT (CREATE/UPDATE 0-rows trava o encadeamento) |
| Agente re-saúda "como se zerasse a janela" no meio da conversa | Continuidade vinha de `staticData` volátil + Resumir Histórico=SEM_HISTORICO. Derivar `jaConversou` do histórico PERSISTENTE (`$('Memória Antiga').all().length>0`) e forçar no prompt |
| Testar bug do agente sem mandar msg a ninguém | Injetar payload no webhook com número DDD `00` (inválido); o agente processa, o `/send` falha, inspeciona Guard flags via `/executions?includeData`. Testar saudação exige conversa LONGA (>buffer) e espaçar > tempo de processamento (evitar race) |

---

## Testing Patterns

### Mock de Chatwoot config

```typescript
vi.mock("@/server/chatwoot", () => ({
  getChatwootConfig: vi.fn(),
  getChatwootActivityToday: vi.fn(),
}));
// Default: não configurado
vi.mocked(getChatwootConfig).mockRejectedValue(new Error("Not configured"));
```

### Mock de webhook auth

```typescript
vi.mock("@/server/http", () => ({
  validateWebhookSecret: vi.fn(),
  validateWebhookSecretOrQuery: vi.fn(),  // OBRIGATÓRIO para chatwoot-webhook
  buildCorsHeaders: vi.fn((_o, _h, methods) => ({...})),
  getErrorMessage: vi.fn((e, f) => e instanceof Error ? e.message : f),
}));
```

### Mock de matchLeadByPhone

```typescript
// Generic function — cast com `as never` para evitar type error
vi.mocked(matchLeadByPhone).mockReturnValue({ id: "lead-1", telefone: "..." } as never);
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

Agente de qualificação alucina re-perguntando/duplicando quando o estado JÁ vem preenchido. Antes de marcar "pronto", rode a matriz de estado — não só o lead-comprador-novo:

- Lead com UTM/faixa de investimento já preenchida → NÃO pode re-perguntar.
- Lead já qualificado → qualificação idempotente (não duplica).
- Lead de captação (≠ comprador) → roteiro próprio; captação não é compra.
- Multi-destinatário (ex: escalação corretor ausente): asserir que TODOS os N destinatários receberam, não só o primeiro — "alerta pra 1 de N" = falha.
- Tom: saudar → apresentar → responder a pergunta → só então encaminhar; sem repetir "o especialista vai confirmar". Sinal de alerta no log: cliente pergunta se está falando com robô.
