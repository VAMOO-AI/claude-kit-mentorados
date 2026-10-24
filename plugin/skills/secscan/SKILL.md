---
name: secscan
description: >-
  Varredura de segurança do repositório LOCAL inteiro (Next.js / React /
  Supabase): scanners, RLS faltando, secret vazando, "roda um secscan",
  "checa a segurança do projeto". Read-only, nunca edita. Revisão só do diff
  é o /security-review; entregável para terceiro é a auditoria-seguranca.
---

# secscan — Revisão de segurança (read-only)

Revisão de segurança **estática e read-only** do projeto local que você está construindo.
Olha código, config, `.env`, SQL/migrations e regras de banco com a cabeça de um pentester —
mas NÃO testa nada rodando/deployado/produção. Aponta os problemas; quem corrige é você
(com contexto: schema, testes, risco de regressão).

> **Modo pedagógico é o padrão aqui.** Cada finding explica o conceito em linguagem simples,
> por que o bug acontece e como corrigir passo a passo. Você aprende, não só recebe uma lista.

## Regras de ferro (nunca quebrar)

- **READ-ONLY.** Nunca modifique/apague/crie código ou config no projeto auditado. Só localize (`arquivo:linha`) e sugira o fix. Você só escreve em `secscan-reports/`: o relatório e o SARIF do semgrep.
- **Verify, don't claim.** Todo "limpo / sem findings" precisa do output REAL da ferramenta colado na mesma resposta. Não rodou uma ferramenta? Diga "não executado" + o comando que falta.
- **Zero findings ≠ seguro.** Relatório limpo só diz que ESTE scan + as ferramentas disponíveis não acharam nada no escopo. O relatório TEM que deixar isso claro.
- **Só o workspace local.** Ler código, rodar SAST/SCA local, ler o SQL do projeto. Nunca cutucar endpoint externo/deployado. Ler doc oficial (OWASP/CWE) pra embasar um fix é permitido.
- **Ferramentas reais primeiro, heurística confirma (modelo CONFIRMED).** Rode os scanners reais (`semgrep`, `gitleaks`, `npm/pnpm audit`, `osv-scanner`) ANTES de confiar em grep. Esta é a única definição de `Confiança` da skill: achado é `CONFIRMED` quando ferramenta real e heurística concordam **ou** quando um teste do próprio projeto exercita o mesmo ponto; qualquer outro é `heuristic` (pode ser falso positivo). *(Modelo adaptado do `decksoftware/csreview`, MIT — crédito preservado.)*
- **Ferramenta faltando → ofereça instalar, nunca silencioso, nunca automático.** Se faltar um scanner, diga (confiança menor) + o comando de install. Se o usuário topar: ferramenta Python (`semgrep`) vai pelo gerenciador oficial (`pipx install semgrep==1.181.0`, `uv tool install semgrep==1.181.0` ou `brew install semgrep`); binário baixado à mão (`gitleaks`, `osv-scanner`) vem só da página de releases oficial, com o **SHA-256 conferido antes de rodar**. Nos dois casos, fora do projeto auditado e nunca com `sudo`. Não deu → siga em modo só-heurística.
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
mkdir -p secscan-reports
# AUSENTE é só binário que não existe. Scanner que roda e sai ≠ 0 falhou ou achou algo.
if ! command -v semgrep >/dev/null; then echo "semgrep AUSENTE → confiança menor. Instalar: pipx install semgrep==1.181.0"
else
  out=$(semgrep scan --config p/owasp-top-ten --metrics=off --sarif --output secscan-reports/secscan.sarif . 2>&1); rc=$?
  # No sucesso o resumo (regras, arquivos, achados) está no fim do $out: vai junto do OK.
  if [ "$rc" -eq 0 ]; then echo "semgrep OK → achados em secscan-reports/secscan.sarif"; printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -15
  else echo "semgrep FALHOU (exit $rc) → não medido; última linha: $(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -1)"; fi
