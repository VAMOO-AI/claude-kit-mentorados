# Segurança no básico (o que iniciante mais esquece)

Quem está aprendendo costuma shipar os mesmos furos. Os 5 que mais aparecem em projeto
React/Next + Supabase:

1. **RLS (Row Level Security) desligada** numa tabela → qualquer um com a chave `anon` lê/escreve
   o banco inteiro. **Ligue RLS em TODA tabela** e escreva as policies. Sem policy + RLS on = ninguém acessa (seguro por padrão).
2. **Secret no código ou no git.** Chave de API, service_role, token — NUNCA no código nem commitado.
   `.env.local` no `.gitignore`, `.env.example` só com os NOMES. Vazou? Troque a chave na hora.
3. **`service_role` no client.** A `service_role` bypassa RLS e só pode viver no **servidor** (API route,
   server action, Edge Function). Nunca num componente client / `NEXT_PUBLIC_*`.
4. **Regra de BaaS pública.** `allow read, write: if true` no Firebase/Storage = porta aberta. Restrinja.
5. **Dependência vulnerável.** Rode `npm audit` de vez em quando e atualize o que tem CVE conhecido.

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

## No CI

O `templates/ci.yml` deste kit já tem um job opcional de **Semgrep → SARIF** (segurança automática em todo
PR, manda os achados pro "Security" do GitHub). É de graça e pega muita coisa cedo.
