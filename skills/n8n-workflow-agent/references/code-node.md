# Code Node Rules + HTTP jsonBody Pitfalls

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

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