fi
# gitleaks em dois modos, sempre --redact (valor de segredo não chega à conversa): o
# histórico (`detect`) e a árvore de trabalho (`dir`), porque o `detect` não lê o que
# ainda não foi commitado. Legenda do exit: 0 limpo · 1 achou segredo · outro falhou.
if ! command -v gitleaks >/dev/null; then echo "gitleaks AUSENTE"
else
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    out=$(gitleaks detect --no-banner --redact -v 2>&1); rc=$?
    printf '%s\n' "$out"
    case "$out" in
      *"not a git repository"*) echo "gitleaks histórico não medido (sem git)" ;;
      *) echo "gitleaks histórico exit $rc (0 limpo · 1 achou segredo · outro falhou)" ;;
    esac
  else echo "gitleaks histórico não medido (sem git): fora de repositório ele sai 0 sem ler nada"; fi
  # `dir` existe desde a 8.19; antes dela o equivalente é `detect --no-git`.
  if gitleaks --help 2>&1 | grep -q '^ *dir '; then gitleaks dir --no-banner --redact -v .
  else gitleaks detect --no-git --source . --no-banner --redact -v; fi
  echo "gitleaks árvore exit $? (0 limpo · 1 achou segredo · outro falhou)"
fi
if ! command -v osv-scanner >/dev/null; then echo "osv-scanner AUSENTE (opcional)"
else osv-scanner scan --format json .; echo "osv-scanner exit $? (0 limpo · 1 achou vulnerabilidade · 128 sem lockfile = não medido · outro falhou)"; fi
if ! command -v trivy >/dev/null; then echo "trivy AUSENTE (opcional: IaC/Docker/misconfig)"
else trivy fs --scanners misconfig,vuln --quiet .; echo "trivy exit $? (0 rodou, achados na saída acima · outro falhou)"; fi
```
Anote quais rodaram, quais faltaram e quais falharam no disclaimer do relatório. Scanner
que falhou não é scanner ausente: instalar de novo não resolve, e a causa (rede, ruleset,
a última linha do erro) vai para o relatório.

Ruleset **fixo**, nunca `--config auto`: o `auto` faz login no registry da Semgrep e manda a
URL do projeto junto, o que não se faz em repositório de cliente. Semgrep é o que mais agrega —
mas saiba o que ele corrobora de fato. **Medido em 31/08/2026** num app React + Supabase:
o ruleset OWASP rodou 255 regras sobre 2.198 arquivos e devolveu 27 findings, **100% em
`.github/` e `.npmrc`**, zero em `src/`, zero em `supabase/functions/`. Num diretório com
quatro vulnerabilidades de código plantadas de propósito: 2 findings, ambos no `ci.yml`,
nenhuma das quatro. Consequência: neste stack **todo achado de C1 (injeção) é
`heuristic`** por construção, e a linha C1 do checklist diz isso — em vez de deixar o
leitor supor que o silêncio do semgrep é ausência de problema.

## Fase 1 — Secrets

```bash
git check-ignore .env .env.local 2>/dev/null   # devem aparecer = estão ignorados
grep -rnE "(NEXT_PUBLIC|VITE)_[A-Z_]*(KEY|SECRET|TOKEN|SERVICE)" --include="*.ts" --include="*.tsx" --include="*.js" . | head
```
Sinalize: `.env`/`.env.local` versionados no git; qualquer coisa sensível atrás de `NEXT_PUBLIC_` ou `VITE_` (os dois vão pro navegador!); `.env.example` faltando.

**Triagem obrigatória antes de reportar número do gitleaks.** Os dois modos da Fase 0.5
somam: o `detect` lê só o histórico commitado e o `dir` lê a árvore de trabalho, inclusive o
que o git ignora. A contagem crua é quase toda ruído: numa auditoria real, "67 leaks" viraram
**zero** achado. Separe em três baldes e reporte só o terceiro como finding, com a contagem
de cada um à vista:

1. **Arquivo não rastreado** (`git check-ignore` / `git ls-files --error-unmatch`): cache de
   ferramenta, `dist/` e o próprio `.env.local`, que é ignorado de propósito. Não vazou para
   lugar nenhum: é higiene local, não incidente.
2. **Rastreado mas público por desenho**: decodifique antes de gritar. JWT com `role=anon`
   do Supabase é chave pública, vai no navegador por contrato:
   `printf %s "<jwt>" | cut -d. -f2 | base64 -d 2>/dev/null` resolve em um comando.
3. **Rastreado e secreto**: `role=service_role`, `sbp_`, `sk-ant-`, senha de Postgres.
   **Este é o finding**, e é CRITICAL. Zero aqui com 60 no balde 1 é um repo saudável.

Achado só do `dir` em arquivo rastreado é segredo prestes a ser commitado (balde 3); em
arquivo ignorado, balde 1.

## Fase 2 — Supabase (o coração)

Olhe o estado real, não chute. Com acesso ao banco (psql, ou o script de SQL que o projeto
já tem; se existir `.context/docs/deploy.md`, ele diz qual), consulte as policies vivas,
**uma query por chamada**:

```sql
select schemaname, tablename from pg_tables where schemaname='public' and rowsecurity is false;
select tablename, policyname, roles, cmd, qual from pg_policies where schemaname='public' order by tablename;
```

Sem acesso ao banco, leia os SQL/migrations estaticamente:

```bash
grep -rniE "enable row level security|create policy|using *\(true\)|security definer|service_role" \
  supabase/migrations src/sql 2>/dev/null | head
