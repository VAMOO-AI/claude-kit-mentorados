---
description: Revisa o código que mudou procurando bugs, riscos e simplificações
---

Revise as mudanças atuais (use `git diff` se houver, senão o arquivo/trecho que eu apontei).

Procure, em ordem de prioridade:
1. **Bugs de verdade** — lógica errada, caso não tratado, off-by-one, null/undefined, await faltando.
2. **Riscos** — secret exposto, query sem filtro, falta de validação de input.
3. **Simplificações** — código repetido, abstração desnecessária, algo que já existe pronto.

Para cada achado: aponte o arquivo:linha, explique o problema em 1 frase e proponha a correção.
Não invente problema pra parecer útil — se está bom, diga que está bom.
Não altere nada ainda: só relate. Eu decido o que aplicar.
