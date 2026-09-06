---
name: find-skills
description: >-
  Procura e instala skill de terceiro pelo ecossistema aberto (npx skills,
  skills.sh). Use em "acha uma skill pra X", "existe skill pra isso?", "dá pra
  instalar algo que faça X". Só dispara quando você chama — o Claude não aciona
  sozinho. Verifica procedência antes de recomendar, porque SKILL.md é
  instrução que o modelo obedece, e o corpo pode executar shell no carregamento.
disable-model-invocation: true
---

> Derivada de `claude-config-team/skills/find-skills`. Aqui ela é **só-slash**
> (`disable-model-invocation: true`, como no time) e ganhou a seção de
> procedência, que vale para os dois kits.

# Achar skill pronta — e não engolir o que vier junto

`npx skills` é o gerenciador do ecossistema aberto de skills; o catálogo fica em
https://skills.sh/.

```bash
npx skills find <termo>          # procura (aceita --owner <dono>)
npx skills add <pacote>          # instala
npx skills check                 # vê o que tem atualização
npx skills update                # atualiza tudo
```

## Antes de qualquer coisa: procedência

Uma skill instalada é **texto que o modelo lê como instrução, em todo projeto
onde ela estiver visível**. Duas consequências práticas, e nenhuma delas é
teórica:

1. **O corpo do SKILL.md pode executar shell no momento em que a skill é
   carregada** — uma exclamação seguida de crase, com um comando dentro.
   Confirmado em 05/09/2026: isso roda **fora de toda a cadeia de permissão**
   (nenhum hook de PreToolUse vê, e a saída entra no contexto como se fosse do
   sistema). Então: **abra e leia o SKILL.md antes de aceitar**, e desconfie de
   qualquer coisa que peça para "só rodar isso rapidinho".
2. **Custo por request.** A description de toda skill visível é relida a cada
   request, dispare ela ou não. `npx skills add` de um pacote inteiro costuma
   trazer dezenas — o total sobe de uma vez e nada avisa. Depois de instalar,
   rode o scan da skill `skills-projeto`.

Checklist de procedência, na ordem:

- **Quantas instalações?** Acima de 1.000, tranquilo. Abaixo de 100, leia o
  código inteiro antes.
- **Quem publicou?** `anthropics`, `vercel-labs`, `microsoft` e afins são outra
  categoria de risco que um autor desconhecido.
- **O repositório existe e tem histórico?** Poucas estrelas, sem commits, sem
  issues — trate como código de estranho, porque é.
- **Vem pacote junto?** Instale a skill, não o bundle, quando o pacote permitir.

## Como procurar

1. **Comece pelo ranking do skills.sh.** Ele ordena por instalação, então o que
   é conhecido no domínio aparece antes de qualquer busca.
2. **Depois o `find`**, com termo específico: `npx skills find react
   performance` acha mais que `npx skills find testing`.
3. Se o termo não render, tente o sinônimo (`deploy` → `deployment`, `ci-cd`).

| Domínio | Termos que costumam render |
|---|---|
| Web | react, nextjs, typescript, css, tailwind |
| Teste | testing, jest, playwright, e2e |
| Infra | deploy, docker, kubernetes, ci-cd |
| Documentação | docs, readme, changelog, api-docs |
| Qualidade | review, lint, refactor, best-practices |
| Design | ui, ux, design-system, accessibility |

## Como apresentar o que achou

Não recomende com base no resultado da busca — verifique primeiro. Depois,
para cada candidata: o que ela faz, quantas instalações, de quem, o comando de
instalação e o link. Uma frase por item; a decisão é de quem pediu.

```
Achei a "react-best-practices" (Vercel, 185K instalações): guia de performance
de React/Next. Instalar: npx skills add vercel-labs/agent-skills@react-best-practices
Ver antes: https://skills.sh/vercel-labs/agent-skills/react-best-practices
```

Instalação global (vale em todo projeto) é `-g`; sem `-g`, entra só neste
projeto — que costuma ser o que você quer quando a skill é de um stack
específico.

## Quando não existe skill para o caso

Diga que não achou e resolva direto — é o caminho mais curto na maioria das
vezes. **Não** ofereça gerar uma skill na hora: skill nasce de coisa que você já
repetiu três vezes, e o critério está na skill `skills-projeto`.
