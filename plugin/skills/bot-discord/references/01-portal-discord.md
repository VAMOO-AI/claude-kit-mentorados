# 01 — Developer Portal, convite e IDs

Nada aqui o agente faz sozinho: é tela do Discord. **Gere a lista para o usuário executar e
peça os valores de volta.** Enquanto os IDs não chegarem, não escreva o código do bot.

## 1. Criar a aplicação e pegar o token

1. https://discord.com/developers/applications → **New Application** → nome do bot.
2. Menu **Bot** → **Reset Token** → copiar. **O token aparece uma vez só.**
   Vai para o `.env` local (`DISCORD_BOT_TOKEN=`) — nunca no git, nunca colado num chat.
3. Ainda em **Bot**: desligue **Public Bot** se só o servidor dele vai usar o bot.

Se o token vazar (commitado, printado, colado em grupo): **Reset Token no portal e trocar na VPS**,
na hora. Token de bot dá acesso a tudo que o bot enxerga.

## 2. Privileged Gateway Intents — ARMADILHA Nº 1

Na mesma tela **Bot**, ligue os toggles:

- ✅ **MESSAGE CONTENT INTENT** — sem ele `message.content` chega **string vazia**
- ✅ **SERVER MEMBERS INTENT** — se for resolver nome, cargo ou lista de membros
- PRESENCE INTENT — só se realmente precisar de status online

Declarar `GatewayIntentBits.MessageContent` no código **não liga a intent**. Com o toggle
desligado o bot conecta, aparece online, não emite erro nenhum — e simplesmente nunca vê texto.
Toda vez que alguém disser "o bot conecta mas não responde", cheque isto primeiro.

> Acima de 100 servidores o Discord exige verificação para liberar essas intents. Bot interno
> de uma empresa nunca chega perto disso — é só marcar e salvar.

## 3. Convidar o bot para o servidor

**OAuth2 → URL Generator**:

- **Scopes**: `bot` **e** `applications.commands`
  (sem o segundo, o registro de slash command falha com `Missing Access`)
- **Bot Permissions** (mínimo real): `View Channels`, `Send Messages`, `Read Message History`,
  `Add Reactions`, `Embed Links`.
  `Manage Messages` só se for apagar/fixar. **Nunca marque Administrator** — bot com Administrator
  é o mesmo risco de uma conta de admin com a senha no `.env`.
- Copie a URL gerada, abra no navegador, escolha o servidor, autorize.

Depois de convidar, confira as **permissões por canal**: um cargo pode negar no canal o que o
convite concedeu no servidor. Bot que fala em todo canal menos um = override de permissão nesse
canal, não bug de código.

## 4. Coletar os IDs

No Discord: **Configurações do usuário → Avançado → Modo desenvolvedor ON**.

- botão direito no servidor → *Copiar ID do servidor* → `DISCORD_GUILD_ID`
- botão direito em cada canal → *Copiar ID do canal* → uma env var por canal
- botão direito no usuário → *Copiar ID do usuário* → allowlist de comandos

Peça ao usuário todos de uma vez. Canal **sempre** por env var: canal muda, o servidor de teste
tem outro ID, e o cliente cria canal novo sem avisar. ID de canal hardcoded é dívida garantida.

## 5. Servidor de teste (recomendado)

Crie um servidor pessoal e convide o mesmo bot lá (ou um segundo app "bot-dev" com token próprio).
Testar direto no servidor do cliente significa que todo experimento vira notificação para a equipe
inteira — e é assim que um bot perde a confiança do time antes de estar pronto.
