---
name: secscan
description: >-
  Use quando o usuário pedir revisão de segurança, code audit, "checa a
  segurança", "tem RLS faltando?", "secret vazando?", ou "roda um secscan"
  num projeto LOCAL Next.js / React / Supabase em desenvolvimento.
  Read-only — NUNCA edita o código auditado. Não é pra alvo deployado/produção.
---

# secscan — Revisão de segurança (read-only)

Revisão de segurança **estática e read-only** do projeto local que você está construindo.
Olha código, config, `.env`, SQL/migrations e regras de banco com a cabeça de um pentester —
mas NÃO testa nada rodando/deployado/produção. Aponta os problemas; quem corrige é você
(com contexto: schema, testes, risco de regressão).

> **Modo pedagógico é o padrão aqui.** Cada finding explica o conceito em linguagem simples,
> por que o bug acontece e como corrigir passo a passo. Você aprende, não só recebe uma lista.

## Regras de ferro (nunca quebrar)

- **READ-ONLY.** Nunca modifique/apague/crie código ou config no projeto auditado. Só localize (`arquivo:linha`) e sugira o fix. O único arquivo que você escreve é o relatório.
- **Verify, don't claim.** Todo "limpo / sem findings" precisa do output REAL da ferramenta colado na mesma resposta. Não rodou uma ferramenta? Diga "não executado" + o comando que falta.
- **Zero findings ≠ seguro.** Relatório limpo só diz que ESTE scan + as ferramentas disponíveis não acharam nada no escopo. O relatório TEM que deixar isso claro.
- **Só o workspace local.** Ler código, rodar SAST/SCA local, ler o SQL do projeto. Nunca cutucar endpoint externo/deployado. Ler doc oficial (OWASP/CWE) pra embasar um fix é permitido.
- **Ferramentas reais primeiro, heurística confirma (modelo CONFIRMED).** Rode os scanners reais (`semgrep`, `gitleaks`, `npm/pnpm audit`, `osv-scanner`) ANTES de confiar em grep. Achado visto por ferramenta real **+** heurística = `CONFIRMED` (alta confiança); só-heurística = marcado como possível falso-positivo. *(Modelo adaptado do `decksoftware/csreview`, MIT — crédito preservado.)*
- **Ferramenta faltando → ofereça instalar, nunca silencioso, nunca automático.** Se faltar um scanner, diga (confiança menor) + o comando de install. Se o usuário topar: baixe só da fonte oficial, **confira o SHA-256 antes de rodar**, instale num dir isolado e gitignored (nunca global, nunca `sudo`), e siga em modo só-heurística se não der.
- **Na dúvida, pesquise.** Não chute comportamento de framework / detalhe de CVE. Use a skill `find-docs` e cite a fonte no finding.

## Fase 0 — Recon

```bash
pwd
test -f package.json && grep -E '"(next|react|@supabase)"' package.json
ls supabase/migrations/*.sql src/sql/*.sql 2>/dev/null && echo "HAS_SQL"
```
Anuncie quais fases vão rodar (um site estático pula a Fase 2, etc.).

## Fase 0.5 — Scanners reais (rode primeiro)

```bash
command -v semgrep && semgrep scan --config auto --sarif --output secscan.sarif . \
  || echo "semgrep AUSENTE → confiança menor. Instalar: pipx install semgrep"
command -v gitleaks && gitleaks detect --no-banner --redact || echo "gitleaks AUSENTE"
command -v osv-scanner && osv-scanner scan --format json . || echo "osv-scanner AUSENTE (opcional)"
```
Anote quais rodaram vs faltaram no disclaimer do relatório. Semgrep é o que mais agrega.

## Fase 1 — Secrets

```bash
git check-ignore .env .env.local 2>/dev/null   # devem aparecer = estão ignorados
grep -rnE "NEXT_PUBLIC_[A-Z_]*(KEY|SECRET|TOKEN|SERVICE)" --include="*.ts" --include="*.tsx" --include="*.js" . | head
```
Sinalize: `.env`/`.env.local` versionados no git; qualquer coisa sensível atrás de `NEXT_PUBLIC_` (isso vai pro navegador!); `.env.example` faltando.

## Fase 2 — Supabase (o coração)

Olhe o estado real. Com acesso ao banco (psql), consulte as policies; senão leia os SQL/migrations estaticamente:

