// src/lib/mcp/confirm-token.ts
import { createHmac, timingSafeEqual } from "node:crypto";

// Token de confirmação das escritas do MCP: a prévia assina o que será feito e o
// estado lido; o aplicar só grava com o token intacto, do mesmo usuário, dentro
// de 5 minutos e com o estado ainda igual. Stateless — nada fica guardado entre
// as duas chamadas (o /api/mcp roda sem sessão na Vercel).

export const CONFIRM_TTL_MS = 5 * 60_000;

export type ConfirmPayload = {
  uid: string;
  kind: string;
  args: Record<string, unknown>;
  state: unknown;
};

type Opts = { secret?: string; now?: number };

// MCP_CONFIRM_SECRET quando existir; senão uma chave derivada da service role.
// Trocar a service role só invalida prévias em aberto.
function resolveSecret(secret?: string): string {
  if (secret) return secret;
  const explicit = process.env.MCP_CONFIRM_SECRET;
  if (explicit) return explicit;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceKey) throw new Error("Sem segredo para o token de confirmação do MCP.");
  return createHmac("sha256", serviceKey).update("mcp-confirm-token:v1").digest("hex");
}

function sign(body: string, secret: string) {
  return createHmac("sha256", secret).update(body).digest("base64url");
}

export function signConfirmToken(payload: ConfirmPayload, opts: Opts = {}): string {
  const exp = (opts.now ?? Date.now()) + CONFIRM_TTL_MS;
  const body = Buffer.from(JSON.stringify({ ...payload, exp })).toString("base64url");
  return `${body}.${sign(body, resolveSecret(opts.secret))}`;
}

export function verifyConfirmToken(
  token: string,
  opts: Opts = {},
): { ok: true; payload: ConfirmPayload } | { ok: false; reason: "invalido" | "expirado" } {
  const [body, sig, extra] = token.split(".");
  if (!body || !sig || extra !== undefined) return { ok: false, reason: "invalido" };
  const expected = Buffer.from(sign(body, resolveSecret(opts.secret)));
  const got = Buffer.from(sig);
  if (expected.length !== got.length || !timingSafeEqual(expected, got)) return { ok: false, reason: "invalido" };

  let parsed: ConfirmPayload & { exp: number };
  try {
    parsed = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  } catch {
    return { ok: false, reason: "invalido" };
  }
  if (typeof parsed.exp !== "number" || (opts.now ?? Date.now()) > parsed.exp) return { ok: false, reason: "expirado" };
  const { exp: _exp, ...payload } = parsed;
  return { ok: true, payload };
}
