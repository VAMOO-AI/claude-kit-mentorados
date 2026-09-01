---
name: secscan
description: >-
  Use quando o usuário pedir revisão de segurança, code audit, "checa a
  segurança", "tem RLS faltando?", "secret vazando?", ou "roda um secscan"
  num projeto LOCAL Next.js / React / Supabase em desenvolvimento.
  Read-only — NUNCA edita o código auditado. Não é pra alvo deployado/produção.
---

> Derivada de `claude-config-team/skills/secscan`. Ao divergir de propósito, diga aqui o quê e por quê.
> Diverge de propósito em um ponto: lá o modo pedagógico é exceção com gatilho;
> aqui ele é o padrão, porque o público do kit é justamente o iniciante.

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
- **Materialized view legível por `anon`/`authenticated`** → vazamento que a RLS não cobre, porque **MV não tem RLS**. É o achado que passa despercebido justamente em projeto com RLS impecável: quem confere RLS e vê tudo verde para de olhar.

  ```sql
  SELECT c.relname,
         has_table_privilege('anon',          c.oid, 'SELECT') AS anon,
         has_table_privilege('authenticated', c.oid, 'SELECT') AS authenticated
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'm';
  ```

  Qualquer `true` é finding, e dá pra provar pela porta do atacante:
  `curl "$SUPABASE_URL/rest/v1/<mv>?select=*" -H "apikey: <anon>"`. Medido numa
  auditoria real em 01/09/2026: 180 de 180 tabelas com RLS, 170 funções
  `SECURITY DEFINER` sem uma falha — e 904 linhas de 16 clientes saindo por uma
  MV, sem nenhum login. Confira o **estado vivo**, não a migration: naquele repo
  o `REVOKE` certo estava versionado havia meses e um `GRANT ALL` posterior o
  desfez em silêncio.
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

**Validação de entrada** (a categoria C4 do checklist sai daqui):

```bash
grep -rn "await req.json()\|request.json()\|req.body\|useSearchParams" \
  src app api supabase/functions 2>/dev/null | head
```

- Handler que lê `body`/`query` tem que validar contra um **schema antes de usar**
  o valor. Detecte o validador que o projeto já tem (`zod`, `valibot`, `yup`,
  `pydantic`, JSON Schema) — não assuma que existe um; a ausência é o achado.
- Valor que decide **dinheiro, permissão ou identidade** vindo do cliente nunca é
  autoridade: o servidor recalcula ou busca no banco. Preço, `role` e `user_id`
  chegando pelo corpo da requisição são o caso clássico.
- Espalhar o objeto do cliente direto no update (`{ ...body }`) é **mass
  assignment** — o usuário manda `role: "admin"` de brinde. E corpo sem teto de
  tamanho é DoS barato.

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

Ordem literal do documento: **Resumo → Disclaimer → 1. CHECKLIST → 2. ANOTAÇÕES →
3. SUGESTÕES DE CORREÇÃO → Ferramentas executadas → Handoff.** Só os três blocos
numerados são obrigatórios em forma; o resto fica em volta, sem numeração.

### As 7 categorias (taxonomia fixa)

Sempre as sete, sempre nesta ordem. A última coluna é quem produz o achado —
nenhuma categoria tem sonda própria fora das fases acima.

| Categoria | Prova mínima (o que precisa ter rodado pra linha sair limpa) | Vem de |
|---|---|---|
| **C1** injeção de código | SAST com ruleset de injeção (`semgrep`) + grep de sink recebendo valor de request: `eval`, `exec`, SQL montado por concatenação, HTML por template | F0.5 + F3 + F5 |
| **C2** autenticação e controle de acesso | Toda rota/handler público checa identidade antes de ler ou mutar; tabela sem RLS ou com policy `using (true)` | F2 + F3 + F5 |
| **C3** exposição de dados sensíveis | Segredo no versionamento **e** no bundle publicado; `service_role`/secret atrás de prefixo público; endpoint devolvendo a linha inteira | F1 + F2 + F3 |
| **C4** validação de entrada | Handler que lê `body`/`query` valida contra schema antes de usar; valor de dinheiro/permissão/identidade vindo do cliente | F3 (bloco de validação) |
| **C5** bibliotecas externas | Audit nativo do lockfile do projeto (`npm`/`pnpm`/`bun`/`poetry`…), ou `osv-scanner`; pacote alucinado | F4 |
| **C6** configurações inseguras | Default inseguro versionado: debug ligado, TLS desligado, CORS `*`, endpoint/credencial hardcoded | F1 + F5 |
| **C7** criptografia e armazenamento | Hash de senha fraco, aleatoriedade não-criptográfica gerando token/reset, JWT sem verificação, segredo legível em repouso | F5 |

### 1. CHECKLIST (obrigatório, sempre impresso)

Tabela de **exatamente 7 linhas**, `Categoria | Estado | Base` — inclusive quando
está tudo limpo. Os estados são **quatro**:

- **`N achado(s)`** — encontrou; os findings vão pro bloco 2.
- **`nenhum problema identificado`** — procurou e não achou. Só sai assim se
  **todas** as provas mínimas daquela linha rodaram.
- **`não medido (<ferramenta> ausente)`** — nomeie o binário que faltou
  (`semgrep`, `gitleaks`, `osv-scanner`).
- **`não aplicável (<motivo>)`** — a precondição da Fase 0 não existe (projeto sem
  banco não tem RLS; site estático não tem rota de API).

