# Changelog

Mudanças notáveis do kit. Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/).
Mentorado: atualizar **não é automático** — o Claude Code desliga o auto-update para
marketplaces de terceiros. Ligue uma vez em `/plugin` → Marketplaces → vamoo-ai →
Enable auto-update (e depois só `/reload-plugins`), ou atualize na mão com
`/plugin marketplace update vamoo-ai` + `/plugin update kit-vamoo` + `/reload-plugins`.
Veja **Atualizar depois** no README — inclusive o que o auto-update NÃO cobre.

Mantenedor: **suba o `version` do `plugin.json` em toda entrega.** Ele é a chave do
cache do Claude Code; sem bump, ninguém recebe a mudança, nem com auto-update ligado.
Se a mudança tocar a barra de status ou as preferências, rode também
`/kit-vamoo:setup` — ele faz backup de tudo antes.

## [0.25.0] — 2026-09-03

### Adicionado

- **Guard-rails de sessão, vindos do kit do time** (#58 — decisão hook a hook; todos leem o
  payload via node, como os demais). Quatro comportamentos:
  - **Checkout no clone que outra sessão está usando é bloqueado.** A regra "NUNCA faça
    `checkout`/`switch`/`stash`/`reset` num clone que outra sessão usa" da skill `worktrees`
    era só prosa. `repo-session.sh` registra as sessões vivas por repositório (um marker por
    `session_id`, em `~/.claude/.cache/repo-sessions/`), e `block-parallel-clone-switch.sh`
    bloqueia a troca no clone principal quando outra sessão esteve ativa nele nos últimos 30
    minutos. Worktree linkado é livre — é para lá que a skill manda. Escotilha `PARALLEL_OK=1`,
    lida depois do parser de heredoc (citada num doc não desliga nada). 33 checks em
    `tests/test-block-parallel-clone-switch.sh`: path entre aspas, `~`, variável do próprio
    comando, as quatro formas de heredoc, e o par registro/bloqueio de ponta a ponta.
  - **`gh pr merge --delete-branch` não fecha PR encadeado.** Deletar a base fecha o PR filho
    de forma irreversível — `gh pr reopen` recusa, `gh pr edit --base` recusa, só recriando.
    `block-delete-branch-with-children.sh` consulta o `gh` só quando todas as pré-condições
    casam (número do PR, flag de deleção, posição de comando), respeita o `--repo` do comando
    e falha aberto sem rede. Escotilha `DELETE_BRANCH_OK=1`. 16 checks em
    `tests/test-block-delete-branch.sh`, com `gh` falso.
  - **A branch mudou entre um prompt e outro? Avisa.** `branch-guard.sh` compara a branch
    de cada prompt com a do anterior na mesma sessão: outra sessão (Codex, outro terminal)
    trocou por fora, e o próximo edit cairia no lugar errado sem nada indicar. Só avisa.
    `tests/test-branch-guard.sh`.
  - **Sessão longa demais? Avisa uma vez por faixa.** `session-size-guard.sh` mede o
    transcript e, em 600 / 1.200 / 2.000 linhas, diz que `/clear` ou `/compact` sai mais
    barato — cada tool call relê a conversa inteira, então o custo cresce com o quadrado do
    comprimento. `tests/test-session-size-guard.sh`.

  Não portados, registrados para não voltar à pauta: `rtk-claude`/`rtk-codex` (o kit não
  distribui o RTK), `check-dev-server` (depende do MCP do Chrome), `dotcontext-doctor` (o
  dotcontext ainda não tem diagnóstico para claude-code; o kit já tem `dotcontext-session`)
  e o dispatcher `pre-bash.sh` (otimização da instalação via `settings.json`; o plugin
  registra pelo `hooks.json` — revisitar se a latência dos cinco hooks de Bash pesar).

### Docs

- **README** descreve os guard-rails novos na linha de `plugin/hooks/`; **skill `worktrees`**
  ganha o bullet do bloqueio de checkout em clone compartilhado, com a escotilha.

## [0.24.0] — 2026-09-03

### Adicionado

