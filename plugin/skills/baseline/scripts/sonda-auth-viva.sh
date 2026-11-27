#!/usr/bin/env bash
# baseline · sonda-auth-viva — o que o painel do Auth diz HOJE, e o status real das rotas.
#
# Só GET e HEAD, sem sessão, sem corpo: nada cria conta, nada escreve. Vale para produção
# do próprio projeto (mesma classe do `curl -sSI` passivo do pilar 08). Não substitui a fase
# dinâmica, e não testa signup de verdade: senha mínima só sai pela Management API.
#
# Com APP_URL, também lê na borda CSP, COOP, CORP e HSTS (preload), e se robots.txt e
# /.well-known/security.txt são servidos ou caem no redirect do login.
#
# Por que existe: o config.toml é do ambiente local. Em dois pentests de 11/2026 o cadastro
# estava aberto no PAINEL, um projeto nem tinha config.toml, e nenhuma skill olhava o painel.
# E um guard de rota que "redireciona" respondia 200 com meta-refresh: a leitura do código
# dizia redirect, o status real dizia outra coisa.
#
# Entradas por ambiente (nada de token na linha de comando, que vai para o histórico):
#   SUPABASE_URL           https://<ref>.supabase.co                        (obrigatório)
#   SUPABASE_ANON_KEY      chave anon/publishable (pública por contrato)    (obrigatório)
#   SUPABASE_ACCESS_TOKEN  PAT do dono, só para GET /v1/projects/<ref>/config/auth (opcional)
#   APP_URL                https://app.exemplo.com                          (opcional)
#   SESSAO_COOKIE          cookie de um usuário de TESTE sem permissão: só preview/staging do
#                          próprio projeto (política do 08-perimetro-dinamico.md), nunca cliente
# Argumentos: rotas protegidas a conferir sem sessão (ex.: /admin /admin/usuarios /api/diag).
#
# Saída: uma linha por fato, `VEREDITO chave valor`, e o que não foi medido diz por quê.
# Exit 0 sempre que mediu algo; 2 sem as entradas mínimas.
set -uo pipefail

: "${SUPABASE_URL:=}" ; : "${SUPABASE_ANON_KEY:=}" ; : "${SUPABASE_ACCESS_TOKEN:=}" ; : "${APP_URL:=}" ; : "${SESSAO_COOKIE:=}"
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "uso: SUPABASE_URL=… SUPABASE_ANON_KEY=… [SUPABASE_ACCESS_TOKEN=…] [APP_URL=…] $0 [/rota …]" >&2
  exit 2
