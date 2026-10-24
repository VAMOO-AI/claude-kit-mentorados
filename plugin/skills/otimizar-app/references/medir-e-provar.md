# Medir e provar

## Scripts desta skill

Precisam de Node 22+ (WebSocket nativo) e do Chrome. **Zero npm install.** O Chrome é
procurado no caminho padrão do macOS e em `google-chrome`/`chromium`; em outro lugar, passe
`CHROME=/caminho/do/chrome`. No Claude Code, o Chrome headless precisa rodar fora do sandbox.

```bash
# CPU por fase (parado no topo, rolando, parado no meio), mediana de 3 runs
node "${CLAUDE_PLUGIN_ROOT}/skills/otimizar-app/scripts/runtime-bench.mjs" https://dominio desktop --runs 3 > antes-desktop.json
node "${CLAUDE_PLUGIN_ROOT}/skills/otimizar-app/scripts/runtime-bench.mjs" https://dominio mobile  --runs 3 > antes-mobile.json

# estrutura da página, antes e depois do fix
node "${CLAUDE_PLUGIN_ROOT}/skills/otimizar-app/scripts/layout-snapshot.mjs" https://dominio mobile > lay-antes-mobile.json
node "${CLAUDE_PLUGIN_ROOT}/skills/otimizar-app/scripts/layout-snapshot.mjs" --compare lay-antes-mobile.json lay-depois-mobile.json
```

- **Perfis.**
  - `desktop`: 1440×900, dpr 1.
  - `mobile`: 390×844, dpr 3, toque e **CPU 4× mais lenta**, que é o celular médio do cliente.
  - Meça os dois: numa landing com canvas animado, rolando a página, o mobile gastava
    três vezes a CPU do desktop.
- **Campos do `runtime-bench`:** o significado de cada campo está em `front-runtime.md`.
  O `cpu_chrome` vem do `ps`; no Linux a resolução é de 1 s, então use `--segundos 20`.
  Dois campos enganam:
  - O `cpu_chrome` mobile tem piso de ~78% numa página em branco.
  - O `script_ms` da rolagem conta o `scrollTo` do próprio bench.

  Os dois estão em `front-runtime.md`. Meça o piso antes de atribuir pintura ao site.
- **`layout-snapshot`.**
  - Mede o layout sem transform e força `content-visibility: visible`. Sem isso, a caixa
    fora da tela saía 0×0 em 1 de 3 runs.
  - Desliga o `setInterval`, para o carrossel com autoplay não virar diferença.
  - Validado assim: 3 runs da mesma página deram 0 diferenças, e um bloco de 150px
    inserido foi acusado. Numa SPA Vite com GSAP, 2 runs deram 0 diferenças no desktop e
    no mobile.
- **Alvo.** O preview protegido da Vercel não abre no headless. Meça em prod ou no build
  de produção local (`vite build && vite preview`, `next build && next start`), nunca em
  `dev`. Compare sempre o mesmo tipo de alvo.
- **Atrás de login os scripts não medem:** abrem a página sem sessão e caem na tela de
  entrada. Diga que a tela logada ficou sem número.
- Os scripts servem para página. Para medir banco, TTFB ou bundle, use as receitas abaixo.

## Outras medidas

- **Web Vitals:**

  ```bash
  npx -y lighthouse@12.8.2 <url> --only-categories=performance --chrome-flags=--headless=new --output=json --output-path=lh.json
  ```

  Nota 99 quer dizer que não há o que otimizar ali; vá atrás do sintoma real.
- **TTFB com amostra que aguenta comparação:** n ≥ 30, reportando mediana, p95 e desvio.

  ```bash
  for i in $(seq 30); do curl -s -o /dev/null -w '%{time_starttransfer}\n' <url>; done | sort -n
  ```

  A mediana fica entre a 15ª e a 16ª linha, e o p95 na 29ª.
- **Bytes e compressão por asset:**

  ```bash
  curl -s -o /dev/null -H 'Accept-Encoding: gzip, br' -w '%{size_download} %{content_type}\n' <url>
  ```
