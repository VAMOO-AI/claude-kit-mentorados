# Diretor de imagem — vídeo (Kling e afins)

Parte de vídeo da skill `diretor-imagem`, lida quando o pedido é vídeo. A
numeração dos princípios é a mesma do `SKILL.md`: os que não estão aqui (1 a 8,
15 e a parte de imagem do 11, com a regra prática) ficam lá e valem igual para
vídeo.

## Movimentos de câmera (vídeo)

**Movimentos físicos da câmera — perspectiva muda:**

> No Kling, todo movimento desta tabela tende a sair como câmera andando, e
> Steadicam, gimbal e "floating" (tabela de estabilização, mais abaixo) também
> — a hierarquia do que usar no lugar está no Princípio 10. A coluna "Quando
> usar" vale para geradores sem esse defeito.

| Usuário diz | Comando técnico (use no prompt) | Quando usar |
|---|---|---|
| "se aproximando", "chegando perto", "indo em direção a..." | `slow dolly in / push in, [N]% over duration, perspective compression` | Quando quer aumentar intimidade ou foco emocional. Mantém a relação espacial entre objetos |
| "se afastando", "voltando", "abrindo o plano" | `slow dolly out / pull back, [N]% over duration, perspective expansion` | Para revelar contexto, criar sensação de descoberta, mostrar escala |
| "deslizando pra esquerda/direita" (acompanhando algo) | `truck left / truck right, [speed], parallel to subject plane` | Para acompanhar movimento lateral ou revelar profundidade lateral |
| "subindo a câmera" (sem inclinar) | `pedestal up [N] units` (sutil) ou `crane up [N] units` (dramático, com arco) | Pedestal: revelações verticais sutis. Crane: épico, descobertas amplas |
| "descendo a câmera" | `pedestal down` (sutil) ou `crane down` (dramático) | Mesma lógica acima |
| "girando ao redor", "circulando" | `slow orbit [direction], [N]° arc over duration, constant radius` | Revela 3D, valoriza objeto/sujeito central |
| "andando junto com..." | `tracking shot, follows subject at constant distance, [side/behind/front]` | Acompanha sujeito em movimento |
| "voo de drone descendo" | `descending drone shot, smooth gimbal stabilization, [angle]° pitch` | Aéreo controlado |

**Movimentos rotacionais — câmera parada, gira no próprio eixo:**

| Usuário diz | Comando técnico |
|---|---|
| "olhando pra esquerda/direita" (sem deslocar) | `pan left / pan right, [speed: slow/medium/whip], [N]° arc` |
| "olhando pra cima/baixo" | `tilt up / tilt down, [N]° arc, motivated by [reveal/follow]` |
| "câmera inclinada", "torta" | `Dutch angle / canted frame, [N]° roll` |

**Lente — perspectiva NÃO muda, só óptica:**

| Usuário diz | Comando técnico | Atenção |
|---|---|---|
| "zoom in" / "zoom out" puro | `optical zoom in/out, lens compression effect, no camera movement` | NUNCA confunda com dolly — o look é diferente |
| "vertigo", "efeito Kubrick", "contra-zoom" | `dolly zoom (Vertigo effect): dolly in + zoom out simultaneously, subject stays same size while background expands` | Efeito psicológico raro, usar com propósito |
| "foco que muda" | `rack focus from [subject A] to [subject B], smooth pull, T-stop maintained` | Mudança de plano focal |

**Estabilização e textura de movimento:**

| Usuário diz | Comando técnico |
|---|---|
| "tremidinho natural", "câmera na mão" | `handheld micro-movement, organic breathing, 3% subtle drift` |
| "estabilizado, suave" | `Steadicam glide, fluid floating motion, no jitter` |
| "drone profissional" | `gimbal-stabilized drone, smooth 3-axis stabilization, cinematic float` |
| "câmera lenta" | `slow motion, ramped to [25%/50%] of natural speed, 120fps capture conformed to 24fps` |
| "ficar parada" | `locked-off camera, tripod-mounted, zero movement` |
| "movimento bem sutil" | `ultra-slow, only [2-4]% movement over full duration, deliberate pace` |
| "rápido, dinâmico" | `swift movement, [N]% over [time], purposeful pacing` |

## Princípios de vídeo

### 9. Respiração e movimentos fisiológicos sutis NÃO funcionam no Kling

**Regra dura:** modelos image-to-video (incluindo Kling) interpretam comandos
como "chest rises with breath", "deep inhale", "shoulders soften with exhale"
como **deformações estranhas no torso** que não leem como humanas — saem com
aparência de pulso/morphing/respiração de animação 2D barata, quebrando
totalmente o realismo. Mesmo que seja realista pedir, o resultado falha.

