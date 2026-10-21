# Transições (`assets/template/src/transitions.tsx`)

Todas são `TransitionPresentation` próprias em DOM, sem shader (os presets `crossZoom`,
`filmBurn` etc. do `@remotion/transitions` dependem de html-in-canvas: não use). Escolha pelo
campo `in` da cena no `timeline.json` (Reel) ou no `film.json` (Film); `d` é a duração em frames
(a transição fica centrada no `cut`). Elas leem o tamanho pelo `useVideoConfig`, então servem
1080×1920 e 1920×1080 sem mudar nada. No Film, cena sem `in` herda a corrente do filme
(`"current"` no `film.json`, padrão `whip`), e `d` sai da
tabela abaixo (`d` na cena sobrescreve); a origem de uma íris vai em `"origin": {"cx", "cy", "color"}`
na cena (sem ela, centro da tela).

| `in` | Visual | `d` típico | Quando | SFX automático |
|---|---|---|---|---|
| `iris` | cena nova abre em círculo com 2 anéis; a antiga empurra câmera | 12–14 | abrir a partir de onde o olho está (centro do logo, do relógio) — defina `ORIGIN` no `Reel.tsx` | whoosh + pop |
| `ink` | igual à íris, com chime | 16 | ir para o fechamento | whoosh + chime |
| `whip` | as duas cenas correm na horizontal com blur direcional | 10 | troca de energia entre palavras | whoosh |
| `whipUp` | idem, vertical | 10 | depois de um impacto | whoosh |
| `push` | vertical, mais suave (blur menor) | 12 | do título para o conteúdo | whoosh |
| `bars` | 8 barras azul/night em cascata cobrem e descobrem | 16–18 | mudança de seção | paper-tap + whoosh |
| `glitch` | fatias deslocadas + riscos azuis/brancos | 10 | entrar em algo técnico/digital | cliques |
| `panel` | dois painéis em chanfro (azul e night) varrem | 18 | mudança de fundo escuro → claro | whoosh |
| `spin` | as duas cenas giram no mesmo sentido com escala e blur | 12 | virada de frase | whoosh |
| `echo` | as duas cenas correm na horizontal com dois ecos atrasados e apagados (rastro), sem blur | 12 | sequência rápida de frases sem corte seco (lançamento de app) | whoosh + pop |
| `cut` | corte seco (`d: 0`) | 0 | **match cut** (mosaico → título) e **smash cut** depois de riser | — |

## Regras

- **O meio da transição cai na batida.** Com 120 BPM a 30 fps, `cut` é múltiplo de 15; o `qa.sh` avisa no Reel, e no Film o `build-timeline.py` arredonda cada cena para cima até a batida.
- **Repita a corrente; varie só com motivo.** Uma transição dominante para 60 a 70 % das trocas, sempre na mesma direção (no Film, o `current`). Uma ou duas reservadas, gastas com significado: `ink`/`iris` = fechamento, `whipUp` = conclusão que sobe, `cut` = match ou smash cut. Nada de trocar de eixo a cada cena sem causa visível (doutrina de motion, regra 6, no `vocabulario.md`).
- A cena de entrada já está rodando durante a transição, com `f < 0`. Se ela começar vazia, a transição revela um fundo liso. Faça a cena já ter conteúdo em `f` negativo (ex.: `Terminals` começa com 40% das janelas). No Film, o primeiro elemento de toda cena entra em `first(p)` (`min(fala0 − 6, −8)`), e cena nova faz o mesmo.
- Transição que deforma a cena (`glitch` em fatias, `spin` com rotate/blur) devolve os filhos intactos quando o progresso está em 0 ou 1: o Remotion mantém a cena envolvida pela apresentação antes e depois da troca, e fatias ou `blur(0)` paradas deixam emenda de 1 px. `echo` segue a mesma guarda, e transição nova também (`p <= 0.001 || p >= 0.999`).
- Transições que escondem a troca atrás de um painel (`bars`, `panel`) trocam a cena exatamente em `p = 0.5`: o painel tem que cobrir 100% nesse instante.
- `Breathe` (zoom lento de 3,5% no Reel, 3% no Film): no Reel envolve toda cena; no Film só o `outro` e o `logo3d` por padrão, e outra cena com `props.breathe: true` (regra 7 da doutrina). Nunca nas duas pontas de um match cut (`breathe: false`): senão a escala não bate e o corte pula.
- Blur direcional vem de um filtro SVG (`feGaussianBlur stdDeviation="x 0"`), não do CSS `blur()`, que é igual em todos os eixos.
