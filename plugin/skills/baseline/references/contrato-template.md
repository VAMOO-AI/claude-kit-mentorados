# Template — `.context/docs/baseline.md`

Copie o bloco abaixo para `<projeto>/.context/docs/baseline.md` e preencha. É o
**contrato do projeto**: a skill é o método, este arquivo é o dado.

Regras de preenchimento:
- Coluna `Estado` só recebe `conforme` com a prova ao lado. Sem prova é
  `nao_medido`.
- Todo item fora do padrão vira **exceção com dono e data**, nunca silêncio.
- O que depende de decisão de pessoa fica `PENDENTE:` — não invente.

---

```markdown
# Baseline — <projeto>

**Atualizado:** <YYYY-MM-DD> · **Base:** `main` @ `<sha>` · **Responsável:** <nome>

Contrato de ambiente e segurança deste projeto. Método em `baseline`.
Auditar: `Skill(baseline)` → modo AUDITAR.

## Superfícies

| Superfície | Onde | Exposição |
|---|---|---|
| App web | `https://<dominio>` (Vercel, projeto `<proj>`) | pública, autenticada |
| Banco / API | Supabase `<ref>` — PostgREST | pública via anon key + RLS |
| Edge functions | `supabase/functions/*` | ver tabela de `verify_jwt` abaixo |
| Automação | n8n `<host>` | webhooks com segredo |

**Ambientes:** <produção só / produção + preview / dev-staging-prod>.
Se não há staging, escreva: *não existe staging — migration errada é incidente de
operação*. Isso muda como tudo é feito e o próximo dev precisa saber.

## Estado por pilar

| # | Pilar | Alvo | Estado | Provado por | Data |
|---|---|---|---|---|---|
| 01 | Frontend | sourcemap não servido, sem segredo em prefixo público, CSP sem `unsafe-inline` | | `curl -sSI <dominio>` | |
| 02 | Banco | RLS em 100%, `SECURITY DEFINER` com `search_path` | | `splinter.sh 0013 0011 0010` | |
| 03 | Auth | fail-closed, todo gate com contrapartida declarada | | curl com token do papel restrito | |
| 04 | Limites | rate limit por identidade, `max_tokens` em LLM | | `collect.sh` + teste de 429 | |
| 05 | Carga | sem query sem teto, agregação no banco acima de 10k | | `pg_stat_user_tables` | |
| 06 | Observabilidade | error tracking ativo, alerta com destino externo | | erro provocado → tracker | |
| 07 | Segredos | inventário completo, scan de HEAD + histórico | | `gitleaks detect` | |

Valores de `Estado`: `conforme` · `nao_conforme` · `parcial` · `nao_medido`.

## Inventário de segredos

| Segredo | Onde vive | Raio de dano | Rotação | Dono |
|---|---|---|---|---|
| | | | | |

## Funções sem verificação de JWT

Cada linha é uma porta aberta de propósito. Sem a coluna de auth própria
preenchida e **provada**, a linha é um finding, não uma exceção.

| Função | Por que é pública | Auth própria | Provada em |
|---|---|---|---|
| | | | |

## Gates de UI e suas contrapartidas

| Gate na interface | Contrapartida no banco | Veredito |
|---|---|---|
| | | real / **cosmético** |

`cosmético` não é acusação — é informação. O risco não é ter gate cosmético; é
não saber qual dos seus gates é.

## Exceções aceitas

| ID | O quê | Motivo | Mitigação | Risco aceito | Dono | Aceito em | Revisar em |
|---|---|---|---|---|---|---|---|
| EX-01 | | | | | | | |

Exceção vencida volta como finding com a severidade original, e com a nota de que
a validade expirou.

## Escopo permitido da auditoria

**Pode:** ler código e config; consultar o banco deste projeto em modo leitura;
rodar scanners locais; `curl` no domínio deste projeto.

**Não pode:** DDL no banco (nem criar schema `lint`); escrever em qualquer tabela;
tocar endpoint de terceiro; usar `semgrep --config auto`; verificar credencial ao
vivo (`trufflehog --only-verified`) sem autorização explícita registrada aqui;
trazer valor de segredo para o contexto.

**Autorizações extras concedidas:** <nenhuma>

## Histórico

| Data | O que mudou | Quem |
|---|---|---|
| <YYYY-MM-DD> | contrato criado | |
```
