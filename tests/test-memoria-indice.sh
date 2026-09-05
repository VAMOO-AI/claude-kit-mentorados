#!/usr/bin/env bash
# O índice de memória em dois níveis respeita o cap, a ordem de prioridade e não
# perde linha (03/09/2026).
#
# O MEMORY.md entra no contexto de toda request e não tinha teto: 57 KB no
# zullo-imoveis. O memoria-indice.sh redistribui as linhas entre MEMORY.md (curto,
# até --cap bytes) e MEMORY-completo.md (cauda). Este teste cobre o que dói se
# quebrar: ordem (feedback > user > reference > project > sem tipo; mais recente
# primeiro; sem data por último), cap em bytes, linha fixa com o N certo,
# idempotência, linha nova redistribuída, duplicata resolvida a favor do MEMORY.md,
# alvo inexistente descartado com aviso, e o caso em que tudo cabe.
#
# Uso: bash tests/test-memoria-indice.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/plugin/scripts/memoria-indice.sh"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/memoria-indice.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
MEM="$TMP/memoria"
mkdir -p "$MEM"

ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperado '$3', veio '$2')"; fi; }

# mem <slug> <type|-> <modified|-> — cria o fato e a linha de índice
mem() {
  local slug="$1" tipo="$2" mod="$3"
  {
    echo "---"
    echo "name: $slug"
    echo "description: \"fato $slug\""
    echo "metadata:"
    echo "  node_type: memory"
    [ "$tipo" != "-" ] && echo "  type: $tipo"
    [ "$mod"  != "-" ] && echo "  modified: ${mod}T12:00:00.000Z"
    echo "---"
    echo
    echo "Conteúdo de $slug."
  } > "$MEM/$slug.md"
  echo "- [Memória $slug](${slug}.md) — gancho de $slug com acento: ação, coração, não"
}
# alvos_em <arquivo> — a sequência de arquivos alvo, na ordem do índice, sem fixa/cabeçalho
alvos_em() { [ -f "$1" ] && sed -n 's/^- \[.*\](\([^)]*\.md\)).*$/\1/p' "$1" | grep -v '^MEMORY-completo.md$' || true; }

# Ordem embaralhada de propósito: a saída tem que sair da prioridade, não da entrada.
{
  echo "## Acervo migrado de outro workspace"
  echo
  echo "Ficou preso na máquina até ontem."
  mem prj-b      project   2026-05-05
  mem ref-velha  reference 2026-07-01
  mem semtipo    -         -
  mem fb-semdata feedback  -
  mem prj-a      project   2026-08-30
  echo "- [Memória fantasma](fantasma.md) — o arquivo não existe mais"
  mem usr-1      user      2026-06-01
  mem prj-d      project   2026-08-31
  mem fb-velha   feedback  2026-07-10
  mem ref-semdata reference -
  mem prj-c      project   -
  mem fb-nova    feedback  2026-08-20
  mem ref-nova   reference 2026-09-01
} > "$MEM/MEMORY.md"
ESPERADA="fb-nova.md fb-velha.md fb-semdata.md usr-1.md ref-nova.md ref-velha.md ref-semdata.md prj-d.md prj-a.md prj-b.md prj-c.md semtipo.md"
CAP=600

echo "== dry-run não escreve =="
cp "$MEM/MEMORY.md" "$TMP/antes.md"
saida="$(bash "$SCRIPT" "$MEM" --cap "$CAP" 2>&1)"; rc=$?
check "dry-run sai 0" "$rc" "0"
cmp -s "$MEM/MEMORY.md" "$TMP/antes.md" && ok "MEMORY.md intacto no dry-run" || falha "dry-run alterou o MEMORY.md"
[ -e "$MEM/MEMORY-completo.md" ] && falha "dry-run criou o MEMORY-completo.md" || ok "dry-run não cria o completo"
printf '%s' "$saida" | grep -q 'dry-run' && ok "saída diz que é dry-run" || falha "saída não avisa que é dry-run"
printf '%s' "$saida" | grep -q 'sem arquivo: fantasma.md' && ok "avisa o alvo inexistente" || { falha "não avisou o alvo inexistente"; printf '%s\n' "$saida"; }
printf '%s' "$saida" | grep -q 'Acervo migrado' && ok "avisa a linha de prosa que sai" || { falha "não avisou a prosa que sai"; printf '%s\n' "$saida"; }

