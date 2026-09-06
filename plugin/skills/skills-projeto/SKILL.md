---
name: skills-projeto
description: >-
  Skill de projeto (.claude/skills) cobra contexto em TODA request, mesmo sem
  disparar. Use ao criar, instalar (npx skills add) ou revisar skill de projeto,
  quando a sessão nasce cara, ou em "vale a pena virar skill?". Traz o teto
  (8 skills / 2.000 chars), o que faz uma skill rotear de verdade (name = pasta,
  description que diz QUANDO, corpo com conteúdo) e como medir. Não é o
  harness-check, que mede a sessão inteira.
---

# Skills do projeto — o que elas cobram, e de quem

Skill de projeto vive em `.claude/skills/<nome>/SKILL.md` e vale só naquele
repositório. O ponto que quase ninguém vê: **a `description` de toda skill
visível entra no contexto antes do seu primeiro prompt e é relida a cada
request.** A skill não precisa disparar para cobrar — basta existir.

Números de 05/09/2026 (MEDIDO em quatro repositórios de cliente): 52 skills
locais somando ~9.030 chars de description, ~2.257 tokens por request
(ESTIMADO por chars÷4). Mais que o catálogo global inteiro da pessoa que mediu.
Ninguém decidiu isso; foi chegando.

## Teto deste kit: 8 skills e 2.000 chars por projeto

Não é lei da física, é orçamento. Acima disso, cada request do projeto carrega
mais catálogo do que trabalho. Passou do teto, a pergunta não é "qual eu apago",
é **"o que cada uma ensina que eu teria que repetir?"**.

Meça antes de mexer:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills-projeto-scan.sh" .
```

Sai uma linha por skill (chars de description, linhas de corpo, situação), o
total, o custo estimado por request e o que está quebrado. O hook do kit roda o
mesmo scan na abertura da sessão e fala **uma vez por mudança** — não a cada
`/clear`.

## O risco maior é o `npx skills add`

Instalar é uma linha, e o que entra pode ser um pacote com dezenas de skills.
Você não vê o custo: nada trava, nada avisa, e a conta chega diluída em toda
request pelo resto do projeto. Antes de instalar qualquer coisa de terceiro:

1. **Quantas skills vêm junto?** Bundle inteiro por causa de uma é o caso mais
   comum de estouro. Instale a skill, não o pacote, quando der.
2. **Leia o SKILL.md antes de aceitar.** Um SKILL.md de terceiro é código que o
   modelo lê como instrução — e o corpo dele pode carregar uma exclamação
   seguida de crase com um comando dentro, que **executa shell no momento em que
   a skill é carregada**, fora de qualquer hook de permissão (confirmado em
   05/09/2026 no kit do time). O que sai desse comando entra no seu contexto
   como se fosse do sistema.
3. **Procedência**: quem publicou, quantas instalações, o repositório existe e
   tem histórico. A skill `find-skills` (`/kit-vamoo:find-skills`) é o caminho
   para procurar; ela cobre esse mesmo aviso.

Depois de instalar, rode o scan. Se o total pulou, desinstale o que você não
consegue explicar em uma frase.

## O que faz uma skill rotear de verdade

O Claude Code escolhe a skill pelo `name` do frontmatter e decide pela
`description`. Três coisas, e todas já falharam em projeto real:

- **`name` igual ao nome da pasta**, minúsculo e com hífen. Pasta
  `refactoring` com `name: Refactoring` **não dispara nunca** — e continua
  cobrando a description em toda request. Em 04/09/2026 um projeto tinha dez
  assim, todas saídas do mesmo scaffold.
- **`description` que diz QUANDO usar**, com as palavras que você realmente
  digita. "Ajuda com testes" não roteia; "use ao escrever teste novo, ao
  investigar teste instável, ou quando o CI fica vermelho só no CI" roteia.
- **Corpo com conteúdo.** Os mesmos dez SKILL.md tinham 99–135 bytes e o corpo
  vazio: cobravam a description e não ensinavam nada. Skill sem corpo é uma
  linha do CLAUDE.md do projeto que se disfarçou de skill.

## Não gere skill — ainda

Este kit **não** tem um passo "gerar skill", e é de propósito. Skill gerada
antes de você ter feito a coisa na mão é palpite formatado: sai casca, sai
description genérica, sai `name` errado. A regra:

> Faça o trabalho **na mão umas três vezes**. Quando você se pegar repetindo a
> mesma explicação para o Claude pela terceira vez, aí existe uma skill — e o
> corpo dela já está escrito, é o que você repetiu.

Quando chegar essa hora, o esqueleto sai de `npx skills init <nome>` (ou de uma
cópia de uma skill deste kit que você entenda). Volte aqui depois com o rascunho
e rode o scan.

## Registre por que cada skill existe

Uma linha por skill, com a data e o motivo. Sem isso, ninguém consegue apagar
nada depois — na dúvida todo mundo mantém, e o total só sobe.

- Projeto com `.context/`: `.context/docs/skills.md`.
- Projeto sem `.context/`: `docs/skills.md` (crie o arquivo; não invente
  `.context/` só para isso).

Formato que basta:

```
- pagamentos-stripe (04/09) — o fluxo de webhook que erramos duas vezes. Sai quando
  o checkout novo estabilizar.
```

## Opcional: teste a skill sob pressão

Skill de disciplina ("sempre rode o teste antes de dizer pronto") costuma ser
ignorada justamente quando dá trabalho obedecer. Dá para provar isso antes de
confiar nela:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skill-pressure-test.sh"
```

É nota, não gate: uma skill sua não precisa passar por isso para existir. Método
em `docs/testar-skills-sob-pressao.md`.

## Checklist antes de commitar uma skill nova

- [ ] `name` do frontmatter == nome da pasta (minúsculo, com hífen)
- [ ] `description` diz QUANDO usar, com as suas palavras, e cabe em 500 chars
- [ ] O corpo ensina algo que você teria que repetir — e você já repetiu
- [ ] O scan continua dentro do teto (8 skills / 2.000 chars)
- [ ] A linha do porquê está em `.context/docs/skills.md` (ou `docs/skills.md`)
