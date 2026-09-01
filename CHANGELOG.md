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
