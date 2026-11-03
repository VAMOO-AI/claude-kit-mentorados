# Base técnica de GEO

O que o crawler (Googlebot, Bingbot, GPTBot, PerplexityBot) precisa receber. Todo item sai do
mesmo dado que a página mostra: texto escrito duas vezes diverge na primeira edição de copy.

## Arquivos na raiz

| Arquivo | Conteúdo | Cuidado |
|---|---|---|
| `robots.txt` | `User-agent: *`, `Allow: /` e `Sitemap: https://<dominio>/sitemap.xml` | Bloquear robôs de treino (GPTBot, CCBot) é decisão do dono do site, não do dev. |
| `sitemap.xml` | uma `<url><loc>` por rota pública, com a URL canônica | Sem `lastmod`: a data do build muda toda página a cada deploy, e o Google passa a ignorar o campo. Só com data verdadeira por página. |
| `llms.txt` | formato de llmstxt.org: `# Marca`, resumo em `>`, listas de links `- [Página](url): descrição` | Gerado das mesmas descrições das rotas. |
| `llms-full.txt` | as ofertas e os FAQs em texto corrido | Nenhuma frase nasce aqui: monte a partir das constantes que a página renderiza. |
| `<chave>.txt` | a chave do IndexNow, sozinha | É pública por protocolo, não é segredo. |

Em Vite, emita os arquivos num plugin com `generateBundle` e `this.emitFile`. Em Next.js, use
`app/robots.ts`, `app/sitemap.ts` e route handlers para os `.txt`.

## HTML que o crawler lê

- **Pré-render por rota.** SPA que só monta no navegador entrega `<div id="root"></div>`. Gere
  `dist/<rota>/index.html` no build (SSR de entrada mais script de prerender), ou use SSG.
- **`title`** no formato `<intenção> | <Marca>`: "Mentoria de IA para empresários | Marca",
  não "Marca | Fulano". A primeira frase visível repete a intenção e nomeia a marca.
- **`meta description`** própria por rota, e canonical absoluto.
- **JSON-LD**:
  - um `@graph` com Organization (`name`, `url`, `foundingDate`, `sameAs` com perfis
    oficiais), Person do fundador, WebSite e um Service por oferta;
  - FAQPage nas páginas que têm FAQ, montado dos mesmos `items` que a página mostra;
  - serialize com `JSON.stringify(data).replace(/</g, '\\u003c')` para não fechar o
    `<script>` por acidente.
- Valide no validator.schema.org (meta: 0 erros, 0 avisos).

## 404 e domínio

- Rota inexistente responde **404 de verdade**, com `<meta name="robots" content="noindex" />`
  e sem canonical. Um rewrite catch-all para o `index.html` transforma todo erro em 200 e
  enche o índice de página duplicada.
- `www` redireciona para o apex com 308 (ou o inverso, mas um só). Na Vercel isso fica no
  painel do domínio, não no repo.

## IndexNow (Bing, Copilot, Yandex, Seznam)

Ao fim de cada deploy de produção, avise todas as URLs do sitemap:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/geo-ia/scripts/indexnow.mjs" https://<dominio> <chave>
```

O script confere que `https://<dominio>/<chave>.txt` serve a chave, lê o sitemap e faz o POST
em `api.indexnow.org`. 200 e 202 são aceite; 422 é URL fora do host ou chave que não bate.

## Gate pós-build

Um script no fim do `npm run build` que falha se faltar algo. O mínimo:

- os quatro arquivos e o `<chave>.txt` existem no `dist/`;
- o `404.html` tem `noindex` e não tem canonical;
- todo bloco `application/ld+json` de toda página faz `JSON.parse`;
- as páginas que devem ter FAQPage têm.

## Conferir no ar

O preview da Vercel costuma ter login (SSO): 404, robots e Content-Type só se testam em
produção.

```bash
for u in /robots.txt /sitemap.xml /llms.txt /llms-full.txt / /nao-existe; do
  curl -sS -o /dev/null -w "$u %{http_code} %{content_type}\n" "https://<dominio>$u"
done
curl -sI https://www.<dominio>/ | head -3
```

Esperado: os arquivos em `text/plain` ou `application/xml`, a home em 200, `/nao-existe` em
404 e o `www` em 308 para o apex.
