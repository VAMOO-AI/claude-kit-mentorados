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
| `desk` | Claude Code Desktop: pedido digitado antes do corte, enviado, "Trabalhando…", card de arquivos editados, resposta com ✓ no meio da 1ª fala; câmera empurra devagar | `kicker?`, `session?`, `prompt`, `working?`, `files?` `[[arquivo, linhas]]`, `reply`, `click?` (cursor clica no enviar) |
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

### Presets de apresentação pessoal e lançamento de app

Mesmo molde dos de cima, em arquivo próprio (`scenes-apresentacao.tsx`, `scenes-app.tsx`). Texto com
`*palavra*` marca a ênfase: no de apresentação ela sai em itálico serifado no acento de conteúdo (`SERIF`
e `C.hot`, no `lib.tsx`); no de app, no acento de conteúdo na fonte da marca.

| `type` | O que faz | Quando usar | `props` |
|---|---|---|---|
| `pillname` | uma linha corta a tela, engrossa em pílula e encolhe num anel que vira o primeiro "o" do nome; as letras nascem do anel para fora, cargo embaixo | abertura de apresentação pessoal; nome sem "o" ganha o anel na frente | `name`, `role?`, `kicker?` |
| `orbit` | a foto abre num círculo, um texto gira em volta dela, a frase entra palavra a palavra com a palavra marcada em itálico; fundo na cor de destaque | quem é a pessoa, em uma frase | `photo?` (em `public/`; sem foto, iniciais), `name?`, `ring`, `quote` |
| `highlights` | um destaque por batida: anel (ou barra) que enche enquanto o número conta | 1–3 números da pessoa ou do produto | `title?`, `items` `[{v, label, prefix?, suffix?, of?, kind?}]`, `step?` |
| `follow` | cartão de perfil (foto, nome, @) e a chamada; o cursor clica e o botão vira "Seguindo ✓"; some no fim se for a última | CTA de seguir | `name`, `handle`, `photo?`, `cta`, `button?`, `done?`, `click?` |
| `appline` | headline palavra por palavra com rastro (echo trail) e o mockup da UI da frase (um motif) entrando com rastro; régua `01 / 05` | uma frase de benefício por cena, em sequência com `in: "echo"` | `line`, `ui` `{kind, ...}`, `n?`, `total?`, `kicker?`, `dark?` |
| `assemble` | peças nas cores da marca voam de fora e pousam numa grade com a forma do logo (lida do alfa do PNG); o PNG assume, nome e tagline sobem | fechamento de lançamento de app | `logo?` (padrão `marca.png`), `name?`, `tag?`, `cols?`, `land?` |

A **apresentação pessoal** pronta é `presets/apresentacao.json` (15 s, `iris` e `panel` alternando
fundo escuro e cor de destaque); o **lançamento de app** é `presets/lancamento-app.json` (30 s,
`logo3d` de abertura, 5 `appline` com `echo`, `assemble`). Mesmo uso do lançamento: `cp` para
`film.json`, troque os textos de exemplo ("Seu Nome", "@seunome", os números) pelos da pessoa (e
`photo`, `logo`) e rode o `qa.sh`.

- Foto e logo ficam em `public/`. Sem `photo` a cena não renderiza `<Img>` (arquivo ausente derruba o render): mostra as iniciais.
- O itálico serifado é a Instrument Serif Italic (OFL, `assets/fonts/` da skill), que o `new.sh` copia para `public/serif-italic.ttf` e o `useFont` carrega; com a serifada da marca da pessoa, passe `--serif <ttf>` no `new.sh`. A palavra marcada sai no acento de conteúdo (`C.hot`; no exemplo, laranja `#ee591b`: troque pela cor de acento da marca) sobre escuro e claro, e em night sobre o azul de destaque (acento quente no azul não tem contraste). O acento nunca vai em dado (azul) nem em CTA (pílula preta).

### Cenas avulsas (`scenes-extras.tsx` e `scenes-mapa.tsx`)

Cenas sem preset próprio: entram em qualquer `film.json` pelo `type`, com som no `SFX_BY_TYPE` e
exemplo na galeria (`EXEMPLOS` do `galeria.py`). Seguem a doutrina: um foco por vez, saída mais
curta que a entrada e overshoot só no que chega com velocidade (regra 5).

