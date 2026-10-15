#!/usr/bin/env bash
# Pilar 04 do collect.sh (edge_auth): guard de cron-secret reconhecido, função aberta acusada.
#
# A heurística procura um guard conhecido no index.ts de cada edge function. Até 15/10/2026 a
# lista não tinha `isCronAuthorized` (guard de cron-secret em _shared, fail-closed e com
# comparação em tempo constante): função protegida virava HIGH "Edge function sem verificação
# de identidade aparente" e travava o /ship. Portado de VAMOO-AI/claude-config-team#337.
#
# Uso: bash tests/test-baseline-edge-auth.sh [caminho-do-collect.sh]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/baseline/scripts/collect.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq ausente — o collect.sh depende dele"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/baseline-edge.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

R="$TMP/repo"
git init -q -b main "$R"
git -C "$R" config user.email t@t; git -C "$R" config user.name t
git -C "$R" config commit.gpgsign false
printf '{"name":"fixture"}\n' > "$R/package.json"
F="$R/supabase/functions"
mkdir -p "$F/_shared" "$F/cron-resumo" "$F/cron-antigo" "$F/aberta"
printf 'export function isCronAuthorized(req: Request): boolean { return false; }\n' > "$F/_shared/cronAuth.ts"
cat > "$F/cron-resumo/index.ts" <<'TS'
import { isCronAuthorized } from "../_shared/cronAuth.ts";
Deno.serve((req) => isCronAuthorized(req) ? new Response("ok") : new Response("no", { status: 401 }));
TS
cat > "$F/cron-antigo/index.ts" <<'TS'
import { verifyCronSecret } from "../_shared/cron.ts";
Deno.serve((req) => verifyCronSecret(req) ? new Response("ok") : new Response("no", { status: 401 }));
TS
cat > "$F/aberta/index.ts" <<'TS'
Deno.serve(() => new Response("qualquer um entra"));
TS
git -C "$R" add -A; git -C "$R" commit -qm base

bash "$SCRIPT" --root "$R" --out "$TMP/out" --pilar 04 >/dev/null 2>"$TMP/err"
J="$TMP/out/findings.json"
[ -f "$J" ] || { echo "findings.json não saiu; stderr: $(head -c 300 "$TMP/err")"; exit 2; }
det="$(jq -r '.findings[] | select(.pilar=="04" and (.title | test("sem verificação de identidade"))) | .detail' "$J")"

echo "== pilar 04: edge_auth =="
case "$det" in *" aberta"*) ok "função sem guard é acusada" ;; *) falha "função aberta não apareceu: ${det:-<sem finding>}" ;; esac
case "$det" in *cron-resumo*) falha "isCronAuthorized não foi reconhecido como guard: $det" ;; *) ok "isCronAuthorized conta como guard" ;; esac
case "$det" in *cron-antigo*) falha "verifyCronSecret deixou de contar como guard: $det" ;; *) ok "verifyCronSecret continua contando" ;; esac
cob="$(jq -r '.coverage[]? | select(.pilar=="04" and .check=="edge_auth") | .reason' "$J" 2>/dev/null)"
case "$cob" in "3 funções"*) ok "_shared fica fora da contagem (3 funções)" ;; *) falha "cobertura inesperada: ${cob:-<vazia>}" ;; esac

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
