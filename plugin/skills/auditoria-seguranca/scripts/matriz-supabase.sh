#!/usr/bin/env bash
# matriz-supabase.sh — matriz de RLS do Supabase: papel × tabela × operação, contando linhas.
#
# Parte da auditoria-seguranca (references/corroborar-dinamico.md). Serve para subir um achado
# de RLS de `lido` para `corroborado` com uma medição repetível, sem colar token na conversa.
#
# Entradas por VARIÁVEL DE AMBIENTE (argumento vai para o histórico do shell e para o `ps`):
#   SUPABASE_URL              ex.: http://127.0.0.1:54321  (só esquema, host, porta e caminho são usados)
#   SUPABASE_ANON_KEY         anon/publishable key (SUPABASE_PUBLISHABLE_KEY também serve)
#   MATRIZ_JWT_A, MATRIZ_JWT_B, MATRIZ_JWT_ADMIN   JWT de cada papel; papel sem JWT fica de fora
# Só no modo escrita:
#   MATRIZ_FILTRO             filtro PostgREST do UPDATE/DELETE, ex.: id=eq.<uuid-do-seed>
#   MATRIZ_CORPO_INSERT       JSON do INSERT;  MATRIZ_CORPO_UPDATE  JSON do UPDATE
#
# Argumentos: nomes de tabela, `--escrita` e `--env <arquivo>`. Token nunca é argumento.
#   --env <arquivo>  lê as variáveis acima de um arquivo NOME=valor (fora do repo, chmod 600),
#                    para quando o shell que roda o script não é o da pessoa. O arquivo é lido,
#                    nunca executado; só os nomes acima são aceitos, e variável já definida no
#                    ambiente vence o arquivo.
#
# Modo padrão: só leitura. HEAD com `Prefer: count=exact` por papel; nenhum dado volta, só a
# contagem do Content-Range. Modo `--escrita`: também INSERT/UPDATE/DELETE, e SÓ se o host for
# localhost, 127.0.0.1 ou [::1] (Supabase local). Não há flag que libere host remoto.
#
# Resultado por célula: número de linhas, `negado` (401/403), `aceito` (INSERT 2xx) ou
# `nao_medido` (rede, status inesperado, sem Content-Range). Erro de rede nunca vira 0.
# Saída: exit 0 tudo medido; 3 sobrou célula não medida; 2 uso inválido ou escrita recusada.
set -uo pipefail

uso() { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; }

# carrega_env <arquivo>: NOME=valor, com `export ` e aspas opcionais; nunca `source`.
carrega_env() {
  local linha nome valor
  [ -f "$1" ] && [ -r "$1" ] || { echo "matriz-supabase: --env: arquivo não encontrado ou ilegível" >&2; exit 2; }
  while IFS= read -r linha || [ -n "$linha" ]; do
    linha="${linha%$'\r'}"
    linha="${linha#"${linha%%[![:space:]]*}"}"
    linha="${linha#export }"
    case "$linha" in ''|'#'*) continue ;; esac
    nome="${linha%%=*}"; valor="${linha#*=}"
    [ "$nome" != "$linha" ] || continue
    case "$valor" in \"*\") valor="${valor#\"}"; valor="${valor%\"}" ;; \'*\') valor="${valor#\'}"; valor="${valor%\'}" ;; esac
    case "$nome" in
      SUPABASE_URL|SUPABASE_ANON_KEY|SUPABASE_PUBLISHABLE_KEY|MATRIZ_JWT_A|MATRIZ_JWT_B|MATRIZ_JWT_ADMIN|MATRIZ_FILTRO|MATRIZ_CORPO_INSERT|MATRIZ_CORPO_UPDATE)
        [ -n "${!nome:-}" ] || printf -v "$nome" '%s' "$valor" ;;
    esac
  done < "$1"
}

ESCRITA=0
TABELAS=()
ENVARQ=""
while [ "$#" -gt 0 ]; do
  a="$1"; shift
  case "$a" in
    --escrita) ESCRITA=1 ;;
    --env) [ "$#" -gt 0 ] || { echo "matriz-supabase: --env pede um arquivo" >&2; exit 2; }; ENVARQ="$1"; shift ;;
    -h|--help) uso; exit 0 ;;
    -*) case "$a" in --[a-z]*) echo "matriz-supabase: flag desconhecida: ${a%%=*}" >&2 ;; *) echo "matriz-supabase: flag desconhecida" >&2 ;; esac; exit 2 ;;
    *)
      # Nome de tabela é identificador. Qualquer outra coisa (inclusive um token colado por
      # engano) é recusada sem ecoar o valor.
      if printf '%s' "$a" | LC_ALL=C grep -Eq '^[A-Za-z_][A-Za-z0-9_]{0,62}$'; then
        TABELAS+=("$a")
      else
        echo "matriz-supabase: argumento recusado (não é nome de tabela; token vai por variável de ambiente)" >&2
        exit 2
      fi ;;
  esac
