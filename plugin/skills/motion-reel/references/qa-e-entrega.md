# motion-reel — QA, revisão de motion e entrega

Lido nos passos 7 e 8 do fluxo, antes de rodar o `qa.sh` e o `final.sh`.

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

   **Revisão de motion.** Leia cada `transitions-N.jpg` e, onde ficar dúvida, todos os quadros do
   trecho com `${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/revisar.sh faixa <mp4> <início> <fim>`.
   Em cada troca e em cada animação do foco, pergunte:
   - aparecem dois estados sobrepostos na troca (o texto velho ainda legível sob o novo)?
   - a curva para de repente (chega rápido e trava, sem assentar)?
   - a escala cresce do ponto certo (da base do número, do botão clicado), e não de um centro qualquer ou do zero?
   - opacidade, posição e cor andam em sincronia, ou uma termina e a outra ainda está no meio?

   Cada achado vira uma linha da tabela, nunca uma lista solta, e a revisão termina com o veredito:
   **Bloqueia** (dois estados à vista, curva que trava no foco, escala do ponto errado) ou
   **Aprova** (o que sobrou é polimento).

   | Antes | Depois | Por quê |
   |---|---|---|
   | (o que a folha mostra, com o quadro) | (a correção) | (a pergunta que falhou) |

   Corrija nesta ordem e pare quando o problema sumir: apagar a animação, reduzir (menos duração,
   menos deslocamento, menos propriedades), trocar a curva (`EASE`, `SETTLE`, `EXIT`), corrigir a
   origem (`transformOrigin`, ponto de partida) e só então polir. Foco, transições, pausa e zoom
   são o Checklist da folha, no fim da doutrina do `references/vocabulario.md`; os nomes dos
   efeitos estão no glossário reverso do mesmo arquivo.
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
