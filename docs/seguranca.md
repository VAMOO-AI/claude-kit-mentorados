# Segurança no básico (o que iniciante mais esquece)

Quem está aprendendo costuma shipar os mesmos furos. Os 7 que mais aparecem em projeto
React/Next + Supabase:

1. **RLS (Row Level Security) desligada** numa tabela → qualquer um com a chave `anon` lê/escreve
   o banco inteiro. **Ligue RLS em TODA tabela** e escreva as policies. Sem policy + RLS on = ninguém acessa (seguro por padrão).
2. **Secret no código ou no git.** Chave de API, service_role, token — NUNCA no código nem commitado.
   `.env.local` no `.gitignore`, `.env.example` só com os NOMES. Vazou? Troque a chave na hora.
3. **`service_role` no client.** A `service_role` bypassa RLS e só pode viver no **servidor** (API route,
   server action, Edge Function). Nunca num componente client / `NEXT_PUBLIC_*`.
4. **Regra de BaaS pública.** `allow read, write: if true` no Firebase/Storage = porta aberta. Restrinja.
5. **Dependência vulnerável.** Rode `npm audit` de vez em quando e atualize o que tem CVE conhecido.
6. **Nenhum limite de uso.** Endpoint que chama IA, envia e-mail ou WhatsApp **sem teto por
   usuário** vira conta impagável no dia em que um login vazar — e ninguém desconfia, porque
   o tráfego está autenticado. Em chamada de IA, `max_tokens` é obrigatório: sem ele a
   resposta pode crescer sem limite. E `max_tokens` sozinho não basta — mil chamadas de
   1.500 tokens custam o mesmo que uma de 1,5 milhão. Precisa dos dois: teto por chamada e
   cota por usuário.
7. **"Secret" que não é secret.** Variável com prefixo `VITE_` ou `NEXT_PUBLIC_` **vai pro
   bundle** — qualquer visitante lê. Um `VITE_WEBHOOK_SECRET` que "protege" seu webhook não
   protege nada. Se o valor autentica alguma coisa, ele fica do lado do servidor, ponto.

## Ordem importa: duas armadilhas de sequência

Duas coisas quebram não por estarem erradas, mas por entrarem na ordem errada:

- **`drop: ['console']` antes de ter error tracking** apaga o único rastro que você teria
  em produção. Ver [`observabilidade.md`](observabilidade.md) — é a armadilha mais cara
  desta lista, porque o sintoma é *não ter sintoma*.
- **Criar tabela antes da policy** deixa uma janela em que ela nasce aberta (ou fechada
  para todo mundo, e você descobre em produção). Os dois statements andam no mesmo PR.

## Revisão automática: a skill `secscan` (já vem no kit)

O kit instala uma skill **`secscan`** (read-only — NUNCA edita seu código). Peça *"roda um secscan"* /
*"checa a segurança"* e ela revisa o projeto local: RLS, secrets, `service_role` no lugar errado,
dependências vulneráveis e padrões inseguros — e te entrega um relatório com **cada problema
explicado em linguagem simples + como corrigir passo a passo** (modo aluno por padrão). É leve e
ótima pra aprender; roda `semgrep`/`gitleaks` se você tiver, senão cai pra heurística. **Comece por ela.**

## Quer ir mais fundo? CSReview (suite completa)

Quando a `secscan` já for pouco, [`csreview`](https://github.com/decksoftware/csreview) é uma skill de IA
**read-only** mais parruda: roda mais ferramentas de verdade (Semgrep, OSV-Scanner, Gitleaks, **Trivy**
pra IaC/Docker) + heurística, e gera relatório **HTML** + **Markdown** + **SARIF**, com baseline pra CI
(falha só em achado NOVO) e provisão verificada das ferramentas. Pega os mesmos furos da lista acima, com
mais cobertura.

Por que é seguro de usar:
- **read-only** no seu código-fonte (só aponta, não muda nada — quem corrige é você/o agente depois);
- baixa as ferramentas **só de fonte oficial**, com **checksum SHA-256 verificado**, numa pasta isolada e gitignored;
- **fail-open**: se não der pra instalar uma ferramenta, ainda roda em modo de confiança menor.

> Projeto MIT da Deck Software (Márcio PS). É novo/pequeno — vale dar uma olhada antes de adotar em escala,
> mas o design é sólido. Como é de terceiro, **instale via o repositório oficial** e preserve o crédito.

**Como usar (depois de instalar como skill global do agente):** peça *"faça uma revisão de segurança"* /
*"roda um security review"*. O agente roda a skill e te entrega o relatório com o que arrumar, em ordem de prioridade.

## Está pronto pra produção? A skill `baseline`

`secscan` responde *"tem vulnerabilidade no meu código?"*. A skill **`baseline`** responde
uma pergunta diferente: *"este app está apto a ir pro ar?"* — e cobre sete frentes: bundle
e secrets, RLS, login e permissão, limites de uso, carga e cache, observabilidade, e
gestão de segredos.

Ela funciona em dois modos: **construir** (app novo já nasce certo) e **auditar** (app que
já está no ar). Peça *"roda o baseline"* ou *"esse app está pronto pra prod?"*.

Duas ideias dela que valem pra qualquer auditoria que você fizer na vida:

- **"Não medido" nunca vira "está ok".** Se faltou ferramenta ou acesso, o relatório diz
  isso em vez de fingir cobertura.
- **Relatório vazio parece aprovação** — por isso, quando não consegue medir nada, ela
  falha de propósito em vez de entregar um relatório limpo.

## No CI

O `templates/ci.yml` deste kit já tem um job opcional de **Semgrep → SARIF** (segurança automática em todo
PR, manda os achados pro "Security" do GitHub). É de graça e pega muita coisa cedo.
