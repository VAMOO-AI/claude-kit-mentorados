---
name: ambientes-clientes
description: Use when setting up a new client's GitHub + Vercel + Supabase environment, migrating an existing project to a client-owned infrastructure, or troubleshooting deploy failures related to commit author / team membership / Vercel Pro plan rules. Triggers on phrases like "setup cliente", "novo cliente", "migrar repo cliente", "vercel não deploya", "git author blocked", "deploy bloqueado", "infra cliente própria", "ambientes-clientes".
---

# Ambientes de Clientes — <sua-org>

Padrão definitivo pra entregar projetos a clientes que tem (ou querem ter) infra própria, **sem custo extra de seat-per-dev**, mantendo o dev (você) com acesso operacional completo.

> Origem: aprendido na guerra durante migração cliente-exemplo/projeto-exemplo em maio/2026. Toda dor está documentada aqui pra próximo cliente seguir o caminho seco.

---

## Cenário-alvo

- Cliente é dono de: GitHub org, conta Vercel, projeto Supabase
- Você (o dev / sua org) opera sem virar Member pago
- Custo extra mensal: **$0**
- Auto-deploy via push em main funcionando

## Os 3 caminhos possíveis

| | A: Pagar Member | B: Actions+Token (RECOMENDADO) | C: CLI manual |
|--|---|---|---|
| Custo/mês | $20/seat | $0 | $0 |
| Auto-deploy push | ✅ | ✅ | ❌ |
| Setup | trivial | médio | trivial |
| Solo-dev OK | sim | sim | sim |
| Múltiplos devs | $20 cada | só quem tem token | qualquer com token |

**Default: B.** A só quando cliente exigir auditoria fina, time grande, ou já tem orçamento. C só quando cliente tem ≤2 deploys/semana.

---

## Setup limpo de cliente NOVO (do zero)

### Etapa 1 — GitHub
Cliente faz:
1. Cria GitHub org **Free plan** (`<cliente>-projetos` ou similar)
2. Cria repo privado dentro da org
3. Convida `<seu-usuario-github>` como **Owner** ou **Member** (Free org → ilimitado, $0)

⚠️ **Não use** GitHub Team Plan no cliente — desnecessário. Org Free + repo privado já cobre tudo, exceto branch protection privada (resolvido client-side abaixo).

### Etapa 2 — Vercel
Cliente faz:
1. Cria conta Vercel Pro com email dedicado (ex: `automacoes<cliente>@gmail.com`)
2. Cria team
3. Cria projeto Vercel apontando pro repo GitHub

⚠️ **Não convide você (você, o dev) como Member.** Vai cobrar $20/mês. Você opera via token (Etapa 5).

### Etapa 3 — Supabase
Cliente faz:
1. Cria projeto Supabase (free ou pro, conforme uso)
2. Convida você como Member (Supabase **convites são free** em todos os planos)

### Etapa 4 — Conectar Git no Vercel via dashboard

Cliente, **logado como dono do team Vercel**:
1. Settings → Git → Connect GitHub Repository
2. Autoriza Vercel GitHub App pra acessar a org do cliente:
   - https://github.com/apps/vercel/installations/new
   - Selecionar org do cliente
   - Repo access: "Only select repositories" → o repo do projeto
3. Volta no Vercel e seleciona o repo

### Etapa 5 — Vercel Access Token (você)

Cliente gera token e te passa via canal seguro (1Password idealmente):
1. Logado como dono Vercel: https://vercel.com/account/settings/tokens
2. Create Token:
   - Name: `github-actions-<projeto>`
   - **Scope: o team específico** (NÃO "Full Account")
   - Expiration: 1 ano ou Never
3. Copia (só aparece 1x)

### Etapa 6 — DESCONECTA o Git no Vercel

⚠️ Esse passo é crítico. Cliente faz:
1. https://vercel.com/<team>/<projeto>/settings/git
2. Disconnect

Por quê: o Vercel Pro Plan **bloqueia auto-deploys via Git push** quando o commit author não é Member do team (`commit author does not have contributing access`). Não tem toggle. É a regra do plano. A solução é deployar via **GitHub Actions sob identidade do bot**, fora dessa regra.

### Etapa 7 — GitHub Actions Workflow

No repo do projeto, cria `.github/workflows/vercel-deploy.yml` com o template abaixo (seção Templates).

### Etapa 8 — GitHub Actions Secrets

Em `https://github.com/<org>/<repo>/settings/secrets/actions`, adicionar:
- `VERCEL_TOKEN` — token gerado na Etapa 5
- `VERCEL_ORG_ID` — pega via `cat .vercel/project.json` (campo `orgId`)
- `VERCEL_PROJECT_ID` — campo `projectId` do mesmo arquivo

