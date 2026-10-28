# diretor-imagem — anatomia do prompt de imagem

Lido no Passo 4, ao montar prompt de imagem ou de text-to-video (que usa os blocos 1-2 e 4-7 daqui).

## Anatomia do prompt — Imagem

Checklist das camadas; o texto final de imagem segue o template enxuto do
Princípio 11 (80-180 palavras) — cada bloco vira uma ou duas frases.

```
[1. SUBJECT & ACTION]
[Quem/o quê + ação/pose, 1-2 frases. Específico e visualmente concreto.]

[2. ENVIRONMENT]
Setting: [tipo de espaço]. Foreground: [elementos próximos, escala, material].
Midground: [elemento central, posição, condição]. Background: [contexto distante,
atmospheric perspective]. Surfaces: [materiais visíveis com textura específica].
Atmosphere: [haze/dust/clarity], [time of day exato], [season if relevant].

[3. PRESERVATION — apenas se houver imagem de referência]
Preserve [identity / background / architecture / proportions] from the reference.
Do not [list of forbidden changes].

[4. CAMERA & LENS — MANDATORY]
The image must be captured as if shot on a [BODY], with a [FOCAL] [LENS_TYPE]
lens, at [APERTURE], ISO [ISO], 1/[SHUTTER] shutter speed, [DOF descriptor],
[focus point], editorial-neutral color profile. This [BODY] + [FOCAL] setup
is mandatory. The final image must look like premium full-frame [BODY] capture.

[5. LIGHTING — specify direction, source, temperature, mood]
Lighting scheme: [three-point / Rembrandt / chiaroscuro / etc].
Key light: [position, source motivation, temperature in K, hardness].
Fill: [position, ratio to key, temperature].
Rim/back: [if present, position, intensity].
Practicals: [visible light sources in frame].
Atmospheric: [haze, particulate, light shafts].
Mood descriptors: soft directional, warm highlights, cool shadows, deeper
contrast, expanded dynamic range, micro-contrast boost, smooth gradations,
zero harsh shadows.

[6. COLOR & TEXTURE]
Color grade: [look reference: bleach bypass / teal-orange / faded film / neutral].
Maintain natural saturation, cinematic contrast curve, [real skin texture /
authentic material grain], subtle natural film grain. No fake glow, no
over-smoothing, no plastic finish.

[7. OUTPUT SPECS]
Render in 8K resolution, 10-bit color depth, REC.2020 wide gamut, cinematic
editorial style, premium clarity, [crop format: portrait 4:5 / landscape 3:2
/ vertical 9:16 / square / cinema 2.39:1].

[8. NEGATIVE INSTRUCTIONS]
NEGATIVE INSTRUCTIONS: [tailored list — see library below].
```
