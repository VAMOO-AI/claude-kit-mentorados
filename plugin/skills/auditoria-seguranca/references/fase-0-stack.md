# auditoria-seguranca — Fase 0, detectar a stack

Lido antes do primeiro comando da auditoria.

## Fase 0 — Detectar a stack (antes de qualquer grep)

Sem isto, a auditoria vira busca por `dangerouslySetInnerHTML` num projeto Vue.

```bash
ls package.json requirements.txt pyproject.toml go.mod Gemfile composer.json Cargo.toml 2>/dev/null
[ -f package.json ] && cat package.json | head -60
ls -d supabase/ prisma/ drizzle/ migrations/ app/ pages/ src/ api/ 2>/dev/null
ls docker-compose*.yml docker-compose*.yaml compose.yaml compose.yml Dockerfile* .github/workflows/ helm/ terraform/ vercel.json 2>/dev/null
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

**Anote também o que você tem para rodar, e o que não tem.** Cada ferramenta vira
uma linha em `ferramentas[]` com estado `executado`, `nao_aplicavel`,
`nao_instalado` ou `falhou`:

```bash
for t in gitleaks semgrep trivy npm pip-audit; do
  printf '%-12s %s\n' "$t" "$(command -v $t >/dev/null && $t --version 2>&1 | head -1 || echo AUSENTE)"
done
```

`gitleaks` ausente não é detalhe de máquina: é a categoria A4 sem a varredura de
histórico. O relatório imprime um aviso de superfície não medida para cada
ferramenta que não rodou — sem isso, quem lê entende ausência de achado como
ausência de problema, e a auditoria vira um carimbo.

A pergunta que ordena a A1 inteira: **qual é o mecanismo de isolamento deste
projeto?** Descubra antes de procurar o furo — "não tem RLS" é achado só onde
RLS era o mecanismo escolhido. Onde o isolamento é filtro manual, o achado é a
query que esqueceu o filtro; onde não existe mecanismo nenhum, o achado é
**estrutural** e vale mais que qualquer linha individual.

**Existe auditoria anterior?** Uma rodada acha metade do que rodadas repetidas
acham (medição da Cloudflare no harness delas, e bate com a nossa experiência).
Se `docs/security-audit/findings.json` já existe no repo, ele é insumo, não
histórico:

```bash
git log -1 --format='%h %ad' --date=short -- docs/security-audit/findings.json
python3 -c "import json;[print(a['id'],a.get('status','aberto'),a['arquivo'],a.get('linhas','')) for a in json.load(open('docs/security-audit/findings.json'))['achados']]"
```

Cada achado antigo recebe um destino **relendo o código atual**, não o texto
antigo: `corrigido` (o fix está lá, cite a linha), `aberto` (carregue com
`desde`), `falso_positivo` (mantenha com o `motivo` de quem refutou). Um
`falso_positivo` antigo suprime só aquela alegação exata — se o código mudou,
vira trabalho de novo. Preencha `auditoria_anterior` com a contagem, e a
cobertura declara "N da auditoria anterior reverificados". Sem arquivo anterior,
a capa diz que é a primeira: uma rodada não esgota o alvo.

**As coisas óbvias, antes de qualquer categoria** (cinco minutos, e é onde o
achado barato mora porque todo mundo supõe que outro conferiu):

```bash
grep -rnE "(TODO|FIXME|HACK|XXX).*(auth|permiss|valid|tenant|secur|token)" --include='*.ts' --include='*.tsx' --include='*.py' --include='*.sql' . | grep -v node_modules
grep -rnE "(redirect|returnTo|return_url|next|callback|goto|continue)\b.*(req\.(query|body)|searchParams|params)" --include='*.ts' --include='*.tsx' . | grep -v node_modules   # open redirect
git log --oneline -i --grep='revert' --grep='auth' --grep='rls' --grep='permiss' --all | head -20   # fix de segurança revertido
ls e2e/ src/**/__tests__/ 2>/dev/null   # o que os testes NÃO testam é a lista de lugares sem rede
```

O `git log` é o que separa esta lista de um checklist: check de auth comentado,
policy dropada "temporariamente" e segredo commitado-e-removido só aparecem no
histórico, e o histórico é o único lugar onde ninguém procura.
