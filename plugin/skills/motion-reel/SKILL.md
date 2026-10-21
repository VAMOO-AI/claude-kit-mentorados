---
name: motion-reel
description: >-
  Cria Reel 9:16, vinheta ou filme 16:9 narrado em motion design com Remotion:
  tipografia cinética, 3D, transições na batida, trilha + SFX e MP4 pronto. Use
  em "faz um reel/vinheta/vídeo", "motion design" ou "vídeo com narração".
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/new.sh *) Bash(${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/qa.sh *) Bash(${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/final.sh *) Bash(${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/py.sh *) Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/voz.py *) Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/galeria.py *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/new.sh *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/qa.sh *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/final.sh *) Bash(${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/revisar.sh *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/revisar.sh *) Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/srt.py *) Bash(npx remotion *) Bash(npx tsc *) Bash(ffmpeg *) Bash(ffprobe *) Bash(node ./scripts/stills.mjs *) Bash(python3 ./scripts/blocks-text.py *) Bash(python3 ./scripts/split-vo.py *) Bash(python3 ./scripts/build-timeline.py *) Bash(python3 ./scripts/track_cinema.py *) Bash(python3 ./scripts/track.py *) Bash(bash ./scripts/dl.sh *) PowerShell(npx remotion *) PowerShell(npx tsc *) PowerShell(ffmpeg *) PowerShell(ffprobe *) PowerShell(node ./scripts/stills.mjs *) PowerShell(python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/voz.py *) PowerShell(python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/galeria.py *)
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
  - presets do Film: `launch` (título cinético + revelação), `beats` (3 batidas de benefício), `glass` (vidro com refração para cards de texto e número) e `logo3d` (o símbolo da pessoa extrudado, assinatura); `presets/lancamento.json` é um `film.json` pronto com os quatro (16:9 + corte 9:16, sem voz, na batida). Quando usar cada um: `references/vocabulario.md`
  - `presets/apresentacao.json`: apresentação pessoal de 15 s (`pillname` → `orbit` → `highlights` → `follow`): nome com a pílula que vira o "O", foto com texto em órbita, 3 destaques com número que conta e o botão Seguir clicado; cenas em `src/scenes-apresentacao.tsx`
  - `presets/explicativo.json`: explicativo de negócio de ~20 s em 5 cenas (`statement` → `title` → `beats` → `glass` → `logo3d`): o problema, o que você faz, como funciona em 3 passos, uma prova com número e fonte, e o nome; 16:9 + corte 9:16, sem voz, na batida. É o exemplo resolvido do `references/briefing-motion.md`
  - `presets/lancamento-app.json`: lançamento de app de 30 s (`logo3d` → 5 × `appline` → `assemble`): uma frase por cena, palavra por palavra com rastro, a UI de cada frase e as peças que montam o logo; cenas em `src/scenes-app.tsx`, transição `echo`
  - cenas avulsas (sem preset, entram em qualquer `film.json`): `src/scenes-extras.tsx` (`swap`, troca de frase com letras que viajam por um portal; `morph`, uma forma que morfa por até 8 estados; `ranking` e `versus`, posições e comparação lado a lado com número que conta) e `src/scenes-mapa.tsx` (`map`, rota e região sobre o Natural Earth); `"motionBlur": true` no `film.json` liga o motion blur real nas transições rápidas; tabela em `references/vocabulario.md`, exemplo de cada uma na galeria
  - comuns: `src/transitions.tsx` (as 11 transições, nos dois formatos) e `src/lib.tsx` (primitivas, paleta `C`, fonte, `BRAND`)
  - `assets/template/scripts/`: `track.py` (trilha do Reel), `track_cinema.py` (trilha do Film), `build-timeline.py`, `blocks-text.py`, `dl.sh`, `split-vo.py`, `stills.mjs`, `grain.py`
- `assets/fonts/`, `assets/sfx/`, `assets/logos/`: Plus Jakarta Sans (OFL), 7 SFX de síntese própria (`soft-click.wav` etc.) e logos placeholder "SUA MARCA"; Instrument Serif Italic (OFL), a serifada da ênfase dos presets, que o `new.sh` copia para `public/serif-italic.ttf` (`--serif <ttf>` põe a da sua marca)
- `scripts/new.sh`, `qa.sh`, `final.sh`: criar, revisar, entregar (os dois últimos recebem a composição)
- `scripts/voz.py`: narração grátis do Film na voz do sistema (`say` no macOS, System.Speech no Windows), uma fala por WAV, com cache por hash em `public/vo/.voz.json` (fala editada sai de novo sozinha)
- `scripts/srt.py`: legenda do Film (texto do `vo.json` no tempo da voz); o `final.sh` chama
- `scripts/revisar.sh`: zooms de revisão de um MP4 (`faixa` com todos os quadros de um trecho, `recorte` em resolução cheia, `transicoes` com 12 quadros em volta de cada corte)
- `scripts/galeria.py`: um quadro de cada cena do Film, de cada transição e de cada cena do Reel, com a marca do projeto, para escolher antes de roteirizar
- `references/briefing-motion.md`: o briefing em cinco partes (entradas, direção com proibidos, estrutura em tabela, construção, armadilhas), o mapa conteúdo → cena, os reads e o checklist do storyboard. **Comece por ele.**
- `references/vocabulario.md`: cada técnica e cena, onde está e quando usar. **Leia antes de roteirizar.**
- `references/transicoes.md`: tabela das transições e regras de ritmo
- `references/narracao.md`: de onde vem a voz (gravação própria, voz do sistema pelo `voz.py` ou ElevenLabs), corte por fala e timeline guiada pela voz
- `references/armadilhas.md`: bugs já pisados. **Leia antes de mexer em 3D, cor, áudio ou render.**

Requisitos: Node.js 18+ com npm, `ffmpeg` e um `python3` com `numpy` (o `py.sh` diz como
criar um venv se faltar). O primeiro render baixa o Chrome headless do Remotion (~90 MB).

## Fluxo

1. **Briefing → beats.** Pegue o texto exato do usuário e quebre em telas de uma ideia
   (0,5–1,5 s no Reel; no Film, uma fala por ideia). Número grande primeiro, apoio depois.
   - Preencha o `references/briefing-motion.md`: entradas perguntadas de uma vez, direção, a tabela de cenas com os reads de cada uma (o que o espectador lê, um por vez, a 2,5 palavras/s + 0,5 s) e o checklist (evento em toda cena, transição motivada, final que rima com a abertura). A tabela vira o `film.json`.
   - Corrija só a ortografia. Mudança de estilo (ex.: "14hs" → "14h") você diz em 1 frase.
   - Nome de produto, modelo ou versão que você não reconhece: sinalize em 1 frase e siga como pedido.
   - Vídeo de referência: baixe com `yt-dlp -o <arquivo> <url>` e extraia quadros com `ffmpeg` (2 fps só na região que interessa, montados numa folha com `tile`). Música e SFX não se deduzem de imagem.
   - Escolha a base pela tabela acima. Com narração ou com 16:9, é o Film.
2. **Marca.** Pergunte uma vez se há logo e paleta. Com os PNGs (fundo transparente), crie o
   projeto com `--logo-light` (logo para fundo claro), `--logo-dark` (para fundo escuro) e `--mark`
   (símbolo) no `new.sh`. Sem eles, os placeholders "SUA MARCA" ficam e isso vai no `PENDENTE:`.
   - Troque `BRAND` e a paleta `C` no `src/lib.tsx`. Outra fonte: `MOTION_FONT` + o nome em `FONT` e `useFont`. Sem a fonte principal em `public/`, o render (e a galeria) para com o nome do arquivo, em vez de sair em system-ui.
3. **Criar o projeto:** `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/new.sh [--logo-light <png>] [--logo-dark <png>] [--mark <png>] [--serif <ttf>] <pasta>`
   - Passe os logos por flag, não por `MOTION_*=… new.sh`: a pré-aprovação da skill (`allowed-tools`) não vale para comando precedido de variável, e a pessoa teria de clicar em Permitir.
   - Os scripts do projeto (`./scripts/stills.mjs`, `./scripts/*.py`, `./scripts/dl.sh`) rodam de dentro da pasta do projeto, em caminho relativo (`cd <projeto> && python3 ./scripts/split-vo.py`): é a forma que a pré-aprovação cobre.
   - Por padrão, use o scratchpad da sessão; se o usuário quiser guardar, a pasta que ele indicar.
   - O projeto sai renderizável nas três composições (o Film de exemplo ainda sem voz).
   - Para escolher cena e transição com a pessoa: `python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/galeria.py <projeto>` → `out/galeria/index.html` (só texto, sem render: `--lista`). O roteiro não muda.
4. **Roteiro.**
   - **Reel:** no `timeline.json`, cada cena tem `cut` (frame em que a transição passa do meio, múltiplo de 15 a 120 BPM), `in` (transição) e `d` (duração). `music` traz `bpm`, `groove_from`, `drop_at`, `break_beats` e `outro_from`; `cues` traz sons dentro da cena (`{"at": "cena+frames", "sfx", "gain", "repeat", "every"}`). `total` é o frame final.
   - **Film:** no `film.json`, uma lista de cenas por formato (`master`, `reel`). Cada cena: `type` (cena de `SCENES`), `vo` (ids das falas), `props` (textos), `in` (opcional: sem ele, a cena herda a corrente, `"current"` no `film.json`, padrão `whip`), `mark` (`braam`, `finale`, `hit`, `drop`, `pulse`), `energy` (0 tenso · 1 calmo · 2 andando · 3 cheio), `pre`/`gap`/`post`/`min` (frames) e `cues`. `letterbox: "title"` põe faixas pretas até a primeira cena desse tipo. O `reel` é um corte do `master`: reuse as mesmas falas.
   - SFX disponíveis: `soft-click`, `dry-pop`, `soft-whoosh`, `low-hit`, `short-rise`, `soft-chime`, `paper-tap`. As transições já soam sozinhas.
   - Leitura (Film): o `build-timeline.py` conta as palavras da tela de cada cena e avisa "leitura curta" quando a cena dura menos que 2,5 palavras/s + 0,5 s; o cálculo fica em `read` na timeline e o storyboard mostra. Se a contagem pega decoração, declare em `"read": [...]` na cena só o que precisa ser lido.
5. **Narração (só Film com voz).** Siga `references/narracao.md`. Pergunte de onde vem a voz; os dois primeiros caminhos não custam nada:
   - **a própria voz:** a pessoa grava cada bloco com uma pausa entre as falas, você converte para `out/vo-blocks/<bloco>.mp3` e o `split-vo.py` corta por fala;
   - **voz do sistema:** falas no `vo.json` e `python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/voz.py <projeto>`. Ele detecta a voz pt-BR (`say` no macOS, System.Speech no Windows): a Luciana quando instalada, senão a primeira que não é voz de novidade (Eddy, Flo...); outra com `--voz`, grava um WAV por fala em `public/vo/<id>.wav`, aplica a pronúncia do `blocks.json`, não sobrescreve a gravação da pessoa e refaz a timeline. Rodar de novo depois de editar o `vo.json`, o `say` do `blocks.json` ou a `--taxa` (só no macOS; no Windows a taxa não muda o áudio) gera só as falas que mudaram; WAV fora do manifesto `public/vo/.voz.json` é gravação da pessoa e fica, mesmo com `--refazer` (passe o id para substituir);
   - **ElevenLabs (pago):** falas no `vo.json`, blocos no `blocks.json`, texto do TTS pelo `blocks-text.py`. Diga ao dono o total de caracteres que ele imprime (≈ créditos) **antes** de gerar e espere o ok; depois **1 bloco de teste** antes dos outros, download pelo `dl.sh`, corte pelo `split-vo.py`.

   Sem voz, pule: o `build-timeline.py` estima a duração pelo texto e avisa.
6. **Cenas.**
   - Reel: adapte as de `scenes.tsx`; os textos do exemplo (kit, modelos, comando `/plugin`) saem todos. Registre cena nova no mapa `SCENES` do `Reel.tsx`; íris nova precisa de origem no `ORIGIN`. As cenas do Reel têm layout fixo em 1080×1920.
   - Film: as de `film-scenes.tsx` leem tudo por props e se ajustam ao formato pelo `useL()` (guia segura de cada formato). Cena nova segue o molde: `useF()` (nunca `useCurrentFrame()`), `useL()`, `bt(p, i)` para animar em cima da fala i, `first(p)` como entrada do primeiro elemento (nunca tela vazia na transição), `fit()` para a fonte caber. Registre em `SCENES` e, se tiver som próprio, espelhe os pontos no `SFX_BY_TYPE` do `track_cinema.py`.
7. **QA:** `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/qa.sh <projeto> [Reel|Master169|Reel916]`. Ele refaz a timeline e a trilha, roda o tsc, renderiza a prévia em 50% e monta em `out/qa-<comp>/`:
   - `sheet-N.jpg`: 2 fps
   - `transitions-N.jpg`: início, meio e fim de cada transição
   - `safe.jpg`: 1 fps com a guia segura do formato
   - aviso de cena parada (≥ 2 s) e quadro preto (≥ 0,5 s), com o trecho em segundos: confira se foi de propósito (cartão final segurado) ou se a cena travou

   Leia as folhas, não screenshots soltos. Para conferir poucas cenas sem renderizar tudo: `cd <projeto> && node ./scripts/stills.mjs <comp> 0.2,0.8 0.4 <índices>`, com os índices separados por espaço ou vírgula (`0 2 5` ou `0,2,5`). Corrija e rode de novo. Verifique:
   - palavra cortada na borda ou texto fora da guia
   - transição revelando tela vazia, emenda de 1 px depois de glitch/spin
   - 3D achatado, acentos, logo esticado ou placeholder esquecido
   - no Film, animação caindo na fala certa (o número aparece quando a voz o diz)
8. **Entrega:** `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/final.sh <projeto> <nome> [Reel|Master169|Reel916]`. Ele renderiza em `out/.staging-<nome>/` (encode que falha não toca no MP4 bom), converte para `yuv420p`, normaliza o áudio em −14 LUFS com limiter de pico verdadeiro em −1,5 dBTP e confere o MP4 que vai ser entregue, não a prévia:
   - `out/<nome>-folha.jpg`: folha de contato do final a 2 fps. Leia antes de entregar: o encode final pode mostrar o que a prévia a 50% escondia (banding, texto borrado, quadro preto)
   - `out/<nome>-loudness.txt`: integrado, pico verdadeiro, segundos mais altos e mais baixos, o segundo do pico e a lista segundo a segundo
   - aviso de cena parada e quadro preto no MP4 final, como no QA
   - `out/<nome>-transicoes/`: 12 quadros seguidos em volta de cada corte, em meia resolução. Leia procurando emenda de 1 px e tela vazia na troca; para olhar de perto, `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/revisar.sh recorte <mp4> <segundo> [x y largura altura]` (resolução cheia) e `revisar.sh faixa <mp4> <início> <fim>` (todos os quadros do trecho)
   - Film com voz: `out/<nome>.srt` (texto do `vo.json` no tempo de cada fala), embutido como faixa no 16:9. Fala sem WAV: sai sem legenda e avisa
   - **exit 1 = reprovado:** integrado fora de −14 ±1 LUFS ou pico acima de −1 dBTP. O novo vira `out/<nome>-reprovado.mp4` e não se entrega; o `<nome>.mp4` anterior, se havia, fica intacto. Ajuste o mix como a mensagem indica e rode de novo. Para reconferir um MP4 sem renderizar: `final.sh --verificar <arquivo.mp4>`
   - acima de 30 MB, e só se passou, sai também `<nome>-leve.mp4`

   **Antes de pôr na tela:** número, nome e afirmação só entram no vídeo com fonte, seja uma URL ou um material que a pessoa deu. Sem fonte, corte ou pergunte.

   Entregue o caminho do MP4 (para o celular, o leve) com este relatório:
   - **fatos e fontes:** cada número, nome ou afirmação que aparece na tela, com a fonte de cada um (URL ou "material da pessoa: <arquivo ou mensagem>")
   - **decisões:** paleta, presets e transições, ritmo (BPM, duração das cenas), voz (gravada, TTS ou sem narração) e o porquê de cada uma
   - **não verificado:** tudo o que você não conferiu, sem suavizar. Sempre entra "áudio não ouvido" (trilha sintética e SFX nunca escutados: peça para o dono ouvir e ofereça uma versão só com SFX se ele for usar música da plataforma); entram também fonte que você não abriu, logo placeholder, nome que a pessoa não confirmou
   - **verificação:** caminho da folha do final e da pasta de transições, integrado e pico do `loudness.txt`, os avisos de cena parada ou quadro preto (ou "sem aviso"), a legenda (se houver) e a saída do tsc e do ffprobe (lint: o projeto não tem)
   - os textos que você mudou ou acrescentou
   - `PENDENTE:` com nomes a confirmar, logos placeholder e onde guardar o projeto (o scratchpad some com a sessão)

## Linguagem visual (padrão do template)

Papel, ink, um azul como acento de dado e um fundo night; sans geométrica pesada; ênfase de
título vazada (nunca itálico nem cor; a exceção é o preset de apresentação, abaixo); CTA em pílula preta; mono só em comando. Sem gradiente
decorativo, glow ou glass: o impacto vem da coreografia. A exceção são os presets `glass` e
`logo3d`, que trazem vidro, luz e reflexo de propósito: use quando a peça pede (lançamento, número
em destaque, assinatura), não como fundo de toda cena. O preset `apresentacao` põe UMA palavra por frase em itálico
serifado no acento de conteúdo (`*palavra*` no texto; a serifada em `SERIF`, a cor em `C.hot`, laranja no
exemplo): é o pedido do formato, não vale para o resto. O acento nunca vai em dado nem em CTA. Com outra marca, troque as cores e
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
