# 01 · Frontend, bundle e superfície pública

Tudo que sai no build vai pro browser do usuário. Quem quiser ler, lê: minificação
não é ofuscação e ofuscação não é segurança. O objetivo aqui não é esconder — é
**não mandar o que não deveria sair**, e não entregar de graça o mapa da mina.

## Contrato

- [ ] **Sourcemap de produção não é servido.** Ou desligado, ou gerado e enviado
      em canal privado pro error tracker (`hidden: true`), nunca publicado junto
      com o bundle.
- [ ] **Nenhuma variável de build com `KEY`/`SECRET`/`TOKEN`/`PASSWORD` no nome
      sob prefixo público** (`VITE_`, `NEXT_PUBLIC_`, `PUBLIC_`, `REACT_APP_`).
      Prefixo público = está no bundle, ponto.
- [ ] **`dropConsole`/`drop_debugger` só depois que existe error tracking** (ver
      pilar 06). Antes disso você está apagando o único rastro que teria.
- [ ] **CSP presente e sem `script-src 'unsafe-inline'` em produção.**
- [ ] Cinco headers acompanham a CSP: `X-Content-Type-Options`,
      `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`,
      `Strict-Transport-Security`.
- [ ] **Se a CSP existe em dois lugares (header e `<meta>`), um teste trava a
      divergência.** A política efetiva é a *interseção* das duas — divergir
      quebra em produção sem quebrar em dev.
- [ ] Rotas pesadas em lazy load, com orçamento de bundle vigiado no CI.
- [ ] `.env`, `.env.local` e `.env.*.local` fora do git; `.env.example`
      commitado, só com nomes de chave.

## Como implementar

**Vite** — o par que importa é `sourcemap` + `drop`:

```ts
// vite.config.ts
const isProd = mode === 'production'

build: {
  sourcemap: !isProd,        // ou 'hidden' se for subir pro error tracker
  minify: 'oxc',
  ...(isProd && { drop: ['console', 'debugger'] }),   // só com pilar 06 pronto
  chunkSizeWarningLimit: 600,
}
define: {
  'process.env.NODE_ENV': JSON.stringify(mode),       // e nada de chave aqui
}
```

**Next.js**: `productionBrowserSourceMaps: false` (é o default — não ligue "pra
debugar em prod"; use o upload privado do Sentry).

**Headers na Vercel** — a base que vale como ponto de partida:

```json
{ "source": "/(.*)", "headers": [
  { "key": "X-Content-Type-Options", "value": "nosniff" },
  { "key": "X-Frame-Options", "value": "DENY" },
  { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" },
  { "key": "Permissions-Policy", "value": "camera=(), microphone=(), geolocation=()" },
  { "key": "Strict-Transport-Security", "value": "max-age=31536000; includeSubDomains" },
  { "key": "Content-Security-Policy", "value":
    "default-src 'self'; script-src 'self'; worker-src 'self' blob:; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://<host-de-imagem>; connect-src 'self' https://<ref>.supabase.co wss://<ref>.supabase.co; base-uri 'self'; form-action 'self'; object-src 'none'; frame-ancestors 'none'" }
]}
```

`object-src 'none'` e `frame-ancestors 'none'` são baratos e cortam classes
inteiras de ataque. `style-src 'unsafe-inline'` costuma ser inevitável com
Tailwind/framer — aceite e registre; `script-src 'unsafe-inline'` **não**.

Prefira listar hosts em `img-src`/`connect-src` a usar `https:` curinga. Curinga
em `connect-src` é o que transforma um XSS em exfiltração.

**Teste que trava a divergência header ↔ meta** — se as duas cópias existem:

```ts
// src/lib/__tests__/csp.test.ts
const fromMeta   = readCspFrom('index.html')
const fromHeader = readCspFrom('vercel.json')
it('CSP do header e do meta são idênticas', () => {
  expect(normalize(fromMeta)).toBe(normalize(fromHeader))
})
```

Sem esse teste, alguém adiciona um host num arquivo só e a interseção derruba a
feature em produção — com o dev verde.

## Como provar

```bash
# sourcemap vazou pro build?
npm run build >/dev/null 2>&1 && find dist .next -name '*.map' 2>/dev/null | head

# variável pública com cara de segredo
grep -rEn '(VITE|NEXT_PUBLIC|PUBLIC|REACT_APP)_[A-Z0-9_]*(KEY|SECRET|TOKEN|PASSWORD)' \
  --include='*.ts' --include='*.tsx' --include='*.env*' . | grep -v node_modules

# headers realmente servidos (produção)
curl -sSI https://<dominio> | grep -iE 'content-security-policy|strict-transport|x-frame|x-content-type|referrer-policy|permissions-policy'

# unsafe-inline em script-src?
curl -sSI https://<dominio> | grep -i content-security-policy | grep -o "script-src[^;]*"

# .env fora do git
git ls-files | grep -E '(^|/)\.env' || echo "OK: nenhum .env versionado"
```

Note que o único teste que vale para headers é o `curl` no domínio real. Ler
`vercel.json` prova que está escrito, não que está servido — um `rewrite` ou um
CDN na frente pode comer o header.

## Armadilhas

| Sintoma | Causa real |
|---|---|
| Erro de React em produção não aparece em lugar nenhum | `drop: ['console']` ligado sem error tracking. O `componentDidCatch` só fazia `console.error` — e o build apagou |
| Feature funciona em dev e morre em prod com erro de CSP | CSP existe em header **e** `<meta>`; a política efetiva é a interseção. Faltou o teste de divergência |
| "O secret do webhook está no `.env`, está seguro" | Prefixo `VITE_`/`NEXT_PUBLIC_` faz ele ir pro bundle. Um secret que valida chamada precisa ficar do lado que não é servido |
| PDF/worker quebra só em produção | `worker-src 'self' blob:` ausente. `script-src` não cobre worker; a diretiva é separada |
| Bundle cresceu 40% e ninguém viu | `chunkSizeWarningLimit` só avisa no build local; sem gate no CI o aviso rola pra cima e some |
| Deploy "success" mas o app serve código velho | Cache do CDN. O gate correto compara o hash do `index-*.js` do build com o que o domínio devolve |

## Nota sobre "não vazar lógica interna"

Minificar ajuda pouco: qualquer um roda um deobfuscador. O que de fato evita vazar
lógica é **não colocar a lógica no cliente**:

- Regra de preço, margem, comissão e desconto → função no banco ou edge function.
  Se está no bundle, está publicada.
- Enum de papéis e permissões pode estar no cliente (a UI precisa), mas a decisão
  é do servidor — ver pilar 03.
- Endpoint interno, host de VPS, nome de bucket e id de projeto aparecem no
  bundle. Trate-os como públicos e proteja por autenticação, não por obscuridade.
