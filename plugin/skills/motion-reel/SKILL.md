---
name: motion-reel
description: >-
  Cria Reel 9:16, vinheta ou filme 16:9 narrado em motion design com Remotion:
  tipografia cinética, 3D, transições na batida, trilha + SFX e MP4 pronto. Use
  em "faz um reel/vinheta/vídeo", "motion design" ou "vídeo com narração".
---

# motion-reel

Um projeto Remotion pronto que vira ponto de partida de toda peça nova. Você não escreve do
zero: copia o template e troca roteiro, marca e cenas. Ele traz duas bases:

| Base | Composição | Quem manda no tempo | Quando |
|---|---|---|---|
| **Reel** | `Reel` (1080×1920) | a música: cortes na batida do `timeline.json` | vinheta, anúncio curto sem voz (até ~40 s) |
| **Film** | `Master169` (1920×1080) e `Reel916` (1080×1920) | a voz: cada cena dura o que as falas dela duram | explicativo, lançamento com narração, versão 16:9 + corte 9:16 do mesmo roteiro; também sem voz (duração por `min`) |

- `assets/template/`: projeto completo (Remotion 4.0.484 travado no lockfile)
  - Reel: `src/timeline.json` (fonte única de tempo), `src/scenes.tsx` (cenas-modelo), `src/Reel.tsx`
  - Film: `film.json` (roteiro por formato), `vo.json` (falas), `blocks.json` (blocos de TTS), `src/Film.tsx`, `src/film-scenes.tsx` (cenas responsivas), `src/desktop.tsx` (Claude Code Desktop estilizado), `src/motifs.tsx` (mini-animações de painel)
  - comuns: `src/transitions.tsx` (as 10 transições, nos dois formatos) e `src/lib.tsx` (primitivas, paleta `C`, fonte, `BRAND`)
  - `assets/template/scripts/`: `track.py` (trilha do Reel), `track_cinema.py` (trilha do Film), `build-timeline.py`, `blocks-text.py`, `dl.sh`, `split-vo.py`, `stills.mjs`, `grain.py`
- `assets/fonts/`, `assets/sfx/`, `assets/logos/`: Plus Jakarta Sans (OFL), 7 SFX de síntese própria (`soft-click.wav` etc.) e logos placeholder "SUA MARCA"
- `scripts/new.sh`, `qa.sh`, `final.sh`: criar, revisar, entregar (os dois últimos recebem a composição)
- `references/vocabulario.md`: cada técnica e cena, onde está e quando usar. **Leia antes de roteirizar.**
- `references/transicoes.md`: tabela das transições e regras de ritmo
- `references/narracao.md`: de onde vem a voz (gravação própria, `say` do macOS ou ElevenLabs), corte por fala e timeline guiada pela voz
- `references/armadilhas.md`: bugs já pisados. **Leia antes de mexer em 3D, cor, áudio ou render.**

Requisitos: Node.js 18+ com npm, `ffmpeg` e um `python3` com `numpy` (o `py.sh` diz como
criar um venv se faltar). O primeiro render baixa o Chrome headless do Remotion (~90 MB).

## Fluxo

1. **Briefing → beats.** Pegue o texto exato do usuário e quebre em telas de uma ideia
   (0,5–1,5 s no Reel; no Film, uma fala por ideia). Número grande primeiro, apoio depois.
   - Corrija só a ortografia. Mudança de estilo (ex.: "14hs" → "14h") você diz em 1 frase.
   - Nome de produto, modelo ou versão que você não reconhece: sinalize em 1 frase e siga como pedido.
   - Vídeo de referência: baixe com `yt-dlp -o <arquivo> <url>` e extraia quadros com `ffmpeg` (2 fps só na região que interessa, montados numa folha com `tile`). Música e SFX não se deduzem de imagem.
   - Escolha a base pela tabela acima. Com narração ou com 16:9, é o Film.
2. **Marca.** Pergunte uma vez se há logo e paleta. Com os PNGs (fundo transparente), crie o
   projeto com `MOTION_LOGO_LIGHT` (logo para fundo claro), `MOTION_LOGO_DARK` (para fundo escuro)
   e `MOTION_MARK` (símbolo). Sem eles, os placeholders "SUA MARCA" ficam e isso vai no `PENDENTE:`.
   - Troque `BRAND` e a paleta `C` no `src/lib.tsx`. Outra fonte: `MOTION_FONT` + o nome em `FONT` e `useFont`.
3. **Criar o projeto:** `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/new.sh <pasta>`
   - Por padrão, use o scratchpad da sessão; se o usuário quiser guardar, a pasta que ele indicar.
   - O projeto sai renderizável nas três composições (o Film de exemplo ainda sem voz).
4. **Roteiro.**
   - **Reel:** no `timeline.json`, cada cena tem `cut` (frame em que a transição passa do meio, múltiplo de 15 a 120 BPM), `in` (transição) e `d` (duração). `music` traz `bpm`, `groove_from`, `drop_at`, `break_beats` e `outro_from`; `cues` traz sons dentro da cena (`{"at": "cena+frames", "sfx", "gain", "repeat", "every"}`). `total` é o frame final.
   - **Film:** no `film.json`, uma lista de cenas por formato (`master`, `reel`). Cada cena: `type` (cena de `SCENES`), `vo` (ids das falas), `props` (textos), `in` (opcional: sem ele, o ciclo escolhe sem repetir), `mark` (`braam`, `finale`, `hit`, `drop`, `pulse`), `energy` (0 tenso · 1 calmo · 2 andando · 3 cheio), `pre`/`gap`/`post`/`min` (frames) e `cues`. `letterbox: "title"` põe faixas pretas até a primeira cena desse tipo. O `reel` é um corte do `master`: reuse as mesmas falas.
   - SFX disponíveis: `soft-click`, `dry-pop`, `soft-whoosh`, `low-hit`, `short-rise`, `soft-chime`, `paper-tap`. As transições já soam sozinhas.
