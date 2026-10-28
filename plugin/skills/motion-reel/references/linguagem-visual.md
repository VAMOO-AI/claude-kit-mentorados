# motion-reel — linguagem visual, abertura e narração em pt-BR

Lido no passo 2 (marca), no passo 6 (cenas) e antes de escrever as falas.

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
