# PostgreSQL Pitfalls + Schema dispatch_tracking

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

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
