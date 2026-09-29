// src/app/api/mcp/route.ts
import type { AuthInfo } from "@modelcontextprotocol/server";
import { createMcpHandler, withMcpAuth } from "mcp-handler";

import { getSupabaseAdmin } from "@/src/lib/supabase-admin";
import { instrumentTools, refuseListen } from "@/src/lib/mcp/instrument";
import { resolveMcpPrincipal, userIdFromOAuthClaims } from "@/src/lib/mcp/principal";
import { registerReadTools } from "@/src/lib/mcp/tools";
import { registerWriteTools } from "@/src/lib/mcp/write-tools";

export const runtime = "nodejs";
// Tamanho da tool mais pesada com cache frio. O deadline das tools fica abaixo.
export const maxDuration = 300;

const handler = createMcpHandler(
  (server) => {
    instrumentTools(server);
    registerReadTools(server);
    registerWriteTools(server);
  },
  {
    serverInfo: { name: "<nome>", version: "1.0.0" },
    instructions: "Dados do <sistema> (<domínios>) recortados pelo nível de acesso de quem fez login.",
  },
);

// Aceita só token do OAuth Server. Chave de serviço (x-api-key) é ignorada de
// propósito: no resto da API ela vira usuário "service" com poder de admin.
async function verifyToken(_req: Request, bearerToken?: string): Promise<AuthInfo | undefined> {
  if (!bearerToken) return undefined;

  const { data, error } = await getSupabaseAdmin().auth.getClaims(bearerToken);
  if (error || !data) return undefined;

  const ids = userIdFromOAuthClaims(data.claims as Record<string, unknown>);
  if (!ids) return undefined;

  const principal = await resolveMcpPrincipal(ids.userId);
  if (!principal.ok) return undefined;

  return {
    token: bearerToken,
    clientId: ids.clientId,
    scopes: [],
    expiresAt: typeof data.claims.exp === "number" ? data.claims.exp : undefined,
    extra: { userId: ids.userId },
  };
}

// Metadata com o path do recurso: o `resource` anunciado sai `.../api/mcp`,
// igual à URL que o cliente conectou.
const authHandler = withMcpAuth(refuseListen(handler), verifyToken, {
  required: true,
  resourceMetadataPath: "/.well-known/oauth-protected-resource/api/mcp",
});

export { authHandler as GET, authHandler as POST, authHandler as DELETE };