fi
command -v curl >/dev/null 2>&1 || { echo "curl ausente" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq ausente" >&2; exit 2; }
SB="${SUPABASE_URL%/}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sonda-auth.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

# 1. O que o GoTrue anuncia a qualquer um (o mesmo que o atacante lê)
cod="$(curl -sS -o "$TMP/settings.json" -w '%{http_code}' --max-time 15 \
        -H "apikey: $SUPABASE_ANON_KEY" "$SB/auth/v1/settings" 2>/dev/null)"
if [ "$cod" = "200" ] && jq -e . "$TMP/settings.json" >/dev/null 2>&1; then
  ds="$(jq -r '.disable_signup' "$TMP/settings.json")"
  ac="$(jq -r '.mailer_autoconfirm' "$TMP/settings.json")"
  echo "MEDIDO auth_settings GET /auth/v1/settings → 200"
  if [ "$ds" = "false" ]; then
    echo "VEREDITO cadastro ABERTO (disable_signup=false): qualquer um cria conta com a chave anon"
  else
    echo "VEREDITO cadastro fechado (disable_signup=$ds)"
  fi
  if [ "$ac" = "true" ]; then
    echo "VEREDITO e-mail AUTO-CONFIRMADO (mailer_autoconfirm=true): o e-mail da conta é o que a pessoa digitou"
  else
    echo "VEREDITO confirmação de e-mail exigida (mailer_autoconfirm=$ac)"
  fi
  provs="$(jq -r '.external // {} | to_entries | map(select(.value==true)) | map(.key) | join(",")' "$TMP/settings.json")"
  echo "VEREDITO provedores ligados: ${provs:-nenhum}"
else
  echo "NAO_MEDIDO auth_settings GET /auth/v1/settings → ${cod:-sem resposta} (chave anon errada ou projeto fora do ar)"
fi

# 2. Senha mínima e checagem de vazamento: só a Management API mostra (o /settings não traz)
ref="${SB#*://}"; ref="${ref%%.*}"
if [ -n "$SUPABASE_ACCESS_TOKEN" ]; then
  # O PAT vai num arquivo de header (0600, apagado no fim), não no argv do curl: argumento de
  # processo aparece no `ps` de qualquer usuário da máquina enquanto a chamada dura.
  ( umask 077; printf 'Authorization: Bearer %s\n' "$SUPABASE_ACCESS_TOKEN" > "$TMP/pat.h" )
  cod="$(curl -sS -o "$TMP/auth.json" -w '%{http_code}' --max-time 15 \
          -H @"$TMP/pat.h" \
          "https://api.supabase.com/v1/projects/$ref/config/auth" 2>/dev/null)"
  rm -f "$TMP/pat.h"
  if [ "$cod" = "200" ] && jq -e . "$TMP/auth.json" >/dev/null 2>&1; then
    jq -r '"VEREDITO senha mínima=\(.password_min_length // "?") requisitos=\(.password_required_characters // "nenhum" | if .=="" then "nenhum" else . end) vazadas_bloqueadas=\(.password_hibp_enabled // false) disable_signup=\(.disable_signup) mailer_autoconfirm=\(.mailer_autoconfirm)"' \
      "$TMP/auth.json"
    min="$(jq -r '.password_min_length // 0' "$TMP/auth.json")"
    [ "${min:-0}" -lt 8 ] 2>/dev/null && echo "VEREDITO senha mínima abaixo de 8: alinhe o painel com a regra do app"
  else
    echo "NAO_MEDIDO auth_config Management API → ${cod:-sem resposta} (PAT sem acesso ao projeto?)"
  fi
else
  echo "NAO_MEDIDO senha_minima sem SUPABASE_ACCESS_TOKEN: confira em Authentication > Password Security no painel"
fi

# 3. Rotas protegidas, sem sessão: o status real, não o que o código diz
if [ -n "$APP_URL" ]; then
  APP="${APP_URL%/}"
  csp="$(curl -sSI --max-time 15 "$APP/" 2>/dev/null | grep -ci '^content-security-policy:')"
  csp_ro="$(curl -sSI --max-time 15 "$APP/" 2>/dev/null | grep -ci '^content-security-policy-report-only:')"
  if [ "${csp:-0}" -gt 0 ]; then echo "VEREDITO CSP presente em /"
  elif [ "${csp_ro:-0}" -gt 0 ]; then echo "VEREDITO CSP só em Report-Only em / (não bloqueia)"
  else echo "VEREDITO CSP AUSENTE em /"; fi
  curl -sSI --max-time 15 "$APP/" 2>/dev/null > "$TMP/h.txt"
  for h in cross-origin-opener-policy cross-origin-resource-policy; do
    grep -qi "^$h:" "$TMP/h.txt" && echo "VEREDITO $h presente" || echo "VEREDITO $h AUSENTE em /"
  done
  if grep -qi '^strict-transport-security:' "$TMP/h.txt"; then
    grep -i '^strict-transport-security:' "$TMP/h.txt" | grep -qi preload \
      && echo "VEREDITO HSTS com preload" || echo "VEREDITO HSTS sem preload"
  else echo "VEREDITO HSTS AUSENTE em /"; fi
  # robots.txt e security.txt: servidos de verdade, ou o middleware manda para o login?
  for arq in /robots.txt /.well-known/security.txt; do
    res="$(curl -sS -o "$TMP/arq.txt" -w '%{http_code} %{content_type} %{redirect_url}' --max-time 15 --max-redirs 0 \
            "$APP$arq" 2>/dev/null)"
    st="${res%% *}"
    if [ "$st" = "200" ] && echo "$res" | grep -qi 'text/plain'; then echo "VEREDITO $arq servido (200 text/plain)"
    else echo "VEREDITO $arq NÃO servido ($res): ausente ou capturado pelo middleware"; fi
  done
  # Sem sessão, o middleware costuma responder 307 antes da página: o 200 com meta-refresh de
  # guard depois do flush só aparece com uma sessão que passa o middleware e não passa a página.
  quem="sem sessão"; CK=()
  if [ -n "$SESSAO_COOKIE" ]; then quem="sessão de teste"; CK=(-H "Cookie: $SESSAO_COOKIE"); fi
  for rota in "$@"; do
    res="$(curl -sS -o "$TMP/rota.html" -w '%{http_code} %{redirect_url}' --max-time 15 --max-redirs 0 \
            ${CK[@]+"${CK[@]}"} "$APP$rota" 2>/dev/null)"
    st="${res%% *}"; loc="${res#* }"
    if [ "$st" = "200" ] && grep -qi 'http-equiv="\?refresh' "$TMP/rota.html" 2>/dev/null; then
      echo "VEREDITO $rota ($quem) → 200 com meta-refresh: o guard roda depois do primeiro flush (monitor lê 'saudável', notFound não dá 404)"
    elif [ "$st" = "200" ]; then
      echo "VEREDITO $rota ($quem) → 200: confira se a página entrega dado ou só a casca"
    else
      echo "VEREDITO $rota ($quem) → $st ${loc:+→ $loc}"
    fi
  done
  [ -z "$SESSAO_COOKIE" ] && [ $# -gt 0 ] && echo "NAO_MEDIDO guard_com_sessao 307 sem sessão prova o middleware, não a página: o 200 com meta-refresh só aparece com sessão de papel baixo (SESSAO_COOKIE, em preview/staging)"
else
  [ $# -gt 0 ] && echo "NAO_MEDIDO rotas sem APP_URL"
fi
exit 0
