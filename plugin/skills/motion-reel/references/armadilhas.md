# Armadilhas já pisadas (reel de exemplo do template, 28/09/2026; filme narrado 16:9 + 9:16, 03/10/2026)

## Imagem e composição

| Sintoma | Causa | Conserto |
|---|---|---|
| Cubo 3D achata e a face B nunca aparece | `filter` (até `blur(0px)`) no elemento com `transform-style: preserve-3d` achata o 3D | filtro só no pai com `perspective`, e só quando > 0 (`filter: x > 0 ? … : undefined`) |
| Partículas/mosaico tremem frame a frame | `Math.random()` | `random("seed-" + i)` do `remotion` |
| Primeiros frames em fonte de fallback | fonte não carregada antes do render | `useFont()` (FontFace + `delayRender`/`continueRender`); a Plus Jakarta é variável (`weight: "200 800"`) |
| Mp4 sai `yuvj420p` (faixa cheia) | padrão do Remotion | `final.sh` converte para `yuv420p` (`scale=in_range=full:out_range=tv`); confira pretos e brancos por pixel (`crop=1:1:x:y,format=rgb24`) |
| Texto na área dos botões do Instagram | bloco com `right: 90` | guia do Reel: esquerda 90, **direita 180**, topo 180, **base 320**. No Film o `useL()` dá a guia do formato (9:16: 90/180/200/340; 16:9: 120/120/96/96) e o `safe.jpg` do `qa.sh` desenha a mesma |
| Palavra gigante cortada na borda | `fontSize` sem medir | `fit(linhas, larguraMáx, base, k, estilo?, folga?)` mede a linha mais larga na fonte real (`measureText`, depois do `useFont`); passe o `estilo` que a cena muda (peso 800, outro `letterSpacing`) e a `folga` do que cresce depois (push, `scale`). Frase que não cabe numa linha: `equilibrar()` quebra em duas de largura parecida. Prova: `galeria.py <projeto> --pior-caso` |
| Spin mostra retângulo girando com bordas | cena de entrada com escala < 1 | entrar com escala > 1 (1 + 1,1·(1−p)) |
| **Emenda de 1 px** (linha fina na borda ou entre fatias) depois de um `glitch` ou `spin` | o Remotion mantém a cena envolvida pela apresentação com progresso 0/1 fora da troca: fatias com `clipPath` e `blur(0)`/`rotate(0)` parados não somam a tela inteira | a apresentação devolve os filhos intactos com `p <= 0.001 \|\| p >= 0.999`; transição nova segue a mesma guarda |
| **Transição revela tela vazia** (fundo liso no meio da troca) | cena de entrada sem conteúdo em `f < 0`; no Film, o 1º elemento esperando a 1ª fala | Reel: pré-popular (ver `transicoes.md`). Film: o 1º elemento entra em `first(p)` = `min(fala0 − 6, −8)` |
| Janela do Desktop com título de uma sessão e outra ativa na sidebar | título fora da lista de sessões | o `Desk` põe o título como sessão ativa; passe `session` nas `props` da cena |
| Match cut pula | `Breathe` numa das pontas, ou escala do card ≠ escala do título | `MOSAIC_ZOOM` compartilhado; `Breathe` desligado nas duas cenas |
| Linhas/triângulos dentro de letra vazada (no M, no K, no acento do "ê") | `-webkit-text-stroke` em fonte variável desenha os contornos sobrepostos de dentro dos glifos | `hollow(cor, px, fundo)`: `paint-order: stroke fill` + fill na cor do fundo (traço dobra, metade fica por baixo); só sobre fundo sólido |
| Animação CSS ou Tailwind (`animation`, `transition`, `animate-*`) não aparece no MP4, ou só no Studio | o Remotion renderiza quadro a quadro e não roda o relógio do navegador | todo movimento sai do frame: `useCurrentFrame()`/`useF()` + `interpolate`/`spring`; nada de keyframes CSS |
| Primeiros quadros (ou o filme inteiro) em system-ui | `PlusJakartaSans.ttf` faltando em `public/` | desde 20/10/2026 o `useFont` cancela o render com a mensagem do arquivo; reponha com o `new.sh`. A serifada continua opcional (cai no Georgia) |
| Contador mostra número maior que o alvo no meio (`2.700` passa por `9.570`) | `Odometer` rola cada dígito sozinho | contagem é `Counter` (inteiro interpolado + `toLocaleString("pt-BR")`); `Odometer` só para versão |

## Shell, ffmpeg e render