```bash
grep -rniE "enable row level security|create policy|using *\(true\)|security definer|service_role" \
  supabase/migrations src/sql 2>/dev/null | head
```
Caça:
- **RLS desligada** numa tabela, ou tabela pública **sem policy** pra `anon`/`authenticated` → qualquer um com a chave `anon` lê/escreve tudo.
- **`service_role` no código client** ou atrás de `NEXT_PUBLIC_` → bypass total do banco no navegador. **CRÍTICO**.
- Policy com `using (true)` / `with check (true)` → RLS efetivamente desligada.
- Função `security definer` sem `set search_path` fixo → escalada de privilégio.
- Bucket de Storage público guardando dado de usuário.

## Fase 3 — Next.js / React

- Rota de API / server action **sem checagem de auth** (`getUser`/sessão) antes de mutar/retornar dado.
- `service_role` ou secret importado num Client Component (vaza pro navegador).
- `dangerouslySetInnerHTML` / `innerHTML` com input do usuário → XSS.
- Endpoint retornando a linha inteira (hash de senha, campos internos) — falta filtrar colunas.
- Query de lista sem limite/paginação → DoS.

## Fase 4 — Dependências (SCA)

```bash
test -f package-lock.json && npm audit || true
test -f pnpm-lock.yaml && pnpm audit || true
```
Sinalize versão com CVE conhecido e **pacote alucinado** (importado mas não existe no registry — comum em código gerado por IA).

## Fase 5 — Heurísticas de "vibe-coding"

Padrões que IA costuma gerar. Grep no projeto:
- Auth de mentira: `if (true)`, `next()` sem guard, `SKIP_AUTH`, `DEBUG` bypass.
- JWT com `algorithm: 'none'` ou verificação desligada.
- Senha com crypto fraca: `md5`/`sha1` em vez de bcrypt/argon2.
- `eval` / `new Function` / `child_process.exec` com input do usuário.
- TLS desligado: `NODE_TLS_REJECT_UNAUTHORIZED=0`, `rejectUnauthorized:false`.
- Comentário dizendo "seguro/production-ready" sem nenhum controle real atrás.

## Fase 6 — Relatório

Escreva em `secscan-reports/<YYYY-MM-DD>-secscan.md`. Peça pro usuário adicionar `secscan-reports/`
no `.gitignore` (não edite o `.gitignore` você mesmo). Se o semgrep rodou, guarde o `secscan.sarif` junto.

Estrutura:
1. **Resumo** — contagem por severidade: `CRITICAL N · HIGH N · MEDIUM N · LOW N`.
2. **Disclaimer** — "Zero findings ≠ seguro" + quais ferramentas rodaram vs faltaram (confiança menor se faltou semgrep/gitleaks).
3. **Findings** — um bloco cada:
   - Severidade · **Confiança** (`CONFIRMED` ou `heuristic`) · Categoria · `arquivo:linha`
   - **O conceito** — explique a ideia de segurança em linguagem simples, sem jargão não-definido (ex: "RLS é o porteiro que decide quais linhas cada usuário pode ver; sem ele, qualquer um lê tudo"). Uma analogia vale três definições.
   - **Por que aconteceu** — o padrão que gera esse bug em código de iniciante/IA, pra reconhecer da próxima.
   - **Como corrigir, passo a passo** — numerado, o fix mais simples que está certo. **NÃO aplique** — o aluno aplica e aprende.
   - **Doc oficial** — link via `find-docs`.
4. **Ferramentas executadas** — semgrep/gitleaks/npm audit/osv: rodou ou pulou (com motivo).

Severidade: `CRITICAL` (secret vazado, RLS bypass, RCE) · `HIGH` (falha de autorização, injeção) · `MEDIUM` (falta hardening) · `LOW` (boa prática).

**No fim:** imprima o caminho do relatório. Diga que é esse arquivo que um agente deve ler antes de planejar qualquer fix — não infira o fix só pelo resumo do chat.

## Quer ir mais fundo?

Esta skill é leve e read-only, ótima pra aprender e pegar o grosso. Pra uma suíte completa de SAST
(mais ferramentas tipo Trivy pra IaC, baseline pra CI travar só em achado NOVO, provisão verificada
de binários), veja o **csreview** em [`docs/seguranca.md`](../../docs/seguranca.md).
