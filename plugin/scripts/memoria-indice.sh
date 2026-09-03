#!/usr/bin/env bash
# memoria-indice.sh — mantém o índice de memória do projeto em dois níveis.
#
# O MEMORY.md de .context/memoria/ entra no contexto de TODA request. Sem teto ele
# cresce com o projeto: 57 KB num CRM (303 memórias), 27 KB e 22 KB em outros dois
# — e nada avisava nem cortava. Este script redistribui as linhas do
# índice em dois arquivos:
#
#   MEMORY.md           índice curto, até --cap bytes (default 8192). A primeira
#                       linha é fixa e aponta para o completo. É o que o harness lê.
#   MEMORY-completo.md  a cauda: mesmo formato, mesma ordem, o que não coube. O
#                       agente faz grep aqui antes de concluir que algo não existe.
#
# Prioridade (o que fica no curto): `type` do frontmatter do arquivo alvo —
# feedback > user > reference > project > sem tipo — e, dentro do tipo,
# `metadata.modified` mais recente primeiro; sem data vai por último. Quando o mesmo
# arquivo aparece nos dois índices, a linha do MEMORY.md vence. Linha cujo arquivo
# alvo não existe mais é descartada, avisando. Linha do MEMORY.md que não é índice
# (cabeçalho de seção, prosa) também sai, avisando qual.
#
# Idempotente: rodar duas vezes não muda nada. Memória nova entra sempre no
# MEMORY.md — é onde o harness escreve — e é redistribuída na rodada seguinte.
# Se tudo cabe no cap, não há MEMORY-completo.md (um existente é removido).
#
# Uso:
#   memoria-indice.sh <dir .context/memoria> [--cap 8192] [--apply]
#   Sem --apply é dry-run: mostra o que faria e não escreve nada.
#
set -euo pipefail
# Bytes, não caracteres: o cap é em bytes e ${#s} só conta bytes em C. Também deixa
# o sort igual em qualquer máquina — a ordem é parte da idempotência.
export LC_ALL=C

die() { echo "memoria-indice: $*" >&2; exit 2; }

DIR=""; CAP=8192; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --cap)     [ $# -ge 2 ] || die "--cap precisa de um valor"; CAP="$2"; shift 2 ;;
    --cap=*)   CAP="${1#--cap=}"; shift ;;
    --apply)   APPLY=1; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    -*)        die "flag desconhecida: $1 (use --cap N, --apply)" ;;
    *)         [ -z "$DIR" ] || die "um diretório só: '$DIR' e '$1'"; DIR="$1"; shift ;;
  esac
done
[ -n "$DIR" ] || die "uso: memoria-indice.sh <dir .context/memoria> [--cap 8192] [--apply]"
[ -d "$DIR" ] || die "não é diretório: $DIR"
case "$CAP" in ''|*[!0-9]*) die "--cap tem que ser um inteiro em bytes (veio '$CAP')" ;; esac
[ "$CAP" -gt 0 ] || die "--cap tem que ser maior que zero"

INDICE="$DIR/MEMORY.md"
COMPLETO="$DIR/MEMORY-completo.md"
NOME_COMPLETO="$(basename "$COMPLETO")"
[ -f "$INDICE" ] || die "sem MEMORY.md em $DIR"

TAB="$(printf '\t')"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/memoria-indice.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

CABECALHO_COMPLETO="Cauda do índice de memória (gerado por memoria-indice.sh): o que não coube no MEMORY.md, na mesma ordem de prioridade. Memória nova entra SEMPRE no MEMORY.md; este arquivo é reescrito na próxima rodada."