**O que NÃO fazer:**
- ❌ "her chest visibly rises with a deep morning breath"
- ❌ "shoulders softening with the exhale"
- ❌ "deliberate inhale and exhale visible on screen"

**O que fazer no lugar:**

A vida humana é transmitida por **micro-ações concretas** e **micro-expressões
faciais**, não por respiração visível. Substitua sempre:

- ✅ Micro-blink natural (`one natural blink at second X`)
- ✅ Olhar que se move/foca (`gaze gently shifts focus from middle distance to near distance`)
- ✅ Lábios que se separam levemente (`lips part very slightly as if about to speak`)
- ✅ Cabeça que tilta minimamente (`head tilts 2° to the right with curiosity`)
- ✅ Mão que ajusta posição (`hand adjusts grip subtly`, `fingertips brush against fabric`)
- ✅ Dedo que toca o rosto (`finger brushes hair behind ear`)
- ✅ Cabelo respondendo à brisa (já mexe sozinho, dá vida)
- ✅ Sorriso Duchenne que floresce nos cantos (`subtle smile blooms at corners of mouth and eyes`)

Se for **absolutamente necessário** indicar que o sujeito está respirando
(ex.: cena meditativa onde calma é o ponto), use linguagem que sinalize
**ausência** de movimento visível e presença implícita:

> `The subject is in a state of calm stillness — breathing naturally and
> imperceptibly, no visible chest expansion above 1%, the breath is felt
> through the overall calm presence rather than seen as motion.`

Isso bloqueia o modelo de inventar respiração estranha.

**Regra geral:** use 1-2 micro-ações concretas por 8 segundos de vídeo. Não
empilhe. A força está na economia.

### 10. Câmera no Kling: default é STATIC. Movimento físico é exceção.

**Regra dura, validada em múltiplos testes:** o Kling interpreta QUALQUER
comando de movimento físico de câmera (dolly in, dolly out, truck, crane,
orbit) como **alguém andando enquanto grava**, mesmo com comandos explícitos
de "motion-control rig", "robotic precision", "absolute zero shake". O
modelo sempre adiciona footstep-like jitter ao movimento. Esse padrão se
repetiu em 2 testes consecutivos (push-in 9% + Steadicam, depois push-in 5%
+ motion-control rig — ambos saíram como walking shot).

**Conclusão prática:** para vídeos premium no Kling, o **default é câmera
estática locked-off**. Toda a vida vem do sujeito + ambiente + luz, não da
câmera. Só comande movimento físico quando ele for essencial à narrativa
(reveal, escala, descoberta) — e mesmo aí, prefira alternativas.

#### Hierarquia de movimento de câmera (do mais seguro ao mais arriscado no Kling):

**🟢 NÍVEL 1 — Câmera totalmente estática (DEFAULT):**

> `Camera is absolutely locked-off, tripod-mounted, mechanically immovable
> throughout the entire duration. Zero translation, zero rotation, zero
> zoom. The frame is fixed. All cinematic life comes from subject motion,
> environmental motion (hair, fabric, vegetation, light play), and natural
> lighting evolution — NOT from camera movement.`

**Vantagens:** Kling renderiza isso impecavelmente. Sem jitter, sem
walking-feel, sem horizon drift. A maioria dos prompts intimistas (retratos,
casais, pessoas em ambiente) funciona muito melhor assim.

**🟡 NÍVEL 2 — Rack focus (foco muda, câmera não move):**

> `Camera is locked-off and absolutely static. The only camera-driven motion
> is a deliberate slow rack focus from [foreground subject] to [background
> element] over [N] seconds, then optionally back. Lens remains at fixed
> focal length, no zoom, no translation, no rotation. Pure focus pull
> executed by a focus puller on the lens barrel.`

**Vantagens:** dá sensação de movimento cinematográfico sem mover a câmera.
Renderiza bem.

**🟡 NÍVEL 3 — Optical zoom muito sutil (2-3% no máximo):**

> `Camera body is absolutely locked-off, tripod-mounted. The only motion is
> an extremely subtle optical zoom in (or out) of 2-3% over the full
> duration, executed via the lens barrel by a focus puller. This is purely
> optical lens compression change — NOT physical camera translation, NOT
> dolly movement. The camera body itself does NOT move at all.`

**Vantagens:** quando algum sentido de "aproximação" for desejado, optical
zoom evita o walking-feel porque o modelo não interpreta como movimento
físico. Mas use sutilíssimo (2-3%) — zoom maior fica óbvio e quebra
realismo.

**🔴 NÍVEL 4 — Movimento físico de câmera (USE COM CUIDADO):**

