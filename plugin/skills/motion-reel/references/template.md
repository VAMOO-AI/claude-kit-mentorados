# motion-reel — o que vem no template

Lido no passo 3 (criar o projeto) e sempre que precisar achar um arquivo, preset ou script do template.

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
  - `galeria.py <projeto> --pior-caso`: a bancada de texto (`presets/pior-caso.json`, que não é preset de filme): cada cena com texto no limite documentado e no limite + 1, assentada, em 9:16 e 16:9, mais o `Grande` do Reel com 7 e 8 letras, com a guia segura por cima (`out/galeria-pior-caso/`). Rode depois de mexer em cena, fonte ou `fit()`
- `references/briefing-motion.md`: o briefing em cinco partes (entradas, direção com proibidos, estrutura em tabela, construção, armadilhas), o mapa conteúdo → cena, os reads e o checklist do storyboard. **Comece por ele.**
- `references/vocabulario.md`: cada técnica e cena, onde está e quando usar. **Leia antes de roteirizar.**
- `references/transicoes.md`: tabela das transições e regras de ritmo
- `references/narracao.md`: de onde vem a voz (gravação própria, voz do sistema pelo `voz.py` ou ElevenLabs), corte por fala e timeline guiada pela voz
- `references/armadilhas.md`: bugs já pisados. **Leia antes de mexer em 3D, cor, áudio ou render.**

Requisitos: Node.js 18+ com npm, `ffmpeg` e um `python3` com `numpy` (o `py.sh` diz como
criar um venv se faltar). O primeiro render baixa o Chrome headless do Remotion (~90 MB).
