# ship — pré-voo e gates do §1 em detalhe

Lido no §0 quando o `gh repo view` falha, e no §1 quando um gate se comporta estranho (tsc mudo, eslint entrando em worktree, teste local vs. CI).

## §0. Conta do `gh` que não vê o repo

Se `gh repo view` falhar com `Could not resolve to a Repository`, a conta **ativa** do `gh` não vê
este repo (várias contas no keyring; a errada fica `Active account: true`). Não troque a ativa
com `gh auth switch`: ela vale para a máquina inteira, e as outras sessões abertas passam a usar
a conta errada. Passe a conta certa por comando:

```bash
GH_TOKEN="$(gh auth token --user <conta-com-acesso>)" gh repo view --json nameWithOwner
```

Só continue quando esse `gh repo view` responder. O mesmo prefixo vai em todo `gh` desta ship
(PR, checks, merge, `gh api`) e no `git push` quando o helper de credencial do git é o `gh`
(`git config --get credential.https://github.com.helper` mostra `gh auth git-credential`). De
dentro de worktree o guard pode recusar o `VAR="$(…)"` na frente do comando: grave o comando num
`.sh` no scratchpad e rode pelo caminho literal (skill `worktrees`). Não abra PR nem dê merge
com a conta que não lista o repositório.

**`.context/` de cache e sessão:** se existir `.context/cache/` ou `.context/runtime/` e o
`.gitignore` não tiver essas entradas, adicione-as antes do commit.

## §1. Detalhes dos gates

Os `--ignore-pattern` existem porque o ESLint 9 (flat config) não lê o `.gitignore` e não ignora
mais pasta que começa com ponto: rodado no clone principal, ele entra nos worktrees que moram
dentro do repo e reprova o seu PR pelo código de outra sessão.

`format:check` vermelho → `prettier --write` só nos arquivos listados, confira de novo, e esses
arquivos entram no commit. Pular o `format:check` porque o eslint passou custa um CI inteiro.

**tsc: no máximo um processo por HEAD.**
- Silêncio por vários minutos é normal: wrappers (`rtk tsc`) guardam a saída até o fim. Não é
  travamento, e não lance um segundo tsc; se já existe um deste HEAD, espere esse.
- Se o CI tem check obrigatório de typecheck (`tsc --noEmit`), não segure o push esperando o
  tsc local: format + eslint verdes bastam para commitar, e o CI é o gate de tipos.
- Sem typecheck no CI, o `tsc --noEmit` local **tem** de passar antes do push.

**Testes:** com a suíte inteira como check obrigatório no CI, rode local só os testes do diff
(arquivos mudados e as pastas irmãs). Sem CI, rode a suíte inteira (`npm test`, ou o do pnpm,
yarn ou bun).

Comando não configurado: diga "sem config de eslint — pulado". Nunca afirme que um gate passou
se ele não rodou.
