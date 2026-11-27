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
# includeSubDomains (e o preload, que o exige) tranca no navegador o subdomínio sem TLS válido:
# o achado tem que mandar conferir o TLS de cada subdomínio antes, não só "ligue e envie".
grep "hsts_sem_preload" "$TMP/a.tsv" | grep -q "TLS válido na 443" && ok "achado de HSTS manda conferir o TLS dos subdomínios antes" || falha "achado de HSTS receita includeSubDomains/preload sem conferir o TLS dos subdomínios"
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

# ───────────── Server Actions: o login e o formulário público do App Router não são route.ts
# Em três pentests de 11/2026 o login, o reset de senha e o formulário de lead eram Server
# Action, o script só lia route.ts e a cobertura dizia "medido".
A="$TMP/actions"
printf '{"name":"fixture"}\n' | grava "$A/package.json"
grava "$A/src/app/login/actions.ts" <<'FIM'
"use server";
import { createClient } from "@/lib/supabase";
export async function signIn(form: FormData) {
  const supabase = await createClient();
  return supabase.auth.signInWithPassword({ email: form.get("email"), password: form.get("password") });
}
FIM
grava "$A/src/lib/supabase.ts" <<'FIM'
export async function createClient() { return null as any; }
FIM
grava "$A/src/app/site/actions.ts" <<'FIM'
'use server'
import { admin } from "@/lib/supabase";
export async function enviarInteresse(form: FormData) {
  await admin.from("leads").insert({ nome: form.get("nome") });
}
FIM
grava "$A/src/app/painel/actions.ts" <<'FIM'
"use server";
export async function salvar(form: FormData) {
  const { data } = await supabase.auth.getUser();
  await supabase.from("notas").insert({ dono: data.user.id });
}
FIM
python3 -I "$RN" --root "$A" > "$TMP/act.tsv" 2>&1
echo "· server actions sem limite"
tem "$TMP/act.tsv" 04 MEDIUM rate_limit_action_auth && ok "login por Server Action sem limite é acusado" || falha "login por Server Action passou: $(cat "$TMP/act.tsv")"
grep "rate_limit_action_auth" "$TMP/act.tsv" | grep -q "src/app/login/actions.ts" && ok "aponta o arquivo do login" || falha "não aponta src/app/login/actions.ts"
tem "$TMP/act.tsv" 04 MEDIUM rate_limit_action_publica && ok "action pública que grava sem limite é acusada" || falha "action pública que grava passou"
grep "rate_limit_action_publica" "$TMP/act.tsv" | grep -q "painel/actions.ts" && falha "action com sessão virou pública" || ok "action com sessão não é acusada como pública"
grep -q "$(printf 'COBERTURA\t04\tserver_actions\tmedido\t3 ')" "$TMP/act.tsv" && ok "cobertura diz quantos arquivos 'use server' leu" || falha "cobertura de server_actions ausente: $(grep server_actions "$TMP/act.tsv")"

# o mesmo projeto com o limitador chamado por RPC com nome próprio (o formato real dos fixes)
grava "$A/src/lib/throttle.ts" <<'FIM'
export async function tentativaBloqueada(chave: string) {
  const { data } = await admin.rpc("login_rate_limit", { p_chave: chave });
  return !data;
}
FIM
grava "$A/src/app/login/actions.ts" <<'FIM'
"use server";
import { createClient } from "@/lib/supabase";
import { tentativaBloqueada } from "@/lib/throttle";
export async function signIn(form: FormData) {
  if (await tentativaBloqueada("x")) return { erro: "muitas tentativas" };
  const supabase = await createClient();
  return supabase.auth.signInWithPassword({ email: form.get("email"), password: form.get("password") });
}
FIM
grava "$A/src/app/site/actions.ts" <<'FIM'
'use server'
export async function enviarInteresse(form: FormData) {
  const { data: ok } = await admin.rpc('site_lead_rate_limit', { p_ip: "x" });
  if (!ok) return;
  await admin.from("leads").insert({ nome: form.get("nome") });
}
FIM
python3 -I "$RN" --root "$A" > "$TMP/act2.tsv" 2>&1
echo "· server actions com limitador por RPC"
grep -q "^ACHADO.*rate_limit_action" "$TMP/act2.tsv" && falha "limitador por rpc('<x>_rate_limit') não foi reconhecido: $(grep rate_limit_action "$TMP/act2.tsv")" || ok "rpc('login_rate_limit') e rpc('site_lead_rate_limit') contam como limite"
grep -q "$(printf 'COBERTURA\t04\tserver_actions\tmedido')" "$TMP/act2.tsv" && ok "segue medido com o limitador" || falha "cobertura de server_actions sumiu"