| Sintoma | Causa | Conserto |
|---|---|---|
| `for fr in $LISTA` roda uma vez só; `ffmpeg $ARGS` recebe tudo como um argumento | o zsh não divide `$VAR` em palavras | os scripts rodam em `bash`; no zsh, `${=VAR}` |
| ffmpeg falha ou trava extraindo quadros de um filme longo | `select=eq(n\,a)+eq(n\,b)+…` com centenas de termos estoura o tamanho de expressão | extraia em lotes (o `qa.sh` usa 24 quadros por chamada, com `-start_number`) |
| `Unrecognized option 'vsync'` | `-vsync` saiu do ffmpeg 9 | `-fps_mode vfr` |
| `stills.mjs`/script Node não acha arquivo em pasta com espaço ("Application Support") | `new URL(import.meta.url).pathname` devolve `%20` | `fileURLToPath(import.meta.url)` |
| Hook bloqueia `cd X && … src/arquivo` | regra de leitura com caminho relativo | caminhos absolutos em tudo |
| Cena lenta de revisar | screenshot por quadro ou render inteiro por ajuste | folhas de contato (`qa.sh`): 1 imagem para 32 quadros; para poucas cenas, `stills.mjs` com os índices |
| Código gerado chama API do Remotion que não existe (prop, hook ou pacote) | skill ou exemplo da Remotion escrito para outra versão; o template trava a 4.0.484 | confira na doc da versão travada (`find-docs`) e no `node_modules/remotion`; não suba a versão por causa de um exemplo |
| O comando `usage` da CLI do HyperFrames (ou outra CLI de terceiro) mostra dados da sua conta do Claude Code | a CLI lê a credencial do Claude Code no Keychain | não rode CLI de motion de terceiro na máquina com sessão do Claude; estude o código, porte a ideia |
| Encode falho apaga o MP4 bom | render direto em `out/<nome>.mp4` | o `final.sh` renderiza e encoda em `out/.staging-<nome>/`; o reprovado vira `<nome>-reprovado.mp4` e o anterior fica |
| Emenda de 1 px some na revisão | a prévia é a 50% e as folhas reduzem de novo | `out/<nome>-transicoes/` (12 quadros por corte, meia resolução com `flags=area`) e `revisar.sh recorte` em resolução cheia |
| Render do Film falha por arquivo ausente (`mix-master.wav`, `grain.png`) | `public/` não vai para o git e o projeto foi copiado sem ele | `new.sh` gera os dois; à mão: `grain.py` e `track_cinema.py <formato>` |

## Áudio e entrega

| Sintoma | Causa | Conserto |
|---|---|---|
| Download da voz dá 403 | a URL assinada do ElevenLabs (`media[].url` do conector) **expira em 2 h** | baixe com `dl.sh` assim que a geração termina; vencida, gere o bloco de novo |
| Fala cortada no meio ou duas falas num WAV | `[long pause]` curto demais, ou bloco com falas muito desiguais | confira a tabela do `split-vo.py`; marque mais as pausas ou divida o bloco |
| Pronúncia errada de nome em inglês ("Claude") | o TTS lê com fonética do inglês | `say` no `blocks.json` ("Claude" → "Cláudi"), só no áudio |
| Fala editada no `vo.json` continua com o áudio velho | o `voz.py` só olhava se o WAV existia | desde 20/10/2026 o `public/vo/.voz.json` guarda o hash (texto depois da pronúncia, voz, taxa) e o do WAV gerado: muda um, a fala sai de novo. WAV fora do manifesto é gravação da pessoa e não se toca; projeto anterior ao cache: passe os ids |
| Pico acima de −1 dBTP no MP4 mesmo com o loudnorm em `TP=-1` | o loudnorm linear não segura um SFX que estoura, e o encode AAC sobe o pico uns décimos (**overshoot**) | o `final.sh` põe um limiter de pico verdadeiro depois do loudnorm (`aresample=192000,alimiter` em −1,5 dBTP, `aresample=48000`) e mede o MP4, não o WAV |
| Volume muito diferente de outros vídeos da plataforma | mix sem normalização; `loudnorm` numa passada só é dinâmico e erra ~1 LU (−12,9 LUFS medido numa trilha sem voz) | `final.sh` mede e aplica em duas passadas (`linear=true`), alvo I=−14 LUFS, TP=−1 dBTP; depois mede o MP4 entregue e sai com exit 1 se o integrado ficar fora de −14 ±1 ou o pico passar de −1 (`out/<nome>-loudness.txt` aponta o segundo do pico) |
| Vídeo não chega no celular/web pelo envio de arquivo | o envio de arquivo (SendUserFile) tem teto de **30 MB** | o `final.sh` gera `<nome>-leve.mp4` (metade da resolução) quando passa de 30 MB; mande o leve e diga onde está o completo |

## Coisas que não foram verificadas

- **Áudio de cada peça nova.** A trilha do Reel (`track.py`) nunca foi ouvida. A do Film (`track_cinema.py`) foi ouvida e aprovada no filme de 03/10/2026, mas cada mix novo muda com o roteiro: toda entrega avisa e pede que o dono escute.
- Os shaders do `@remotion/transitions` (html-in-canvas): não testados, evitados de propósito.