Só recorra a dolly/truck/crane quando o reveal narrativo realmente exigir
(revelar fachada do prédio, mostrar escala do ambiente, descoberta
contextual). E mesmo aí:
- Mantenha amplitude **MUITO** baixa: 2-4% para push/pull, 3-5% para truck
- Comande de novo a estabilização mecânica + zero shake (não funciona 100%,
  mas reduz)
- Aceite que pode sair com algum walking-feel
- Considere se vale a pena vs. alternativas

#### Decisão por caso de uso:

| Tipo de cena | Movimento recomendado |
|---|---|
| Retrato íntimo / casal / momento emocional | 🟢 Estática (default) |
| Lifestyle pessoal sem reveal de produto | 🟢 Estática |
| Storytelling "olhe o que eles veem" | 🟡 Rack focus |
| Aproximação contemplativa | 🟡 Optical zoom 2% |
| Reveal de arquitetura/fachada/produto | 🔴 Truck ou pull-back 3-4% |
| Showcase de ambiente amplo | 🔴 Slow pan ou truck 4% |
| Drone / aéreo | 🔴 Aceitar que vai sair "drone-like" |

**Negative instructions sempre obrigatórios em vídeo:**
- No camera shake whatsoever
- No operator breath in the camera
- No handheld feel
- No floating motion
- No drift in the horizon line
- **No walking-shot feel**
- **No footstep-like camera jitter**
- **No simulated cameraperson movement**

**Quando tremor for intencional** (handheld documental, cena nervosa), aí sim
comande explicitamente como exceção. Mas isso é exceção, não regra.

### 11. Tamanho de prompt — parte de vídeo

A parte de imagem e a regra prática ao gerar ficam no `SKILL.md`.

#### Geradores de VÍDEO (Kling, Runway Gen-3, Sora, Pika):

- Token allowance MUITO maior — treinados pra absorver detalhe granular
- Detalhe **ajuda** porque controla timing, física, movimento
- Mas TEM teto: prompts >2800 palavras começam a diluir
- **Sweet spot validado em testes A/B**: **1800-2500 palavras** — o detalhe
  paga em fidelidade real, NÃO é gordura
- Versão lean (~580 palavras) testada lado-a-lado com versão longa
  (~2200 palavras) na mesma cena/imagem: a longa entregou claramente melhor
  resultado (timing das micro-ações, fidelidade do Duchenne smile, hair
  realism, preservation de branding)
- Beat-by-beat de ações, environmental motion emphatic, preservation
  detalhado, hair realism granular — TODOS pagam pelos tokens que ocupam
- **Não tente economizar tokens em vídeo Kling** — a precisão se perde

#### Sinais de prompt verdadeiramente inflado (vídeo) — só corte se for isso:

- Mesmo conceito repetido **5+ vezes** com palavras quase idênticas (3-4 é
  saudável e funciona como reinforcement)
- Parágrafos puramente decorativos sem comando acionável
- Negative com >50 itens completamente fora de contexto pra cena
- Beat-by-beat empilhando mais de 12 micro-ações em 8s (5-8 é ideal)

**Não corte:**
- Repetições estratégicas de keywords críticos (mandatory, never frozen, no
  morph) — elas paganham peso na atenção
- Detalhe granular de hair, environmental motion, preservation — testado e
  validado que entregam melhor resultado
- Beat-by-beat de timing das ações — controla narrative beats no vídeo
- Negative instructions específicos da cena (15-30 itens é normal)

### 12. Vegetação inventada — preservação por exclusão explícita

**Regra dura:** modelos image-to-video tendem a **adicionar vegetação onde
não existe** — especialmente quando o prompt pede que vegetação se mexa, o
modelo interpreta como license pra povoar mais áreas com plantas, weeds,
ground cover, ou foliage que não estavam na imagem de referência. Isso
quebra a fidelidade visual da peça.

**O que NÃO fazer:**
- ❌ Descrever vegetação genericamente ("various plants throughout")
- ❌ Comandar movimento de vegetação sem ancorar em locais específicos
- ❌ Negative apenas com "no invented vegetation" (vago demais)

**O que fazer:**

1. **Listar EXATAMENTE quais plantas existem e ONDE** — coordenadas espaciais
   ou referência clara à composição (foreground left, behind chair, on
   balcony level 2, etc.)

2. **Comandar preservation explícita por exclusão**:

> `The ONLY vegetation present in this scene is: [lista exata]. No other
> vegetation exists anywhere in the frame. The concrete surfaces are bare
> concrete. The pool deck is empty paving — no plants, no weeds, no ground
> cover. The corners and edges of the architecture are clean — no foliage
> materializes there. No vegetation appears between [element A] and
> [element B]. Vegetation does not spread, propagate, or appear in any
> location not specified above.`

