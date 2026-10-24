# C1 — Injeção: os sete grupos

> Referência da skill `secscan`, Fase 3. Leia ao avaliar C1.

Varredura do **repositório inteiro**: SQL dinâmico (inclusive o das functions do servidor,
que nenhum teste de front carrega), command injection, path traversal, injeção de template
e de expressão, SSRF, e injeção em log e em filtro. O semgrep da Fase 0.5 não corrobora
código de app neste stack, então **todo achado de C1 é `heuristic`**, e a linha C1 do
checklist diz isso em vez de deixar o leitor supor que o silêncio do semgrep é ausência de
problema. Um "C1 limpo" vale menos que um "C2 limpo": não infle severidade para compensar.

**C1.1 — SQL dinâmico.** Ache o driver e a escotilha raw dele:
`grep -rniE "knex|prisma|sequelize|psycopg|sqlalchemy|database/sql|pg\.Client"`. ORM
parametrizado é seguro por padrão; o que interessa é `$queryRawUnsafe`, `knex.raw`,
`session.execute(text(f"..."))`, `db.Query("..."+x)`. Regra do veredito: valor do usuário só
entra como **parâmetro** (`$1` / `?` / `:name`); **identificador** (tabela, coluna,
`ORDER BY`, direção) nunca vem do request: ou é lista fechada, ou é finding.

