<!-- secscan: lido na Fase 3, ao avaliar C2, C3 e C6 em app Next.js ou com Supabase Auth no servidor -->

## Next.js e Supabase Auth: onde a checagem some (Fase 3)

> Ponto de partida: skills `hunt-*` de `elementalsouls/Claude-BugHunter` (MIT), destiladas em
> checklist defensivo para este stack. Só a parte estática: o teste com requisição das mesmas
> classes (middleware, source map, CORS, GraphQL, CSRF, URL interna) é a fase dinâmica da
> `baseline`, em `skills/baseline/references/08-perimetro-dinamico.md`.

Sem `next` no `package.json`, os itens de Next são `não aplicável`; os de Supabase Auth valem
para todo código de servidor que usa `@supabase/ssr` ou `@supabase/supabase-js`.

```bash
grep -E '"next"|"@supabase/(ssr|supabase-js|auth-helpers-nextjs)"' package.json
ls middleware.* proxy.* src/middleware.* src/proxy.* 2>/dev/null
grep -rnE 'auth\.getSession\(' src app lib supabase/functions --include='*.ts' --include='*.tsx' 2>/dev/null
grep -rlE "^['\"]use server['\"]" src app 2>/dev/null
```

### C2 — Autenticação e controle de acesso

- **`getSession()` decidindo acesso no servidor.** Ela lê a sessão do cookie sem conferir a
  assinatura, e o cookie é do cliente. Em middleware/proxy, route handler, Server Action, Server
  Component e Edge Function, identidade vem de `getClaims()` (verifica a assinatura do token) ou
  `getUser()` (consulta o Auth). `getSession()` no servidor serve para pegar o token e repassar,
  nunca para o `if`. `HIGH` quando o retorno decide acesso ou vira o `user.id` de uma query com
  `service_role`.
- **Middleware como única barreira.** No Next 16 o arquivo se chama `proxy.ts`; até a 15,
  `middleware.ts`: procure os dois. O middleware redireciona quem não tem sessão, mas route
  handler, Server Action e página que lê dado conferem de novo, por dois motivos concretos: o
  `matcher` costuma excluir `/api`, `/_next/data` ou um prefixo esquecido; e o CVE-2025-29927
  (GHSA-f82v-jwr5-mffw, crítico) permitia pular o middleware com o header
  `x-middleware-subrequest` (corrigido em 12.3.5, 13.5.9, 14.2.25 e 15.2.3; a versão vulnerável
  sai pelo audit da Fase 4, na C5). Leia o `matcher` e, para cada rota protegida só por ele,
  procure a checagem no próprio handler. Ausente: `HIGH`.
- **Server Action é um POST público.** Toda função exportada de arquivo `'use server'` ganha um
  id chamável sem passar pela tela. Checagem que mora no componente (botão escondido, redirect
  no client) não protege. Cada action confere identidade e dono do recurso no corpo dela.
  `grep -LE 'getClaims|getUser|requireUser|requireRole|auth\(' <arquivos 'use server'>` lista os
  candidatos; leia cada um, porque o helper do projeto pode ter outro nome.
- **CSRF em route handler com cookie.** Server Action confere `Origin` contra `Host` sozinha;
  route handler (`app/**/route.ts`) não. Handler que muda estado e reconhece o usuário pelo
  cookie de sessão precisa conferir `Origin` ou `Sec-Fetch-Site`, ou exigir
  `Content-Type: application/json` e recusar o resto. Cliente que manda `Authorization: Bearer`
  não tem o problema. Mutação em `GET` (rota de "confirmar", "excluir", "aceitar convite") é
  achado por si. `MEDIUM`; `HIGH` em ação de conta (e-mail, senha, vínculo de provedor).
  Na sugestão de correção, não escreva `origin === new URL(request.url).origin`: atrás de
  proxy a URL da requisição pode trazer o host interno, e toda escrita vira 403 em produção
  com o teste local verde. A forma: `Sec-Fetch-Site` primeiro (`same-origin` e `none` passam);
  só sem ele, `Origin` contra a URL pública do app vinda de variável de ambiente; rota que
  autentica por bearer (token de API, OAuth, MCP) fica isenta, porque é cross-origin por
  desenho. Os passos estão no pilar 03 da baseline (`skills/baseline/references/03-auth.md`,
  "Sessão e CSRF").
- **Cookie do `@supabase/ssr` sem `HttpOnly` não é achado.** O cliente do navegador
  (`createBrowserClient`) lê a sessão do cookie, e a biblioteca grava com `httpOnly: false` por
  padrão; receitar `HttpOnly` quebra o login. Reporte como limite de arquitetura (`INFO`),
  confira `Secure` e aponte a CSP como a defesa contra script que lê o token. `HttpOnly` e
  prefixo `__Host-` são exigência de cookie de sessão própria.
- **Endpoint de revalidação** (`revalidatePath`/`revalidateTag` atrás de rota pública): exige
  segredo forte comparado em tempo constante (C7), só `POST`, e `path`/`tag` do request contra
  uma lista. `LOW` a `MEDIUM` (custo e cache envenenado).