5. **Narração (só Film com voz).** Siga `references/narracao.md`. Pergunte de onde vem a voz; os dois primeiros caminhos não custam nada:
   - **a própria voz:** a pessoa grava cada bloco com uma pausa entre as falas, você converte para `out/vo-blocks/<bloco>.mp3` e o `split-vo.py` corta por fala;
   - **`say` do macOS:** detecte a voz pt-BR com `say -v '?'` (não fixe o nome, ele muda de máquina para máquina) e gere uma fala por arquivo em `public/vo/<id>.wav`;
   - **ElevenLabs (pago):** falas no `vo.json`, blocos no `blocks.json`, texto do TTS pelo `blocks-text.py`. Diga ao dono o total de caracteres que ele imprime (≈ créditos) **antes** de gerar e espere o ok; depois **1 bloco de teste** antes dos outros, download pelo `dl.sh`, corte pelo `split-vo.py`.

   Sem voz, pule: o `build-timeline.py` estima a duração pelo texto e avisa.
6. **Cenas.**
   - Reel: adapte as de `scenes.tsx`; os textos do exemplo (kit, modelos, comando `/plugin`) saem todos. Registre cena nova no mapa `SCENES` do `Reel.tsx`; íris nova precisa de origem no `ORIGIN`. As cenas do Reel têm layout fixo em 1080×1920.
   - Film: as de `film-scenes.tsx` leem tudo por props e se ajustam ao formato pelo `useL()` (guia segura de cada formato). Cena nova segue o molde: `useF()` (nunca `useCurrentFrame()`), `useL()`, `bt(p, i)` para animar em cima da fala i, `first(p)` como entrada do primeiro elemento (nunca tela vazia na transição), `fit()` para a fonte caber. Registre em `SCENES` e, se tiver som próprio, espelhe os pontos no `SFX_BY_TYPE` do `track_cinema.py`.
7. **QA:** `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/qa.sh <projeto> [Reel|Master169|Reel916]`. Ele refaz a timeline e a trilha, roda o tsc, renderiza a prévia em 50% e monta em `out/qa-<comp>/`:
   - `sheet-N.jpg`: 2 fps
   - `transitions-N.jpg`: início, meio e fim de cada transição
   - `safe.jpg`: 1 fps com a guia segura do formato

   Leia as folhas, não screenshots soltos. Para conferir poucas cenas sem renderizar tudo: `node <projeto>/scripts/stills.mjs <comp> 0.2,0.8 0.4 <índices>`. Corrija e rode de novo. Verifique:
   - palavra cortada na borda ou texto fora da guia
   - transição revelando tela vazia, emenda de 1 px depois de glitch/spin
   - 3D achatado, acentos, logo esticado ou placeholder esquecido
   - no Film, animação caindo na fala certa (o número aparece quando a voz o diz)
8. **Entrega:** `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/final.sh <projeto> <nome> [Reel|Master169|Reel916]`. Ele renderiza, converte para `yuv420p`, normaliza o áudio em −14 LUFS (pico −1 dBTP), imprime `ffprobe` e loudness e, acima de 30 MB, gera também `<nome>-leve.mp4`. Entregue o caminho do MP4 (para o celular, o leve) e reporte:
   - a saída do tsc e do ffprobe (lint: o projeto não tem)
   - **o áudio não foi ouvido** (trilha sintética + SFX nunca auditados): peça para o dono escutar; ofereça uma versão só com SFX se ele for usar música da plataforma
   - os textos que você mudou ou acrescentou
   - `PENDENTE:` com nomes a confirmar, logos placeholder e onde guardar o projeto (o scratchpad some com a sessão)

## Linguagem visual (padrão do template)

Papel, ink, um azul como acento de dado e um fundo night; sans geométrica pesada; ênfase de
título vazada (nunca itálico nem cor); CTA em pílula preta; mono só em comando. Sem gradiente
decorativo, glow ou glass: o impacto vem da coreografia. Com outra marca, troque as cores e
mantenha as regras. Curva da casa: `cubic-bezier(.22,1,.36,1)`.

## Abertura e assinatura

A `Intro` e o `Outro` do Reel e as cenas `title` e `outro` do Film usam o símbolo da pessoa
(`public/marca.png`, o `MOTION_MARK` do `new.sh`), que entra com escala. Com `"symbol": false`
(na cena do `timeline.json` ou nas `props` do `film.json`) a cena fica sem símbolo. Nenhuma cena
desenha marca própria do template: o que aparece é sempre o PNG de quem cria o projeto.

## Narração em pt-BR

- **Sem jargão.** Fala o benefício em linguagem simples; nome técnico só aparece na tela, como rótulo.
- **Pronúncia.** Nome em inglês que a voz erra vai no `say` do `blocks.json` com a grafia que soa
  certo ("Claude" → "Cláudi"), só no áudio; na tela continua a grafia original.

Não publique nada: gerar o vídeo não autoriza postar.
