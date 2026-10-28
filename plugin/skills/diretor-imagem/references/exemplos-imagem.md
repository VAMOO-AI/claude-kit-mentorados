# diretor-imagem — exemplos de imagem e prompt de referência

Lido no Passo 4 como calibragem de tamanho e nível de detalhe (Exemplo 1 e o apêndice). Os Exemplos 2 e 3 (vídeo) estão em [video-kling.md](video-kling.md).

## Exemplos

### Exemplo 1 — Imagem from scratch (interior de um empreendimento residencial)

**Input do usuário:**
> Quero um prompt pra gerar uma sala de estar de um empreendimento
> residencial, ampla, luz natural, bem editorial, estilo AD Magazine.

**Tradução interna:**
- Caso: imobiliário interior → Hasselblad + 24mm tilt-shift
- Iluminação: natural daylight motivated, AD aesthetic
- Estilo editorial premium

**Output:**

```text
A spacious premium apartment living room, floor-to-ceiling windows on the
left pouring soft midday light across polished porcelain floors; low
off-white linen sofa, walnut coffee table with a single ceramic vessel, a
large fiddle-leaf fig, one muted abstract artwork on a plaster wall. Shot on
a Hasselblad H6D with a 24mm tilt-shift lens at f8, ISO 200, 1/60 on tripod,
deep focus, perfectly vertical lines — this Hasselblad + 24mm tilt-shift
setup is mandatory. Motivated natural daylight 5600K as soft key from
camera-left, gentle bounce fill from the right, smooth gradations, no harsh
shadows. Editorial neutral grade, honest walnut and porcelain texture,
subtle film grain, AD Magazine restraint. 8K, landscape 3:2.
NEGATIVE: warped perspective, tilted verticals, inflated room proportions,
clutter, HDR halos, fake glow.
```

> Quer testar uma versão golden hour (luz mais quente, sombras longas) ou
> overcast (luz totalmente difusa, mais neutra)?

## Apêndice: prompt de referência que originou esta skill

Um mentorado trouxe o prompt abaixo como referência de qualidade. Ele NÃO é um
template fixo — é um exemplo que demonstra a aplicação dos princípios desta
skill (especificidade de câmera Sony A1 + 85mm f1.4, preservation total,
linguagem cinematográfica de iluminação, real skin texture, output specs
explícitas, negative instructions estruturadas). Use-o como inspiração de
nível de detalhamento e fluência técnica, não copie literalmente — o tamanho
do texto final segue o Princípio 11.

```text
Enhance the portrait while strictly preserving the subject's identity with
accurate facial geometry. Do not change their expression or face shape. Only
allow subtle feature cleanup without altering who they are. Keep the exact
same background from the reference image. No replacements, no changes, no
new objects, no layout shifts. The environment must look identical.

The image must be recreated as if it was shot on a Sony A1, using an 85mm
f1.4 lens, at f1.6, ISO 100, 1/200 shutter speed, cinematic shallow depth
of field, perfect facial focus, and an editorial-neutral color profile.
This Sony A1 + 85mm f1.4 setup is mandatory. The final image must clearly
look like premium full-frame Sony A1 quality.

Lighting must match the exact direction, angle, and mood of the reference
photo. Upgrade the lighting into a cinematic, subject-focused style: soft
directional light, warm highlights, cool shadows, deeper contrast, expanded
dynamic range, micro-contrast boost, smooth gradations, and zero harsh
shadows.

Maintain neutral premium color tone, cinematic contrast curve, natural
saturation, real skin texture (not plastic), and subtle film grain. No fake
glow, no runway lighting, no over smoothing.

Render in 4K resolution, 10-bit color, cinematic editorial style, premium
clarity, portrait crop, and keep the original environmental vibe untouched.
Re-render the subject with improved realism, depth, texture, and lighting
while keeping identity and background fully preserved.

NEGATIVE INSTRUCTIONS: No new background. No background change. No overly
dramatic lighting. No face morphing. No fake glow. No flat lighting. No
over-smooth skin.
```

**Por que ele funciona:**
1. Especificidade técnica concreta (Sony A1, 85mm f1.4, f1.6, ISO 100, 1/200)
2. Preservation explícita (identity + background)
3. Linguagem cinematográfica de iluminação (soft directional, warm/cool, micro-contrast)
4. Texture realism (real skin, film grain, no plastic)
5. Output specs claros
6. Negative instructions cirúrgicas