- **`git-sync` acha a conta do `gh` que enxerga o repositório** (#54; vindo do kit do time,
  lá #63). Máquina com conta pessoal e conta de trabalho no mesmo keyring: a ativa devolve
  `Could not resolve to a Repository` para o repo da outra — que lê como repositório
  inexistente, não como conta errada, e o relatório saía cego para PR sem dizer o motivo.
  O script testa as demais contas de `gh auth status`, usa a que enxerga (só neste
  processo, sem trocar a ativa) e diz qual foi; se nenhuma enxerga, diz isso com todas as
  letras. `GH_TOKEN` exportado tem precedência. Junto vem o bloco de avisos do time:
  branch cujo upstream sumiu e alteração não commitada direto na branch compartilhada
  entram em `### avisos (ação sua)`, e o `### summary` grita quando há aviso. 18 checks
  em `tests/test-git-sync-conta.sh`, com `gh` falso — 10 falham no script anterior.
- **`memoria-link` não perde projeto sem transcript** (#56; time #49/#60/#61). O caminho
  vinha só do `cwd` gravado no transcript, e o Claude Code poda os `.jsonl` antigos:
  projeto sem transcript perdia o caminho e o loop dava `continue` sem uma linha de aviso —
  memória presa na máquina enquanto a varredura dizia que estava tudo em dia. Agora o slug
  é resolvido contra os diretórios reais (só aceita resposta única; empate é aviso),
  memória sem destino é reportada com o comando para ligar à mão, o README do formato é
  escrito em `--adotar`/`--repo` (nunca na varredura automática, que só conta e aponta),
  `README.md`/`MEMORY.md` não contam como fato, e `memory` que virou link quebrado é
  tratado como problema, não como "sem memória local". `tests/test-memoria-link.sh` novo —
  8 checks falham no script anterior.

### Corrigido

- **`worktree-gc` só apaga worktree cuja branch está mesmo mergeada** (#55). "Mergeada"
  era `gh pr list --state merged | length > 0`: bastava a branch ter tido um PR mergeado um
  dia. Commit feito depois, ainda sem push, contava como lixo — e `--apply` apagava trabalho
  novo (no teste, o script anterior **apagou** o worktree). Agora o tip local precisa estar
  contido no head do PR mergeado (fail-closed: sem prova, mantém); `.env.local` diferente do
  clone principal segura o worktree, porque é invisível no `status` e some junto; e worktree
  detached limpo com HEAD já em `origin/main` vira candidato em vez de ser pulado para
  sempre. `tests/test-worktree-gc.sh` novo, com `gh` falso que responde às duas formas de
  consulta — 7 checks falham no anterior.

### Docs

- **README: são 19 skills.** A tabela dizia 18 e a seção "Skills incluídas" dizia 15; o
  diretório tem 19, e todas já estavam descritas.
- **Skill `git-sync`**: parágrafo "Duas contas no mesmo keyring", com a saída que o script
  imprime quando usa a outra conta.

## [0.23.1] — 2026-09-03

### Corrigido

- **`check-careful` lia heredoc pela metade e deixava passar o comando destrutivo de verdade**
  (#72; vindo do kit do time, lá #137). Tag que o parser não reconhecia nunca fechava, e aí ele
  engolia o resto do comando — inclusive o que vem DEPOIS do terminador, que é comando real.
  Medido: `cat > x.sql <<'END-OF-SQL' … END-OF-SQL` seguido de `psql -c "DROP TABLE users"`
  **não pedia confirmação nenhuma**; sem o heredoc antes, o mesmo `psql` pergunta. E este é
  o hook que roda vivo neste kit (`acceptEdits`) — no time ele fica calado no bypass.
  Faltavam quatro formas: tag com hífen ou ponto, terminador indentado por tab do `<<-`,
  `EOF)`/`EOF)"` fechando um `$(cat <<EOF`, e `<<<` (here-string), cujo `<<EOF` interno era
  lido como abertura. A escotilha `CAREFUL_OFF=1` também: era lida do comando **cru**, então
  um doc que apenas a mencionava desligava o hook inteiro — não só o bloco de SQL — para o
  `rm -rf` real que viesse depois; agora é lida depois do parser, como o `HOTFIX_MAIN=1` do
  `block-main-commit` já fazia. Como prefixo de verdade continua valendo. 8 casos novos em
  `tests/test-check-careful.sh` — 4 falham contra o hook anterior, os outros 4 provam que
  o conserto não vira falso positivo (`DROP` dentro do corpo continua calado).

## [0.23.0] — 2026-09-03

### Adicionado

- **Skill `secscan`: a calibração de falso positivo do kit do time** (#53). O recorte
  pedagógico daqui (253 linhas contra 467 lá) não tinha nada do que o time mediu em 31/08 —
  e a medição é o que separa "achei 40 problemas" de "achei 40 linhas, 14 são problema".
  Entra só a parte de precisão, mantendo o tamanho: a regra de ferro do `CONFIRMED`
  (ferramenta real **e** heurística no mesmo ponto, ou teste do projeto; o resto é
  `heuristic`); o que o semgrep de fato corrobora (255 regras em 2.198 arquivos → 27
  findings, todos em `.github/` e `.npmrc`; 4 vulnerabilidades plantadas → 0 vistas, então
  C1 sai sempre `heuristic`); guarda de lockfile antes dos `|| true` e o estado `não medido`
  para ferramenta presente com input ausente; e a seção "Falso positivo — o que a
  calibração ensinou": 36% de precisão medida, grep localiza e leitura decide, anotação de
  exemplo apodrece, hit contado duas vezes, sink não é primitiva, veredito julgado em
  `.context/docs/security/vereditos.md` — a mesma tabela que a `baseline` lê.

### Corrigido

- **Skill `baseline` roteia para o pilar 08** (#57). O `references/08-perimetro.md` existia
  desde o porte anterior, mas nada apontava para ele: "subiu host, painel ou domínio novo →
  08" e "edge/webhook **ou login** → 04" entram no roteamento, e a description ganha a
  palavra "perímetro" (465 caracteres; o teto é ~600).

## [0.22.0] — 2026-09-03

### Corrigido

- **O CI nunca rodou `tests/test-block-main-commit.sh`.** Os 42 casos do guard de commit
  na `main` — inclusive os 14 de heredoc que entraram na 0.21.0 — existiam no repo e
  ficavam parados; o workflow só tinha um teste de fumaça do hook. O step entra, e um gate
  novo (`Nenhum teste ficou de fora deste workflow`, vindo do kit do time) reprova o CI
  quando um `tests/test-*.sh` não está referenciado no `ci.yml`.

### Adicionado

- **Hook `block-cd-leitura-relativa`: o fim do pedido de autorização que aparecia até no
  modo bypass.** Medido em 03/09: `cd /caminho && grep -n "cargos" src/lib/tipos.ts` fazia
  o Claude Code parar e pedir aprovação, com a mensagem *"…after a cd would search a
  directory that cannot be determined here, and a `Read()` deny rule is configured; only
  you can approve running it anyway"*. Não era hook nenhum: depois do `cd` o harness não
  sabe em que pasta a leitura vai cair e, como o kit configura regras `Read()` em
  `permissions.deny` (as que impedem a leitura de `.env`, chave SSH e afins), ele não
  consegue provar que a leitura é segura — então pergunta a você, mesmo em bypass.
  Apagar as regras calaria o prompt e derrubaria junto a proteção dos seus segredos, que
  é a única que vale em todos os modos. Então o hook faz o contrário: bloqueia o padrão e
  devolve o comando pronto em caminho absoluto, que o harness resolve e libera sozinho.
  O Claude lê, corrige e segue — você não aprova nada. Escotilha `CD_LEITURA_OK=1`;
  23 casos em `tests/test-block-cd-leitura-relativa.sh`, a maioria provando que comando
  legítimo não é barrado (trecho entre aspas nunca é caminho, `sed -i` é escrita, corpo de
  heredoc é conteúdo). Regra correspondente no `CLAUDE-global.md`.

## [0.21.0] — 2026-09-03

### Adicionado

- **Índice de memória em dois níveis** (`plugin/scripts/memoria-indice.sh`, passo 5 da skill
  `memoria-projeto`). O `MEMORY.md` de `.context/memoria/` entra em toda request e crescia
  sem teto — 57 KB num CRM com 303 memórias. O script mantém o curto até 8 KB, por
  prioridade de tipo, e move a cauda para `MEMORY-completo.md`, no mesmo formato.
  Idempotente, dry-run por padrão. Vindo do kit do time (lá, #120).
- **Subagente `revisor`** (`plugin/agents/revisor.md`): review read-only de trabalho já
  feito — spec compliance, checks rodados de novo por conta própria, findings com
  `arquivo:linha`, veredito em 4 seções. Não edita nada; quem aplica é a conversa
  principal. Vindo do kit do time (lá, #124).
- **`check-careful` registra cada `ask`** em `~/.claude/.cache/check-careful/decisoes.tsv`:
  data, sessão, modo de permissão e a regra — nunca o comando, que pode carregar segredo.
  Aprovação concedida não deixa rastro no transcript, então "por que está pedindo
  aprovação?" só se responde com este arquivo. `CHECK_CAREFUL_LOG` redireciona; vazio
  desliga (a suíte usa).

### Corrigido

- **`git-sync --cleanup` enxerga branch mergeada sem `[gone]`** (#68). O cleanup só coletava
  branch com upstream apagado; branch mergeada por PR cujo remoto sobreviveu ao
  `--delete-branch` (o `gh pr merge` quebra depois do merge quando roda de dentro de um
  worktree) ou que nunca teve upstream ficava invisível — 10 num kit e 5 num CRM em 03/09.
  A consulta ao `gh` passa a devolver número e head do PR; fora do `[gone]` a prova para o
  `-D` é dupla: PR mergeado **e** head == tip; commit depois do merge preserva a branch.
  Só o local sai; o remoto sobrevivente fica com o comando impresso. 6 checks novos em
  `tests/test-git-sync-cleanup.sh`, que falham no script anterior.
- **`block-main-commit.sh` ignora o corpo de heredoc** (#65). `cat > script.sh <<'EOF'` com
  `git commit` e `bash -c` no corpo, numa sessão com cwd em main, era bloqueado como se
  fosse o commit. O corpo some antes de qualquer match — inclusive da resolução de
  `git -C`/`cd` e do `HOTFIX_MAIN=1`, que um corpo conseguia contaminar. 14 casos novos
  em `tests/test-block-main-commit.sh` (8 falhavam antes).

### Performance

- **`warn-branch-behind.sh` faz `git fetch` no máximo 1x a cada 10 min por repositório +
  branch** (#63): custava ~1 s em todo SessionStart. Marcador em
  `~/.claude/.cache/warn-branch-behind/`; dentro da janela compara com o `origin/<branch>`
  já local e continua avisando. `tests/test-warn-branch-behind.sh` novo, com `git` falso
  que conta os fetches.

### Docs

- **Skill `worktrees`**: três recusas novas do guard do harness, medidas em 03/09 (#51):
  `source <arquivo>` mesmo sendo `.env`, `gh` com `VAR="$(…)"` e `--jq` entre aspas, e o
  parêntese de `tipo(escopo):` no título do PR lido como subshell — com o contorno de cada
  uma na tabela, e a afirmação de que o guard inspeciona a linha de comando, não o corpo do
  arquivo.

## [0.20.0] — 2026-09-03

### Adicionado

- **Skill `harness-check`: para onde vai o seu token.** O pedido "me ajuda a
  gastar menos token" sempre terminava no mesmo lugar errado — cortar o
  CLAUDE.md, que é a parte que dá pra ver. Medido em 03/09/2026 numa conta com o
  harness carregado: o contexto inicial era **52,7K tokens** e só **~5K (10%)**
  vinha de arquivo editável (CLAUDE.md 2,1K, descrições de skill 1,7K, memória
  0,9K). Os outros 90% são system prompt, schemas de ferramenta e MCP. Enxugar o
  CLAUDE.md ali economiza ~2% do preload: faxina, não economia.
  A skill manda medir antes de cortar, em quatro passos — `/context` para a
  composição do preload (comando built-in não se invoca por `Bash`: peça o output
  ao usuário), `ccusage` para o gasto real, `claude mcp list` para o MCP que
  ninguém usa, e os hábitos que de fato movem a conta, com a sessão-maratona em
  primeiro lugar. Fecha com uma regra que vale para qualquer relatório de custo:
  **rotule todo número como MEDIDO, ESTIMADO ou INDISPONÍVEL** — a maior fatia do
  preload não é mensurável arquivo a arquivo, e apresentar `chars÷4` como medição
  é como a auditoria de token engana.
  Espelho da mesma entrega no kit do time (`claude-config-team` 0.27.0), onde a
  skill se apoia nos scripts de telemetria que aquele kit tem; aqui ela é
  autocontida, só com o que o Claude Code já dá de fábrica.

## [0.19.2] — 2026-09-03

### Corrigido
- **`release.yml`: grupo de concorrência por commit e job só em `main`** — os
  dois achados do Codex no #62. O grupo era por branch, e o GitHub mantém só
  **um** run pendente por grupo, substituído pelo run mais novo: três bumps
  mergeados em sequência derrubariam a release do meio, e o run seguinte não
  a refaz. Agora é `release-${{ github.sha }}`, cada merge com a própria fila.
  E o job só roda com `github.ref` em `refs/heads/main`: `workflow_dispatch`
  aceita qualquer branch, e um disparo numa branch tagearia um commit não
  mergeado — que o run de `main`, vendo a tag existir, manteria.
- Se a `v0.19.1` não aparecer entre as releases, foi por isso: o GitHub não
  processou o push do merge do #62 — nenhum workflow rodou para aquele commit,
  nem o `ci`. O merge desta versão é um push novo que muda o `plugin.json`.

## [0.19.1] — 2026-09-03

### Corrigido
- **CHANGELOG: os cabeçalhos `## [0.13.0]`, `## [0.14.0]` e `## [0.15.0]` voltaram.**
  Três PRs seguidos resolveram o conflito no topo do arquivo trocando o
  cabeçalho do vizinho pelo seu em vez de inserir acima dele — o texto de cada
  versão ficou, o título sumiu, e o bloco `0.16.0` acabou com quatro
  `### Adicionado` colados. Nada foi reescrito: cada trecho só voltou para
  baixo do cabeçalho que já tinha quando nasceu (`c30cb97`, `c8a325d`, `63c0c95`).

### Adicionado
- **O gate de versão pega seção repetida e cabeçalho fora de ordem.**
  `tests/test-versao-changelog.sh` só via versão duplicada, e a corrupção acima
  passou por ele três vezes: versão engolida não repete — some. Agora reprova
  bloco com a mesma `### Seção` duas vezes (o sintoma do cabeçalho engolido) e
  lista de `## [x.y.z]` que não desce estritamente. Provado contra o CHANGELOG
  anterior (reprova) e contra o corrigido (passa).
- **Release automática por versão do `plugin.json`** (`.github/workflows/release.yml`).
  Merge em `main` que muda o `plugin/.claude-plugin/plugin.json` cria a tag
  anotada `v<version>` e a GitHub Release com o bloco daquela versão do
  CHANGELOG como corpo (`.github/scripts/changelog-bloco.sh`, com teste). A
  instalação pelo marketplace nunca dependeu de tag — o cache do Claude Code é
  chaveado pelo `version` — mas a última release feita à mão foi a `v0.7.0`, e
  o badge do README parou nela enquanto o plugin ia a `0.19.0`. Reexecutar não
  duplica: tag e release que já existem são mantidas. Nenhuma action de
  terceiro além do `actions/checkout`.

## [0.19.0] — 2026-09-03

Lote de desempenho: o que o kit roda a cada ação, medido em 03/09/2026, e o que
ele carrega em toda request.

### Performance
- **O dispatch do dotcontext saiu do `PostToolUse`.** Rodava depois de todo
  `Write`, `Edit` e `Bash`: 1,27 s por chamada para devolver `{"continue":true}`
  sem tocar arquivo nenhum (testado com payload completo em dois projetos). Só o
  `SessionStart` injeta algo útil (~1 KB de contexto do `.context/`), e é o único
  que fica.
- **O `SessionStart` do dotcontext virou `plugin/hooks/dotcontext-session.sh`, e
  só dispara em projeto com `.context/`.** Em repositório git SEM a pasta, o
  `hook dispatch` do dotcontext 1.1.1 sai varrendo o repo e não volta em menos de
  10 s (130–150% de CPU em três repos reais; em pasta vazia, `git init` novo ou
  repo com `.context/` responde em 0,2–0,6 s) — o hook estourava o teto de 60 s e
  toda sessão aberta num projeto sem dotcontext esperava um minuto para receber
  o aviso "this repository does not have .context/ yet". O CLAUDE.md do kit já
  ensina o `init the context`; o aviso não pagava o minuto. Com `.context/`, o
  hook usa o binário global `dotcontext` quando existe (~0,6 s) e cai para o
  `npx` pinado quando não (~1,3 s). Prova: `tests/test-dotcontext-session.sh`
  (sem `.context/` não chama; com, chama uma vez, pelo binário, com o payload
  intacto; sem binário, `npx -y @dotcontext/cli@1.1.1`).
- **O `notify-stop.sh` consulta o dispositivo de áudio uma vez a cada 10 min.**
  O `system_profiler SPAudioDataType` rodava em todo `Stop` (1 a 3 s) só para
  escrever no log para onde o som foi. O resultado fica em
  `~/.claude/.cache/notify-stop/output-device`, com idade checada por
  `find -mmin` (igual no macOS e no Linux). Medido: 0,43 s → 0,02 s por turno. O
  som e a notificação não mudam. Prova: `tests/test-notify-stop-cache.sh`, com um
  `system_profiler` falso que conta as chamadas.
- **Descriptions enxutas.** A description de cada skill entra em toda request,
  use-se a skill ou não. `git-sync` 1.069 → 459 chars (a de 0.18.0 listava 14
  gatilhos e repetia o corpo), `find-docs` 919 → 289 (e em pt-BR — estava em
  inglês), `diretor-imagem` 540 → 389, `guardrails-ia` 578 → 503,
  `auditoria-seguranca` 604 → 509. `grilling` cresceu de propósito (286 → 440)
  para dizer quando NÃO disparar. Soma das 18 skills: 8.924 → 7.517 chars.
  Nenhum gatilho de uso real saiu.

### Alterado
- **`diretor-imagem` só dispara para prompt de imagem/vídeo.** A description
  antiga, em inglês, ativava a skill em `"um prompt"` e `"comando"` — e cada
  disparo indevido carregava 65 KB de corpo. Os gatilhos agora são "prompt de
  imagem", "prompt de vídeo", "gerar imagem", "direção de arte", nano
  banana/Kling/Midjourney ou foto colada pedindo prompt; título e persona
  passaram a "Diretor de imagem" (o apelido Banana fica como apelido).
- **`grilling` não dispara mais por vagueza.** A description dizia "use quando o
  pedido é vago" e o interrogatório abria em tarefa de cinco minutos. Agora
  aciona em implementação GRANDE (multi-sistema, schema/auth/infra,
  irreversível) e ganhou a seção sobre ancorar o loop em `.context/docs` quando o
  projeto tem dotcontext. Portado do kit do time.
- **`grill-with-docs` ganhou `disable-model-invocation: true`.** A description
  já dizia que é manual; agora o Claude Code também sabe.

### Adicionado
- **`~/.claude/.keep-local`: o que é seu, o `kit-setup.sh` não remove.** A
  limpeza da instalação antiga lê o `.kit-manifest` e apaga o que está listado —
  inclusive a skill do kit que você editou e o script seu com nome igual. O
  arquivo é um caminho por linha, relativo a `~/.claude`, `#` comenta, glob
  simples (`skills/meu-*`; pasta listada protege o que está dentro). Protege
  contra remoção, não contra instalação: `agents.md` e a barra continuam sendo
  atualizados. Documentado no README, em `docs/migrar-do-install-antigo.md` e na
  skill `setup`.
- **Rotação de backups: ficam os 3 `backup-kit-<data>/` mais recentes.** Antes
  cada execução do setup criava um e nenhum saía. Prova das duas coisas:
  `tests/test-kit-setup-keep-local.sh` (fantasma sem `.keep-local` sai, com fica,
  glob funciona, 5 execuções deixam 3 backups — os mais novos).

### Corrigido
- **`install.sh` anunciava "2 comandos"; o plugin tem 3** (`atalhos`,
  `explicar`, `revisar`). Agora conta a pasta, como já fazia com as skills.
- O teste do cleanup do `git-sync` citava um repositório interno pelo nome.
- `docs/programacao-avancada-com-claude.md` dizia que os hooks vinham do
  `settings.json`; vêm do plugin, e a seção agora lista os que existem e o que
  cada um custa.

## [0.18.0] — 2026-09-03

### Segurança
- **O gate de RLS da skill `baseline` só enxergava o schema `public`.** O regex
  que extrai o nome da tabela tinha `(public\.)?` na frente, então
  `create table vendas.pedidos` era lido como a tabela "vendas". Duas
  consequências, e a segunda é a grave: tabela COM RLS fora de `public` era
  acusada de estar sem (o schema nunca aparece do lado do `alter table … enable
  row level security`); e numa migration com `create table crm.agendamentos`
  sem RLS e `alter table crm.leads enable …`, os dois lados viravam "crm" e se
  cancelavam — a tabela aberta passava calada e o gate do `/ship` rodava verde.
  Agora qualquer `schema.` é aceito e o que se compara é o nome da tabela.
  Portado do kit do time. Prova, na mesma migration: antes acusava
  `aberta crm vendas` (dois schemas, e `agendamentos` não aparece); depois,
  `aberta agendamentos` — exatamente as duas sem RLS.

### Corrigido
- **Caminhos que não existem em instalação pelo marketplace.** `baseline`
  (SKILL.md e `references/02-banco.md`) e `git-sync` mandavam rodar os scripts
  em `~/.claude/skills/…`, onde só a instalação antiga pelo `install.sh` deixava
  arquivo; instalado como plugin, a skill mora dentro do plugin. Os comandos
  passam a usar `${CLAUDE_PLUGIN_ROOT}` (o Claude Code preenche ao carregar a
  skill) com o caminho antigo como fallback, e o `collect.sh` descobre a própria
  pasta para montar o comando de reconferência que sai em cada finding — antes
  ele apontava para um arquivo inexistente.
- **`verify` não é skill deste kit.** O `CLAUDE-global.md` e a `verificacao`
  roteavam "antes de dizer pronto" para uma skill `verify` que não existe em
  lugar nenhum. Agora só `verificacao`.

## [0.17.3]

### Corrigido
- **O aviso de fim de turno rodava em background e podia morrer com o hook.** O
  `Stop` era `afplay ... & exit 0` inline: em background o aviso só sai se o
  processo sobreviver ao fim do hook, e quando o harness encerra o processo do
  hook o filho morre junto no mesmo grupo — sem erro e sem som. Agora o hook chama
  `plugin/hooks/notify-stop.sh`, que toca em foreground com teto (`afplay -t 1.2`)
  e escreve uma linha por turno em `~/.claude/logs/notify-stop.log`.
- **O log registra o dispositivo de saída, que é a causa mais comum do silêncio.**
  Com um fone Bluetooth pareado o `afplay` devolve 0 e o som vai para o fone: o
  sintoma é idêntico ao de "o hook não disparou", e sem o log não havia como
  separar os dois. `CLAUDE_STOP_QUIET=1` silencia sem editar o plugin.

## [0.17.2]

### Corrigido
- **Launcher na frente do `git` faz o guard do worktree recusar o comando.** A
  skill `worktrees` já listava as recusas por casamento de texto, mas faltava a
  que ninguém liga à causa: o guard só sabe ler `git` como **primeiro token**, e
  um hook de PreToolUse que prefixa comandos esconde o git. A recusa muda de
  texto para *"runs `<launcher>` with a git command among its operands: what runs
  it … cannot be read here"*, e o comando não roda — um `git add` de um arquivo
  só para de funcionar. Este kit não tem hook assim; a linha existe para quem
  instala o seu. Espelho de `claude-config-team#114`, onde o hook do RTK causava
  isso na prática (03/09/2026).

## [0.17.1]

### Corrigido
- **A skill `worktrees` descrevia mal o guard do harness.** Ela listava heredoc
  grande e laço artesanal como os gatilhos da recusa *"too complex to verify
  that it stays inside the worktree"* — e quem lê conclui que comando simples
  passa. Não passa: a detecção é casamento de **texto**, então a substring `git`
  dentro de `githubCommitSha` faz um `curl` à API da Vercel ser recusado como
  comando git, e o colchete de uma rota dinâmica (`.../[id]/route.ts`) num
  comando composto vira "construct too complex". Um terceiro caso não estava
  documentado: `cd` para **outro repositório** também é recusado — de dentro de
  um worktree não se mexe em outro repo, nem para ler o status. Cada linha nova
  da tabela vem com o contorno correspondente.

## [0.17.0]

O que sobrou da leitura do `AlbertoGRB/dev-kit` (um agregador de superpowers,
gstack e ponytail) depois de cruzar com o que o kit já faz. Cinco ideias
pequenas; nada de roteador novo nem de skill de 1.800 linhas.

### Adicionado
- **`/kit-vamoo:atalhos` e a convenção `// atalho: <teto>; <quando revisitar>`.**
  Quando você (ou o Claude) simplifica de propósito — um lock global, ler o
  arquivo inteiro em memória, deixar sem índice — a simplificação ganha uma marca
  no código dizendo até onde aguenta e quando voltar. O comando lista todas em
  uma tela e aponta as `[sem-gatilho]`, que são as que viram "depois" pra sempre.
  A regra entrou no `CLAUDE-global.md` (ao lado de "não over-engineer").
- **Skill `baseline`, `02-banco.md`: "Migration que não derruba produção".**
  A checklist do que quebra um banco com dado mesmo com RLS perfeita: NOT NULL
  antes do backfill, índice em tabela viva sem CONCURRENTLY, DROP ou RENAME de
  coluna que o código em produção ainda lê, e a ordem entre schema e código. A
  regra de caminho de `supabase/migrations/` e o passo de deploy do `ship`
  passam a apontar pra ela.
- **Skill `verificacao`, duas referências e um script.** `qa-taxonomia.md` dá
  o formato do veredito de QA (severidade em quatro níveis, sete categorias,
  checklist por página, e a contagem do que foi coberto — "nenhum achado" sem
  contagem é relatório vazio). `testes-flaky.md` cobre as duas causas que mais
  voltam em teste instável: esperar tempo em vez de condição, e um teste que
  suja o estado de outro — com `scripts/find-polluter.sh`, que roda os arquivos
  um a um e para no culpado.

- **`plugin/scripts/skill-pressure-test.sh` + `tests/skills/` + `docs/testar-skills-sob-pressao.md`.**
  Teste pra skill de disciplina, como se fosse código: um cenário com três ou
  mais pressões (prazo, autoridade, evidência parcial) roda **sem** a skill
  (`--baseline`) e **com** a skill do plugin no system prompt (`--com-skill`), e
  o runner compara a letra escolhida com a esperada. Três cenários entram (dois
  da `verificacao`, um da `worktrees`). Honestidade: no `haiku` eles passam
  também sem a skill, então hoje são regressão, não prova — o doc diz o que
  falta pra virarem prova. Serve pra quem cria as próprias skills e quer saber
  se a regra segura quando o Claude tem motivo pra furar.

### Alterado
- **`/kit-vamoo:revisar` e o `agents.md`: revisor separa o que é mecânico do que
  é decisão.** Cada achado sai marcado `[mecânico]` (um sênior aplicaria sem
  discutir: dead code, N+1, número mágico) ou `[decisão]` (segurança, race,
  remover funcionalidade, mudança visível). "Aplica os mecânicos" vira um pedido
  seguro. E quatro categorias que revisor costuma pular entram sempre: valor
  novo de enum/status (ler TODOS os consumidores fora do diff), saída de IA que
  vira dado, ler-e-depois-gravar sem atomicidade, e migration.
- `.gitignore` passa a ignorar `.claude-worktrees/`, onde as sessões do Claude
  criam worktrees dentro do repositório.

## [0.16.0]

### Adicionado
- **Skill `worktrees`: o banco local não é isolado por worktree.** O worktree
  isola os arquivos; o banco de desenvolvimento é **um só na máquina**,
  compartilhado por todos eles — a migration que você roda num worktree aparece
  no banco que o outro está usando. E o sintoma não é erro de banco: é um
  `git push` recusado por um gate que compara o schema do código com o schema
  vivo, reprovando por um motivo sem relação com o que você mexeu. Entrou o que
  fazer em ordem, com o aviso que mais importa: **nunca resetar o banco para
  "limpar"** — isso apaga as migrations de quem está trabalhando ao lado.

## [0.15.0]

### Adicionado
- **Hook `path-rules`**: a regra do caminho entra no contexto quando o arquivo
  aparece, uma vez por sessão, sem bloquear nada. Regra escrita no `CLAUDE.md`
  custa contexto em **toda** request da sessão, usada ou não — "migration é
  irreversível" não interessa em nenhuma sessão que não toca migration.
  As regras ficam em `plugin/hooks/path-rules.conf`, no formato `glob | texto`,
  e o arquivo é feito pra você acrescentar as suas: é o lugar de "no MEU projeto,
  quando mexer em X, lembre de Y". Nasce cobrindo `.env`/`.env.local`,
  migrations, edge functions, `settings.json` e `package.json`.
  Teste em `tests/test-path-rules.sh`, provado contra um hook quebrado antes de
  entrar.

## [0.14.0]

### Adicionado
- **Skill `auditoria-seguranca`**: auditoria em 5 categorias — isolamento de
  inquilino, permissão decidida no navegador, IDOR, chaves expostas e XSS — que
  sai como **PDF em pt-BR dentro do repo auditado + issues prontas pra colar**.
  Detecta a stack antes de auditar, então funciona em projeto que não é Supabase.
  O gerador do PDF não tem dependência: stdlib do Python + um Chromium já
  instalado. Não substitui o `secscan`: aquele varre e entrega Markdown fora do
  repo, este é o pacote de entrega pra outra pessoa ler e agir.
- **Pilar 08 do `baseline` — perímetro e superfície exposta.** Os sete pilares
  olhavam para dentro do app; nenhum perguntava o que responde na internet com o
  nome do projeto. Inventário de hosts, headers em **toda** borda (não só a
  Vercel), painel de infra fora do domínio principal e atrás de allowlist,
  versão não publicada, saúde detalhada autenticada, repositório privado
  conferido.
- **Força bruta em autenticação no pilar 04.** O pilar define o gatilho como
  "custa alguma coisa" — e tentar senha não custa nada, então o endpoint mais
  atacado escapava por construção. Entrou limite por IP **e** por identidade,
  escalada de resposta (atraso → desafio → bloqueio) e paridade de mensagem
  entre conta que existe e conta que não existe, que é a metade esquecida
  (enumeração de usuário entrega a base de e-mails sem descobrir uma senha).

## [0.13.0]

### Adicionado
- **Teste de coerência de versão** (`tests/test-versao-changelog.sh`). São quatro
  lugares que precisam dizer a mesma coisa — `plugin.json`,
  `plugin/scripts/kit-setup.sh`, `install.sh` e o topo do CHANGELOG — e o CI só
  comparava os três primeiros. O teste cobre o CHANGELOG e pega **versão
  repetida**, que é o sintoma de dois PRs bumpando para o mesmo número: o git
  auto-mergeia linha idêntica, o segundo bump vira no-op e o kit anuncia uma
  versão que já saiu. Na v0.12.0 uma variante disso passou: o bump esqueceu o
  `kit-setup.sh` porque quem bumpou procurou o arquivo na raiz e ele mora em
  `plugin/scripts/`.
- **Skill `worktrees`: o que fazer quando o Claude recusa um comando** com "too
  complex to verify that it stays inside the worktree". É guard do harness, não
  bug: heredoc grande, `&&` encadeado e `cd` pro clone caem nele. Entrou a tabela
  de trocas (heredoc → `Write`, patch → `Edit`) e a regra de parar na segunda
  recusa idêntica em vez de reescrever o mesmo comando.

## [0.12.0]

### Corrigido
- **Materialized view era ponto cego do `secscan` e do `baseline`.** Uma auditoria
  real em 01/09/2026 achou 904 linhas de 16 workspaces de clientes legíveis **sem
  nenhum login**, por uma MV — e `materialized` não aparecia em nenhuma das duas
  skills. MV **não tem RLS**: não existe policy que a proteja, e o
  `GRANT ALL ON ALL TABLES IN SCHEMA public` do Supabase (certo para tabela, onde
  a RLS decide a linha) é, para MV, o acesso. Quem cria a primeira MV pra montar
  um dashboard não tem como saber que publicou a tabela inteira. Entrou a sonda
  (`relkind='m'` + `has_table_privilege`) com prova pela porta do atacante, mais
  o item de contrato no `02-banco.md`, antes do item de RLS.
- `.worktrees/` no `.gitignore` — estava untracked e a um `git add -A` de virar
  commit.

## [0.11.0]

### Adicionado
- Skill **`guardrails-ia`**: os guard-rails de um agente que fala com pessoa real. Os dois
  erros que teste de fluxo não pega — a IA afirmar o que a empresa não sustenta, e continuar
  falando com quem mandou parar — não aparecem como erro no log, aparecem como conversa
  normal. O que está ali: alegações numa allowlist verificada, que entra no prompt **e**
  filtra a saída (prompt pedindo "não invente" vaza por paráfrase); `nao_contatar` como
  estado permanente, checado na montagem da fila e de novo antes do envio; `precisa_humano`
  com destino real; e **propriedade de canal — quem responde não é quem grava**: o guard de
  pausa antes do nó que grava o inbound apaga do banco tudo que o cliente escreve enquanto
  o humano conduz.
- Skill **`baseline`**: teto de gasto acumulado de IA consultado antes da chamada, com pausa
  (pilar 04 — rate limit é por identidade, e worker autônomo não tem usuário; o limite dele
  é dinheiro); tabela `ai_calls` com custo atribuível a lead/conversa/cliente (pilar 06 —
  gasto total é fatura, custo por lead é decisão); config de negócio num arquivo único e
  gitignored, com `.example` espelhado (pilar 07).
- Skill **`verificacao`**: efeito colateral externo tem três degraus — simulado, **dry-run
  com o envio final bloqueado** e smoke real autorizado. Sem o degrau do meio, o primeiro
  exercício do caminho real é o disparo em produção.
- Skill **`orquestracao`**: cláusula de degradação em sandbox — ambiente que não alcança a
  dependência implementa, testa contra fake e declara o que não foi verificado, em vez de
  travar o projeto ou fingir que testou.

## [0.10.7]

### Corrigido
- **O guard de commit em main lia o path CRU do comando.** O shell expande `~` e `$VAR`
  antes de o git ver o path; o hook, não — então ele decidia pelo repo errado, nas duas
  direções. `cd ~/projetos/meu-worktree && git commit` e `W=/x; git -C $W commit`
  **bloqueavam commit legítimo** (o hook caía no diretório da sessão, que estava em main),
  e o inverso é pior: com a sessão numa feature branch, `W=<repo-em-main>; git -C $W commit`
  **deixava o commit em main passar**. Agora o hook reproduz as duas expansões antes de
  resolver o repositório — variável só quando o próprio comando a atribui, que é o único
  valor que ele pode conhecer; sem isso o path segue cru e cai no diretório da sessão,
  que é a falha segura.
  Junto vieram as correções que o kit do time já tinha e este não: path entre aspas na
  detecção do commit, `git -C`/`cd` lidos até a aspa de fechamento (path com espaço) e
  path que não resolve como repositório não virar passe livre.
  A suíte `tests/test-block-main-commit.sh` passou a ser a mesma do kit do time:
  22 casos, **11 vermelhos** na versão anterior deste hook.

## [0.10.6]

### Adicionado
- Skill **`bot-discord`**: bot de Discord em Node/TypeScript hospedado em VPS própria, do
  Developer Portal ao container rodando. Nasceu de um bot que está em produção há meses —
  o que está escrito ali é o que quebrou na prática, não o que costuma aparecer em tutorial:
  a intent de conteúdo de mensagem que fica desligada no portal e deixa o bot online e mudo
  **sem erro nenhum**; o `dotenv` que precisa carregar antes do import da aplicação porque
  import ES é *hoisted*; o `COPY` seletivo no Dockerfile que builda verde e mata o container
  no boot; e o gate de idempotência sem o qual mensagem editada, restart e reação re-notificam
  a equipe inteira. A skill obriga a conferir o log de boot depois do deploy: build verde não
  é prova de que o bot subiu.
  Estrutura: `SKILL.md` com as perguntas iniciais, as armadilhas caras e o gate de verificação;
  as três references (`01-portal-discord`, `02-codigo-base`, `03-deploy-vps`) carregam sob demanda.

## [0.10.5]

### Documentação
- `ship`: como esperar o CI sem torrar contexto. O caminho que parece natural — deixar
  um comando com `--watch` num monitor de eventos — custa caro: ele redesenha a tabela
  inteira a cada poucos segundos, e cada redesenho acorda a sessão, que relê a conversa
  toda. Medido no kit do time em 01/09/2026: ~40 despertares num único deploy, nenhum
  com informação nova. Em background (`run_in_background`) o mesmo comando dá uma
  notificação, no fim, e `--fail-fast` aborta no primeiro check obrigatório vermelho.

## [0.10.4]

### Corrigido
- `git-sync --cleanup-apply` limpava **zero** em repo com squash merge. Ele decidia por
  ancestralidade em dois pontos (`branch -d` e `merge-base --is-ancestor`), e squash nunca
  faz o commit da branch virar ancestral de `main` — então trabalho já publicado aparecia
  como "não mergeado" e nada era removido. Agora a ancestralidade segue sendo o primeiro
  teste e o `gh pr list --head` entra quando ela falha: PR mergeado vira `-D` citando o
  número, ausência de PR vira skip avisando que pode haver trabalho exclusivo, e sem `gh`
  o comportamento antigo volta inteiro. O dry-run mostra a intenção de `-D` antes de você
  aprovar.
- `git-sync` tratava worktree `locked` como sessão viva sempre. O motivo do lock traz o pid
  e fica pra trás quando a sessão morre, imunizando o worktree para sempre; agora confere
  com `kill -0` e só destrava o morto, no apply. Sem pid legível, assume vivo.
- `tests/test-git-sync-cleanup.sh` cobre os dois, mais o caso em que o cache de PR vazaria
  entre branches — o bash 3.2 do macOS degrada `declare -A` calado para array indexado, e
  uma branch sem PR herdaria o número da última consultada.

## [0.10.3] — 2026-08-31

### Documentado

- **Atualizar o kit não é automático, e isso não estava escrito.** O Claude Code
  desliga o auto-update para marketplaces de terceiros — este kit é um deles.
  O README dizia só `/plugin update kit-vamoo`, o que dá a entender que basta
  lembrar de rodar. Agora a seção **Atualizar depois** traz os dois caminhos: ligar
  o auto-update de uma vez (`/plugin` → Marketplaces → vamoo-ai → Enable
  auto-update) ou atualizar na mão, com os três comandos na ordem certa —
  `marketplace update` re-lê o catálogo, `plugin update` baixa, `/reload-plugins`
  aplica sem reiniciar.
- **O que o auto-update não faz.** Ele não toca no que veio do `/kit-vamoo:setup`
  (CLAUDE.md global, barra de status, preferências), porque um plugin não consegue
  declarar essas chaves. E o aviso de versão nova só aparece dentro do menu
  `/plugin` — quem nunca abre, nunca vê.
- **Para quem mantém o kit:** o `version` do `plugin.json` é a chave do cache. Sem
  bump, ninguém recebe a mudança, nem com auto-update ligado. Está escrito no
  README e no topo deste arquivo.
- **Migração da instalação antiga** ganhou doc próprio na v0.10.2
  (`docs/migrar-do-install-antigo.md`), com prompt pronto para colar no Claude.

## [0.10.2] — 2026-08-31

### Adicionado

- **Regra: artefato só quando você pedir com essa palavra.** O Claude às vezes
  decide publicar um Artifact por conta própria, porque julga que o resultado
  "merece uma página" — e aí o seu relatório vira um link em vez de um arquivo
  no projeto, fora do alcance do `grep` e do git. Agora o `CLAUDE-global.md`
  diz explicitamente que relatório, plano e análise vão pro terminal ou pro
  repositório, e que artefato só sai quando você pedir ("artefato", "publica
  isso", "faz uma página").

## [0.10.1] — 2026-08-31

### Corrigido

- **Ligar o modo bypass desarmava o check-careful em silêncio.** Em
  `bypassPermissions` o hook se cala de propósito (ali o `ask` não freia subagent
  nem workflow, então ele vira só interrupção) — mas quem ligava o modo não
  tinha como saber disso, e continuava trabalhando achando que a rede de
  proteção estava lá. Agora o primeiro comando da sessão traz um aviso dizendo
  que o hook está desligado, que quem protege nesse modo é o `permissions.deny`,
  e como trazer as confirmações de volta (`CAREFUL_ON=1`). **Uma vez por sessão,
  nunca mais** — repetir a cada comando seria exatamente a interrupção que a
  recalibração de agosto existiu para remover. Coberto por dois casos novos em
  `tests/test-check-careful.sh`.

### Adicionado

- **Cinco arquivos de credencial a mais no `permissions.deny`**, todos de
  caminho fixo e leitura rara: `~/.config/gh/hosts.yml` (token do GitHub em
  texto claro), `~/.netrc`, `~/.npmrc` do home (o `.npmrc` **de projeto**
  continua livre — é onde mora `legacy-peer-deps` e é lido o tempo todo),
  `~/.docker/config.json` e `~/.config/op/**`. A escolha não foi por intuição:
  cada padrão foi medido contra 30 dias de comandos reais antes de entrar, e o
  que tinha uso legítimo ficou de fora.

## [0.10.0] — 2026-08-30

### Corrigido

- **A skill de memória mandava você rodar um comando que mente.** A linha que
  descobre se este projeto já está ligado montava o nome do diretório trocando
  só `/` e espaço por `-`. Só que o Claude Code troca **todo** caractere fora de
  `[a-zA-Z0-9]` — ponto, `_`, `+`, tudo. Resultado: acerta no clone e erra em
  **todo worktree**, porque o caminho de um worktree tem `.claude`/`.worktrees` e
  o ponto ficava intacto. O `readlink` volta vazio, e a tabela logo abaixo lê
  vazio como "não adotado" — a skill dizia que a memória não estava ligada num
  projeto que estava. O mesmo arquivo já explicava por que essa forma é errada,
  na tabela de armadilhas: o comando contradizia a própria skill.

  A forma correta é a que os scripts do kit (`memoria-link.sh`,
  `memoria-worktree-link.sh`) já usavam: `printf '%s' "$PWD"` em vez de `pwd`
  (que emite uma quebra de linha, e a quebra viraria mais um `-` no fim, gerando
  um slug que não existe em lugar nenhum) e um `sed` cortando o `-` final.

- **`find-docs` mandava reinstalar o `ctx7` global antes de cada consulta.**
  Agora só instala se faltar (`command -v ctx7 >/dev/null || npm install -g …`).
  Um `npm install -g` por pergunta de documentação é tempo e rede que ninguém
  pediu.

### Adicionado

- **O `secscan` passa a fechar com um checklist de 7 linhas que não dá para
  omitir.** Antes o relatório listava o que foi achado — e categoria nenhuma
  investigada saía do relatório sem deixar rastro, o que um iniciante lê como
  aprovação. Agora toda execução imprime as sete categorias (C1 injeção · C2
  auth · C3 exposição de dado · C4 validação de entrada · C5 dependências · C6
  configuração · C7 cripto e armazenamento) com um de quatro estados: `N
  achado(s)`, `nenhum problema identificado`, `não medido (<ferramenta>
  ausente)` ou `não aplicável (<motivo>)`. Ferramenta que não rodou vira **não
  medido**, nunca limpo. Junto vêm o bloco de sugestões que proíbe correção
  genérica ("valide o input" não é correção, é o problema repetido) e a Fase 7,
  que registra o que o modo pedagógico **não** simplifica: o checklist.
- **Sonda de validação de entrada na Fase 3 do `secscan`** — sem ela a linha C4
  do checklist sairia "não medido" em toda execução. Cobre handler que usa
  `body`/`query` sem schema, valor de dinheiro/permissão/identidade vindo do
  cliente e `{ ...body }` espalhado no update (mass assignment).
- **`verificacao`: como diagnosticar CI vermelho.** Pegue a mensagem literal
  (`gh run view <id> --log-failed`; se você já rerodou e passou, ela só existe na
  tentativa 1, via `gh api`) **antes** de olhar o diff — é onde mais se inventa
  causa plausível e errada. E as três condições para chamar um teste de instável:
  não está no seu diff, passa localmente e o rerun fecha verde. Duas não bastam.
- **`handoff`: a memória do projeto sai junto.** O handoff conta uma frente de
  trabalho; a memória guarda o que sobrevive a ela. A skill agora pede o
  `git status --short .context/memoria/` antes de fechar, manda apagar o fato que
  se provou errado, marcar hipótese como hipótese, e transformar em memória o que
  este handoff descobriu e vai valer daqui a um mês.
- **Proveniência nas 13 skills derivadas.** Cada uma diz de qual skill do repo do
  time ela saiu, com o convite explícito de registrar ali o que diverge de
  propósito e por quê. Fork silencioso é como o kit ficou publicando um bug que o
  time já tinha corrigido — a linha existe para o drift ficar visível na próxima
  leitura, não seis meses depois.

## [0.9.0] — 2026-08-30

### Corrigido

- **O hook `check-careful` para de perguntar no que tem undo.** Ele interrompia demais, e
  interrupção demais faz a pessoa desligar o guard-rail inteiro — o pior desfecho possível.
  Recalibrado contra 75.184 comandos reais de 30 dias replayados contra o hook: dos 303
  disparos, sobram 100 (e zero em modo bypass). O que saiu era quase tudo operação **com
  undo** — `git push --force-with-lease` (que já recusa se o remoto andou), `git rm -r`
  (volta com `git restore`), `rm -rf` de path relativo dentro de repo git, `cat > x.sql`
  escrevendo SQL sem executar, `supabase db reset` local, `git add -A` dentro de worktree.
- **`block-main-commit` quebrava com aspas no path, nos dois sentidos.** `cd "$W" && git
  commit` dentro de worktree era bloqueado (o hook caía no cwd da sessão), e
  `git -C "$W" commit` num repo em main PASSAVA (o path era capturado com as aspas e o git
  não resolvia — falha aberta num hook que existe pra fechar). Aspas é a prática certa:
  sem elas, path com espaço no nome nem funciona. Entra `tests/test-block-main-commit.sh`,
  que o hook não tinha: 14 casos, 6 falhas contra a versão anterior.
- **Em `bypassPermissions` o hook se cala.** Nesse modo o `ask` não freia subagent nem
  workflow, então ele não era controle — era só interrupção. Quem protege em bypass é
  `permissions.deny`, que vale em todo modo. `CAREFUL_ON=1` traz o hook de volta;
  `CAREFUL_OFF=1` como prefixo do comando desliga pontualmente (mesmo idioma do
  `HOTFIX_MAIN=1`).

### Segurança

- **A barra de status executava o nome da branch.** `plugin/scripts/statusline.js` montava
  `execSync('gh pr list --head ' + branch)` por concatenação, e nome de branch aceita
  metacaractere de shell: `x$(touch${IFS}/tmp/x)` é ref válida no git. Dar checkout numa
  branch vinda de PR de terceiro bastava pra rodar comando arbitrário na sua máquina.
  Agora usa `execFileSync` com argv separado, que não passa por shell.
- **`npx @dotcontext/cli@latest` sem pin** rodava a cada Write/Edit/Bash: qualquer
  publicação futura, inclusive comprometida, executaria aí. Pinado em `1.1.1` (junto do
  `@dotcontext/mcp` no `.mcp.json`).
- **Nova regra de exfiltração**: comando de rede (`curl`/`wget`/`scp`/`rsync`) carregando
  credencial no próprio segmento agora pede confirmação. Nada barrava isso — o
  `permissions.deny` só cobre a ferramenta `Read`, não o Bash.
- **`deny` do template ganha chave privada e certificado** (`~/.ssh/**`, `id_rsa*`,
  `id_ed25519*`, `*.pem`, `serviceAccountKey.json`). Chega em quem já instalou: o
  `merge-settings.js` acrescenta `deny` por união.

### Melhorado

- `hookjson.js` lê vários campos numa chamada só — eram 3 startups de node por comando
  Bash — e não estoura mais stack trace quando o pipe fecha antes (`| head`).
- `tests/test-check-careful.sh` reescrito a partir do corpus medido: 39 casos, e falha 16
  vezes contra a versão anterior do hook (prova de regressão).

## [0.8.1] — 2026-08-29

### Corrigido

- **Barreira de segurança nova não chegava em quem já tinha o kit.** O merge do
  `settings.json` unia só `permissions.allow` — `deny` e `ask` ficavam de fora.
  Na prática: quem instalou o kit meses atrás recebia toda permissão nova e
  nenhuma proteção nova, calado. Agora as três listas são união. Foi assim que
  os 7 `deny` da 0.8.0 (`.env`, `supabase login`/`link`/`db push`,
  `vercel login`) não chegaram sozinhos em quem já era usuário.

### Mudado

- **O instalador passou a dizer o que não mexeu.** Se o seu
  `permissions.defaultMode` é diferente do recomendado pelo kit, ele mantém o
  seu — como sempre fez — mas agora **avisa** e mostra como trocar, em vez de
  ficar mudo. Preferência sua continua sendo sua; o que muda é você saber que
  existe uma recomendação diferente.
- O merge saiu de dentro do `kit-setup.sh` e virou
  `plugin/scripts/merge-settings.js`, que dá para testar sozinho. Antes só era
  possível exercitá-lo rodando o instalador inteiro contra o `~/.claude` de
  verdade.

### Adicionado

- `tests/test-merge-settings.sh`, no CI: 11 casos cobrindo os dois lados — o que
  o kit precisa entregar (deny, allow em união, chave nova) e o que é seu e não
  pode ser tocado (tema, barra de status, permissão própria, modo de permissão),
  mais idempotência e `settings.json` inválido. Falha em 3 contra o merge da
  0.8.0.
- **Guard de versão no CI**: mexeu em `plugin/` e não subiu a `version` do
  `plugin.json`, o CI barra. O Claude Code usa esse campo para decidir se baixa
  a atualização — publicar sem bumpar deixa quem já instalou com a cópia em
  cache, sem erro e sem aviso.

## [0.8.0] — 2026-08-29

### Corrigido

- **O Claude pedia autorização o tempo todo — e pedia até no modo bypass.** São
  duas causas independentes, as duas resolvidas aqui.

  A primeira: um hook `PreToolUse` que responde `ask` **passa por cima do modo
  bypass**. O `check-careful` tinha três regras com falso positivo, e a pior era
  a de `git push --force`: ela procurava `git push` e `-f` no comando inteiro,
  sem `case`, então `git commit -F - <<EOF && git push` — o jeito normal de
  escrever uma mensagem de commit — disparava. Medido nos transcritos de quem
  usa o kit todo dia: **139 interrupções indevidas em 14 dias, 89% delas por
  esse `-F`**. Agora o flag só conta dentro do trecho do push. Junto: `rm -rf
  .next` parou de perguntar (a lista de pastas descartáveis exigia barra no
  fim) e `git add -A src app` também (tem caminho explícito, não é "add
  amplo").

  A segunda: a lista de permissões do template tinha **12 entradas**, e o modo
  era `default` — ou seja, quase todo comando e toda edição de arquivo parava
  pra perguntar. Agora são **85 permissões** (inspeção do repo, git e gh só de
  leitura, npm/npx/bun/pnpm, type-check, lint e teste) e o modo é
  `acceptEdits`: o Claude edita arquivo sem perguntar, mas `git commit`, `git
  push`, `gh pr merge` e qualquer comando fora da lista continuam pedindo.

### Segurança

- **`deny` no template** (não existia): `.env`, `.env.local` e variantes fora do
  alcance da ferramenta Read, e `supabase login` / `supabase link` / `supabase
  db push` / `vercel login` bloqueados — login interativo trava a sessão e
  `db push` empurra migration sem revisão.
- **`check-careful` agora pega leitura de `.env` pelo terminal** (`cat`,
  `head`, `base64`…). O `deny` acima cobre só a ferramenta Read; pelo Bash a
  credencial entraria no contexto assim mesmo. Append (`cat >> .env`) não conta,
  é escrita.

### Adicionado

- `tests/test-check-careful.sh` — 25 casos tirados de comandos reais, rodando no
  CI. Falha em 14 contra o hook anterior; passa inteiro no novo. Aceita um
  caminho de hook como argumento, pra rodar contra a versão antiga e ver a
  diferença.

## [0.7.0] — 2026-08-24

### Instalar deixou de precisar de terminal

O kit virou um **plugin do Claude Code**. Instalar agora são três coisas
digitadas dentro do próprio Claude Code — sem clonar repo, sem rodar script, sem
`claude mcp add`:

```
/plugin marketplace add VAMOO-AI/claude-kit-mentorados
/plugin install kit-vamoo@vamoo-ai
/kit-vamoo:setup
```

O terceiro passo existe por um limite técnico, não por preguiça: o
`settings.json` de um plugin só aceita as chaves `agent` e `subagentStatusLine`,
então CLAUDE.md global, barra de status, idioma e permissões **não cabem num
plugin**. A skill `setup` instala essa parte e ainda ajuda a preencher o
CLAUDE.md com os seus dados, na conversa.

O `install.sh` continua, agora como caminho alternativo — ele faz exatamente os
mesmos três passos a partir de um clone local (útil sem rede, ou numa aula).

### Adicionado

- **Skill `memoria-projeto`** — tira a memória do projeto da sua máquina e põe
  dentro do repositório, em `.context/memoria/`. O Claude Code guarda o que
  aprende em `~/.claude/projects/<slug>/memory`, que é local: troca de
  computador e some, e quem mais trabalha no projeto nunca vê. A skill cria a
  pasta versionada, liga o diretório do harness nela e migra o que estava preso
  na máquina.

  O gate que vale a pena entender: ela **recusa** a adoção se achar credencial
  escrita na memória. Versionar memória é distribuí-la — adotar por cima de uma
  API key commita essa chave no repositório, e não tem desfazer: quem clonar
  depois leva junto, e o histórico guarda mesmo que você apague no commit
  seguinte.

- **Skill `setup`** (`/kit-vamoo:setup`) — instala CLAUDE.md, barra de status e
  preferências, e conduz o preenchimento do CLAUDE.md.

- **Skill `diretor-imagem`** — já estava no repositório desde sempre, como um
  arquivo solto em `skills/`, e por isso **nunca foi instalada em ninguém**: o
  instalador só varria subdiretórios. Virou skill de verdade.

### Corrigido

- **O `settings.json` agora é MESCLADO, não sobrescrito.** O README prometia
  isso desde a primeira versão; o `install.sh` fazia o contrário — sobrescrevia
  com um aviso fácil de não ver, e quem tinha `permissions` ou `env` próprios
  perdia tudo. Agora as suas chaves ganham e a lista `allow` vira a união das
  duas.

- **O `CLAUDE.md` que já existe não é mais sobrescrito.** O modelo do kit fica em
  `~/.claude/CLAUDE.kit.md` pra comparar; trocar exige `--force`.

- **O som de "terminou" não quebra mais fora do macOS.** O hook checa se o
  `afplay` existe antes de chamar — no Windows/Git Bash ele simplesmente não faz
  nada, em vez de falhar a cada turno.

- **Os guard-rails de git funcionam rodando do plugin.** Eles procuravam o
  helper em `~/.claude/scripts/hookjson.js` e falham em aberto quando não acham
  — instalado por plugin, isso significaria proteção contra commit na `main`
  desligada em silêncio. Agora resolvem ao lado do próprio script.

- **README dizia "10 skills"** quando eram 12 (hoje são 15).

### Alterado

- A barra de status mostra o contexto em **número absoluto**, não em % da janela.
  Numa janela de 1M, 500k pinta "50%" e parece saudável — quando é meio milhão
  de tokens sendo relidos a cada comando. Verde até 150k, amarelo até 300k.

- Reorganização: skills, comandos, hooks, scripts e templates passaram pra
  `plugin/`. O `marketplace.json` fica em `.claude-plugin/` na raiz. Fonte única
  — não existe mais uma cópia no repositório e outra em `~/.claude` divergindo.

## [0.6.1] — 2026-08-23

### Adicionado

- **Skill `baseline`** — responde *"este app está pronto pra produção?"* em 7 frentes:
  bundle e secrets, RLS, login e permissão, limites de uso, carga e cache,
  observabilidade e gestão de segredos. Dois modos: construir (app novo nasce certo) e
  auditar (app que já está no ar). Traz scripts que **medem** — `doctor` (o que dá pra
  medir), `collect` (mede sem julgar), `render` (relatório com cobertura declarada) e
  `splinter` (os 21 lints de segurança do Supabase, rodados como consulta, sem alterar
  nada no banco).

  A regra que vale levar pra qualquer auditoria: **"não medido" nunca vira "está ok"**, e
  quando não consegue medir nada ela **falha de propósito** — relatório vazio parece
  aprovação, e é o pior resultado possível.

- **Skill `handoff`** — `/handoff` monta o documento de passagem com template fixo e
  âncora de git. A regra que dá valor ao documento: marcar cada afirmação como
  `[verificado: <comando>]` ou `[acreditado]`. Quem assume trata o handoff como contrato
  e não re-confere; crença escrita como fato vira premissa falsa pra tudo depois.

- **`docs/observabilidade.md`** — *"como você descobre que quebrou?"*. Começa pela
  armadilha de ligar `drop: ['console']` antes de ter error tracking, que apaga o único
  rastro que você teria em produção.

### Alterado

- `templates/CLAUDE-global.md` ganha duas regras de custo que valem no dia a dia:
  **screenshot fica na conversa e é relido a cada mensagem seguinte** (tire print
  quando o visual é a pergunta; pra conferir texto ou erro, leia a página como
  texto) e **sessão longa é o que mais consome seu limite** — a cada comando o
  Claude relê a conversa inteira, então três sessões de 1h custam bem menos que
  uma de 3h com o mesmo trabalho. Terminou a tarefa, assunto novo → `/clear`.

- `docs/seguranca.md` passa de 5 para 7 furos comuns: entram **falta de limite de uso**
  (endpoint que chama IA sem `max_tokens` nem cota vira conta impagável) e **"secret" que
  não é secret** (`VITE_`/`NEXT_PUBLIC_` vai pro bundle). Ganha também a seção de ordem —
  as duas armadilhas onde o problema não é o quê, é o quando.
## [0.6.0] — 2026-08-06

### Skill nova: `git-sync` (trabalhar no mesmo repo que outra pessoa)

O Claude Code Desktop não mostra PR, nem branch remota nova, nem avisa que alguém
mexeu nos mesmos arquivos que você. Duas pessoas no mesmo projeto descobrem o
conflito tarde demais — na hora do PR. Essa skill fecha esse buraco.

- **`skills/git-sync`** — `/git-sync` faz `fetch --prune` e atualiza o clone e os
  worktrees **só por fast-forward** (nunca `pull` com merge, nunca `rebase`
  automático, nunca `reset --hard`, nunca commita por você).
- **Modo time, automático**: quando o repo tem 2+ autores na branch principal nos
  últimos 30 dias, o relatório passa a mostrar o que o outro mudou, branches
  remotas ativas, PRs abertos com autor/`mergeable`/review, PRs mergeados na
  janela — e **risco de conflito**: os arquivos que mudaram na `main` e que você
  também tocou. Force com `--team`, desligue com `--no-team`.
- **Avisos acionáveis** (com o comando exato ao lado): branch atrás da `main`,
  commits locais sem push, branch divergida porque os dois commitaram nela, e
  branch local homônima de uma que já existe no GitHub.
- **Protocolo de sessão** documentado na skill: rode ao abrir (antes de escrever
  a primeira linha) e ao fechar (nada pode ficar sem push).
- Roteamento novo em `templates/CLAUDE-global.md` — o Claude carrega a skill
  sozinho quando você diz que vai começar a mexer no projeto.

Opcional: `gh` instalado e autenticado (`gh auth login`). Sem ele tudo funciona,
só não há visão de PR.

## [0.5.1] — 2026-07-28

### Ajustes pra família Claude 5 (Fable/Opus 5)
- **`templates/CLAUDE-global.md`**: 2 regras novas — (1) pedido que parece errado/subótimo:
  o Claude diz em 1 frase e segue como pedido, nunca transforma a tarefa silenciosamente;
  (2) docs/relatórios gerados sem filler (sem seção boilerplate nem resumo redundante).
  Os modelos da família 5 tendem a expandir escopo e inflar relatórios — o controle é por prompt.
- **`commands/revisar.md`**: trocado "não invente problema pra parecer útil" por "reporte tudo
  que encontrar, rankeado por severidade". Em modelo com precisão alta, a instrução conservadora
  fazia subreportar bug real.
- **`skills/orquestracao`**: freio anti-over-delegation (não delegar o que resolve em poucos
  tool calls; sem subagent pra auto-conferência) + dica de `effort` por estágio em `agent()`.

### Docs
- **`docs/programacao-avancada-com-claude.md`**: link de leitura avançada pro repo
  aipromptguide-workflows (workflows multi-agente + Workflow Principles).

## [0.5.0] — 2026-07-15

### Segurança / sanitização
- **Removidas 8 skills internas/de-cliente** que não eram pedagógicas e expunham operação
  interna: `agent-reporting`, `ambientes-clientes`, `n8n-workflow-agent`,
  `pipedrive-automation`, `vamoo-infra`, `vps-hardening-clientes`, `notebooklm`,
  `notebooklm-project-ops`. (Remover `n8n-workflow-agent` também tirou um identificador
  real de projeto Supabase que aparecia num exemplo.)
- Renomeadas `vamoo-{orquestracao,verificacao,worktrees}` → nomes neutros.

### Performance
- **Removido o hook `typecheck.sh`** (rodava `tsc --noEmit` do projeto inteiro a cada
  edição — travava 12-20s). Fica só o `lint-fix.sh`; o type-check vira parte do check
  final antes de "pronto".

### Instalador — reinstalação que CONSERTA o legado
- `install.sh` agora **sobrescreve o `settings.json`** (com backup) em vez de recusar —
  assim quem tinha o hook tsc antigo o perde ao reinstalar. A versão anterior fica em
  `backup-kit-<data>/settings.json` pra reaplicar customizações (permissions/env).
- Mecanismo "fantasma" estendido a **hooks/scripts/comandos** (antes só skills): item
  que saiu do kit é removido da sua instalação com backup — ex: o `typecheck.sh`.
- **Versionamento**: o manifesto guarda a versão (`kit 0.5.0`) e o instalador avisa
  "atualizando de X → Y".

### Config
- `CLAUDE-global.md` enxugado (v5): `grilling` aciona por **implementação grande** (não
  vagueza); removidas as referências órfãs ao plugin `superpowers`; mantidos os modos
  EXPLAIN/MENTOR (é pedagógico).
- README/SECURITY/docs atualizados (17 → 9 skills).

## [0.4.0] — 2026-07-07

### Adicionado
- **Barra de status com visibilidade de GitHub.** A statusline agora mostra, além de
  diretório/branch/contexto: alterações não salvas (`✗`), commits à frente/atrás do
  remoto (`↑`/`↓`), **GitHub conectado** (`gh✓`/`gh✗`) e **PR aberto pra branch** (`PR#`).
  Resolve a cegueira do Claude Code Desktop, que não mostra nada disso visualmente. O
  estado do GitHub é cacheado (~90s) e atualizado em segundo plano — a barra nunca trava
  esperando a rede. Escrita em node puro (`scripts/statusline.js`), roda no Mac e no Windows.
- **Guard-rails de git como arquivos** (`hooks/`, `scripts/`):
  - `check-careful.sh` — pede confirmação antes de `rm -rf` (fora de pastas descartáveis),
    `DROP`/`TRUNCATE`, `git push --force` e `git add -A/-u/.`.
  - `warn-branch-behind.sh` — avisa, ao abrir a sessão, se a branch está atrás do remoto.
  - `warn-worktree-stale.sh` — avisa se o worktree atual já foi mergeado (é lixo) ou se o
    clone principal não está em `main`.
  - `worktree-gc.sh` — utilitário pra limpar worktrees de branches já mergeadas
    (`worktree-gc.sh` = dry-run; `--apply` remove).

### Alterado
- **Fim da dependência de `jq`.** Todos os hooks passaram a ler o JSON do Claude Code via
  **node** (helper `scripts/hookjson.js`) em vez de `jq`. Como o node já é pré-requisito do
  kit (a statusline roda nele), o `jq` sai da lista de dependências — um pré-requisito a
  menos pra instalar. Os hooks de lint/typecheck e a proteção de commit continuam iguais,
  só sem precisar de `jq`.
- **`block-main-commit` virou arquivo robusto** (`hooks/block-main-commit.sh`), no lugar da
  versão inline por substring. Agora resolve o **repo-alvo real** (`git -C <path>` / primeiro
  `cd <path>`) em vez de olhar só o diretório da sessão, e não confunde `git commit` que
  aparece dentro de uma string (grep/echo). O escape `HOTFIX_MAIN=1` segue igual.
- `install.sh` agora instala as pastas `hooks/` e `scripts/`, e o aviso sobre `jq` virou
  aviso sobre `node`/`gh` (as dependências que de fato importam).

## [0.3.0] — 2026-06-11

### Corrigido
- **Hooks de lint/typecheck automático estavam quebrados (no-op silencioso).** Usavam
  `$CLAUDE_FILE_PATH`, que não é uma variável de ambiente oficial do Claude Code — vinha
  sempre vazia, então o eslint/tsc nunca rodava de fato. Agora leem o caminho do arquivo
  do JSON via stdin (`jq -r '.tool_input.file_path'`), conforme a documentação oficial.
  Degradam graciosamente se `jq` não estiver instalado (não rodam, mas não quebram).

### Adicionado
- Hook `PreToolUse` no `settings.json`: **bloqueia `git commit` direto na `main`/`master`**
  (escape `HOTFIX_MAIN=1` pra quando for proposital). Protege do erro clássico de
  commitar na branch errada — comum com vários terminais abertos no mesmo projeto.
  Portável (só `grep` + `git`, sem depender de `jq`).
- `CLAUDE-global.md`: seção sobre rodar vários terminais no mesmo repo (branch por
  sessão, `git add` só dos seus arquivos, conferir `git log` após o commit).
- `install.sh` avisa quando `jq` não está instalado (os hooks de lint/typecheck
  precisam dele) e mostra como instalar.

## [0.2.0] — 2026-06-09

### Segurança
- `python-dotenv` da skill notebooklm atualizado 1.0.0 → 1.2.2 (GHSA-mf9w-mj56-hr94).

### Adicionado
- `install.sh --dry-run` (mostra o que faria) e `--backup-dir` (muda o destino do backup).
- Backup completo: statusline, skills e comandos agora também são salvos em
  `~/.claude/backup-kit-<data>/` antes de sobrescrever (antes só CLAUDE.md/agents.md).
- Manifesto de instalação (`~/.claude/.kit-manifest`): skills removidas do kit em
  versões novas são limpas na reinstalação (com backup), sem tocar nas suas skills próprias.
- CI do próprio kit (valida JSON, shell, Python, links, secrets e dependências).
- `LICENSE` (MIT), `SECURITY.md` e este `CHANGELOG.md`.
- README com badges (CI/licença/release), URL real de clone e seção "Quer ir além?".

### Mudado
- Skill `pipedrive-automation`: frontmatter corrigido (name batia com a pasta) e
  conteúdo reescrito em PT-BR, curado e enxuto.
- Skill `n8n-workflow-agent`: SKILL.md de 2.310 linhas virou roteador curto +
  referências por domínio em `references/` (carrega só o contexto necessário).
- Templates de CI atualizados pra Node 22.
- Hooks do `settings.json` usam `npm exec --no` (só roda eslint/tsc se o projeto
  tiver a ferramenta instalada — não baixa nada por conta própria).
- Skill `agent-reporting`: caminhos configuráveis via `TICKTICK_ENV_FILE` /
  `TICKTICK_PROJECTS_FILE`; sem credencial configurada, avisa e sai sem quebrar.

### Removido
- Permissão `Bash(npm install:*)` do settings.json default — instalar dependência
  nova volta a pedir sua aprovação (mais seguro pra quem está começando).

## [0.1.0] — 2026-06-08

- Versão inicial: CLAUDE.md, agents.md, settings.json, statusline, /revisar,
  /explicar, docs pedagógicas, templates (projeto, CI, Playwright) e 10 skills.
