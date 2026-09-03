---
name: auditoria-seguranca
description: >-
  Auditoria de segurança em 5 categorias (isolamento de inquilino, permissão
  decidida no navegador, IDOR, chaves expostas, XSS) com entregável: PDF em
  pt-BR dentro do repo auditado + issues de GitHub prontas para colar. Detecta a
  stack antes, então serve repo que não é Supabase. Use em "auditoria de
  segurança", "relatório de segurança", "auditoria em PDF", "achou IDOR?",
  "revisa esse código atrás de falhas". Não é o secscan (varredura em Markdown
  fora do repo): este é o pacote para outra pessoa ler e agir.
---

# auditoria-seguranca — 5 categorias, PDF e issues

Auditoria **estática e read-only sobre o código**, empacotada como entregável:
um PDF em pt-BR e uma lista de issues que outra pessoa consegue executar sem ter
lido o código. O valor não está nos greps — está em **percorrer tudo** (não
amostra), **registrar o que está correto** e **entregar num formato que sobrevive
à conversa**.

## Fronteira — qual skill responde o quê

| Skill | Responde | Entrega |
|---|---|---|
| **`auditoria-seguranca`** (esta) | "Quais das 5 falhas clássicas este código tem, e o que faço com isso?" | PDF + issues, **dentro** do repo |
| `secscan` | "Existe `service_role` em `src/`? Esse `eval` é explorável?" | Markdown + SARIF, **fora** do repo |
| `baseline` | "A plataforma está apta a produção?" | contrato em `.context/docs/baseline.md` (ou o doc de contrato do seu projeto) |

**Não reimplemente as sondas do secscan aqui.** Quando a stack for
Supabase/Next/n8n, as buscas de cada categoria já estão calibradas lá — este
arquivo aponta para a fase certa em cada seção. Copiar grep entre as duas skills
é como as duas divergem.

## Iron rules

- **Read-only no código auditado.** A única escrita permitida é `docs/security-audit/`
  (relatório, script gerador, `findings.json`). Isso é uma exceção **declarada** —
  o `secscan` proíbe escrever no working tree alheio; aqui o PDF e o gerador são o
  produto, e produto vai versionado. Ainda assim: **branch própria**, nunca
  commit direto na branch de trabalho de outra pessoa.
- **Achado só existe com `arquivo:linha` aberto e lido.** Grep localiza; quem
  decide é a leitura. Trecho de código no relatório é copiado do arquivo, não
  reescrito de memória.
- **Percorra tudo nas categorias A1 e A3, e publique DUAS contagens:** quantos
  handlers foram **lidos integralmente** e quantos foram **triados por padrão**
  (grep de gate). As duas somadas têm que dar o total; a primeira sozinha é a
  que sustenta "auditado". "Amostrei os principais" reprova a auditoria: IDOR
  mora justamente na rota que ninguém lembra.
- **Grep erra nos dois sentidos, e o falso negativo é o caro.** Na auditoria de
  01/09/2026 a primeira varredura acusou 26 endpoints "sem auth", a segunda 10,
  e a leitura mostrou 0 — o projeto usava helpers (`isAuthorized`,
  `x-automation-key`) que o padrão não previa. Na mesma sessão, um detector de
  segredo com fallback vazio acusou 20 arquivos e eram 17: procurava
  `!CRON_SECRET` e não casava com `!MENTORIA_CRON_SECRET`. Antes de publicar
  qualquer contagem, abra alguns dos que o grep **liberou** — é o lado que
  ninguém confere.
- **O que está correto também é resultado.** Cada categoria produz pelo menos
  uma linha de "verificado e está certo, com evidência". Relatório só com
  achados não prova cobertura nenhuma.
- **Categoria que não se aplica sai escrita como não aplicável, com motivo.**
  Nunca force achado para preencher seção; nunca deixe a seção em silêncio, que
  o leitor interpreta como aprovação.
- **Zero achado ≠ seguro.** O PDF diz o que foi medido e como.

## Fase 0 — Detectar a stack (antes de qualquer grep)

Sem isto, a auditoria vira busca por `dangerouslySetInnerHTML` num projeto Vue.

```bash
ls package.json requirements.txt pyproject.toml go.mod Gemfile composer.json Cargo.toml 2>/dev/null
[ -f package.json ] && cat package.json | head -60
ls -d supabase/ prisma/ drizzle/ migrations/ app/ pages/ src/ api/ 2>/dev/null
ls docker-compose*.yml Dockerfile* .github/workflows/ helm/ terraform/ vercel.json 2>/dev/null
```

