# Diretivas para Sub-Agentes

> Fica em `~/.claude/agents.md`. Vale para todo sub-agente lançado durante o trabalho.
> Sub-agentes tendem a sair do escopo, sobrescrever trabalho um do outro e dizer "passou" sem rodar nada. Estas regras evitam isso.

## Default: read-only
- Sub-agentes existem principalmente para EXPLORAR (Grep, Read, Glob, busca).
- Edit/Write acontece na conversa principal por padrão — assim você vê cada mudança.
- Exceção (write em sub-agente permitido): tarefa mecânica e isolada (ex.: renomear em N arquivos, formatar, gerar testes) com escopo explícito.

## Contrato de escopo (OBRIGATÓRIO para writes paralelos)
- Cada agente recebe no prompt:
  - A lista exata de arquivos que pode modificar.
  - O que pode LER mas não alterar.
  - Uma frase descrevendo o comportamento esperado.
- Edit fora do contrato → PARE e avise o orquestrador. Não expanda escopo no silêncio.
- No final, reporte exatamente quais arquivos tocou.

## Verify, don't claim
- Não diga "lint passou", "testes passaram", "compila" sem colar o output REAL do comando na resposta final.
- Status herdado da conversa anterior NÃO conta. Rode de novo se for afirmar.
- Não conseguiu rodar → diga "não executado" + os comandos que faltam.

## Escopo por agente
- No máximo ~5-8 arquivos por agente. Mais que isso → quebre em mais agentes com contratos separados.
- Reporte só o que foi pedido. Notou um problema fora do escopo? Mencione, mas não mexa.

## Segurança ao editar
- Antes de editar: leia o arquivo. Depois de editar: leia de novo.
- No máximo 3 edições no mesmo arquivo sem reler.
- Rename: grep separado por chamadas, tipos, strings, imports e testes/mocks.
- Nunca delete arquivo sem checar quem referencia.
- Nunca rode `push --force`, `reset --hard` ou ação destrutiva sem autorização explícita do orquestrador.

## Atenção ao contexto
- Arquivos grandes (>500 linhas): leia em pedaços (offset/limit).
- Resultados de ferramenta podem truncar. Output que parece cortado → rode de novo com escopo menor.
- Não confie em leitura antiga depois de muitas operações — releia.

## Código
- Código humano, sem comentário robótico nem header desnecessário.
- Copie o padrão do código ao redor antes de escrever.
- Não over-engineer. Não adicione abstração que ninguém pediu.

## Comunicação — formato do relatório final
1. **Feito**: o que mudou (1-3 linhas).
2. **Arquivos tocados**: lista exata, nada a mais.
3. **Verificação**: output de tsc/lint/testes OU "não executado: <motivo>".
4. **Riscos / fora de escopo**: o que você notou mas não tocou.
