// src/lib/mcp/instrument.ts
import type { McpServer } from "@modelcontextprotocol/server";

// Abaixo do maxDuration da rota (300s): a tool presa sai com log e erro legível
// em vez de a Vercel matar a função sem deixar rastro.
export const TOOL_DEADLINE_MS = 240_000;

type ToolResult = { isError?: boolean };

/** Envolve toda tool registrada com log de tempo (`[mcp] tool=X ms=Y ok|erro|timeout`) e deadline. */
export function instrumentTools(server: McpServer, deadlineMs = TOOL_DEADLINE_MS): McpServer {
  const register = server.registerTool.bind(server) as (name: string, config: unknown, cb: unknown) => unknown;
  server.registerTool = ((name: string, config: unknown, cb: (...args: unknown[]) => Promise<ToolResult>) =>
    register(name, config, async (...args: unknown[]) => {
      const started = Date.now();
      let timer: ReturnType<typeof setTimeout> | undefined;
      const deadline = new Promise<"timeout">((resolve) => {
        timer = setTimeout(() => resolve("timeout"), deadlineMs);
      });
      try {
        const result = await Promise.race([cb(...args), deadline]);
        const outcome = result === "timeout" ? "timeout" : result.isError ? "erro" : "ok";
        console.info(`[mcp] tool=${name} ms=${Date.now() - started} ${outcome}`);
        if (result !== "timeout") return result;
        return {
          content: [{ type: "text" as const, text: "A consulta demorou demais e foi interrompida. Tente de novo." }],
          isError: true,
        };
      } finally {
        clearTimeout(timer);
      }
    })) as McpServer["registerTool"];
  return server;
}

// `subscriptions/listen` (protocolo 2026-07-28) abre um SSE que nunca fecha: em
// função serverless ele fica preso até o maxDuration e ocupa uma conexão do
// cliente, que passa a enfileirar as tools. O servidor não emite notificação
// (tools fixas), então recusar como método inexistente não tira nada do cliente.
export function refuseListen(handler: (req: Request) => Promise<Response>) {
  return async (req: Request): Promise<Response> => {
    if (req.method === "POST") {
      const body: unknown = await req
        .clone()
        .json()
        .catch(() => null);
      if (body && typeof body === "object" && !Array.isArray(body) && (body as { method?: unknown }).method === "subscriptions/listen") {
        const id = (body as { id?: unknown }).id ?? null;
        return Response.json({
          jsonrpc: "2.0",
          id,
          error: { code: -32601, message: "Este servidor não oferece subscriptions/listen." },
        });
      }
    }
    return handler(req);
  };
}

/* Testes (vitest) que acompanham este arquivo:
 * - repassa args e loga `[mcp] tool=<nome> ms=\d+ ok`
 * - tool que nunca resolve + fake timers → isError com "demorou demais" e log `timeout`
 * - resultado isError → log `erro`
 * - refuseListen: listen → handler NÃO chamado, status 200, error.code -32601, mesmo id
 * - refuseListen: tools/call passa com o corpo intacto; GET e corpo inválido passam
 */