Preencha, e **escreva na nota metodológica do PDF**:

| Dimensão | O que descobrir | Por que muda a auditoria |
|---|---|---|
| Linguagem / framework | Next, Fastify, Express, Django, Rails, Laravel, Go | define onde moram os handlers |
| ORM / query builder | Prisma, Drizzle, Supabase JS, SQLAlchemy, ActiveRecord, SQL cru | define como se lê o filtro de tenant |
| Auth | Supabase Auth, JWT próprio, NextAuth, Devise, sessão de servidor | define quem é `req.user` |
| **Mecanismo de isolamento** | RLS, middleware de tenant, filtro manual, nenhum | **é a pergunta central da A1** |
| Frontend | React, Vue, Angular, Svelte, template de servidor, nenhum | define o sink de XSS |
| Deploy | Docker, CI, Helm, Terraform, Vercel | onde os segredos default se escondem |

A pergunta que ordena a A1 inteira: **qual é o mecanismo de isolamento deste
projeto?** Descubra antes de procurar o furo — "não tem RLS" é achado só onde
RLS era o mecanismo escolhido. Onde o isolamento é filtro manual, o achado é a
query que esqueceu o filtro; onde não existe mecanismo nenhum, o achado é
**estrutural** e vale mais que qualquer linha individual.

## A1 — Banco sem tranca (isolamento de inquilino/dono)

Alvo: **toda** query de listagem, busca, agregação, relatório e exportação.
Agregação e exportação são as que mais escapam, porque não devolvem "um
registro" e por isso ninguém pensa nelas como vazamento — e são as que devolvem
o negócio inteiro do concorrente.

- Stack Supabase → as sondas de RLS, `SECURITY DEFINER` sem `search_path`, view
  sem `security_invoker` e policy `PERMISSIVE` duplicada estão no **`secscan`,
  Phase 2**. Use de lá.

**Antes de qualquer policy, pergunte o que a RLS não alcança.** Toda a Phase 2 do
secscan — RLS, policy, `security_invoker`, `SECURITY DEFINER` — só fala de
objetos onde RLS existe. **Materialized view não tem RLS. Nunca.** Não há policy
que a proteja, e o Supabase concede `ALL ON ALL TABLES` no schema `public` por
padrão (`GRANT`s que o `pg_dump` do baseline costuma omitir e alguém restaura
depois). Para tabela isso está certo — a RLS decide a linha. Para MV, o `GRANT`
**é** o acesso, e o PostgREST publica.

```sql
-- MV legível por quem vem do browser. Zero linha aqui, ou é achado.
SELECT c.relname,
       has_table_privilege('anon',          c.oid, 'SELECT') AS anon,
       has_table_privilege('authenticated', c.oid, 'SELECT') AS authenticated
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'm';

-- o ACL cru, que mostra o GRANT amplo que ninguém lembra de ter dado
SELECT relname, relacl::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND relkind IN ('m','v') AND relacl::text LIKE '%anon=%';
```

O mesmo vale para **view que lê de MV**: `security_invoker` faz a coisa certa e
ainda entrega o dado, porque a permissão que ele respeita é justamente a que
está aberta. Provado em 01/09/2026 num projeto real: 180 de 180 tabelas com
RLS, 170 funções `SECURITY DEFINER` sem uma falha — e 904 linhas de 16 clientes
saindo por uma MV, sem login. **A postura de RLS ser impecável não é evidência
sobre a MV; são superfícies diferentes.**

Consulte o **estado vivo**, não a migration. No mesmo repo, o `REVOKE` correto
estava versionado desde maio e um `GRANT ALL` de julho o desfez: ler a migration
dava o assunto como resolvido.
- Stack com ORM → ache toda chamada de leitura e cheque o filtro de tenant:

```bash
grep -rnE "\.(findMany|findFirst|groupBy|aggregate|count|raw)\(|\.query\(|\.select\(|session\.(query|execute)\(" \
  --include='*.ts' --include='*.js' --include='*.py' --include='*.rb' --include='*.go' . \
  | grep -v -e node_modules -e '\.test\.' -e '\.spec\.' -e __tests__
```