3. **Negative instructions específicos sempre incluir em cenas externas:**
- No invented vegetation
- No additional plants materializing
- No weeds appearing in concrete cracks
- No ground cover spreading
- No foliage growing on architectural surfaces
- No new planters appearing
- No moss or lichen on surfaces (unless specified)
- Vegetation count and positions identical to reference frame

4. **Por área de risco, comandar o "vazio"**:

Cenas de piscina, deck, terraço — sempre dizer explicitamente que as
áreas pavimentadas/concreto/madeira estão **VAZIAS** de vegetação. O modelo
precisa ouvir o "não tem" pra não inventar.

> `Pool deck pavement is completely clear and clean — no plants, no weeds,
> no ground cover materializes on the deck surface throughout any frame.`

5. **Cenas com piscina/água/lago — atenção tripla**:

Padrão validado: Kling confunde reflexos de vegetação na água + ripples +
revestimento verde/turquesa de mosaico + comandos de "vegetação se mexer"
como license pra colocar plantas DENTRO da água (matos brotando, algas,
folhas flutuando). Sempre comandar explicitamente o conteúdo do espelho
d'água:

> `WATER BODY CONTENT — STRICT: the pool/lake/water contains ONLY clean
> [chlorinated] water. The water is COMPLETELY FREE of any vegetation,
> any plants, any weeds, any algae, any moss, any leaves, any organic
> matter, any debris, any floating objects, any submerged plants, any
> growth on the walls or floor. The mosaic tile pattern at the bottom is
> CERAMIC TILE ONLY — geometric ceramic tile, NOT plants, NOT algae, NOT
> organic matter. The turquoise/green color is tile pigment, not
> vegetation. The reflections on the water surface are reflections of the
> EXISTING above-water vegetation (the [list]) — they are mirror images,
> NOT actual plants in the water. No vegetation materializes in or on the
> water at any point.`

E nos negative:
- No plants in the pool / water
- No weeds growing in the pool / water
- No algae on pool surface or walls
- No moss in the pool
- No floating leaves or debris
- No submerged vegetation
- Mosaic tiles are ceramic, not algae

### 13. Image-to-video: a referência É a descrição. NÃO redescreva a cena toda.

**Bug catastrófico validado em teste 2026-04-27:** prompt detalhado pra
cena de closet com mulher vista através de portas de vidro temperado —
Kling ignorou completamente a imagem de referência e gerou um vídeo
totalmente diferente (mulher diferente, ângulo diferente, elementos
diferentes). Sintoma de que o modelo tratou o prompt como **text-to-video**
em vez de image-to-video.

Abrir com "Starting from the reference image: [descrição exaustiva]" funciona
em cena simples — a descrição confirma a referência. Em cena visualmente
complexa (vidro com reflexo, geometria em camadas, muitos itens a preservar),
a descrição longa compete com a imagem e o Kling pode descartar a referência
e gerar do zero.

**Sinais de risco que aumentam a chance desse bug:**

- Cena vista **através de superfícies translúcidas** (vidro, voile, espelho)
- **Reflexos importantes** na composição
- **Múltiplos elementos preserváveis** listados (>5 itens nomeados)
- **Geometria layered complexa** (foreground+midground+background com vários objetos cada)
- **Sujeito secundário** ou em pose incomum

**Image-to-video em cena complexa: não redescreva a cena.**

A imagem de referência **já entrega** a composição, identidade, ambiente,
iluminação, props, geometria. O trabalho do prompt é dizer o que
**MUDA** ao longo da duração, não recriar o que já está visível.

#### Estrutura âncora (image-to-video, cena complexa):

```
[1. ANCHOR — 1 frase curta]
"Animate the reference image as a [duration]-second cinematic video,
preserving every visible element with absolute fidelity."

[2. MOTION — beat-by-beat detalhado]
Subject motion (micro-actions, no breathing motion).
Hair motion (strand-level, response to motion + breeze).
Environmental motion (calibrated to context).

[3. CAMERA]
Locked-off statement.

[4. PRESERVATION — por exclusão, não por descrição]
"Every visible element of the reference image is preserved in form,
position, color, and identity. Do not invent new elements. Do not
remove existing elements. Do not change [list specific risks for this
scene type — branding, faces, key items]."

[5. LIGHTING CONTINUITY]
Brief continuity statement.

[6. OUTPUT SPECS + CAMERA BODY/LENS]

[7. NEGATIVE INSTRUCTIONS]
```

