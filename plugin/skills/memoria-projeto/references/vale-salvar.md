# Vale salvar?

A pergunta: uma sessão daqui a um mês, sem esta conversa, ficaria surpresa ao descobrir
isso sozinha e grata por já saber? Se ela leria no código, no `git log`, no `AGENTS.md` ou
em `.context/docs/`, não salve. Também fica de fora o que só vale hoje (prazo, o estado de
um PR aberto, quem vai revisar amanhã).

| Não salve | Salve |
|---|---|
| "O projeto usa Next.js e Supabase" (está no `package.json`) | "O e-mail de boas-vindas sai pela função `enviar-boas-vindas`, não pelo Auth do Supabase: o template do Auth não aceita o logo do cliente" |
| "Corrigi o bug do carrinho hoje" (é o commit) | "O total do carrinho diverge do relatório com cupom percentual: o relatório arredonda por item, o carrinho no total. Verificado em 12/10/2026" |
| "Rodar `npm test` antes do PR" (já está no `AGENTS.md`) | "O teste de data passa no meu Mac e falha no CI: ele assume o fuso UTC" |
| "Revisar isso amanhã com o sócio" (contexto do momento) | "O cliente aprova layout pelo WhatsApp, não pelo link de preview: o preview pede login e não abre no celular dele" |

Fato que se provou errado se apaga: memória errada é lida com confiança e ninguém re-checa.