Depois, uma a uma: o `where` cita o tenant do **chamador autenticado** (não um
id que veio do request)? Um tenant vindo do body é a mesma falha com outro nome.

Não conclua "está protegido" porque o ORM tem middleware de tenant configurado:
confirme que o middleware cobre `raw`/`$queryRaw`/`groupBy` — quase sempre não
cobre.

## A2 — Permissão definida no navegador

Método: **cruzamento**, não varredura. Liste os gates de papel do frontend,
depois abra o endpoint de cada um.

```bash
# 1. os gates do frontend
grep -rnE "isAdmin|canEdit|hasRole|useRole|role *[=!]==|permissions?\.(includes|has)" \
  --include='*.tsx' --include='*.jsx' --include='*.vue' --include='*.svelte' src/ app/ 2>/dev/null

# 2. o que o servidor exige (compare os dois conjuntos, um por um)
grep -rnE "requireAuth|requireRole|authorize|before_action|@login_required|middleware\(" \
  --include='*.ts' --include='*.js' --include='*.py' --include='*.rb' api/ src/ app/ 2>/dev/null
```

O achado é sempre a diferença: gate de papel no front **sem** verificação
equivalente no handler. A `baseline`, pilar `03-auth.md`, chama isso de
gate **cosmético** e exige que cada um declare sua contrapartida — quando o
projeto for da casa, use o contrato de lá em vez de recomeçar o inventário.

Autenticação não é autorização: `requireAuth` num endpoint de admin é achado,
não proteção.

## A3 — IDOR

**Percorra todos os handlers.** Enumere primeiro, audite depois, e reporte a
razão lidos/total.

```bash
grep -rnE "(app|router|fastify)\.(get|post|put|patch|delete)\(|@(Get|Post|Put|Patch|Delete)\(|def (get|post|put|patch|delete)|path\(" \
  --include='*.ts' --include='*.js' --include='*.py' --include='*.rb' --include='*.go' . \
  | grep -v -e node_modules -e '\.test\.' -e '\.spec\.' | tee /tmp/handlers.txt | wc -l
```

Para cada handler que recebe um id (path, query **ou body**), a pergunta é uma
só: **o objeto é carregado cruzando o id com o dono/tenant do chamador?**

- `findUnique({ where: { id } })` seguido de checagem posterior costuma estar ok;
  `delete/update({ where: { id } })` direto **não tem** checagem posterior possível
  — é o padrão que mais aparece.
- `deleteMany`/`updateMany` com `{ id, tenantId }` e resposta 404 quando
  `count === 0` é o formato certo do fix.
- Id sequencial aumenta severidade (enumerável sem vazamento prévio); UUID
  reduz explorabilidade mas **não** conserta — UUID vaza em log, e-mail, URL
  compartilhada e export.

## A4 — Chaves expostas

Quatro superfícies, e a quarta é a que quase ninguém varre:

```bash
command -v gitleaks && gitleaks detect --no-banner --redact -v   # HEAD + histórico
grep -rnE '\$\{[A-Z_]+:-[^}]+\}' docker-compose*.yml helm/ .github/ scripts/ 2>/dev/null  # defaults
grep -rnE "(api[_-]?key|secret|token|password|passwd|private[_-]key) *[:=] *['\"][^'\"]{8,}" \
  --include='*.yml' --include='*.yaml' --include='*.env*' --include='*.md' . | grep -v node_modules
# 4. o bundle publicado (o segredo que "só existe no servidor" e foi pro browser)
[ -d dist ] || npm run build 2>/dev/null; grep -rEo "(sk-[A-Za-z0-9]{16,}|eyJhbGciOi[A-Za-z0-9._-]{20,}|sbp_[a-z0-9]{20,})" dist/ 2>/dev/null | sort -u
```

**Default público é achado, mesmo com a variável sobrescrita em produção hoje.**
`${JWT_SECRET:-supersecret}` é um segredo real esperando um deploy distraído. O
achado só fecha com **validação de startup** que aborta o boot com o valor
conhecido — a ausência dessa validação é parte do achado, não uma sugestão
extra.

Agrupe os defaults num achado por tema (todos os segredos do compose viram uma
issue só) para não gerar spam.

## A5 — Inputs sem tratamento (XSS)

Frontend, por framework:

