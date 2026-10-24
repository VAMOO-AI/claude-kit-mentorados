# §4 da ship: Vercel / frontend

Use uma única estratégia de deploy, escolhida no 4a. CLI manual é fallback explícito (o projeto
exige, ou o `gitSource` respondeu `error`), nunca um desvio silencioso: deploy manual concorrendo
com o automático dá corrida no alias.

**PR só de doc** (mexe apenas em `.md` / `.context/docs/`, sem `src/`, `index.html`,
`vercel.json`, `public/`) não precisa de deploy.

Os valores (nome da variável do token e o arquivo dela, team id, project id, domínio, sequência
provada) vêm do `.context/docs/deploy.md`. O token entra sempre pelo mesmo `read_var` do 3a de
[supabase-n8n.md](supabase-n8n.md), num `.sh` no scratchpad, nunca por `source`.

## 4a. Escolha da estratégia

Nesta ordem:

1. **A estratégia marcada como oficial no `deploy.md`.** Se é o auto-deploy da integração Git, o
   merge já deployou: o 4a não dispara nada, só confirma que o deployment do SHA da branch padrão
   está em production (não em preview) com `state` `success`, e segue para o 4d:

   ```bash
   gh api 'repos/{owner}/{repo}/deployments?sha=<SHA>&environment=Production' --jq '.[].id'
   gh api 'repos/{owner}/{repo}/deployments/<id>/statuses' --jq '.[0].state'   # success
   ```

   Sem production `success` do SHA, nada de loop em foreground: confira uma vez e deixe
   `Pendente`, ou rode um único `sleep 300; gh api …` (o primeiro comando acima) em `Bash` com
   `run_in_background`. Se ainda não apareceu, `Pendente` no relatório e pergunte; não troque de
   estratégia sozinho.

   Sem `deploy.md`, faça essa mesma conferência antes dos itens 2 e 3: production com `success`
   do SHA quer dizer que a integração Git está deployando, e é só confirmar.
2. **Um workflow do repo faz o deploy:** GitHub Actions (4b). Não é só o `vercel-deploy.yml`:
   contam `vercel deploy`, `vercel --prod`, `npx vercel@<versão> deploy` e a `vercel-action`:

   ```bash
   grep -rlE 'vercel(@[^[:space:]"]*)?"?[[:space:]]+(deploy|--prod)|vercel-action' .github/workflows/
   ```

