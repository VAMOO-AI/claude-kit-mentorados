# Armadilhas já pisadas (28/09/2026, reel de exemplo do template)

| Sintoma | Causa | Conserto |
|---|---|---|
| Cubo 3D achata e a face B nunca aparece | `filter` (até `blur(0px)`) no elemento com `transform-style: preserve-3d` achata o 3D | filtro só no pai com `perspective`, e só quando > 0 (`filter: x > 0 ? … : undefined`) |
| Partículas/mosaico tremem frame a frame | `Math.random()` | `random("seed-" + i)` do `remotion` |
| Primeiros frames em fonte de fallback | fonte não carregada antes do render | `useFont()` (FontFace + `delayRender`/`continueRender`); a Plus Jakarta é variável (`weight: "200 800"`) |
| Mp4 sai `yuvj420p` (faixa cheia) | padrão do Remotion | `final.sh` converte para `yuv420p` (`scale=in_range=full:out_range=tv`); confira pretos e brancos por pixel (`crop=1:1:x:y,format=rgb24`) |
| Texto na área dos botões do Instagram | bloco com `right: 90` | guia do Reel: esquerda 90, **direita 180**, topo 180, **base 320**; o `safe.jpg` do `qa.sh` desenha a guia |
| Palavra gigante cortada na borda | `fontSize` sem medir | Plus Jakarta 800 ≈ 0,62–0,72 em por letra em caixa alta; confira na folha de quadros |
| Spin mostra retângulo girando com bordas | cena de entrada com escala < 1 | entrar com escala > 1 (1 + 1,1·(1−p)) |
| Transição revela tela vazia | cena de entrada sem conteúdo em `f < 0` | pré-popular (ver `transicoes.md`) |
| `for fr in $LISTA` roda uma vez só | o zsh não divide variável em palavras | loops dos scripts rodam em `bash` |
| Hook bloqueia `cd X && … src/arquivo` | regra de leitura com caminho relativo | caminhos absolutos em tudo |
| Match cut pula | `Breathe` numa das pontas, ou escala do card ≠ escala do título | `MOSAIC_ZOOM` compartilhado; `Breathe` desligado nas duas cenas |
| Cena lenta de revisar | screenshot por quadro | folhas de contato (`qa.sh`): 1 imagem para 32 quadros |

## Coisas que não foram verificadas

- **Áudio.** Ninguém ouviu a batida sintética nem os SFX. Toda entrega avisa isso e pede que o dono escute.
- Os shaders do `@remotion/transitions` (html-in-canvas): não testados, evitados de propósito.
