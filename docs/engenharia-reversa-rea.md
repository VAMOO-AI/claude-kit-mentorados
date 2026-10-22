# Engenharia reversa com o REA

A skill `reverse-engineer-anything` saiu do kit na 0.62.0. Quase todo o texto dela era cópia do
upstream, e o corpo mandava rodar `rea setup`, o que contradizia o próprio cabeçalho. Esta nota
guarda só a regra que o kit tinha acrescentado.

- **Quando usar:** quando a pergunta depende de um binário, pacote ou app empacotado
  (Electron/JS, APK, firmware) ou de uma captura HAR/SAZ. Se você tem o código-fonte, leia o
  código com as ferramentas normais.
- **Instruções:** as do upstream, [morluto/rea](https://github.com/morluto/rea) (MIT), na versão
  que você for usar.
- **Ligue o MCP só durante a investigação, no escopo local e com versão fixa.** Rode na pasta da
  investigação, porque o escopo local vale por pasta:

  ```bash
  claude mcp add rea --scope local -- npx -y rea-agents@6.4.0 mcp
  claude mcp remove rea --scope local
  ```

- **Nunca rode `rea-agents setup` nem o "setup plan" do upstream.** Ele registra o MCP no escopo
  de usuário (`~/.claude.json`) e em todo cliente que encontrar (Codex, Claude Desktop), e
  instala a skill do upstream de um jeito que o Claude a aciona sozinho.
