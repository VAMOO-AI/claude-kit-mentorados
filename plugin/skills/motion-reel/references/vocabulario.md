# Vocabulário de motion — o que já existe no template

Cada técnica tem um exemplo funcionando em `assets/template/src/scenes.tsx` (Reel), `film-scenes.tsx` (Film) ou `lib.tsx`. Reaproveite
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
| `MarkIn` | o símbolo da marca (`public/marca.png`, o `MOTION_MARK` do `new.sh`) entra com escala e opacidade; caixa fixa com `objectFit: contain`, então qualquer proporção cabe sem esticar; `out` faz sair | abertura e assinatura: é o que a `Intro`, o `Outro`, o `title` e o `outro` usam |
| `shake(f, at, amp, dur)` | tremor que decai | impacto de palavra única |
| `Bg` | fundo + fonte | raiz de toda cena |

## Cenas-modelo (`scenes.tsx`)

| Cena | Técnica | Reuso típico |
|---|---|---|
| `Intro` | partículas (`random(seed)`) convergem para um anel → o símbolo (`MarkIn`) entra com escala → mergulho de câmera no centro | abertura de marca |
| `Grande` | palavra única, letras caem em stagger com escala + blur | 1 palavra de impacto (≤ 7 letras em 226px) |
| `Marquee` (`Atualizacao`, `Performar`) | faixas diagonais de texto vazado correndo em sentidos opostos + tarja sólida central | palavra-tema que precisa "encher a tela" |
| `Mosaic` + `Title` | grade 3D de cards (câmera recua, inclina, volta) → **match cut**: o card central abre até virar a tela | nome de produto/oferta |
| `Models` | cubo 3D (`rotateX` com `preserve-3d`) troca face A → face B; depois resumo em linhas | duas coisas em sequência (modelos, antes/depois, plano A/B) |
| `Hours` | relógio: 60 ticks + ponteiro com rastro + anel de progresso + contador | tempo investido, prazo |
| `Terminals` | parede 3D de janelas acendendo + janela-herói com comando digitado e número | volume de trabalho técnico |
| `Credit` | número + barra-pílula que enche + frase em palavras staggered | porcentagem, consumo, meta |
| `Voce` | smash: flash azul, palavra gigante com blur que assenta, ondas de choque, tremor | clímax depois de uma pausa na música |
| `NoUsoDoClaude` | 3 linhas em máscara, última vazada, sublinhado que se desenha | fechamento da frase principal |
| `Outro` | símbolo (`MarkIn`) entra com escala → logo PNG revelado por `clipPath` → nome, subtítulo, pílula preta de CTA, endereço em mono | assinatura + CTA |

No `timeline.json`, a cena `intro` ou `outro` aceita `"symbol": false` (ex.: `{"id": "outro", "cut": 885, "in": "ink", "d": 16, "symbol": false}`): a `Intro` fica só com o anel e o nome, o `Outro` começa direto pelo logo. Sem a chave, o símbolo aparece.

## Film: cenas responsivas (`film-scenes.tsx`, 16:9 e 9:16)

Escolha pelo `type` no `film.json`; os textos vão em `props`. Toda cena anima em cima das falas
(`bt(p, i)`) e entra com `first(p)`, antes do corte.

| `type` | O que faz | `props` |
|---|---|---|
| `desk` | Claude Code Desktop: pedido digitado antes do corte, enviado, "Trabalhando…", card de arquivos editados, resposta com ✓ no meio da 1ª fala; câmera empurra devagar | `kicker?`, `session?`, `prompt`, `working?`, `files?` `[[arquivo, linhas]]`, `reply` |
| `statement` | frases em máscara, um grupo por fala; o grupo sai quando o próximo entra; última linha vazada | `bg` (`night`/`paper`), `groups` `[{beat, frac?, lines, hollowLast?}]` |
| `title` | o símbolo (`MarkIn`) entra com escala acima do título, letras caem com escala, tremor no corte, inclinação 3D que assenta; subtítulo e pílula na 2ª fala | `line1`, `line2` (vazada), `sub?`, `pill?`, `symbol?` (padrão `true`; `false` tira o símbolo e centraliza o título) |
| `numbers` | um `Counter` por fala; os anteriores esmaecem (linha no 16:9, coluna no 9:16) | `items` `[{v, label}]` |
| `commands` | comandos digitados um a um no Desktop, cada um com resposta ✓; selo na 2ª fala | `line1`, `line2`, `cmds` `[{cmd, reply}]`, `badge?`, `session?` |
| `chapter` | número gigante vazado gira em Y, nome em máscara, linha que varre | `n`, `name`, `count?`, `label?` |
| `card` | item de uma série: nome + o que faz + "antes" riscado + selo de prova; janela do Desktop em 3D com o comando e um motif; régua de progresso embaixo | `n`, `total`, `kicker?`, `name`, `line`, `before?`, `beforeLabel?`, `solved?`, `proof?`, `cmd?`, `motif?`, `dark?`, `session?` |
| `cta` | duas frentes (pergunta + pílula), a 2ª na 2ª fala; comandos em mono embaixo | `q1`, `pill1`, `q2?`, `pill2?`, `cmds?` |
| `outro` | símbolo (`MarkIn`) → logo PNG revelado por `clipPath` → nome e subtítulo; fade no fim | `name`, `sub?`, `logo?` (padrão `logo-dark.png`), `symbol?` (padrão `true`; `false` começa direto pelo logo) |