- **Interação (digitação, filtro):** Playwright ou trace do DevTools com
  `Emulation.setCPUThrottlingRate` em 4, medindo ms por tecla com volumes diferentes de
  dado. Rode o Playwright com `npx`, sem instalar no projeto.
- **Banco:** delta de `pg_stat_statements` e `explain (analyze, buffers)`, no pilar 05 da
  `baseline` (`${CLAUDE_PLUGIN_ROOT}/skills/baseline/references/05-carga.md`).
- **Banco em escala sem encostar em prod.** Quando Preview e Production dividem o mesmo
  projeto Supabase, carga "no preview" é carga em prod. Suba um Postgres descartável em
  Docker, aplique um shim mínimo do Supabase (roles, schema `auth`, `auth.uid()`), rode
  **todas** as migrations na ordem real, gere a massa com `generate_series` e meça cada
  situação com a mesma massa.
  - Num SaaS multi-tenant, com centenas de empresas e dezenas de milhares de pessoas, a
    função de RLS antiga, a nova e a nova durante uma visão deram o mesmo tempo por ciclo,
    dentro do ruído. O plano (`Bitmap Index Scan … Index Cond: (empresa_id = f())`) mostrou
    por quê.
  - Versione a massa junto com o harness, senão o número não se reproduz.

## Estatística que não mente

- A mesma ferramenta, o mesmo perfil, o mesmo alvo e o mesmo n, antes e depois.
- Use a mediana, nunca uma run só. Diferença menor que o desvio é ruído.
- **Não some ramos paralelos** como se fossem sequenciais. Uma estimativa de ganho de
  "−600 a −1.500 ms" caiu por isso.
- Declare o que não foi medido.

## Armadilhas do próprio instrumento

- **Soma dentro de `| while read`** roda num subshell, e o total sai zerado.
- **`wc -c` no macOS** devolve espaços à esquerda e quebra a aritmética: use `$(( $(wc -c < arquivo) ))`.
- **Nome de arquivo com espaço** quebra `for f in $(ls)`. Use glob ou `find -print0`.
- **`du` com vários argumentos** soma o que você não queria somar.
- **`curl -H 'Host: x'`** manda o SNI errado. Use `--resolve x:443:<ip>`.
- **Chunk que não existe** devolve 200 com `text/html`, o fallback da SPA. Cheque o
  `content_type` antes de dizer que o arquivo está lá.
- **"TypeScript: No errors found"** sem `node_modules` é falso verde, porque o tsc nem
  rodou. Isso inclui saída filtrada por proxy de CLI.
- **`pg_isready` no `postgres:16` do Docker** responde OK durante o bootstrap, que sobe,
  roda o init e reinicia. Espere conectando de fora (`psql -c 'select 1'` em loop), que é
  como o teste vai conectar.
- **Teste SQL que procura só a própria string de falha** deixa um `ERROR` do Postgres
  passar como verde, e o teste para de valer sem avisar. Procure pelas duas.

## Provar que chegou ao ar

1. Ache o bundle servido e procure uma string única do fix:

   ```bash
   curl -s https://dominio/ | grep -o 'assets/index-[^"]*\.js'
   curl -s https://dominio/assets/index-<hash>.js | grep -c '<string-do-fix>'
   ```
2. Para imagens e assets, o `size_download` servido tem de bater com o arquivo local
   otimizado, um por um.
3. Para região: `curl -sI <url> | grep -i x-vercel-id` tem de mostrar `gru1::gru1` (ou a
   região do seu banco nos dois lados).
4. **Deploy BLOCKED** porque o autor do commit não está no time da Vercel, ou
   `.vercel/project.json` apontando para outro projeto: vá pela `ship` (e pelo
   `.context/docs/deploy.md` do projeto, se existir). O token vai só por env, nunca como
   `--token=` na linha de comando, porque o erro imprime o valor no log.
