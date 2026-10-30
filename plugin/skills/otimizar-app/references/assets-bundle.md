# Bytes: bundle, imagens, fontes, cache

Carregue quando a queixa for "demora pra aparecer" ou quando o número de partida estiver em
bytes: Lighthouse, `curl -w`, tamanho do boot.

## Bundle: meça o boot, não o `dist`

- **Conta o que o `index.html` baixa antes do primeiro paint:** o entry, o `modulepreload`
  **da rota inicial** e o CSS. O `modulepreload` de uma rota lazy não bloqueia o primeiro
  paint, e somá-lo como crítico já inventou gargalo: num app, mais de 150 KB de `charts`
  eram preload de rota lazy, o boot real era outro, e nenhuma das 3 hipóteses o mexeu.
- Use o build real (`npm run build`), não a leitura dos imports. Rastreador de imports
  caseiro precisa ser validado primeiro contra um caso cujo resultado você já sabe.
- Barrel file e `import` de tipo sem `import type` podem puxar módulo pesado para o chunk
  errado. Trate como hipótese a medir: o mesmo diagnóstico foi refutado no mesmo dia,
  quando medido.
- `lazy()` numa página que ninguém abre no boot só troca o nome do chunk.
- Dependência instalada e sem import sai: uma lib de animação com centenas de KB e zero
  imports é um caso típico. Antes de remover, rode um grep em `scripts/` também: um
  `qrcode` "morto" gerava um SVG que estava no ar.
- **Vite 8 (Rolldown)** ignora `esbuild.drop`. A remoção de console passa para
  `output.minify.compress`.
- `dropConsole` em prod apaga o `console.error` dos ErrorBoundary. Tenha error tracking
  antes de otimizar às cegas.
- **Chunk velho depois de deploy:** a aba aberta pede um chunk que já não existe. Resolve
  com `lazyWithReload` ou com rota de versão que recarrega a aba.

## Imagens

- `next/image` com `unoptimized` entrega o arquivo inteiro: centenas de KB para desenhar
  um avatar de 96 px. Com `sizes="96px"` caiu para poucos KB. **Sem `sizes` não há ganho.**
  Teste que trava o `src` literal quebra; teste a origem do arquivo.
- **Fora do Next:** `cwebp -q 80` em 2 larguras, com
  `<picture><source type="image/webp">` e o PNG como fallback. Num site de templates
  isso levou alguns MB a menos de 200 KB.
- **Recompressão em lote:** só grava o arquivo se passar num gate de qualidade (PSNR ≥ 30
  para PNG, ≥ 38 para JPEG) e de ganho mínimo. JPEG recomprimido sobre JPEG degrada.
- **Não renomeie asset que o bundle referencia:** o nome fica cravado no JS minificado com
  hash. Sobrescreva no mesmo caminho.
- **Upload:** comprima no navegador antes de subir. Nunca guarde base64 em coluna; use o
  Storage. Num mapa de fotos, o GET caiu de mais de 100 KB para poucos KB só por isso.
- **Miniatura que baixa a foto original do Storage.** Uma lista de 52 entradas mostrava
  quadrados de 64 px com as fotos originais de ~1 MB (até 6 MB): ~54 MB a cada abertura
  da aba, no celular inclusive. E cada miniatura assinava a própria URL num `useEffect`
  (duas vezes por item): 161 requests ao Storage. O conserto, sem mudar o visual:
  - **assinar em lote** na página: um `createSignedUrls(paths)` em vez de um
    `createSignedUrl` por item, repassado às miniaturas por contexto (161 → 58 requests;
    o tempo não mexeu, porque o peso eram os bytes);
  - **`loading="lazy"` + `decoding="async"`** no `<img>`: desktop 53,9 → 0,4 MB e
    4,4 → 1,7 s até o último dado; celular 53,6 → 0,1 MB, porque a lista fica abaixo da
    dobra.

  Meça bytes somando o `responseBodySize` dos requests ao Storage, com contexto limpo
  (sem cache), e conte as miniaturas que carregaram, para provar que nada sumiu. O próximo
  passo seria gerar a miniatura no upload; a transformação de imagem do Supabase é de
  plano pago.
- `deviceSizes` sem 2k/4k, mais um teto de largura, evita o upscale do hero.
- Não troque a arte sem aprovação. Um SVG "recriado" no lugar do PNG muda a marca.

## Fontes

- Peso de fonte carregado e não usado sai da URL do Google Fonts (o 700 baixado e nunca
  usado é o caso mais comum).

## Cache HTTP

- **SPA Vite na Vercel** (`vercel.json`):
  - `/assets/(.*)` com `public, max-age=31536000, immutable`, porque o nome leva hash;
  - `/images/(.*)` com `public, max-age=86400, stale-while-revalidate=604800`.
  - Sem esse header, a Vercel serve o `/assets` com `public, max-age=0, must-revalidate`
    e toda visita revalida.
- **Não leve a API junto.** `/api` com dado de cliente fica `no-store, private`, para a
  resposta de um tenant nunca parar em cache intermediário.
- Imagem atrás de URL assinada (JWT) não entra no cache. Troque por uma URL estável,
  `/api/.../{id}/{versao}`, com cache.
- Confira o header que o domínio serve de fato: `curl -sI <url>` e procure `cache-control`.
