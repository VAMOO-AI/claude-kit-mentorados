# Receita alternativa — edge function do Supabase (app não-Next)

Servidor MCP + servidor OAuth próprio numa edge function, atrás de rewrites do
domínio do app. Tirada de um MCP em produção num SPA Vite + Supabase + Vercel,
verificado em 03/10/2026 nos três clientes (Claude Code, claude.ai, ChatGPT).
Código despersonalizado em `references/code/edge/`.

## Quando usar

- **Stack não é Next.js** (SPA Vite, CRA, outro front estático) e o backend é
  Supabase. A receita Next (rota `/api/mcp` + Supabase OAuth Server) não cabe.
- **Schema grande, mesmo em Next.** O token do Supabase OAuth Server também vale no
  PostgREST, e a trava RESTRICTIVE (`banco.md`) entra em toda tabela aberta a
  `authenticated`. Com centenas de tabelas, ofereça esta receita como opção (token
  opaco, que só abre a função) — a decisão é do usuário, não troca automática.

Requisitos: domínio próprio do app com rewrite externo (`vercel.json` na receita
verificada; o rewrite equivalente da Netlify ou da Cloudflare não foi testado) e
edge functions do Supabase.
Sem rewrite, com o issuer no `supabase.co`: não verificado.

**Escopo verificado: um dono, só leitura.** A tabela de tokens só guarda
`client_id`, sem usuário nem papel. Para multiusuário, veja o fim deste arquivo
antes de prometer recorte por papel.

## Fluxo

```
cliente ──POST app/mcp (sem Bearer)──▶ rewrite → função → 401 + WWW-Authenticate:
          resource_metadata="app/.well-known/oauth-protected-resource/mcp"
        ──GET app/.well-known/oauth-*──▶ arquivo ESTÁTICO em public/.well-known/
        ──POST app/oauth/register──▶ função: DCR com allowlist de callback
navegador ──GET <ref>.supabase.co/functions/v1/<funcao>/oauth/authorize──▶
          302 app/mcp-autorizar.html#req=<id>
dono    ──tela: "Enviar código" → código chega no canal do dono → digita──▶
          location.assign(callback?code&state&iss)
cliente ──POST app/oauth/token (PKCE S256)──▶ access opaco 1 h + refresh 30 d rotativo
        ──POST app/mcp  Authorization: Bearer <opaco>──▶ tools
```

## Arquivos (`references/code/edge/` → projeto)

| Referência | Destino no projeto | O que faz |
|---|---|---|
| `references/code/edge/handler.ts` | `supabase/functions/<funcao>/handler.ts` | OAuth (DCR, authorize, token, refresh) + MCP JSON-RPC; tudo injetado, testável |
| `references/code/edge/index.ts` | `supabase/functions/<funcao>/index.ts` | liga o store no Supabase, o kill switch, o envio do código e as tools |
| `references/code/edge/handler.test.ts` | `supabase/functions/<funcao>/handler.test.ts` | 24 testes com store em memória; inclui o que confere os estáticos |
| `references/code/edge/oauth.sql` | `supabase/migrations/<ts>_mcp_oauth.sql` | clientes, pedidos, tokens (só hash), kill switch, `mcp_consume_otp` |
| `references/code/edge/mcp-autorizar.html` + `references/code/edge/mcp-autorizar.js` | `public/mcp-autorizar.html` + `.js` | tela de login: mostra app e destino, pede e confere o código |
| `references/code/edge/vercel.json` | `vercel.json` (mescle) | rewrites `/mcp` e `/oauth/*` + header dos metadados |

No `index.ts`, adapte: `FUNCAO`, `nome`, `quem`, `instrucoes`, o `enviarCodigo`
(stub que lança erro até ser ligado) e o `tools.ts`. As tools chamam a MESMA lib
que a tela do app usa; se o app tem um assistente interno com tools de leitura,
reaproveite a lista.

## Passo a passo

1. **Migration** (`oauth.sql`): o kill switch nasce desligado. Aplique antes do
   deploy da função.
