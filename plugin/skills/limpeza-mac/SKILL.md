---
name: limpeza-mac
description: >-
  Limpeza profunda de um Mac de desenvolvimento (só macOS). Cobre worktrees órfãs e
  mergeadas, branches já mergeadas, node_modules e .next de repo parado, caches de
  npm/uv/bun/yarn, versões velhas de CLIs de IA, a VM do Claude Desktop e os restos do
  OrbStack. Primeiro um inventário read-only; o SHA de cada branch vai para um ledger
  antes de apagar. Só manual: "/kit-vamoo:limpeza-mac".
disable-model-invocation: true
---

# Limpeza do Mac

O espaço de um Mac de dev raramente está onde o limpador comercial procura. Ele mora em
node_modules/.next dos repos (dezenas de GB), no disco da VM do OrbStack, no cache do npm e
na VM do Claude Desktop. Esta skill mede isso, apaga só o que é seguro por construção e
guarda o SHA de cada branch que sai, para dar para restaurar.

Só roda no macOS: em outro sistema os dois scripts dizem isso e saem sem fazer nada. Os
caminhos de `~/Library` abaixo também são só do Mac.

```bash
S="${CLAUDE_PLUGIN_ROOT}/skills/limpeza-mac/scripts"
PLANO="$HOME/backups/limpeza-$(date +%F)/plano"; LEDGER="$HOME/backups/limpeza-$(date +%F)"
df -h /System/Volumes/Data | tail -1     # o `df /` mostra o volume do sistema, não o seu
```

O ledger vai para `~/backups`, não para o scratchpad: quando a sessão acaba, o scratchpad
some, e o SHA iria junto.

## 1. Inventário (read-only)

Pergunte à pessoa onde ficam os repos dela. Sem raiz na linha de comando, o inventário usa
`LIMPEZA_RAIZES` (pastas separadas por `:`), e sem ela procura em `~/Developer`,
`~/Projects`, `~/code` e `~/Documents`. Pasta que não existe é ignorada.

```bash
bash "$S/inventario.sh" "$PLANO" ~/pasta-dos-repos ~/outra-pasta
```

A rodada leva alguns minutos, porque faz fetch em todos os repos e um `gh pr list` por
branch que não é ancestral do default. Não rode `du` em `~` inteiro: demora demais, e o
inventário já mede o que importa em `pocos.tsv` e `builds.tsv`.

Antes de apagar, mostre à pessoa só o que exige decisão dela:
- worktrees e branches `LOCAL(+N)` e `pushed(+N)`: trabalho que não chegou ao default;
- repos com `sem-origin`: as branches são a única cópia;
- clones duplicados do mesmo remote (`git remote get-url` igual): apagar clone inteiro está
  fora do escopo desta skill;
- órfãs com arquivo fora de build: o `aplicar.sh` não as toca. O git não as conhece mais,
  então `git status` ali não responde. Compare com o clone principal
  (`diff -rq -x node_modules -x .next -x .git <órfã> <clone>`) e mostre à pessoa o que só
  existe ou difere na órfã: é ela quem decide.

## 2. Git, builds e órfãs

```bash
DRY=1 bash "$S/aplicar.sh" "$PLANO" "$LEDGER"   # mostre a saída à pessoa
bash "$S/aplicar.sh" "$PLANO" "$LEDGER"         # só com o OK dela
```

O que o script respeita, e por quê:
- **`merged(PR#N)` só com o SHA igual ao head do PR.** O `gh pr list --head` casa pelo
  nome da branch, então um commit feito depois do merge ou um nome reusado se perderia num
  `-D`. Um tip que é só ancestral do head também fica. O PR também tem que ter sido mergeado
  **no default** (`--base`), porque uma branch empilhada mergeada em outra feature não
  chegou lá. E o `origin/HEAD` local é atualizado (`set-head --auto`) antes, porque ele fica
  velho quando o default muda no GitHub.
- **Todo worktree passa pelo `worktree-gc.sh --verificar <caminho>` do plugin.** São as
  mesmas travas do gc: sujo, arquivo ignorado de valor, branch não mergeada. Qualquer saída
  diferente de 0 mantém o worktree, inclusive quando o `worktree-gc.sh` instalado ainda não
  tem esse modo.
- **Arquivo ignorado conta como sujeira.** O `worktree remove` sem `--force` apaga ignorado
  sem avisar (`.env.local`, sqlite, dump), e o ledger não restaura isso. Só passa ignorado
  de build ou cópia byte a byte do mesmo arquivo no clone principal (o `.env` semeado).
- **Worktree cujo HEAD mudou depois do inventário fica.** Em detached, nenhuma branch
  seguraria o commit novo.
- **`worktree remove` sem `--force`.** Ele recusa sozinho uma árvore suja. Se a sujeira for
  só symlink de `.venv`/`models`, mostre à pessoa e remova com `--force` apenas com o OK
  dela.
