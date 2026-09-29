// src/app/oauth/consent/page.tsx — tela do OAuth Server (authorization_url_path).
// Classes/tokens abaixo são placeholders: use o design system do projeto alvo.
import { redirect } from "next/navigation";

import { DENY_MESSAGE, resolveMcpPrincipal } from "@/src/lib/mcp/principal";
import { createClient } from "@/src/utils/supabase/server";

export const dynamic = "force-dynamic";

// Uma linha por papel: o que o agente enxerga. Mesma fonte da página MCP.
const ACESSO_POR_PAPEL = {
  admin: "todos os registros e times",
  manager: "o seu time",
  member: "os seus próprios dados",
  support: "a operação, sem valores por pessoa",
} as const;

// O proxy já garantiu sessão + MFA; aqui só decide se esta conta pode ligar um agente.
export default async function ConsentPage({ searchParams }: { searchParams: Promise<{ authorization_id?: string }> }) {
  const { authorization_id: authorizationId } = await searchParams;
  if (!authorizationId) return <Shell titulo="Pedido inválido" texto="Falta o authorization_id." />;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    redirect(`/login?redirect=${encodeURIComponent(`/oauth/consent?authorization_id=${authorizationId}`)}`);
  }

  const { data: details, error } = await supabase.auth.oauth.getAuthorizationDetails(authorizationId);
  if (error || !details) return <Shell titulo="Pedido expirado" texto="Volte ao seu agente e conecte de novo." />;
  // Consentimento já dado antes: o Supabase devolve direto o redirect.
  if (!("authorization_id" in details)) redirect(details.redirect_url);

  const principal = await resolveMcpPrincipal(user.id);
  const clientName = details.client.name || "Um agente";

  if (!principal.ok) {
    return (
      <Shell titulo="Acesso ao MCP não liberado" texto={DENY_MESSAGE[principal.reason]}>
        <DecisionForm authorizationId={authorizationId} somenteRecusar />
      </Shell>
    );
  }

  const p = principal.principal;
  return (
    <Shell titulo={`Conectar ${clientName} ao <sistema>`} texto={`${clientName} vai consultar o <sistema> em seu nome, como ${p.email}.`}>
      <dl className="mt-6 space-y-3 rounded border p-4 text-sm">
        <div>
          <dt className="text-xs uppercase">O agente enxerga</dt>
          <dd className="mt-1">{ACESSO_POR_PAPEL[p.role]}</dd>
        </div>
        <div>
          <dt className="text-xs uppercase">Volta para</dt>
          <dd className="mt-1 break-all font-mono text-xs">{details.redirect_uri}</dd>
        </div>
      </dl>
      <p className="mt-4 text-xs">Ações que alteram dados sempre mostram uma prévia e pedem sua confirmação no agente.</p>
      <DecisionForm authorizationId={authorizationId} />
    </Shell>
  );
}

function Shell({ titulo, texto, children }: { titulo: string; texto: string; children?: React.ReactNode }) {
  return (
    <main className="flex min-h-screen items-center justify-center px-4 py-10">
      <section className="w-full max-w-md rounded border p-6">
        <p className="text-xs font-semibold uppercase tracking-widest">MCP · &lt;sistema&gt;</p>
        <h1 className="mt-2 text-xl font-semibold">{titulo}</h1>
        <p className="mt-2 text-sm">{texto}</p>
        {children}
      </section>
    </main>
  );
}

function DecisionForm({ authorizationId, somenteRecusar }: { authorizationId: string; somenteRecusar?: boolean }) {
  return (
    <form action="/api/oauth/decision" method="POST" className="mt-6 flex gap-3">
      <input type="hidden" name="authorization_id" value={authorizationId} />
      <button type="submit" name="decision" value="deny" className="flex-1 rounded border px-4 py-2.5 text-sm">
        {somenteRecusar ? "Voltar ao agente" : "Recusar"}
      </button>
      {!somenteRecusar && (
        <button type="submit" name="decision" value="approve" className="flex-1 rounded px-4 py-2.5 text-sm font-semibold">
          Permitir acesso
        </button>
      )}
    </form>
  );
}