```bash
grep -rnE "dangerouslySetInnerHTML|v-html|\[innerHTML\]|innerHTML *=|\{@html|\|safe|html_safe|raw\(" \
  --include='*.tsx' --include='*.jsx' --include='*.vue' --include='*.svelte' --include='*.html' \
  --include='*.erb' --include='*.py' src/ app/ templates/ 2>/dev/null
grep -rnE "href=\{[^}]*(url|link|href)|src=\{[^}]*(url|src)|eval\(|new Function\(" --include='*.tsx' --include='*.jsx' src/ 2>/dev/null
```

Depois: **existe lib de sanitização no projeto** (`dompurify`, `sanitize-html`,
`bleach`, `sanitize`)? Se existe, cada sink encontrado ou passa por ela ou é
achado. Se não existe e há sink, o achado é a ausência.

Backend — o ponto cego real: **onde a aplicação escreve HTML fora do framework**.
Template de e-mail, PDF gerado, mensagem de bot, corpo de webhook. React protege
a página; nada disso passa por React.

```bash
grep -rnE '`[^`]*<(p|div|a|table|strong|h[1-6])[^`]*\$\{' --include='*.ts' --include='*.js' . | grep -v node_modules
```

URL controlada pelo usuário em `href`/`src` é a variante que passa despercebida:
`javascript:` continua executando, e a defesa é allowlist de protocolo.

## Fase 6 — findings.json e o PDF

O relatório é gerado por script, não escrito à mão: os números do resumo e dos
gráficos saem dos mesmos dados da tabela, e não podem discordar.

```bash
mkdir -p docs/security-audit
cp ~/.claude/plugins/*/skills/auditoria-seguranca/scripts/gerar-relatorio.py docs/security-audit/ \
  || cp "$CLAUDE_PLUGIN_ROOT/skills/auditoria-seguranca/scripts/gerar-relatorio.py" docs/security-audit/
# escreva docs/security-audit/findings.json (schema em references/findings-schema.md)
python3 docs/security-audit/gerar-relatorio.py docs/security-audit/findings.json \
  --out docs/security-audit/relatorio-auditoria-seguranca.pdf
```

Sem dependência: stdlib + Chrome/Chromium já instalado (HTML → servidor HTTP
efêmero → `--print-to-pdf`). O servidor não é firula: o rodapé nativo do Chrome
é o único que sabe numerar `3/12`, e ele imprime a URL do documento — abrindo
`file://` o PDF entregue ao cliente carregaria o caminho absoluto da sua máquina.

**Verifique o PDF antes de entregar** (a regra de screenshot vale: no máximo
duas páginas rasterizadas, e só porque aqui o pixel é a evidência):

```bash
pdfinfo docs/security-audit/relatorio-auditoria-seguranca.pdf | head -3
pdftoppm -png -r 68 -f 2 -l 2 docs/security-audit/relatorio-auditoria-seguranca.pdf /tmp/pg
```

Olhe a página do resumo: rótulo de barra cortado, rosca sem legenda e tabela
transbordando são defeitos de entrega, não detalhe.

## Fase 7 — Issues

Cada achado acionável vira uma issue completa (`[Segurança] <falha>`, labels
`security` + severidade, problema, evidência com `arquivo:linha`, impacto,
correção, critérios de aceite verificáveis). O gerador já emite tudo entre
`--- ISSUE n ---` e `--- FIM ISSUE n ---` a partir do `findings.json`.

Critério de aceite bom é executável: *"requisição com id de outro tenant devolve
404"* vale; *"corrigir o IDOR"* não vale. E quando o achado for bug de
comportamento, o critério inclui **o teste falhando no commit anterior ao fix** —
verde sozinho não prova regressão nenhuma.

## Armadilhas

| Sintoma | Causa real |
|---|---|
| Auditoria "limpa" em projeto que nunca foi auditado | Amostrou handlers em vez de percorrer. Conte e publique a razão lidos/total |
| Achado de A1 que o time rebate em 5 minutos | O projeto usa middleware de tenant e você leu a query sem ler o middleware |
| Categoria some do relatório | Stack sem frontend/sem multi-tenant. Isso é "não aplicável **escrito**", nunca seção ausente |
| PDF com número diferente do texto | Alguém editou a tabela à mão. Os números saem só do `findings.json` |
| Issue devolvida como "não reproduz" | Faltou a condição de explorabilidade (flag, config, papel necessário) |
| Segredo "já rotacionado" reaparece | Rotação não reescreve histórico: sem `gitleaks` no histórico você não sabe o que ainda está lá |
