# orquestracao — schema de `agent()` e workflow multi-round

Lido no passo de escrever o script do Workflow: o `schema` de um `agent()` ou um loop de review/fix.

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
