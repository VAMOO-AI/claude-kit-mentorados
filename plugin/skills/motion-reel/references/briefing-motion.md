# Briefing de motion

Ponto de partida de toda peça do Film e do Reel. O briefing preenche o `film.json` (ou o
`timeline.json` do Reel) com as cenas que o template já tem: não é um renderer novo nem um
roteiro solto. São cinco partes, nesta ordem, e a tabela da parte 3 vira o roteiro linha a linha.

Fontes (só a ideia, nenhum código copiado): a estrutura do briefing e a duração pela leitura vêm
do gerador de prompt do Me dá um Exemplo (MDE); o padrão de seis blocos (entradas, direção,
estrutura, construção, armadilhas, início) vem dos briefings do guanmo-ai/awesome-ai-motion
(scripts MIT, prompts dos autores); a beat sheet vem do buildwithhanif/claude-animation-skill
(MIT, Copyright (c) 2026 Hanif); os reads e o checklist vêm do `ANIMATION_GUIDE.md` do
JohnHeibel/ClaudeAnimationBase (MIT, Copyright (c) 2026 John Heibel).

## 1. Entradas: pergunte tudo de uma vez

Uma mensagem só, com o que o contexto não responde. Não comece a escrever cena antes das respostas.

| Entrada | Por que importa |
|---|---|
| Objetivo e público (o que a pessoa faz depois de ver) | decide o fechamento (CTA, assinatura, seguir) |
| Texto exato que precisa aparecer ou ser dito | o briefing corrige só ortografia |
| Base e formatos: Reel (música) ou Film (voz); 16:9, 9:16 ou os dois | o `reel` do Film é corte do `master`, não roteiro novo |
| Duração alvo | com voz, a duração vem da fala; sem voz, do `min` de cada cena |
| Voz: `say` grátis, gravação própria, ElevenLabs (pago) ou sem voz | sem voz, o ritmo é da batida (15 frames = 1 batida a 120 BPM) |
| Marca: logo para fundo claro e escuro, símbolo, paleta | peça de cliente usa a marca dele |
| Números e afirmações, cada um com a fonte | número sem fonte não entra na tela |
| Referência de motion (link ou peça guardada) | adapta o conceito; vídeo de terceiro não entra na entrega |
| Onde guardar o projeto | o scratchpad some com a sessão |

## 2. Direção

- **Uma frase de estética.** Exemplo: "tipografia pesada em papel e night, um azul de dado, impacto pela coreografia".
- **Paleta com papéis:** fundo, texto, destaque (dado) e apoio. A paleta é a `C` do `src/lib.tsx`; troque as cores e mantenha os papéis.
- **Um foco por vez.** Uma ideia por tela; o elemento que importa entra sozinho ou primeiro.
- **Intensidade em número**, para o roteiro dizer quanto, não "suave" ou "forte". Referência do template a 30 fps (1 frame ≈ 33 ms):

| Intensidade | Deslocamento | Escala | Entrada | Stagger | No template |
|---|---|---|---|---|---|
| sutil | 20–40 px | 95–102 % | 400–600 ms | 0–60 ms | `Breathe` (zoom de 3 %, só no fim), números que esmaecem |
| moderada (padrão) | 40–80 px | 80–110 % | 300–500 ms | 60–100 ms | `MaskUp` (sobe 110 % da linha em 14 frames, ≈ 470 ms), linhas do `statement` a 5 frames |
| intensa | 60 px ou mais, ou corte pela borda | 50–150 % | 100–300 ms | 30–50 ms | letras do `title` (60 px e escala 1,5 → 1 em 14 frames), tremor do `shake`, `glitch` |

Curva da casa: `cubic-bezier(.22,1,.36,1)` (`EASE`). A doutrina de motion (`vocabulario.md`) explica quando variar.

