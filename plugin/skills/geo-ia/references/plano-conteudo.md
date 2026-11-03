# Plano de conteúdo GEO

Só depois da fase 2 (indexação nos dois índices) e de uma remedição. Antes disso, qualquer
ganho fica sem atribuição.

## Matriz por pergunta

Uma linha por pergunta sem marca, com as fontes que a medição mostrou:

| Pergunta | Página que deveria ganhar | O que as citadas têm e a nossa não | Fontes de fora que aparecem | Ação |
|---|---|---|---|---|
| "treinamento de X in company" | `/treinamento` | título e primeira frase com a intenção exata | listas de "melhores empresas", blogs | indexar; depois entrar nas listas |
| "empresa que faz Y sob medida" | não existe | página dedicada, com casos de uso e etapas | sites de concorrentes | página nova, se a intenção for de fato outra |
| "Z para indústria no Brasil" | nenhuma | mídia e instituições | imprensa, entidades de classe | guia e trabalho fora do site |

Como preencher a terceira coluna: abra 3 a 5 URLs citadas e compare o endereço, o `title`, a
primeira frase e se existe FAQ. Na medição de origem, boa parte das citações do Perplexity era
página de oferta com a intenção no endereço e no título (`/treinamento-ia-empresas`,
`/servicos/agentes-de-ia`). Isso é hipótese a testar, não regra.

## Frentes, em ordem

1. **Ajuste do que existe**: título, descrição e FAQ com a intenção da pergunta. Sem endereço
   novo: página quase igual à que já existe divide a relevância.
2. **Página nova** só para intenção que hoje não tem página e que o portfólio sustenta. Passa
   por `grilling` (rota, prerender, sitemap e IndexNow) antes do código.
3. **Guias**: um guia responde uma pergunta, com a resposta no primeiro parágrafo. Derive da
   pauta de conteúdo que já existe: o mesmo assunto do carrossel ou do Reel, em texto que a IA
   lê. Uma seção de guias é infraestrutura nova (rota, prerender, sitemap), então `grilling`
   antes. Ritmo sustentável: 1 a cada 2 semanas.
4. **Fora do site**, contínuo e na mão do dono:
   - pedir inclusão nas listas de "melhores" que a IA cita;
   - release para mídia do setor e entidades da região, com o ângulo do fundador;
   - evento com página pública (Sympla e afins aparecem citados);
   - podcast ou entrevista em que o fundador aparece com o nome da marca;
   - README público de repositório que diga de quem é o método.
5. **Medição contínua**: uma rodada por semana mostra a curva depois de cada frente.

## Regras de texto

- Número só com fonte. Prova própria só se já for pública e aprovada.
- Nome, tela ou setor identificável de cliente só com autorização escrita.
- O nome da marca sempre na forma oficial, igual em título, JSON-LD e `llms.txt`.
- Copy nova passa pela régua de voz do projeto, se houver, e pela aprovação do dono antes de
  publicar.

## Quando liberar página nova e guias

As três condições, conferidas e registradas:

1. todas as páginas comerciais estão indexadas no Google e no Bing, com rastreamento posterior
   ao último deploy de texto;
2. houve pelo menos uma remedição completa (todos os provedores presentes) depois disso;
3. a pergunta-alvo continua sem a marca e a matriz mostra que falta uma página, não um índice.