2. **Função**: `handler.ts`, `index.ts`, teste, `tools.ts`. No
   `supabase/config.toml`:

   ```toml
   [functions.<funcao>]
   verify_jwt = false
   ```

   Secret `MCP_PUBLIC_BASE=https://<dominio-do-app>` (sem barra no fim). Deploy com
   `--no-verify-jwt` também, pela skill `ship` ou script do projeto.
3. **Metadados estáticos**: gere `public/.well-known/oauth-authorization-server` e
   `public/.well-known/oauth-protected-resource/mcp` a partir de `metadadosServidor`
   e `metadadosRecurso` (JSON, sem extensão). O teste "metadados estáticos do Vercel
   batem com o handler" lê esses arquivos e falha se divergirem do handler — mudou um, regenere o outro.
   Troque o `<ref>` de `FN_PROD` no teste pelo ref do projeto.
4. **Tela**: `public/mcp-autorizar.html` + `.js`, com as cores e a fonte do app.
5. **`vercel.json`**: os dois rewrites ANTES do catch-all do SPA (`/(.*)` →
   `/index.html`; a ordem decide) e o bloco de header dos metadados. Se o app tem
   CSP com `form-action 'self'`, a tela já termina com `location.assign` em vez de
   form POST + 302 cross-origin; `connect-src 'self'` cobre o `fetch('/oauth/…')`.
6. **PWA**: se o app tem service worker com `navigateFallback`, acrescente ao
   `navigateFallbackDenylist`:
   `[/^\/[^/]+\.html$/, /^\/mcp$/, /^\/oauth\//, /^\/\.well-known\//]`.
7. **Ligar só no fim**: `UPDATE mcp_config SET enabled = true WHERE id;` e conectar
   o primeiro cliente.

## Prova que fecha

| Etapa | Prova |
|---|---|
| Função | `deno test --allow-read supabase/functions/<funcao>/` verde, output colado |
| Metadados | `curl -sI https://<app>/.well-known/oauth-authorization-server` → `200` + `content-type: application/json`; corpo com `authorization_response_iss_parameter_supported: true` |
| 401 | `curl -si -X POST https://<app>/mcp` → `401` com `resource_metadata` no domínio do app |
| Protocolo | POST com `MCP-Protocol-Version: 2026-07-28` → `400` sem corpo |
| Clientes | `whoami` respondendo em cada cliente que o usuário vai usar; linhas `[mcp] tool=` nos logs, 0 erro |
| Kill switch | `enabled = false` → a próxima tool volta "desligado" sem esperar o token expirar |

## Armadilhas (cada uma impediu a conexão sem erro legível)

- **O Vercel não reescreve `/.well-known`.** É path reservado: rewrite para a função
  não pega. Os metadados (RFC 8414 e 9728) têm que ser arquivos estáticos em
  `public/.well-known/`, e o header `Content-Type: application/json` vem do
  `vercel.json` — sem ele, arquivo sem extensão não sai como JSON.
- **Service worker de PWA engole a navegação do `/authorize`.** O `navigateFallback`
  manda qualquer navegação desconhecida para o `index.html` do SPA. Em modo
  `prompt`, o SW antigo segue ativo até o usuário clicar em Atualizar, então o
  denylist novo não basta no primeiro deploy. Por isso o `authorization_endpoint`
  fica no host da função (`<ref>.supabase.co`), única URL que o navegador abre, e
  ele só responde 302 para um `.html` da raiz do app.
- **No `supabase.co`, a edge function serve `text/html` como `text/plain`.** A tela
  de consentimento não pode sair da função: a função só devolve JSON e 302; o
  HTML é estático no domínio do app.
- **Issuer e `resource` saem de `MCP_PUBLIC_BASE`, nunca de `req.url`.** Atrás do
  rewrite, o host que a função vê é o do `supabase.co`, e o cliente recusa
  metadado de outro host.
- **`verify_jwt = false`.** O token é opaco; com `verify_jwt` o gateway devolve 401
  antes de a função rodar. Deploy sem o `config.toml` volta o flag para `true`.
- **Protocolo `2026-07-28`.** Servidor que fala só os protocolos 2025 responde
  `400` sem corpo a `MCP-Protocol-Version` desconhecido. Um erro "moderno"
  (`-32022`) faz o cliente achar que o servidor fala o protocolo novo e não cair no
  `initialize` legado. `subscriptions/listen` recebe `-32601` na hora, e `GET /mcp`
  é `405` (nada de stream aberto).
