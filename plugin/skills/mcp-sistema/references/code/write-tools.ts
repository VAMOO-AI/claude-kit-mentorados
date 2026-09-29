// src/lib/mcp/write-tools.ts — gerador de prévia/aplicar + um exemplo.
import type { McpServer, ServerContext } from "@modelcontextprotocol/server";
import { z } from "zod";

import { finishAudit, startAudit } from "./audit-log";
import { signConfirmToken, verifyConfirmToken } from "./confirm-token";
import type { McpPrincipal } from "./principal";
import { json, run, text } from "./tools";

type Prepared =
  | { ok: false; motivo: string }
  | {
      ok: true;
      resumo: string;
      antes: unknown;
      depois: unknown;
      /** Estado lido na prévia; o aplicar recusa se mudou. */
      state: unknown;
      apply: () => Promise<void>;
    };

type WriteKind<Args extends Record<string, unknown>> = {
  name: string;
  title: string;
  description: string;
  inputSchema: z.ZodType<Args>;
  /** false = cria algo novo; true = sobrescreve um valor existente. */
  destructive: boolean;
  /** MESMA função na prévia e no aplicar, sempre com dados relidos (sem cache). */
  prepare: (principal: McpPrincipal, args: Args) => Promise<Prepared>;
};

const denied = (motivo: string) => text(motivo, true);

export function registerWrite<Args extends Record<string, unknown>>(server: McpServer, kind: WriteKind<Args>) {
  server.registerTool(
    `${kind.name}_previa`,
    {
      title: `${kind.title} (prévia)`,
      description: `${kind.description} NÃO grava: devolve o antes/depois e um confirm_token. Mostre a prévia ao usuário e só chame ${kind.name}_aplicar se ele confirmar.`,
      inputSchema: kind.inputSchema,
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async (args: Args, ctx: ServerContext) =>
      run(ctx, async (p) => {
        const prep = await kind.prepare(p, args);
        if (!prep.ok) return denied(prep.motivo);
        const confirm_token = signConfirmToken({ uid: p.authUserId, kind: kind.name, args, state: prep.state });
        return json({
          previa: prep.resumo,
          antes: prep.antes,
          depois: prep.depois,
          confirm_token,
          validade: "5 minutos",
          proximo_passo: `Peça confirmação ao usuário; se ele aprovar, chame ${kind.name}_aplicar com este confirm_token.`,
        });
      }),
  );

  server.registerTool(
    `${kind.name}_aplicar`,
    {
      title: `${kind.title} (aplicar)`,
      description: `Aplica a alteração de uma prévia de ${kind.name}_previa que o usuário confirmou. Altera dados e fica registrado.`,
      inputSchema: z.object({ confirm_token: z.string().min(10) }),
      annotations: { readOnlyHint: false, destructiveHint: kind.destructive, idempotentHint: false, openWorldHint: false },
    },
    async ({ confirm_token }: { confirm_token: string }, ctx: ServerContext) =>
      run(ctx, async (p) => {
        const token = verifyConfirmToken(confirm_token);
        if (!token.ok) {
          return denied(token.reason === "expirado" ? `A prévia expirou. Chame ${kind.name}_previa de novo.` : "confirm_token inválido.");
        }
        const { payload } = token;
        if (payload.kind !== kind.name) return denied(`Este token é de ${payload.kind}, não de ${kind.name}.`);
        if (payload.uid !== p.authUserId) return denied("Este token foi emitido para outra conta.");

        const prep = await kind.prepare(p, payload.args as Args);
        if (!prep.ok) return denied(prep.motivo);
        if (JSON.stringify(prep.state) !== JSON.stringify(payload.state)) {
          return denied(`O dado mudou desde a prévia. Chame ${kind.name}_previa de novo e confirme com o usuário.`);
        }

        let auditId: string;
        try {
          auditId = await startAudit({
            principal: p,
            clientId: ctx.http?.authInfo?.clientId ?? null,
            tool: `${kind.name}_aplicar`,
            args: payload.args,
            antes: prep.antes,
            depois: prep.depois,
          });
        } catch (err) {
          console.error("[mcp] log de auditoria indisponível:", err);
          return denied("Alteração não aplicada: o registro de auditoria está indisponível.");
        }
        try {
          await prep.apply();
        } catch (err) {
          await finishAudit(auditId, { ok: false, erro: err instanceof Error ? err.message : String(err) });
          throw err;
        }
        await finishAudit(auditId, { ok: true });
        return json({ aplicado: true, resumo: prep.resumo, depois: prep.depois });
      }),
  );
}

/* Exemplo de kind (ajustar meta de um membro):
registerWrite(server, {
  name: "meta_ajustar",
  title: "Ajustar meta",
  description: "Ajusta a meta mensal de um membro do seu time.",
  inputSchema: z.object({ membro: z.string().min(2), mes: z.string().regex(/^\d{4}-\d{2}$/), meta: z.number() }),
  destructive: true,
  prepare: async (p, args) => {
    const hierarquia = await loadHierarchy(args.mes);          // relido, sem cache
    const scope = resolveMcpScope(p, hierarquia);
    const alvo = findMembers(hierarquia, scope, args.membro);  // só dentro do escopo
    if (alvo.length !== 1) return { ok: false, motivo: alvo.length ? "Nome ambíguo." : "Membro fora do seu acesso." };
    const atual = await readMeta(alvo[0].id, args.mes);
    const plan = planMeta({ scope, membro: alvo[0], metaAtual: atual, metaNova: args.meta }); // pura, testada
    if (!plan.ok) return plan;
    return {
      ok: true, resumo: `Meta de ${alvo[0].name} em ${args.mes}: ${atual ?? "—"} → ${args.meta}`,
      antes: plan.antes, depois: plan.depois, state: { atual },
      apply: () => upsertMeta(alvo[0].id, args.mes, args.meta),  // mesma função da rota do app
    };
  },
});
*/