| `type` | O que faz | Quando usar | `props` |
|---|---|---|---|
| `ranking` | posições de baixo para cima: cada linha entra com a barra crescendo e o número contando (pousa com `SETTLE`), e a anterior esmaece; o 1º entra por último com antecipação, overshoot de escala, hit-stop de 3 quadros e a barra na cor de dado (`C.brand`) | "quem ganha", onde o tempo ou o dinheiro vai, top 3 a 6 (número só com fonte) | `items` `[{label, v, prefix?, suffix?}]` (a ordem sai do `v`), `title?`, `kicker?`, `step?` (padrão 15), `low?` (menor é melhor) |
| `versus` | dois lados lado a lado (também no 9:16): a coluna da esquerda cresce com o número contando, depois a da direita; no veredito o melhor ganha a cor de dado e o selo aparece e assenta sem passar do alvo, o outro esmaece | antes e depois, nós contra o jeito antigo, plano A contra B (número só com fonte) | `left`, `right` `{label, v, prefix?, suffix?}`, `title?`, `kicker?`, `low?` (menor é melhor), `badge?` (padrão `melhor`), `step?` (padrão 30); com fala: esquerda na 1ª, direita na 2ª, veredito na 3ª |
| `map` | mapa-múndi do Natural Earth (domínio público, `world-atlas` 110m) com a câmera assentando de longe para perto no enquadramento da região e das paradas; a região acende na cor de destaque; a rota se desenha trecho a trecho em arco de círculo máximo, cada parada acende quando a linha chega e o nome entra 4 quadros depois; a última acende e pulsa | de onde para onde (entrega, expansão, viagem, cliente em outra cidade), "estamos aqui" | `route` `[{name?, at: [lon, lat]}]` (2–6), `region?` (nome em inglês, como no Natural Earth: `Brazil`), `title?`, `kicker?`, `seg?` (frames por trecho, padrão 24) |
| `morph` | uma caixa só morfa de estado em estado (círculo, pílula, losango, cartão, coluna, quadrado, barra): largura, altura, canto, giro e cor somam uma mola por troca, então a troca nova parte de onde a anterior estiver; a palavra do estado entra depois da caixa assentar e sai antes da próxima; com `loop`, volta à 1ª forma e o fim casa com o começo | etapas de um processo, fases, "uma coisa que vira outra" (2–8 estados, uma palavra cada) | `states` `[{label, shape? (0–7), color? (brand/fill/light)}]`, `kicker?`, `step?` (padrão 30), `loop?` (padrão `true`) |
| `swap` | a frase A entra letra a letra; na troca, um portal em SVG (elipses em arame) abre embaixo da linha e cada letra de A voa por ele até o lugar dela em B, medido na fonte real; letra que sobra mergulha no portal, letra que falta nasce dele e pousa com overshoot | virada de ideia em duas frases curtas ("Ideia solta" → "Plano pronto"), antes e depois, nome antigo e novo | `from`, `to`, `kicker?`, `bg?` (`night`/`paper`), `at?` (frame da troca; padrão: a 2ª fala, ou 45) |

- O `swap` mede a posição de cada letra no layout real (régua invisível com a mesma fonte, depois do `fontesProntas()` do `lib.tsx`), não pelo `fit()`. Frase com mais de 16 caracteres quebra em duas linhas.
- **Motion blur real (`motionBlur`).** `"motionBlur": true` no topo do `film.json` (ou `{"samples": 2–16, "shutter": 1–360}`; `true` = 8 e 180°) liga o `CameraMotionBlur` do `@remotion/motion-blur` só nos quadros das transições rápidas (`whip`, `whipUp`, `push`, `spin`), e o blur desenhado delas cai pela metade: sozinhas, 8 amostras deixam cópias em degrau no pico do `whip`, e a metade do desenhado preenche os degraus. Cada quadro da troca vira `samples` renders somados: no filme de exemplo (45 s, cinco trocas rápidas) o render cheio passou de 114 s para mais que o dobro. O ganho é sutil (rastro contínuo na borda que corre): ligue em peça curta com troca rápida no centro da cena, não por padrão. Áudio, grão e letterbox ficam fora da soma.
- Letras iguais (sem diferenciar maiúscula) viram par; quanto mais letras em comum, mais a troca lê como a mesma palavra se rearrumando.

Utilitários exportados para cena nova: `useL()` (W, H, `v` = vertical, guia `l r t b`), `bt`,
`first`, `fit(linhas, larguraMáx, base, k)`, `H1`, `LABEL`. Moldura: `Breathe` (zoom de
3%, só no `outro`/`logo3d` ou com `props.breathe`, regra 7 da doutrina), grão de película (`public/grain.png`) e letterbox opcional até a cena-âncora (`letterbox`).

