#!/usr/bin/env bash
# O modo completo do collect.sh vê o .env e o JWT untracked fora do .gitignore, como o --diff.
#
# Até a 0.43.0 só o --diff lia `git ls-files --others --exclude-standard`: a auditoria completa
# (a baseline sem --diff) olhava só o que o git rastreia, e o .env novo que o próximo
# `git add -A` versiona saía limpo. O que o .gitignore cobre continua fora.
#
# Os nomes são de propósito: "meu segredo.env" tem espaço e "ação.ts" tem acento. Sem
# core.quotePath=false o git cita o segundo com escape octal, e um produtor com aspas e outro
# sem desencontram o `grep -Fxf` que cruza o JWT com a lista de untracked.
#
# Uso: bash tests/test-collect-completo-untracked.sh [caminho-do-collect.sh]
set -uo pipefail
SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/baseline/scripts/collect.sh}"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq ausente — o collect.sh depende dele"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/collect-completo.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

# JWT falso montado aqui, para o próprio teste não carregar um literal que scanner acusa
JWT_FAKE="eyJ$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12).eyJ$(printf 'y%.0s' 1 2 3 4 5 6 7 8 9 10 11 12)"

R="$TMP/repo"
git init -q -b main "$R"
git -C "$R" config user.email t@t; git -C "$R" config user.name t
git -C "$R" config commit.gpgsign false
# o excludesFile global de quem roda (muitos ignoram .env) não pode decidir o teste
git -C "$R" config core.excludesFile /dev/null
printf '{"name":"fixture"}\n' > "$R/package.json"
printf '.env.local\nignorado/\n' > "$R/.gitignore"
git -C "$R" add package.json .gitignore
git -C "$R" commit -qm base
BASE="$(git -C "$R" rev-parse HEAD)"

# untracked e fora do .gitignore
printf 'SUPABASE_KEY=%s\n' "$JWT_FAKE" > "$R/.env"
printf 'K=%s\n' "$JWT_FAKE" > "$R/meu segredo.env"
printf 'export const k = "%s";\n' "$JWT_FAKE" > "$R/ação.ts"
# ignorado: fica fora nos dois modos
printf 'K=%s\n' "$JWT_FAKE" > "$R/.env.local"
mkdir -p "$R/ignorado"; printf 'K=%s\n' "$JWT_FAKE" > "$R/ignorado/segredo.ts"

roda() { # roda <n> [args] — deixa EXIT e o findings.json em $TMP/out-<n>
  local n="$1"; shift
  bash "$SCRIPT" --root "$R" --out "$TMP/out-$n" --pilar 07 "$@" >/dev/null 2>"$TMP/err-$n"
  EXIT=$?; ERRF="$TMP/err-$n"
  J="$TMP/out-$n/findings.json"
}
titulo() { jq -r --arg t "$1" '.findings[] | select(.pilar=="07" and (.title | test($t))) | "\(.severity)|\(.title)|\(.file)|\(.detail)"' "$J" 2>/dev/null; }

for modo in completo diff; do
  if [ "$modo" = completo ]; then roda 1; else roda 2 --diff "$BASE"; fi
  echo "== modo $modo: untracked fora do .gitignore reprova =="
  [ "$EXIT" -eq 1 ] && ok "exit 1" || falha "exit $EXIT (esperado 1); stderr: $(head -c 200 "$ERRF")"

  env_u="$(titulo 'Arquivo .env untracked')"
  case "$env_u" in
    HIGH*"|.env|"*) ok ".env untracked: HIGH" ;;
    *) falha ".env untracked não virou HIGH: ${env_u:-<ausente>}" ;;
  esac
  case "$env_u" in
    *.env.local*) falha ".env.local está no .gitignore e entrou" ;;
    *) ok ".env.local (no .gitignore) fica fora" ;;
  esac

  jwt_u="$(titulo 'JWT em arquivo untracked')"
  case "$jwt_u" in HIGH*) ok "JWT untracked: HIGH" ;; *) falha "JWT untracked não virou HIGH: ${jwt_u:-<ausente>}" ;; esac
  for f in "meu segredo.env" "ação.ts" ".env"; do
    case "$jwt_u" in
      *"$f"*) ok "o finding cita '$f' com o nome como está no disco" ;;
      *) falha "o finding não cita '$f': ${jwt_u:-<ausente>}" ;;
    esac
  done
  case "$jwt_u" in
    *'\303'*) falha "nome com escape octal do git no finding: $jwt_u" ;;
    *) ok "sem escape octal no nome" ;;
  esac
  case "$jwt_u" in
    *ignorado/segredo.ts*|*.env.local*) falha "arquivo do .gitignore entrou no JWT untracked" ;;
    *) ok "o que o .gitignore cobre fica fora" ;;
  esac

  cob="$(jq -r '.coverage[] | select(.pilar=="07" and .check=="jwt_no_head") | .reason' "$J" 2>/dev/null)"
  case "$cob" in
    *untracked*) ok "a cobertura diz que leu o untracked: $cob" ;;
    *) falha "a cobertura não fala do untracked: ${cob:-<vazia>}" ;;
  esac
done

echo "== modo completo: o que já está no git continua CRITICAL =="
git -C "$R" add .env; git -C "$R" commit -qm env
roda 3
crit="$(titulo 'Arquivo .env versionado')"
case "$crit" in CRITICAL*) ok ".env versionado: CRITICAL" ;; *) falha ".env versionado: ${crit:-<ausente>}" ;; esac
env_u="$(titulo 'Arquivo .env untracked')"
case "$env_u" in *"|.env|"*) falha "o .env já versionado saiu também como untracked" ;; *) ok "o versionado não se repete como untracked" ;; esac

echo
if [ "$falhas" -eq 0 ]; then echo "TODOS OS CHECKS PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit "$falhas"