```bash
# SQL montado por template/concatenação, nas três camadas (front, functions, scripts)
grep -rniE '(select |insert into |update .+ set |delete from |where |order by ).*(\$\{|" ?\+|'"'"' ?\+)' \
  src/ supabase/functions/ scripts/ --include='*.ts' --include='*.tsx' --include='*.cjs' 2>/dev/null | grep -v '\.test\.'
# o parâmetro que VIRA sql: helpers de execução arbitrária
grep -rn "rpc('exec_sql\|rpc('execute_sql\|rpc('run_sql" src/ scripts/ supabase/functions/ 2>/dev/null
# rpc com nome de função dinâmico (o nome também é identificador)
grep -rn '\.rpc(`' src/ supabase/functions/ --include='*.ts' --include='*.tsx' 2>/dev/null
```

**C1.2 — Command injection.** A família que executa string em shell: `exec`/`execSync`,
`spawn` com `shell: true`, `os.system`, `subprocess.run(..., shell=True)`, `sh -c`. O
veredito não é "usa exec", é **"o valor vem de fora"**: request, arquivo, `.env`, saída de
outro comando. O fix é sempre a forma com lista de argumentos: `execFileSync(cmd, [args])`,
`spawn(cmd, args)` sem shell, `subprocess.run([...])`. Fonte de fora que quase ninguém
trata como entrada: **o próprio git**. Ele aceita criar branch chamada
`x$(touch${IFS}/tmp/x)`, e qualquer `execSync(\`git ... ${branch}\`)` executa o subshell
(`${IFS}` derruba a defesa de "não tem espaço"). Vale para nome de branch, tag, remote,
arquivo e mensagem de commit em hook.

```bash
grep -rnE 'execSync|exec\(|spawnSync|spawn\(|child_process|shell: ?true|os\.system|subprocess\.(run|call|Popen)' \
  scripts/ .github/ .husky/ supabase/functions/ --include='*.cjs' --include='*.js' --include='*.mjs' --include='*.ts' --include='*.py' --include='*.sh' 2>/dev/null
# só os que interpolam (o subconjunto que interessa)
grep -rnE '(execSync|exec)\(`[^`]*\$\{' scripts/ .github/ --include='*.cjs' --include='*.js' --include='*.mjs' 2>/dev/null
```

**C1.3 — XSS, inclusive fora do framework.** O sink de framework (`dangerouslySetInnerHTML`,
`v-html`, `[innerHTML]`, `|safe`) todo scanner acha. O que ninguém varre é **onde a
aplicação escreve HTML fora do framework**: template de e-mail, PDF gerado, mensagem de
bot, corpo de webhook. O React protege a página; nada disso passa por ele.

```bash
grep -rn 'dangerouslySetInnerHTML\|innerHTML\|v-html' src/ 2>/dev/null | grep -v '__tests__'
# HTML montado por template string nas functions (e-mail). Estes greps localizam o ARQUIVO,
# nunca a interpolação sem escape: a leitura é sua. Ancorar só em DOCTYPE perde o template
# montado em fragmento (`<div><strong>${nome}</strong>`), que é o formato mais comum.
grep -rn '<!DOCTYPE html\|<html lang' supabase/functions --include='*.ts' 2>/dev/null
grep -rnE 'return `<[a-z]' supabase/functions --include='*.ts' 2>/dev/null
# quantas cópias de escape existem: cada cópia é uma que não recebe a correção do módulo central
grep -rn 'function escapeHtml\|const escapeHtml' src/ supabase/functions --include='*.ts' --include='*.tsx' 2>/dev/null
```

**C1.4 — Path traversal e chave de Storage.** `readFile`, `createReadStream`, `path.join`,
`sendFile`, `open()` recebendo valor do request. `..%2f` e `..\` passam por validação
ingênua; a defesa é resolver e conferir o prefixo (`path.resolve` + `startsWith(base)`), não
lista de `..` proibido. No Supabase o equivalente é a **chave do objeto no Storage**: quando
o tenant vem do primeiro segmento do caminho, caminho montado com entrada do cliente sem
prefixo derivado no servidor quebra o isolamento, sem `..` nenhum: basta o id de outro
tenant. Toda montagem de chave: `grep -rn 'storage\.from(' src/ supabase/functions --include='*.ts' --include='*.tsx'`.

**C1.5 — Injeção de template e de expressão.** Duas formas. (1) Motor de template
**compilando** string do usuário: `Handlebars.compile(input)`, `ejs.render(input)`,
`Template(input)` do Jinja. Compilar template é executar código; interpolar dado não é.
(2) Expressão de plataforma low-code avaliada sobre payload cru: no n8n, **Code Node**
(`jsCode`) e expressão `{{ }}`. Payload de webhook dentro de `{{ }}` é avaliado, e
`{{ ... }}` montando **JSON por concatenação** quebra a estrutura antes de virar injeção.

```bash
# Descubra onde os fluxos moram: glob fixo em pasta inexistente vira "não aplicável" sem ninguém olhar.
N8N_DIR=$(for d in n8n n8n_workflows workflows; do [ -d "$d" ] && echo "$d" && break; done)
[ -z "$N8N_DIR" ] && echo "nenhum diretório de fluxo n8n → C1.5 é 'não aplicável (sem n8n)'"
[ -n "$N8N_DIR" ] && grep -rn '"jsCode"' "$N8N_DIR" --include='*.json' | wc -l
[ -n "$N8N_DIR" ] && grep -roh '{{[^}]*\$json[^}]*}}' "$N8N_DIR" --include='*.json' | sort -u
grep -rnE 'Handlebars\.compile|ejs\.render|new Function|\bTemplate\(' src/ supabase/functions/ --include='*.ts' --include='*.tsx' 2>/dev/null
```

O `\b` antes de `Template(` não é decoração: sem ele o padrão casa `renderMessageTemplate(`,
`getMessageTemplate(` e devolve dezenas de hits de ruído. Nenhum comando separa valor do
servidor (INFO) de `$json` vindo de webhook (HIGH): é leitura, não reporte toda expressão
como HIGH.

**C1.6 — SSRF.** `fetch`, `axios`, `requests.get` ou `curl` com URL vinda do request:
webhook configurável, importador "cole a URL", proxy de imagem. Lista de hosts permitidos
**antes** do fetch é a defesa; bloquear `169.254.169.254` não é (DNS rebinding, redirect).
Confira `redirect: 'follow'`: permitir a primeira URL não cobre o destino do 302. Function
do servidor é o lugar, porque roda com os segredos no ambiente.

```bash
grep -rnE 'fetch\((url|targetUrl|body\.|payload\.|[a-zA-Z_]+\.url)' supabase/functions/ src/ --include='*.ts' --include='*.tsx' 2>/dev/null
grep -rn "redirect: *'follow'" supabase/functions/ --include='*.ts' 2>/dev/null
# a forma indireta (`const alvo = payload.webhook; fetch(alvo)`) escapa do primeiro:
grep -rnB3 'fetch(' supabase/functions/ --include='*.ts' 2>/dev/null | grep -E '(body|payload)\.'
```

Os três são localizadores: quem decide é a leitura de onde a variável nasce.

**C1.7 — Injeção em log e em filtro.** (1) Log: valor do usuário com `\n` forja uma linha de
log inteira e envenena alerta; log estruturado (JSON) elimina a classe. (2) Filtro montado
por string: `?col=eq.` do PostgREST, `$where` do Mongo. No supabase-js, `.or()` recebe
**string com gramática própria** (vírgula, `.` e parênteses são separadores): valor do
request com vírgula não vira SQLi, vira reescrita do filtro, com linha de outro tenant no
resultado.

```bash
# filtro: template literal E concatenação (só a crase perde `.or('x.eq.' + termo)`)
grep -rnE "\.(or|filter|like|ilike)\((\`|'[^']*' *\+|\"[^\"]*\" *\+)" src/ supabase/functions --include='*.ts' --include='*.tsx' 2>/dev/null
grep -rnE 'console\.(log|warn|error)\(.*\$\{|logger\.(info|warn|error)\(`' src/ supabase/functions --include='*.ts' --include='*.tsx' 2>/dev/null
```