**Proibidos** (a não ser que a pessoa peça):
- easing elástico ou de quique em texto;
- explosão de partículas, glow, neon, lens flare, chão de grade, fundo piscando, anéis de choque;
- gradiente decorativo e vidro fora dos presets `glass` e `logo3d`;
- RGB split e tremor de câmera contínuo (o `shake` é só no impacto);
- ênfase em itálico ou cor (a exceção é o preset de apresentação); laranja em dado ou CTA; mono fora de comando;
- logo redesenhado ou esticado; número sem fonte; comando que não existe no produto;
- cartão provisório ("Lorem", "Texto aqui") em render que vai para a pessoa.

## 3. Estrutura: a tabela que vira o `film.json`

Uma linha por cena, na ordem. Com voz, a duração é a das falas; sem voz, escreva em compassos
(1 compasso = 4 batidas = 60 frames = 2 s a 120 BPM) e ponha em `min` (frames, múltiplo de 15).

| # | Ideia (uma frase) | Duração ou compassos | O que se lê (reads) | Cena do template (`type`) | Transição (`in`) e motivo | Som |
|---|---|---|---|---|---|---|
| 1 | … | 2 compassos (`min` 120) | "…" | `statement` | corte seco: abre | — |

### Mapa conteúdo → cena

| Conteúdo | Cena | Observação |
|---|---|---|
| número | `numbers` (com voz), `highlights` ou `glass` (sem voz) | sem voz, os itens do `numbers` entram juntos: use `highlights` ou `glass`, que caem na batida |
| lista ou passos | `rows` (motif do `card`), `beats` (sem voz, 1–3 palavras por item) ou `card` em série | passo a passo com prova: `card`; benefício curto: `beats` |
| frase | `statement` | um grupo por fala; última linha vazada |
| uso do produto | `desk` (Claude Code Desktop) ou `commands` | comando real, tirado do README do produto |
| título ou nome do produto | `title` ou `launch` | sem voz, o `sub` e a `pill` do `title` não aparecem (entram na 2ª fala) |
| quem é a pessoa | `pillname`, `orbit` | preset `apresentacao` |
| capítulo de uma série | `chapter` | |
| chamada para ação | `cta` ou `follow` | |
| assinatura | `outro` ou `logo3d` | `logo3d` com `mark: "finale"` em peça de 6 s reprova o loudness |

### Reads: o que o espectador precisa ler, e por quanto tempo

Cada cena lista, em ordem, as leituras (reads) que o espectador precisa fazer: o título, o
número com o rótulo, a frase. Regras:

- **Um read por vez.** Dois textos novos no mesmo instante disputam o olho; o segundo entra quando o primeiro já foi lido.
- **Duração pela leitura:** 2,5 palavras/s + 0,5 s. Cinco palavras pedem 2,5 s. Se os reads não cabem, alongue a cena ou corte um read; nunca esprema.
- **Ação rápida, significado segurado:** a mudança acontece em poucos frames e o resultado fica na tela.
- O `build-timeline.py` conta as palavras das `props` (fora a moldura de UI: sessão, arquivos, status, painel ilustrativo, botão, palavra de fundo), grava `read` (`words`, `need`, `secs`) em cada cena da timeline e avisa "leitura curta" quando a cena dura menos que a leitura. Quando a contagem pega texto que é só decoração, declare na cena do `film.json` o que precisa ser lido: `"read": ["O cliente chama.", "Ninguém responde."]`.

### Checklist do storyboard (antes de construir)

- [ ] **Evento em toda cena:** algo acontece (causa e reação, número que conta, frase que vira); cena só de texto parado é cartão.
- [ ] **Transição motivada:** a corrente (`"current"` no `film.json`, padrão `whip`) leva a maioria das trocas na mesma direção; `in` explícito só com motivo (`iris`/`ink` = fecha, `whipUp` = conclusão que sobe, `cut` = match ou smash cut). Dois ou três tipos por filme.
- [ ] **Final que rima com a abertura:** a última cena devolve um elemento da primeira (a mesma palavra, o símbolo, a cor de fundo).
- [ ] **Leitura:** nenhuma cena com aviso de leitura curta, ou o aviso foi aceito de propósito.
- [ ] **Beat-chave no meio da cena,** onde a transição não come.
- [ ] **Fonte de cada número** anotada para o relatório de entrega.

