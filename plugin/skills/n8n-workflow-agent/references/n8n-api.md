# n8n API + Build Pattern

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

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

- **SQL testável solo:** pelo cliente SQL do seu projeto (psql, `supabase db`…), ex.: `psql "$DATABASE_URL" -f src/sql/<feature>/01-query.sql` — a URL do banco vem do ambiente do comando, nunca escrita no repo
- **JS testável solo:** `node scripts/<feature>/test-format-msg.js` com mock de `$input`
- **TDD real:** test failing → impl → test passing → commit por arquivo
- **Diffs legíveis:** cada commit toca 1 SQL ou 1 JS, não um JSON monolítico
- **Reuso:** mesma SQL/JS pode entrar em 2+ workflows

### Quando NÃO usar

- Workflows com <5 nodes ou só nodes nativos do n8n (Set, IF, HTTP) — overhead não compensa
- Quando a equipe edita só pela UI do n8n — build script vira fonte concorrente
- Protótipos descartáveis

---

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

**MAS — schedule trigger de workflow NOVO, ativado via API, DISPARA** (confirmado em produção, num deploy queue-mode onde o webhook dá 404). Diferença prática: o roteador HTTP de webhooks não recebe o evento de registro via API, mas o agendador interno de schedules sim. `minutesInterval: 1` ativado via API disparou em ~15-60s (alinha ao minuto cheio).

### Rodar SQL/DDL ad-hoc sem connection direta ao Postgres (padrão "n8n como executor")

Quando você só tem a **credencial Postgres dentro do n8n** (sem `SUPABASE_DB_URL` local), rode SQL via um **workflow temporário schedule** (já que schedule via API dispara — ver acima):

1. POST `/workflows` com `Schedule(minutesInterval:1) → Postgres(executeQuery, credentials da cred existente)`. Extraia o credential id de qualquer node Postgres de um workflow exportado.
2. `POST /activate` → o schedule dispara em ~15-60s.
3. Leia o resultado em `GET /executions?workflowId=X&includeData=true` (campo `runData["NodeName"][0].data.main[0]`).
4. `POST /deactivate` + `DELETE /workflows/{id}` (limpeza).

**DDL via executeQuery trava o encadeamento:** `CREATE TABLE`/`UPDATE` que afetam 0 rows emitem **0 items** → nodes downstream não rodam (ver "executeQuery retornando 0 rows"). Para um setup multi-statement (CREATE + CREATE + INSERT + verificação), use **UM** Postgres node com todos os statements separados por `;` terminando num **`SELECT`** — o node retorna o resultado do último statement (sempre ≥1 row) e nada trava. Backfill/DDL idempotentes (`IF NOT EXISTS`, `ON CONFLICT DO NOTHING`) tornam re-runs seguros se o schedule disparar 2x antes do delete.

### Workflow Reload after API PUT (CRÍTICO)

**Mesmo problema atinge webhook triggers em alguns casos — fora de queue mode.** Após `PUT /workflows/{id}`, o N8N pode continuar servindo execuções com a definição anterior em cache. Se uma nova node adicionada não aparecer no `runData` mesmo o `connections` mostrando que ela está wirada, force reload via API (em queue mode o ciclo não recupera: ver § Webhook Trigger NÃO REGISTRA, logo abaixo):

```js
await apiCall('POST', '/api/v1/workflows/' + WORKFLOW_ID + '/deactivate');
await new Promise(r => setTimeout(r, 1500));
await apiCall('POST', '/api/v1/workflows/' + WORKFLOW_ID + '/activate');
```

**Sintomas do bug:** runData mostra `Resposta → Check Transferencia` direto, pulando a node nova que você inseriu entre as duas. Solution: deactivate+reactivate cycle.

### Webhook Trigger NÃO REGISTRA via API (n8n self-hosted em queue mode)

> ⚠️ **REGRA DURA OPERACIONAL (workflow LIVE em horário de atendimento):** `PUT /workflows/{id}` **derruba o webhook (404) na hora** e o ciclo `deactivate→activate` via API **NÃO recupera** — só o **Publish manual no editor** re-registra. Logo: NUNCA PUTe um agente em produção sem antes (a) avisar o dono/operador que vai precisar publicar no editor em seguida, e (b) ter o editor aberto pronto pra publicar. Quem tem acesso ao editor é quem publica. Backup do LIVE + preservar `staticData` no body do PUT antes de tocar. (Caso real: confiar no `deactivate→activate` pós-PUT deixou o webhook 404 e o agente fora do ar até o Publish manual — `active:true` é mentira, o webhook continua morto.)
>
> **Não é universal:** num n8n 2.x em queue mode, criar via API registrou o webhook na hora e o PUT em workflow ativo manteve o webhook respondendo 200 (ver § Hosts, logo abaixo). O comportamento varia por versão e deploy. Antes de planejar o deploy de um n8n que você não conhece, teste com um workflow-sonda. Até a sonda provar o contrário, a cautela acima vale para agente em produção.

