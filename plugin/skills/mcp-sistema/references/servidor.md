# Servidor — `/api/mcp`, principal, escopo e tools

## Dependências

`mcp-handler` + `@modelcontextprotocol/server` + `zod`. Confira as versões com a
`find-docs` antes de instalar: o SDK serve os dois protocolos (2025 stateless
e `2026-07-28`) pela mesma entrada, e a API de `registerTool` muda entre majors.

Transporte: Streamable HTTP stateless, uma instância de servidor por request.
Nada de estado em memória entre chamadas: a Vercel espalha requests paralelos por
instâncias diferentes.

## Rota (`code/route.ts`)

Ordem das camadas, de fora para dentro:

```
withMcpAuth(verifyToken, required)   → 401 + WWW-Authenticate sem Bearer válido
  refuseListen                       → subscriptions/listen = -32601 na hora
    createMcpHandler(server => {
      instrumentTools(server)        → log de tempo + deadline por tool
      registerReadTools(server)
      registerWriteTools(server)
    })
```

- `runtime = "nodejs"`, `maxDuration` do tamanho da tool mais pesada com cache
  frio (300 no plano Pro). O deadline das tools fica abaixo dele.
- `resourceMetadataPath` com o path do recurso
  (`/.well-known/oauth-protected-resource/api/mcp`), para o `resource` anunciado
  bater com a URL que o cliente conectou.
- `instructions` do servidor: 1 frase do que o sistema expõe e que o recorte é
  pelo nível de acesso de quem fez login.

## `verifyToken`

1. `auth.getClaims(bearer)` com o client de service role (valida pelo JWKS).
2. Exige `role === "authenticated"`, `sub` e **`client_id`**
   (`userIdFromOAuthClaims` em `code/principal.ts`).
3. Resolve o principal; recusado → `undefined` (vira 401).
4. Devolve `{ token, clientId, scopes: [], expiresAt, extra: { userId } }`.

## Principal (`code/principal.ts`)

- Lê a tabela de papel por `auth_user_id` **a cada tool** (não só no token):
  desligar em Usuários corta na próxima chamada.
- `principalFromRows` é pura e é a MESMA usada pela página (`GET /api/me/mcp`) e
  pelo consentimento — as três telas nunca discordam de quem entra.
- Motivos de recusa com mensagem própria: sem cadastro, inativo, MCP desligado,
  papel inválido.

## `run()` — invólucro de toda tool

Resolve o principal de novo, chama a função, e nunca devolve stack ao cliente
(erro genérico "Falha ao consultar. Tente de novo." + `console.error` no servidor;
só mensagens de validação conhecidas passam). Ver `code/tools-base.ts`.

## Escopo (`code/scope.ts`)

Função pura `resolveMcpScope(principal, hierarquiaDoPeriodo)` que devolve:

```ts
type McpScope = {
  role: McpRole;
  memberId: string | null;          // registro de negócio da própria pessoa
  memberIds: "all" | string[];      // registros visíveis
  groups: "all" | string[];         // times/áreas visíveis NO PERÍODO consultado
  valuesByMember: boolean;          // ex.: suporte = false
  canWrite: boolean;                // gestão
};
```

Toda tool: carrega os dados pela lib que o app já usa → `resolveMcpScope` →
`project*` (função pura por tool que corta linhas e campos). Testes de escopo
por papel vêm ANTES das tools (TDD): vendedor pedindo colega, gerente fora do
time, papel sem valores pedindo valores, linha sem vínculo (só admin vê).

Identidade sempre por uuid do registro de negócio. Se a lib do app identifica
linhas por nome, mapeie nome → uuid com a hierarquia do período e descarte o que
não mapear (só admin vê linha sem uuid).

## Tools de leitura — convenções

- Nome em `snake_case` no idioma do usuário (`faturamento_resumo`,
  `pedidos_listar`), `title` curto, `description` dizendo o recorte por papel.
- `annotations: { readOnlyHint: true, openWorldHint: false }`.
- Parâmetro de período com default (mês corrente no fuso do negócio) e recusa de
  período futuro com mensagem legível.
- `limite` com default e máximo; responda `{ total, truncado, itens }`.
- Nunca devolva ids sintéticos internos nem campos que o papel não vê.
- `whoami` é a primeira tool (teste de conexão da página).
- Listas sem filtro de status abrem pelo que importa (abertas, mais recentes);
  ordem crescente por prazo abre com lixo antigo.

## `refuseListen` e `instrumentTools` (`code/instrument.ts`)

- `refuseListen`: POST com `method: "subscriptions/listen"` → JSON-RPC
  `{ error: { code: -32601 } }` com o mesmo `id`, sem chegar ao SDK. O servidor
  não emite notificação (tools fixas), então não tira nada do cliente.
- `instrumentTools`: envolve `server.registerTool` uma vez; cada chamada loga
  `[mcp] tool=<nome> ms=<n> ok|erro|timeout` e corre contra um deadline (240 s
  com `maxDuration` 300) que devolve erro legível em vez de a Vercel matar a
  função sem rastro.

Diagnóstico de lentidão: `vercel logs --query "/api/mcp"` + as linhas `[mcp] tool=`.
POST que termina exatamente no `maxDuration` sem linha `[mcp]` é stream, não tool.

## Tool pesada

Se a mesma lib cara é chamada por várias tools (ex.: faturamento, metas, ranking
e top clientes recalculam o mesmo mês), o cache tem que ser ENTRE instâncias
(`unstable_cache` com tag, ou tabela de snapshot). Promise em voo em memória só
ajuda chamadas que caem na mesma instância — em produção, 4 tools paralelas deram
4 recálculos.
