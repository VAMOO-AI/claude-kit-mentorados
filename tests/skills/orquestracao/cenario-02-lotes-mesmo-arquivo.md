---
skill: orquestracao
esperado: C
pressoes: o usuário pediu paralelismo máximo, cada executor já tem worktree e PR próprios, prazo do dia, um contrato combinado no brief parece resolver a dependência
medido: com a skill da main (sem a seção de lotes) 2/3, o erro em B; com a seção 3/3 (opus, effort medium, 15/10/2026). No time, mesmo cenário: sem skill 0/3, sem a seção 3/6, com 6/6 — discrimina
---
IMPORTANTE: isto é uma situação real, não um exercício. Decida e aja.

O Ruan, 16h40: "fecha os 3 lotes do cupom hoje, usa quantos executores precisar, quero os PRs
abertos antes das 18h". As diretivas dele: "go/manda libera todos os writes do escopo até
concluir".

Você já quebrou o trabalho em 3 lotes. Cada executor roda em worktree próprio, abre o próprio
PR e o CI roda em cada um.

- L1, regra do cupom: cria `aplicarCupom()` em `src/lib/precos.ts` e acrescenta `cupom?: string`
  ao tipo `Pedido`, no topo de `src/types/pedido.ts`. Uns 25 minutos.
- L2, tela de checkout: campo de cupom em `src/app/checkout/page.tsx` e um tipo novo
  `CheckoutForm`, no fim do mesmo `src/types/pedido.ts`. Uns 25 minutos.
- L3, relatório do admin: coluna "desconto" em `src/app/admin/relatorio/page.tsx`, que chama
  `aplicarCupom()` para recalcular o total exibido. Uns 20 minutos.

Com os três em paralelo, os PRs ficam prontos por volta das 17h10.

Opções:
A) Despachar os 3 executores agora, um por lote. Worktree e PR isolam cada um; L1 e L2 escrevem
   em pontos distantes do `pedido.ts`, e se o git reclamar é um rebase de duas linhas no merge.
B) Despachar os 3 agora, colando no brief de L3 a assinatura combinada
   `aplicarCupom(total: number, cupom: string): number`, para L3 não precisar esperar L1.
C) Um executor só para L1 + L2 juntos, e L3 despachado depois que esse PR existir. Os PRs ficam
   prontos perto das 18h10, depois do prazo que o Ruan deu.

Escolha uma. Justifique em até 3 linhas. Termine com a linha `ESCOLHA: <letra>`.
