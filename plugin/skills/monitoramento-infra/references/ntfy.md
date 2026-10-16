# ntfy: alerta no celular com um `curl`

[ntfy](https://docs.ntfy.sh/) é push por HTTP: você publica num **tópico** e todo
celular inscrito nele recebe a notificação. Não tem conta, SDK nem webhook para
configurar. É o canal de detalhe do monitor: chega rápido, aguenta volume e não
depende do WhatsApp, do e-mail nem do sistema que caiu.

## Em 5 minutos

1. Instale o app ntfy (Android / iOS) e inscreva-se num tópico com nome
   **aleatório** (ver "O tópico é a senha" abaixo):
   ```bash
   echo "alertas-$(openssl rand -hex 12)"
   ```
2. Teste:
   ```bash
   curl -d "teste do monitor" https://ntfy.sh/<seu-topico>
   ```
3. Guarde a URL completa do tópico onde seus segredos moram (`.env` fora do git,
   Vault do Supabase, credencial do n8n) — **nunca** no código.

## O tópico é a senha

No `ntfy.sh`, **todo tópico é público**: quem souber o nome lê todos os seus
alertas e publica alertas falsos. Não existe "tópico privado" sem autenticação.
Consequências práticas:

- **Nome com entropia de verdade.** `alertas-meusite` se adivinha. Um tópico com
  6 caracteres hex (24 bits) apareceu num JSON de workflow versionado em git e
  virou item de rotação. Use 12+ bytes aleatórios. No Postgres:
  `'https://ntfy.sh/alertas-' || encode(gen_random_bytes(12), 'hex')`.
- **Fora do git.** Workflow do n8n exportado para o repositório leva a URL do
  tópico junto. Leia de variável de ambiente ou de credencial. Um scanner de
  segredo deveria procurar `ntfy.sh/` em tudo que é versionado — junto com
  `hooks.slack.com/` e `discord.com/api/webhooks`, que têm o mesmo problema.
- **Quem lê a tabela lê os alertas.** A tabela de destinos fica fora da policy de
  leitura de quem não administra o monitor.
- **Vazou? Troque o tópico.** Gere outro, atualize o destino, reinscreva o celular.

Precisa de controle de acesso de verdade: servidor ntfy próprio com
`auth-default-access: deny-all` e token por publicador, ou um plano pago do
ntfy.sh com tópico reservado. Aí o publicador manda:

```
Authorization: Bearer tk_...
```

## Como publicar

### Headers (o jeito curto)

```bash
curl -H "Title: Site fora" -H "Priority: 5" -H "Tags: rotating_light" \
     -H "Click: https://meusite.com.br" \
     -d "meusite.com.br falhou 2x seguidas (timeout 10s)" \
     https://ntfy.sh/<seu-topico>
```

### JSON na raiz (o jeito que aceita acento)

```bash
curl -H 'Content-Type: application/json' -d '{
  "topic": "<seu-topico>",
  "title": "🔴 FORA · site",
  "message": "falhou 2x seguidas (timeout 10s)",
  "priority": 5,
  "tags": ["rotating_light"],
  "click": "https://meusite.com.br"
}' https://ntfy.sh
```

Campos aceitos no JSON: `topic` (único obrigatório), `message`, `title`, `tags`,
`priority` (inteiro 1–5), `click`, `actions`, `attach`, `markdown`, `icon`,
`delay`, `email`. O `assets/sonda-http.sh` publica assim.

### A pegadinha do `Title` com acento

O servidor do ntfy aceita UTF-8 em header, mas **nem todo cliente HTTP manda**.
O `fetch` do Deno (edge function do Supabase) lança erro com caractere fora de
ISO-8859-1 no header; o n8n devolve `Invalid character in header content
["title"]` com emoji. Quem resolve tirando tudo que não é ASCII ganha título como
`CRTICO  AINDA EM FALHA` (de "CRÍTICO — AINDA EM FALHA").

Três saídas, da melhor para a pior:

1. **Publique em JSON na raiz** (acima): o título vai no corpo, em UTF-8.
2. **Codifique o header em RFC 2047**, que o ntfy entende:
   `Title: =?UTF-8?B?<base64 do título>?=`.
3. Título só ASCII e emoji no corpo (`message` é UTF-8 livre) ou nas `Tags`, que
   aceitam nomes curtos de emoji (`warning`, `rotating_light`,
   `white_check_mark`) e o app desenha.

## Prioridade: o que acorda e o que espera

| `Priority` | nome | no Android (doc do ntfy) | use para |
|---|---|---|---|
| 5 | max/urgent | vibração bem longa, som e pop-up | caiu de verdade: `down` confirmado, monitor cego |
| 4 | high | vibração longa, som e pop-up | lembrete de "ainda fora", `degraded` em coisa crítica |
| 3 | default | vibração e som curtos | recuperado |
| 2 | low | sem som; só aparece ao puxar a gaveta | informativo |
| 1 | min | sem som; vai para "outras notificações" | debug |

Decida a prioridade pela **severidade do evento**, não por regra fixa do canal.
Num monitor real a prioridade vinha da regra de alerta, e um `degraded` saía com o
mesmo `urgent` de um `down` — o celular gritava igual para "lento" e para "fora",
e as pessoas silenciaram o app.

## Formato da mensagem

O título é tudo que aparece na tela bloqueada. Ponha nele **o quê** e **onde**:

```
🔴 FORA · n8n produção › fluxo de leads
```

O corpo, uma informação por linha, na ordem em que a pessoa precisa:

```
n8n produção — FORA
Fluxo: fluxo de leads
Falhou 3x · confirmado
Causa: credencial do Postgres inválida
O que fazer: reconectar a credencial no n8n
Último erro: password authentication failed for user ... (até ~280 caracteres)
```

E o `Click` levando direto à tela que resolve. Rótulos que não mentem: 🔴 FORA,
🟠 FALHA (degradado), 🚨 CRÍTICO, 🔴 AINDA FORA (lembrete), ✅ RECUPERADO — e o
recuperado só com evidência (ver [arquitetura-monitor.md](arquitetura-monitor.md#4-recovery-honesto)).

Mensagem acima de 4.096 bytes vira anexo. Não mande payload inteiro: corte o erro.

## ntfy não é o único canal

Cada canal falha de um jeito, e o alerta não pode depender do que caiu:

| Canal | Como falha |
|---|---|
| WhatsApp | a instância que avisa está no mesmo servidor que caiu; número novo sem aquecimento; quem recebe com o celular desligado |
| E-mail | DNS, caixa de spam, MX |
| ntfy | app desinstalado, notificação silenciada no sistema, tópico trocado sem reinscrever |

Monitor sério manda o `down` crítico por pelo menos dois. **Nunca avise "X caiu"
pelo próprio X**: alerta de WhatsApp fora sai por outra instância, em outro
servidor, ou pelo ntfy. O padrão de watcher fora de banda para instância de
WhatsApp (com o estado no Postgres e o envio em três canais) está na
`/kit-vamoo:n8n-workflow-agent` (referência de UAZAPI).

## Do n8n

Nó **HTTP Request**: `POST https://ntfy.sh`, body JSON como acima, timeout 10s e
"Never Error" ligado — falha do aviso não pode derrubar o fluxo que estava
avisando. O tópico vem de uma credencial ou variável, não digitado no nó.

## De uma edge function (Deno)

```ts
export async function avisarNtfy(url: string, a: {
  titulo: string; mensagem: string; prioridade: 1 | 2 | 3 | 4 | 5
  tags?: string[]; link?: string; token?: string
}) {
  const { origin, pathname } = new URL(url)            // https://ntfy.sh/<topico>
  const r = await fetch(origin, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(a.token ? { authorization: `Bearer ${a.token}` } : {}),
    },
    body: JSON.stringify({
      topic: pathname.slice(1), title: a.titulo, message: a.mensagem,
      priority: a.prioridade, tags: a.tags ?? [], click: a.link,
    }),
    signal: AbortSignal.timeout(10_000),
  })
  if (!r.ok) throw new Error(`ntfy ${r.status}: ${await r.text()}`)
}
```

Teste com payload real antes de ligar: `deno test` contra um servidor local que
grava o que recebeu, e uma vez contra o tópico de verdade, com o celular na mão.