done
[ "${#TABELAS[@]}" -gt 0 ] || { echo "matriz-supabase: informe ao menos uma tabela" >&2; uso >&2; exit 2; }
[ -z "$ENVARQ" ] || carrega_env "$ENVARQ"

KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
[ -n "${SUPABASE_URL:-}" ] || { echo "matriz-supabase: defina SUPABASE_URL" >&2; exit 2; }
[ -n "$KEY" ] || { echo "matriz-supabase: defina SUPABASE_ANON_KEY (ou SUPABASE_PUBLISHABLE_KEY)" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "matriz-supabase: python3 não encontrado" >&2; exit 2; }

# Esquema, host e a base sem userinfo, query nem fragmento. A requisição usa ESTA base, então o
# host checado é o host contatado (http://127.0.0.1@exemplo.test vira exemplo.test).
PARSE="$(python3 -I -c '
import sys, urllib.parse
try:
    u = urllib.parse.urlsplit(sys.argv[1].strip())
    h = (u.hostname or "").lower().rstrip(".")
    p = u.port
except ValueError:
    sys.exit(1)
if u.scheme not in ("http", "https") or not h:
    sys.exit(1)
hp = ("[%s]" % h) if ":" in h else h
if p: hp += ":%d" % p
print(u.scheme, h, "%s://%s%s" % (u.scheme, hp, u.path.rstrip("/")))
' "$SUPABASE_URL")" || { echo "matriz-supabase: SUPABASE_URL inválida (esperado http(s)://host[:porta])" >&2; exit 2; }
read -r _ESQUEMA HOST BASE <<EOF
$PARSE
EOF

if [ "$ESCRITA" -eq 1 ]; then
  case "$HOST" in
    localhost|127.0.0.1|::1) ;;
    *) echo "matriz-supabase: --escrita recusada: host '$HOST' não é localhost, 127.0.0.1 nem [::1]." >&2
       echo "  Escrita só roda contra Supabase local (supabase start) com usuários seed. Nunca contra o projeto do cliente." >&2
       exit 2 ;;
  esac
fi

command -v curl >/dev/null 2>&1 || { echo "matriz-supabase: curl não encontrado" >&2; exit 2; }

# Token com aspas, barra invertida ou espaço quebraria o config do curl: recusa sem mostrar.
token_ok() { case "$1" in *[\"\\[:space:]]*) return 1 ;; *) return 0 ;; esac; }
token_ok "$KEY" || { echo "matriz-supabase: a anon key tem caractere inválido" >&2; exit 2; }

PAPEIS=("anon")
TOKS=("$KEY")
for par in "A:A:${MATRIZ_JWT_A:-}" "B:B:${MATRIZ_JWT_B:-}" "admin:ADMIN:${MATRIZ_JWT_ADMIN:-}"; do
  p="${par%%:*}"; resto="${par#*:}"; var="${resto%%:*}"; t="${resto#*:}"
  if [ -z "$t" ]; then echo "# papel $p sem JWT (MATRIZ_JWT_$var): fora da matriz"; continue; fi
  token_ok "$t" || { echo "matriz-supabase: o JWT do papel $p tem caractere inválido" >&2; exit 2; }
  PAPEIS+=("$p"); TOKS+=("$t")
done

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/matriz-supabase.XXXXXX")" || { echo "matriz-supabase: mktemp falhou" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT
CELULAS="$TMPD/celulas.tsv"; : > "$CELULAS"
NAO_MEDIDAS=0

# requisita <token> <metodo> <url> [arquivo-de-corpo] -> imprime "<http_code> <total-do-Content-Range>"
# Os headers com token vão pelo stdin (curl -K -): não aparecem no argv nem no `ps`.
requisita() {
  local tok="$1" met="$2" url="$3" corpo="${4:-}" code total
  local args=(-sS --connect-timeout 5 --max-time 20 -o /dev/null -D "$TMPD/h" -w '%{http_code}' -K -)
  : > "$TMPD/h"
  if [ "$met" = "HEAD" ]; then args+=(--head); else args+=(-X "$met"); fi
  [ -n "$corpo" ] && args+=(-H 'Content-Type: application/json' --data-binary "@$corpo")
  code="$(printf 'url = "%s"\nheader = "apikey: %s"\nheader = "Authorization: Bearer %s"\nheader = "Prefer: return=minimal, count=exact"\n' \
            "$url" "$KEY" "$tok" | curl "${args[@]}" 2>/dev/null)" || true
  case "$code" in [0-9][0-9][0-9]) ;; *) code=000 ;; esac
  total="$(tr -d '\r' < "$TMPD/h" | awk 'tolower($1)=="content-range:"{print $2}' | tail -1)"
  total="${total##*/}"
  case "$total" in ''|*[!0-9]*) total='-' ;; esac
  printf '%s %s\n' "$code" "$total"
}

