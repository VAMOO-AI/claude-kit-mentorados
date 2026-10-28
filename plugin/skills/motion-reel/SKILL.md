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
zero: copia o template e troca roteiro, marca e cenas. Cada passo aponta um arquivo em
`references/`: **leia o arquivo no passo que o cita**, mesmo que já tenha lido antes (depois de
uma compactação, só o começo desta skill volta ao contexto).

## Regras duras

- **Não publique nada: gerar o vídeo não autoriza postar.**
- **Número, nome e afirmação só entram no vídeo com fonte**, seja uma URL ou um material que a
  pessoa deu. Sem fonte, corte ou pergunte.
- **Texto do usuário:** corrija só a ortografia. Mudança de estilo (ex.: "14hs" → "14h") você diz
  em 1 frase. Nome de produto, modelo ou versão que você não reconhece: sinalize em 1 frase e siga.
- **ElevenLabs (pago):** diga ao dono o total de caracteres que o `blocks-text.py` imprime
  (≈ créditos) **antes** de gerar e espere o ok; depois **1 bloco de teste** antes dos outros.
- **Pré-aprovação (`allowed-tools`):** logos por flag no `new.sh`, nunca `MOTION_*=… new.sh`
  (comando precedido de variável não casa a regra e a pessoa teria de clicar em Permitir). Os
  scripts do projeto rodam de dentro da pasta, em caminho relativo
  (`cd <projeto> && python3 ./scripts/split-vo.py`).
- **Leia as folhas, não screenshots soltos**, no QA e no MP4 final.
- **`final.sh` com exit 1 = reprovado:** o novo vira `out/<nome>-reprovado.mp4` e não se entrega.
- O relatório de entrega sempre traz "áudio não ouvido" em **não verificado**.
- **Cena nova do Film:** `useF()` (nunca `useCurrentFrame()`) e `first(p)` como entrada do primeiro
  elemento (nunca tela vazia na transição).
- **Visual:** ênfase de título vazada, nunca itálico nem cor (exceção: preset `apresentacao`); o
  acento nunca vai em dado nem em CTA; sem gradiente decorativo, glow ou glass fora dos presets
  `glass` e `logo3d`.

## Base

| Base | Composição | Quem manda no tempo | Quando |
|---|---|---|---|
| **Reel** | `Reel` (1080×1920) | a música: cortes na batida do `timeline.json` | vinheta, anúncio curto sem voz (até ~40 s) |
| **Film** | `Master169` (1920×1080) e `Reel916` (1080×1920) | a voz: cada cena dura o que as falas dela duram | explicativo, lançamento com narração, versão 16:9 + corte 9:16 do mesmo roteiro; também sem voz (duração por `min`) |

Filmes prontos (`film.json` completos): `presets/lancamento.json`, `presets/explicativo.json`
(o exemplo resolvido do briefing), `presets/apresentacao.json` e `presets/lancamento-app.json`.
Mapa do template (arquivos, presets, cenas avulsas, scripts, fontes e SFX): **leia
[references/template.md](references/template.md)** ao criar o projeto ou procurar um arquivo.

Requisitos: Node.js 18+ com npm, `ffmpeg` e um `python3` com `numpy` (o `py.sh` diz como
criar um venv se faltar). O primeiro render baixa o Chrome headless do Remotion (~90 MB).

## Fluxo

1. **Briefing → beats.** **Leia [references/briefing-e-projeto.md](references/briefing-e-projeto.md)
   e preencha o [references/briefing-motion.md](references/briefing-motion.md). Comece por ele.**
   Texto exato do usuário em telas de uma ideia (0,5–1,5 s no Reel; no Film, uma fala por ideia),
   a tabela de cenas com os reads e o checklist (evento em toda cena, transição motivada, final que
   rima com a abertura, por que cada coisa se move). A tabela vira o `film.json`. Com narração ou
   com 16:9, é o Film.
2. **Marca.** **Leia [references/briefing-e-projeto.md](references/briefing-e-projeto.md)** (passo 2:
   logos, `BRAND`, paleta `C`, fonte). Guia de vídeo da casa (`.context/docs/motion.md` no projeto ou
   `~/.claude/docs/motion-reel-casa.md`) antes de perguntar; sem guia, pergunte uma vez se há logo e
   paleta. Sem os PNGs, os placeholders "SUA MARCA" ficam e vão no `PENDENTE:`. Paleta, ênfase,
   símbolo e curva da casa: **leia [references/linguagem-visual.md](references/linguagem-visual.md)**.
3. **Criar o projeto:** `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/new.sh [--logo-light <png>] [--logo-dark <png>] [--mark <png>] [--serif <ttf>] <pasta>`
   (padrão: scratchpad da sessão). **Leia [references/briefing-e-projeto.md](references/briefing-e-projeto.md)
   (passo 3) e [references/template.md](references/template.md)** antes de criar. Para escolher cena e transição com a pessoa:
   `python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/galeria.py <projeto>`; depois de mexer
   em cena, fonte ou `fit()`, a bancada de texto `galeria.py <projeto> --pior-caso`.
4. **Roteiro.** **Leia [references/roteiro-e-cenas.md](references/roteiro-e-cenas.md) e
   [references/vocabulario.md](references/vocabulario.md)** antes de escrever o `timeline.json`
   (Reel) ou o `film.json` (Film). Transições e ritmo: [references/transicoes.md](references/transicoes.md).
5. **Narração (só Film com voz).** **Leia [references/narracao.md](references/narracao.md)** e
   pergunte de onde vem a voz: a própria (gravada por bloco, cortada pelo `split-vo.py`), a do
   sistema (`python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/voz.py <projeto>`, grátis) ou
   ElevenLabs (pago, regra dura acima). Sem voz, pule. Fala sem jargão (nome técnico só na tela,
   como rótulo); nome em inglês que a voz erra vai no `say` do `blocks.json` ("Claude" → "Cláudi").
6. **Cenas.** **Leia [references/roteiro-e-cenas.md](references/roteiro-e-cenas.md) antes de
   escrever cena nova** (o molde do Reel e do Film). **Leia
   [references/armadilhas.md](references/armadilhas.md) antes de mexer em 3D, cor, áudio ou render.**
7. **QA:** `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/qa.sh <projeto> [Reel|Master169|Reel916]`.
   **Leia [references/qa-e-entrega.md](references/qa-e-entrega.md)** antes: as folhas, o `stills.mjs`
   e o que verificar.

   **Revisão de motion.** Leia cada `transitions-N.jpg` e, onde ficar dúvida, todos os quadros do
   trecho com `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/revisar.sh faixa <mp4> <início> <fim>`.
   Em cada troca: aparecem dois estados sobrepostos? a curva para de repente? a escala cresce do
   ponto certo? opacidade, posição e cor andam em sincronia? Cada achado vira uma linha de
   `| Antes | Depois | Por quê |` e a revisão termina com **Bloqueia** ou **Aprova**. Corrija
   nesta ordem: apagar a animação, reduzir, trocar a curva, corrigir a origem e só então polir.
   Foco, transições, pausa e zoom são o Checklist da folha, no fim da doutrina do
   `references/vocabulario.md`.
8. **Entrega:** `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/final.sh <projeto> <nome> [Reel|Master169|Reel916]`.
   **Leia [references/qa-e-entrega.md](references/qa-e-entrega.md)** antes: o que o `final.sh` gera,
   o que ler no MP4 final e o relatório (fatos e fontes, decisões, não verificado, verificação,
   textos mudados, `PENDENTE:`). Entregue o caminho do MP4 (para o celular, o leve) com esse relatório.