```

A migration diz o que alguém quis; o banco diz o que vale. Os dois divergem com frequência
(um `GRANT` posterior desfaz um `REVOKE` antigo, uma função recriada à mão perde o
`search_path`): quando der para consultar o banco, ele é a autoridade e o grep é só o
localizador.
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

  Qualquer `true` é finding, e a própria query prova: o privilégio é o fato. A
  prova pela porta do atacante vai no relatório, para o dono do projeto rodar
  contra o projeto dele — a skill não chama endpoint publicado:
  `curl "$SUPABASE_URL/rest/v1/<mv>?select=*" -H "apikey: <anon>"`. Medido numa
  auditoria real em 01/09/2026: 180 de 180 tabelas com RLS, 170 funções
  `SECURITY DEFINER` sem uma falha — e 904 linhas de 16 clientes saindo por uma
  MV, sem nenhum login. Confira o **estado vivo**, não a migration: naquele repo
  o `REVOKE` certo estava versionado havia meses e um `GRANT ALL` posterior o
  desfez em silêncio. View com `security_invoker` que lê de uma MV entrega o dado do
  mesmo jeito: o invoker respeita a permissão, e a permissão é que está aberta.
- **`service_role` no código client** ou atrás de `NEXT_PUBLIC_`/`VITE_` → bypass total do banco no navegador. **CRÍTICO**.
- **Cliente admin (`service_role`) numa rota pública** (ex.: página sem login como
  `/r/[token]`) fazendo `select *` ou joins com `(*)`: passa por cima da RLS e traz coluna
  sensível de brinde (dado pessoal do dono, campo interno). Sinalize sempre; a
  **severidade depende da exposição**: o dado sensível aparece no JSX ou vai para um Client
  Component → HIGH; é buscado e nunca renderizado → LOW (latente: o próximo render vaza o
  dado, porque ele já está no objeto). O fix é o mesmo: colunas explícitas, nunca `*`.
- Policy com `using (true)` / `with check (true)` → RLS efetivamente desligada. A
  contrapartida (constraint de domínio compensando) é da Fase 2.5.
- Função `security definer` sem `set search_path` fixo → escalada de privilégio. O
  `pg_proc` é a autoridade (`select proname, proconfig from pg_proc where prosecdef`); o grep
  nas migrations só localiza.
- Bucket de Storage público guardando dado de usuário.

## Fase 2.5 — Validação de entrada (C4)

Ausência de schema **é** o achado; não precisa de um sink depois dela. As ferramentas que
olham só o diff costumam recusar esta classe ("missing input validation" sem impacto
provado), por isso ela tem fase própria.

**Passo 0: descubra o validador antes de exigir um.** Não cobre zod de um repo Python:

```bash
grep -hoiE '(zod|valibot|yup|ajv|joi|superstruct|class-validator|pydantic|marshmallow|jsonschema|cerberus|go-playground/validator)' \
  package.json pyproject.toml requirements.txt go.mod composer.json Gemfile 2>/dev/null | sort -u
```

Zero hits **não é o finding**: só muda a comparação para guarda escrita à mão (`typeof`,
`if (!body.x)`, `isinstance`). O finding é o boundary sem nenhum dos dois. Ausência de
validação é `heuristic` por construção (você detecta uma chamada que *não existe*); vira
`CONFIRMED` pelo critério único das regras de ferro, e aqui um teste do projeto que
exercita o boundary conta.

Os boundaries a caçar (server action e form, fila, webhook de automação, valor que decide
dinheiro/permissão/identidade, policy permissiva sem constraint, identidade sem
normalização, limite de entrada, mass assignment, confusão de tipo) estão em
[references/c4-validacao.md](references/c4-validacao.md), com o veredito de cada um: leia
ao avaliar C4.

Levantamento: estes três imprimem o **gap**, não o inventário.

```bash
# 1. GAP: function que lê entrada crua MENOS a que tem schema. O receptor do body muda de
# nome (`req`, `request`, `_req`): fixar em `req.json()` subconta. E `.json()` solto casa
# `response.json()`, que é leitura de RESPOSTA. Varra a pasta inteira, não só `*/index.ts`.
comm -23 \
  <(grep -rlnE "\b(req|request|_req|rq)\.(json|formData|text|arrayBuffer)\(|new URL\((req|request|_req|rq)\.url\)" supabase/functions --include="*.ts" 2>/dev/null | grep -v '/_shared/' | sort) \
  <(grep -rlnE "zod|valibot|safeParse|z\.object" supabase/functions --include="*.ts" 2>/dev/null | grep -v '/_shared/' | sort)

