---
name: orquestracao
description: >-
  Como dispatchar subagents e executores em paralelo sem dois writers no mesmo
  arquivo: lotes por dependência (Files:/Depends-on:), scope contract pra writes,
  brief autossuficiente com Status:, N terminais no mesmo repo. Use ao orquestrar
  >5 arquivos independentes, montar workflow/fan-out, ou quando um run morre no
  meio. Gatilhos: "subagents", "fan-out", "workflow", "paralelo em N arquivos",
  "rate limit 429/529".
---

# Orquestração de subagents

A mecânica do Workflow (teto de concorrência do runner, `.filter(Boolean)`, `pipeline()` >
`parallel()`, `resumeFromRunId`, effort por estágio) está na skill built-in
`workflow-authoring`. Aqui fica o que ela não cobre.

## Quando fan-out (e quando NÃO)

- Subagents paralelos pra **>5 arquivos independentes**. Não delegue o que resolve em poucos
  tool calls, nem a conferência do trabalho recém-feito: revisor é pra PR/branch.
- Qual subagente: lote de implementação despachado → agente `executor` do kit
  (`subagent_type: kit-vamoo:executor`); review → `revisor` (`kit-vamoo:revisor`). Os dois
  rodam em `effort: medium`.
- Onda manual, com barreira entre lotes, só com 429/529 medido: o runner já segura o pico.
- Auditoria ou review multi-área com juiz adversarial: o workflow `audit-multidim` (o
  `/kit-vamoo:setup` instala em `~/.claude/workflows/`) só roda com pedido explícito da pessoa
  ("usa o workflow", `/audit-multidim`). Com o pedido, não reescreva o script:
  `scriptPath: ~/.claude/workflows/audit-multidim.js` + `args`
  (`{alvo, contexto, regras, areas: [{key, files, foco}], maxFindings}`). Sem ele, faça o
  fan-out com `Agent` e ofereça o workflow em uma linha.

## Schema de `agent()`: o que evita o retry do StructuredOutput

Schema que o subagente erra custa um turno por tentativa. Ao escrever o `schema`:

- **`required` mínimo**: só o que o passo seguinte consome. Campo nice-to-have fica fora.
- **Raso**: objeto na raiz e no máximo um array de objetos com poucos campos. Lista longa de
  obrigatórios faz o agente esquecer uma propriedade, e o output inteiro é rejeitado.
