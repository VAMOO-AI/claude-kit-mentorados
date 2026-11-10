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
- **Modo sem perguntas (`--sem-perguntas`), só para quem pede.** Regra `ask` pergunta em
  qualquer modo de permissão, inclusive no bypass. Com `--sem-perguntas`, o setup tira as
  regras `ask` de comando (`Bash(...)` e `PowerShell(...)`) que o kit pôs e não as põe de novo
  nas atualizações; a escolha fica em `~/.claude/kit-vamoo/sem-perguntas`. Diga à pessoa o que
  deixa de pedir confirmação: `git push --force`, `--delete`, `--mirror` e `--all` em branch
  que não é a main, push direto na main, `git reset --hard`, `git clean`, `git branch -D`,
  `checkout -f`, `checkout -- .`, `switch --discard-changes`, `restore .`, `stash drop`/`clear`,
  `worktree remove --force`, `gh pr merge`, `gh repo delete`, `gh release delete`,
  `supabase secrets set`/`unset`, `supabase migration repair`, `find -delete`/`-exec`,
  `Remove-Item -Recurse`, listar variáveis de ambiente e comando que cita `.pem`, chave SSH ou
  credencial. E o que continua barrado, porque as regras `deny` não mudam: force push na
  main, `supabase db push`, login do Supabase e da Vercel, leitura de `.env`. Os hooks do kit,
  as regras `ask` de conector e as `ask` que a pessoa escreveu continuam. Uma regra de comando
  que ela escreveu com o texto idêntico ao de uma regra do kit sai junto: o setup não tem como
  distinguir. `--com-perguntas` desliga e devolve as regras no mesmo setup.
- **O setup liga o auto-update do kit** (`extraKnownMarketplaces.vamoo-ai.autoUpdate`).
  É o que faz o kit parar de envelhecer na máquina de quem instalou: o Claude
  Code desliga a atualização automática de marketplace de terceiro por padrão, e
  o botão que liga isso vive no `/plugin`, um painel que **não existe no
  aplicativo de desktop**. Declarado no `settings.json`, vale nos dois — e a
  fonte do marketplace que a pessoa já tinha não é trocada. Quem desligou de
  propósito (`autoUpdate: false`) continua desligado, com aviso na saída.
