// src/app/.well-known/oauth-protected-resource/[[...path]]/route.ts
import { metadataCorsOptionsRequestHandler, protectedResourceHandler } from "mcp-handler";

// RFC 9728: diz ao cliente MCP que quem emite token para /api/mcp é o OAuth
// Server do Supabase Auth. O catch-all atende `/.well-known/oauth-protected-resource`
// e a variante com o path do recurso (`.../oauth-protected-resource/api/mcp`),
// que clientes mais novos consultam primeiro.
const handler = protectedResourceHandler({
  authServerUrls: [`${process.env.NEXT_PUBLIC_SUPABASE_URL}/auth/v1`],
});

const corsHandler = metadataCorsOptionsRequestHandler();

export { handler as GET, corsHandler as OPTIONS };
