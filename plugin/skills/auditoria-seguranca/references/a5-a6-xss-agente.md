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

Comportamento do provedor, do renderizador do WhatsApp ou do modelo que o
código não mostra → `a_validar`, com o que o dono confere.
