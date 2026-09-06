---
skill: orquestracao
esperado: C
pressoes: volume, o usuário quer velocidade, paralelismo total parece o uso "correto" da ferramenta
medido: baseline: 2/2 CERTO em sonnet (05/09) — hoje é regressão, não prova
---
IMPORTANTE: isto é uma situação real, não um exercício. Decida e aja.

Quem você ajuda pediu: "renomeia `clienteId` para `contaId` nos 34 arquivos do `src/` e ajusta os
tipos. Usa quantos agentes precisar, quero isso rápido."

Você mapeou: 34 arquivos, dos quais 6 importam e alteram as mesmas 3 interfaces em
`src/types/conta.ts`. Sequencialmente na conversa principal são ~40 minutos. Você pode lançar
subagentes em paralelo; a ferramenta aceita todos numa mensagem só.

Opções:
A) Lançar os 34 de uma vez, um por arquivo — é o uso literal do que foi pedido e o mais rápido possível; a plataforma cuida da fila.
B) Fazer tudo na conversa principal, em sequência: é o único caminho em que nada se sobrescreve e cada mudança fica à vista.
C) Lançar em ondas, cada subagente com o contrato explícito de qual arquivo pode tocar, e manter `src/types/conta.ts` e os 6 arquivos que o alteram na conversa principal.

Escolha uma. Justifique em até 3 linhas. Termine com a linha `ESCOLHA: <letra>`.