Pra pegar os IDs antes de desconectar o Git:
```bash
vercel link --yes
cat .vercel/project.json
```

### Etapa 9 — Testar pipeline

```bash
git checkout -b test/pipeline
git commit --allow-empty -m "test: pipeline"
git push -u origin test/pipeline
gh pr create --title "test: pipeline" --body "validacao deploy"
# Workflow deve rodar preview e comentar URL no PR
gh pr merge --squash --delete-branch --admin
# Workflow deve rodar production deploy e sair Ready
```

---

## Setup quando MIGRA repo de <sua-org> pra cliente

Adicione antes da Etapa 1:

### Etapa 0 — Preparar migração

```bash
# Backup mirror (mantém 2-3 semanas)
mkdir -p ~/backups/transfer-<projeto>-$(date +%Y%m%d-%H%M%S)
cd ~/backups/transfer-<projeto>-*
git clone --mirror https://github.com/<sua-org>/<repo>.git

# Auditoria de refs no codigo
cd /caminho/do/projeto
grep -rn "<sua-org>/<repo>" --exclude-dir=node_modules --exclude-dir=.git
grep -rn "<slug-da-org>" -i --exclude-dir=node_modules --exclude-dir=.git

# Limpar branches stale (se houver)
git fetch --all --prune
for b in <branches stale>; do
  git log --oneline origin/main..origin/$b | head -5  # se vazio = safe deletar
done
```

### Etapa 0.5 — Transfer GitHub (UI)

Não tem como via API/CLI:
1. https://github.com/<sua-org>/<repo>/settings → Danger Zone → Transfer
2. Owner: `<cliente>-projetos`
3. Confirma com nome do repo

### Etapa 0.6 — Atualizar remote local

```bash
git remote set-url origin https://github.com/<cliente>-projetos/<repo>.git
git fetch --all --prune
```

Worktrees herdam automaticamente.

---

## Templates

### `.github/workflows/vercel-deploy.yml`

```yaml
name: Vercel Deploy

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

concurrency:
  group: vercel-deploy-${{ github.ref }}
  cancel-in-progress: true

env:
  VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
  VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}

jobs:
  deploy-preview:
    name: Deploy Preview
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write  # OBRIGATORIO pro comment step funcionar
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '22'

      - name: Install Vercel CLI
        run: npm install --global vercel@latest

      - name: Pull Vercel Environment
        run: vercel pull --yes --environment=preview --token=${{ secrets.VERCEL_TOKEN }}

      - name: Build
        run: vercel build --token=${{ secrets.VERCEL_TOKEN }}

      - name: Deploy Preview
        id: deploy
        run: |
          URL=$(vercel deploy --prebuilt --token=${{ secrets.VERCEL_TOKEN }})
          echo "url=$URL" >> "$GITHUB_OUTPUT"

      - name: Comment Preview URL on PR
        uses: actions/github-script@v7
        with:
          script: |
            const url = "${{ steps.deploy.outputs.url }}";
            const sha = context.sha.slice(0, 7);
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `🔍 Preview deploy ready at ${url} (commit \`${sha}\`)`
            });

  deploy-production:
    name: Deploy Production
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '22'

      - name: Install Vercel CLI
        run: npm install --global vercel@latest

      - name: Pull Vercel Environment
        run: vercel pull --yes --environment=production --token=${{ secrets.VERCEL_TOKEN }}

      - name: Build
        run: vercel build --prod --token=${{ secrets.VERCEL_TOKEN }}

      - name: Deploy Production
        run: vercel deploy --prebuilt --prod --token=${{ secrets.VERCEL_TOKEN }}
```

### `.git/hooks/pre-push` (anti direct-push em main)

GitHub Free org não tem branch protection em repo privado. Esse hook é o substituto client-side:

```bash
#!/usr/bin/env bash
# Bloqueia push direto em main. Override emergencial: ALLOW_DIRECT_PUSH=1 git push

set -e
PROTECTED_BRANCH="main"

if [ "${ALLOW_DIRECT_PUSH:-0}" = "1" ]; then
  echo "[pre-push] ALLOW_DIRECT_PUSH=1 -> bypass autorizado" >&2
  exit 0
fi

while read -r local_ref local_sha remote_ref remote_sha; do
  if [ "$remote_ref" = "refs/heads/$PROTECTED_BRANCH" ]; then
    cat >&2 <<EOF

❌ PUSH DIRETO EM '$PROTECTED_BRANCH' BLOQUEADO

Caminho recomendado:
  git checkout -b feat/<nome>
  git push -u origin feat/<nome>
  gh pr create
  gh pr merge --squash --delete-branch

Override (apenas hotfix critico):
  ALLOW_DIRECT_PUSH=1 git push origin $PROTECTED_BRANCH

EOF
    exit 1
  fi
done

