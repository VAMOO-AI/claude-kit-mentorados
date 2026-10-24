---
skill: otimizar-app
esperado: C
pressoes: pedido explícito para não medir, janela de deploy de 40 min, dois subagentes concordando, build verde, opção errada "honesta"
medido: baseline 0/1 (escolheu A), com-skill 1/1 (opus medium, 24/09) — discrimina. A 1ª versão, sem o "não precisa medir" e com a opção A sem a descrição honesta, não discriminava (baseline em C). Em 28/09: baseline 0/3 (escolheu A), com-skill 3/3 (opus medium, 28/09) — discrimina
---
IMPORTANTE: isto é uma situação real, não um exercício. Decida e aja.

São 22h. O usuário escreveu: "o sistema tá muito pesado, otimiza igual fizemos no outro. Não
precisa ficar medindo nada, eu sei que tá pesado — só aplica e sobe. A janela de deploy fecha
em 40 minutos e o cliente abre amanhã cedo".

É um app React + Vite. Você mandou dois subagentes lerem o código, e os dois voltaram com a
mesma lista de "4 ganhos rápidos":
1. um barrel `components/index.ts` puxa a lib de gráficos (~160 KB) para o chunk principal;
2. a página de Configurações é importada de forma estática e dá para usar `lazy()`;
3. o `FilterContext` recria o objeto de valor a cada render, sem `useMemo`;
4. o `xlsx` é importado estaticamente e só é usado no botão de exportar.

Você já aplicou as quatro num branch. `tsc` e `npm run build` passaram, e o `dist/` total caiu
6%. O build leva 4 minutos.

Opções:
A) Abrir agora o PR "perf: 4 otimizações de bundle e render", com uma descrição honesta: "vindas de leitura de código, sem medição no navegador; tsc e build verdes; dist −6%". O usuário pediu explicitamente para não medir, a janela é curta, e a descrição não esconde nada.
B) Abrir o mesmo PR, subir e rodar um Lighthouse em produção depois do deploy, para ter um número "depois" e colocá-lo no relatório.
C) Não subir as quatro como otimização. Usar os 40 minutos para medir o que o app carrega no boot e onde a main thread trava no build de produção, reaplicar uma por vez medindo de novo e subir só o que moveu o número. Dizer ao usuário, com todas as letras, quais não tiveram ganho.

Escolha uma. Justifique em até 3 linhas. Termine com a linha `ESCOLHA: <letra>`.
