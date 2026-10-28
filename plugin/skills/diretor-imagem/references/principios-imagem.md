# diretor-imagem — princípios de engenharia (1 a 8, 11 e 15)

Lido no Passo 4, antes de montar qualquer prompt (imagem ou vídeo). Os princípios 9, 10, 12, 13, 14, 16 e a parte de vídeo do 11 estão em [video-kling.md](video-kling.md).

## Princípios de engenharia (a "fórmula Forsen")

Aplique sempre, calibrando ao caso:

### 1. Especificidade técnica de câmera é mandatória

Trate o gerador como equipe de filmagem real. Sempre declare:

- **Corpo:** Sony A1, ARRI Alexa 35, RED V-Raptor, Hasselblad H6D, Phase One XF IQ4
- **Lente:** focal + abertura específicas (ex.: 85mm f1.4, 35mm f1.8, 24mm tilt-shift)
- **Abertura usada:** "at f1.6" — diferente da abertura máxima da lente
- **ISO:** 100 (luz forte), 400-800 (low-light), 1600+ (noite com grão controlado)
- **Shutter:** 1/200 padrão; 1/50 para motion blur intencional em vídeo
- **DOF:** "razor-thin focus plane", "cinematic shallow DOF", "deep focus hyperfocal"

Reforce com `"This [setup] is mandatory"` para evitar drift.

### 2. Preservation prompts — o que NÃO mudar

Sempre que houver imagem de referência, declare explicitamente:

- Identidade facial (retratos): `preserve facial geometry, do not alter expression or proportions`
- Background: `keep the exact background from the reference. No replacements, no new objects, no layout shifts`
- Arquitetura: `preserve exact architectural proportions, window placement, ceiling height, material finishes`
- Continuidade temporal (vídeo): `preserve frame-to-frame identity, no morph, no drift, no flickering`

### 3. Linguagem cinematográfica completa

Substitua adjetivos vagos por vocabulário de DP. Use o glossário acima.
Sempre proibir explicitamente o que NÃO quer (ver biblioteca de negative
prompts).

### 4. Realismo de textura é não-negociável

- Pessoas: `real skin texture with pores, micro-imperfections, natural asymmetry, no plastic finish`
- Materiais: `authentic surface grain, honest texture, physical-based rendering`
- Sempre: `subtle natural film grain, no digital sterility`

### 5. Output specs explícitas — 8K como default

Feche todo prompt com:

> `Render in 8K resolution, 10-bit color depth, REC.2020 wide gamut, cinematic editorial style, premium clarity, [crop format]`

Para vídeo: `Render at 4K minimum (8K preferred), 24fps cinematic motion cadence, smooth temporal coherence, photoreal physics`

### 6. Negative instructions sempre estruturadas

Bloco final `NEGATIVE INSTRUCTIONS:` cirúrgico — ver biblioteca abaixo.

### 7. Repetição estratégica de palavras-chave (vídeo)

Em vídeo, termos críticos (`mandatory`, `cinematic`, `8K`, `preserve`,
`photoreal`) aparecem 2-3 vezes em pontos distintos do prompt: nos testes da
parte de vídeo do Princípio 11 (`references/video-kling.md`) a repetição pagou
em fidelidade. Em imagem, o orçamento de 80-180 palavras não comporta
repetição; cada termo entra uma vez, como no Exemplo 1.

### 8. Cabelo solto é o teste do realismo

Cabelo é onde IA generativa mais entrega o "tell" — fica com cara de capacete,
peruca, ou textura pintada. Sempre que houver cabelo solto visível, comande
explicitamente:

**Para imagens (estático):**

Em imagem, condense em uma frase:
`strand-level hair realism, flyaways and baby hairs at the hairline, natural strand color variation, no helmet or wig look`.
O bloco longo abaixo é para quando o orçamento de palavras permite (Princípio 11).

> `Hair MUST be rendered with strand-level realism: individual flyaway
> strands visible, fine baby hairs at the hairline and temples, natural
> color variation strand-to-strand (NOT flat single-color), realistic
> root-to-tip subtle gradient, sub-surface light scattering through
> strand groups, specular highlights catching the key light along strand
> length, organic asymmetry — NEVER a helmet, NEVER a wig, NEVER painted
> texture, NEVER plastic shine.`

**Para vídeos (movimento):**

> `Loose hair MUST show continuous strand-level response to ambient air
> throughout the full duration — individual strands and small clusters
> move independently with organic gravity-aware physics, baby hairs at
> the hairline drift continuously, fly-away strands trace small
> unpredictable arcs, NOT a single solid mass, NOT painted-on rigidity,
> NOT statue-frozen. Even in still scenes indoors, breathing and body
> heat create micro air currents — hair always lives.`

