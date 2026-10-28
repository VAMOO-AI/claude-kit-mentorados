# Contribuir

Para quem mantém o kit. A nota para mentorado continua no topo do [CHANGELOG.md](CHANGELOG.md).

## Toda entrega sobe a versão, mas quem sobe é o release

O `version` do `plugin.json` é a chave do cache do Claude Code. Sem bump, ninguém recebe a
mudança, nem com auto-update ligado. Se a mudança tocar a barra de status ou as preferências,
rode também `/kit-vamoo:setup`, que faz backup de tudo antes.

A versão tem de ser a mesma nestes cinco lugares (`bash tests/test-versao-changelog.sh`):

- `plugin/.claude-plugin/plugin.json` (campo `version`)
- `install.sh` e `plugin/scripts/kit-setup.sh` (`KIT_VERSION`)
- o primeiro `## [x.y.z]` do `CHANGELOG.md`
- a primeira linha de dado de `plugin/novidades.txt`

Até a 0.82, cada PR subia a versão. Com vários PRs na fila, cada merge obrigava o seguinte a
fazer rebase e a rodar o CI de novo, e dois PRs chegaram a disputar o mesmo número. Agora:

1. **O PR de feature não sobe versão** e não toca `CHANGELOG.md` nem `plugin/novidades.txt`.
   O texto fica no corpo do PR, nestas duas seções:

   ```markdown
   ## Para o CHANGELOG
   ### Adicionado
   - **`nome-da-skill`**: o que mudou, para quem mantém.

   ### Corrigido
   - ...

   ## Para o novidades
   Uma frase na voz do mentorado, sem "|".
   setup
   ```

   - O `### Seção` é opcional. Bullet sem seção vai para `### Mudado`.
   - A linha `setup` só entra quando a versão mexe no que o `/kit-vamoo:setup` instala.
   - Cada seção termina no próximo `#` ou `##`, no `---` ou no rodapé `🤖`.

   No CI desse PR, as suítes rodam inteiras e o último passo do `validate` ("Mexeu no plugin?
   A versão tem que subir") fica vermelho. É o esperado: o PR não entra sozinho.
2. **O release junta os PRs prontos** num branch `release/<versão>`, com um bump e um CI só:

   ```bash
   bash scripts/release-trem.sh 0.83.0 310 311 312
   ```

   - O script cria o worktree `.claude/worktrees/release-<versão>` a partir de `origin/main`.
   - Ele dá merge de `pull/<n>/head` de cada PR, na ordem dada, e para no primeiro conflito,
     dizendo o PR e o arquivo. O conserto é fazer rebase do PR na main, ou tirá-lo do trem.
   - Ele sobe a versão nos cinco lugares e monta o bloco do CHANGELOG, agrupado por seção, e a
     linha das novidades com o texto de cada PR.
   - Por fim, roda os dois gates de versão e faz o commit.
   - **Não faz push.** Revise o bloco e a linha, e então rode o `git push` e o
     `gh pr create --draft --body-file`, que o script imprime.
   - O número é **a versão da main + 1**, decidido na hora do release.
3. Depois do merge do release, **feche os PRs incluídos**: o squash do release não os fecha.
   Os comandos `gh pr close` estão no corpo que o script gerou.

**Exceção:** PR que não toca `plugin/` (só CI, `scripts/`, `tests/` ou docs da raiz) não
precisa de versão, porque o gate só olha `plugin/`. Ele entra sozinho, sem esperar release.

A tag sai do workflow de release quando o `plugin.json` muda na `main`. Não crie tag na mão.
O restante do fluxo está no README, na seção "Se você mantém o kit".

## Gates para rodar antes de abrir o PR

São rápidos e pegam o que mais volta do CI:

```bash
bash tests/test-docs-consistencia.sh
bash tests/test-lint-instrucoes.sh
bash tests/test-skill-descriptions.sh
bash tests/test-sem-dado-de-cliente.sh
bash tests/test-pin-versao.sh
```

No CI, o job `macos` roda a suíte inteira em 3 shards (`.github/scripts/ci-shard.sh`). Teste
novo em `tests/test-*.sh` entra num shard sozinho, mas precisa de um passo próprio no
`validate`, porque o check "Nenhum teste ficou de fora" faz grep do nome no `ci.yml`.

## Upstreams: de onde o kit tira ideia

`scripts/upstreams.json` lista os repos que inspiram o kit (superpowers, rtk, gstack…), com a
data e a versão da última leitura e o que veio de cada um. O workflow `upstreams` roda nos
dias 1 e 15 e, quando sai coisa depois da leitura, abre ou atualiza a issue
`upstreams: novidade para ler`. Para conferir na hora: `bash scripts/upstreams-check.sh`.

Quem lê cruza cada novidade com o kit (já temos, não serve, trazer) e, no PR que traz a
ideia (ou num PR só do manifesto, se nada entrou), atualiza `lido_em`, `lido_versao` e
`que_trouxemos` da entrada. Depois fecha a issue. Sem esse passo, o próximo run aponta de
novo as mesmas releases.