Em deploys self-hosted com queue mode (main + webhook worker separados), workflows **criados ou atualizados via API REST** ficam com `active=true` no DB mas o roteador HTTP retorna **404 "webhook not registered"**. O deactivate+activate cycle acima TAMBÉM falha — não dispara o pubsub event que avisa o webhook worker pra recarregar rotas.

**Sintoma:**
```bash
curl -X POST .../api/v1/workflows/{id}/activate → 200, active=true
curl -X POST .../webhook/<path> → 404 "not registered"
```

**Diagnóstico rápido:** se um workflow ATIVADO PELA UI no mesmo deploy responde mas o criado-via-API não, é esse bug.

**Fix confirmado em produção (n8n 1.x):**
1. Abrir o workflow no editor n8n UI
2. **Arrastar qualquer nó** (move diff real — Cmd+S sem diff não basta)
3. Salvar (Cmd+S) → toast "Workflow saved" aparece
4. Webhook fica online imediatamente

**Fix no n8n 2.x (modelo de versões/publish):** drag+save NÃO basta. O workflow criado via API nasce como rascunho sem versão publicada; quem registra o webhook de produção é o **Publish**:
1. Abrir o workflow no editor → fazer um **diff real** (ex.: Shift+S adiciona um sticky) → o 2.x **autosalva** o rascunho sozinho (Cmd+S manual não é obrigatório)
2. O botão do topo vira **"Publish"** → clicar → modal "Publish workflow" (nome da versão + descrição) → confirmar
3. Webhook registra na hora (probe 200 "Workflow was started")
Gotchas: setas no teclado NÃO movem node (sem diff); drag sintético via JS não pega (XYFlow usa pointer capture); se o editor mostrar "Autosave failed: Unauthorized", a SESSÃO do n8n expirou — relogar antes de qualquer tentativa (o resto parece funcionar mas nada persiste).

**Implicação grave para iteração (nos deploys onde o bug aparece; confirme com a sonda):** cada `PUT /workflows/{id}` via API desregistra o webhook. Após qualquer PUT, repetir o ritual (1.x: drag+save; 2.x: diff+Publish). Estratégia: minimizar PUTs (consolidar mudanças num único push) ou migrar pra editar no UI direto após o setup inicial.

### Hosts: Editor vs Webhook Receiver

**Editor/API** (para CRUD de workflows, executions): `https://<your-n8n-editor-host>`
**Webhook receiver** (para disparar workflows): `https://<your-n8n-webhook-host>`

Em deploys com queue mode, são SUBDOMÍNIOS DIFERENTES. Disparar webhook no host do editor retorna 200 fake mas não cria execution. Use o `webhookUrl` que aparece em uma execução real para confirmar o host correto:

```bash
# Verificar host real:
curl ".../api/v1/executions/{id}?includeData=true" | jq '.data.resultData.runData.Webhook1[0].data.main[0][0].json.webhookUrl'
```

#### O proxy só roteia `/webhook/*`: MCP Server Trigger e Form ficam inalcançáveis

Medido num n8n 2.x em queue mode. `/webhook/*` e `/webhook-test/*` respondem, mas `/mcp/*` e `/form/*` devolvem **"Cannot POST"** do Express: o proxy manda só `/webhook/*` para o worker, e o resto cai no main, que não serve essas rotas. O **MCP Server Trigger** nativo fica inalcançável sem mexer no proxy. Diagnóstico em dois curls: `/mcp-test/x` responde "webhook not registered" (a rota existe e chegou no n8n), enquanto `/mcp/x` dá "Cannot POST" (não chegou). Saída sem VPS: servidor MCP **stateless** sobre um Webhook comum, tratando `initialize`, `ping`, `tools/list` e `tools/call`, com 202 para notificação e 405 no GET. Valide a implementação com o cliente oficial `@modelcontextprotocol/sdk`.

No mesmo n8n, um workflow criado via API registrou o webhook na hora, e um PUT em workflow ativo manteve o webhook vivo (200). O "PUT derruba o webhook" de § Webhook Trigger NÃO REGISTRA **não é universal**. Antes de adotar o ritual de Publish manual num n8n novo, teste com um workflow-sonda: crie via API um Webhook que devolve 200, chame, faça um PUT trivial e chame de novo.

### Verificar config-version mismatch

```js
// Comparar version IDs antes/depois do PUT
console.log('versionId:', wf.versionId);
console.log('activeVersionId:', wf.activeVersionId);
// Se diferentes → workflow tem mudanças não publicadas, reload necessário
```

---
