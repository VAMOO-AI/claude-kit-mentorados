# auditoria-seguranca — Fase 5, classificar a evidência e fechar o veredito

Lido antes de montar o findings.json, depois das seis categorias.

## Fase 5 — classificar a evidência e fechar o veredito

Antes de gerar o PDF, passe achado por achado e responda **quatro** perguntas
que não são a severidade:

1. **Qual é o caminho?** → `caminho[]` e `condicoes[]`. Entrada de menor
   confiança, propagação, sink, cada passo com `arquivo:linha`; e o que precisa
   ser verdade para explorar (nível de auth, papel, flag, config, estado do
   dado), **tipado**. É o que quem corrige refaz e o que o revisor relê. Se o
   primeiro passo não é uma entrada que um ator de menor confiança alcança, o
   achado não tem ator — volte.
2. **Como eu sei disto?** → `evidencia`. O grep casou e você não abriu o arquivo:
   `padrao`. Você abriu, leu o caminho inteiro e ele fecha: `lido`. Existe algo
   fora da sua leitura confirmando — uma requisição real de leitura, outra
   ferramenta, o log de produção: `corroborado`, com a fonte nomeada. Depende de
   fato que o repositório não mostra: `status: a_validar`, com `bloqueio` e
   `plano_validacao`.
3. **Alguém tentou derrubar?** → o juiz. Antes de mandar, quem achou preenche
   `muda_severidade_se`: as condições que, se verdadeiras, mudam a nota ("se a
   rota exige papel admin no middleware, cai para média"). Para cada `alta` e
   `critica`, um subagent `kit-vamoo:revisor` fresco recebe **só** o achado (id,
   título, arquivo:linha, caminho, trecho, por_que, `muda_severidade_se`) e a
   ordem de refutar: reler cada linha citada, procurar o controle que o autor
   não viu (middleware, trigger, policy, gate no caller), conferir que a
   entrada é alcançável pelo ator dito e testar cada condição de
   `muda_severidade_se`. O juiz não recebe sua opinião, sua confiança nem os
   outros achados — isso é o que faz dele uma segunda leitura. Com mais de
   cinco achados graves, lance os juízes em paralelo, um `kit-vamoo:revisor`
   por achado, numa mensagem só.

   O juiz devolve `mantido` ou `refutado`, com motivo em uma frase, e preenche
   `contraevidencia`: a evidência mais forte que achou **contra** o achado e
   por que ela não o derruba. Achado mantido sem `contraevidencia` não foi
   julgado; foi carimbado. O contrato padrão do `kit-vamoo:revisor` em modo juiz
   devolve só veredito e motivo: **o prompt do dispatch pede os três campos por
   nome** (veredito com motivo, `contraevidencia`, severidade nova quando
   rebaixa) ou eles não voltam.

   **Descartar exige a mesma força que confirmar.** `refutado` só vale com uma
   destas três provas, cada uma verificável por quem relê:

   - o **controle** que derruba o achado, com `arquivo:linha`, rodando antes do
     sink em **todos** os caminhos até ele;
   - o **caminho que não fecha**, com `arquivo:linha`: a rota não está
     registrada, o sink é parametrizado, a linha citada não diz o que o achado
     afirma;
   - o **objeto vivo** que bloqueia (policy, privilégio de coluna, trigger),
     com a consulta que o mostra e o resultado.

   Um caminho sem o controle basta para o achado ficar de pé. Não refuta:

   - "a lib/o framework já cuida disso", sem a linha onde cuida;
   - controle que existe, mas em outro caminho até o mesmo sink;
   - chamada irmã que está segura (a rota vizinha filtra tenant; esta não);
   - "não achei quem chama" — a rota publicada é chamável por quem a acha;
   - "é interno" ou "só admin usa", sem o gate que impõe isso no servidor.

   **Juiz que discorda da nota, e não do achado, rebaixa; não apaga.** O
   achado fica `mantido` com a severidade nova e o motivo citando a condição de
   `muda_severidade_se` que se confirmou. Rebaixou por uma condição que não
   estava na lista? Vale igual, desde que o motivo a nomeie com a evidência;
   e ela entra em `muda_severidade_se`, para a próxima leitura conferir a
   mesma coisa. Refutado vira `falso_positivo` com o
   `motivo` do juiz; mantido segue.
4. **Isso ainda está de pé?** → `status`. `risco_aceito` e `falso_positivo` saem
   do cálculo do veredito, mas continuam no relatório com selo e `motivo`:
   sumir com eles é como a mesma discussão volta na auditoria seguinte.

Depois, a severidade — pelas **âncoras** do `findings-schema.md`, não pela
sensação: crítica é não autenticado com execução, banco inteiro ou qualquer
conta; alta é controle explícito **derrotado por completo** (cross-tenant,
bypass de auth, XSS armazenado que atinge outros); média é violação real com
raio pequeno. **A severidade nunca passa do impacto demonstrado**: se o campo
`impacto` não consegue dizer o dano concreto, a nota é menor do que parece. O
que não cruza fronteira nenhuma vai para `hardening[]`, não para `baixa`.

O **veredito** (`BLOQUEADO` / `REVISAR` / `LIBERADO`) sai daí sozinho — regra na
tabela do `findings-schema.md`, calculada pelo gerador. Não escreva veredito à
mão e não negocie a nota para cima: se o cliente precisa de `LIBERADO`, o caminho
é corrigir o achado ou registrar `risco_aceito` com justificativa, não baixar a
severidade.

Três assimetrias que a tabela codifica de propósito:

- **Severidade alta que só bateu num grep vai para `REVISAR`, não bloqueia.** Dá
  para bloquear um deploy com uma leitura, não com um palpite.
- **Crítica não confirmada nunca sai `LIBERADO`.** Confiança baixa numa crítica é
  motivo para ir confirmar, não para encerrar o assunto.
- **Crítica `a_validar` segura em `REVISAR`.** Não bloqueia (não está provada),
  não libera (o bloqueio é para resolver, não para esquecer).

Quando o projeto tiver um gate de deploy, o `BLOQUEADO` daqui é insumo dele, não
uma opinião paralela.
