# diretor-imagem — glossário: linguagem natural → vocabulário técnico

Lido no Passo 3, antes de traduzir o briefing para vocabulário técnico.

## Glossário: linguagem natural → vocabulário técnico

Esta é a peça central. Quando o usuário fala em PT-BR coloquial, você traduz
para a linguagem que os modelos de IA entendem com precisão.

### Iluminação — vocabulário cinematográfico

**Direção da luz (sempre especifique):**

| Conceito casual | Vocabulário técnico |
|---|---|
| "luz da janela" | `motivated by practical window light from camera-[side], soft directional` |
| "luz dura" | `hard directional light, defined shadow edges, single point source` |
| "luz suave" | `soft diffused light, large source-to-subject ratio, gradient shadow falloff` |
| "contraluz", "atrás do sujeito" | `backlight / rim light from behind, separating subject from background, halation on hair edges` |
| "luz por cima" | `top light / overhead key, motivated by skylight or pendant practical` |
| "luz embaixo" | `under-lighting / accent uplight, motivated by [practical source]` |

**Esquemas clássicos (use o nome — modelos reconhecem):**

- `three-point lighting` — key + fill + rim/back
- `Rembrandt lighting` — triângulo de luz na bochecha oposta à fonte (retrato)
- `butterfly lighting` / `Paramount` — luz frontal alta, sombra de borboleta sob o nariz
- `split lighting` — metade do rosto na luz, metade na sombra
- `loop lighting` — pequena sombra do nariz curvada para a bochecha
- `chiaroscuro` — alto contraste, fortes sombras, drama
- `high-key` — predominância de tons claros, baixo contraste, alegre/clínico
- `low-key` — predominância de tons escuros, alto contraste, dramático
- `motivated lighting` — toda fonte tem origem visível ou plausível na cena

**Temperatura e mood (especifique em Kelvin quando importar):**

- Golden hour: `warm 3200-4500K, low-angle directional, long shadows, atmospheric haze`
- Blue hour: `cool 8000-10000K, ambient diffuse, no direct sun, deep shadow saturation`
- Midday: `neutral 5600K, top-down hard sun, deep contact shadows`
- Overcast: `5500-6500K, soft omnidirectional diffusion, shadowless`
- Tungsten interior: `warm 3200K practicals, cooler 5600K window fill mix`
- Cinema teal-orange: `warm 4500K key, cool 7500K fill, complementary color grade`

**Color grading (descreva o look):**

- `bleach bypass` — alto contraste, dessaturado, cinza-prateado (ex: Saving Private Ryan)
- `teal & orange` — Hollywood blockbuster
- `faded film stock` — Kodak Vision3 emulation, lifted blacks, organic grain
- `Fujifilm Pro 400H emulation` — verdes pastel, rosas suaves
- `ARRI Alexa LogC + REC.709` — neutral cinema baseline
- `editorial neutral` — magazine-grade, true skin, no stylization

### Atmosfera e profundidade

| Usuário diz | Comando técnico |
|---|---|
| "com névoa", "atmosférico" | `atmospheric haze, volumetric particulate, light shafts visible, depth-graded fog` |
| "poeira no ar" | `airborne dust motes catching backlight, organic particulate texture` |
| "fumaça" | `theatrical haze, motivated smoke, ambient diffusion at midground` |
| "fundo desfocado" | `cinematic shallow depth of field, smooth bokeh, defocused background, [aperture] f1.4-f2` |
| "tudo nítido" | `deep focus, hyperfocal distance, f8-f11, sharp foreground to background` |
| "profundidade", "camadas" | `layered composition: defined foreground / midground / background, atmospheric perspective enhancing depth` |
| "vidro/reflexo" | `physically accurate reflections, fresnel falloff, no plastic highlights` |
| "molhado/chuva" | `surface wetness with realistic specularity, light refraction through droplets, no plastic look` |

### Mood/atmosfera narrativa

| Usuário diz | Tradução |
|---|---|
| "ficar mais cinematográfico" | `cinematic anamorphic look, 2.39:1 aspect, lens flare horizontal streaks, organic film grain` |
| "premium / alto padrão" | `editorial premium, AD Magazine aesthetic, refined restraint, considered composition` |
| "moody / pesado" | `chiaroscuro lighting, lifted shadows with deep contrast, melancholic palette` |
| "leve / arejado" | `high-key lighting, airy negative space, soft diffusion, hopeful palette` |
| "vintage / analógico" | `35mm film emulation, organic grain, halation on highlights, mild gate weave` |
| "documental / verdade" | `naturalistic lighting, available light only, no color stylization, candid framing` |
