<!-- secscan: lido na Fase 4.5, quando o repo tem .github/workflows/ -->

## CI no GitHub Actions (Fase 4.5, C5 e C6)

> Ponto de partida: skill `offensive-cicd-pipeline` de `SnailSploit/Claude-Red` (MIT), só a parte
> de GitHub Actions. Critérios reescritos para revisão estática.

Workflow é código que roda com o token do repositório e os secrets do CI. Sem
`.github/workflows/`, a fase é `não aplicável (sem workflows)`.

```bash
ls .github/workflows/*.y*ml 2>/dev/null || echo "sem workflows → Fase 4.5 não aplicável"
# 1. Dado de quem abre PR, issue ou comentário interpolado no shell
grep -nE '\$\{\{ *github\.(head_ref|event\.(pull_request\.(title|body|head\.(ref|label))|issue\.(title|body)|comment\.body|review\.body|review_comment\.body|discussion\.(title|body)|head_commit\.(message|author)|commits|pages))' .github/workflows/*.y*ml
# 2. Gatilhos que rodam com a permissão da main sobre código de fora
grep -nE 'pull_request_target|workflow_run|issue_comment' .github/workflows/*.y*ml
# 3. Action de terceiro por tag ou branch, não por SHA
grep -nE 'uses: *[^ ./][^@ ]*@' .github/workflows/*.y*ml | grep -vE '@[0-9a-f]{40}'
# 4. Permissão do GITHUB_TOKEN
grep -nE '^ *permissions:|write-all|contents: *write|id-token: *write' .github/workflows/*.y*ml
```

Grep localiza; leitura decide.

- **Expressão no `run:`** (grupo 1). `${{ … }}` é substituído **antes** de o shell rodar: título
  de PR com `"; curl … | sh #` vira comando. É achado quando o valor vem de quem não tem escrita
  no repo e cai num `run:` ou no `script:` de `actions/github-script`. A correção é passar por
  `env:` (`TITULO: ${{ github.event.pull_request.title }}`) e usar `"$TITULO"` no shell. `HIGH`;
  `CRITICAL` se o job tem secret ou token com escrita.
- **`pull_request_target` com checkout do PR** (grupo 2). Esse gatilho roda com os secrets e o
  token de escrita da main. O problema é o job fazer `actions/checkout` com
  `ref: ${{ github.event.pull_request.head.sha }}` (ou `head.ref`) e depois instalar, buildar ou
  testar esse código: código de qualquer fork roda com os secrets. `CRITICAL`. O gatilho que só
  rotula ou comenta, sem checkout do PR, não é achado. `workflow_run` que baixa artefato do run
  disparado por PR e executa ou interpreta o conteúdo é a mesma classe.
- **Action sem pin** (grupo 3). Tag (`@v4`) e branch (`@main`) podem ser movidas pelo dono da
  action; SHA não. Action do próprio GitHub (`actions/*`) e da própria organização pesa menos que
  action de terceiro com poucos mantenedores: `MEDIUM` para terceiro, `LOW` para `actions/*`. Um
  bloco por workflow, com a contagem.
- **Permissão larga** (grupo 4). Sem bloco `permissions:`, o token herda o padrão do
  repositório, que pode ser escrita. `write-all` ou `contents: write` num job que não publica
  nada: `MEDIUM`. `id-token: write` sem deploy por OIDC: `LOW`.
- **Secret no log**: `echo ${{ secrets.X }}`, `set -x` antes de usar secret, secret passado como
  argumento de linha de comando. O mascaramento do GitHub não cobre valor derivado (base64, JSON
  montado). `HIGH`.

Action sem pin entra na **C5**; os outros, na **C6**. A Base dessas linhas diz que a Fase 4.5 foi
leitura dos workflows, sem scanner dedicado.
