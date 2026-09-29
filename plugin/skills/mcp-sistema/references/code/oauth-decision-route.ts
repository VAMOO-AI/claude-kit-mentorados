// src/app/api/oauth/decision/route.ts
import { NextResponse } from "next/server";

import { resolveMcpPrincipal } from "@/src/lib/mcp/principal";
import { createClient } from "@/src/utils/supabase/server";

// Decisão da tela /oauth/consent. Aprovar exige de novo o gate do MCP: o form
// é HTML puro e o POST poderia chegar com decision=approve mesmo quando a tela
// só ofereceu "Voltar ao agente".
export async function POST(request: Request) {
  const form = await request.formData();
  const authorizationId = form.get("authorization_id");
  const decision = form.get("decision");
  if (typeof authorizationId !== "string" || !authorizationId) {
    return NextResponse.json({ error: "authorization_id ausente" }, { status: 400 });
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const aprova = decision === "approve" && (await resolveMcpPrincipal(user.id)).ok;
  const { data, error } = aprova
    ? await supabase.auth.oauth.approveAuthorization(authorizationId, { skipBrowserRedirect: true })
    : await supabase.auth.oauth.denyAuthorization(authorizationId, { skipBrowserRedirect: true });

  if (error || !data) return NextResponse.json({ error: error?.message ?? "Falha na autorização" }, { status: 400 });
  return NextResponse.redirect(data.redirect_url, 303);
}