# celula <op> <papel> <tabela> <url> <code> <total> [motivo-forcado]
celula() {
  local op="$1" papel="$2" tab="$3" url="$4" code="$5" total="$6" motivo="${7:-}" res
  if [ -n "$motivo" ]; then res=nao_medido
  elif [ "$code" = 000 ]; then res=nao_medido; motivo=rede
  elif [ "$code" = 401 ] || [ "$code" = 403 ]; then res=negado
  else
    case "$code" in
      2??) if [ "$op" = INSERT ]; then res=aceito
           elif [ "$total" != '-' ]; then res="$total"
           else res=nao_medido; motivo=sem_content_range; fi ;;
      *) res=nao_medido; motivo="status_$code" ;;
    esac
  fi
  [ "$res" = nao_medido ] && NAO_MEDIDAS=$((NAO_MEDIDAS+1))
  printf 'matriz-supabase op=%s papel=%s tabela=%s resultado=%s http=%s%s url=%s\n' \
    "$op" "$papel" "$tab" "$res" "$code" "${motivo:+ motivo=$motivo}" "$url"
  printf '%s\t%s\t%s\t%s\n' "$papel" "$tab" "$op" "$res" >> "$CELULAS"
}

MODO=leitura; [ "$ESCRITA" -eq 1 ] && MODO=escrita
echo "# matriz-supabase modo=$MODO host=$HOST base=$BASE em $(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "$ESCRITA" -eq 1 ]; then
  [ -n "${MATRIZ_CORPO_INSERT:-}" ] && printf '%s' "$MATRIZ_CORPO_INSERT" > "$TMPD/insert.json"
  [ -n "${MATRIZ_CORPO_UPDATE:-}" ] && printf '%s' "$MATRIZ_CORPO_UPDATE" > "$TMPD/update.json"
fi
FILTRO="${MATRIZ_FILTRO:-}"

for tab in "${TABELAS[@]}"; do
  url="$BASE/rest/v1/$tab"
  i=0
  while [ "$i" -lt "${#PAPEIS[@]}" ]; do
    read -r c t <<EOF
$(requisita "${TOKS[$i]}" HEAD "$url")
EOF
    celula SELECT "${PAPEIS[$i]}" "$tab" "$url" "$c" "$t"
    i=$((i+1))
  done
  [ "$ESCRITA" -eq 1 ] || continue
  for op in INSERT UPDATE DELETE; do
    i=0
    while [ "$i" -lt "${#PAPEIS[@]}" ]; do
      p="${PAPEIS[$i]}"; falta=""; u="$url"; met=""; corpo=""
      case "$op" in
        INSERT) met=POST;   corpo="$TMPD/insert.json"; [ -f "$corpo" ] || falta=sem_MATRIZ_CORPO_INSERT ;;
        UPDATE) met=PATCH;  corpo="$TMPD/update.json"; [ -f "$corpo" ] || falta=sem_MATRIZ_CORPO_UPDATE
                [ -n "$FILTRO" ] || falta=sem_MATRIZ_FILTRO; u="$url?$FILTRO" ;;
        DELETE) met=DELETE; [ -n "$FILTRO" ] || falta=sem_MATRIZ_FILTRO; u="$url?$FILTRO" ;;
      esac
      # Sem filtro, UPDATE/DELETE pegaria a tabela inteira: não sai requisição.
      if [ -n "$falta" ]; then
        celula "$op" "$p" "$tab" "$u" - - "$falta"
      else
        read -r c t <<EOF
$(requisita "${TOKS[$i]}" "$met" "$u" "$corpo")
EOF
        celula "$op" "$p" "$tab" "$u" "$c" "$t"
      fi
      i=$((i+1))
    done
  done
done

echo
awk -F'\t' -v escrita="$ESCRITA" '
  { k=$1 SUBSEP $2; v[k SUBSEP $3]=$4; if(!(k in visto)){visto[k]=1; ordem[++n]=k} }
  END {
    ops = escrita ? "SELECT INSERT UPDATE DELETE" : "SELECT"; m = split(ops, o, " ")
    printf "%-8s %-24s", "papel", "tabela"; for(j=1;j<=m;j++) printf " %-11s", o[j]; print ""
    for(i=1;i<=n;i++){ split(ordem[i], pt, SUBSEP); printf "%-8s %-24s", pt[1], pt[2]
      for(j=1;j<=m;j++){ x=v[ordem[i] SUBSEP o[j]]; printf " %-11s", (x==""?"-":x) } print "" }
  }' "$CELULAS"
TOTAL="$(wc -l < "$CELULAS" | tr -d ' ')"
echo
echo "# $TOTAL célula(s), $NAO_MEDIDAS não medida(s). nao_medido não é 0: não cite como prova."
[ "$NAO_MEDIDAS" -eq 0 ] || exit 3
exit 0