**Resultado esperado:** prompts mais curtos (~800-1500 palavras vs. 2200)
porque a redescrição visual sai. Detalhe vai pra motion, hair, preservation
risks, e negatives — onde paga.

Cena simples (sujeito único, ambiente claro, poucos itens a preservar): a
anatomia com descrição completa funciona. Cena complexa: use a estrutura
âncora.

**Heurística pra decidir:**

| Cena | Template |
|---|---|
| Retrato/pessoa única em ambiente claro | Descrição completa |
| Casal/família em ambiente claro | Descrição completa |
| Pessoa através de vidro/voile/espelho | Âncora (confia na referência) |
| Cena com >5 itens nomeados pra preservar | Âncora |
| Reflexos importantes na composição | Âncora |
| Ambiente sem pessoas (arquitetura, água) | Descrição completa, mais focada |

### 14. Efeitos visuais espalham — comande por exclusão

**Padrão validado:** quando você comanda um efeito visual em um elemento da
cena (vapor de uma xícara, fumaça de uma vela, glow de uma lâmpada, chama
de um cooktop, ondulação de água), Kling **espalha esse efeito pra outros
elementos plausíveis** que ele identifica na cena, mesmo se você não pediu.

**Exemplos validados em testes:**
- Comando "steam rises from coffee mug" → vapor saindo TAMBÉM da garrafa
  de suco de laranja (cold beverage, fisicamente impossível)
- Comando "vegetation moves with breeze" → plantas materializando em locais
  sem vegetação (já documentado em Princípio 12)
- Comando "candle flame flickers" → outras chamas/luzes começam a flicker
  também (extrapolação)

**Regra: para CADA efeito visual comandado, especifique simultaneamente:**

1. **EM QUAIS elementos** o efeito existe (com nomeação específica)
2. **EM QUAIS elementos** o efeito NÃO existe (lista explícita de exclusão)
3. **POR QUÊ não existe** nos excluídos (justificativa física)

#### Template:

```
Subtle continuous [EFEITO] MUST rise from [ELEMENTO A] and [ELEMENTO B]
ONLY — these are [hot/active/etc justificativa]. NO [EFEITO] from any
other source in the scene. Specifically: [ELEMENTO C] contains [cold
liquid / inert material / etc] and produces ZERO [efeito]. [ELEMENTO D]
is [estado] and produces ZERO [efeito]. [Continuar excluindo todos os
elementos plausíveis].
```

#### Casos comuns a comandar por exclusão:

| Efeito | Onde costuma espalhar (cuidar) |
|---|---|
| **Vapor/steam** | Qualquer recipiente com líquido visível (suco, vinho, água gelada) |
| **Fumaça** | Qualquer fogo/chama, qualquer fonte de calor (mesmo apagada) |
| **Chama/fogo** | Lareiras, fogões, velas, qualquer "lugar onde fogo poderia estar" |
| **Glow/aura** | Qualquer luz, joias, telas, materiais brilhantes |
| **Ondulação/ripple** | Qualquer superfície reflexiva (espelho, vidro, piso polido) |
| **Vento em vegetação** | Qualquer planta visível (ver Princípio 12) |

**Negative instructions cirúrgicos sempre incluir quando comandar efeito:**

- No [EFEITO] from cold beverages
- No [EFEITO] from inert objects
- No [EFEITO] materializing on [outros elementos plausíveis]
- [EFEITO] only from the specified sources

**Exemplo concreto (caso da garrafa de suco):**

❌ Errado: "Steam rises from the mugs"
✅ Tentativa 1: "Steam MUST rise from the mother's coffee mug and the
son's hot chocolate mug ONLY — both contain hot beverages. NO steam from
the orange juice bottle (cold beverage). NO steam from the French press
(sealed container at table temperature). NO steam from any other
container, plate, or item in the scene."

#### Regra de escalonamento — quando exclusão NÃO basta:

**Padrão validado em 2 testes consecutivos:** mesmo com exclusão explícita
e justificativa física, Kling continuou adicionando vapor na garrafa de
suco. Conclusão: alguns efeitos têm tendência tão forte de espalhar no
modelo que a exclusão sozinha não segura.

**Regra de escalonamento:**

1. **Tentativa 1**: comandar com exclusão explícita (template padrão acima)
2. **Tentativa 2 (se Tentativa 1 falhou)**: **proibir o efeito
   COMPLETAMENTE** da cena, mesmo que isso signifique perder o efeito
   onde ele faria sentido (ex.: nas xícaras quentes)

