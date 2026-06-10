# Pipedrive Integration

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

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