# ───────────── app em subpasta: `app/` do monorepo não é o diretório de rotas
M="$TMP/mono"
printf '{"name":"raiz"}\n' | grava "$M/package.json"
printf '{"name":"app"}\n' | grava "$M/app/package.json"
grava "$M/app/src/app/api/x/[id]/route.ts" <<'FIM'
export async function GET() { return Response.json({}); }
FIM
python3 -I "$RN" --root "$M" > "$TMP/mono.tsv" 2>&1
echo "· app em subpasta"
grep -q "^ACHADO" "$TMP/mono.tsv" && falha "da raiz do monorepo saiu achado sem ter lido rota: $(grep '^ACHADO' "$TMP/mono.tsv" | head -2)" || ok "da raiz do monorepo não sai achado"
grep "$(printf 'COBERTURA\t04\trate_limit_rota\tnao_medido')" "$TMP/mono.tsv" | grep -q -- "--root app" && ok "nao_medido diz para rodar com --root app" || falha "não aponta a raiz do app: $(grep rate_limit_rota "$TMP/mono.tsv")"
python3 -I "$RN" --root "$M/app" > "$TMP/mono2.tsv" 2>&1
tem "$TMP/mono2.tsv" 04 MEDIUM rate_limit_rota_publica && ok "com --root app a rota é lida" || falha "com --root app a rota não foi lida"

# ───────────── collect.sh, pilar 04 e 01: ausência de pasta não é achado
if [ -f "$COLLECT" ]; then
  echo "· collect.sh: rate limit agregado e sourcemap"
  col() { # col <dir> <saida> — repo git mínimo e collect dos pilares 01, 04 e 07
    ( cd "$1" && git init -q -b main . && git config user.email t@t && git config user.name t \
        && git config commit.gpgsign false && git add -A && git commit -qm base ) >/dev/null 2>&1
    bash "$COLLECT" --root "$1" --out "$2" --pilar 01,04,07 >/dev/null 2>&1
  }
  rl() { jq -r '[.findings[] | select(.pilar=="04" and (.title|test("Nenhum rate limit")))] | length' "$1/findings.json"; }
  col "$M" "$TMP/c-mono"
  [ "$(rl "$TMP/c-mono")" = "0" ] && ok "raiz sem src/ nem supabase/functions: nenhum 'Nenhum rate limit'" || falha "achado de rate limit em raiz sem onde procurar"
  jq -e '.coverage[] | select(.pilar=="04" and .check=="rate_limit" and .status=="nao_medido" and (.reason|test("--root app")))' "$TMP/c-mono/findings.json" >/dev/null 2>&1 \
    && ok "rate_limit nao_medido aponta a subpasta do app" || falha "rate_limit não saiu nao_medido com a subpasta: $(jq -c '.coverage[] | select(.check=="rate_limit")' "$TMP/c-mono/findings.json")"
  col "$A" "$TMP/c-act"
  [ "$(rl "$TMP/c-act")" = "0" ] && ok "limitador por rpc('<x>_rate_limit') conta no agregado" || falha "agregado acusou 'Nenhum rate limit' com limitador por RPC"
  S2="$TMP/semlimite"; printf '{"name":"f"}\n' | grava "$S2/package.json"; printf 'export const x = 1\n' | grava "$S2/src/a.ts"
  mkdir -p "$S2/.next/dev/static" "$S2/.next/cache"; : > "$S2/.next/dev/static/a.js.map"; : > "$S2/.next/cache/b.map"
  col "$S2" "$TMP/c-sem"
  jq -e '.findings[] | select(.pilar=="04" and (.title|test("Nenhum rate limit")) and .confidence=="heuristic" and .file=="src")' "$TMP/c-sem/findings.json" >/dev/null 2>&1 \
    && ok "sem limite: achado heuristic apontando pasta que existe" || falha "achado de rate limit não é heuristic em src: $(jq -c '.findings[] | select(.pilar=="04") | {title,confidence,file}' "$TMP/c-sem/findings.json")"
  jq -e '[.findings[] | select(.pilar=="01" and (.title|test("Sourcemap")))] | length == 0' "$TMP/c-sem/findings.json" >/dev/null 2>&1 \
    && ok ".map de .next/dev e .next/cache não é bundle servido" || falha "sourcemap de build de desenvolvimento virou achado"
fi