✅ Tentativa 2 (escalonamento): "NO STEAM ANYWHERE in this scene. NO vapor
from any container, hot or cold. NO mist from any source. The mugs may
contain hot beverages but show ZERO visible steam. The orange juice
bottle is cold and shows ZERO steam. NO water vapor, NO atmospheric mist
beyond ambient particles. The scene is steam-free throughout all frames."

**Trade-off aceitável:** perder o cinematic value do vapor das xícaras
(que era nice-to-have) em troca de eliminar o risco fatal do vapor
hallucinado em garrafa de suco (que é deal-breaker visual). O custo do
hallucination é maior que o ganho do efeito.

**Aplicar a mesma escalada para outros efeitos teimosos:**
- Se chama do cooktop espalhar pra outros lugares → proibir TODA chama
- Se ripples espalharem pra outras superfícies → proibir TODOS ripples
- Se glow espalhar pra outras lâmpadas → fixar TODAS lâmpadas como steady

**Princípio:** se um efeito visual hallucinated apareceu mesmo após
exclusão explícita, o próximo prompt elimina o efeito por completo.
Realismo perfeito > efeito cinematográfico parcialmente quebrado.

### 16. Checagem de plausibilidade física (vídeo)

Antes de finalizar um prompt de vídeo, escaneie a cena e pergunte:

- Há **vegetação** visível? (plantas, folhas, árvores, grama, flores)
- Há **cabelo solto** no sujeito?
- Há **tecido leve** (camiseta solta, vestido, lenço, cortina)?
- Há **água/líquidos** visíveis? (taça, piscina, fonte, chuva)
- Há **chamas, fumaça, vapor, partículas** no ar?
- O cenário é **externo ou semi-externo** (varanda, jardim, beira-mar,
  janela aberta, calçada)?

Se SIM para qualquer combinação que envolva fluxo de ar plausível
(externa + vegetação = vento; janela aberta + cortina = brisa; varanda +
plantas = vento de altura), a movimentação **DEVE ser comandada
emphatically** no bloco Environmental Motion. Modelos de image-to-video
congelam silenciosamente elementos cuja movimentação foi pedida de forma
suggestive em vez de mandatory. Use `MUST visibly respond`, `continuous
movement throughout duration`, `NOT static`, `NOT frozen`.

Esta checagem é não-negociável para vídeos com cenas que tenham qualquer um
desses elementos.

## Anatomia do prompt — Vídeo Kling AI

### Image-to-video

```
[1. STARTING FRAME]
Cena simples (pessoa única ou sem pessoas, ambiente claro): "Starting from the
reference image: [1-2 frases do frame inicial — composição, iluminação e mood
já presentes]". Cena complexa (vidro, reflexo, >5 itens a preservar): só a
âncora do Princípio 13 — "Animate the reference image as a [N]-second
cinematic video, preserving every visible element with absolute fidelity."

[2. SUBJECT MOTION]
[Micro-ações concretas — gesto, micro-expressão, olhar, cabeça — com ângulo e
segundo. Ex.: "subject slowly turns head 12° to the right over 3 seconds,
micro-blink at second 4". Respiração visível não entra (Princípio 9).]

[3. ENVIRONMENTAL MOTION — physical plausibility é OBRIGATÓRIA]
[O que se move no ambiente: folhas, cabelo, tecido, partículas, reflexos,
nuvens, água, fumaça. Sempre justifique fisicamente: "fabric responds to
gravity drape", "leaves react to gentle 4km/h breeze"].

**REGRA CRÍTICA:** se a cena tem vegetação, cabelo solto, tecido leve,
chamas, água, fumaça, ou partículas, e o contexto é um ambiente onde haveria
fluxo de ar real (varanda, externa, janela aberta, beira-mar, etc.), a
movimentação **NÃO É OPCIONAL** — precisa estar visível. Modelos de
image-to-video tendem a congelar elementos como estátuas se o comando for
fraco. Use linguagem emphatic, não suggestive:

- ❌ Fraco: "leaves may sway slightly" / "subtle plant movement"
- ✅ Emphatic: "**vegetation MUST visibly respond** to the established breeze
  — leaf tips drift continuously throughout the duration with organic
  gravity-aware motion, NOT static. Each leaf cluster shows independent
  response. The movement is gentle (8-12% amplitude) but **continuous and
  unmistakable** — never frozen."

Para cabelo: "loose hair strands MUST show visible continuous response to
ambient air, NOT painted-on rigidity."

Para tecido leve: "fabric MUST show continuous gravity drape and breeze
response, NOT statue-stiffness."

Para água/líquidos: "surface MUST show continuous physically-accurate ripple
or refraction shift, NOT glass-frozen."

Sempre estabeleça a fonte (breeze, draft, convection) E reforce que a
resposta é mandatória.

[4. CAMERA — no Kling o default é locked-off (Princípio 10)]
Locked-off statement (Nível 1). Se o briefing pede sensação de movimento: rack
focus ou optical zoom de 2-3% (Níveis 2-3). Movimento físico só para reveal,
com 2-4% e os negativos de walking shot (Nível 4).

[5. PRESERVATION — anti-morph commands]
Preserve facial identity, body proportions, clothing details, background
composition, architectural geometry, lighting direction. No identity drift.
No morph. No background warping. No frame popping. Photoreal physics
throughout.

[6. ATMOSPHERE & LIGHTING CONTINUITY]
Lighting remains consistent with reference frame — [same direction, color
temperature, contrast]. [Atmospheric elements maintain natural physics:
particles drift consistently, reflections track surface motion].

[7. QUALITY & DURATION]
Duration: [5s / 10s]. Render at 4K-8K resolution, 24fps cinematic motion
cadence, organic motion blur (1/48s shutter equivalent), smooth temporal
coherence, photoreal physics-based simulation, premium realism.

[8. NEGATIVE INSTRUCTIONS]
NEGATIVE INSTRUCTIONS: [tailored video-specific list].
```