- **Lock de sessão morta não protege nada.** O Claude grava `claude session X (pid N)` no
  lock do worktree. Se o pid não existe e o `--verificar` libera, o script faz `unlock` e
  remove. Se o remove falhar, o lock volta.
- **Worktree com índice mexido nas últimas 24h é `ativa`**, nunca merged: uma branch
  recém-criada sem commit também é ancestral do default. O inventário usa
  `--no-optional-locks` para o próprio `status` não reescrever o índice e apagar esse sinal.
  Qualquer `git status` comum (IDE, git-sync, você) reescreve o índice e faz tudo virar
  `ativa` por 24h. O erro é para o lado de manter.
- **`.next` dentro de `.vercel/output` não é build solto.** É o prebuilt do deploy, e o
  inventário não desce em `.vercel`.
- **A idade do repo vem do reflog do HEAD**, não do mtime do índice, que qualquer
  `git status` reescreve.
- **Worktree detached** sai quando o HEAD é ancestral do default. Squash não é ancestral:
  se `git diff --stat <sha> <commit-do-squash>` sair vazio, rode o `--verificar` nele e
  remova só com o OK da pessoa.

Não rode `git gc --prune=now` nem `--aggressive` depois. O ledger restaura com
`git -C <repo> branch <branch> <sha>` enquanto os objetos soltos existirem, o que dura
cerca de duas semanas.

## 3. Caches

São regeneráveis e custam só um novo download:

```bash
npm cache clean --force
uv cache clean
rm -rf ~/.bun/install/cache ~/.yarn/berry/cache   # `bun pm cache rm` exige estar num projeto
brew cleanup -s --prune=all
```

Em cada ferramenta abaixo, mantenha a versão que o binário usa e apague o resto. Rode só as
que existirem na máquina:
- `~/.local/share/claude/versions/*`: confira `which -a claude` antes. Se o binário for o
  do Homebrew, todas as versões dali são lixo.
- `~/.local/share/cursor-agent/versions/*`: a versão ativa é o alvo de `~/.local/bin/cursor-agent`.
- `~/Library/Application Support/Cursor/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions/*`:
  cerca de 600 MB por versão. A ativa é o alvo do link em `agent-cli/.local/bin/cursor-agent`.
  Os `cursor-agent-worker-*.log/.spec/.owner.json` com mais de 7 dias também saem.
- `~/Library/Caches/ms-playwright/*`: só a revisão mais antiga de cada navegador. Um
  projeto que fixa uma versão velha baixa de novo.

Estes precisam do app fechado. Rode `pgrep -fl` antes; se o app estiver aberto, o item vira
PENDENTE:
- **Claude Desktop**: `~/Library/Application Support/Claude/vm_bundles/claudevm.bundle`
  (cerca de 10 GB, recriado quando o Cowork sobe). Se esta sessão roda dentro do Desktop,
  não toque.
- **Cursor**: `logs/*` e `CachedData/*`. O `state.vscdb` inchado se resolve com `DELETE FROM
  cursorDiskKV` + `VACUUM`. O VACUUM sozinho não resolve, porque a freelist fica vazia.
- **Chrome**: `OptGuideOnDeviceModel` (cerca de 4 GB, modelo on-device). Ele volta sozinho
  se o recurso estiver ligado. Para de voltar desligando
  `chrome://flags/#optimization-guide-on-device-model`.

Não toque em:
- `~/.claude/projects`: memória e transcripts, que o CLI já poda por `cleanupPeriodDays`;
- `~/.cache/huggingface` e `~/.cache/whisper-cpp`: modelos que um projeto pode estar usando,
  às vezes por symlink, e que custam GBs para baixar de novo;
- `~/Downloads`.

## 4. OrbStack

Com o app instalado, `orb stop` encolhe o disco esparso. Containers removidos não devolvem
espaço antes disso. Para a remoção completa, com o app já desinstalado e com o OK da pessoa:

```bash
rm -rf ~/Library/Group\ Containers/*.dev.orbstack ~/.orbstack
chmod u+w ~/OrbStack && rm -rf ~/OrbStack        # ponto de montagem, read-only
sed -i '' '/\.orbstack\/shell\/init.zsh/d' ~/.zprofile
```

Os links `docker`, `docker-compose`, `docker-credential-osxkeychain`, `kubectl`, `orb` e
`orbctl` em `/usr/local/bin` são do root e ficam quebrados. Entregue à pessoa o comando
pronto para ela rodar com sudo no terminal dela:
`sudo rm -f /usr/local/bin/{docker,docker-compose,docker-credential-osxkeychain,kubectl,orb,orbctl}`.

## 5. Relatório

Mostre o `df -h /System/Volumes/Data` de antes e de depois e o que saiu em cada fase. Feche
com um bloco `PENDENTE:` com o que ficou para a pessoa decidir: branches LOCAL, repos sem
origin, clones duplicados, apps que estavam abertos e o comando com sudo.
