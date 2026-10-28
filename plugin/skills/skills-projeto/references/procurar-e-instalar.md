# skills-projeto — Procurar e instalar skill pronta

Lido antes de rodar `npx skills@1.7.4 find` ou `add`. A regra dura (busque e apresente; `add` só
com pedido explícito da pessoa) e a checagem antes de instalar ficam no SKILL.md: o "item 2 acima"
é o item 2 de "O risco maior é o `npx skills@1.7.4 add`" (ler o SKILL.md de terceiro inteiro).

## Onde o `add` põe a skill

O `npx skills@1.7.4 add` costuma pôr a skill em `.agents/skills/<nome>` e só um link em
`.claude/skills/<nome>`. O Claude Code carrega pelo link: ele não lê
`.agents/skills` direto, então o que só existe lá não pesa aqui (pesa no Codex,
que lê). O scan e o aviso da abertura contam as skills que chegam pelo link.
A skill nova entra na sessão aberta sozinha; se não aparecer no menu, rode
`/reload-skills` em vez de reiniciar.

## Procurar skill pronta

`npx skills@1.7.4` é o gerenciador do ecossistema aberto; o catálogo fica em
https://skills.sh/. A versão fica fixa: a 1.7.4 foi conferida em 20/10/2026 (`find`,
`add`, `update` e `init` no `--help`; o `check` roda, mas não aparece lá). Sem versão,
o `npx` baixaria a do dia sem perguntar.

```bash
npx skills@1.7.4 find <termo>          # procura (aceita --owner <dono>)
npx skills@1.7.4 add <pacote>          # instala: só quando a pessoa pediu
npx skills@1.7.4 check                 # vê o que tem atualização
npx skills@1.7.4 update                # atualiza tudo
```

Ranking do skills.sh primeiro, depois `find <domínio + tarefa>`. Resultado de busca
não é aval: 1.000+ instalações é sinal razoável e abaixo de 100 pede mais cuidado;
`anthropics`, `vercel-labs`, `microsoft` e afins são outra categoria de risco que um
autor desconhecido; repositório sem histórico é código de estranho. Nenhum número
dispensa ler o SKILL.md (item 2 acima).

Para cada candidata, uma frase: o que faz, quantas instalações, de quem, o comando e
o link. Sem `-g` a skill entra só neste projeto, que costuma ser o certo para skill de
stack; global (`-g`) só se a pessoa pedir. Não achou nada: diga isso e resolva direto,
sem oferecer gerar skill (ver "Não gere skill — ainda").
