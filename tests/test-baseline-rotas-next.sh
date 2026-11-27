#!/usr/bin/env bash
# rotas-next.py (pilares 01, 04 e 08 da baseline).
#
# O pilar 04 media rate limit no projeto inteiro: um 429 em qualquer arquivo e o check saía
# "medido". Num pentest de 11/2026 o login tinha limite e a busca do inbox, o lookup por
# telefone e o link por token não tinham. Também não havia check de segredo de máquina
# compartilhado entre famílias de rota, nem de COOP/CORP, robots.txt e security.txt.
#
# Este teste monta um projeto Next sintético e confere que:
#   - rota pública (excluída do matcher do middleware) com token no caminho e sem limite é acusada,
#     e a que chama um limitador não é;
#   - rota coberta pela sessão do middleware com busca livre é acusada como LOW;
#   - rota que compara header com segredo conta como autenticada (não vira "pública");
#   - um segredo de ENTRADA usado em duas famílias é acusado; token de SAÍDA e mapa de chaves não;
#   - COOP/CORP ausentes e HSTS sem preload são acusados, e somem quando declarados;
#   - robots.txt e security.txt ausentes são acusados, e somem quando existem;
#   - o collect.sh leva os achados para os pilares certos.
#
# Uso: bash tests/test-baseline-rotas-next.sh [rotas-next.py] [collect.sh]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
RN="${1:-$RAIZ/plugin/skills/baseline/scripts/rotas-next.py}"
COLLECT="${2:-$RAIZ/plugin/skills/baseline/scripts/collect.sh}"
[ -f "$RN" ] || { echo "script não encontrado: $RN"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 ausente"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq ausente — o collect.sh depende dele"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rotas-next.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
grava() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
tem()   { grep -q "$(printf 'ACHADO\t%s\t%s\t%s\t' "$2" "$3" "$4")" "$1"; }   # tem <saida> <pilar> <sev> <check>
nao()   { ! grep -q "$(printf '\t%s\t' "$2")" "$1" || ! grep "$(printf '\t%s\t' "$2")" "$1" | grep -q "^ACHADO"; }

P="$TMP/app"
printf '{"name":"fixture"}\n' | grava "$P/package.json"
grava "$P/src/middleware.ts" <<'EOF'
import { NextResponse } from "next/server";
export async function middleware(req) {
  const { data } = await supabase.auth.getUser();
  if (!data.user) return NextResponse.redirect(new URL("/login", req.url));
}
export const config = {
  matcher: ["/((?!_next/static|favicon.ico|api/r/|api/ingest|api/n8n|api/webhook).*)"],
};
EOF
grava "$P/next.config.ts" <<'EOF'
const headers = [
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains" },
];
export default { async headers() { return [{ source: "/(.*)", headers }]; } };
EOF
grava "$P/src/lib/maquina.ts" <<'EOF'
import { timingSafeEqual } from "node:crypto";
export function confere(req: Request) {
  const s = process.env.MAQUINA_SECRET ?? "";
  const h = req.headers.get("x-maquina-secret") ?? "";
  return s.length > 0 && s.length === h.length && timingSafeEqual(Buffer.from(s), Buffer.from(h));
}
EOF
grava "$P/src/lib/chaves.ts" <<'EOF'
import { timingSafeEqual } from "node:crypto";
const mapa = JSON.parse(process.env.INTEGRACAO_CHAVES ?? "{}");
export function confereChave(req: Request) {
  const id = req.headers.get("x-integracao") ?? ""; const k = mapa[id] ?? "";
  return timingSafeEqual(Buffer.from(k), Buffer.from(req.headers.get("x-chave") ?? ""));
}
EOF
grava "$P/src/lib/ia.ts" <<'EOF'
export async function pergunta(t: string) {
  return fetch("https://api.exemplo-ia.com/v1", { headers: { Authorization: `Bearer ${process.env.IA_API_KEY}` }, body: t });
}
EOF
grava "$P/src/lib/limite.ts" <<'EOF'
export async function limitar(chave: string) { return admin.rpc("rate_limit_take", { p_bucket: chave }); }
EOF
for r in ingest/a ingest/b n8n/c n8n/d; do
  grava "$P/src/app/api/$r/route.ts" <<'EOF'
import { confere } from "@/lib/maquina";
import { confereChave } from "@/lib/chaves";
import { pergunta } from "@/lib/ia";
export async function POST(req: Request) {
  if (!confere(req) && !confereChave(req)) return new Response(null, { status: 401 });
  await pergunta("x");
  return new Response("ok");
}
EOF
done
grava "$P/src/app/api/r/[token]/route.ts" <<'EOF'
export async function GET(req: Request, { params }) {
  const { token } = await params;
  return new Response(token);
}
EOF
grava "$P/src/app/api/r/limitada/[id]/route.ts" <<'EOF'
import { limitar } from "@/lib/limite";
export async function GET(req: Request) {
  await limitar("x");
  return new Response("ok");
}
EOF
grava "$P/src/app/api/busca/route.ts" <<'EOF'
export async function GET(req: Request) {
  const q = new URL(req.url).searchParams.get("q");
  return Response.json({ q });
}
EOF
grava "$P/src/app/api/webhook/[canal]/route.ts" <<'EOF'
export async function POST(req: Request) {
  if (req.headers.get("authorization") !== `Bearer ${process.env.WEBHOOK_SECRET}`) return new Response(null, { status: 401 });
  return new Response("ok");
}
EOF

python3 -I "$RN" --root "$P" > "$TMP/a.tsv" 2>"$TMP/a.err"; rc=$?
echo "· projeto sem limite nem headers (exit $rc)"
[ $rc -eq 0 ] && ok "sai 0" || falha "saiu $rc: $(head -3 "$TMP/a.err")"
tem "$TMP/a.tsv" 04 MEDIUM rate_limit_rota_publica && ok "rota pública por token sem limite acusada" || falha "rota pública por token passou calada"
grep "rate_limit_rota_publica" "$TMP/a.tsv" | grep -q "api/r/\[token\]" && ok "o exemplo é a rota por token" || falha "a rota por token não está no exemplo"
grep "rate_limit_rota_publica" "$TMP/a.tsv" | grep -q "limitada" && falha "rota com limitador acusada" || ok "rota que chama o limitador não é acusada"
grep "rate_limit_rota_publica" "$TMP/a.tsv" | grep -q "webhook" && falha "webhook com segredo tratado como público" || ok "comparar header com segredo conta como autenticado"
tem "$TMP/a.tsv" 04 LOW rate_limit_rota_sessao && ok "busca com sessão do middleware acusada (LOW)" || falha "busca com sessão passou calada"
grep "segredo_compartilhado" "$TMP/a.tsv" | grep -q "MAQUINA_SECRET" && ok "segredo de entrada em 2 famílias acusado" || falha "segredo de entrada compartilhado passou"
grep "segredo_compartilhado" "$TMP/a.tsv" | grep -q "IA_API_KEY" && falha "token de saída acusado como segredo compartilhado" || ok "token de saída fica de fora"
grep "segredo_compartilhado" "$TMP/a.tsv" | grep -q "INTEGRACAO_CHAVES" && falha "mapa de chaves acusado" || ok "mapa de chaves por integração fica de fora"
tem "$TMP/a.tsv" 01 LOW headers_isolamento && ok "COOP/CORP ausentes acusados" || falha "COOP/CORP ausentes passaram"
tem "$TMP/a.tsv" 01 INFO hsts_sem_preload && ok "HSTS sem preload acusado" || falha "HSTS sem preload passou"
tem "$TMP/a.tsv" 08 LOW robots_txt && ok "robots.txt ausente acusado" || falha "robots.txt ausente passou"
tem "$TMP/a.tsv" 08 INFO security_txt && ok "security.txt ausente acusado" || falha "security.txt ausente passou"

# ───────────── o mesmo projeto com headers, robots e security.txt
Q="$TMP/ok"; cp -R "$P" "$Q"
grava "$Q/next.config.ts" <<'EOF'
const headers = [
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
  { key: "Cross-Origin-Resource-Policy", value: "same-origin" },
];
export default { async headers() { return [{ source: "/(.*)", headers }]; } };
EOF
printf 'User-agent: *\nDisallow: /\n' | grava "$Q/public/robots.txt"
printf 'Contact: mailto:seguranca@exemplo.com\nExpires: 2027-12-31T00:00:00Z\n' | grava "$Q/public/.well-known/security.txt"
python3 -I "$RN" --root "$Q" > "$TMP/b.tsv" 2>&1
echo "· projeto com headers e arquivos"
for c in headers_isolamento hsts_sem_preload robots_txt security_txt; do
  grep -q "$(printf 'ACHADO\t[0-9]*\t[A-Z]*\t%s\t' "$c")" "$TMP/b.tsv" && falha "$c ainda acusado" || ok "$c some quando resolvido"
done

# ───────────── integração no collect.sh
if [ -f "$COLLECT" ]; then
  echo "· collect.sh --pilar 01,04,08"
  ( cd "$P" && git init -q -b main . && git config user.email t@t && git config user.name t \
      && git config commit.gpgsign false && git add -A && git commit -qm base ) >/dev/null 2>&1
  bash "$COLLECT" --root "$P" --out "$TMP/col" --pilar 01,04,08 >/dev/null 2>"$TMP/col.err"; rc=$?
  [ $rc -eq 0 ] || [ $rc -eq 1 ] && ok "collect sai $rc" || falha "collect saiu $rc: $(head -2 "$TMP/col.err")"
  for par in "04 rate_limit_rota_publica" "01 headers_isolamento" "08 robots_txt"; do
    set -- $par
    jq -e --arg p "$1" '.findings[] | select(.pilar==$p and (.ref|test("rotas do Next")))' "$TMP/col/findings.json" >/dev/null 2>&1 \
      && ok "pilar $1 recebe $2" || falha "pilar $1 sem $2 no findings.json"
  done
fi

echo
if [ $falhas -eq 0 ]; then echo "tudo verde"; exit 0; fi
echo "$falhas falha(s)"; exit 1
