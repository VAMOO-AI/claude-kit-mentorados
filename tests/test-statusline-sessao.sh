#!/usr/bin/env bash
# Uma linha só de contexto na barra. A `ctx:` lê o payload do harness (context_window); a
# `ses:` lê o transcript (input + cache_read + cache_creation do último usage, sem sidechain,
# iteração "message" do advisor, usage zerado ignorado, compact_boundary zera) e só aparece
# quando o payload não traz `context_window`. Nunca as duas juntas: antes as duas mandavam
# /compact a partir de 300K. A régua é a mesma: verde, amarelo em 150k, vermelho com /compact
# em 300k. Contar linhas do transcript mandava /compact depois do /compact, porque o
# transcript só cresce. Também cobre o ⚡N t/s da última chamada de API e o aviso de troca
# de modelo no meio da sessão.
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
# Sem context_window no payload: a `ses` é o fallback, lida do transcript. Saída crua (com cor).
render() { TP="${1:-}" node -e 'process.stdout.write(JSON.stringify({transcript_path:process.env.TP||undefined,workspace:{current_dir:process.env.HOME}}))' \
    | node "$SL" 2>>"$TMP/err"; }
# Com payload: TOK tokens em current_usage (TOK vazio = current_usage null) e o mesmo transcript.
render_com() { TP="${1:-}" TOK="${2:-}" node -e 'const t=process.env.TOK; process.stdout.write(JSON.stringify({transcript_path:process.env.TP||undefined,workspace:{current_dir:process.env.HOME},context_window:{current_usage:t?{input_tokens:+t}:null}}))' \
    | node "$SL" 2>>"$TMP/err"; }
sem_cor() { sed 's/\x1b\[[0-9;]*m//g'; }
tem() { printf '%s' "$1" | sem_cor | grep -qF -- "$2"; }
# Cor de um segmento: o código ANSI colado no texto ("ctx:160k"). A cor é o que a régua diz,
# e o sem_cor apaga exatamente isso — por isso se testa a saída crua.
ESC=$(printf '\033')
cor() { # <saída crua> <texto do segmento>
  case "$1" in
    *"${ESC}[31m$2"*) echo vermelho ;;
    *"${ESC}[38;5;208m$2"*) echo laranja ;;
    *"${ESC}[33m$2"*) echo amarelo ;;
    *"${ESC}[32m$2"*) echo verde ;;
    *) echo nenhuma ;;
  esac
}
DIR="$(basename "$HOME")"

echo "== com payload: só a ctx =="
tr u320000; out="$(render_com "$TMP/tr.jsonl" 310000)"
tem "$out" 'ses:' && falha "ses junto da ctx: $(printf '%s' "$out" | sem_cor)" || ok "310k no payload e 320k no transcript: sem ses"
[ "$(cor "$out" 'ctx:310k')" = vermelho ] && ok "…ctx vermelha" || falha "ctx 310k não saiu vermelha: $(cor "$out" 'ctx:310k')"
tem "$out" 'ctx:310k /compact' && ok "…e a ctx avisa /compact" || falha "ctx sem /compact: $(printf '%s' "$out" | sem_cor)"
tr u160000; out="$(render_com "$TMP/tr.jsonl" 160000)"
tem "$out" 'ses:' && falha "ses junto da ctx em 160k: $(printf '%s' "$out" | sem_cor)" || ok "160k no payload e no transcript: sem ses"
[ "$(cor "$out" 'ctx:160k')" = amarelo ] && ok "…ctx amarela" || falha "ctx 160k não saiu amarela: $(cor "$out" 'ctx:160k')"
tem "$out" '/compact' && falha "ctx 160k já manda /compact" || ok "…sem /compact em 160k"
out="$(render_com "$TMP/tr.jsonl" 50000)"
[ "$(cor "$out" 'ctx:50k')" = verde ] && ok "50k no payload: ctx verde" || falha "ctx 50k não saiu verde: $(cor "$out" 'ctx:50k')"
tr u320000; out="$(render_com "$TMP/tr.jsonl")"
tem "$out" 'ses:' && falha "context_window sem current_usage pintou a ses: $(printf '%s' "$out" | sem_cor)" || ok "context_window presente e current_usage null: sem ses"
out="$(render_com "$TMP/nao-existe.jsonl" 50000)"
tem "$out" 'ctx:50k' && ! tem "$out" 'ses:' && ok "payload sem transcript legível: só a ctx" || falha "com payload e sem transcript: $(printf '%s' "$out" | sem_cor)"

