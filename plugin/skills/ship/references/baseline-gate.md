# ship §1b — gate de baseline em detalhe

Lido no §1b, entre o commit do §2 e o push, sempre que o diff toca `src/`, `supabase/` ou env.

### 1b. Gate de baseline (quando o diff toca `src/`, `supabase/` ou env)

Roda depois do commit do §2 e antes do push. O `--diff` procura segredo no que o push vai levar:
o índice, o disco e **cada commit do range `base..HEAD`** — `.env` que um commit trouxe e outro
tirou, ou JWT consertado só no disco, continuam reprovando. Arquivo untracked fora do
`.gitignore` também entra; o que o `.gitignore` cobre fica fora. Só sobre o diff, sem rede:
segundos. Existe porque nenhum gate anterior olha para **postura de ambiente**: segredo novo,
tabela nova sem RLS, edge function sem verificação de identidade, variável pública com nome de
segredo.

A pasta do resultado é uma por repo e por commit, `/tmp/ship-baseline-<repo>-<sha>`: com pasta
fixa, duas ships em paralelo leem o `findings.json` uma da outra. `<repo>` é o último pedaço do
`git rev-parse --show-toplevel` (em worktree, o nome dele) e `<sha>` é o que a primeira linha
abaixo imprime. Escreva o caminho por extenso nos comandos seguintes: variável não passa de uma
chamada do Bash para a outra. Depois de um `--amend` o SHA muda, e a pasta também.

```bash
git rev-parse --short HEAD
bash "${CLAUDE_PLUGIN_ROOT}/skills/baseline/scripts/collect.sh" \
     --diff origin/HEAD --out /tmp/ship-baseline-<repo>-<sha>; echo "collect exit=$?"
# exit 0 = limpo · exit 1 = CRITICAL/HIGH no diff · exit 3 = não mediu nada
jq -r '.findings[] | select(.severity=="CRITICAL" or .severity=="HIGH")
       | "\(.severity) [\(.pilar)] \(.title) — \(.file)"' /tmp/ship-baseline-<repo>-<sha>/findings.json
jq -r '.coverage[] | select(.status=="nao_medido") | "\(.pilar) \(.check): \(.reason)"' /tmp/ship-baseline-<repo>-<sha>/findings.json
```

Sem `origin/HEAD` o collect sai 3 dizendo que a base não resolve: `git remote set-head origin
--auto`, ou passe `origin/main` (`origin/master`, se for a padrão). Com exit 3 não há
`findings.json`, e os dois jq só acusam arquivo ausente.

**exit 1 bloqueia o push.** No `--diff` isso cobre: JWT ou `.env` versionado, ou untracked fora
do `.gitignore` · variável de prefixo público (`VITE_`/`NEXT_PUBLIC_`/`PUBLIC_`/`REACT_APP_`)
com `KEY|SECRET|TOKEN|PASSWORD` · tabela criada sem `ENABLE ROW LEVEL SECURITY` em
`supabase/migrations/` ou `migrations/` · fail-open em mapa de permissão · e, só em repo com
`supabase/functions/`, edge function sem verificação de identidade aparente e chamada de LLM sem
`max_tokens`. `SECURITY DEFINER` sem `SET search_path` sai MEDIUM: não bloqueia, vai para o
relatório.

Achado com "untracked" no título ainda não está em commit nenhum: a correção é o `.gitignore`
antes do próximo `git add`. O segredo dos outros achados está em algum commit do range, e o gate
olha todos: tirá-lo do HEAD, do índice ou do disco não basta, e commit novo por cima também não
— o push leva o histórico. Se entrou no último commit: `git rm --cached <arquivo>` no `.env` (ele
fica no disco) ou o código corrigido, e `git commit --amend`. Se entrou antes:
`git reset --soft <commit>^`, o commit anterior ao que o trouxe, e recommite sem ele. Para refazer
o range inteiro, parta de onde a branch nasceu:
`git reset --soft "$(git merge-base origin/<branch padrão> HEAD)"`. Nunca
`origin/<branch padrão>`: com a main andando, o índice da branch cai em cima da main nova e o
commit refeito apaga o que outra pessoa mergeou no meio — com o gate em exit 0. Branch já pushada:
o push seguinte é `--force-with-lease` e pede confirmação da pessoa. Rode o §1b de novo. Se já
subiu, rotacione o segredo.

O segundo jq lista o que não foi medido, e nenhuma linha é check que falhou. Em todo `--diff`
saem quatro, por desenho: `02 lints_banco`, `03 gate_vs_rls`, `07 gitleaks` e `07 env_example`
(banco, token de papel e histórico ficam para a auditoria completa da `baseline`). Sai também
`02 rls_migrations` quando o diff não traz migration em `supabase/migrations/` ou `migrations/`,
e `04 edge_auth` num repo sem `supabase/functions/`. Essas duas vão para o relatório quando o diff
tem o que elas não olharam (migration em `src/sql/`, chamada de LLM em `src/`), e aí não contam
como limpo.

**exit 3 não é aprovação**: nada foi medido. Trate como gate que não rodou e descubra por quê
(`bash "${CLAUDE_PLUGIN_ROOT}/skills/baseline/scripts/doctor.sh"`).

Achado que já é **exceção aceita** em `.context/docs/baseline.md` não bloqueia, mas a exceção
precisa estar lá antes, com dono e data. Registrar exceção no meio da ship para desbloquear a
própria ship é desligar o alarme para não ouvi-lo. Sem `baseline.md`, o gate roda mesmo assim.
