#!/usr/bin/env bash
# baseline · collect — mede. Não julga.
#
# Emite findings.json com dois arrays: findings (fatos observados) e coverage
# (o que foi medido, o que não foi e por quê). O julgamento — severidade final,
# exceção aceita, falso-positivo — é da fase 2, com o contrato do projeto na mão.
#
# INVARIANTE: se nenhum check rodou, sai com exit 3. Relatório vazio parece
# aprovação, e é o pior resultado possível.
#
#   collect.sh [--out DIR] [--root DIR] [--diff BASE] [--pilar 01,07]
#
#   --diff BASE   só o que o diff contra BASE toca (gate do /ship; rápido, sem rede)

set -uo pipefail

OUT="" ; ROOT="$PWD" ; DIFF_BASE="" ; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out)   OUT="${2:-}"; shift 2 ;;
    --root)  ROOT="${2:-}"; shift 2 ;;
    --diff)  DIFF_BASE="${2:-}"; shift 2 ;;
    --pilar) ONLY="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done
cd "$ROOT" 2>/dev/null || { echo "root inválido: $ROOT" >&2; exit 2; }
ROOT="$PWD"
[ -n "$OUT" ] || OUT="/tmp/baseline-$(basename "$ROOT")"
mkdir -p "$OUT"

# Pré-condição: isto é um projeto? "Não achei CSP" num diretório sem projeto não
# é medição, é ausência de alvo — e sairia como relatório limpo. Invariante 2.
is_project=0
for m in package.json .git supabase src pyproject.toml go.mod Cargo.toml; do
  [ -e "$m" ] && is_project=1 && break
done
if [ $is_project -eq 0 ]; then
  echo "ERRO: $ROOT não parece um projeto (sem package.json, .git, src/, supabase/...)." >&2
  echo "Medir aqui produziria um relatório limpo por ausência de alvo, não por conformidade." >&2
  exit 3
fi

F="$OUT/.findings.ndjson" ; C="$OUT/.coverage.ndjson"
: > "$F" ; : > "$C"
CHECKS_RUN=0     # todos os checks registrados
MEASURED=0       # só os que efetivamente mediram alguma coisa

