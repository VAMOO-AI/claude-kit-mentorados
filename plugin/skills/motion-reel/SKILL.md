---
name: motion-reel
description: >-
  Cria Reel 9:16, vinheta ou anúncio de lançamento em motion design com
  Remotion: tipografia cinética, 3D, transições na batida, trilha + SFX e MP4
  pronto pro Instagram. Use em "faz um reel/vinheta", "motion design" ou
  "anima esse anúncio".
---

# motion-reel

Um projeto Remotion pronto (um reel de 33 s anunciando o próprio kit) que vira ponto de
partida de toda peça nova. Você não reescreve do zero: copia o template, troca o roteiro no
`timeline.json`, a marca no `lib.tsx` e adapta as cenas-modelo.

- `assets/template/`: projeto completo (Remotion 4.0.484 travado no lockfile)
  - `src/timeline.json`: **fonte única de tempo** (cenas, cortes, transições, música, cues)
  - `src/scenes.tsx`: cenas-modelo
  - `src/transitions.tsx`: as 10 transições
  - `src/lib.tsx`: primitivas, paleta `C`, fonte e nome da marca `BRAND`
  - `assets/template/scripts/track.py`: trilha
- `assets/fonts/`, `assets/sfx/`, `assets/logos/`: fonte Plus Jakarta Sans (OFL), 7 SFX de síntese própria (`soft-click.wav` etc.) e logos placeholder "SUA MARCA"
- `scripts/new.sh`, `qa.sh`, `final.sh`: criar, revisar, entregar
- `references/vocabulario.md`: cada técnica, onde está e quando usar. **Leia antes de roteirizar.**
- `references/transicoes.md`: tabela das transições e regras de ritmo
- `references/armadilhas.md`: bugs já pisados. **Leia antes de mexer em 3D, cor ou render.**

Requisitos: Node.js 18+ com npm, `ffmpeg` e um `python3` com `numpy` (o `py.sh` diz como
criar um venv se faltar). O primeiro `npm ci` baixa o Remotion e o Chrome headless dele.

## Fluxo

1. **Briefing → beats.** Pegue o texto exato do usuário e quebre em telas de uma ideia
   (0,5–1,5 s; frase de mais de 3 palavras fica ≥ 1,3 s; número grande primeiro, apoio depois).
   - Corrija só a ortografia. Mudança de estilo (ex.: "14hs" → "14h") você diz em 1 frase.
   - Nome de produto, modelo ou versão que você não reconhece: sinalize em 1 frase e siga como pedido, com o valor isolado no `timeline.json`.
   - Vídeo de referência: baixe com `yt-dlp -o <arquivo> <url>` e extraia quadros com `ffmpeg` (2 fps só na região que interessa, montados numa folha com `tile`). Música e SFX não se deduzem de imagem.
2. **Marca.** Pergunte uma vez se há logo e paleta. Com os PNGs (fundo transparente), crie o
   projeto com `MOTION_LOGO_LIGHT` (logo para fundo claro), `MOTION_LOGO_DARK` (para fundo escuro)
   e `MOTION_MARK` (símbolo). Sem eles, os placeholders "SUA MARCA" ficam e isso vai no `PENDENTE:`.
   - Troque `BRAND` e a paleta `C` no `src/lib.tsx`. Outra fonte: `MOTION_FONT` + o nome em `FONT` e `useFont`.
   - O `Outro` usa a proporção do logo placeholder (4958×1202) e o `Intro` a do símbolo (1512×702): logo com outra proporção, ajuste essas contas.
3. **Criar o projeto:** `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/new.sh <pasta>`
   - Por padrão, use o scratchpad da sessão; se o usuário quiser guardar, a pasta que ele indicar.
4. **Roteiro no `timeline.json`:**
   - Em cada cena, `cut` é o frame em que a transição passa do meio (múltiplo de 15 a 120 BPM), `in` é o tipo de transição e `d` a duração. Varie as transições.
   - `music`: `bpm`, `groove_from`, `drop_at` (clímax, com pausa e riser antes), `break_beats` e `outro_from`.
   - `cues`: `{"at": "cena+frames", "sfx": "...", "gain", "repeat", "every"}`, para sons dentro da cena. As transições já soam sozinhas.
   - SFX disponíveis: `soft-click`, `dry-pop`, `soft-whoosh`, `low-hit`, `short-rise`, `soft-chime`, `paper-tap`.
   - `total` é o frame final.
5. **Cenas:**
   - Adapte as de `scenes.tsx`; os textos do exemplo (kit, modelos, comando `/plugin`) saem todos. Cena nova segue o molde: `useF()` (nunca `useCurrentFrame()`), `Bg`, `ip`, `MaskUp`, `random(seed)`. Registre-a no mapa `SCENES` do `Reel.tsx`.
   - Uma íris nova precisa de origem no `ORIGIN`.
   - Formato diferente de 1080×1920: troque `W` e `H` em `scenes.tsx` e `transitions.tsx`, e o tamanho em `index.tsx`.
6. **QA:** `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/qa.sh <projeto>`. Ele confere se os cortes caem na batida, roda o tsc, gera a trilha, renderiza a prévia em 50% e monta três folhas:
   - `sheet-N.jpg`: 2 fps
   - `transitions.jpg`: início, meio e fim de cada transição
   - `safe.jpg`: 1 fps com a guia segura do Reel

   Leia as folhas, não screenshots soltos. Corrija e rode de novo. Verifique:
   - palavra cortada na borda
   - texto fora da guia (direita 180 e base 320 são dos botões do Instagram)
   - transição revelando tela vazia
   - 3D achatado
   - acentos
   - logo esticado ou placeholder esquecido
7. **Entrega:** `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/final.sh <projeto> <nome>`. Ele renderiza em 1080×1920, converte para `yuv420p` e imprime o `ffprobe` e o volume. Entregue o caminho do MP4 e reporte:
   - a saída do tsc e do ffprobe (lint: o projeto não tem)
   - **o áudio não foi ouvido** (batida sintética + SFX nunca auditados): peça para o dono escutar; ofereça uma versão só com SFX se ele for usar música do Instagram
   - os textos que você mudou ou acrescentou
   - `PENDENTE:` com nomes a confirmar, logos placeholder e onde guardar o projeto (o scratchpad some com a sessão)

## Linguagem visual (padrão do template)

Papel, ink, um azul como acento de dado e um fundo night; sans geométrica pesada; ênfase de
título vazada (nunca itálico nem cor); CTA em pílula preta; mono só em comando. Sem gradiente
decorativo, glow ou glass: o impacto vem da coreografia. Com outra marca, troque as cores e
mantenha as regras. Curva da casa: `cubic-bezier(.22,1,.36,1)`.

Não publique nada: gerar o vídeo não autoriza postar.
