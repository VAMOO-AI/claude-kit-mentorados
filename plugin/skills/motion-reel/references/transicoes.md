# Transições (`assets/template/src/transitions.tsx`)

Todas são `TransitionPresentation` próprias em DOM, sem shader (os presets `crossZoom`,
`filmBurn` etc. do `@remotion/transitions` dependem de html-in-canvas: não use). Escolha pelo
campo `in` da cena no `timeline.json`; `d` é a duração em frames (a transição fica centrada no `cut`).

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
| `cut` | corte seco (`d: 0`) | 0 | **match cut** (mosaico → título) e **smash cut** depois de riser | — |

## Regras

- **O meio da transição cai na batida.** Com 120 BPM a 30 fps, `cut` é múltiplo de 15; o `qa.sh` avisa.
- Não repita a mesma transição em sequência. Varie o eixo: horizontal → cascata → vertical → íris.
- A cena de entrada já está rodando durante a transição, com `f < 0`. Se ela começar vazia, a transição revela um fundo liso. Faça a cena já ter conteúdo em `f` negativo (ex.: `Terminals` começa com 40% das janelas).
- Transições que escondem a troca atrás de um painel (`bars`, `panel`) trocam a cena exatamente em `p = 0.5`: o painel tem que cobrir 100% nesse instante.
- `Breathe` (zoom lento de 3,5%) envolve toda cena, **exceto** as duas pontas de um match cut: senão a escala não bate e o corte pula.
- Blur direcional vem de um filtro SVG (`feGaussianBlur stdDeviation="x 0"`), não do CSS `blur()`, que é igual em todos os eixos.
