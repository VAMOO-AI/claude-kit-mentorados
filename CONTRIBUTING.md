# Contribuir

Para quem mantém o kit. A nota para mentorado continua no topo do [CHANGELOG.md](CHANGELOG.md).

**Suba o `version` do `plugin.json` em toda entrega.** Ele é a chave do
cache do Claude Code; sem bump, ninguém recebe a mudança, nem com auto-update ligado.
Se a mudança tocar a barra de status ou as preferências, rode também
`/kit-vamoo:setup` — ele faz backup de tudo antes.

A versão tem de ser a mesma nestes cinco lugares (`bash tests/test-versao-changelog.sh`):

- `plugin/.claude-plugin/plugin.json` (campo `version`)
- `install.sh` e `plugin/scripts/kit-setup.sh` (`KIT_VERSION`)
- o primeiro `## [x.y.z]` do `CHANGELOG.md`
- a primeira linha de dado de `plugin/novidades.txt`

A tag sai do workflow de release quando o `plugin.json` muda na `main`. Não crie tag na mão.
O restante do fluxo está no README, na seção "Se você mantém o kit".