## Claude Code Desktop (`desktop.tsx`)

Para mostrar alguém usando o Claude de verdade, nunca cara de terminal. Peças: `Desk` (janela,
sidebar opcional com sessões; título fora da lista vira a sessão ativa), `Composer` (caixa com
"Automático · Opus 5.5 · Alto", rótulos por props), `UserMsg`, `AsstText`, `Working` (✻ girando),
`EditCard` (arquivos com `+linhas`), `typing(texto, f, at, cps)` e `fadeIn`. Monte a conversa como
filhos do `Desk`, de cima pra baixo; ela fica colada no composer.

**Cursor e cliques.** `Cursor` viaja numa curva de Bézier em `trip` quadros (15–21, ou seja 500–700 ms),
aperta a 85% no quadro `at` (2 quadros para baixo, 6 para assentar: snap, then hold) e solta uma onda
de 9 quadros (300 ms) no ponto do clique; some em 6 quadros depois de `hide`. Ponha no `overlay` do
`Desk` (coordenadas da janela) e mire com `sendButton(w, h, pad, scale)`. O `Composer` com `busy`
troca a seta pelo quadrado de parar, como o app faz enquanto trabalha. No `desk`, `click: true` liga
tudo isso: o clique cai 1 quadro antes do envio, com o `soft-click` no `sfx_desk`.

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
- **Paleta do exemplo** (troque em `C`, no `lib.tsx`): papel `#fcfcfc`, ink `#000`, azul `#007dff` (dado), night `#05070a`; laranja `#ee591b` (`hot`) só como acento de conteúdo. Azul sobre night é `#4da3ff`; preenchimento azul com texto branco é `#0063cc`. Alternar fundo claro/escuro marca o ritmo.
- **Mono só em comando/terminal.** Ênfase de título = vazado (o preset de apresentação é a exceção: itálico serifado colorido numa palavra).
- Nada de gradiente decorativo, glow ou glass. O impacto vem da coreografia: máscara, escala, corte pela borda, câmera 3D, match cut. Exceção: os presets `glass` e `logo3d` (acima) usam vidro, luz e reflexo por escolha; no máximo uma cena de cada por peça.
- Comando que aparece na tela tem que ser **real** (o público digita o que vê). Busque no README do produto.
- Logo é sempre o PNG oficial da marca, sem esticar (altura manda). Nunca redesenhe o logo em CSS ou SVG.

## Explicativo de negócio (`presets/explicativo.json`)

Filme pronto de ~20 s, sem voz, na batida, 16:9 + corte 9:16, só com cenas que já existem: `statement`
(o problema) → `title` (o que você faz) → `beats` (como funciona em 3 passos) → `glass` (uma prova:
o número num cartão e a fonte no outro) → `logo3d` (o nome). É o exemplo resolvido do `briefing-motion.md`.
Mesmo uso dos outros: `cp presets/explicativo.json film.json`, troque os textos e o número (com a
fonte da pessoa) e rode o `qa.sh` (`Master169` e `Reel916`). Sem voz, o `title` não mostra `sub` nem
`pill`; com narração, ponha as falas em `vo` e a animação passa a cair nelas.

## Glossário reverso: nome do efeito → onde está no template

Quando a pessoa (ou uma referência) diz o nome do efeito, ache aqui a peça que já faz. A chave é o
efeito; o que pôr em cada tipo de conteúdo é o "Mapa conteúdo → cena" do `briefing-motion.md`.

| Efeito | Onde está |
|---|---|
| stagger (cascata) | letras do `title` (Film) e do `Grande` (Reel); linhas do `statement`, no tempo da fala com `lineFracs` |
| mask reveal | `MaskUp` (`lib.tsx`): o texto sobe de dentro de uma janela |
| clip-path reveal | logo do `outro` (Film) e do `Outro` (Reel), aberto por `clipPath` depois do símbolo |
| line drawing | `evolvePath` (`@remotion/paths`): as órbitas que se desenham em volta do cubo do `Models` |
| number ticker | `Counter` (contagem que pousa) e `Odometer` (dígitos que rolam), no `lib.tsx` |
| morph | cena `morph` (`MorphShape`): uma forma só que vira a próxima |
| text morph | cena `swap` (`LetterSwap`): as letras de uma frase viajam até a outra |
| match cut | `Mosaic` → `Title` (Reel): o card central abre até virar a tela |
| typewriter | `typing()` (`desktop.tsx`), no `desk`, no `commands` e no `card` |
| 3D flip | `Models` (Reel): cubo em `rotateX` troca a face A pela B |
| ripple | onda do `Cursor` no clique (`desktop.tsx`) |
| anticipation | `ANTIC` (`lib.tsx`): o foco do `numbers` e o 1º do `ranking` recuam antes de ir |
| marquee | `Marquee` (`scenes.tsx`), por trás das cenas `atualizacao` e `performar` do Reel |
| orbit | cena `orbit` (texto girando em volta da foto, preset de apresentação); o `Orbit` interno do `Models` |
| shake | `shake()` (`lib.tsx`): o tremor do `title`, do `launch`, do `logo3d` e do `Voce` |