## 4. Construção (sempre igual)

1. `scripts/new.sh <projeto>` (a marca vem do passo 2 do `SKILL.md`).
2. Se um preset cobre o pedido, `cp presets/<arquivo>.json film.json` e troque os textos; senão escreva o `film.json` a partir da tabela: cada linha vira `{"type", "vo", "props", "in", "mark", "energy", "min"}`.
3. Com voz: falas no `vo.json`, ids em `vo`, e `voz.py`. Sem voz: `vo: []` e `min`.
4. `python3 <projeto>/scripts/build-timeline.py` (o `qa.sh` e o storyboard também rodam): leia os avisos de leitura curta e de fala sem WAV.
5. Na dúvida de cena ou transição, `galeria.py`; com a pessoa, o storyboard (um quadro por cena) antes de voz paga.
6. `qa.sh`, ajustes, `final.sh`.

Regras fixas: estado só em função do frame (`useF()`), nada guardado entre frames (`useState`
acumulando, `Date.now()`, `Math.random()`); texto e números reais; cena nova no molde do
`film-scenes.tsx` (passo 6 do `SKILL.md`). Os padrões de easing e duração de `lib.tsx`,
`transitions.tsx` e `film-base.tsx` não mudam por peça.

## 5. Armadilhas ativas

As que mais aparecem num roteiro novo (o resto está em `armadilhas.md`):

- **Transição revela tela vazia:** o 1º elemento entra em `first(p)`, antes do corte.
- **Palavra gigante cortada na borda:** `fit()` estima 0,56 em por caractere; confira na folha.
- **Cena sem voz que espera fala:** `numbers` sem fala mostra todos os itens juntos; o `sub` do `title` não aparece.
- **3D achatado:** `filter` no nó `preserve-3d`.
- **Laranja sem contraste** sobre o azul de destaque.
- **Peça curta com `mark: "finale"`** passa do loudness.
- **Texto na zona dos botões** da rede (o `safe.jpg` do `qa.sh` mostra a guia).

## Exemplo resolvido: explicativo de negócio (`presets/explicativo.json`)

Entradas: serviço que responde clientes no WhatsApp; sem voz; 16:9 + 9:16; ~20 s; número com fonte.
Direção: `"current": "whip"` no `film.json` (a corrente da doutrina), `iris` só no fechamento.

| # | Ideia | Duração | Reads | `type` | `in` | Som |
|---|---|---|---|---|---|---|
| 1 | o problema | 105 frames (3,5 s) | "O cliente chama." → "Ninguém responde." | `statement` | corte (abre) | — |
| 2 | o que você faz | 105 (3,5 s) | o nome → "resolve" | `title` | corrente (`whip`) | `braam` |
| 3 | como funciona em 3 passos | 120 (4 s) | "Como funciona" → 3 passos, um por batida | `beats` | corrente (`whip`) | `drop` |
| 4 | uma prova com fonte | 195 (6,5 s) | "Na prática" → 87 e o rótulo → a fonte, num cartão próprio | `glass` | corrente (`whip`) | — |
| 5 | o nome | 120 (4 s) | a marca → o @ | `logo3d` | `iris`: fecha | `finale` |

Leitura medida pelo `build-timeline.py`: 2,5 s, 1,7 s, 3,7 s, 6,1 s e 0,9 s, todas dentro da cena.
Sem voz, `statement`, `title` e `glass` não têm fala para revelar aos poucos: ficam com `breathe: true`
(regra 7 da doutrina), e o `qa.sh` sai sem aviso de cena parada nos dois formatos.
O número do exemplo é placeholder: troque pelo da pessoa, com a fonte dela.
