// src/lib/mcp/scope.ts — recorte por papel, PURO e testado antes das tools.
import type { McpPrincipal, McpRole } from "./principal";

/** Hierarquia do PERÍODO consultado (quem estava em qual time naquele mês). */
export type Hierarchy = { activeMembers: readonly { id: string; group: string }[] };

export type McpScope = {
  role: McpRole;
  memberId: string | null;
  group: string | null; // time da pessoa no período
  memberIds: "all" | string[];
  groups: "all" | string[];
  valuesByMember: boolean;
  canWrite: boolean;
};

export function resolveMcpScope(p: McpPrincipal, h: Hierarchy): McpScope {
  const own = p.memberId ? h.activeMembers.find((m) => m.id === p.memberId) : undefined;
  const group = own?.group ?? null;
  switch (p.role) {
    case "admin":
      return { role: p.role, memberId: p.memberId, group, memberIds: "all", groups: "all", valuesByMember: true, canWrite: true };
    case "support":
      return { role: p.role, memberId: p.memberId, group, memberIds: "all", groups: "all", valuesByMember: false, canWrite: false };
    case "manager": {
      const ids = group ? h.activeMembers.filter((m) => m.group === group).map((m) => m.id) : [];
      return { role: p.role, memberId: p.memberId, group, memberIds: ids, groups: group ? [group] : [], valuesByMember: true, canWrite: true };
    }
    case "member":
      return {
        role: p.role,
        memberId: p.memberId,
        group,
        memberIds: p.memberId ? [p.memberId] : [],
        groups: group ? [group] : [],
        valuesByMember: true,
        canWrite: false,
      };
  }
}

/** Linha sem vínculo (memberId null) só aparece para quem vê tudo. */
export function canSeeMember(scope: McpScope, memberId: string | null): boolean {
  if (scope.memberIds === "all") return true;
  return memberId != null && scope.memberIds.includes(memberId);
}

/** Período YYYY-MM → intervalo; padrão = mês corrente no fuso do negócio; futuro é recusado. */
export function periodRange(mes: string | undefined, today = new Date().toISOString().slice(0, 10)) {
  const key = mes ?? today.slice(0, 7);
  if (key > today.slice(0, 7)) throw new Error(`O período ${key} ainda não começou.`);
  const [y, m] = key.split("-").map(Number);
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const from = `${key}-01`;
  const to = key === today.slice(0, 7) ? today : `${key}-${String(last).padStart(2, "0")}`;
  return { key, from, to };
}

/* Testes que vêm ANTES das tools (um por fronteira):
 * - member pedindo dado de colega → não aparece
 * - manager: vê o próprio time do PERÍODO; quem trocou de time no mês seguinte segue no antigo
 * - support: valuesByMember=false → tools de valor recusam
 * - linha sem memberId: só admin
 * - agregados (ranking/top N): member recebe a própria posição + total do time, sem valores de colegas
 */