Utilitários exportados para cena nova: `useL()` (W, H, `v` = vertical, guia `l r t b`), `bt`,
`first`, `fit(linhas, larguraMáx, base, k)`, `H1`, `LABEL`. Moldura de todas: `Breathe` (zoom de
3%), grão de película (`public/grain.png`) e letterbox opcional até a cena-âncora (`letterbox`).

## Claude Code Desktop (`desktop.tsx`)

Para mostrar alguém usando o Claude de verdade, nunca cara de terminal. Peças: `Desk` (janela,
sidebar opcional com sessões; título fora da lista vira a sessão ativa), `Composer` (caixa com
"Automático · Opus 5.5 · Alto", rótulos por props), `UserMsg`, `AsstText`, `Working` (✻ girando),
`EditCard` (arquivos com `+linhas`), `typing(texto, f, at, cps)` e `fadeIn`. Monte a conversa como
filhos do `Desk`, de cima pra baixo; ela fica colada no composer.

## Motifs (`motifs.tsx`): o benefício em imagem

Painel de 680×440 que anima em ~90 frames a partir de `a`. No `film.json`:
`"motif": {"kind": "rows", "title": "...", "items": [...]}`. `kind` desconhecido vira painel com o
nome, visível na folha de QA.

| `kind` | Mostra | Props |
|---|---|---|
| `rows` | checklist que marca item a item | `items`, `title?`, `foot?`, `step?` |
| `chat` | balões alternando (`me` à direita) | `msgs` `[{me?, t}]`, `title?` |
| `pipeline` | etapas em linha acendendo | `gates`, `title?`, `foot?` |
| `lanes` | barras de progresso em paralelo | `labels`, `title?`, `foot?` |
| `branches` | tronco que se divide em 3 | `names`, `title?`, `foot?` |
| `sync` | duas caixas trocando pontos | `left`, `right`, `foot?` |
| `tags` | linhas com selo sim/não | `rows` `[[texto, ok]]`, `yes?`, `no?`, `title?` |
| `scan` | varredura marcando achados | `title?`, `foot?`, `mark?`, `hits?` |
| `doc` | documento que se escreve + selos | `headline`, `chips`, `kind_label?` |
| `pillars` | N colunas enchendo + "k/N" | `label`, `n?`, `accent?`, `title?` |
| `meter` | porcentagem que sobe ou desce | `from`, `to`, `label`, `foot?`, `title?` |
| `split` | barra única dividida em partes | `parts` `[[rótulo, %]]`, `title?` |
| `ceiling` | barras com teto; acima dele apagam | `limit`, `label`, `cut?`, `heights?`, `title?` |
| `steps` | passos numerados + "no ar" pulsando | `steps`, `foot?`, `title?` |
| `graph` | centro com ramos (quem vê o quê) | `hub`, `spokes` `[[nome, detalhe]]` |
| `viewfinder` | visor de câmera com o pedido digitado | `prompt`, `foot?` |
| `develop` | arquivo sendo gerado em faixas | `file`, `done?`, `note?` |
| `timeline` | trilhas de edição com agulha | `title?` |

## Regras de composição (aprendidas nesta peça)

- **Uma ideia por tela, 0,5–1,5 s cada.** Frase de mais de 3 palavras fica ≥ ~1,3 s. No Film, uma ideia por fala, e a animação entra quando a voz diz a coisa.
- **Mesmo roteiro, dois formatos:** o `reel` do `film.json` é um corte do `master` (título, 2–3 cenas fortes, CTA, assinatura), não um roteiro novo.
- Frase longa do briefing vira **beats**: o número grande primeiro, o apoio depois.
- **Paleta do exemplo** (troque em `C`, no `lib.tsx`): papel `#fcfcfc`, ink `#000`, azul `#007dff` (dado), night `#05070a`. Azul sobre night é `#4da3ff`; preenchimento azul com texto branco é `#0063cc`. Alternar fundo claro/escuro marca o ritmo.
- **Mono só em comando/terminal.** Ênfase de título = vazado.
- Nada de gradiente decorativo, glow ou glass. O impacto vem da coreografia: máscara, escala, corte pela borda, câmera 3D, match cut.
- Comando que aparece na tela tem que ser **real** (o público digita o que vê). Busque no README do produto.
- Logo é sempre o PNG oficial da marca, sem esticar (altura manda). Nunca redesenhe o logo em CSS ou SVG.