### Text-to-video

Use a anatomia de imagem do `SKILL.md` (blocos 1-2, 4-7) **+** os blocos de
movimento (camera, subject motion, environmental motion) **+** quality/duration
de vídeo. Omita o bloco de preservation — não há referência.

## Negativos de vídeo

**Vídeo (Kling) — críticos:**
- No face morphing
- No identity shift between frames
- No warping
- No frame jitter
- No flickering
- No background distortion
- No unnatural physics
- No sudden zooms (unless specified)
- No melting hands during motion
- No frame-to-frame inconsistency
- No object morphing
- No texture swimming
- No artificial buoyancy
- **No statue-frozen vegetation when breeze is established** (vegetation must
  visibly respond — never painted-on stiffness)
- **No statue-frozen hair when ambient air is established**
- **No statue-frozen fabric when motion or breeze is plausible**
- **No glass-frozen water/liquid surfaces when physics demand response**

## Exemplos de vídeo

> Os exemplos de vídeo (2 e 3) estão abreviados para caber aqui; em uso real,
> expanda beat-by-beat até a faixa do Princípio 11 — não copie o tamanho deles.

### Exemplo 2 — Vídeo Kling com imagem fornecida

**Input do usuário:**
> [cola foto da fachada de um empreendimento residencial ao golden hour]
> Quero um vídeo de 5 segundos pra esse, com a câmera se afastando devagar.

**Análise visual (interna):**
- Sujeito: fachada residencial premium, ângulo low front-quarter
- Iluminação atual: golden hour direcional camera-left
- Mood: sereno, aspiracional
- Ambiente: contexto urbano calmo, canteiro baixo à frente e copas de árvore
  nas bordas do quadro

**Tradução de "se afastando devagar":**
- "se afastando" → pull-back (dolly out), 3-4% no Kling (Princípio 10) —
  acima disso sai como câmera andando
- "devagar" → os 3-4% distribuídos nos 5 segundos, pacing deliberate
- o pedido já diz o que muda e a duração → gera direto e oferece, no fim, a
  alternativa sem movimento físico

**Output:**

```text
Starting from the reference image: a premium residential building facade
captured at golden hour, low front-quarter angle, warm directional light
from camera-left creating defined shadow geometry on architectural details,
foreground landscaping (low ornamental plants and ground cover), serene
urban context.

Subject motion: the building remains completely static and geometrically
locked — zero deformation of facade, windows, balconies, or brand identity.

Environmental motion: the ONLY vegetation in this scene is the low
ornamental planting in the foreground bed and the tree foliage at the frame
edges; no other vegetation exists anywhere, and the facade, balconies and
paving stay free of plants. That foliage MUST visibly respond to a gentle
5 km/h breeze throughout the full duration — continuous, organic, NOT
static. Atmospheric particles catching golden light drift slowly across the
midground air.

Camera movement: slow pull-back of 3-4% over 5 seconds revealing a little
more of the urban context. Motion-control rig, mechanical stabilization,
absolute zero shake, locked horizon. Lens: fixed focal length, no zoom.
Pacing: deliberate, contemplative.

Preservation: maintain exact facade geometry, window grid alignment, balcony
placement, brand identity, all architectural proportions, original golden
hour lighting direction and color temperature. Preserve frame-to-frame
identity for every architectural element. No identity drift. No facade
morphing. No window shape shift. No background warping. Photoreal physics
throughout.

Lighting continuity: golden hour 4200K maintained throughout duration,
shadow direction consistent, color temperature locked, no exposure pulsing.
Atmospheric particles physically consistent with golden-hour air quality.

Duration: 5 seconds. Render at 8K resolution, 24fps cinematic motion
cadence, organic motion blur (1/48s shutter equivalent), smooth temporal
coherence, photoreal physics-based simulation, premium realism throughout.

NEGATIVE INSTRUCTIONS: No facade morphing. No window grid drift. No invented
architectural details. No warping. No frame jitter. No flickering. No
sudden zooms. No camera shake. No exposure pulsing. No HDR halos. No
unnatural physics on landscaping. No texture swimming. No artificial
buoyancy. No identity drift between frames. No operator breath in the
camera. No drift in the horizon line. No handheld feel. No floating motion.
No walking-shot feel. No footstep-like camera jitter. No simulated
cameraperson movement. No invented vegetation. No foliage growing on
architectural surfaces.
```

