# §3 da ship: Supabase e n8n

O Supabase faz parte da produção: diff que toca `supabase/functions/` ou traz migration nova
(`supabase/migrations/` ou `src/sql/`) inclui o deploy dele nesta ship. Os dois flags saem da
detecção do §3 da `SKILL.md`, pelo diff do PR depois do commit. Sem nenhum dos dois, pule 3a–3c e
marque N/A no relatório.

Os valores (project-ref, nome da variável do token, arquivo onde ela mora, comando de migration)
vêm do `.context/docs/deploy.md` do projeto. Sem ele, derive o project-ref de
`supabase/.temp/project-ref` ou do host do `.env.local` (`SUPABASE_URL` → `<ref>.supabase.co`), e
pergunte o resto.

## 3a. Token do `functions deploy` (só com TOCA_EDGE_FUNCTIONS; nunca imprima segredo)

```bash
# Lê só a linha da variável do projeto, do arquivo que o deploy.md indica. `source` jogaria
# todos os segredos do arquivo no ambiente. Estas linhas e os deploys do 3c vão num .sh no
# scratchpad, rodado pelo caminho absoluto (`bash /abs/deploy-fn.sh`): de dentro de worktree o
# guard recusa `source`/`export`, e o env não passa de uma chamada do Bash para a outra.
read_var() { { grep -E "^$2=" "$1" 2>/dev/null || true; } | head -1 | cut -d= -f2- | tr -d "\"'"; }
SUPABASE_ACCESS_TOKEN="$(read_var <arquivo-do-deploy.md> <VAR_DO_TOKEN>)"
[ -n "$SUPABASE_ACCESS_TOKEN" ] || { echo "<VAR_DO_TOKEN> ausente" >&2; exit 1; }
export SUPABASE_ACCESS_TOKEN                # o supabase CLI lê do ambiente
PROJECT_REF=<project-ref do deploy.md>
```

Para saber se a chave existe sem ver o valor:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/env-tem-chave.sh" <arquivo> <VAR>` (diz `presente`, `vazia`
ou `ausente`). `cat`, `head` e `grep` no arquivo trariam o valor para o contexto.

Deploy respondeu 403: **PARE** e diga qual variável falta. Não diga "shipped".

## 3b. Migrations (novas nesta ship)

Migration contra produção é destrutiva: o comando é o do `deploy.md` e, sem ele, pergunte antes.
O padrão que funciona tem dois tempos:

1. **Valide em transação:** execute o arquivo dentro de `BEGIN; … ROLLBACK;` contra o banco (o
   script do projeto costuma ter um `--dry-run` que faz isso). Erro aqui não deixou nada pela
   metade.
2. **Aplique** com `psql` e `ON_ERROR_STOP=1`, pelo script do projeto, que lê a URL do banco
   sozinho: sem colar a URL no shell e sem `source` do `.env`.

Repo com o próprio script de migration: use-o e não o substitua por cópia de outro projeto, porque
ele costuma ter travas próprias (lint de DROP, confirmação de produção) que a cópia apagaria.
Projeto que espelha migration em `src/sql/YYYY-MM-DD_*.sql`: é o mesmo SQL, aplique uma vez só.
`supabase db push` aplica tudo o que o banco ainda não tem, inclusive migration de outra branch:
use só se o `deploy.md` mandar.

Antes de aplicar, a checklist "Migration que não derruba produção" da `baseline`
(`baseline/references/02-banco.md`): NOT NULL só depois do backfill, índice em tabela viva com
CONCURRENTLY, DROP/RENAME só depois do deploy que parou de usar, e a ordem schema↔código decidida.

## 3c. Edge functions (cada function que o PR mudou)

```bash
git diff --name-only origin/HEAD...HEAD | /usr/bin/grep '^supabase/functions/' | cut -d/ -f3 | sort -u   # sem origin/HEAD: origin/main
supabase functions deploy <nome> --project-ref "$PROJECT_REF"                   # com config.toml: respeita [functions.<nome>] verify_jwt
supabase functions deploy <nome> --project-ref "$PROJECT_REF" --no-verify-jwt   # SÓ sem config.toml: webhook público exige o flag a cada deploy
```

A fonte de verdade do `verify_jwt` é o `supabase/config.toml` (`[functions.<nome>] verify_jwt =
false` para cada webhook público). **Deploy sem `config.toml` reseta `verify_jwt=true`** e o
webhook passa a responder 401 sem ninguém notar; só nesse caso re-aplique `--no-verify-jwt` a cada
deploy. Webhook público novo: adicione a entrada no `config.toml` no mesmo PR.

## 3d. n8n (quando `n8n_workflows/` mudou)

Só se o `deploy.md` tiver uma seção n8n com a tabela de workflows; senão, N/A. O padrão:

- `PUT` do workflow pela API, depois `deactivate` + `activate` (o n8n só re-registra o webhook na
  ativação).
- Sonda do webhook pelo `%{http_code}`: 200 ou 400 = registrado; 404 = precisa de Publish manual
  no editor, e isso vai para o Pendente do relatório.

A skill `n8n-workflow-agent` tem o resto (baseline + diff antes do PUT, layout, Code Node).