- **Vínculo de conta por e-mail.** Callback de login social que acha o usuário pelo e-mail do
  provedor, sem exigir e-mail verificado, entrega a conta a quem cadastrar o mesmo e-mail em
  outro provedor. Procure `signInWithOAuth`, `linkIdentity` e callback próprio com
  `eq('email', …)`. `HIGH`.
- **App que emite token OAuth** (tem `/authorize` e `/token` próprios: servidor MCP com
  registro dinâmico, "Entrar com <app>" para parceiro): o checklist de código de uso único,
  PKCE, `redirect_uri`, DCR, refresh e clickjacking está em
  [c8-oauth-servidor.md](c8-oauth-servidor.md). Os achados dele entram nesta C2.

### C3 — Exposição de dados sensíveis

- **Prop de Server Component para Client Component.** Toda prop de um componente
  `'use client'` vai serializada no HTML e no payload RSC, legível no navegador. Linha inteira do
  banco (`select('*')`) passada como prop entrega coluna interna. O finding é a prop, com o
  `arquivo:linha` do `select` que a alimenta: mesma classe do endpoint que devolve a linha
  inteira.
- **Cache com dado de um usuário servido a outro.** `unstable_cache`, `'use cache'`, `fetch` com
  `next: { revalidate }` ou página estática que lê sessão ou cookie e guarda o resultado sob uma
  chave sem o usuário. `HIGH` quando o dado é pessoal.

### C6 — Configuração insegura

- **URL absoluta montada com `Host`.** `headers.get('host')` ou `x-forwarded-host` montando link
  de e-mail, redirect ou callback deixa o atacante escolher o domínio do link de reset. A URL do
  site vem de variável de ambiente. Em self-host abaixo do 14.1.1, a mesma confiança no `Host`
  em Server Action vira SSRF (CVE-2024-34351, GHSA-fr5h-rqp8-mj6g); na Vercel não se aplica.
  `MEDIUM`; `HIGH` em link de reset ou de login.
- **`images.remotePatterns` com curinga** (`hostname: '**'`) ou `domains` amplo: o `/_next/image`
  vira proxy de qualquer host (custo, hotlink, SSRF limitado). `dangerouslyAllowSVG: true` sem
  `contentSecurityPolicy` junto. `LOW` a `MEDIUM`.
- **IP do cliente lido de header forjável.** Rate limit ou allowlist por `x-forwarded-for` lido
  como vem, atrás de proxy que não o sobrescreve, deixa o atacante escolher o IP. Na Vercel, use
  `ipAddress()` de `@vercel/functions`; em Express, `trust proxy` igual ao número real de
  proxies, nunca `true`. `MEDIUM`.
- **`postMessage` sem origem.** `addEventListener('message', …)` que não compara `event.origin`
  com uma lista exata, ou `postMessage(dado, '*')` levando dado sensível. `MEDIUM`.

```bash
grep -rnE "headers(\(\))?\.get\(['\"](host|x-forwarded-host)['\"]" src app 2>/dev/null
grep -nE 'remotePatterns|domains|hostname|dangerouslyAllowSVG' next.config.* 2>/dev/null
grep -rniE 'x-forwarded-for|x-real-ip|trust proxy' src app supabase/functions 2>/dev/null
grep -rnE "addEventListener\(['\"]message['\"]|postMessage\(" src app 2>/dev/null
grep -rnE "unstable_cache|['\"]use cache['\"]|revalidate(Path|Tag)?\(" src app 2>/dev/null
grep -rnE 'export (const|async function|function) GET\b' -A15 src/app app 2>/dev/null | grep -E '\.(insert|update|delete|upsert|rpc)\('
grep -rnE "searchParams\.(set|get)\(['\"](callbackUrl|next|redirect(To)?|returnTo)['\"]" src app 2>/dev/null
find src lib -iname '*rate*limit*' -not -path '*/node_modules/*' 2>/dev/null
```
- **Mutação em GET**: o grep também casa `export const GET = wrapper(...)`, que o de antes
  perdia quando toda rota do projeto passa por um wrapper.
- **Parâmetro de retorno** (`callbackUrl`, `next`, `returnTo`): `get` sem validar que é
  caminho relativo do próprio site é open redirect (`MEDIUM`). `set` sem `get` em lugar nenhum
  é parâmetro órfão: o login não volta para onde o usuário estava (`LOW`).
- **Rate limit com contador em memória.** `new Map()` ou `LRUCache` num arquivo de limite, sem
  KV, Redis nem tabela, vale por instância: em serverless o limite real é o configurado vezes
  o número de instâncias, e zera no cold start. O critério "lê `x-forwarded-for` como vem" não
  basta: pergunte também se o contador é compartilhado (`rate_limit_em_memoria` no
  `rotas-next.py` da baseline). `LOW` a `MEDIUM`.
- **Erro de guard engolido.** Rota com guard que lança erro tipado e `catch` que devolve 500
  ou sucesso: o 403 some. Não aparece em busca por "rota sem guard", porque o guard está lá
  (`autherror_engolido` no `rotas-next.py`). `MEDIUM`.