# 1. Coleta as linhas de índice dos dois arquivos, sem duplicata (primeira ocorrência
#    vence — o MEMORY.md é lido antes). Linha de índice: "- [Título](arquivo.md) …".
#    A linha fixa (alvo MEMORY-completo.md) é regenerada, não copiada. O que não é
#    índice no MEMORY.md vai para um arquivo à parte, para avisar; no completo é
#    ignorado (o cabeçalho é nosso).
FONTES=("$INDICE")
[ -f "$COMPLETO" ] && FONTES+=("$COMPLETO")
awk -v completo="$NOME_COMPLETO" -v prosa="$TMPD/prosa" -v dup="$TMPD/duplicatas" '
  { sub(/\r$/, "") }
  /^- \[/ && match($0, /\]\([^()]*\.md\)/) {
    alvo = substr($0, RSTART + 2, RLENGTH - 3)
    sub(/^\.\//, "", alvo)
    if (alvo == completo) next
    if (alvo in visto) { print alvo > dup; next }
    visto[alvo] = 1
    print alvo "\t" $0
    next
  }
  FNR == NR && $0 !~ /^[ \t]*$/ { print $0 > prosa }   # só do primeiro arquivo (MEMORY.md)
' "${FONTES[@]}" > "$TMPD/brutas"

# 2. Para cada linha: o alvo existe? Qual o type e o modified? Vira
#    "rank <TAB> datakey <TAB> alvo <TAB> linha", que é o que o sort ordena.
#    Sem data, a chave é "0": no sort reverso ela cai depois de qualquer ISO.
frontmatter() { # frontmatter <arquivo> → "type<TAB>modified"
  awk '
    NR == 1 && $0 !~ /^---[ \t\r]*$/ { exit }
    NR > 1  && $0 ~  /^---[ \t\r]*$/ { exit }
    NR > 1 {
      sub(/\r$/, "")
      if ($0 ~ /^[ \t]*type:[ \t]*/)     { t = $0; sub(/^[ \t]*type:[ \t]*/, "", t);     gsub(/["'"'"' \t]/, "", t) }
      if ($0 ~ /^[ \t]*modified:[ \t]*/) { m = $0; sub(/^[ \t]*modified:[ \t]*/, "", m); gsub(/["'"'"' \t]/, "", m) }
    }
    END { printf "%s\t%s\n", t, m }
  ' "$1"
}

: > "$TMPD/inexistentes"
: > "$TMPD/classificadas"
while IFS="$TAB" read -r alvo linha; do
  [ -n "$alvo" ] || continue
  if [ ! -f "$DIR/$alvo" ]; then echo "$alvo" >> "$TMPD/inexistentes"; continue; fi
  IFS="$TAB" read -r tipo modificado <<< "$(frontmatter "$DIR/$alvo")"
  case "$tipo" in
    feedback)  rank=0 ;;
    user)      rank=1 ;;
    reference) rank=2 ;;
    project)   rank=3 ;;
    *)         rank=4; tipo="${tipo:-sem-tipo}" ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\n' "$rank" "${modificado:-0}" "$alvo" "$tipo" "$linha" >> "$TMPD/classificadas"
done < "$TMPD/brutas"

sort -t "$TAB" -k1,1n -k2,2r -k3,3 "$TMPD/classificadas" > "$TMPD/ordenadas"

# 3. Distribui. A linha fixa é a primeira do curto e reserva espaço antes de
#    qualquer outra; o N dela é conhecido só no fim, então a reserva usa o total
#    (limite superior de dígitos). O curto é um PREFIXO da ordem: a primeira linha
#    que não cabe fecha o curto, e daí em diante tudo é cauda — assim "está no
#    curto" quer dizer "tem prioridade sobre tudo que está no completo".
linha_fixa() { printf -- '- [Índice completo](%s) — %s memórias fora do índice curto; grep aqui antes de assumir que não existe' "$NOME_COMPLETO" "$1"; }

TOTAL="$(wc -l < "$TMPD/ordenadas" | tr -d ' ')"
BYTES_TOTAL="$(awk -F '\t' '{ n += length($5) + 1 } END { print n + 0 }' "$TMPD/ordenadas")"

: > "$TMPD/curto"; : > "$TMPD/cauda"
N_CURTO=0; N_CAUDA=0
if [ "$BYTES_TOTAL" -le "$CAP" ]; then
  cut -f 5- "$TMPD/ordenadas" > "$TMPD/curto"
  N_CURTO="$TOTAL"