# 2. teto de tamanho na entrada + mass assignment + coerção sem guarda
grep -rlnE "content-length|MAX_BYTES|file\.size|\.length *> *[0-9]{3}" supabase/functions/*/index.ts 2>/dev/null
grep -rnE "\.(insert|update|upsert)\((body|payload|data|input|params)\b|\.(insert|update|upsert)\(\{ *\.\.\.|Number\((body|payload|params|url\.searchParams)" \
  src supabase/functions --include="*.ts" --include="*.tsx" 2>/dev/null
```

```sql
-- 3. função que o papel anônimo executa com parâmetro que decide dinheiro/permissão/identidade
select p.oid::regprocedure, pg_get_function_arguments(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'EXECUTE')
   and pg_get_function_arguments(p.oid) ~* '(total|price|amount|valor|desconto|status|role|user_id|owner|content)';
```

Sem acesso ao banco, o item 3 vira estático: o `GRANT EXECUTE ... TO anon` nas migrations e a
leitura da assinatura de cada função.

## Fase 3 — Next.js / React

- Rota de API / server action **sem checagem de auth** (`getUser`/sessão) antes de mutar/retornar dado.
- `service_role` ou secret importado num Client Component (vaza pro navegador).
- Endpoint retornando a linha inteira (hash de senha, campos internos) — falta filtrar colunas.
- Query de lista sem limite/paginação → DoS (e o teto de 1.000 linhas do Supabase cortando calado).
- CORS `Access-Control-Allow-Origin: *` em endpoint autenticado.

A validação de entrada (C4) tem fase própria, a 2.5.

### C1 — Injeção

Varredura do **repositório inteiro** em sete grupos: SQL dinâmico, command injection, XSS
(inclusive o HTML montado fora do framework: e-mail, PDF, bot), caminho e chave de Storage,
template e expressão (Code Node e `{{ }}` do n8n), SSRF, e injeção em log e em filtro
(`.or()` do supabase-js). Os comandos e o veredito de cada grupo estão em
[references/c1-injecao.md](references/c1-injecao.md): leia ao avaliar C1. O semgrep não
corrobora código de app neste stack, então **todo achado de C1 é `heuristic`**, e a linha C1
do checklist diz isso.

### Webhooks e n8n

- Nó Webhook **sem validação de header de auth ou segredo** na chamada que chega.
- Credencial escrita dentro de um Code Node em vez de ficar nas credenciais do n8n.
- Payload que chega usado sem validação (injeção em nó seguinte, SQL, shell). O schema é
  da Fase 2.5; aqui é a guarda de quem pode chamar.
- Tópico de push (ntfy) ou URL de webhook de chat com o token no caminho, em texto no git:
  a própria URL é a senha.

## Fase 4 — Dependências (SCA)

```bash
f=$(ls package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb 2>/dev/null | head -1)
[ -n "$f" ] && echo "lockfile: $f" \
  || echo "SEM LOCKFILE → C5 é 'não medido (lockfile ausente)', nunca 'nenhum problema identificado'"
test -f bun.lock && bun audit || true
test -f package-lock.json && npm audit || true
test -f pnpm-lock.yaml && pnpm audit || true
```
Com `yarn.lock` ou `bun.lockb`, o `npm audit` não serve: rode `yarn npm audit` (Yarn 2+) ou
`yarn audit` (Yarn 1), ou leia o `osv-scanner` da Fase 0.5, que entende `yarn.lock` (o
`bun.lockb` é binário e ele não lê: C5 fica `não medido` sem outro scanner).
O teste do lockfile é o resultado do `ls`, não o exit do pipe: o `head` sai 0 mesmo sem
nada para ler, e aí o aviso nunca saía. E ele não é decoração: os `|| true` são exatamente
o modo de falha que esta skill acusa nos outros — sem lockfile, tudo falha em silêncio e
C5 sairia limpa sem ter lido uma linha. `osv-scanner` tem o mesmo defeito: não lê `package.json` puro, roda, sai 0
e não mede nada (medido em 31/08/2026: zero achado, e as vulnerabilidades estavam lá).

Sinalize versão com CVE conhecido e **pacote alucinado** (importado mas não existe no registry — comum em código gerado por IA).
Pra achar o alucinado, `npm install --package-lock-only --ignore-scripts` falha com E404
nomeando o fantasma — rode numa **cópia** do `package.json` fora do repo (o comando escreve
lockfile, e você é read-only aqui). Efeito colateral que vai no relatório: essa mesma falha
impede gerar o lockfile, então um repo com dependência inventada deixa C5 cega também para
as CVEs reais. Reporte os dois fatos juntos. Complemento: liste os imports sem entrada no
lockfile e triague à mão (alias de caminho, módulo nativo e módulo virtual do bundler são
ruído).

### C5.2 — Subir versão é mudança de código (o PR de bump)

A Fase 4 olha o que **está** instalado. Esta parte olha a mudança que **troca** o
instalado: o PR mais fácil de aprovar sem ler, e o que meses depois vira "não mudei nada
e quebrou". A pergunta da triagem é uma só: **o que passou a rodar aqui que ninguém
escreveu?** Entra quando o escopo é uma branch/PR, ou quando o histórico recente mexeu
nas dependências:

```bash
git diff --stat origin/main...HEAD -- package.json package-lock.json pnpm-lock.yaml bun.lock
git log --oneline -5 -- package.json
git ls-files package-lock.json pnpm-lock.yaml bun.lock   # vazio com lockfile no disco = lockfile fora do git
```

- **Um pacote por PR** (ou um grupo pequeno e relacionado). Bump em lote quebra o build e
  esconde qual dos 14 pacotes quebrou, e o revert leva os 13 inocentes junto.
- **O que decide é o changelog, não o número.** Semver é promessa do mantenedor, não
  garantia: patch carrega mudança de comportamento com frequência. Em major, o PR diz
  **o que quebra** — "subiu de 4 para 5" não é descrição.
- **Testes verdes ANTES e DEPOIS**, com output colado. "Instalou" não é verificação. Se
  quase nenhum teste passa pelo que a dependência faz, **essa lacuna é o achado**: o
  teste vem antes do bump, senão o verde não prova nada.
- **O lockfile é o que de fato sobe.** Revise o diff dele, não só o do `package.json`;
  commite sempre; nunca edite à mão. Um bump direto arrasta dezenas de dependências
  indiretas, e é ali que mora o pacote que ninguém escolheu. `^4.2.0` no `package.json`
  aceita qualquer 4.x: sem lockfile no git, cada `npm install` pode montar outra árvore.
  No CI, a instalação tem que ser a que respeita o lockfile (`npm ci`,
  `pnpm install --frozen-lockfile`, `bun install --frozen-lockfile`); `npm install` no CI
  resolve as faixas de novo e testa uma árvore que ninguém revisou.
- **Dependência nova pede procedência**, não só versão: existe no registro (pacote
  alucinado é a Fase 4), quem mantém, quando foi o último commit, licença, quanto pesa no
  bundle. E a pergunta anterior a todas: **o que já está no projeto resolve isso?** Toda
  dependência é passivo.
- **`postinstall` é execução de código na sua máquina e no CI.** Em pacote novo ou em
  major, olhe os scripts de instalação antes de rodar; `--ignore-scripts` na primeira
  instalação é barato.

Reporte como achado de **C5** quando a mudança de dependência não tiver changelog lido,
testes verdes dos dois lados, lockfile revisado e commitado, ou quando o CI instalar com
`npm install`. Não é detalhe: é a via de supply chain que a Fase 4 não vê, porque na hora
do scan a versão nova já está instalada. No modo pedagógico, o caso contado passo a passo
está em [`docs/seguranca.md`](https://github.com/VAMOO-AI/claude-kit-mentorados/blob/main/docs/seguranca.md#atualizar-dependência-também-é-mudança-de-código).

## Fase 5 — Heurísticas de "vibe-coding"

Padrões que IA costuma gerar. Grep no projeto:
- Auth de mentira: `if (true)`, `next()` sem guard, `SKIP_AUTH`, `DEBUG` bypass.
- `eval` / `new Function` com input do usuário (`child_process.exec` é a C1.2).
- Comentário dizendo "seguro/production-ready" sem nenhum controle real atrás.

### C7 — Criptografia e armazenamento

Hash de senha sem KDF (sha256 puro é o que passa batido), gerador comum criando token ou
slug, comparação de segredo sem tempo constante, cripto simétrica com ECB ou IV fixo, TLS
desligado, JWT sem verificação, segredo e dado pessoal em repouso (coluna em claro, cron,
localStorage, arquivo em base64 numa coluna) e gestão de chave. Os comandos (`git grep`, só
arquivo rastreado) e os hits que não são finding estão em
[references/c7-cripto-armazenamento.md](references/c7-cripto-armazenamento.md): leia ao
avaliar C7. O discriminante é o **destino** do valor, nunca a primitiva. C7 só sai como
"nenhum problema identificado" se as varreduras de hash, aleatoriedade e armazenamento
rodaram de fato.

## Falso positivo — o que a calibração ensinou

Medido em 31/08/2026, rodando esta skill num app real: **5 dos 14 achados HIGH+ eram
reais — 36% de precisão**, contra uma meta de 70%. Um relatório onde dois em cada três
alertas graves são ruído deixa de ser lido — e aí o achado real passa junto. Regras que
saíram dessa rodada:

- **Grep localiza; leitura decide.** Nenhum comando desta skill emite veredito. Ele aponta
  o arquivo; você abre a linha, segue de onde o valor vem e só então escreve o finding.
  Finding sem `arquivo:linha` que você mesmo leu não existe.
- **Anotação de exemplo apodrece.** Todo `arquivo:linha` que veio de relatório anterior,
  de memória ou de exemplo nesta skill foi medido num repo, numa data. Na calibração, a
  skill mandava reportar um fallback `Math.random()` de token de convite que já tinha
  virado `crypto.randomUUID()` — repetir a anotação era **fabricar finding**. Antes de
  citar, abra o arquivo: se o código mudou, a anotação é ruído, não atalho.
- **Não conte o mesmo hit duas vezes.** Greps de bullets vizinhos se sobrepõem (na
  calibração, "29 mass assignment" eram 20 + 9 coerções `Number()` que o bullet seguinte
  contava de novo). Some as contagens do Resumo só depois de triar.
- **O discriminante é o destino do valor, nunca a primitiva.** `md5()` num fingerprint e
  `Math.random()` numa key de lista React não são finding; `Math.random()` gerando token de
  reset é. Diga no finding por que aquele uso é explorável, não que a função existe.
- **Falso positivo julgado mora num arquivo, não no código.** `nosemgrep` e
  `eslint-disable` espalham a decisão pelo diff e não dizem quem decidiu nem quando. O dono
  do projeto registra em `.context/docs/security/vereditos.md` (fingerprint · veredito ·
  por quê · quem · quando — a skill `baseline` lê a mesma tabela). Antes de reportar,
  consulte: achado já julgado não volta como novo. O veredito vence quando o código ao
  redor muda — por isso o "por quê" é obrigatório.

**Precedentes.** [references/checklist-incidentes.md](references/checklist-incidentes.md)
traz 27 checks de C2, C3, C5 e C6 que nasceram de incidente real, cada um com como achar a
ferramenta equivalente no repo auditado: consulte durante as Fases 2 a 5, ou quando um
finding precisar de precedente.

**Calibração da casa.** Se existir `~/.claude/docs/secscan-casa.md` (ou
`.context/docs/security/calibracao.md` no projeto), leia durante as Fases 2 a 5: ele traz
os incidentes datados e as contagens medidas num repo de verdade, com o comando de cada
check naquele stack. É calibração de um repo, não resposta: rode o comando no repo auditado
e cole a saída de agora.

## Fase 6 — Relatório

Escreva em `secscan-reports/<YYYY-MM-DD>-secscan.md`. Peça pro usuário adicionar `secscan-reports/`
no `.gitignore` (não edite o `.gitignore` você mesmo). Se o semgrep rodou, o `secscan.sarif` já está nessa pasta (Fase 0.5).

Ordem literal do documento: **Resumo → Disclaimer → 1. CHECKLIST → 2. ANOTAÇÕES →
3. SUGESTÕES DE CORREÇÃO → Ferramentas executadas → Handoff.** Só os três blocos
numerados são obrigatórios em forma; o resto fica em volta, sem numeração.

### As 7 categorias (taxonomia fixa)

Sempre as sete, sempre nesta ordem. A última coluna é quem produz o achado —
nenhuma categoria tem sonda própria fora das fases acima.

| Categoria | Prova mínima (o que precisa ter rodado pra linha sair limpa) | Vem de |
|---|---|---|
| **C1** injeção de código | SAST com ruleset de injeção (`semgrep`) + os sete grupos do bloco C1 (SQL, shell, HTML fora do framework, caminho, template, SSRF, log e filtro). O semgrep não corrobora código de app neste stack (Fase 0.5): todo achado sai `heuristic`, e a linha diz isso | F0.5 + F3 |
| **C2** autenticação e controle de acesso | Toda rota/handler público checa identidade antes de ler ou mutar; tabela sem RLS ou com policy `using (true)`; toda function que dispensa o gateway valida o chamador (bloco abaixo) | F2 + F3 |
| **C3** exposição de dados sensíveis | Segredo no versionamento **e** no bundle publicado (`grep` de `sbp_`/`eyJhbGciOi`/`sk-ant-` no `dist/` depois do build); `service_role`/secret atrás de prefixo público; endpoint devolvendo a linha inteira; view sem `security_invoker` lendo tabela protegida; duas policies PERMISSIVE do mesmo comando para o mesmo papel (somam com OR) | F1 + F2 + F3 |
| **C4** validação de entrada | Fase 2.5 inteira: o gap de boundary sem schema impresso, valor de dinheiro/permissão/identidade, limite de entrada, mass assignment | F2.5 |
| **C5** bibliotecas externas | Audit nativo do lockfile do projeto (`npm`/`pnpm`/`bun`/`poetry`…), ou `osv-scanner`; pacote alucinado; o CI roda algum audit? (`grep -rn audit .github/workflows/ package.json`: vazio é finding de processo) | F4 |
| **C6** configurações inseguras | Default inseguro versionado: debug ligado, TLS desligado, CORS `*`, URL de auth com curinga (`site_url` em `http://` no `supabase/config.toml`), endpoint/credencial hardcoded, URL de webhook ou tópico de push com o token no caminho | F1 + F3 + F5 |
| **C7** criptografia e armazenamento | Bloco C7 inteiro: hash, aleatoriedade, slug, comparação, cripto simétrica, TLS, JWT, armazenamento, gestão de chave | F5 |

Uma sonda de C2 que vale para todo projeto Supabase com functions: function fora do
`supabase/config.toml` herda o padrão (`verify_jwt = true`) no próximo deploy, e quem a
chamava sem JWT passa a tomar 401 no gateway, sem erro em lugar nenhum. E toda function com
`verify_jwt = false` precisa provar o chamador no próprio código (segredo em header, HMAC do
payload ou validação de token).

```bash
# O `test -f` não é decoração: sem ele, num repo sem config.toml o comm lista TODAS as
# functions e sai 0, e a skill reporta "N desprotegidas" num repo que só não tem o arquivo.
if [ -f supabase/config.toml ]; then
  comm -23 <(ls supabase/functions | grep -v '^_shared' | sort) \
           <(grep -o '^\[functions\.[^]]*\]' supabase/config.toml | sed 's/\[functions\.//;s/\]//' | sort)
else
  echo "sem supabase/config.toml → esta sonda de C2 é 'não aplicável (sem config.toml)', NUNCA 'todas desprotegidas'"
fi
```

### 1. CHECKLIST (obrigatório, sempre impresso)

Tabela de **exatamente 7 linhas**, `Categoria | Estado | Base` — inclusive quando
está tudo limpo. Os estados são **quatro**:

- **`N achado(s)`** — encontrou; os findings vão pro bloco 2.
- **`nenhum problema identificado`** — procurou e não achou. Só sai assim se
  **todas** as provas mínimas daquela linha rodaram.
- **`não medido (<ferramenta> ausente)`** — nomeie o binário que faltou
  (`semgrep`, `gitleaks`, `osv-scanner`). Instalado e falhou (a Fase 0.5 imprime
  `FALHOU` ou um exit fora da legenda) é **`não medido (<ferramenta> falhou: exit N)`**,
  nunca `ausente`. **Ferramenta presente com input ausente
  também é não medido**, e é o caso que mais engana: `osv-scanner` instalado num projeto
  sem lockfile roda, sai 0 e não lê nada; o histórico do `gitleaks` fora de repositório git
  também (a árvore de trabalho continua medida pelo `gitleaks dir`). Escreva
  o motivo real — `não medido (lockfile ausente)`, `não medido (sem git)` —, nunca "nenhum problema identificado" com a ferramenta na coluna Base.
- **`não aplicável (<motivo>)`** — a precondição da Fase 0 não existe (projeto sem
  banco não tem RLS; site estático não tem rota de API).

Regras duras:

- **É proibido omitir uma linha.** Categoria não investigada é `não medido`, nunca
  limpa — silêncio virando aprovação é o modo de falha desta skill.
- Prova parcial (a heurística rodou, o scanner não) continua `nenhum problema
  identificado`, mas a coluna **Base** carrega o qualificador
  *(parcial: semgrep ausente)*. O qualificador mora na Base, nunca vira um quinto estado.
- **Prova parcial COM achado é `N achado(s)`, e o qualificador continua obrigatório.** Parte
  das sondas da linha não rodou (sem `config.toml`, sem acesso ao banco) e as que rodaram
  acharam coisa. `não medido` apagaria achado real; `N achados` sozinho esconde que metade
  da prova não rodou. Escreva `2 achados` no Estado e `(parcial: sem acesso ao banco — a
  consulta de policies não rodou)` na Base. Nunca escolha entre o achado e o buraco:
  reporte os dois.
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
MEDIUM N · LOW N · INFO N` · **Disclaimer** "Zero findings ≠ seguro" (só significa que este
scan, com estas ferramentas, neste escopo, não achou nada) · **Ferramentas
executadas** — semgrep/gitleaks/audit/osv/trivy/consulta ao banco: rodou ou não rodou e por quê. As
linhas `não medido` do checklist têm que bater com essa lista.

Severidade: `CRITICAL` (secret vazado, RLS bypass, RCE) · `HIGH` (falha de autorização, injeção) · `MEDIUM` (falta hardening) · `LOW` (boa prática) · `INFO` (registro, sem risco hoje).

**Handoff:** imprima o caminho do relatório. Diga que é esse arquivo que um agente deve ler antes de planejar qualquer fix — não infira o fix só pelo resumo do chat.

### O que se corta do relatório (e o que é proibido cortar)

A saída desta skill é **artefato de handoff**: o arquivo que outro agente lê antes de
corrigir, e achado que não está escrito nele some quando a sessão acaba. Cortar conselho
custa atenção; cortar achado esconde vulnerabilidade. Por isso o arquivo leva tudo, e o
corte, quando existe, é só no chat. A lição vale além desta skill: **regra editorial boa
num lugar vira defeito no outro quando muda o que a saída é.**

**Proibido no arquivo do relatório:**

- **Limitar a 1–2 achados por categoria.** Se C2 tem 16 rotas sem checagem de identidade,
  são 16 no relatório. Imprimir 2 e calar 14 é o mesmo *silêncio virando aprovação* que a
  regra dura do checklist proíbe — pior, com cara de relatório completo.
- **Pular categoria vazia.** Colide com *É proibido omitir uma linha*. Aqui a linha vazia
  **é** informação: diz que a sonda rodou e não achou, e é ela que separa `nenhum problema
  identificado` de `não medido`. As 7 linhas saem sempre.

**No terminal o corte é de atenção, nunca de registro.** No chat: o checklist inteiro
(7 linhas), todos os `CRITICAL` e `HIGH` — se são nove, saem nove —, e dos `MEDIUM`/`LOW`
só o que muda a ordem de correção, agrupado por classe; feche com `cortei N achados
menores — os N estão completos em <caminho>`. O excedente já está escrito no arquivo: a
linha de corte é um ponteiro, não uma promessa.

**Agrupar não é cortar, e é o que de fato desinfla.** Vinte hits da mesma classe viram
**um** bloco com a contagem e 2–3 representantes `arquivo:linha`, não vinte blocos quase
iguais. A contagem continua completa; o que sai é a repetição.

E o motivo de o cap ser a ferramenta errada aqui está medido logo acima: **36% de
precisão**. O que infla relatório de scanner não é excesso de achado verdadeiro, é falso
positivo. Teto de contagem sobre uma lista majoritariamente ruidosa não devolve sinal —
sorteia qual dos achados reais sobrevive. Quem desinfla é triagem: abrir o `arquivo:linha`
antes de citar, e olhar o destino do valor, não a primitiva.

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

**Modo direto.** Se a pessoa pedir ("modo direto", "sem explicação") ou o guia da casa
disser que o padrão dela é o direto, os blocos 2 e 3 saem sem "O conceito" e "Por que
aconteceu". O checklist de 7 linhas, as contagens e o disclaimer não mudam em modo nenhum.

## Quer ir mais fundo?

Esta skill é leve e read-only, ótima pra aprender e pegar o grosso. Pra uma suíte completa de SAST
(mais ferramentas tipo Trivy pra IaC, baseline pra CI travar só em achado NOVO, provisão verificada
de binários), veja o **csreview** em [`docs/seguranca.md`](https://github.com/VAMOO-AI/claude-kit-mentorados/blob/main/docs/seguranca.md).