> Quer testar uma versão com a câmera fixa e optical zoom out de 2–3%? Dá a
> mesma sensação de abrir o plano, sem risco de walking shot.

### Exemplo 3 — Retrato com tradução de movimento

**Input do usuário:**
> Tenho uma foto da minha esposa na sala. Quero um vídeo de 8 segundos onde
> a câmera vai chegando perto bem devagar e ela dá um sorriso sutil no final.

**Tradução interna:**
- "chegando perto bem devagar" → no Kling, aproximação é optical zoom in de
  2-3% com o corpo da câmera locked-off (Princípio 10); dolly in com Steadicam
  sai como walking shot
- "sorriso sutil no final" → micro-expressão aos 6,5s
- a foto mostra cabelo solto perto da orelha → movimento de fios obrigatório
  (Princípios 8 e 16)

**Output:**

```text
Starting from the reference image: a portrait of the subject in a softly-lit
living room interior, current expression neutral and contemplative,
naturalistic environmental lighting from window-side, cinematic shallow depth
of field already established with subject in focus and background
gracefully defocused.

Subject motion: subject begins with current neutral expression. Around
second 6.5, a subtle, micro-expression smile begins to bloom — soft,
authentic warmth at the corners of the mouth and eyes (Duchenne marker
present), reaching gentle peak at second 7.5 and holding. One natural
micro-blink around second 3. She is in calm stillness — breathing
imperceptibly, no visible chest or shoulder motion. No head turn, no
shoulder shift.

Environmental motion: loose hair strands near the ear MUST show continuous,
gentle strand-level response to room air throughout the full duration —
individual strands move independently, NOT a single solid mass, NOT frozen.
Background bokeh remains dimensional.

Camera movement: camera body is absolutely locked-off, tripod-mounted,
mechanically immovable. The only motion is an extremely subtle optical zoom
in of 2-3% over the full 8 seconds, executed on the lens barrel — pure lens
compression, NOT dolly, NOT physical camera translation. 85mm lens; focus
stays razor-thin on the eyes. Pacing: contemplative, intimate.

Preservation: preserve facial identity with absolute fidelity — facial
geometry, proportions, asymmetries, distinguishing features all locked.
Preserve clothing details, hair texture and color, jewelry if present,
background composition. No identity drift. No face morphing. No proportion
shift. No background warping. Photoreal physics throughout.

Lighting continuity: maintain exact lighting direction, color temperature,
and contrast from reference frame. Soft directional from window-side, warm
highlights, cool shadow tones, natural shadow falloff. As the optical zoom
slowly tightens the frame, catchlights in the eyes stay consistent and
lighting character remains identical.

Color grade: editorial neutral with cinematic contrast curve, real skin
texture preserved (visible pores, micro-imperfections, natural asymmetry),
no plastic finish, subtle natural film grain. Authentic premium portraiture.

Duration: 8 seconds. Render at 8K resolution, 24fps cinematic motion
cadence, organic motion blur (1/48s shutter equivalent), smooth temporal
coherence, photoreal physics-based simulation, premium portrait realism.

NEGATIVE INSTRUCTIONS: No face morphing. No identity drift. No plastic
skin. No over-smoothing. No symmetric features. No doll-like eyes. No
over-rendered teeth. No uncanny valley. No melted features. No background
warping. No frame jitter. No flickering. No sudden zooms. No camera shake.
No exposure pulsing. No texture swimming. No fake glow. No visible breathing
motion. No operator breath in the camera. No drift in the horizon line. No
handheld feel. No floating motion. No walking-shot feel. No footstep-like
camera jitter. No simulated cameraperson movement. No statue-frozen hair.
```

> Quer testar com rack focus do rosto para um detalhe do ambiente, ou com a
> câmera totalmente fixa, sem o zoom?
