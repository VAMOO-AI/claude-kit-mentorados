# Página MCP, guia de instalação e chave por usuário (PR 4)

Visual: o design system do PROJETO ALVO (tokens, fontes, claro/escuro, componentes
de card/badge que o app já tem). Não copie classes do exemplo.

## Quem vê

- `GET /api/me/mcp` (`code/me-mcp-route.ts`) devolve `{ enabled, role }` usando
  `principalFromRows` — a MESMA decisão do servidor. Página, item de menu e
  servidor nunca discordam.
- Item "MCP" na área de gestão só com `enabled`. Sem acesso, a view mostra um card
  "Acesso ao MCP não liberado — peça ao administrador em Usuários & Acessos".

## Estrutura da página (nesta ordem)

1. **Cabeçalho**: eyebrow "MCP", título "Conecte o <sistema> ao seu agente", 1
   frase: pergunte no Claude/ChatGPT/outro cliente; o agente enxerga o mesmo que
   você vê aqui, recortado pelo seu nível de acesso.
2. **Card resumo** (4 colunas no desktop, empilhado no mobile):
   - Endpoint + botão Copiar URL.
   - Autenticação: "Login com a sua conta" / "OAuth pelo navegador, sem token".
   - O agente acessa: chips por papel + 1 linha do recorte (mesma fonte do
     consentimento).
   - Servidor: nome curto (`<nome>`).
3. **Instalação guiada** em 4 passos com barra de progresso (localStorage via
   `useSyncExternalStore`, com fallback em memória; servidor renderiza vazio para
   não dar mismatch de hidratação). Ver `code/install-guide.tsx`.
   1. Escolha a ferramenta: Claude (app ou web) · Claude Code (terminal) ·
      ChatGPT (app ou web) · Outro cliente (MCP remoto).
   2. Adicione o MCP — instrução da ferramenta escolhida:
      - Claude Code: `claude mcp add --transport http <nome> <url>`
      - Claude: Configurações → Conectores → Adicionar conector personalizado,
        nome `<nome>`, URL.
      - ChatGPT: Configurações → Conectores (Apps) → modo desenvolvedor → criar
        conector com a URL.
      - Outro: qualquer cliente de MCP remoto com Streamable HTTP e login OAuth.
   3. Faça login: o navegador abre o login do app (com MFA se pedir) e depois a
      tela de consentimento → Permitir. Não há token para copiar.
   4. Teste a conexão: "Quem sou eu no <sistema>?" → tool `whoami`.
   Passos 2–4 com botão "Marcar como feito"; passo 1 marca ao escolher; botão
   "Recomeçar".
4. **Prompts úteis** em abas por domínio (ex.: Faturamento · Operação · Reuniões ·
   Gestão). Cada prompt: título, texto com botão Copiar, tools usadas, selo
   "Altera dados" nos de escrita. Abas e prompts filtrados pelo papel.
5. **Dúvidas frequentes** (`<details>`): Preciso de token? · O que o agente faz em
   meu nome? · Como desconecto? (remover o conector; o admin corta na hora em
   Usuários) · Posso usar em mais de uma ferramenta?

## Catálogo de prompts (`src/lib/mcp/prompts.ts`)

- Tipo `McpPrompt = { titulo, prompt, tools, alteraDados, papeis }` e abas.
- `MCP_TOOLS`: lista das tools registradas. Teste: toda tool citada num prompt
  existe em `MCP_TOOLS`, e `MCP_TOOLS` bate com o que `registerReadTools` +
  `registerWriteTools` registram (pega tool renomeada sem atualizar a página).
- Teste: nenhum prompt de escrita para papel sem `canWrite`; papel sem valores não
  recebe prompt de valores.
- **Roda no navegador: só `import type` do principal.** Import de valor puxa a
  service role para o bundle.
- Tool nova ou papel que muda de recorte → atualize o catálogo no mesmo PR.

## Chave em Usuários & Acessos

- Coluna/toggle "Acesso ao MCP" na lista de usuários, só para admin.
- `PATCH /api/admin/users/[id]` aceita `mcp_enabled` (boolean) com o mesmo guard de
  admin das outras mudanças de papel; teste de rota: não-admin → 403; valor não
  booleano → 400.
- Desligar corta na próxima tool (o principal é lido a cada chamada) — diga isso no
  tooltip da chave.
