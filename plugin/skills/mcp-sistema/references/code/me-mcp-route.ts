// src/app/api/me/mcp/route.ts
import { NextResponse } from "next/server";

import { requireAuth } from "@/src/lib/api-auth"; // guard de sessão do projeto
import { principalFromRows, type McpRole } from "@/src/lib/mcp/principal";
import { getSupabaseAdmin } from "@/src/lib/supabase-admin";

export const dynamic = "force-dynamic";

const ROLES: readonly McpRole[] = ["admin", "manager", "member", "support"];

// Estado do MCP do usuário da sessão, para a página MCP e o item do menu.
// `enabled` usa a mesma regra do servidor (principalFromRows), lido só por
// auth_user_id, como o /api/mcp.
export async function GET(request: Request) {
  const auth = await requireAuth(request as never);
  if (auth.error) return auth.error;

  const { data, error } = await getSupabaseAdmin()
    .from("app_users")
    .select("email, full_name, role, is_active, mcp_enabled")
    .eq("auth_user_id", auth.user.id)
    .maybeSingle();

  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  if (!data) return NextResponse.json({ enabled: false, role: null });

  const role = ROLES.find((r) => r === data.role) ?? null;
  const verdict = principalFromRows(auth.user.id, data, null);
  return NextResponse.json({ enabled: verdict.ok, role });
}
