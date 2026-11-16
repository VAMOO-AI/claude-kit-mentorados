# auditoria-seguranca — A5 (XSS) e A6 (agente de IA com ferramentas)

Lido antes de auditar as categorias A5 e A6.

## A5 — Inputs sem tratamento (XSS)

Frontend, por framework:

```bash
grep -rnE "dangerouslySetInnerHTML|v-html|\[innerHTML\]|innerHTML *=|\{@html|\|safe|html_safe|raw\(" \
  --include='*.tsx' --include='*.jsx' --include='*.vue' --include='*.svelte' --include='*.html' \
  --include='*.erb' --include='*.py' src/ app/ templates/ 2>/dev/null
grep -rnE "href=\{[^}]*(url|link|href)|src=\{[^}]*(url|src)|eval\(|new Function\(" --include='*.tsx' --include='*.jsx' src/ 2>/dev/null
```

Depois: **existe lib de sanitização no projeto** (`dompurify`, `sanitize-html`,
`bleach`, `sanitize`)? Se existe, cada sink encontrado ou passa por ela ou é
achado. Se não existe e há sink, o achado é a ausência.

Backend — o ponto cego real: **onde a aplicação escreve HTML fora do framework**.
Template de e-mail, PDF gerado, mensagem de bot, corpo de webhook. React protege
a página; nada disso passa por React.