# ───────────── erro de guard engolido: o 403 vira 500 (ou 200) dentro do catch
# Num pentest de 11/2026 o guard existia e lançava o erro certo; o catch da rota devolvia 500.
# Nenhum grep de "rota sem guard" pega isso, porque o guard está lá.
E="$TMP/guard"
printf '{"name":"fixture"}\n' | grava "$E/package.json"
grava "$E/src/lib/auth.ts" <<'FIM'
export class AuthError extends Error { status = 403 }
export async function requireAccess(modulo: string) { throw new AuthError("sem acesso") }
FIM
grava "$E/src/lib/api-error.ts" <<'FIM'
import { AuthError } from "./auth";
export function handleApiError(e: unknown) {
  if (e instanceof AuthError) return Response.json({ error: "forbidden" }, { status: 403 });
  return Response.json({ error: "erro" }, { status: 500 });
}
FIM
grava "$E/src/app/api/engole/route.ts" <<'FIM'
import { requireAccess } from "@/lib/auth";
export async function GET() {
  try { await requireAccess("admin"); return Response.json({ ok: true }); }
  catch (e) { return Response.json({ error: "erro interno" }, { status: 500 }); }
}
FIM
grava "$E/src/app/api/traduz/route.ts" <<'FIM'
import { requireAccess } from "@/lib/auth";
import { handleApiError } from "@/lib/api-error";
export async function GET() {
  try { await requireAccess("admin"); return Response.json({ ok: true }); }
  catch (e) { return handleApiError(e); }
}
FIM
grava "$E/src/app/api/confere/route.ts" <<'FIM'
import { requireAccess, AuthError } from "@/lib/auth";
export async function GET() {
  try { await requireAccess("admin"); return Response.json({ ok: true }); }
  catch (e) { if (e instanceof AuthError) return new Response(null, { status: 403 }); throw e; }
}
FIM
grava "$E/src/app/api/semtry/route.ts" <<'FIM'
import { requireAccess } from "@/lib/auth";
export async function GET() { await requireAccess("admin"); return Response.json({ ok: true }); }
FIM
grava "$E/src/app/pessoas/actions.ts" <<'FIM'
"use server";
import { requireAccess } from "@/lib/auth";
export async function salvar() {
  try { await requireAccess("pessoas"); } catch { return { ok: false }; }
}
FIM
python3 -I "$RN" --root "$E" > "$TMP/guard.tsv" 2>&1
echo "· erro de guard engolido"
tem "$TMP/guard.tsv" 03 MEDIUM autherror_engolido && ok "catch que engole o erro do guard é acusado" || falha "autherror_engolido não saiu: $(grep -c ACHADO "$TMP/guard.tsv") achados"
grep "autherror_engolido" "$TMP/guard.tsv" | grep -q "^ACHADO.*2 arquivos" && ok "conta os dois (rota e action)" || falha "contagem errada: $(grep '^ACHADO.*autherror' "$TMP/guard.tsv" | cut -f6)"
for bom in traduz confere semtry; do
  grep "^ACHADO.*autherror_engolido" "$TMP/guard.tsv" | grep -q "api/$bom/" && falha "$bom foi acusada" || ok "$bom não é acusada"
done
grep -q "$(printf 'COBERTURA\t03\tautherror_engolido\tmedido')" "$TMP/guard.tsv" && ok "cobertura medido" || falha "cobertura ausente: $(grep autherror "$TMP/guard.tsv" | grep COBERTURA)"
grep -q "$(printf 'COBERTURA\t03\tautherror_engolido\tnao_medido')" "$TMP/act.tsv" && ok "projeto sem erro de autorização tipado: nao_medido" || falha "sem erro tipado deveria sair nao_medido: $(grep autherror "$TMP/act.tsv")"