3. **Sem workflow, com `.vercel/project.json` válido e o token do projeto:** deploy por
   `gitSource` pela API. Ele builda a branch padrão do GitHub, não o disco: num worktree depois de
   squash-merge, um build local publicaria uma árvore que nunca foi mergeada
   (`git rev-parse HEAD^{tree} origin/main^{tree}` dá hashes diferentes). O `.vercel/` é
   gitignored e só existe no clone principal, lido pelo caminho absoluto. Grave num `.sh` no
   scratchpad e rode em background:

   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   CLONE=$(git worktree list --porcelain | sed -n '1s/^worktree //p')   # clone principal
   read_var() { { grep -E "^$2=" "$1" 2>/dev/null || true; } | head -1 | cut -d= -f2- | tr -d "\"'"; }
   VERCEL_TOKEN="$(read_var <arquivo-do-deploy.md> <VAR_DO_TOKEN>)"
   [ -n "$VERCEL_TOKEN" ] || { echo "<VAR_DO_TOKEN> ausente" >&2; exit 1; }
   ORG=$(jq -r .orgId "$CLONE/.vercel/project.json")
   PROJECT=$(jq -r .projectId "$CLONE/.vercel/project.json")
   REF=$(git -C "$CLONE" symbolic-ref --quiet --short refs/remotes/origin/HEAD || true)
   REF=${REF#origin/}
   [ -n "$REF" ] || { echo "sem origin/HEAD: git remote set-head origin --auto" >&2; exit 1; }
   REPO_ID=$(gh api 'repos/{owner}/{repo}' --jq .id)
   R=$(curl -sS -X POST "https://api.vercel.com/v13/deployments?teamId=$ORG" \
     -H "Authorization: Bearer $VERCEL_TOKEN" -H 'Content-Type: application/json' \
     -d "{\"name\":\"<projeto-na-vercel>\",\"project\":\"$PROJECT\",\"target\":\"production\",\"gitSource\":{\"type\":\"github\",\"ref\":\"$REF\",\"repoId\":$REPO_ID}}")
   echo "$R" | jq '{id, url, readyState, error}'
   ID=$(echo "$R" | jq -r '.id // empty'); [ -n "$ID" ] || exit 1   # error → item 4
   npx vercel@59.25.0 inspect "$ID" --wait --timeout 10m --scope "$ORG" --token "$VERCEL_TOKEN" >/dev/null 2>&1 || true
   curl -sS "https://api.vercel.com/v13/deployments/$ID?teamId=$ORG" \
     -H "Authorization: Bearer $VERCEL_TOKEN" | jq '{id, url, readyState, errorMessage, sha: .meta.githubCommitSha}'
   ```

   `project` fixa o projeto pelo id: nome parecido de outro projeto do mesmo team não recebe o
   deploy. O `sha` do GET (`meta.githubCommitSha`) é o commit que foi ao ar: tem de ser o da
   branch padrão, e vai para o relatório. Se o GET ainda disser `QUEUED`/`BUILDING`, não faça
   loop: `Pendente` com o `id`, e confira uma vez depois.
4. **CLI manual** (4c0 + 4c1) quando o projeto exigir, ou quando o `gitSource` responder `error`.

Sem `deploy.md`, workflow nem `.vercel/project.json`, **PARE**. Não derive projeto e scope da
conta que o `vercel whoami` devolve: a sessão local pode ser de outro cliente.

## 4b. GitHub Actions (quando um workflow do repo faz o deploy)

O runner faz checkout do SHA exato e autentica na Vercel com os secrets do repositório: nada sujo
do worktree vai junto, e o author do commit não precisa ser membro do team. Depois do merge, ache
o run do SHA da branch padrão:

```bash
git fetch origin <branch padrão>
git rev-parse origin/<branch padrão>      # o DEPLOY_SHA
gh run list --workflow <arquivo do workflow> --branch <branch padrão> --commit <DEPLOY_SHA> \
  --event push --limit 1 --json databaseId,status,conclusion,headSha,url
```

Confirme que `headSha` é o `DEPLOY_SHA`. Cada chamada do Bash começa sem as variáveis da anterior:
os valores vão por extenso. Espere em background, **só o workflow de deploy** (no CI do PR é o
`gh pr checks --watch --fail-fast` do 2b):

```bash
gh run watch <RUN_ID> --exit-status > /tmp/deploy-<RUN_ID>.log 2>&1
```

Se o projeto documentar `workflow_dispatch` e o evento automático não existir para o SHA,
recupere no mesmo workflow: `gh workflow run <arquivo> --ref <branch padrão>`, ache o run com
`--event workflow_dispatch --commit <DEPLOY_SHA>` e espere do mesmo jeito. Run vermelho pede o log
e a causa; não troque para outro projeto ou token.

### Deploy por `workflow_run`: CI vermelho = produção parada, em silêncio

Repo cujo deploy dispara por `workflow_run` do CI só deploya com
`github.event.workflow_run.conclusion == 'success'`. Quando o CI falha, o job não roda e o run
inteiro aparece como **`skipped` cinza**, não vermelho. A `main` fica à frente do que está no ar e
nada chama atenção. Um teste instável derruba o deploy de produção.

Não pare no "PR mergeado":

```bash
gh run list --workflow "<deploy>" --branch main --limit 3 --json status,conclusion,displayTitle
```

`skipped` aqui quer dizer que **não deployou**. Rerun do CI faz o `workflow_run` disparar de novo
quando fecha verde; ou publique direto com `gh workflow run "<deploy>" --ref main`.

### O log da falha some depois do rerun

`gh run view <id> --log-failed` lê a tentativa **mais recente**. Se você rerodou e ela passou, o
comando volta vazio e a causa original fica inacessível. Pegue a tentativa que falhou pelo número
dela, numa pasta fora do repo (no cwd, o zip vira untracked e derruba a prova de limpeza do
worktree):

```bash
mkdir -p /tmp/ci-log-<id>-1
gh api 'repos/{owner}/{repo}/actions/runs/<id>/attempts/1/logs' > /tmp/ci-log-<id>-1/logs.zip
unzip -q -o /tmp/ci-log-<id>-1/logs.zip -d /tmp/ci-log-<id>-1
grep -rl "<nome do teste>" /tmp/ci-log-<id>-1 | head -1
```

Lido o que precisava, apague a pasta. A mensagem real da tentativa que falhou é o que confirma ou
derruba a hipótese de causa; sem ela, o diagnóstico vira palpite.

## 4c0. Pré-voo do deploy por CLI

Quase toda falha de deploy por CLI cai em três causas, e **as três dão erros que apontam para o
lugar errado**. Cheque antes (se o projeto tiver um script de pré-voo, o `deploy.md` diz qual):

| # | Causa | Sintoma enganoso |
|---|---|---|
| 1 | Token de **outro team** | `Could not retrieve Project Settings… remove the .vercel directory`: manda mexer no `project.json`, mas o problema é o token |
| 2 | Token com escopo de **conta pessoal** | `/v2/user` responde 200 com o e-mail certo; todo o resto dá `forbidden` + `saml:true` |
| 3 | Env **Sensitive** | `vercel pull` grava a string literal `[SENSITIVE]`; o build local morre em `new URL("[SENSITIVE]")` sem dizer qual variável é, e `next build` **sem** as envs passa, o que despista |

Confira também que o `.vercel/project.json` local aponta para o projeto alvo: teams têm projetos
com nomes parecidos, e o deploy vai para o errado sem erro. **Um team, um token:** o token de um
team não serve para o projeto de outro, e a falta dele é bloqueio para a pessoa resolver, não
motivo para usar outro.

## 4c1. Deploy por CLI (siga a sequência provada do `deploy.md`)

Deploye só de um checkout limpo do **HEAD da branch padrão**, nunca do worktree ou da branch de
feature: depois de squash-merge, a árvore da feature não é a da `main`. Confirme
`HEAD == origin/<branch padrão>` e `git status --porcelain` vazio.

Comum aos dois modos, num `.sh` só (o env não passa de uma chamada do Bash para a outra):

```bash
read_var() { { grep -E "^$2=" "$1" 2>/dev/null || true; } | head -1 | cut -d= -f2- | tr -d "\"'"; }
VERCEL_TOKEN="$(read_var <arquivo-do-deploy.md> <VAR_DO_TOKEN>)"
unset VERCEL_ORG_ID VERCEL_PROJECT_ID VERCEL_OIDC_TOKEN   # os do .env.local costumam ser de outro team
npx vercel@59.25.0 whoami --token "$VERCEL_TOKEN"
```

**Modo `prebuilt`** (build local, imune a cache velho da Vercel):

```bash
npx vercel@59.25.0 pull --yes --environment=production --token "$VERCEL_TOKEN"   # (+ --scope se o projeto exigir)
VERCEL_FORCE_NO_BUILD_CACHE=1 npx vercel@59.25.0 build --prod --token "$VERCEL_TOKEN"
npx vercel@59.25.0 deploy --prebuilt --prod --yes --token "$VERCEL_TOKEN"
```

**Modo `remote`** (projeto com env **Sensitive**):

```bash
# NÃO rode `vercel pull`: ele grava [SENSITIVE] no lugar dos valores e o build local quebra.
# Deixe a Vercel buildar, onde ela tem os valores reais. --force faz o papel do
# VERCEL_FORCE_NO_BUILD_CACHE=1 do modo prebuilt.
npx vercel@59.25.0 deploy --prod --yes --force --token "$VERCEL_TOKEN"
```

Se já rodou `vercel pull` antes de perceber, apague o `.vercel/.env.production.local` antes de
qualquer build: as envs mascaradas contaminam o build.

## 4d. Verifique o bundle que está no ar (depois de todo deploy de frontend)

**CI verde não é produção saudável.** A Vercel pode servir HTTP 200 com um bundle sem as variáveis
públicas do backend (o app cai num modo demo, "sistema não configurado", sem erro no console).
Depois de todo deploy de frontend, duas checagens, com o output colado:

1. **O host do backend está no bundle** (por exemplo o `<ref>.supabase.co`): `curl` do domínio e
   `grep` do host, ou o script que o `deploy.md` indicar.
2. **A mudança desta ship está no bundle servido.** O `index-*.js` **não muda de hash** quando você
   edita rota **lazy-loaded**: só o chunk dela muda. Compare o chunk da rota editada com o
   `dist/assets/` do build local; o hash do Vite é de conteúdo, então hashes iguais = mesmo código.

```bash
PRODIDX=$(curl -s https://<DOMINIO>/ | grep -oE 'assets/index-[A-Za-z0-9_-]+\.js' | head -1)
curl -s "https://<DOMINIO>/$PRODIDX" | grep -oE '<MeuChunk>-[A-Za-z0-9_-]+\.js' | head -1
ls dist/assets/ | grep '<MeuChunk>-'   # mesmo hash nos dois = mudança no ar
```

HTTP 200 em asset não prova deploy: o fallback de SPA também responde 200.
