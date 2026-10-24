# Front em execução: CPU, animação, render

Carregue quando o número de partida for CPU (`runtime-bench`), long task ou ms por interação.

## Lendo o `runtime-bench`

- **`cpu_main` alto com a página parada:** algo roda sem ninguém pedir. Pode ser loop de
  `requestAnimationFrame`, animação infinita ou intervalo.
- **`style_por_s` na casa das dezenas com a página parada:** alguma animação CSS ou JS
  está ativa (60 é uma por frame). Se é o hero visível, é esperado. Se está fora da tela, é
  custo puro. Com `cpu_main` baixo, não é alvo sozinho: uma tela de login deu ~50/s
  parada com menos de 5% de main thread.
- **`cpu_main` só sobe quando a página rola:** o custo está no scroll. Suspeite de handler
  de scroll ou pointer, `backdrop-filter`, `background-attachment: fixed` ou parallax.
- **mobile (CPU 4×) muito acima do desktop:** o trabalho é proporcional a pixel, como
  canvas em dpr 3 ou blur.
- **`cpu_chrome` muito acima de `cpu_main`:** o custo é de raster, GPU ou compositor, vindo
  de blur, filtro ou camada grande. **No perfil `mobile`, isso só vale acima do piso.** O
  headless compõe por software em dpr 3, e uma página em branco já dá ~78% (macOS).
  Antes de culpar uma camada, rode o bench mobile em `'data:text/html,<p>x</p>'` e compare.
  Num número perto do piso, não há sinal. Um site deu 79–97% em toda fase e todo build, e
  a "onda pesada no celular" de um relatório era só esse piso.
- **`script_ms` da fase "rolando":** inclui o `scrollTo()` que o próprio bench chama a cada
  frame, com o layout que ele força. Num caso, ele dobrou num fix que derrubou a main
  thread em um terço. O profiler mostrou centenas de ms no `scrollTo` e ~10 ms por função
  do app nos dois builds. Na rolagem, compare `cpu_main` e `layouts`. Para atribuir JS ao
  app, use `Profiler.start` e agregue o self time por função.

## Animação e canvas

Vieram de uma landing com canvas e brilhos animados, otimizada "sem mexer no visual". Em
cada linha, o visual não muda.

| Técnica | Por que o visual não muda |
|---|---|
| Um `IntersectionObserver` para o loop de rAF do canvas e marca `.is-offscreen` → `animation-play-state: paused` no CSS. Use um observer compartilhado no módulo, não um por componente. | ninguém vê o que está fora da tela |
| `.cta:not(:hover, :focus-visible) { animation-play-state: paused }` | só vale se o brilho é resposta ao hover. Confira no visual antes. |
| Canvas a 30 fps com compensação de passo: desenha a cada ~33 ms e avança a simulação em `Math.round(elapsed / (1000/60))` passos, com teto de 4 | mesma velocidade com metade dos frames. `ctx.filter = "blur()"` custa por pixel, e o ganho vem de ter menos frames. |
| Loop JS de animação (lib `motion` num texto brilhante) → `@keyframes` CSS | o compositor anima sem a main thread |
| `pointermove` agrupado em `requestAnimationFrame`, com `passive: true`, aplicado só com o elemento visível | um estilo por frame, não um por evento |
| `touch-action: none` num card → `pan-y` | o `none` bloqueava o scroll no celular |
| `content-visibility: auto` + `contain-intrinsic-size: auto 600px` em seção abaixo da dobra | layout e paint pulados fora da tela. Meça: com a página parada pode não mexer. |

**O que não funcionou:** canvas em 1/4 da resolução. O pixel diff estava ok e a CPU ficou
igual, então foi descartado. `background-attachment: fixed` repinta no scroll, mas
trocá-lo muda o visual, e ficou de propósito.

Um caso de site de terceiro mostra a combinação que mais pesa. Um blur grande animado
(`filter: blur(95px)` com `scale`) ficava sob N `backdrop-filter` que liam esse fundo, e
um gradiente era repintado a cada `mousemove`. Resultado: cada movimento do mouse borrava
de novo N camadas. O conserto é parar de animar o blur ou tirar o `backdrop-filter` do que
fica por cima. O kill-switch não pode depender só de `prefers-reduced-motion`.

## Render React

- **Estado alto demais.** O rascunho morava no pai e re-renderizava lista e thread a cada
  tecla. Ele passa a ser estado do componente que digita, e o pai só o espelha num
  `useRef`.
- **`React.memo` que nunca vale:**
  - `Date.now()` no render: vira prop, com um tique por minuto;
  - `useMemo` com o objeto inteiro nas deps: as deps passam a ser só as fatias usadas, tipadas com `Pick<>`.
- **`key` por índice** remonta a linha, e o input perde o foco.
- **Input controlado gravando no banco a cada tecla:** vira não controlado e grava ao
  sair do campo.
- **Trabalho caro a cada tecla:** `useDeferredValue` alivia, mas a causa (remontagem)
  continua lá.
- **Lista longa:** `@tanstack/react-virtual` com `measureElement` e `getItemKey` pelo id.
  Com dnd-kit, o `useDroppable` fica na coluna, não no card. Num kanban, isso levou o
  congelamento ao trocar filtro de dezenas de segundos para menos de 100 ms no pior caso.
- **`AnimatePresence mode="popLayout"`/`layoutId`** mede o `getBoundingClientRect` de
  cada item a cada mudança. Em lista grande, tem de sair.
- **Busca que carrega a lista inteira no cliente e pontua tudo a cada tecla:** passa a ser
  busca no servidor com teto e debounce. Mais em `dados-rede.md`.
- Um **teste que conta renders** segura o ganho: um `ConversationList.memo.test.tsx` que
  conta 1 linha reconciliada em vez de 20.

## Como provar

- `runtime-bench` antes e depois, desktop e mobile, nas mesmas fases.
- Para interação: trace do DevTools (long tasks) ou Playwright com CPU 4×, medindo ms por tecla.
- `layout-snapshot --compare` dando 0 diferenças, mais um screenshot de cada lado para o
  que é cor ou animação.