```bash
grep -rnE '`[^`]*<(p|div|a|table|strong|h[1-6])[^`]*\$\{' --include='*.ts' --include='*.js' . | grep -v node_modules
```

URL controlada pelo usuário em `href`/`src` é a variante que passa despercebida:
`javascript:` continua executando, e a defesa é allowlist de protocolo.

## A6 — Agente de IA com ferramentas

`aplicavel` só quando um modelo de linguagem **decide uma ação**: agente de
WhatsApp no n8n com tools, edge function que chama LLM e executa o que ele
devolve, assistente com acesso a banco, MCP server. Chat que só responde texto
não é A6. Sem essa superfície, escreva `aplicavel: false` com o motivo.

A regra que ordena a categoria: **prompt de guard-rail não é fronteira de
segurança.** "Você não deve apagar registros" no system prompt vale zero; o que
conta é check determinístico no handler da tool. E prompt injection sozinha
também não é achado — o achado é o controle de código que falta **depois** que
o modelo foi convencido. A `guardrails-ia` cobre o comportamento do agente; aqui
é o código.

Quatro mapas antes de procurar: quem executa cada tool (identidade efetiva),
o que cada tool consegue fazer, de onde vem cada texto que entra no contexto
(mensagem do lead, documento recuperado, memória, resultado de outra tool) e
para onde vai a saída do modelo.

```bash
# onde o modelo é chamado e onde a resposta dele vira ação
grep -rnE "tools?\s*[:=]|function_call|tool_calls|\.invoke\(|runTool|executeTool|createAgent|AgentExecutor" --include='*.ts' --include='*.js' --include='*.py' --include='*.json' . | grep -v node_modules
grep -rnE "service_role|SUPABASE_SERVICE_ROLE|createClient\([^)]*service" --include='*.ts' --include='*.js' . | grep -v node_modules   # com que identidade a tool roda
```

Para cada tool que **escreve, envia, agenda ou lê dado de outra pessoa**:

- **Deputado confuso.** A tool roda com `service_role` ou credencial ampla e o
  handler **não re-checa** se o solicitante (o lead, o usuário do chat) poderia
  fazer aquela operação naquele recurso pelo produto normal. Credencial
  compartilhada com escopo por usuário **imposto na query** não é achado.
- **Ação sem vínculo com o pedido.** Conteúdo controlado pelo atacante (mensagem
  do lead, e-mail ingerido, página recuperada) faz o agente executar uma ação
  com a autoridade da vítima — envio, agendamento, mudança de cadastro — que
  ela não pediu nem aprovou. Vale mesmo se a vítima **poderia** fazer aquilo:
  autorização genérica não é intenção.
- **Argumento da tool no sink.** O modelo monta o `where`, o caminho do arquivo,
  a URL, o comando. Schema estruturado limita a forma, não autoriza nada:
  siga cada campo da chamada decodificada até o sink como faria com
  `req.body`.
- **Memória e contexto entre tenants.** Histórico, embeddings, cache de prompt
  e "memória do agente" com chave larga demais: uma conversa lê o que outro
  tenant escreveu, ou uma observação de baixa confiança vira instrução durável
  para outro usuário.
- **Saída do modelo num sink de renderização.** Resposta em HTML, template de
  WhatsApp, Markdown com link, comando: o mesmo encoding da A5, e o modelo é
  uma fonte tão não confiável quanto o usuário.
- **Loop sem teto.** Uma mensagem dispara N chamadas de tool, N envios, N
  cobranças de API sem orçamento por requisição, idempotência ou cancelamento.
  Prove por contagem no código; nunca esgotando o serviço.
- **Annotation tratada como permissão.** `readOnlyHint`, `destructiveHint`,
  `idempotentHint` e afins numa tool MCP são o que o autor da tool **declara**,
  não o que ela faz. Cliente ou gate que libera sem aprovação porque a tool
  "diz" que é só leitura confia no texto de quem pode estar mentindo (ou
  errando). Achado: a hint decide se pede aprovação, e o handler escreve,
  envia ou lê dado de outro. Não é achado: a hint só muda a interface e a
  decisão vem de uma allowlist do lado de quem chama.
- **Aprovação presa ao nome, não à chamada.** O humano aprova "enviar e-mail"
  e o agente manda para qualquer destinatário, com qualquer corpo, quantas
  vezes quiser. A aprovação tem que cobrir a chamada exata — tool **e**
  argumentos — e cair se um argumento mudar depois do clique. Procure onde a
  aprovação é guardada: se a chave é só o nome da tool (ou um "sempre
  permitir" por sessão), qualquer argumento passa.
- **Egress que o modelo escolhe.** Tool de agente ou nó HTTP do n8n que monta
  URL, host, destinatário ou webhook a partir de texto do modelo ou do lead é
  canal de exfiltração: uma instrução escondida numa mensagem manda o agente
  postar o histórico num coletor público (webhook.site e parecidos). No n8n, o
  parâmetro que o modelo preenche aparece como `$fromAI(...)` nos nós de tool;
  o que vem do lead aparece como `$json` ou `$('Nome do nó')`; no HTTP Request
  Tool antigo, como placeholder `{nome}` na URL.

```bash
# n8n: campo de destino preenchido pelo modelo ou pelo lead, nos workflows exportados.
# Lê o JSON e imprime nó, campo, marca e se o host é fixo: nunca o valor, que pode
# trazer chave na query string
find . -name '*.json' -not -path '*/node_modules/*' 2>/dev/null | python3 -c '
import json, re, sys
CAMPO = re.compile(r"^(url|baseUrl|sendTo|toEmail|to|cc|bcc|webhookUrl|endpoint|host|chatId|phone|number|recipient)$", re.I)
MARCA = re.compile(r"\$fromAI|\$json|\$\(\x27[^\x27]+\x27\)|\$node\[|(?<!\{)\{[A-Za-z_][A-Za-z0-9_]*\}")
def anda(o, cam):
    if isinstance(o, dict):
        for k, v in o.items(): yield from anda(v, cam + [k])
    elif isinstance(o, list):
        for i, v in enumerate(o): yield from anda(v, cam + [str(i)])
    else: yield cam, o
for f in sys.stdin:
    f = f.strip()
    try: w = json.load(open(f, encoding="utf-8", errors="replace"))
    except Exception: continue
    for n in (w.get("nodes") or []) if isinstance(w, dict) else []:
        for cam, v in anda(n.get("parameters") or {}, []):
            if not (isinstance(v, str) and cam and CAMPO.match(cam[-1])): continue
            marcas = sorted(set("$(…)" if x.startswith("$(") else x for x in MARCA.findall(v)))
            if not marcas: continue
            pre = v.lstrip("=").split("{{")[0]
            host = "host fixo" if re.match(r"https?://[^/@?#{]+/", pre) else "host variável"
            print(f + ": nó " + repr(n.get("name")) + ": " + ".".join(cam) + ": " + " ".join(marcas) + ": " + host)'
# código: fetch/axios/got (inclusive .post/.get e template literal) com endereço vindo de
# argumento de tool
grep -rniE '(fetch|axios|got|request|http)(\.[a-z]+)?\(`?(\$\{)?(args|input|params|toolInput|arguments)\.[a-zA-Z_.]*(url|endpoint|webhook|host)' \
  --include='*.ts' --include='*.js' --include='*.py' . | grep -v node_modules
```

Achado: o destino vem do modelo ou do lead e não há allowlist de host ou de
destinatário entre a montagem e o envio. Não é achado: host fixo no nó, com a
`/` logo depois dele (`https://api.x.com/{{ … }}`), só o caminho ou o corpo
variável e sem dado de outro tenant no corpo; allowlist conferida no handler
antes do envio. Sem a `/`, o host não é fixo: `https://api.x.com{{ … }}` vira
`https://api.x.com@coletor.example/` com um valor só.

Comportamento do provedor, do renderizador do WhatsApp ou do modelo que o
código não mostra → `a_validar`, com o que o dono confere.
