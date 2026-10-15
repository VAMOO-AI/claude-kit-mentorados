# Pipedrive Integration

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

## Pipedrive Integration

### API basics

```
Base:    https://<your-company>.pipedrive.com/api/v1
Auth:    header x-api-token: <token> (API key) OU Authorization: Bearer (OAuth)
Pipeline: identificado por numeric ID, NÃO por nome
```

### Discover IDs antes de hardcode (CRÍTICO)

**SINTOMA:** tool ou workflow tem `STAGE_NAMES = { 2: 'Qualificação', 3: 'Proposta' }` hardcoded, mas o stage real do deal não aparece corretamente no resumo (vira "Stage 4" sem nome).

**ROOT CAUSE:** o pipeline tem mais stages do que os 2-3 documentados na tool. Stages novos foram adicionados via UI Pipedrive mas o mapping no código não foi atualizado.

**Pattern:** antes de hardcodear, descobrir stages reais via API. O token fica só no ambiente do comando (variável de ambiente), nunca no repo nem no workflow exportado, e vai no header `x-api-token`, não na URL: URL aparece em log (`curl -v`, proxy, execução do n8n), e o `openapi.yaml` da API v1 declara a API key como esse header. Sem `PIPEDRIVE_API_TOKEN` definida, o comando para com `defina PIPEDRIVE_API_TOKEN` em vez de mandar o header vazio:

```bash
curl -s -H "x-api-token: ${PIPEDRIVE_API_TOKEN:?defina PIPEDRIVE_API_TOKEN}" \
  "https://<your-company>.pipedrive.com/api/v1/stages?pipeline_id=$PIPEDRIVE_PIPELINE_ID" \
  | jq -r '.data[] | "  " + (.id|tostring) + ": \"" + .name + "\","'
```

Output direto pra copy-paste no `STAGE_NAMES`:
```
  1: "Entrada",
  2: "Qualificação",
  3: "Proposta",
  4: "Fechamento",
  ...
```

**Alternativa cacheada:** se o pipeline muda, considere fetchar stages dinamicamente uma vez por execução do workflow e cachear em static data — mas pra workflows de baixa frequência (cron diário), hardcode mapped + redocumentar quando mudar é mais simples.

### Pipelines: NÃO use o nome

`pipeline_id` é numérico e estável. **Não tente buscar por nome** (`pipeline=My Pipeline`) — a API não suporta isso de forma confiável. Sempre passe o ID:

```bash
# Listar todos os pipelines pra descobrir o ID
curl -s -H "x-api-token: ${PIPEDRIVE_API_TOKEN:?defina PIPEDRIVE_API_TOKEN}" "https://<your-company>.pipedrive.com/api/v1/pipelines" | jq '.data[] | {id, name}'
```

O `PIPEDRIVE_PIPELINE_ID=<n>` vai no `.env.local` (ou nas variáveis do n8n), com a chave sem valor no `.env.example`.

### `GET /deals/{id}` response shape

```json
{
  "success": true,
  "data": {
    "id": 101,
    "title": "...",
    "stage_id": 3,
    "value": 150000,
    "currency": "BRL",
    "status": "open",       // open | won | lost | deleted
    "user_id": { "id": 1, "name": "Vendedor Exemplo", "email": "..." },
    "owner_name": "Vendedor Exemplo",   // expandido em alguns casos
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