Lacunas, sem cena no template: before/after slider, parallax, follow-through, squash & stretch e
skeleton. Se a peça pedir uma delas, é cena nova (passo 6 do `SKILL.md`).

Regras de motion de interface que **não** valem aqui (não "corrija" o template por elas):
- **"Nunca ease-in".** Em UI, a resposta ao clique não pode demorar a começar. Aqui a saída acelera
  de propósito: `EXIT` no fade final e `EASE_IN` na saída do `MaskUp` (regra 2 da doutrina).
- **"Sair pelo mesmo caminho que entrou".** O `MaskUp` entra de baixo e sai por cima, e a corrente
  de transição corre num sentido só (regra 6).

Nomes dos efeitos e perguntas de revisão (passo 7 do `SKILL.md`): ideias reescritas de
`emilkowalski/skills` (`animation-vocabulary`, `review-animations`), Copyright (c) 2026 Emil
Kowalski, MIT.

## Doutrina de motion (padrão do template desde 20/10/2026)

Regras que dirigem o movimento. O filme de teste foi comparado nas duas versões (a anterior e a
com a doutrina) e a com a doutrina virou o padrão, **sem cor de foco no clímax**: o foco é só
movimento, o número continua na cor do texto. Tempos a 30 fps (1 quadro ≈ 33 ms). Filme antigo continua
renderizando: os campos novos são opcionais; o que muda sem pedir é o `Breathe` (só no fim), a
corrente de transição no lugar do ciclo, os tempos de `Pill`, `Card`, `Cta` e `Outro`, e a contagem do
`Numbers` (fora do foco, 18 quadros com `SETTLE`; eram 22 com `EASE`). Em 21/10/2026, depois de outro
filme A/B, ele adotou também o overshoot só no que chega com velocidade (regra 5) e o desfoque na
troca no mesmo lugar (regra 9).

1. **Um foco por vez.** Só um elemento faz o movimento principal; o apoio entra 4 a 14 quadros
   depois (130 a 470 ms), nunca junto. O que já foi dito esmaece para 35 % ou menos (o `numbers`
   faz). No `card`, a janela do Desktop entra 10 quadros depois do nome.
2. **Saída mais curta que a entrada.** A saída dura cerca de 75 % da entrada e acelera (`EXIT`). O
   `MaskUp` entra em 14 quadros e sai em 10; o fade do `outro` é de 16 quadros com `EXIT`. Entre
   cenas, a transição é a saída.
3. **Pausa antes do clímax.** Entre a penúltima batida e o clímax, 0,3 a 0,75 s (9 a 22 quadros)
   sem movimento novo e sem fala: `"gaps": [0, 12]` na cena dá 20 quadros antes da 3ª fala.
4. **Variar ease e duração.** Curva pelo comportamento, não pelo elemento; no máximo duas animações
   com a mesma curva e duração por cena; a mais lenta dura ~3× a mais rápida. Constantes do `lib.tsx`:

   | Constante | Curva | Comportamento |
   |---|---|---|
   | `EASE` | `Easing.bezier(.22, 1, .36, 1)` | entrada, máscara (padrão do `ip`) |
   | `SETTLE` | `Easing.bezier(0, .65, .51, .99)` | assentamento: contagem que pousa, logo que trava |
   | `EXIT` | `Easing.bezier(1, .02, .54, .42)` | saída que acelera, fade final |
   | `EASE_INOUT` | `Easing.bezier(.83, 0, .17, 1)` | viagem de estado a estado |
   | `POP` | `Easing.out(Easing.back(1.7))` | overshoot de ~10 % no que chega com velocidade (a letra que voa no `swap`) |
   | `ANTIC` | `Easing.back(1.7)` | antecipação: recua antes de ir |

   O `Counter` aceita `ease` (padrão `EASE`): contagem de apoio com `SETTLE`, a do clímax quase linear.