Regras duras:

- **É proibido omitir uma linha.** Categoria não investigada é `não medido`, nunca
  limpa — silêncio virando aprovação é o modo de falha desta skill.
- Prova parcial (a heurística rodou, o scanner não) continua `nenhum problema
  identificado`, mas a coluna **Base** carrega o qualificador
  *(parcial: semgrep ausente)*. O qualificador mora na Base, nunca vira um quinto estado.
- **Base** lista o que de fato rodou naquela linha — o comando. Base vazia obriga
  `não medido`.

Exemplo do formato (3 das 7 linhas; **as outras 4 também são impressas**):

| Categoria | Estado | Base |
|---|---|---|
| C2 autenticação e controle de acesso | **2 achados** | grep de `create policy` em `supabase/migrations` · leitura das rotas de API |
| C6 configurações inseguras | nenhum problema identificado | grep de TLS/CORS/debug *(parcial: semgrep ausente)* |
| C5 bibliotecas externas | não medido (osv-scanner ausente) | — |

### 2. ANOTAÇÕES

Só as categorias com achado. Um bloco por finding:

- `Severidade · Confiança (CONFIRMED ou heuristic) · C<n> <categoria> · arquivo:linha`
- **Trecho** — 3 a 8 linhas do código real, com a linha do problema marcada.
  **Nunca cole o valor de um segredo**: só o nome da variável e o prefixo
  (`SUPABASE_SERVICE_ROLE_KEY = eyJhbGciOi…`), no relatório e no chat.
- **O conceito** — explique a ideia de segurança em linguagem simples, sem jargão não-definido (ex: "RLS é o porteiro que decide quais linhas cada usuário pode ver; sem ele, qualquer um lê tudo"). Uma analogia vale três definições.
- **Por que aconteceu** — o padrão que gera esse bug em código de iniciante/IA, pra reconhecer da próxima.
- **Por que é explorável** — o caminho concreto do atacante até o dado, não a definição da classe.
- **Doc oficial** — link via `find-docs`.

### 3. SUGESTÕES DE CORREÇÃO

Uma por finding, nomeando arquivo, linha e a mudança. **NÃO aplique** — quem
aplica é o dono do projeto, e é aplicando que se aprende.

- **Proibido genérico**: "sanitize a entrada", "valide o input", "revise as
  permissões". Isso não é correção, é o nome do problema repetido.
- **Obrigatório específico**: "valide `body` com o schema que já existe em
  `lib/schemas.ts` antes da linha 42", "troque o `escapeHtml` local de
  `Comentario.tsx:97` pelo import de `src/lib/sanitize.ts`", "selecione colunas
  explícitas no lugar de `select('*')` em `useUsuarios.ts:20`".
- **Passo a passo numerado**, o fix correto mais simples em vez do elegante.
- **Como prevenir a categoria** — o que passa a ser rodado sempre pra essa classe
  não voltar.
- **Gate que trava a regressão**, quando existir: o comando que **falha hoje e
  passa depois do fix**. Não existe gate → diga isso e aponte onde ele entraria
  (um step do CI), sem criá-lo — a skill é read-only.

Em volta dos três blocos: **Resumo** com as contagens `CRITICAL N · HIGH N ·
MEDIUM N · LOW N` · **Disclaimer** "Zero findings ≠ seguro" (só significa que este
scan, com estas ferramentas, neste escopo, não achou nada) · **Ferramentas
executadas** — semgrep/gitleaks/npm audit/osv: rodou ou não rodou e por quê. As
linhas `não medido` do checklist têm que bater com essa lista.

Severidade: `CRITICAL` (secret vazado, RLS bypass, RCE) · `HIGH` (falha de autorização, injeção) · `MEDIUM` (falta hardening) · `LOW` (boa prática).

**Handoff:** imprima o caminho do relatório. Diga que é esse arquivo que um agente deve ler antes de planejar qualquer fix — não infira o fix só pelo resumo do chat.

## Fase 7 — Modo pedagógico (é o padrão aqui)

O scan é o mesmo e a estrutura da Fase 6 é a mesma: **os três blocos, na mesma
ordem, e o CHECKLIST continua com as 7 linhas e os 4 estados, sem simplificação**.
É justamente ele que impede o iniciante de ler silêncio como aprovação — a
tentação de "poupar o aluno" some exatamente a informação que ele não tem como
inferir sozinho.

O que muda no modo pedagógico é o **texto dentro dos blocos 2 e 3**, escrito para
quem nunca ouviu falar de RLS ou XSS: o conceito antes do jargão, o padrão que
produziu o bug (quase sempre copy-paste ou um agente que pulou o passo de auth), o
passo a passo numerado e o link da doc real, pra ele aprender a ler a fonte.

Mantenha as contagens de severidade e o disclaimer — iniciante é justamente quem
mais lê relatório limpo como "está seguro". Um relatório só, com enquadramento
pedagógico; não escreva um segundo arquivo.

## Quer ir mais fundo?

Esta skill é leve e read-only, ótima pra aprender e pegar o grosso. Pra uma suíte completa de SAST
(mais ferramentas tipo Trivy pra IaC, baseline pra CI travar só em achado NOVO, provisão verificada
de binários), veja o **csreview** em [`docs/seguranca.md`](https://github.com/VAMOO-AI/claude-kit-mentorados/blob/main/docs/seguranca.md).
