---
description: Revisa o código que mudou procurando bugs, riscos e simplificações
---

Revise as mudanças atuais (use `git diff` se houver, senão o arquivo/trecho que eu apontei).

Procure, em ordem de prioridade:
1. **Bugs de verdade** — lógica errada, caso não tratado, off-by-one, null/undefined, await faltando.
2. **Riscos** — secret exposto, query sem filtro, falta de validação de input.
3. **Simplificações** — código repetido, abstração desnecessária, algo que já existe pronto.

Quatro coisas que revisor costuma pular e você não pula:
- **Valor novo de enum/status/tipo**: leia TODOS os lugares que consomem os valores irmãos (switch, filtro, lista de permitidos, dropdown, CHECK no banco), mesmo fora do diff. Grep acha o irmão; só a leitura diz se o valor novo cai num default errado.
- **Saída de IA que vira dado**: e-mail, URL, nome ou JSON gerado por modelo indo pro banco, pro e-mail ou pro `fetch` sem validar formato e sem lista de hosts permitidos.
- **Ler-e-depois-gravar sem atomicidade**: `SELECT` seguido de `UPDATE`/`INSERT` sem constraint única ou sem `WHERE` do estado anterior. Duas requisições ao mesmo tempo duplicam ou pulam etapa.
- **Migration**: NOT NULL sem backfill, índice sem CONCURRENTLY em tabela com dado, DROP/RENAME de coluna que o código em produção ainda lê.

Para cada achado: aponte o arquivo:linha, explique o problema em 1 frase e proponha a correção.
Marque cada um como **[mecânico]** (dead code, N+1, comentário que contradiz o código, número mágico, validação faltando: um sênior aplicaria sem discutir) ou **[decisão]** (segurança, race, remover funcionalidade, mudança de comportamento visível, fix acima de ~20 linhas: dois sêniores poderiam discordar). Se eu mandar "aplica os mecânicos", você aplica só esses; os de decisão eu decido um a um.
Reporte tudo que encontrar, rankeado por severidade — eu filtro o que aplicar. Se está bom, diga que está bom.
Não altere nada ainda: só relate. Eu decido o que aplicar.
