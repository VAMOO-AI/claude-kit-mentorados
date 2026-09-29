# OAuth — Supabase Auth como servidor de autorização

Fluxo completo:

```
cliente MCP ──POST /api/mcp (sem Bearer)──▶ 401 + WWW-Authenticate: resource_metadata=…
           ──GET /.well-known/oauth-protected-resource[/api/mcp]──▶ { authorization_servers: [<supabase>/auth/v1] }
           ──DCR + /authorize no Supabase──▶ redireciona para <app>/oauth/consent?authorization_id=…
usuário    ──login (senha + MFA) → /oauth/consent → Permitir──▶ Supabase emite code → token
cliente MCP ──POST /api/mcp  Authorization: Bearer <JWT com client_id>──▶ tools
```

## 1. Ligar o OAuth Server no projeto

**Prod — Management API** (PAT da conta DONA do projeto, em variável de ambiente):

```bash
# baseline: guarde a resposta inteira antes de mudar qualquer coisa
curl -s -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  "https://api.supabase.com/v1/projects/$REF/config/auth" > auth-config-antes.json
jq 'with_entries(select(.key|test("oauth_server|site_url|uri_allow_list")))' auth-config-antes.json
```

Confira `site_url` = domínio de prod do app (o consentimento é montado a partir
dele) e que os domínios antigos seguem em `uri_allow_list`. Os nomes das chaves do
OAuth Server saem desse GET (`oauth_server_*`); faça PATCH **só** nelas:
habilitar, permitir registro dinâmico (DCR) e caminho de autorização
`/oauth/consent`. Depois do PATCH, repita o GET e compare com o baseline — só
essas chaves podem ter mudado. Alternativa pelo painel: Authentication → OAuth
Server.

**Local — `supabase/config.toml`** (a CLI recente já cria a seção com
`enabled = false`: edite a existente; uma segunda seção quebra com
`table oauth_server already exists`):

```toml
[auth.oauth_server]
enabled = true
authorization_url_path = "/oauth/consent"
allow_dynamic_registration = true
```

## 2. Metadados do recurso (RFC 9728)

`src/app/.well-known/oauth-protected-resource/[[...path]]/route.ts` — catch-all,
porque clientes mais novos consultam a variante com o path do recurso primeiro.
Código: `code/well-known-route.ts`.

## 3. Proxy / middleware

- `/api/mcp` e `/.well-known/oauth-protected-resource*` saem do gate de cookie: a
  rota autentica por Bearer, e o cliente lê os metadados sem sessão.
- Essa saída vem ANTES do bloco que aceita chave de serviço (`x-api-key`): no MCP
  a chave não pode virar usuário de serviço.
- `/oauth/consent` continua atrás do gate normal (sessão + MFA).
- O redirect para o login guarda de onde a pessoa veio (`?redirect=<path+query>`).

```ts
if (pathname === "/api/mcp" || pathname.startsWith("/.well-known/oauth-protected-resource")) {
  return supabaseResponse; // sem gate de cookie e sem x-api-key
}
// ...
function loginUrl(request: NextRequest) {
  const url = request.nextUrl.clone();
  const destino = request.nextUrl.pathname + request.nextUrl.search;
  url.pathname = "/login";
  url.search = "";
  if (destino !== "/") url.searchParams.set("redirect", destino);
  return url;
}
```

## 4. Login volta para o consentimento

A tela de login lê `?redirect=` e, depois de senha + MFA, navega para
`safeRedirectPath(redirect)` (`code/safe-redirect.ts`). Sem a validação vira open
redirect. Cubra com teste: `//evil.com`, `/\evil.com`, `javascript:`, `/login?…`
voltam para `/`.

## 5. Tela de consentimento + decisão

- `src/app/oauth/consent/page.tsx` (`code/consent-page.tsx`): sem sessão →
  login com redirect; `getAuthorizationDetails`; se a resposta já traz
  `redirect_url` (consentimento anterior), redireciona; roda o MESMO gate do
  servidor MCP. Sem acesso → tela explica o motivo e só oferece "Voltar ao
  agente" (que nega). Com acesso → mostra quem, com que conta, o que o agente
  enxerga para aquele papel e para onde volta (`redirect_uri`).
- `src/app/api/oauth/decision/route.ts` (`code/oauth-decision-route.ts`):
  **revalida o gate** antes de aprovar e responde `303` para `redirect_url`.

## 6. Prova do PR 1

```bash
claude mcp add --transport http <nome> https://<dominio>/api/mcp
```

Abrir `/mcp` no Claude Code → login → consentimento → `whoami`. Decodifique o
access token (ou logue as claims no `verifyToken` uma vez, sem o token) e confirme
a claim `client_id`. Sem ela, a trava de `banco.md` não distingue o agente da
sessão web.