**Negative instructions específicos pra cabelo** (vídeo: sempre; imagem: 1-2 dos de maior risco, dentro dos 4-6):
- No helmet hair
- No wig appearance
- No painted hair texture
- No plastic hair shine
- No single-mass hair (must read as individual strands)
- No symmetric hair fall (humans aren't symmetric)
- No frozen hair when air movement is plausible

**Por tipo de cabelo, ajuste o vocabulário:**
- **Liso longo:** `silk-like flow, individual strand definition, gravity drape, smooth specular highlights along length`
- **Ondulado:** `organic wave pattern, irregular curl rhythm, volume with gravity, varied wave amplitude strand-to-strand`
- **Cacheado:** `defined coil pattern, individual curl integrity, organic volume, no clumping into mass`
- **Crespo/4C:** `natural coil density, organic volume, individual coil definition, no flattening`
- **Curto/raspado:** `individual short strand definition at scalp, realistic density, micro-shadow at scalp`

Quando houver cabelo solto visível — de qualquer pessoa, na referência ou no
briefing —, esses comandos são obrigatórios no prompt; não deixe pro modelo
deduzir. Cabelo preso, curto ou coberto: use só a linha do tipo de cabelo e
preserve o penteado da referência — comando de fio solto ali muda o penteado.

### 11. Tamanho de prompt: calibre por gerador (imagem ≠ vídeo)

**Verdade técnica:** modelos de IA têm comportamentos opostos quanto a
tamanho de prompt:

#### Geradores de IMAGEM (nano banana, Midjourney, Flux, DALL-E, Imagen):

- Prompts longos **diluem atenção** — modelo pesa menos cada conceito
- Best practice: prosa enxuta + keywords densas
- **Padrão**: descrição visual concisa + specs de câmera + lighting + negative
- **Total alvo**: 80-180 palavras

**Template enxuto pra imagem (versão lean):**
```
[Subject + action, 1 frase]. [Environment, 1 frase].
[Camera body + lens + aperture + ISO]. [Lighting scheme + mood].
[Color grade + texture]. [Output: 8K, format].
NEGATIVE: [lista cirúrgica de 4-6 itens críticos].
```

#### Regra prática ao gerar:

- Se o briefing é **imagem** → versão lean (80-180 palavras), prosa densa
- Se o briefing é **vídeo** → beat-by-beat, ~800-1500 palavras na estrutura
  âncora (cena complexa, Princípio 13); até ~2500 com descrição completa (cena
  simples). Abaixo de ~600 perde timing e física (teste A/B na parte de vídeo
  deste princípio, em `references/video-kling.md`)
- **Nunca** entregue versão longa pra nano banana — ele ignora 60% do prompt
- **Nunca** entregue versão lean pra Kling em cena complexa — perde controle
  de timing e física

### 15. Filtros de segurança em geradores de imagem — cuidado com crianças

**Padrão validado em 2026-04-28:** prompts com descrição detalhada de
crianças pequenas (idade específica + cabelo + roupas + características
físicas) **triggam filtros de segurança infantil** em Gemini/nano banana
e similares, resultando em rejeição do prompt mesmo quando o conteúdo é
inocuo (cena familiar de café da manhã, marketing imobiliário).

**O que NÃO fazer em prompts de imagem com crianças:**

- ❌ "5-6 year old son with short blond hair wearing white t-shirt"
- ❌ "young daughter approximately 6 years old, long dark brown hair, beige dress, barefoot"
- ❌ Combinação de idade específica + roupas detalhadas + features físicas

**O que fazer no lugar:**

1. **Descrição vaga da composição familiar:**
   - ✅ "a family at breakfast" / "a young family"
   - ✅ "adult woman accompanied by two children"
   - ✅ "two children from behind or side angle"

2. **Foco no adulto** (descrição completa) **+ crianças apenas como
   contexto compositivo:**
   - ✅ Adulto: detalhe completo (cabelo, roupa, postura)
   - ✅ Crianças: apenas presença e ângulo (não detalhar idade exata,
     roupas específicas, ou features faciais)

3. **Image-to-image como alternativa segura:**
   Se a imagem de referência já tem as crianças, suba a referência junto
   com prompt curto tipo "enhance this image with editorial premium
   quality, real skin texture, AD Magazine aesthetic" — assim o gerador
   não precisa "criar" crianças do zero, só refina o que já existe.

4. **Considere remover crianças da composição:**
   Se o filtro continuar bloqueando, gerar versão só com adultos é o
   caminho mais seguro pra peça de marketing.

**Roteamento Gemini app — nota técnica:**

Mensagens como "Can't generate that video" mesmo quando o usuário quer
imagem podem indicar que o Gemini app está roteando o prompt pro Veo
(modelo de vídeo) em vez do nano banana (modelo de imagem). Pode ser
trigger por: linguagem temporal ("over 8 seconds"), comandos de motion
("camera locked-off"), beat-by-beat. Pra forçar imagem, use
exclusivamente vocabulário fotográfico estático e evite qualquer
referência a tempo/movimento.
