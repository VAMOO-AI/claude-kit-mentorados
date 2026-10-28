# motion-reel — briefing, marca e criação do projeto

Lido nos passos 1 a 3 do fluxo.

1. **Briefing → beats.** Pegue o texto exato do usuário e quebre em telas de uma ideia
   (0,5–1,5 s no Reel; no Film, uma fala por ideia). Número grande primeiro, apoio depois.
   - Preencha o `references/briefing-motion.md`: entradas perguntadas de uma vez, direção, a tabela de cenas com os reads de cada uma (o que o espectador lê, um por vez, a 2,5 palavras/s + 0,5 s) e o checklist (evento em toda cena, transição motivada, final que rima com a abertura, por que cada coisa se move). A tabela vira o `film.json`.
   - Corrija só a ortografia. Mudança de estilo (ex.: "14hs" → "14h") você diz em 1 frase.
   - Nome de produto, modelo ou versão que você não reconhece: sinalize em 1 frase e siga como pedido.
   - Vídeo de referência: baixe com `yt-dlp -o <arquivo> <url>` e extraia quadros com `ffmpeg` (2 fps só na região que interessa, montados numa folha com `tile`). Música e SFX não se deduzem de imagem.
   - Escolha a base pela tabela acima. Com narração ou com 16:9, é o Film.
2. **Marca.** Se existir um guia de vídeo da casa (`.context/docs/motion.md` no projeto ou
   `~/.claude/docs/motion-reel-casa.md`), siga-o antes de perguntar: ele diz de onde vêm logos,
   fonte, SFX e voz, e os padrões de cada tipo de peça. Sem guia, pergunte uma vez se há logo e paleta. Com os PNGs (fundo transparente), crie o
   projeto com `--logo-light` (logo para fundo claro), `--logo-dark` (para fundo escuro) e `--mark`
   (símbolo) no `new.sh`. Sem eles, os placeholders "SUA MARCA" ficam e isso vai no `PENDENTE:`.
   - Troque `BRAND` e a paleta `C` no `src/lib.tsx`. Outra fonte: `MOTION_FONT` + o nome em `FONT` e `useFont`. Sem a fonte principal em `public/`, o render (e a galeria) para com o nome do arquivo, em vez de sair em system-ui.
3. **Criar o projeto:** `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/new.sh [--logo-light <png>] [--logo-dark <png>] [--mark <png>] [--serif <ttf>] <pasta>`
   - Passe os logos por flag, não por `MOTION_*=… new.sh`: a pré-aprovação da skill (`allowed-tools`) não vale para comando precedido de variável, e a pessoa teria de clicar em Permitir.
   - Os scripts do projeto (`./scripts/stills.mjs`, `./scripts/*.py`, `./scripts/dl.sh`) rodam de dentro da pasta do projeto, em caminho relativo (`cd <projeto> && python3 ./scripts/split-vo.py`): é a forma que a pré-aprovação cobre.
   - Por padrão, use o scratchpad da sessão; se o usuário quiser guardar, a pasta que ele indicar.
   - O projeto sai renderizável nas três composições (o Film de exemplo ainda sem voz).
   - Para escolher cena e transição com a pessoa: `python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/galeria.py <projeto>` → `out/galeria/index.html` (só texto, sem render: `--lista`). O roteiro não muda.