want() { [ -z "$ONLY" ] || case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
jstr() { printf '%s' "${1-}" | tr -d '\000' | jq -Rs .; }

# add_finding pilar sev conf titulo arquivo detalhe recheck ref
add_finding() {
  jq -nc --argjson p "$(jstr "$1")" --argjson s "$(jstr "$2")" --argjson c "$(jstr "$3")" \
        --argjson t "$(jstr "$4")" --argjson f "$(jstr "$5")" --argjson d "$(jstr "$6")" \
        --argjson r "$(jstr "$7")" --argjson e "$(jstr "$8")" \
    '{pilar:$p,severity:$s,confidence:$c,title:$t,file:$f,detail:$d,recheck:$r,ref:$e}' >> "$F"
}
# add_coverage pilar check status tool motivo
add_coverage() {
  CHECKS_RUN=$((CHECKS_RUN+1))
  [ "$3" = "medido" ] && MEASURED=$((MEASURED+1))
  jq -nc --argjson p "$(jstr "$1")" --argjson k "$(jstr "$2")" --argjson s "$(jstr "$3")" \
        --argjson t "$(jstr "$4")" --argjson r "$(jstr "$5")" \
    '{pilar:$p,check:$k,status:$s,tool:$t,reason:$r}' >> "$C"
}

# Escopo de arquivos. Em --diff, só o que mudou; senão, tudo que o git rastreia.
if [ -n "$DIFF_BASE" ]; then
  SCOPE="$(git diff --name-only --diff-filter=ACMR "$DIFF_BASE"...HEAD 2>/dev/null)"
  [ -n "$SCOPE" ] || SCOPE="$(git diff --name-only --diff-filter=ACMR "$DIFF_BASE" 2>/dev/null)"
else
  SCOPE="$(git ls-files 2>/dev/null)"
fi
SCOPE_FILE="$OUT/.scope"; printf '%s\n' "$SCOPE" | grep -v '^$' > "$SCOPE_FILE"
DIFF_MODE=0; [ -n "$DIFF_BASE" ] && DIFF_MODE=1

# No modo --diff o gate é incremental: só interessa o que ESTE diff introduziu.
# Check agregado sobre o repo inteiro (histórico do gitleaks, contagem global de
# ErrorBoundary, CSP do projeto) não pertence a um gate de commit — é lento e
# reprova por dívida que o autor do PR não criou.
global_check() { [ $DIFF_MODE -eq 0 ]; }

# Filtra saída "arquivo:linha:..." mantendo só arquivos do diff.
only_scope() {
  if [ $DIFF_MODE -eq 0 ]; then cat; else
    awk -F: 'NR==FNR{s[$0];next} {p=$1; sub(/^\.\//,"",p); if (p in s) print}' \
      "$SCOPE_FILE" - 2>/dev/null
  fi
}
# Idem para saída que é só o caminho (grep -l, git grep -l, find).
only_scope_paths() {
  if [ $DIFF_MODE -eq 0 ]; then cat; else
    awk 'NR==FNR{s[$0];next} {p=$0; sub(/^\.\//,"",p); if (p in s) print}' \
      "$SCOPE_FILE" - 2>/dev/null
  fi
}

hits() { # conta linhas não vazias (grep -c sai 1 quando conta 0; o ; true evita "0\n0")
  printf '%s' "${1-}" | grep -c . 2>/dev/null; true
}

# ─────────────────────────────────────────── 01 · frontend
if want 01; then
  # sourcemap presente em build já feito (agregado: não pertence a gate de diff)
  if global_check; then
  maps="$(find dist .next build -name '*.map' -not -path '*/node_modules/*' 2>/dev/null | head -5)"
  if [ -n "$maps" ]; then
    add_finding 01 HIGH CONFIRMED "Sourcemap presente no diretório de build" \
      "$(printf '%s' "$maps" | head -1)" \
      "Sourcemap servido junto com o bundle publica o código-fonte original. Se for para o error tracker, gere com hidden e apague do diretório publicado." \
      "find dist .next build -name '*.map' 2>/dev/null | head" \
      "pilar 01"
    add_coverage 01 sourcemap medido find ""
  elif [ -d dist ] || [ -d .next ] || [ -d build ]; then
    add_coverage 01 sourcemap medido find ""
  else
    add_coverage 01 sourcemap nao_medido find "sem diretório de build; rode o build antes"
  fi
  fi

  # variável de prefixo público com cara de segredo
  pub="$(grep -nEr '(VITE|NEXT_PUBLIC|PUBLIC|REACT_APP)_[A-Z0-9_]*(KEY|SECRET|TOKEN|PASSWORD)' \
        --include='*.ts' --include='*.tsx' --include='*.js' --include='*.env*' . 2>/dev/null \
        | grep -v node_modules | grep -viE '_ANON_KEY|_PUBLISHABLE|_PUBLIC_KEY|test|spec|__tests__' | only_scope | head -20)"
  # Agrupado por VARIÁVEL, não por ocorrência: a mesma var citada em 13 arquivos
  # é um problema, não treze. Repetir vira ruído e enterra os outros pilares.
  if [ -n "$pub" ]; then
    vars="$(printf '%s' "$pub" | grep -oE '(VITE|NEXT_PUBLIC|PUBLIC|REACT_APP)_[A-Z0-9_]*(KEY|SECRET|TOKEN|PASSWORD)' | sort -u)"
    nv="$(hits "$vars")" ; nocc="$(hits "$pub")"
    add_finding 01 HIGH CONFIRMED "Variável de prefixo público com nome de segredo (${nv:-0})" \
      "$(printf '%s' "$pub" | head -1 | cut -d: -f1,2 | sed 's|^\./||')" \
      "Prefixo público vai para o bundle servido ao browser: se este valor autentica alguma coisa, ele não autentica mais. Variáveis: $(printf '%s' "$vars" | tr '\n' ' '). Ocorrências: ${nocc:-0} — primeira acima." \
      "grep -rnE '(VITE|NEXT_PUBLIC)_[A-Z0-9_]*(KEY|SECRET|TOKEN)' --include='*.ts' src/" \
      "pilar 01"
  fi
  add_coverage 01 prefixo_publico medido grep ""

  # CSP e headers (agregado do projeto)
  if global_check; then
  csp_src=""
  for f in vercel.json next.config.js next.config.mjs next.config.ts public/_headers netlify.toml index.html; do
    [ -f "$f" ] && grep -qi 'content-security-policy' "$f" 2>/dev/null && csp_src="$csp_src $f"
  done
  if [ -n "$csp_src" ]; then
    add_coverage 01 csp medido grep "declarada em:$csp_src"
    if grep -hoi "script-src[^;\"]*" $csp_src 2>/dev/null | grep -qi "unsafe-inline"; then
      add_finding 01 MEDIUM CONFIRMED "CSP com 'unsafe-inline' em script-src" \
        "$(printf '%s' "$csp_src" | awk '{print $1}')" \
        "script-src com unsafe-inline anula a proteção principal da CSP contra XSS refletido." \
        "grep -o \"script-src[^;]*\" vercel.json" "pilar 01"
    fi
    n_csp="$(printf '%s' "$csp_src" | wc -w | tr -d ' ')"
    if [ "${n_csp:-0}" -gt 1 ]; then
      add_finding 01 MEDIUM heuristic "CSP declarada em mais de um lugar" \
        "$(printf '%s' "$csp_src" | sed 's/^ //')" \
        "A política efetiva é a interseção das cópias. Sem teste que trave a divergência, uma delas envelhece e a feature quebra só em produção." \
        "diff <(grep -o \"Content-Security-Policy.*\" vercel.json) <(grep -o 'content-equiv.*' index.html)" \
        "pilar 01"
    fi
  else
    add_finding 01 MEDIUM CONFIRMED "Nenhuma CSP declarada" "vercel.json" \
      "Sem CSP, qualquer injeção de script executa e pode exfiltrar para qualquer host." \
      "curl -sSI https://<dominio> | grep -i content-security-policy" "pilar 01"
    add_coverage 01 csp medido grep "nenhuma encontrada"
  fi
  fi
fi

# ─────────────────────────────────────────── 02 · banco
if want 02; then
  if [ -d supabase/migrations ] || [ -d migrations ]; then
    MIG="$(ls -d supabase/migrations migrations 2>/dev/null | head -1)"
    # No modo --diff, só as migrations que ESTE diff adicionou.
    if [ $DIFF_MODE -eq 1 ]; then
      MIG_FILES="$(grep -E '(supabase/)?migrations/.*\.sql$' "$SCOPE_FILE" 2>/dev/null | tr '\n' ' ')"
      [ -n "$MIG_FILES" ] || MIG_FILES=""
    else MIG_FILES="$MIG"; fi
    if [ -z "$MIG_FILES" ]; then
      add_coverage 02 rls_migrations nao_medido grep "nenhuma migration neste diff"
    else
    # [[:space:]]+ e não espaço literal: as migrations alinham as colunas
    # ("ALTER TABLE public.deal_tags     ENABLE ROW LEVEL SECURITY") e um regex
    # com espaço único reporta como desprotegida uma tabela que tem RLS.
    created="$(grep -rhoiE 'create[[:space:]]+table[[:space:]]+(if[[:space:]]+not[[:space:]]+exists[[:space:]]+)?(public\.)?"?[a-z0-9_]+' $MIG_FILES 2>/dev/null \
      | grep -oiE '[a-z0-9_]+$' | sort -u)"
    rls="$(grep -rhoiE 'alter[[:space:]]+table[[:space:]]+(only[[:space:]]+)?(public\.)?"?[a-z0-9_]+"?[[:space:]]+enable[[:space:]]+row[[:space:]]+level[[:space:]]+security' $MIG_FILES 2>/dev/null \
      | sed -E 's/.*table[[:space:]]+(only[[:space:]]+)?(public\.)?"?([a-z0-9_]+)"?[[:space:]]+enable.*/\3/I' | sort -u)"
    semrls="$(comm -23 <(printf '%s\n' "$created") <(printf '%s\n' "$rls") 2>/dev/null | grep -v '^$')"
    n="$(hits "$semrls")"
    if [ "${n:-0}" -gt 0 ]; then
      add_finding 02 HIGH heuristic "Tabela criada sem ENABLE ROW LEVEL SECURITY nas migrations ($n)" \
        "$MIG" \
        "Tabela em schema exposto sem RLS é legível por qualquer um com a anon key. Migrations podem não refletir o banco: confirme com o lint 0013. Tabelas: $(printf '%s' "$semrls" | tr '\n' ' ' | cut -c1-300)" \
        "bash ~/.claude/skills/baseline/scripts/splinter.sh 0013" "lint 0013_rls_disabled_in_public"
    fi
    add_coverage 02 rls_migrations medido grep "estático: policy aplicada pelo dashboard não aparece aqui"

    # SECURITY DEFINER sem search_path (bloco de função)
    sd_total="$(grep -rioE 'security definer' $MIG_FILES 2>/dev/null | grep -c . 2>/dev/null; true)"
    sd_sp="$(grep -rioE 'set search_path' $MIG_FILES 2>/dev/null | grep -c . 2>/dev/null; true)"
    if [ "${sd_total:-0}" -gt "${sd_sp:-0}" ]; then
      add_finding 02 MEDIUM heuristic "SECURITY DEFINER sem SET search_path (aprox. $((sd_total - sd_sp)) de $sd_total)" \
        "$MIG" \
        "Função SECURITY DEFINER sem search_path fixo é vetor de escalonamento de privilégio — pior ainda quando é chamada de dentro de uma policy. Contagem aproximada; confirme com o lint 0011." \
        "bash ~/.claude/skills/baseline/scripts/splinter.sh 0011" "lint 0011_function_search_path_mutable"
    fi
    add_coverage 02 security_definer medido grep "contagem agregada, não por função"

    ut="$(grep -rn 'using (true)' $MIG_FILES 2>/dev/null | grep -c . 2>/dev/null; true)"
    if [ "${ut:-0}" -gt 0 ]; then
      add_finding 02 MEDIUM CONFIRMED "Policies com USING (true) ($ut ocorrências)" "$MIG" \
        "USING (true) libera todas as linhas para o papel da policy. Pode ser intencional — se for, precisa estar nas exceções aceitas do contrato." \
        "grep -rn 'using (true)' $MIG" "lint 0024_rls_policy_always_true"
    fi
    si="$(grep -rn 'security_invoker *= *false' $MIG_FILES 2>/dev/null | grep -c . 2>/dev/null; true)"
    if [ "${si:-0}" -gt 0 ]; then
      add_finding 02 MEDIUM heuristic "Views com security_invoker = false ($si)" "$MIG" \
        "View com security_invoker=false roda com o privilégio do dono e fura a RLS de quem consulta. Legítimo para agregação de BI; exige justificativa versionada." \
        "bash ~/.claude/skills/baseline/scripts/splinter.sh 0010" "lint 0010_security_definer_view"
    fi
    add_coverage 02 policies_permissivas medido grep ""
    fi
  else
    add_coverage 02 rls_migrations nao_medido - "sem diretório de migrations"
  fi

  if [ -x scripts/db-query.sh ] || [ -n "${SUPABASE_DB_URL:-}" ]; then
    add_coverage 02 lints_banco nao_medido splinter "acesso disponível — rode splinter.sh para medir no banco real"
  else
    add_coverage 02 lints_banco nao_medido splinter "sem acesso ao banco (scripts/db-query.sh ou SUPABASE_DB_URL)"
  fi
fi

# ─────────────────────────────────────────── 03 · auth
if want 03; then
  # Descarta linha de comentário: um comentário que EXPLICA o antipadrão
  # ("o fail-open anterior era `?? ALL_MODULES`") reabria o achado depois de
  # corrigido — e finding que não fecha quando o bug fecha treina a ignorar o gate.
  fo="$(grep -rnE '\?\?\s*(ALL_|Object\.values)' src/ 2>/dev/null \
      | grep -iE 'role|module|permission|access' \
      | grep -vE ':[[:space:]]*(//|\*|/\*)' \
      | only_scope | head -10)"
  if [ -n "$fo" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      add_finding 03 HIGH CONFIRMED "Fail-open em mapa de permissão" \
        "$(printf '%s' "$line" | cut -d: -f1,2)" \
        "Papel desconhecido cai no conjunto máximo. Um papel novo cadastrado no banco nasce vendo tudo, sem erro nenhum." \
        "grep -rn '?? ALL_' src/ | grep -i role" "pilar 03"
    done <<< "$fo"
  fi
  add_coverage 03 fail_open medido grep ""
  add_coverage 03 gate_vs_rls nao_medido curl "exige token de papel restrito — teste manual, ver pilar 03"
fi

# ─────────────────────────────────────────── 04 · limites
if want 04; then
  if [ -d supabase/functions ]; then
    sem_auth="" ; total_fn=0
    for d in supabase/functions/*/; do
      n="$(basename "$d")"; [ "$n" = "_shared" ] && continue
      [ -f "$d/index.ts" ] || continue
      if [ $DIFF_MODE -eq 1 ]; then grep -q "^$d" "$SCOPE_FILE" 2>/dev/null || continue; fi
      total_fn=$((total_fn+1))
      # requireAuth/assertAuth vêm de _shared e são o padrão mais comum de guard —
      # sem eles na lista, função corretamente protegida vira finding HIGH.
      grep -qE 'headers\.get\(|verifySecret|secretMatches|timingSafeEqual|auth\.getUser|verifyCronSecret|requireAuth|assertAuth|requireUser' "$d/index.ts" 2>/dev/null \
        || sem_auth="$sem_auth $n"
    done
    if [ -n "$sem_auth" ]; then
      add_finding 04 HIGH heuristic "Edge function sem verificação de identidade aparente" \
        "supabase/functions" \
        "Nenhuma checagem de header, segredo ou getUser encontrada em:$sem_auth. Se verify_jwt estiver ativo a plataforma cobre; se estiver na allowlist de públicas, é porta aberta." \
        "grep -L 'headers.get\\|auth.getUser' supabase/functions/*/index.ts" "pilar 04"
    fi
    add_coverage 04 edge_auth medido grep "$total_fn funções inspecionadas"

    llm_sem=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      grep -qE 'max_tokens|maxOutputTokens|max_output_tokens|max_completion_tokens' "$f" 2>/dev/null || llm_sem="$llm_sem $f"
    done <<< "$(grep -rlE 'chat\.completions\.create|generateContent|messages\.create|/v1/chat/completions' supabase/functions src 2>/dev/null | only_scope_paths | sort -u)"
    if [ -n "$llm_sem" ]; then
      add_finding 04 HIGH CONFIRMED "Chamada de LLM sem teto de tokens" \
        "$(printf '%s' "$llm_sem" | awk '{print $1}')" \
        "Sem max_tokens a resposta pode crescer sem limite. Combinado com ausência de quota por usuário, uma conta comprometida gera custo ilimitado. Arquivos:$llm_sem" \
        "grep -L max_tokens \$(grep -rl 'chat.completions.create' supabase/functions)" "pilar 04"
    fi
    add_coverage 04 llm_max_tokens medido grep ""
  else
    add_coverage 04 edge_auth nao_medido - "sem supabase/functions"
  fi

  # Rate limit IMPOSTO, não SOFRIDO. Tratar o 429 de um fornecedor
  # (TemplatesRateLimitError, RateLimitError) não é impor limite ao próprio
  # endpoint — e casar com isso produz um falso negativo tranquilizador.
  # Só padrões de IMPOSIÇÃO. '429,' solto casa com coordenada geográfica
  # (-49.6210429,) e 'Retry-After' sem aspas casa com o header sendo LIDO de um
  # fornecedor. Ambos produziriam um "tem rate limit" falso.
  if global_check; then
  rl="$(grep -rnE 'rate_limit_take|rateLimitTake|checkRateLimit|new Ratelimit|status: *429|status=429|["'"'"']Retry-After["'"'"'] *:' \
        supabase/functions src 2>/dev/null | grep -v node_modules \
        | grep -viE 'RateLimitError|rateLimited|instanceof|=== *429|== *429|headers\.get' \
        | grep -c . 2>/dev/null; true)"
  if [ "${rl:-0}" -eq 0 ]; then
    add_finding 04 HIGH CONFIRMED "Nenhum rate limit próprio encontrado" "supabase/functions" \
      "Sem limite por identidade, uma conta legítima comprometida vale tanto quanto uma brecha — e sai mais caro, porque tráfego autenticado não levanta suspeita. Tratamento do 429 de fornecedor foi descartado da contagem: isso é sofrer limite, não impor." \
      "grep -rnE 'rate_limit_take|status: *429' supabase/functions src" "pilar 04"
  fi
  add_coverage 04 rate_limit medido grep "conta só limite imposto; 429 de terceiro descartado"
  fi
fi

# ─────────────────────────────────────────── 05 · carga
if want 05; then
  sel="$(grep -rnE "\.from\('[^']+'\)" src/ 2>/dev/null | grep '\.select(' \
        | grep -vE '\.range\(|\.limit\(|\.single\(|\.maybeSingle\(|count:' | only_scope | head -40)"
  n="$(hits "$sel")"
  if [ "${n:-0}" -gt 0 ]; then
    add_finding 05 MEDIUM heuristic "Consultas de lista sem teto explícito ($n)" \
      "$(printf '%s' "$sel" | head -1 | cut -d: -f1,2)" \
      "PostgREST corta em 1000 linhas e devolve 200 — a lista fica truncada sem erro. Encadeamento em várias linhas gera falso-positivo aqui; confirme os casos." \
      "grep -rn \".from('\" src/ | grep '.select(' | grep -v '.range(\\|.limit('" "pilar 05"
  fi
  add_coverage 05 query_sem_teto medido grep "heurística de uma linha; encadeamento multilinha escapa"

  if global_check; then
  idx="$(grep -rhoi 'create index' supabase/migrations 2>/dev/null | grep -c . 2>/dev/null; true)"
  add_coverage 05 indices medido grep "$idx CREATE INDEX nas migrations"
  fi
fi

# ─────────────────────────────────────────── 06 · observabilidade
# Agregado por natureza: 'o projeto tem error tracking' não é pergunta de diff.
if want 06 && global_check; then
  # Padrões ancorados: 'rollbar' solto casa com a classe CSS 'scrollbar' e
  # produz falso negativo de error tracking — o pior tipo de erro aqui.
  tracker="$(grep -rlE '@sentry/|Sentry\.init|captureException|captureMessage|@datadog/|posthog-js|@bugsnag/|rollbar\.init|newrelic' \
            src package.json 2>/dev/null | head -3)"
  dropc="$(grep -rlniE "drop:\s*\[?['\"]console|dropConsole|removeConsole" \
          vite.config.ts vite.config.js next.config.js next.config.mjs next.config.ts 2>/dev/null | head -2)"
  if [ -z "$tracker" ]; then
    if [ -n "$dropc" ]; then
      add_finding 06 CRITICAL CONFIRMED "console removido no build e nenhum error tracking" \
        "$(printf '%s' "$dropc" | head -1)" \
        "Erro em produção não deixa rastro em lugar nenhum: o console era o único registro e o build o apaga. Instale o tracker antes de ligar o drop — a ordem não é negociável." \
        "grep -rn 'captureException\\|Sentry.init' src/ package.json" "pilar 06"
    else
      add_finding 06 HIGH CONFIRMED "Nenhum error tracking instalado" "package.json" \
        "Erro de produção só é descoberto quando um usuário reclama, e sem stack trace não dá para chegar na linha." \
        "grep -rn '@sentry\\|captureException' package.json src/" "pilar 06"
    fi
  fi
  add_coverage 06 error_tracking medido grep ""

  eb="$(grep -rn '<ErrorBoundary' src/ 2>/dev/null | grep -c . 2>/dev/null; true)"
  if [ "${eb:-0}" -le 1 ]; then
    add_finding 06 MEDIUM CONFIRMED "ErrorBoundary montado em $eb lugar(es)" "src/" \
      "Um único boundary no topo transforma erro de qualquer componente em tela branca do app inteiro. Um por área isola o estrago." \
      "grep -rn '<ErrorBoundary' src/ | wc -l" "pilar 06"
  fi
  add_coverage 06 error_boundary medido grep "$eb montados"
fi

# ─────────────────────────────────────────── 07 · segredos
if want 07; then
  envs="$(git ls-files 2>/dev/null | grep -E '(^|/)\.env' | grep -vE '\.env\.example$|\.env\.1password$|\.env\.template$' | only_scope_paths)"
  if [ -n "$envs" ]; then
    add_finding 07 CRITICAL CONFIRMED "Arquivo .env versionado" "$(printf '%s' "$envs" | head -1)" \
      "Arquivo de ambiente no git expõe todo segredo do projeto para quem tiver leitura do repositório, e o histórico guarda mesmo depois de removido. Arquivos:$(printf '%s' "$envs" | tr '\n' ' ')" \
      "git ls-files | grep -E '(^|/)\\.env'" "pilar 07"
  fi
  add_coverage 07 env_versionado medido git ""

  jwt="$(git grep -lE 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}' -- . ':!*.lock' ':!*.snap' ':!node_modules' 2>/dev/null | only_scope_paths)"
  nj="$(hits "$jwt")"
  if [ "${nj:-0}" -gt 0 ]; then
    add_finding 07 CRITICAL CONFIRMED "JWT versionado no HEAD ($nj arquivos)" \
      "$(printf '%s' "$jwt" | head -1)" \
      "Token JWT em arquivo rastreado. Se for service_role, é acesso total ao banco ignorando RLS. Gate de secret scan que só varre o diff nunca encontra isto. Arquivos: $(printf '%s' "$jwt" | tr '\n' ' ' | cut -c1-400)" \
      "git grep -lE 'eyJ[A-Za-z0-9_-]+\\.eyJ' -- . ':!*.lock'" "pilar 07"
  fi
  add_coverage 07 jwt_no_head medido git ""

  if command -v gitleaks >/dev/null 2>&1 && global_check; then
    gitleaks detect --no-banner --redact --report-format json \
      --report-path "$OUT/gitleaks.json" >/dev/null 2>&1
    gl="$(jq 'length' "$OUT/gitleaks.json" 2>/dev/null || echo 0)"
    if [ "${gl:-0}" -gt 0 ]; then
      add_finding 07 HIGH CONFIRMED "gitleaks: $gl achados no histórico" "$OUT/gitleaks.json" \
        "Varredura do histórico completo, não só do diff. Confirme quais credenciais ainda estão vivas antes de priorizar — achado antigo já rotacionado não é incidente." \
        "gitleaks detect --no-banner --redact" "pilar 07"
    fi
    add_coverage 07 gitleaks medido gitleaks "histórico completo"
  else
    add_coverage 07 gitleaks nao_medido gitleaks "gitleaks ausente ou modo diff (histórico é check agregado)"
  fi

  if [ -f .env.example ] && global_check; then
    vals="$(grep -nE '=.+' .env.example 2>/dev/null | grep -vE '=\s*(your|<|xxx|CHANGE|\.\.\.|""|$)' | head -5)"
    [ -n "$vals" ] && add_finding 07 MEDIUM heuristic ".env.example com valores preenchidos" ".env.example" \
      "O exemplo deve trazer só nomes de chave. Valor real ali vaza como qualquer outro arquivo versionado." \
      "grep -nE '=.+' .env.example" "pilar 07"
    add_coverage 07 env_example medido grep ""
  else
    add_coverage 07 env_example nao_medido - ".env.example ausente ou modo diff"
  fi
fi

# ─────────────────────────────────────────── montar findings.json
# INVARIANTE 2 — medição ausente nunca é veredito limpo.
# Não basta ter rodado: é preciso ter MEDIDO. Um alvo onde todo check saiu
# 'nao_medido' produziria um relatório limpo que parece aprovação. Sai 3.
if [ "$CHECKS_RUN" -eq 0 ] || [ "$MEASURED" -eq 0 ]; then
  echo "ERRO: nada foi medido ($MEASURED medições em $CHECKS_RUN checks)." >&2
  echo "Relatório vazio parece aprovação — por isso este script falha em vez de emitir um." >&2
  echo "Verifique --root ($ROOT) e --pilar ($ONLY); rode doctor.sh para ver o que falta." >&2
  exit 3
fi

SHA="$(git rev-parse --short HEAD 2>/dev/null || echo desconhecido)"
BR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo desconhecido)"
jq -n \
  --arg project "$(basename "$ROOT")" --arg root "$ROOT" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sha "$SHA" --arg br "$BR" \
  --arg mode "$([ -n "$DIFF_BASE" ] && echo "diff:$DIFF_BASE" || echo completo)" \
  --argjson checks "$CHECKS_RUN" --argjson measured "$MEASURED" \
  --slurpfile f "$F" --slurpfile c "$C" \
  '{meta:{project:$project,root:$root,generated_at:$at,git_sha:$sha,branch:$br,mode:$mode,
          checks_run:$checks,checks_measured:$measured},
    coverage:$c, findings:$f}' > "$OUT/findings.json" || { echo "falha ao montar findings.json" >&2; exit 4; }
rm -f "$F" "$C" "$SCOPE_FILE"

nf="$(jq '.findings | length' "$OUT/findings.json")"
echo "checks: $CHECKS_RUN (medidos: $MEASURED) · findings: $nf · $OUT/findings.json"

# exit 1 quando há CRITICAL/HIGH — é o que o gate do /ship consome
jq -e '[.findings[] | select(.severity=="CRITICAL" or .severity=="HIGH")] | length == 0' \
  "$OUT/findings.json" >/dev/null 2>&1 || exit 1
exit 0
