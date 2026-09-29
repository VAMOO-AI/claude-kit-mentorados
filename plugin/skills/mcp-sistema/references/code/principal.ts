// src/lib/mcp/principal.ts
import { getSupabaseAdmin } from "@/src/lib/supabase-admin";

// Quem está do outro lado do MCP. O papel vem de UMA fonte (a tabela de
// usuários do app), lida a cada chamada: desativar lá revoga na próxima tool.
// Adapte: nome da tabela de usuários, papéis e tabela de negócio (`members`).
export type McpRole = "admin" | "manager" | "member" | "support";

export type McpPrincipal = {
  authUserId: string;
  email: string;
  name: string | null;
  role: McpRole;
  memberId: string | null; // registro de negócio (vendedor, colaborador…)
  group: string | null; // time/área atual; o recorte de período usa a hierarquia do período
};

export type McpDenyReason = "sem_cadastro" | "inativo" | "mcp_desligado" | "papel_invalido";

type AppUserRow = {
  email: string;
  full_name: string | null;
  role: string | null;
  is_active: boolean | null;
  mcp_enabled: boolean | null;
};

type MemberRow = { id: string; group: string | null };

const ROLES: readonly McpRole[] = ["admin", "manager", "member", "support"];

// Só o token emitido pelo OAuth Server carrega `client_id`. Sem essa exigência,
// o JWT da sessão web (mesma assinatura, mesmo `aud`) também abriria o MCP.
export function userIdFromOAuthClaims(claims: Record<string, unknown>): { userId: string; clientId: string } | null {
  if (claims.role !== "authenticated") return null;
  const userId = typeof claims.sub === "string" ? claims.sub : null;
  const clientId = typeof claims.client_id === "string" ? claims.client_id : null;
  if (!userId || !clientId) return null;
  return { userId, clientId };
}

// Pura: a MESMA decisão serve o servidor, o consentimento e GET /api/me/mcp.
export function principalFromRows(
  authUserId: string,
  appUser: AppUserRow | null,
  member: MemberRow | null,
): { ok: true; principal: McpPrincipal } | { ok: false; reason: McpDenyReason } {
  if (!appUser) return { ok: false, reason: "sem_cadastro" };
  if (!appUser.is_active) return { ok: false, reason: "inativo" };
  if (!appUser.mcp_enabled) return { ok: false, reason: "mcp_desligado" };
  const role = ROLES.find((r) => r === appUser.role);
  if (!role) return { ok: false, reason: "papel_invalido" };

  return {
    ok: true,
    principal: {
      authUserId,
      email: appUser.email,
      name: appUser.full_name,
      role,
      memberId: member?.id ?? null,
      group: member?.group ?? null,
    },
  };
}

export async function resolveMcpPrincipal(authUserId: string) {
  const admin = getSupabaseAdmin();
  const [appUser, member] = await Promise.all([
    admin
      .from("app_users")
      .select("email, full_name, role, is_active, mcp_enabled")
      .eq("auth_user_id", authUserId)
      .maybeSingle(),
    // Vínculo por auth_user_id, nunca por nome (homônimos).
    admin.from("members").select("id, group").eq("auth_user_id", authUserId).maybeSingle(),
  ]);
  if (appUser.error) throw appUser.error;
  if (member.error) throw member.error;
  return principalFromRows(authUserId, appUser.data, member.data);
}

export const DENY_MESSAGE: Record<McpDenyReason, string> = {
  sem_cadastro: "Sua conta não está cadastrada em Usuários & Acessos.",
  inativo: "Sua conta está desativada.",
  mcp_desligado: "O acesso ao MCP não foi liberado para a sua conta. Peça ao administrador.",
  papel_invalido: "Sua conta não tem um nível de acesso válido para o MCP.",
};