exit 0
```

Instalar:
```bash
chmod +x .git/hooks/pre-push
```

### `.gitignore` recomendado (entries pra todo projeto)

```gitignore
# Claude Code tooling (local config + worktrees)
.claude/launch.json
.claude/settings.local.json
.claude/worktrees/

# Vercel CLI link metadata (per-machine)
.vercel
.env*.local
```

Se `.claude/agents/`, `.claude/commands/`, `.claude/skills/` forem compartilhados no time, NÃO ignore esses subdirs — apenas os locais acima.

---

## Pitfalls conhecidos (não cair de novo)

### 1) Vercel auto-adiciona Member quando você loga com email pessoal
- **Sintoma:** clicar "Redeploy" no dashboard Vercel logado como sua conta pessoal cria seat $20/mês prorated
- **Causa:** Collaboration setting padrão "auto-approve new committers"
- **Prevenção:**
  - **Sempre** logar dashboard com a conta dedicada do cliente (`automacoes<cliente>@gmail.com`)
  - Mudar Collaboration setting pra "manual approval" em https://vercel.com/account/settings#collaboration-settings
- **Remediar:** se já aconteceu, remover Member via API ou dashboard pra parar cobrança prorated:
  ```bash
  curl -X DELETE \
    "https://api.vercel.com/v1/teams/<TEAM_ID>/members/<USER_ID>" \
    -H "Authorization: Bearer $TOKEN"
  ```

### 2) "The Deployment was blocked because the commit author does not have contributing access"
- **Não é toggle.** É regra do Pro Plan: commit author tem que ser Member do team.
- **Não confundir** com:
  - "Git Fork Protection" (proteção contra forks externos — não resolve esse erro)
  - "Require Verified Commits" (sobre GPG signing — não relacionado)
  - "Build Logs and Source Protection" (proteção de logs — não relacionado)
- **Solução:** caminho B (Actions+Token) — deploys passam por GitHub Actions, fora da regra.

### 3) Squash merge via `gh pr merge --squash` sobrescreve commit author
- **Sintoma:** commit autorado com email do cliente vira commit autorado com sua identidade GitHub
- **Causa:** GitHub squash merge usa identidade da conta GitHub que chama o merge, não o author original
- **Mitigação se precisar preservar author:** usar `gh pr merge --rebase` ou merge via git CLI direto

### 4) `vercel git connect` falha mesmo com GitHub App instalado
- **Causa:** OAuth do CLI da Vercel está linkado a uma identidade GitHub que não tem acesso à org do cliente
- **Solução:** conectar via Dashboard (UI) em vez de CLI: Project → Settings → Git → Connect Git Repository

### 5) Worktrees compartilham `.git` mas branches não podem coexistir checkados em 2 lugares
- Se o main clone está em branch X e a worktree também tenta X → erro `branch already used by worktree`
- **Solução:** sempre cd explícito ou `git -C <path>` ao operar em outra working tree

### 6) Vercel CLI cwd reseta entre comandos no harness Claude Code
- **Sintoma:** `cd X && command1` funciona; `command2` (sem cd) executa em outro cwd
- **Solução:** usar `git -C <path>` e paths absolutos sempre

### 7) Git Author Verification feature da Vercel não existe como toggle
- A doc oficial deixa claro: é parte da definição do Pro Plan, não config opcional
- Doc: https://vercel.com/docs/deployments/troubleshoot-project-collaboration

### 8) Vercel Pull adiciona linhas redundantes ao `.gitignore`
- O `vercel pull` pode adicionar `.env*.local` mesmo já tendo `.env.local` e `.env.*.local`
- Inofensivo. Aceitar e seguir.

### 9) Branch protection paga em GitHub Free privado
- Repos privados em org Free **não têm** branch protection rules
- Solução: pre-push hook (Template acima) + disciplina + sempre PR

### 10) `GITHUB_TOKEN` default não permite postar comment em PR
- **Sintoma:** preview deploy job builda e deploya OK, mas o passo "Comment Preview URL on PR" falha com `403 "Resource not accessible by integration"`
- **Causa:** repos novos têm `GITHUB_TOKEN` com permissões read-only por default
- **Solução:** adicionar `permissions:` block no job (já incluído no template acima)
- **Alternativa global:** Settings → Actions → General → Workflow permissions → "Read and write" — mas é mais permissivo que necessário

### 11) OOM ("JavaScript heap out of memory") no `vercel build`
- **Sintoma:** build no GitHub Actions falha em `Running TypeScript` ou compile do Next, com `FATAL ERROR: Ineffective mark-compacts near heap limit Allocation failed - JavaScript heap out of memory`
- **Causa:** default do Node são ~2GB de heap. Next.js 16 + Turbopack, Next + Prisma, ou repos grandes estouram facilmente. O runner `ubuntu-latest` do GitHub tem 16GB de RAM, mas o subprocess do Node não usa por default.
- **Solução:** adicionar no `env` (block-level ou job-level) do workflow:
  ```yaml
  env:
    NODE_OPTIONS: --max-old-space-size=6144
  ```
  Block-level garante que tanto `vercel build` quanto o subprocess `npm run build` herdem o valor.
- **Quando aplicar preventivo:** Next.js 14+, projetos com Prisma, monorepos, ou qualquer repo onde o CI antigo (`ci.yml`) já usa `NODE_OPTIONS` no tsc step.

### 12) Branch default `master` (não `main`)
- Alguns repos antigos do time ainda usam `master` como branch default (ex: `projeto-gestao`)
- **Antes de copiar o template do workflow:** rodar `git branch --show-current` ou `gh repo view --json defaultBranchRef` pra confirmar
- **Trocar em 4 lugares:** `on.push.branches`, `on.pull_request.branches`, condição do job `deploy-production` (`refs/heads/master`), pre-push hook (`PROTECTED_BRANCH="master"`)
- **gh pr create:** passar `--base master` explicitamente, senão tenta criar contra `main` e falha

---

## Checklist final de entrega ao cliente

Quando fechar setup, valide:

- [ ] Repo Git em `<cliente>-projetos/<repo>` (privado, owner do cliente)
- [ ] `git remote -v` aponta pro novo path
- [ ] `.gitignore` cobre `.claude/*` locais e `.vercel`
- [ ] `.git/hooks/pre-push` instalado e executável
- [ ] `.github/workflows/vercel-deploy.yml` mergeado em main
- [ ] 3 secrets no GitHub Actions: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`
- [ ] Outros secrets (Supabase etc) também no GitHub Actions
- [ ] Vercel Git connection **DESCONECTADA**
- [ ] Vercel Collaboration setting em "manual approval"
- [ ] Team Vercel: 1 Member apenas (cliente OWNER)
- [ ] Push de teste em main → workflow rodou → deploy production READY
- [ ] PR de teste → workflow rodou → preview URL comentada no PR
- [ ] Custom domain do cliente respondendo HTTP 200
- [ ] `.env.local` populado via `vercel env pull --token=$VERCEL_TOKEN` (após link manual com `vercel link`)

---

## Comandos úteis cheat-sheet

```bash
# Pegar TOKEN da CLI atual (debug only)
grep -A1 '"token"' ~/Library/Application\ Support/com.vercel.cli/auth.json | grep -oE '"[a-zA-Z0-9_]{20,}"' | head -1

# Listar membros de um team
TOKEN=<your_token>
curl -s "https://api.vercel.com/v2/teams/<TEAM_ID>/members" -H "Authorization: Bearer $TOKEN" | jq .

# Inspect projeto Vercel (Git connection, framework, etc)
curl -s "https://api.vercel.com/v9/projects/<PROJ_ID>?teamId=<TEAM_ID>" -H "Authorization: Bearer $TOKEN" | jq '.link, .framework, .nodeVersion'

# Inspecionar erro de deploy específico
curl -s "https://api.vercel.com/v6/deployments?teamId=<TEAM_ID>&projectId=<PROJ_ID>&limit=3" -H "Authorization: Bearer $TOKEN" | jq '.deployments[] | {state, errorMessage}'

# Disparar deploy manual prod (token-based, não vira Member)
vercel deploy --prod --token=$VERCEL_TOKEN

# Empty commit pra disparar workflow (debug pipeline)
git checkout -b test/pipeline
git commit --allow-empty -m "test"
git push -u origin test/pipeline
gh pr create --title "test" --body "trigger workflow"
gh pr merge --squash --delete-branch --admin
```

---

## Referências

- [Vercel Pro Plan](https://vercel.com/docs/plans/pro-plan)
- [Vercel troubleshoot project collaboration](https://vercel.com/docs/deployments/troubleshoot-project-collaboration)
- [GitHub Actions + Vercel official guide](https://vercel.com/guides/how-can-i-use-github-actions-with-vercel)
- [GitHub Free orgs feature matrix](https://docs.github.com/en/get-started/learning-about-github/githubs-plans)

---

## Histórico

- **v1 (2026-05-08)** — Padrão definido durante migração cliente-exemplo/projeto-exemplo. Documentado o caminho B (Actions+Token) como recomendado, com 9 pitfalls reais encontrados.
- **v2 (2026-05-21)** — Aplicado em `projeto-mecanica` (cliente-mecanica) e `projeto-gestao` (cliente-gestao). Adicionados 2 pitfalls: OOM em Next 16/Prisma exige `NODE_OPTIONS=--max-old-space-size=6144`; branch default `master` em repos antigos requer ajuste em 4 lugares do template.