- **ChatGPT e RFC 9207.** Sem anunciar
  `authorization_response_iss_parameter_supported: true` e sem devolver `iss` em
  TODA resposta do authorize (sucesso, erro e "não fui eu"), o ChatGPT registra um
  callback por conexão (`chatgpt.com/connector/oauth/<id>`). Com 9207 ele usa o
  estável (`chatgpt.com/connector_platform_oauth_redirect`). O handler aceita os
  dois formatos.
- **Allowlist de callback no registro.** É o que corta phishing por DCR. Callbacks
  confirmados:
  - claude.ai / Desktop: `https://claude.ai/api/mcp/auth_callback` (e o mesmo
    path em `claude.com`);
  - Claude Code: `http://localhost:<porta>/callback` ou `http://127.0.0.1:<porta>/callback`,
    porta aleatória — loopback vale em qualquer porta;
  - ChatGPT: `https://chatgpt.com/connector_platform_oauth_redirect`.

  Cliente novo que não conecta: procure `[mcp] registro_recusado redirect=` nos
  logs — a linha diz qual callback falta na lista.
- **PKCE errado queima o code.** O resgate é atômico e vem antes da conferência do
  verifier: o cliente precisa logar de novo. É o desenho, não bug.
- **ChatGPT não aceita Bearer fixo.** Só OAuth, sem auth ou misto. Chave estática
  no header serve para Claude Code, não para ele.

## Conectar (caminhos verificados em 03/10/2026)

- **Claude Code**: `claude mcp add --transport http <nome> https://<app>/mcp` →
  `/mcp` → autenticar. `claude mcp login <nome>` precisa de terminal interativo
  (fora de TTY falha com "stdin isn't a terminal").
- **claude.ai / Desktop**: Personalização → Conectores → Adicionar → Adicionar
  conector personalizado → nome + URL (ele detecta OAuth e registro dinâmico
  sozinho) → Vincular. Cada tool pede "Permitir" na primeira chamada.
- **ChatGPT**: Plugins (`chatgpt.com/plugins`) → Adicionar → Criar servidor MCP
  personalizado → URL, autenticação OAuth → aceitar o aviso de risco → Criar como
  plugin → Continuar. No chat, chame com `@<nome>`. Não procure "Developer mode":
  as docs da OpenAI citam, a tela não tem.

## Operação

```sql
-- liga / desliga na hora (lido a cada chamada; nasce false)
UPDATE mcp_config SET enabled = true,  updated_at = now() WHERE id;
UPDATE mcp_config SET enabled = false, updated_at = now() WHERE id;
-- derruba todas as sessões (o cliente pede login de novo)
UPDATE mcp_tokens SET revoked_at = now() WHERE revoked_at IS NULL;
```

Logs: `[mcp] tool=<nome> ms=<n> ok|erro|timeout`, `[mcp] codigo_enviado`,
`[mcp] autorizado`, `[mcp] registro_recusado`. Pela Management API, use
`GET /v1/projects/<ref>/analytics/endpoints/logs?sql=…` com a tabela única `logs`
(ex.: `select timestamp, event_message from logs where event_message like '%[mcp]%'`);
o endpoint `logs.all` não serve.

## Multiusuário (não verificado nesta receita)

O login por código ao dono não escala para um time. Para mais de uma pessoa:

- a tela de autorização autentica com a sessão do Supabase Auth do app (login
  normal + MFA), e o pedido aprovado grava o `user_id`;
- `mcp_auth_requests` e `mcp_tokens` ganham `user_id`; o `tokenPorAccess` devolve
  `{ client_id, user_id }`;
- cada tool resolve o principal pelo `user_id` a cada chamada e corta pelo escopo,
  como em `servidor.md` (principal, `resolveMcpScope`, testes por papel ANTES);
- a liberação por pessoa e o rollout seguem o `SKILL.md` (nasce desligada, liga só
  para o dono primeiro).

Escreva isso na spec como decisão aberta e prove com teste por papel antes de
liberar a segunda pessoa.