echo "== --apply: cap, linha fixa, ordem, cauda =="
bash "$SCRIPT" "$MEM" --cap "$CAP" --apply >"$TMP/apply.log" 2>&1 || { falha "--apply saiu com erro"; cat "$TMP/apply.log"; }
bytes="$(wc -c < "$MEM/MEMORY.md" | tr -d ' ')"
[ "$bytes" -le "$CAP" ] && ok "MEMORY.md tem $bytes bytes (cap $CAP)" || falha "MEMORY.md estourou o cap: $bytes > $CAP"
[ -f "$MEM/MEMORY-completo.md" ] && ok "MEMORY-completo.md criado" || falha "MEMORY-completo.md não foi criado"
n_cauda="$(alvos_em "$MEM/MEMORY-completo.md" | wc -l | tr -d ' ')"
n_curto="$(alvos_em "$MEM/MEMORY.md" | wc -l | tr -d ' ')"
check "curto + cauda = 12 memórias (fantasma fora)" "$((n_curto + n_cauda))" "12"
[ "$n_curto" -ge 2 ] && [ "$n_cauda" -ge 2 ] && ok "cap pequeno dividiu de verdade ($n_curto curto / $n_cauda cauda)" || falha "divisão degenerada: $n_curto / $n_cauda"
primeira="$(head -1 "$MEM/MEMORY.md")"
check "1ª linha é a fixa com o N da cauda" "$primeira" "- [Índice completo](MEMORY-completo.md) — $n_cauda memórias fora do índice curto; grep aqui antes de assumir que não existe"
head -1 "$MEM/MEMORY-completo.md" | grep -q 'SEMPRE no MEMORY.md' && ok "cabeçalho do completo diz onde a memória nova entra" || falha "cabeçalho do completo errado"
ordem="$( { alvos_em "$MEM/MEMORY.md"; alvos_em "$MEM/MEMORY-completo.md"; } | tr '\n' ' ' | sed 's/ $//')"
check "ordem: tipo, depois data desc, sem data por último" "$ordem" "$ESPERADA"
grep -q 'fantasma.md' "$MEM/MEMORY.md" "$MEM/MEMORY-completo.md" && falha "alvo inexistente ficou no índice" || ok "alvo inexistente descartado"
grep -q 'Acervo migrado' "$MEM/MEMORY.md" && falha "prosa ficou no MEMORY.md" || ok "prosa saiu do MEMORY.md"
grep -q 'coração' "$MEM/MEMORY.md" && ok "linha preservada byte a byte (acentos)" || falha "acentos corrompidos"

echo "== idempotência =="
cp "$MEM/MEMORY.md" "$TMP/curto1.md"; cp "$MEM/MEMORY-completo.md" "$TMP/cauda1.md"
saida="$(bash "$SCRIPT" "$MEM" --cap "$CAP" --apply 2>&1)"
cmp -s "$MEM/MEMORY.md" "$TMP/curto1.md" && cmp -s "$MEM/MEMORY-completo.md" "$TMP/cauda1.md" \
  && ok "segunda rodada não muda nada" || falha "segunda rodada alterou os arquivos"
printf '%s' "$saida" | grep -q 'já em dia' && ok "e diz que está em dia" || falha "não disse 'já em dia'"

echo "== linha nova no MEMORY.md é redistribuída na próxima rodada =="
mem fb-fresca feedback 2026-09-03 >> "$MEM/MEMORY.md"
bash "$SCRIPT" "$MEM" --cap "$CAP" --apply >/dev/null 2>&1
check "a nova (feedback, mais recente) vai para o topo do curto" "$(alvos_em "$MEM/MEMORY.md" | head -1)" "fb-fresca.md"
total="$( { alvos_em "$MEM/MEMORY.md"; alvos_em "$MEM/MEMORY-completo.md"; } | wc -l | tr -d ' ')"
check "nenhuma memória perdida no caminho" "$total" "13"
bytes="$(wc -c < "$MEM/MEMORY.md" | tr -d ' ')"
[ "$bytes" -le "$CAP" ] && ok "cap continua respeitado ($bytes)" || falha "cap estourado após a nova: $bytes"

echo "== duplicata: a linha do MEMORY.md vence a do completo =="
echo "- [Memória prj-c](prj-c.md) — gancho REESCRITO no curto" >> "$MEM/MEMORY.md"
bash "$SCRIPT" "$MEM" --cap "$CAP" --apply >/dev/null 2>&1
n="$(cat "$MEM/MEMORY.md" "$MEM/MEMORY-completo.md" | grep -c '(prj-c.md)')"
check "prj-c aparece uma vez só" "$n" "1"
cat "$MEM/MEMORY.md" "$MEM/MEMORY-completo.md" | grep -q 'REESCRITO no curto' && ok "venceu a versão do MEMORY.md" || falha "venceu a versão do completo"

echo "== tudo cabe: sem linha fixa, completo removido =="
bash "$SCRIPT" "$MEM" --cap 100000 --apply >"$TMP/grande.log" 2>&1
[ -e "$MEM/MEMORY-completo.md" ] && falha "completo ficou mesmo com tudo cabendo" || ok "MEMORY-completo.md removido"
grep -q 'Índice completo' "$MEM/MEMORY.md" && falha "linha fixa ficou sem cauda" || ok "sem linha fixa quando não há cauda"
check "as 13 memórias estão no MEMORY.md" "$(alvos_em "$MEM/MEMORY.md" | wc -l | tr -d ' ')" "13"
check "e a ordem se mantém" "$(alvos_em "$MEM/MEMORY.md" | head -3 | tr '\n' ' ' | sed 's/ $//')" "fb-fresca.md fb-nova.md fb-velha.md"

echo "== argumentos ruins =="
bash "$SCRIPT" "$MEM" --cap abc >/dev/null 2>&1 && falha "--cap não numérico aceito" || ok "--cap não numérico recusado"
bash "$SCRIPT" >/dev/null 2>&1 && falha "sem diretório aceito" || ok "sem diretório recusado"
bash "$SCRIPT" "$TMP" >/dev/null 2>&1 && falha "diretório sem MEMORY.md aceito" || ok "diretório sem MEMORY.md recusado"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; fi
exit "$falhas"
