# Fan-out, Ordem de Balões, Keep-Alive, Redis, Anti-Loop, Dedup

> Referência da skill `n8n-workflow-agent`. Carregue só quando o tema for esse.

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