- `enum` em campo categórico e `maxItems` em todo array.
- Prosa longa vai num campo string só (`notes`), não espalhada em N campos obrigatórios.
- **Repita as chaves exatas no prompt** ("responda `{findings: [{file, issue, proposal}]}`"):
  os dois erros que mais voltam são chave extra na raiz ("must NOT have additional
  properties") e `required` faltando.
- Os parâmetros do tool `Workflow` são `script` ou `scriptPath`, `args` e `resumeFromRunId`.
  Não existe `run_in_background` (é do Bash): o tool rejeita a chamada.

## Workflow multi-round (loop de review e fix)

Vale ao autorar workflow com loop de review/fix, não para fan-out simples. Não há engine
pronto para esse ciclo: o script é seu. Antes de prometer um comando a alguém, confira que
ele existe; instrução que manda usar o que não existe custa a sessão inteira de quem acredita.

- **Controle × dados**: o schema de retorno leva só decisões (`pass?`, `clean?`); conteúdo
  rico viaja por ARQUIVO, sem paráfrase do harness no meio.
- **Ledger de descartados**: o revisor cego lê só o ledger dos findings dispensados, nunca as
  reviews anteriores. Não re-litiga, mas re-verifica o diff fresco. Contestou o descarte →
  quem corrige corrige ou escala; nunca re-dispensa em silêncio.
- **Cegueira por posição**: agente que não pode ver um documento nunca recebe o caminho, e o
  documento não fica em pasta que ele lê. "Não leia X" não é cegueira.
- **Agente solo crítico morto → `throw`**: o `.filter(Boolean)` é para fan-out. Em papel único
  (crítico do plano, varredura final), agente morto que volta vazio é indistinguível de
  veredito limpo, e tem de falhar alto.
- **Estados terminais distintos**: esgotou rounds, esgotou tokens e provou que nada qualifica
  são três saídas. Juntar duas deixa cansaço passar por prova.
- **Estacione, não descarte**: trabalho que não passa vira `parked-<id>.patch` com o comando
  de restauração em `NEEDS-USER.md`; árvore limpa em todo estado terminal.

## Ambiente sem a dependência → implemente, simule, documente o real

Agente em container/cloud/sandbox não alcança o que só existe na máquina do operador (Chrome
logado, VPN, banco de produção, credencial que não sai do cofre). Escreva no prompt do dispatch:

> Se este ambiente não alcança <dependência>, **não pare o projeto**: implemente
> a camada completa, teste contra um fake/página simulada, e deixe o teste real
> DOCUMENTADO (comando exato + o que observar) para rodar no ambiente que
> alcança. Reporte o bloqueio exato quando chegar nele; siga com tudo que não
> depende dele.

A segunda metade é a que some: o que não foi verificado volta declarado como não verificado,
com o comando pronto. Vale igual para credencial faltando.

## Doctor antes do fan-out

Descobrir no meio de 8 agentes que falta uma dependência é o desperdício mais caro do
fan-out: os 8 já gastaram contexto e mediram menos.

- Fan-out que roda ferramenta (scanner, linter, build, migration) → confira a presença dela
  **uma vez, no coordenador**, e passe o resultado no prompt. Faltou: instalar, seguir
  degradado (declarado no relatório) ou abortar, decidido antes.
- Auditoria: `bash "${CLAUDE_PLUGIN_ROOT}/skills/baseline/scripts/doctor.sh"`.
- Vale além de binário: token expirado, worktree sujo, branch atrás do remote, `.env.local`
  ausente no worktree novo. O que os N agentes descobririam separados, descubra uma vez.
- **Ferramenta ausente vira "não medido", nunca "conforme".** Agente que não rodou o scanner
  e relata "nada encontrado" é falso verde, e não se distingue de sucesso ao ler N relatórios.

## Quais executores rodam juntos: lotes por dependência

Antes de despachar N executores, marque cada lote com dois campos:

- `Files:` são os caminhos exatos que o lote cria ou edita ("os arquivos do front" não
  é marcação). `Depends-on:` são os lotes de que ele precisa, ou `nenhum`. Usar função,
  tipo ou tabela que outro lote cria é depender dele.
- Dois lotes só saem juntos sem dependência entre eles, nem transitiva, **e** com os
  `Files:` disjuntos. Mesmo arquivo em pontos diferentes desqualifica: o worktree adia o
  choque para o merge, não o evita.
- Dúvida em qualquer um dos dois campos → o lote depende de tudo que veio antes. O erro
  seguro é perder paralelismo.
- Dois lotes no mesmo arquivo → um executor só, com os dois.
- `CHANGELOG.md`, lockfile e settings compartilhado não entram no `Files:` de executor:
  ficam com a conversa principal, que escreve depois dos merges.
- Cada executor continua em worktree próprio, com commit e PR próprios; o merge é
  serializado (seção "N terminais", abaixo).

## Writes em paralelo (scope contract)

- Subagents read-only por default (Grep/Read/Glob). Edit/Write na conversa principal.
- Writes paralelos só com **scope contract explícito por agent**. Em worktree, cada agent
  confirma a branch correta antes do primeiro write.
- **O `~/.claude/subagentes.md` não chega sozinho ao subagente.** O CLAUDE.md que o kit
  instala só resume as regras e aponta o arquivo, e `Explore`/`Plan` não recebem nem o resumo:
  - dispatch para `Explore`/`Plan`: o prompt diz "Leia ~/.claude/subagentes.md antes de
    começar e siga as regras de subagent de lá";
  - nos outros, não mande reler o CLAUDE.md: cite só a regra de que aquele estágio precisa;
  - com writes, cole no prompt o scope contract e o formato de report do `subagentes.md`;
  - com browser ou QA visual, cole a regra de imagem (screenshot só quando o pixel é a
    evidência; estado/texto/erro/DOM → `read_page`/`get_page_text`; veredito em texto).
- **O brief é autossuficiente.** O executor não viu a conversa: "igual ao lote 3" e teste
  descrito em prosa não existem para ele. Cole o trecho, o caminho e o comando. O report abre
  com a linha `Status:` (`FEITO`, `FEITO_COM_RESSALVAS`, `PRECISA_CONTEXTO` ou `BLOQUEADO`),
  que é o que você lê primeiro ao juntar N reports.

## N terminais no mesmo repo: escopo disjunto e merge em fila

Várias sessões no mesmo repositório são fan-out sem orquestrador:

- **Escopo disjunto por arquivo**, decidido ANTES de abrir os terminais. Dois terminais no
  mesmo `src/pages/X.tsx` escrevem o mesmo código duas vezes.
- **Merge é serializado.** O primeiro que mergeia move a `main`, e o verde do CI dos outros
  passa a ser de uma base velha. Rebase quem tocar os mesmos arquivos; o resto mergeia como
  está (skill `worktrees`, "Base velha").

## Revisor: subagente `kit-vamoo:revisor`, read-only

Verifica independente, roda checks frescos e reporta findings com `arquivo:linha` **sem
editar nada**: quem corrige é a conversa principal ou um agente com scope contract. O
protocolo, as cinco categorias e a varredura de SKILL.md vêm no próprio agente.

- **Contexto = o diff.** `gh pr diff <n>` ou `git diff --stat` primeiro; `.context/docs` só se
  o diff citar. Revisor que varre o repo inteiro gasta 30 minutos ou mais por passada.
- Um revisor por PR, **em paralelo**. Nunca N PRs em série na mesma sessão.
- Codex como revisor alternativo: `codex -p review` (o perfil que o `codex-optimize.sh` cria:
  effort high, sem memories, sem subagente). Em `max`, a mesma revisão custa 3 a 4 vezes o
  tempo e não acha mais nada.
- **Segunda passada só onde o risco paga.** PR que toca auth/RLS, migration, dinheiro ou
  disparo para pessoa: ao fechar, ofereça em uma linha uma segunda revisão com lente
  diferente da primeira (segurança depois de qualidade), em contexto limpo, recebendo o ledger
  do que já foi descartado. Oferecer não é rodar, e a mesma lente duas vezes não acha mais nada.

## Memória de veredito (falso-positivo não se resolve no código)

Silenciar o achado onde ele aparece (`nosemgrep`, `eslint-disable`, exceção no scanner)
espalha a decisão pelo código, some no diff e não diz quem decidiu nem quando. O veredito vai
num arquivo, no formato do `secscan`:

```markdown
<!-- .context/docs/security/vereditos.md -->
| Fingerprint | Veredito | Por quê | Quem | Quando |
|---|---|---|---|---|
| `src/import.ts:88 sql-injection` | falso-positivo | parâmetro vem de enum fechado, não de input | dev responsável | 2026-08-22 |
| `scripts/build-*.cjs service_role` | risco aceito | ver EX-01 em `.context/docs/baseline.md` | dev responsável | 2026-08-22 |
```

Antes de reabrir um finding, consulte a tabela; depois de julgar um novo, escreva nela. Vale
para auditoria, revisor de PR e todo fan-out que produz achado: sem isso, cada rodada paga o
mesmo julgamento e chega a conclusões diferentes conforme o agente. Código ao redor mudou →
o fingerprint deixa de valer e o achado volta. Registre o motivo, não só o "não é problema".

## Cleanup (parte da tarefa, não follow-up)

- Worktree de lote nasce pelo `EnterWorktree` (ou `isolation: worktree`), não por
  `git worktree add` cru quando pode haver outra sessão no repo: é o isolamento que o guard
  do clone compartilhado assume.
- PR mergeou → descarte pela regra da skill `worktrees` ("Limpeza no fim").
- Antes de fechar o run, inventário: cada worktree do run sai pela mesma regra, e o que não
  tem a prova vai para o report com o motivo, para a pessoa decidir.
