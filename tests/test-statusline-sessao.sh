#!/usr/bin/env bash
# O `ses:` da barra mede a sessão como o session-size-guard: o contexto do último turno no
# transcript (input + cache_read + cache_creation do último usage, sem sidechain, iteração
# "message" do advisor, usage zerado ignorado, compact_boundary zera), nas faixas
# 150K/300K/400K+, e não quebra quando não há transcript. Contar linhas mandava /compact
# depois do /compact, porque o transcript só cresce. Também cobre o
# ⚡N t/s da última chamada de API e o aviso de troca de modelo no meio da sessão.
#
# A barra é o que a pessoa olha o dia inteiro, e o wrapper esconde erro
# (`|| printf '[statusline]'`): quebrar aqui não aparece como erro, aparece como barra
# sumida. Por isso o teste roda o .js direto e vigia o stderr.
#
# Uso: bash tests/test-statusline-sessao.sh [caminho-do-statusline.js]
set -uo pipefail
SL="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/statusline.js}"
[ -f "$SL" ] || { echo "statusline não encontrado: $SL"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }

falhas=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
# Transcript sintético: cada argumento vira uma linha. uN = usage de N tokens (repartido em
# input/cache_read/cache_creation), aN:M = advisor (usage de cima N, iteração message M),
# sN = sidechain com N, z = usage zerado, c = compact_boundary, pN = N linhas '{}' de enchimento.
tr() { ARGS="$*" node -e '
const L = [];
const us = (n) => ({ input_tokens: 1000, cache_read_input_tokens: n - 3000, cache_creation_input_tokens: 2000, output_tokens: 10 });
for (const a of process.env.ARGS.split(" ")) {
  const n = +a.slice(1).split(":")[0];
  if (a[0] === "u") L.push({ type: "assistant", message: { usage: us(n) } });
  else if (a[0] === "a") {
    const m = +a.split(":")[1];
    L.push({ type: "assistant", message: { usage: { ...us(n), iterations: [{ type: "message", ...us(m) }, { type: "advisor_message", ...us(n - m) }] } } });
  }
  else if (a[0] === "s") L.push({ type: "assistant", isSidechain: true, message: { usage: us(n) } });
  else if (a[0] === "z") L.push({ type: "assistant", message: { model: "<synthetic>", usage: { input_tokens: 0, output_tokens: 0 } } });
  else if (a[0] === "c") L.push({ type: "system", subtype: "compact_boundary" });
  else if (a[0] === "p") for (let i = 0; i < n; i++) L.push({});
}
process.stdout.write(L.map((x) => JSON.stringify(x)).join("\n") + "\n");' > "$TMP/tr.jsonl"; }
render() { TP="${1:-}" node -e 'process.stdout.write(JSON.stringify({transcript_path:process.env.TP||undefined,workspace:{current_dir:process.env.HOME},context_window:{current_usage:{input_tokens:1000}}}))' \
    | node "$SL" 2>>"$TMP/err" | sed 's/\x1b\[[0-9;]*m//g'; }

tr p100 u100000; s="$(render "$TMP/tr.jsonl")"
printf '%s' "$s" | grep -q 'ses:' && falha "apareceu abaixo de 150K: $s" || ok "100K: sem indicador"
printf '%s' "$s" | grep -q 'ctx:' && ok "o resto da barra continua saindo" || falha "barra vazia: $s"

tr u160000; s="$(render "$TMP/tr.jsonl")"
printf '%s' "$s" | grep -q 'ses:160k sessão nova?' && ok "160K: tokens + sessão nova?" || falha "faixa 150K errada: $s"
tr u320000; s="$(render "$TMP/tr.jsonl")"
printf '%s' "$s" | grep -q 'ses:320k /compact' && ok "320K em transcript curto: /compact" || falha "faixa 300K errada: $s"
tr u450000; s="$(render "$TMP/tr.jsonl")"
printf '%s' "$s" | grep -q 'ses:450k maratona' && ok "450K: faixa das maratonas" || falha "faixa 400K errada: $s"

tr u350000 p1300 c; s="$(render "$TMP/tr.jsonl")"
printf '%s' "$s" | grep -q 'ses:' && falha "mandou /compact depois do compact: $s" || ok "compact depois do último usage: sem indicador, mesmo com 1.300 linhas"
tr u350000 c u60000; s="$(render "$TMP/tr.jsonl")"
printf '%s' "$s" | grep -q 'ses:' && falha "valor de antes do compact: $s" || ok "turno de 60K depois do compact: sem indicador"
tr a340000:170000; s="$(render "$TMP/tr.jsonl")"
printf '%s' "$s" | grep -q 'ses:170k' && ok "advisor: vale a iteração message (170k), não a soma" || falha "advisor contou a soma: $s"
tr u200000 s500000; s="$(render "$TMP/tr.jsonl")"
printf '%s' "$s" | grep -q 'ses:200k' && ok "sidechain depois não entra" || falha "sidechain contou: $s"
tr u320000 z; s="$(render "$TMP/tr.jsonl")"
printf '%s' "$s" | grep -q 'ses:320k' && ok "usage zerado no fim: vale o anterior" || falha "usage zerado apagou a medida: $s"

s="$(render "$TMP/nao-existe.jsonl")"
printf '%s' "$s" | grep -q 'ctx:' && ok "transcript inexistente: barra normal" || falha "quebrou sem transcript: $s"
s="$(render)"
printf '%s' "$s" | grep -q 'ctx:' && ok "payload sem transcript_path: barra normal" || falha "quebrou sem o campo: $s"

# ── tokens/s da última chamada e aviso de troca de modelo ──
# HOME e TMPDIR temporários: a marca do primeiro modelo vai para o tmpdir, e o teste não
# pode deixar rastro na máquina de quem roda.
mkdir -p "$TMP/home" "$TMP/tmp"
# transcript sintético: $1 = arquivo, $2 = idade da resposta em segundos, $3 = cenário
fixture() { IDADE="$2" CEN="$3" node -e '
const t0 = Date.now() - Number(process.env.IDADE) * 1000;
const ts = (s) => new Date(t0 + s * 1000).toISOString();
const L = [];
const u = (s, extra) => L.push({ type: "user", timestamp: ts(s), message: { content: [{ type: "tool_result" }] }, ...extra });
const a = (s, id, out, extra) => L.push({ type: "assistant", timestamp: ts(s), message: { id, usage: { output_tokens: out } }, ...extra });
const c = process.env.CEN;
if (c === "tps") {
  // resposta anterior, que não pode contar
  u(-60); a(-58, "msg_velha", 9999);
  // última chamada: começa em -10s, 3 linhas do mesmo id com tool_result intercalado,
  // termina em 0s. 500 tokens / 10s = 50 t/s. Medir a partir do tool_result intercalado
  // daria 85 t/s; parar na primeira linha do id, 250.
  u(-10); a(-8, "msg_ultima", 500); a(-6, "msg_ultima", 500); u(-5.9); a(0, "msg_ultima", 500);
  // subagente (sidechain) depois: não entra na conta
  u(1, { isSidechain: true }); a(2, "msg_sub", 50000, { isSidechain: true });
} else if (c === "sem-assistant") {
  u(-10); L.push({ type: "system", timestamp: ts(-5) });
}
process.stdout.write(L.map((x) => JSON.stringify(x)).join("\n") + "\n");' > "$1"; }
render2() { TP="${1:-}" SID="${2:-}" MID="${3:-}" HOME="$TMP/home" node -e '
const p = { workspace: { current_dir: process.env.HOME }, context_window: { current_usage: { input_tokens: 1000 } } };
if (process.env.TP) p.transcript_path = process.env.TP;
if (process.env.SID) p.session_id = process.env.SID;
if (process.env.MID) p.model = { id: process.env.MID };
process.stdout.write(JSON.stringify(p));' \
    | HOME="$TMP/home" TMPDIR="$TMP/tmp" node "$SL" 2>>"$TMP/err" | sed 's/\x1b\[[0-9;]*m//g'; }

fixture "$TMP/tps.jsonl" 5 tps; s="$(render2 "$TMP/tps.jsonl")"
printf '%s' "$s" | grep -qF '⚡50 t/s' && ok "t/s da última chamada: 500 tokens em 10s = ⚡50 t/s" || falha "t/s errado ou ausente: $s"
printf '%s' "$s" | grep -q 'ctx:' && ok "com t/s, o resto da barra continua" || falha "barra quebrou com t/s: $s"
fixture "$TMP/velho.jsonl" 600 tps; s="$(render2 "$TMP/velho.jsonl")"
printf '%s' "$s" | grep -qF '⚡' && falha "resposta de 10 min atrás ainda pinta t/s: $s" || ok "resposta parada há >5 min: sem t/s"
fixture "$TMP/sem.jsonl" 5 sem-assistant; s="$(render2 "$TMP/sem.jsonl")"
printf '%s' "$s" | grep -qF '⚡' && falha "t/s sem resposta no transcript: $s" || ok "transcript sem resposta: sem t/s"
printf '%s' "$s" | grep -q 'ctx:' && ok "transcript sem resposta: barra normal" || falha "quebrou sem resposta: $s"
s="$(render2 "$TMP/nao-existe.jsonl")"
printf '%s' "$s" | grep -qF '⚡' && falha "t/s com transcript inexistente: $s" || ok "transcript inexistente: sem t/s"
printf '%s' "$s" | grep -q 'ctx:' && ok "transcript inexistente (t/s): barra normal" || falha "quebrou sem transcript: $s"

s="$(render2 "" sess-a claude-opus-5-5)"
printf '%s' "$s" | grep -q 'modelo trocou' && falha "acusou troca no primeiro render: $s" || ok "primeiro render: sem aviso de modelo"
s="$(render2 "" sess-a claude-opus-5-5)"
printf '%s' "$s" | grep -q 'modelo trocou' && falha "acusou troca com o mesmo modelo: $s" || ok "mesmo modelo: sem aviso"
s="$(render2 "" sess-a 'claude-opus-5-5[1m]')"
printf '%s' "$s" | grep -q 'modelo trocou' && falha "[1m] contou como troca: $s" || ok "só o [1m] mudou: sem aviso"
s="$(render2 "" sess-a claude-opus-4-8)"
printf '%s' "$s" | grep -qF '⚠ modelo trocou: opus-5-5→opus-4-8' && ok "safeguard trocou para o 4.8: aviso na barra" || falha "troca não apareceu: $s"
printf '%s' "$s" | grep -q 'ctx:' && ok "com o aviso, o resto da barra continua" || falha "barra quebrou com o aviso: $s"
s="$(render2 "" sess-b claude-opus-4-8)"
printf '%s' "$s" | grep -q 'modelo trocou' && falha "a marca vazou entre sessões: $s" || ok "outra sessão começa limpa"
s="$(render2 "" "../../x" claude-opus-5)"
printf '%s' "$s" | grep -q 'ctx:' && ok "session_id estranho: barra normal" || falha "quebrou com session_id estranho: $s"
[ -e "$TMP/tmp/x" ] || [ -e "$TMP/x" ] && falha "session_id com ../ virou caminho" || ok "session_id com ../ não vira caminho"
[ -z "$(ls -A "$TMP/home")" ] && ok "nada gravado no HOME" || falha "gravou no HOME: $(ls -A "$TMP/home")"

[ -s "$TMP/err" ] && falha "o .js escreveu em stderr: $(head -3 "$TMP/err")" || ok "nenhum erro em stderr"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
