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
- **O setup liga o auto-update do kit** (`extraKnownMarketplaces.vamoo-ai.autoUpdate`).
  É o que faz o kit parar de envelhecer na máquina de quem instalou: o Claude
  Code desliga a atualização automática de marketplace de terceiro por padrão, e
  o botão que liga isso vive no `/plugin`, um painel que **não existe no
  aplicativo de desktop**. Declarado no `settings.json`, vale nos dois — e a
  fonte do marketplace que a pessoa já tinha não é trocada. Quem desligou de
  propósito (`autoUpdate: false`) continua desligado, com aviso na saída.