# ───────────── job em background sem claim atômico, e limitador que só vale por instância
J="$TMP/job"
printf '{"name":"fixture"}\n' | grava "$J/package.json"
printf '{}\n' | grava "$J/vercel.json"
grava "$J/src/app/api/sync/route.ts" <<'FIM'
import { after } from "next/server";
import { rateLimit } from "@/lib/rate-limit";
export async function POST(req: Request) {
  rateLimit("ip");
  const rodando = await db.run.findFirst({ where: { status: "RUNNING" } });
  if (rodando) return Response.json({ error: "já rodando" }, { status: 409 });
  await db.run.create({ data: { status: "RUNNING" } });
  after(() => sincronizar());
  return Response.json({ ok: true });
}
FIM
grava "$J/src/app/api/sync-ok/route.ts" <<'FIM'
import { after } from "next/server";
export async function POST() {
  const [claim] = await db.$queryRaw`insert into run (status) values ('RUNNING') on conflict do nothing returning id`;
  if (!claim) return Response.json({ error: "já rodando" }, { status: 409 });
  after(() => sincronizar());
  return Response.json({ ok: true });
}
FIM
grava "$J/src/lib/rate-limit.ts" <<'FIM'
const hits = new Map<string, number>();
export function rateLimit(chave: string) { hits.set(chave, (hits.get(chave) ?? 0) + 1); return hits.get(chave)! < 10; }
FIM
python3 -I "$RN" --root "$J" > "$TMP/job.tsv" 2>&1
echo "· job sem claim e limite em memória"
tem "$TMP/job.tsv" 04 MEDIUM job_sem_claim && ok "after() sem claim atômico é acusado" || falha "job_sem_claim não saiu"
grep "^ACHADO.*job_sem_claim" "$TMP/job.tsv" | grep -q "sync-ok" && falha "rota com insert on conflict foi acusada" || ok "insert ... on conflict conta como claim"
grep "^ACHADO.*job_sem_claim" "$TMP/job.tsv" | grep -q "api/sync/route.ts" && ok "aponta a rota que lê e depois cria" || falha "não aponta api/sync/route.ts"
tem "$TMP/job.tsv" 04 LOW rate_limit_em_memoria && ok "limitador em Map de instância é acusado" || falha "rate_limit_em_memoria não saiu"
grava "$J/src/lib/rate-limit.ts" <<'FIM'
import { Ratelimit } from "@upstash/ratelimit";
const cache = new Map();
export const limiter = new Ratelimit({ ephemeralCache: cache });
export function rateLimit(chave: string) { return limiter.limit(chave); }
FIM
python3 -I "$RN" --root "$J" > "$TMP/job2.tsv" 2>&1
grep -q "^ACHADO.*rate_limit_em_memoria" "$TMP/job2.tsv" && falha "limitador com contador compartilhado foi acusado" || ok "contador compartilhado (upstash) não é acusado"

# ───────────── collect.sh, pilar 01: os outros headers e a CSP que só reporta
if [ -f "$COLLECT" ]; then
  echo "· collect.sh: headers e CSP Report-Only"
  H="$TMP/headers"; printf '{"name":"f"}\n' | grava "$H/package.json"; printf 'export const x = 1\n' | grava "$H/src/a.ts"
  grava "$H/next.config.ts" <<'FIM'
const csp = "default-src 'self'; script-src 'self' 'unsafe-inline'";
const headers = [
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Content-Security-Policy-Report-Only", value: csp },
];
export default { async headers() { return [{ source: "/(.*)", headers }]; } };
FIM
  col "$H" "$TMP/c-h"
  t1() { jq -r '.findings[] | select(.pilar=="01") | .title' "$TMP/$1/findings.json"; }
  t1 c-h | grep -q "Report-Only" && ok "CSP só em Report-Only é achado próprio" || falha "sem achado de Report-Only: $(t1 c-h | tr '\n' '|')"
  t1 c-h | grep -q "Nenhuma CSP declarada" && falha "Report-Only saiu como 'Nenhuma CSP'" || ok "não diz 'Nenhuma CSP' quando há Report-Only"
  t1 c-h | grep -q "unsafe-inline" && falha "'unsafe-inline' da Report-Only saiu como política aplicada" || ok "'unsafe-inline' só na Report-Only não é achado de política aplicada"
  hd="$(t1 c-h | grep "Headers de segurança não declarados")"
  for h in x-content-type-options referrer-policy permissions-policy; do
    printf '%s' "$hd" | grep -q "$h" && ok "acusa a falta de $h" || falha "não acusa $h: $hd"
  done
  printf '%s' "$hd" | grep -q "x-frame-options" && falha "acusou x-frame-options, que está declarado" || ok "não acusa o header declarado"
  grava "$H/next.config.ts" <<'FIM'
const headers = [
  { key: "X-Frame-Options", value: "DENY" }, { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=()" },
  { key: "Content-Security-Policy", value: "default-src 'self'; frame-ancestors 'none'" },
];
export default { async headers() { return [{ source: "/(.*)", headers }]; } };
FIM
  ( cd "$H" && git add -A && git commit -qm headers ) >/dev/null 2>&1
  bash "$COLLECT" --root "$H" --out "$TMP/c-h2" --pilar 01,04,07 >/dev/null 2>&1
  t1 c-h2 | grep -qE "Headers de segurança|Report-Only|Nenhuma CSP" && falha "com tudo declarado ainda acusa: $(t1 c-h2 | tr '\n' '|')" || ok "com os headers e a CSP aplicada, nada disso é acusado"
fi

echo
if [ $falhas -eq 0 ]; then echo "tudo verde"; exit 0; fi
echo "$falhas falha(s)"; exit 1
