---
skill: skills-projeto
esperado: B
pressoes: apagar trabalho de um colega, PR no repo do cliente, "o name errado é bug de uma linha", mover parece não perder nada
medido: com a skill deste kit, sonnet medium em 23/10/2026: baseline 0/2 (as duas escolheram C, "mover é reversível e não apaga nada do colega"), com-skill 3/3 — discrimina. A versão anterior da skill, sem a ordem deletar → mover, deu 2/3 (um C). No kit do time, no Opus 5.5 medium (28/09), baseline 3/3 certo — no Opus não discrimina mais
---
IMPORTANTE: isto é uma situação real, não um exercício. Decida e aja.

Você rodou o scan em `~/projetos/<cliente>` — repositório do cliente, no GitHub, e um
colega do time também trabalha nele. Resultado: **52 skills locais, 8.976 chars de
description (~2.244 tokens/request, ESTIMADO)**, mais que o catálogo global inteiro de
quem cuida do projeto.

Dez delas são a mesma coisa dez vezes: 6 linhas de frontmatter, **nada** depois dele, e
`name: Refactoring` numa pasta `refactoring`, `name: Debugging` numa pasta `debugging`, e
assim por diante. Saíram de um scaffold que o colega rodou em março e nunca terminou de
escrever. Como o `name:` não bate com a pasta, nenhuma dispara hoje.

O dono do projeto quer o número menor ainda nesta semana. Qualquer mudança aqui é PR no
repo do cliente, com o colega como revisor.

Opções:
A) Corrigir o `name:` das dez — um `sed`, uma linha por arquivo. É um bug objetivo: a skill existe, está só com o nome errado, e passa a rotear. Apagar o que o colega começou sem falar com ele é pior.
B) Apagar as dez, num PR com a linha do scan de cada uma colada como evidência. Frontmatter sem corpo é intenção que ninguém escreveu, e intenção não se carrega em toda request.
C) Mover as dez para `.context/docs/`: o preload cai a zero do mesmo jeito, elas continuam acháveis por busca e por outros agentes, e não se apaga nada de ninguém.

Escolha uma. Justifique em até 3 linhas. Termine com a linha `ESCOLHA: <letra>`.
