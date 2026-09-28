# Diretivas para Sub-Agentes

> Fica em `~/.claude/subagentes.md`. Vale para todo sub-agente lançado durante o trabalho.
> Sub-agentes tendem a sair do escopo, sobrescrever trabalho um do outro e dizer "passou" sem rodar nada. Estas regras evitam isso.

## Default: read-only
- Sub-agentes existem principalmente para EXPLORAR (Grep, Read, Glob, busca).
- Edit/Write acontece na conversa principal por padrão — assim você vê cada mudança.
- Exceções (write em sub-agente permitido):
  - tarefa mecânica e isolada (ex.: renomear em N arquivos, formatar, gerar testes) com escopo explícito;
  - lote de implementação que a conversa principal despacha com contrato de escopo (arquivos permitidos, worktree próprio, verificação com output real) → agente `executor` do plugin, em `effort: medium`.

## Revisor: quem corrige e o que pergunta
- Review vai para o agente `revisor` do plugin, em `effort: medium`.
- Severidade diz a ordem; **natureza** diz quem decide o fix. O revisor não edita nem classifica: reporta cada achado com `arquivo:linha`, confiança (alta/média/baixa), o cenário de falha e a correção proposta, inclusive os de severidade baixa e os que não confirmou. Quem separa mecânico de decisão e aplica é a conversa principal. Mecânico (um sênior aplicaria sem discutir) entra quando você mandar "aplica os mecânicos"; decisão (dois sêniores poderiam discordar) você decide um a um.
- Mecânico: dead code, variável nunca lida, N+1 sem eager loading, comentário que contradiz o código, número mágico → constante, validação faltando em saída de IA, versão/caminho desatualizado.
- Decisão: segurança (auth, XSS, injeção), race / ler-e-depois-gravar, remover funcionalidade, mudança de comportamento visível, qualquer fix acima de ~20 linhas.
- Cinco categorias que revisor costuma pular e entram em todo review: valor novo de enum/status (ler TODOS os consumidores fora do diff), saída de IA que vira dado, ler-e-depois-gravar sem atomicidade, migration (checklist na skill `baseline`, `references/02-banco.md`) e versão de dependência que subiu (é mudança de código: changelog lido, lockfile commitado junto, um pacote por vez; skill `secscan`, C5.2).

## Contrato de escopo (writes em paralelo)
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
- Antes de editar: leia o arquivo; releia se um hook ou outra sessão pode ter mexido nele (o `eslint --fix` do fim do turno, outro terminal no mesmo clone, edição feita via Bash).
- Antes de reportar, confira o conjunto pelo `git diff --stat`: é a lista de "Arquivos tocados".
- Rename: grep separado por chamadas, tipos, strings, imports e testes/mocks.
- Nunca delete arquivo sem checar quem referencia.
- Nunca rode `push --force`, `reset --hard` ou ação destrutiva sem autorização explícita do orquestrador.

## Atenção ao contexto
- Arquivos grandes (>500 linhas): leia em pedaços (offset/limit).
- Resultados de ferramenta podem truncar. Output que parece cortado → rode de novo com escopo menor.

## Código
- Código humano, sem comentário robótico nem header desnecessário.
- Copie o padrão do código ao redor antes de escrever.
- Não over-engineer. Não adicione abstração que ninguém pediu.

## Comunicação — formato do relatório final
1. **Feito**: o que mudou (1-3 linhas).
2. **Arquivos tocados**: lista exata, nada a mais.
3. **Verificação**: output de tsc/lint/testes OU "não executado: <motivo>".
4. **Riscos / fora de escopo**: o que você notou mas não tocou.
