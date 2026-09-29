// src/lib/mcp/tools.ts (base) — helpers + o padrão de uma tool de leitura
import type { McpServer, ServerContext } from "@modelcontextprotocol/server";
import { z } from "zod";

import { DENY_MESSAGE, resolveMcpPrincipal, type McpPrincipal } from "./principal";
import { periodRange, resolveMcpScope } from "./scope";

const READ_ONLY = { readOnlyHint: true, openWorldHint: false } as const;

export function text(value: string, isError = false) {
  return { content: [{ type: "text" as const, text: value }], ...(isError ? { isError: true } : {}) };
}

export function json(value: unknown) {
  return text(JSON.stringify(value));
}

// Toda tool resolve o principal de novo (desligar em Usuários corta na próxima
// chamada) e nunca vaza stack de erro para o cliente.
export async function run(ctx: ServerContext, fn: (principal: McpPrincipal) => Promise<ReturnType<typeof text>>) {
  const userId = ctx.http?.authInfo?.extra?.userId;
  if (typeof userId !== "string") return text("Sessão MCP sem usuário.", true);
  try {
    const result = await resolveMcpPrincipal(userId);
    if (!result.ok) return text(DENY_MESSAGE[result.reason], true);
    return await fn(result.principal);
  } catch (err) {
    console.error("[mcp] tool falhou:", err);
    // Só mensagens de validação conhecidas passam; o resto vira erro genérico.
    const message = err instanceof Error && /^(Período|O período)/.test(err.message) ? err.message : "Falha ao consultar. Tente de novo.";
    return text(message, true);
  }
}

const periodoParam = z
  .string()
  .regex(/^\d{4}-\d{2}$/)
  .optional()
  .describe("Mês no formato YYYY-MM. Padrão: mês corrente.");

export function registerReadTools(server: McpServer) {
  server.registerTool(
    "whoami",
    {
      title: "Quem sou eu",
      description: "Mostra com qual conta o agente está conectado, o nível de acesso e o time. Use para testar a conexão.",
      annotations: READ_ONLY,
    },
    async (ctx) =>
      run(ctx, async (p) =>
        text([`Conectado como ${p.name ?? p.email} (${p.email}).`, `Nível de acesso: ${p.role}.`, p.group ? `Time: ${p.group}.` : "Sem time vinculado."].join("\n")),
      ),
  );

  // Padrão: carrega pela MESMA lib do app → escopo do período → projeção pura.
  server.registerTool(
    "resumo_periodo",
    {
      title: "Resumo do período",
      description: "Resumo do mês pelo mesmo cálculo da tela. Diretoria vê tudo; gerente, o time; membro, o próprio e o total do time.",
      inputSchema: z.object({ mes: periodoParam }),
      annotations: READ_ONLY,
    },
    async ({ mes }, ctx) =>
      run(ctx, async (p) => {
        const range = periodRange(mes);
        const data = await loadResumo(range.from, range.to); // lib do app, com cache entre instâncias
        const scope = resolveMcpScope(p, data.hierarchy);
        return json({ mes: range.key, ...projectResumo(data.rows, scope) });
      }),
  );
}

// Declarações só para o esqueleto compilar na cabeça de quem lê.
declare function loadResumo(from: string, to: string): Promise<{ rows: unknown[]; hierarchy: unknown }>;
declare function projectResumo(rows: unknown[], scope: ReturnType<typeof resolveMcpScope>): Record<string, unknown>;