echo "== sem payload: a ses é o fallback, com a régua da ctx =="
tr p100 u100000; out="$(render "$TMP/tr.jsonl")"
tem "$out" 'ctx:' && falha "ctx sem payload: $(printf '%s' "$out" | sem_cor)" || ok "sem payload: sem ctx"
[ "$(cor "$out" 'ses:100k')" = verde ] && ok "100K: ses verde com os tokens" || falha "ses 100k não saiu verde: $(cor "$out" 'ses:100k')"
tr u160000; out="$(render "$TMP/tr.jsonl")"
[ "$(cor "$out" 'ses:160k')" = amarelo ] && ok "160K: ses amarela" || falha "ses 160k não saiu amarela: $(cor "$out" 'ses:160k')"
tem "$out" '/compact' && falha "ses 160k já manda /compact" || ok "…sem /compact"
tr u320000; out="$(render "$TMP/tr.jsonl")"
[ "$(cor "$out" 'ses:320k')" = vermelho ] && ok "320K: ses vermelha" || falha "ses 320k não saiu vermelha: $(cor "$out" 'ses:320k')"
tem "$out" 'ses:320k /compact' && ok "…com /compact" || falha "sem /compact em 320K: $(printf '%s' "$out" | sem_cor)"
tr u450000; out="$(render "$TMP/tr.jsonl")"
[ "$(cor "$out" 'ses:450k /compact')" = vermelho ] && ok "450K: vermelho com /compact, a mesma régua" || falha "450K fora da régua: $(printf '%s' "$out" | sem_cor)"
tem "$out" 'maratona' && falha "faixa própria de maratona na ses" || ok "…sem faixa própria de maratona"

tr u350000 p1300 c; s="$(render "$TMP/tr.jsonl")"
tem "$s" 'ses:' && falha "mandou /compact depois do compact: $(printf '%s' "$s" | sem_cor)" || ok "compact depois do último usage: sem ses, mesmo com 1.300 linhas"
tr u350000 c u60000; s="$(render "$TMP/tr.jsonl")"
tem "$s" 'ses:60k' && ! tem "$s" '350k' && ok "turno depois do compact: vale o 60K" || falha "valor de antes do compact: $(printf '%s' "$s" | sem_cor)"
tr a340000:170000; s="$(render "$TMP/tr.jsonl")"
tem "$s" 'ses:170k' && ok "advisor: vale a iteração message (170k), não a soma" || falha "advisor contou a soma: $(printf '%s' "$s" | sem_cor)"
tr u200000 s500000; s="$(render "$TMP/tr.jsonl")"
tem "$s" 'ses:200k' && ok "sidechain depois não entra" || falha "sidechain contou: $(printf '%s' "$s" | sem_cor)"
tr u320000 z; s="$(render "$TMP/tr.jsonl")"
tem "$s" 'ses:320k' && ok "usage zerado no fim: vale o anterior" || falha "usage zerado apagou a medida: $(printf '%s' "$s" | sem_cor)"

s="$(render "$TMP/nao-existe.jsonl")"
tem "$s" "$DIR" && ! tem "$s" 'ses:' && ok "transcript inexistente: barra normal, sem ses" || falha "quebrou sem transcript: $(printf '%s' "$s" | sem_cor)"
s="$(render)"
tem "$s" "$DIR" && ok "payload sem transcript_path: barra normal" || falha "quebrou sem o campo: $(printf '%s' "$s" | sem_cor)"

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
