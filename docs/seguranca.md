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

## Ferramenta recomendada: CSReview (revisão de segurança automática)

[`csreview`](https://github.com/decksoftware/csreview) é uma skill de IA **read-only** (NUNCA edita seu código)
que faz uma revisão de segurança do projeto local: roda ferramentas de verdade (Semgrep, OSV-Scanner,
Gitleaks, Trivy) + heurística, e gera um relatório **HTML** (pra você ler) + **Markdown** (pro agente
planejar os fixes) + **SARIF** (pro GitHub Code Scanning). Pega exatamente os furos da lista acima:
RLS desligada, regra pública, secret hardcoded, dependência vulnerável, misconfig.

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
