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
| `Voce` | smash: flash na cor da marca, palavra gigante com blur que assenta, ondas de choque, tremor | clímax depois de uma pausa na música |
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

### Presets (lançamento, vidro e logo 3D)

Cenas como as de cima (`type` no `film.json`), feitas para abrir ou fechar uma peça. Sem fala, o
ritmo é da trilha: o elemento i cai na batida i·`step` (15 frames = 1 batida a 120 BPM, a grade do
`track_cinema.py`); com fala, cai na fala i. Todas têm som próprio no `SFX_BY_TYPE` e pintam com a
paleta `C` do `lib.tsx`: trocou a paleta, os presets trocam junto.

| `type` | O que faz | Quando usar | `props` |
|---|---|---|---|
| `launch` | palavras do título batem uma por batida, alternando sólida e vazada, com tremor e régua de batidas; uma batida de pausa, uma fenda de luz abre a tela clara e o nome do produto entra com o espaçamento fechando | abertura de lançamento; 2–4 palavras curtas | `words`, `name`, `tag?`, `kicker?`, `step?` (padrão 15) |
| `beats` | um benefício por batida: a cor seguinte da paleta (`accentFill`, `night`, `paper`) varre a tela e a palavra sobe com um soco de escala; contador `01 / 03` | as 3 batidas de benefício depois da revelação; 1–3 palavras por item | `items`, `kicker?`, `step?` (padrão 30) |
| `glass` | painéis de vidro sobre um fundo com estrutura (anéis nas cores da paleta, grade, palavra grande): dentro do painel o fundo aparece ampliado e deslocado (`feDisplacementMap`), com borda acesa e brilho que atravessa na entrada; número conta, texto fica | 1–3 números ou frases curtas que precisam de destaque; uma cena por peça | `title?`, `cards` `[{value, label}]`, `word?` (palavra do fundo), `step?` (padrão 15) |
| `logo3d` | o símbolo da pessoa (`public/marca.png`, o `--mark` do `new.sh`) extrudado em camadas, girando e assentando numa pose com ângulo residual, com brilho preso ao ângulo, luz na cor da marca atrás e reflexo no chão; nome e subtítulo depois da pose; fade se for a última cena | assinatura no fim (no lugar do `outro`) ou vinheta de marca | `mark?` (padrão `marca.png`), `name?` (padrão `BRAND`), `sub?`, `turns?` (padrão 1), `settle?` (frame da pose, padrão 60) |

O **filme de lançamento** pronto é `presets/lancamento.json`: `launch` → `beats` → `glass` → `logo3d`,
~15 s, o `reel` é o corte 9:16 com as mesmas cenas. Para usar: `cp presets/lancamento.json film.json`,
troque os textos de exemplo ("Seu Produto", os números) pelos da pessoa e rode o `qa.sh`
(`Master169` e `Reel916`). Com narração, ponha as falas em `vo` e a animação passa a cair nelas.

- O logo 3D não redesenha a marca: empilha o PNG, na proporção que ele tiver. Sem `--mark` no `new.sh`, sai o placeholder "SUA MARCA" e isso vai no `PENDENTE:`. O `filter` fica só na `Img` de cada camada; no nó `preserve-3d` ele achata o 3D.
- O vidro é desenhado, não `backdrop-filter`: dentro de uma transição o que o backdrop amostra muda. Sobre fundo liso a refração some; o `glass` traz o próprio fundo. Texto vazado sobre o vidro deixa o fill aparecer: o texto ali é sólido.
- Clipe curto (~6 s) só com o `logo3d`: o `mark: "finale"` pode empurrar o integrado para fora do alvo e o `final.sh` reprova. Em peça curta, tire o `mark` e deixe o som próprio da cena.

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
- **Paleta do exemplo** (troque em `C`, no `lib.tsx`, ou com `--cor` e `--cor-escura` no `new.sh`): papel `#fcfcfc`, ink `#000`, grafite `#3f3f46` (acento sobre fundo claro), night `#05070a`. Grafite claro sobre night é `#d4d4d8`; preenchimento escuro com texto branco é `#18181b`. Alternar fundo claro/escuro marca o ritmo.
- **Mono só em comando/terminal.** Ênfase de título = vazado.
- Nada de gradiente decorativo, glow ou glass. O impacto vem da coreografia: máscara, escala, corte pela borda, câmera 3D, match cut. Exceção: os presets `glass` e `logo3d` (acima) usam vidro, luz e reflexo por escolha; no máximo uma cena de cada por peça.
- Comando que aparece na tela tem que ser **real** (o público digita o que vê). Busque no README do produto.
- Logo é sempre o PNG oficial da marca, sem esticar (altura manda). Nunca redesenhe o logo em CSS ou SVG.
