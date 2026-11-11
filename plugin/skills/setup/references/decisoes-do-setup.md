# setup — decisões que o kit-setup.sh já toma

Lido no passo 1, depois do `--dry-run`: o que o setup faz no `settings.json`, para dizer à pessoa em voz alta.

- **`settings.json` é mesclado, não substituído.** As chaves de quem instala
  ganham; a lista `allow` vira a união das duas. Ninguém perde permissão ou
  variável de ambiente que já tinha configurado.
- **O modo de permissão vira Auto (`auto`).** Quem estava no Manual (`default`), no
  Accept edits (`acceptEdits`) ou sem modo passa para `auto`, o padrão do próprio Claude Code desde a v2.1.283, e a
  saída diz isso numa linha. No Auto, um segundo modelo (o classificador) revisa cada
  comando antes de rodar no lugar do "Permitir" manual. Se o Auto não estiver
  disponível para a conta ou o modelo, o Claude Code abre a sessão em Manual: não é o
  setup que falhou. Quem quer ficar no Accept edits cria
  `~/.claude/kit-vamoo/manter-accept-edits`, e a saída ensina isso quando troca.
  `bypassPermissions`, `plan` e `dontAsk` ficam como estão. Junto vêm allow de git local, `git push` e `gh pr create`, e `ask` para o que
  não tem volta (force push, push na main, descartar alteração local, `rm -r` fora das
  pastas descartáveis, listar variáveis de ambiente, ler arquivo de segredo), com espelho
  em `PowerShell(...)`. Runner de script (`node scripts/*`, `npx tsx`, `npm run`, `awk`)
  e `ffmpeg` não entram no allow global, e o setup tira de quem já tinha os
  `Bash(awk:*)`, `Bash(npx tsx:*)` e `Bash(npm run:*)` que versões anteriores do kit
  gravaram: o projeto libera o comando exato no próprio `.claude/settings.json`. Quem
  quer o manual de vez cria `~/.claude/kit-vamoo/manter-modo-manual` e o setup não
  troca mais.
- **Modo sem perguntas (`--sem-perguntas`), só para quem pede.** A escolha fica em
  `~/.claude/kit-vamoo/sem-perguntas` e vale nos setups seguintes. O modo faz três coisas, e
  as três têm de ser ditas:
  1. **Põe `permissions.defaultMode` em `bypassPermissions`** (no app, **Ignorar
     permissões**), venha a pessoa de onde vier (Manual, Auto, Accept edits, plan), e grava
     `skipDangerousModePermissionPrompt` para a CLI não abrir o aviso do modo perigoso. Os
     marcadores `manter-modo-manual` e `manter-accept-edits` seguram o modo; aí a saída diz
     que ele não está em bypass.
  2. **Tira as regras `ask` de comando** (`Bash(...)` e `PowerShell(...)`) que o kit pôs e
     não as põe de novo nas atualizações. Regra `ask` pergunta em qualquer modo, inclusive no
     bypass.
  3. **Reduz o hook de confirmação ao que não tem volta**, em qualquer modo.

  **No app de desktop o `settings.json` não basta.** Diga os dois passos, que são da pessoa e
  não dá para fazer por ela: em **Settings > Code**, ligar **Allow bypass permissions mode**
  (em plano Team ou Enterprise quem libera é a organização); e, no seletor de modo ao lado do
  botão de enviar, escolher **Ignorar permissões** em cada pasta onde já tinha outro modo (o
  seletor é lembrado por pasta e vence o arquivo). Sem isso o app continua pedindo "Permitir"
  e a pessoa conclui que o modo não pegou.

  O que deixa de pedir confirmação: `git push --force`, `--delete`, `--mirror` e `--all` em
  branch que não é a main, push direto na main, `git reset --hard`, `git clean`,
  `git branch -D`, `checkout -f`, `checkout -- .`, `switch --discard-changes`, `restore .`,
  `stash drop`/`clear`, `worktree remove --force`, `gh pr merge`, `gh release delete`,
  `supabase secrets set`/`unset`, `supabase migration repair`, `find -delete`/`-exec`,
  `rm -r`/`Remove-Item -Recurse` de pasta de dentro do projeto, `git add -A`, DDL
  (`CREATE`/`ALTER TABLE`), listar variáveis de ambiente e comando que cita `.pem`, chave SSH
  ou credencial.

  O que ainda pergunta, em qualquer modo: `rm -r` fora do projeto (ou do projeto inteiro e do
  `.git` dele), `DROP`/`TRUNCATE` sendo executado, `supabase db reset` no banco remoto,
  `gh repo delete` e comando de rede que leva credencial para fora.

  O que continua barrado, porque as regras `deny` não mudam: force push na main,
  `supabase db push`, login do Supabase e da Vercel, leitura de `.env`, `rm -rf` em `/` e na
  pasta de usuário. O hook que bloqueia commit direto na main, as regras `ask` de conector e
  as `ask` que a pessoa escreveu continuam. Uma regra de comando que ela escreveu com o texto
  idêntico ao de uma regra do kit sai junto: o setup não tem como distinguir.

  Depois de ligado, um setup comum (o da atualização) não força o bypass de novo em quem
  trocou o modo na mão. `--com-perguntas` desliga no mesmo setup: devolve as regras e o modo
  de permissão de antes.
- **O setup liga o auto-update do kit** (`extraKnownMarketplaces.vamoo-ai.autoUpdate`).
  É o que faz o kit parar de envelhecer na máquina de quem instalou: o Claude
  Code desliga a atualização automática de marketplace de terceiro por padrão, e
  o botão que liga isso vive no `/plugin`, um painel que **não existe no
  aplicativo de desktop**. Declarado no `settings.json`, vale nos dois — e a
  fonte do marketplace que a pessoa já tinha não é trocada. Quem desligou de
  propósito (`autoUpdate: false`) continua desligado, com aviso na saída.