else
  fixa_max="$(linha_fixa "$TOTAL")"
  orcamento=$(( CAP - ${#fixa_max} - 1 ))
  acumulado=0; cortou=0
  while IFS="$TAB" read -r _rank _data _alvo _tipo linha; do
    if [ "$cortou" -eq 0 ] && [ $(( acumulado + ${#linha} + 1 )) -le "$orcamento" ]; then
      printf '%s\n' "$linha" >> "$TMPD/curto"; acumulado=$(( acumulado + ${#linha} + 1 )); N_CURTO=$((N_CURTO + 1))
    else
      cortou=1; printf '%s\n' "$linha" >> "$TMPD/cauda"; N_CAUDA=$((N_CAUDA + 1))
    fi
  done < "$TMPD/ordenadas"
  { linha_fixa "$N_CAUDA"; echo; cat "$TMPD/curto"; } > "$TMPD/curto.final"
  mv "$TMPD/curto.final" "$TMPD/curto"
  { printf '%s\n' "$CABECALHO_COMPLETO"; cat "$TMPD/cauda"; } > "$TMPD/cauda.final"
  mv "$TMPD/cauda.final" "$TMPD/cauda"
fi

# 4. Relatório — e escrita, só com --apply.
BYTES_CURTO="$(wc -c < "$TMPD/curto" | tr -d ' ')"
N_INEXISTENTES="$(wc -l < "$TMPD/inexistentes" | tr -d ' ')"
N_PROSA="$( [ -f "$TMPD/prosa" ] && wc -l < "$TMPD/prosa" | tr -d ' ' || echo 0 )"
N_DUP="$( [ -f "$TMPD/duplicatas" ] && wc -l < "$TMPD/duplicatas" | tr -d ' ' || echo 0 )"

echo "memoria-indice — $DIR (cap $CAP bytes)"
echo "  memórias indexadas: $TOTAL · duplicatas resolvidas: $N_DUP · alvo inexistente (descartadas): $N_INEXISTENTES"
[ "$N_INEXISTENTES" -gt 0 ] && sed 's/^/      ! sem arquivo: /' "$TMPD/inexistentes"
if [ "$N_PROSA" -gt 0 ]; then
  echo "  ! $N_PROSA linha(s) do MEMORY.md que não são índice saem (cabeçalho/prosa):"
  cut -c 1-100 "$TMPD/prosa" | sed 's/^/      /'
fi
echo "  por tipo: $(cut -f 4 "$TMPD/ordenadas" | sort | uniq -c | awk '{ printf "%s%s %s", (n++ ? ", " : ""), $2, $1 } END { if (!n) printf "nenhuma" }')"
if [ "$N_CAUDA" -eq 0 ]; then
  echo "  MEMORY.md: $N_CURTO linha(s) · $BYTES_CURTO bytes — tudo cabe; sem $NOME_COMPLETO"
else
  echo "  MEMORY.md: $((N_CURTO + 1)) linha(s) (fixa + $N_CURTO) · $BYTES_CURTO bytes"
  echo "  $NOME_COMPLETO: $((N_CAUDA + 1)) linha(s) (cabeçalho + $N_CAUDA) · $(wc -c < "$TMPD/cauda" | tr -d ' ') bytes"
fi

mudou=0
cmp -s "$TMPD/curto" "$INDICE" || mudou=1
if [ "$N_CAUDA" -eq 0 ]; then
  [ -e "$COMPLETO" ] && mudou=1
else
  cmp -s "$TMPD/cauda" "$COMPLETO" 2>/dev/null || mudou=1
fi

if [ "$mudou" -eq 0 ]; then
  echo "  já em dia — nada a escrever."
  exit 0
fi
if [ "$APPLY" -eq 0 ]; then
  echo "[dry-run] nada escrito. Para aplicar: bash ${BASH_SOURCE[0]} \"$DIR\" --cap $CAP --apply"
  exit 0
fi

# Escreve ao lado e move: leitura no meio da escrita vê o arquivo antigo ou o novo,
# nunca metade. Temporário no mesmo diretório para o mv ser rename, não cópia.
cp "$TMPD/curto" "$DIR/.MEMORY.md.$$" && mv "$DIR/.MEMORY.md.$$" "$INDICE"
if [ "$N_CAUDA" -eq 0 ]; then
  [ -e "$COMPLETO" ] && { rm -f "$COMPLETO"; echo "  removido $NOME_COMPLETO (tudo cabe no MEMORY.md)"; }
else
  cp "$TMPD/cauda" "$DIR/.$NOME_COMPLETO.$$" && mv "$DIR/.$NOME_COMPLETO.$$" "$COMPLETO"
fi
echo "  escrito."
