# Vocabulário de motion — o que já existe no template

Cada técnica tem um exemplo funcionando em `assets/template/src/scenes.tsx` ou `lib.tsx`. Reaproveite
copiando e mudando o texto, não reescrevendo do zero.

## Primitivas (`lib.tsx`)

| Peça | O que faz | Quando usar |
|---|---|---|
| `ip(f, [a,b], [x,y], ease?)` | interpolate com clamp e `EASE` da casa (`cubic-bezier(.22,1,.36,1)`) | toda animação |
| `useF()` | frame local da cena já descontado o `lead` da transição de entrada: **f = 0 é o corte na batida** | sempre, no lugar de `useCurrentFrame()` dentro de cena |
| `MaskUp` | texto sobe de dentro de uma janela `overflow: hidden`; `out` faz sair para cima | toda entrada de texto — é o tique mais "profissional" da peça |
| `Counter` | inteiro interpolado até o valor, formatado em pt-BR (`2.700`), largura reservada | contagem, porcentagem, horas |
| `Odometer` | dígitos rolam em coluna até o valor; `spins` = voltas extras | versão ou código (`5.5`); em contagem o meio passa do alvo |
| `hollow(cor, px, fundo)` | texto vazado (`-webkit-text-stroke` + `paint-order`); `fundo` = cor sólida atrás do texto | a ênfase de título da casa (nunca itálico/cor) |
| `lemniscatePath` / `lemniscatePoint` | o infinito em SVG, para `evolvePath` desenhar | motivo do exemplo em movimento; troque pelo traço da sua marca (o logo que fica é sempre o PNG) |
| `shake(f, at, amp, dur)` | tremor que decai | impacto de palavra única |
| `Bg` | fundo + fonte | raiz de toda cena |

## Cenas-modelo (`scenes.tsx`)

| Cena | Técnica | Reuso típico |
|---|---|---|
| `Intro` | partículas (`random(seed)`) convergem para um traço que se desenha → cross para o logo PNG → mergulho de câmera no cruzamento | abertura de marca |
| `Grande` | palavra única, letras caem em stagger com escala + blur | 1 palavra de impacto (≤ 7 letras em 226px) |
| `Marquee` (`Atualizacao`, `Performar`) | faixas diagonais de texto vazado correndo em sentidos opostos + tarja sólida central | palavra-tema que precisa "encher a tela" |
| `Mosaic` + `Title` | grade 3D de cards (câmera recua, inclina, volta) → **match cut**: o card central abre até virar a tela | nome de produto/oferta |
| `Models` | cubo 3D (`rotateX` com `preserve-3d`) troca face A → face B; depois resumo em linhas | duas coisas em sequência (modelos, antes/depois, plano A/B) |
| `Hours` | relógio: 60 ticks + ponteiro com rastro + anel de progresso + contador | tempo investido, prazo |
| `Terminals` | parede 3D de janelas acendendo + janela-herói com comando digitado e número | volume de trabalho técnico |
| `Credit` | número + barra-pílula que enche + frase em palavras staggered | porcentagem, consumo, meta |
| `Voce` | smash: flash azul, palavra gigante com blur que assenta, ondas de choque, tremor | clímax depois de uma pausa na música |
| `NoUsoDoClaude` | 3 linhas em máscara, última vazada, sublinhado que se desenha | fechamento da frase principal |
| `Outro` | infinito se desenha → logo PNG revelado por `clipPath` → nome, subtítulo, pílula preta de CTA, comando em mono | assinatura + CTA |

## Regras de composição (aprendidas nesta peça)

- **Uma ideia por tela, 0,5–1,5 s cada.** Frase de mais de 3 palavras fica ≥ ~1,3 s.
- Frase longa do briefing vira **beats**: o número grande primeiro, o apoio depois.
- **Paleta do exemplo** (troque em `C`, no `lib.tsx`): papel `#fcfcfc`, ink `#000`, azul `#007dff` (dado), night `#05070a`. Azul sobre night é `#4da3ff`; preenchimento azul com texto branco é `#0063cc`. Alternar fundo claro/escuro marca o ritmo.
- **Mono só em comando/terminal.** Ênfase de título = vazado.
- Nada de gradiente decorativo, glow ou glass. O impacto vem da coreografia: máscara, escala, corte pela borda, câmera 3D, match cut.
- Comando que aparece na tela tem que ser **real** (o público digita o que vê). Busque no README do produto.
- Logo é sempre o PNG oficial da marca, sem esticar (altura manda). Nunca redesenhe o logo em CSS ou SVG.