5. **Antecipação, overshoot, "snap, then hold" e hit-stop**, só no foco. **Overshoot só no que chega
   com velocidade:** o que voou, caiu ou veio de uma antecipação (o número do clímax, o 1º do
   `ranking`, a letra do `swap`). O que entra por máscara, fade ou escala (o selo do `versus`, a
   pílula do CTA, a forma do `morph`, a parada do `map`) assenta com `SETTLE`, sem passar do alvo. Recuo de 3 a 4 quadros (escala 1 → 0,92); overshoot numa propriedade só
   (escala ou rotação, nunca posição nem o dígito); a mudança em 1 a 6 quadros e depois segura;
   `hitStop(f, at, hold = 3)` congela o elemento no impacto enquanto o resto segue; o som sai
   1 quadro antes do contato. Bounce e elastic, não. No `numbers`, `"focus": "last"` faz isso com o
   último número (antecipação, conta em 6 quadros, congela 3 a 1,12 de escala, assenta em 12 com
   `SETTLE`, rótulo quando a fala o diz); o `low-hit` vai em `cues` (`"b2+1"`).
6. **Duas ou três transições por filme, com uma direção dominante.** Cena sem `in` herda a corrente
   (`"current"` no `film.json`, padrão `whip`); `in` explícito só com motivo (`ink`/`iris` =
   fechamento, `whipUp` = conclusão que sobe, `cut` = match ou smash cut). Detalhes em `transicoes.md`.
7. **`Breathe` só onde pede.** Zoom ambiente em toda cena é "o vídeo esperando". No Film o `Breathe`
   envolve só o `outro` e o `logo3d` (o cartão segurado); outra cena liga com `props.breathe: true`,
   e `breathe: false` desliga (ponta de match cut). Sem o zoom, a cena fica viva revelando pela fala:
   nenhum trecho de 2 s ou mais sem algo novo. No `statement`, um grupo por fala ou por `frac` e
   `lineFracs` (fração da fala em que cada linha entra: `[0.45, 0.8]`); no `numbers`, o rótulo do
   foco chega quando a fala o diz; no `cta`, cada pílula entra no ponto da fala que a diz. Cena que
   termina de entrar com segundos sobrando é erro de planejamento: o `qa.sh` avisa cena parada.
8. **Um impacto por trecho.** `mark: "hit"` e cue de impacto não se repetem dentro de ~90 quadros
   (3 s): o segundo apaga o clímax.
9. **Desfoque na troca no mesmo lugar.** Quando dois estados ocupam o mesmo ponto ao mesmo tempo (os
   grupos do `statement`), o que sai desfoca até 2 px e o que entra parte de 2 px, só durante a troca.
   É `filter: blur()` calculado pelo frame, de 2 a 5 px, nunca acima de 20 px nem num nó `preserve-3d`
   (achata o 3D, `armadilhas.md`). Onde os estados não se sobrepõem (o rótulo do `morph` some antes do
   próximo entrar), não entra: custa render e não aparece. Custo medido no filme de teste: o trecho de
   271 quadros com as trocas foi de 17,8–19,6 s para 23,6–24,7 s.

Checklist da folha: dá para dizer qual é o foco em cada quadro? Quantos tipos de transição o filme
tem, e a direção é a mesma? Há pausa visível antes do clímax? O número do clímax passa e assenta, ou
só aparece? Alguma cena está viva só por causa do zoom?

Fontes (ideias reescritas; as curvas de `SETTLE` e `EXIT` são os valores do `motion-taste.md`):
HyperFrames, `heygen-com/hyperframes`, Apache-2.0 (regras 1, 2, 3, 6 e 7); `motion-taste.md` do
`diffusionstudio/lottie`, Copyright (c) 2026 Diffusion Studio Inc., MIT (curvas por comportamento,
regras 4 e 5); claude-animation, `buildwithhanif/claude-animation-skill`, Copyright (c) 2026 Hanif,
MIT (snap then hold, overshoot, hit-stop); ClaudeAnimationBase, `JohnHeibel/ClaudeAnimationBase`,
Copyright (c) 2026 John Heibel, MIT (antecipação, um foco por vez); `emilkowalski/skills`, Copyright
(c) 2026 Emil Kowalski, MIT (overshoot só com velocidade, desfoque na troca: regras 5 e 9).
