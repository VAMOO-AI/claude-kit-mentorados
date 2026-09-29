// src/lib/mcp/audit-log.ts
import { getSupabaseAdmin } from "@/src/lib/supabase-admin";

import type { McpPrincipal } from "./principal";

// mcp_audit_log. A linha nasce ANTES da gravação: se o log falhar, a escrita não
// acontece — não existe alteração pelo MCP sem rastro.

export async function startAudit(entry: {
  principal: McpPrincipal;
  clientId: string | null;
  tool: string;
  args: unknown;
  antes: unknown;
  depois: unknown;
}): Promise<string> {
  const { data, error } = await getSupabaseAdmin()
    .from("mcp_audit_log")
    .insert({
      auth_user_id: entry.principal.authUserId,
      email: entry.principal.email,
      role: entry.principal.role,
      client_id: entry.clientId,
      tool: entry.tool,
      args: entry.args,
      antes: entry.antes,
      depois: entry.depois,
    })
    .select("id")
    .single();
  if (error || !data) throw new Error(`mcp_audit_log indisponível: ${error?.message ?? "sem id"}`);
  return (data as { id: string }).id;
}

export async function finishAudit(id: string, result: { ok: true } | { ok: false; erro: string }) {
  const { error } = await getSupabaseAdmin()
    .from("mcp_audit_log")
    .update({
      status: result.ok ? "aplicado" : "falhou",
      erro: result.ok ? null : result.erro,
      finished_at: new Date().toISOString(),
    })
    .eq("id", id);
  if (error) console.error("[mcp] falha ao fechar o log de auditoria", id, error.message);
}
