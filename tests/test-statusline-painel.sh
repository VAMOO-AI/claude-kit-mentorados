#!/usr/bin/env bash
# O modo painel da statusline (até 7 linhas). O modo curto tem a suíte dele,
# tests/test-statusline-sessao.sh; as duas rodam o mesmo plugin/scripts/statusline.js.
#
# Uma linha só para o contexto. A `ctx` lê o payload do harness; a `ses` lê o
# transcript (input + cache_read + cache_creation do último usage, sem sidechain, iteração
# "message" do advisor, compact_boundary zera) e só aparece quando o payload não traz
# `context_window`. As duas usam a mesma régua: amarelo em 150k, vermelho com (/compact) em
# 300k. Antes as duas avisavam /compact juntas a partir de 300K. Também:
# a cor do ctx por tokens relidos (150k/300k, com a % da janela como teto), a tag de
# thinking só no desvio, o aviso de troca de modelo no meio da sessão e o ⚡t/s da última
# chamada (do `user` antes da primeira linha do id até a última, não do tool_result intercalado).
#
# E o que é só deste modo: qual modo vale (variável, arquivo, padrão) e o 👤 de quem está no
# teclado, que só aparece, e só carimba a sessão, com $CLAUDE_WHO, ~/.claude/whoami ou
# ~/.claude/.team-manifest.
#
# A barra é o que a pessoa olha o dia inteiro: quebrar o render é quebrar o feedback de
# custo, e o wrapper esconde erro (`|| printf '[statusline]'`). Aqui roda o .js direto — se
# ele lançar, o teste vê.
#
# O HOME é temporário: a barra grava marcadores por sessão em ~/.claude/.cache, e o teste
# não pode sujar os da máquina.
#
# Uso: bash tests/test-statusline-painel.sh [caminho-do-statusline.js]
set -uo pipefail
SL="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/scripts/statusline.js}"
[ -f "$SL" ] || { echo "statusline não encontrado: $SL"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node ausente"; exit 2; }

falhas=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
export CLAUDE_STATUSLINE_MODO=painel
unset CLAUDE_WHO
# com o whoami, o painel carimba a sessão; os casos sem ele estão no fim do arquivo
printf 'teste\n' > "$HOME/.claude/whoami"
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
tem()   { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
sem_cor() { sed 's/\x1b\[[0-9;]*m//g'; }

# Transcript sintético: cada argumento vira uma linha. uN = usage de N tokens (repartido em
# input/cache_read/cache_creation), aN:M = advisor (usage de cima N, iteração message M),
# sN = sidechain com N, z = usage zerado, c = compact_boundary, p = N linhas '{}' de enchimento.
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
# Sem payload de contexto: a `ses` é o fallback, lida do transcript.
render() { # <transcript_path>
  TP="$1" node -e 'process.stdout.write(JSON.stringify({session_id:"t",transcript_path:process.env.TP,model:{display_name:"Opus"},workspace:{current_dir:process.env.HOME}}))' \
    | node "$SL" 2>"$TMP/err"
}
# Com payload: TOK tokens numa janela de 1M, e o mesmo transcript.
render_com() { # <transcript_path> <tokens>
  TP="$1" TOK="$2" node -e 'const t=+process.env.TOK; process.stdout.write(JSON.stringify({session_id:"t",transcript_path:process.env.TP,model:{display_name:"Opus"},workspace:{current_dir:process.env.HOME},context_window:{context_window_size:1000000,total_input_tokens:t,used_percentage:Math.floor(t*100/1000000)}}))' \
    | node "$SL" 2>>"$TMP/err"
}
linha() { printf '%s\n' "$2" | sem_cor | grep -E "^$1 " || true; }

# Cor de um segmento: o código ANSI colado no número ("160k/16%", "160k tok"). Não basta achar
# uma cor na linha — a barra, o número e o recado usam a mesma, e é ela que se testa.
ESC=$(printf '\033')
VERDE="${ESC}[32m"; AMARELO="${ESC}[33m"; LARANJA="${ESC}[38;5;208m"; VERMELHO="${ESC}[1m${ESC}[91m"
cor_ctx() { # <saída crua> <texto do segmento>
  case "$1" in
    *"$VERMELHO$2"*) echo vermelho ;;
    *"$LARANJA$2"*)  echo laranja ;;
    *"$AMARELO$2"*)  echo amarelo ;;
    *"$VERDE$2"*)    echo verde ;;
    *)               echo nenhuma ;;
  esac
}

echo "== com payload: só a ctx =="
tr u320000; out="$(render_com "$TMP/tr.jsonl" 310000)"
[ -z "$(linha ses "$out")" ] && ok "310k no payload e 320k no transcript: sem linha ses" || falha "ses junto da ctx: $(linha ses "$out")"
tem "$(linha ctx "$out")" "(/compact)" && ok "…e a ctx avisa (/compact)" || falha "ctx sem (/compact): $(linha ctx "$out")"
tr u160000; out="$(render_com "$TMP/tr.jsonl" 160000)"
[ -z "$(linha ses "$out")" ] && ok "160k no payload e no transcript: sem linha ses" || falha "ses junto da ctx em 160k: $(linha ses "$out")"
[ "$(cor_ctx "$out" "160k/16%")" = amarelo ] && ok "…e a ctx sai amarela" || falha "ctx 160k não saiu amarela: $(cor_ctx "$out" "160k/16%")"
tem "$(linha ctx "$out")" "/compact" && falha "ctx 160k já manda /compact" || ok "…sem /compact em 160k"
out="$(render_com "$TMP/nao-existe.jsonl" 50000)"
[ -n "$(linha ctx "$out")" ] && [ -z "$(linha ses "$out")" ] && ok "payload sem transcript legível: só a ctx" || falha "com payload e sem transcript: $(printf '%s' "$out" | sem_cor | tail -2)"

echo "== sem payload: a ses é o fallback, com a régua da ctx =="
tr p100 u100000; out="$(render "$TMP/tr.jsonl")"
[ -z "$(linha ctx "$out")" ] && ok "sem payload: sem linha ctx" || falha "ctx sem payload: $(linha ctx "$out")"
tem "$(linha ses "$out")" "100k" && ok "100K: ses aparece com os tokens" || falha "sem ses em 100K: $(linha ses "$out")"
[ "$(cor_ctx "$out" "100k tok")" = verde ] && ok "…verde" || falha "ses 100k não saiu verde: $(cor_ctx "$out" "100k tok")"
[ -f "$HOME/.claude/.cache/session-owner/t" ] && ok "marcador da sessão vai para o HOME do teste" || falha "session-owner/t fora do HOME temporário"

tr u160000; out="$(render "$TMP/tr.jsonl")"
[ "$(cor_ctx "$out" "160k tok")" = amarelo ] && ok "160K: ses amarela" || falha "ses 160k não saiu amarela: $(cor_ctx "$out" "160k tok")"
tem "$(linha ses "$out")" "/compact" && falha "ses 160k já manda /compact" || ok "…sem /compact"

tr u320000; out="$(render "$TMP/tr.jsonl")"
[ "$(cor_ctx "$out" "320k tok")" = vermelho ] && ok "320K: ses vermelha" || falha "ses 320k não saiu vermelha: $(cor_ctx "$out" "320k tok")"
tem "$(linha ses "$out")" "(/compact)" && ok "…com o recado (/compact)" || falha "sem /compact em 320K: $(linha ses "$out")"

tr u450000; s="$(linha ses "$(render "$TMP/tr.jsonl")")"
tem "$s" "(/compact)" && ok "450K: (/compact), a mesma régua" || falha "sem /compact em 450K: $s"
tem "$s" "maratona" && falha "faixa própria de maratona na ses: $s" || ok "…sem faixa própria de maratona"

tr u350000 p1300 c; s="$(linha ses "$(render "$TMP/tr.jsonl")")"
[ -z "$s" ] && ok "compact depois do último usage: sem linha, mesmo com 1.300 linhas" || falha "mandou /compact depois do compact: $s"

tr u350000 c u60000; s="$(linha ses "$(render "$TMP/tr.jsonl")")"
tem "$s" "60k" && ! tem "$s" "350k" && ok "turno depois do compact: vale o 60K" || falha "valor de antes do compact: $s"

tr a340000:170000; s="$(linha ses "$(render "$TMP/tr.jsonl")")"
tem "$s" "170k" && ok "advisor: vale a iteração message (170k), não a soma" || falha "advisor contou a soma: $s"

tr u200000 s500000; s="$(linha ses "$(render "$TMP/tr.jsonl")")"
tem "$s" "200k" && ok "sidechain depois não entra" || falha "sidechain contou: $s"

tr u320000 z; s="$(linha ses "$(render "$TMP/tr.jsonl")")"
tem "$s" "320k" && ok "usage zerado no fim: vale o anterior" || falha "usage zerado apagou a medida: $s"

# Transcript inexistente e payload sem transcript: a barra não pode quebrar por isso.
s="$(render "$TMP/nao-existe.jsonl")"
[ -n "$s" ] && [ -z "$(linha ses "$s")" ] && ok "transcript inexistente: render normal, sem linha" || falha "quebrou sem transcript"
out="$(node -e 'process.stdout.write(JSON.stringify({session_id:"t",model:{display_name:"Opus"},workspace:{current_dir:process.env.HOME}}))' | node "$SL" 2>>"$TMP/err")"
[ -n "$out" ] && ok "payload sem transcript_path: render normal" || falha "quebrou sem transcript_path"

# Daqui em diante o payload vem de variáveis: SID, MODELO, THINK (true|false), TOK, JAN.
mkdir -p "$HOME/proj"
barra() {
  node -e '
    const e = process.env, jan = +e.JAN || 1000000, tok = +e.TOK || 0;
    const d = {
      session_id: e.SID || "s",
      model: {id: e.MODELO || "claude-opus-5-5[1m]", display_name: "Opus"},
      workspace: {current_dir: e.HOME + "/proj"},
      context_window: {context_window_size: jan, total_input_tokens: tok, used_percentage: Math.floor(tok * 100 / jan)},
    };
    if (e.THINK) d.thinking = {enabled: e.THINK === "true"};
    process.stdout.write(JSON.stringify(d));' | node "$SL" 2>>"$TMP/err"
}

confere_cor() { # <tokens> <janela> <texto do segmento> <cor esperada> <descrição>
  local out c; out="$(TOK="$1" JAN="$2" barra)"; c="$(cor_ctx "$out" "$3")"
  [ "$c" = "$4" ] && ok "$5" || falha "$5 — saiu $c"
}

confere_cor 100000 1000000 "100k/10%" verde    "ctx 100k em 1M: verde"
confere_cor 160000 1000000 "160k/16%" amarelo  "ctx 160k em 1M: amarelo (pela % seria verde)"
confere_cor 310000 1000000 "310k/31%" vermelho "ctx 310k em 1M: vermelho (pela % seria verde)"
s="$(TOK=310000 JAN=1000000 barra | sem_cor)"
tem "$s" "(/compact)" && ok "…com o recado (/compact)" || falha "ctx 310k em 1M sem o recado (/compact)"
# Janela de 200k (Haiku): 300k nem cabe. Só o limiar absoluto pintaria 170k de amarelo com
# o auto-compact na porta; a % segue de teto, e o que acender primeiro vale.
confere_cor 120000 200000 "120k/60%" amarelo   "ctx 120k em 200k (60%): amarelo pela %"
confere_cor 145000 200000 "145k/72%" laranja   "ctx 145k em 200k (72%): laranja, auto-compact perto"
confere_cor 170000 200000 "170k/85%" vermelho  "ctx 170k em 200k (85%): vermelho antes dos 300k"

# Thinking: o campo é o toggle, e no Opus 5.5 e no Fable 5 o thinking não desliga. Só o
# desvio aparece — toggle desligado num modelo que obedece.
s="$(MODELO='claude-opus-5-5[1m]' THINK=true barra | sem_cor)"
tem "$s" thinking && falha "opus-5-5 com toggle ligado: tag acesa sem informar nada" || ok "opus-5-5, toggle ligado: nenhuma tag"
s="$(MODELO=claude-opus-5-5 THINK=false barra | sem_cor)"
tem "$s" thinking && falha "opus-5-5 com toggle desligado: tag de algo que não acontece" || ok "opus-5-5, toggle desligado: nenhuma tag"
s="$(MODELO=claude-fable-5-1 THINK=false barra | sem_cor)"
tem "$s" thinking && falha "fable-5-1 com toggle desligado: tag de algo que não acontece" || ok "fable-5-1, toggle desligado: nenhuma tag"
s="$(MODELO=claude-opus-4-8 THINK=false barra | sem_cor)"
tem "$s" sem-thinking && ok "opus-4-8, toggle desligado: sem-thinking" || falha "opus-4-8 com thinking desligado e nenhuma tag"
s="$(MODELO=claude-sonnet-5 THINK=true barra | sem_cor)"
tem "$s" thinking && falha "sonnet-5 com toggle ligado: tag no caso normal" || ok "sonnet-5, toggle ligado: nenhuma tag"

# Troca de modelo no meio da sessão: switchModelsOnFlag leva ao claude-opus-4-8 quando os
# safeguards sinalizam; /model também troca. A barra guarda o primeiro model.id da sessão.
SID=troca MODELO='claude-opus-5-5[1m]' barra >/dev/null
s="$(SID=troca MODELO=claude-opus-4-8 barra | sem_cor)"
tem "$s" "⚠ modelo trocou:" && ok "mesma sessão, dois modelos: ⚠ modelo trocou" || falha "troca de modelo sem tag: $(printf '%s' "$s" | head -2)"
tem "$s" "opus-5-5→opus-4-8" && ok "…com de onde veio e para onde foi" || falha "a tag não diz a troca (opus-5-5→opus-4-8)"
[ -f "$HOME/.claude/.cache/session-model/troca" ] && ok "…e o primeiro modelo fica no HOME do teste" || falha "sem marcador em .cache/session-model/troca"
SID=fica barra >/dev/null
s="$(SID=fica barra | sem_cor)"
tem "$s" "modelo trocou" && falha "mesmo modelo e a tag acendeu" || ok "mesma sessão, mesmo modelo: sem tag"
s="$(SID=nova MODELO=claude-opus-4-8 barra | sem_cor)"
tem "$s" "modelo trocou" && falha "sessão que já nasce no opus-4-8 acusou troca" || ok "sessão que nasce no opus-4-8: sem tag"
SID=janela MODELO='claude-opus-5-5[1m]' barra >/dev/null
s="$(SID=janela MODELO=claude-opus-5-5 barra | sem_cor)"
tem "$s" "modelo trocou" && falha "só a janela mudou ([1m]) e a tag acendeu" || ok "só o [1m] mudou: sem tag"

# ⚡t/s da última chamada. Transcript sintético: $1 = arquivo, $2 = idade da resposta em
# segundos, $3 = cenário.
fixture() { IDADE="$2" CEN="$3" node -e '
const t0 = Date.now() - Number(process.env.IDADE) * 1000;
const ts = (s) => new Date(t0 + s * 1000).toISOString();
const L = [];
const u = (s, extra) => L.push({ type: "user", timestamp: ts(s), message: { content: [{ type: "tool_result" }] }, ...extra });
const a = (s, id, out, extra) => L.push({ type: "assistant", timestamp: ts(s), message: { id, usage: { output_tokens: out } }, ...extra });
if (process.env.CEN === "tps") {
  // resposta anterior, que não pode contar
  u(-60); a(-58, "msg_velha", 9999);
  // última chamada: começa em -10s, 3 linhas do mesmo id com tool_result intercalado,
  // termina em 0s. 500 tokens / 10s = 50 t/s. Medir a partir do tool_result intercalado
  // daria 85 t/s; parar na primeira linha do id, 250.
  u(-10); a(-8, "msg_ultima", 500); a(-6, "msg_ultima", 500); u(-5.9); a(0, "msg_ultima", 500);
  // subagente (sidechain) depois: não entra na conta
  u(1, { isSidechain: true }); a(2, "msg_sub", 50000, { isSidechain: true });
} else {
  u(-10); L.push({ type: "system", timestamp: ts(-5) });
}
process.stdout.write(L.map((x) => JSON.stringify(x)).join("\n") + "\n");' > "$1"; }
render_tps() { # <transcript_path>
  TP="$1" node -e 'process.stdout.write(JSON.stringify({session_id:"tps",transcript_path:process.env.TP,model:{display_name:"Opus"},workspace:{current_dir:process.env.HOME},context_window:{used_percentage:10,context_window_size:200000,current_usage:{input_tokens:1000}}}))' \
    | node "$SL" 2>>"$TMP/err" | sem_cor
}

fixture "$TMP/tps.jsonl" 5 tps; s="$(render_tps "$TMP/tps.jsonl")"
tem "$s" "⚡50 t/s" && ok "t/s da última chamada: 500 tokens em 10s = ⚡50 t/s" || falha "t/s errado ou ausente: $(printf '%s' "$s" | grep -o '⚡[0-9]* t/s' || echo nada)"
fixture "$TMP/velho.jsonl" 600 tps; s="$(render_tps "$TMP/velho.jsonl")"
tem "$s" "⚡" && falha "resposta de 10 min atrás ainda pinta t/s" || ok "resposta parada há >5 min: sem t/s"
fixture "$TMP/sem.jsonl" 5 sem-assistant; s="$(render_tps "$TMP/sem.jsonl")"
tem "$s" "⚡" && falha "t/s sem resposta no transcript" || ok "transcript sem resposta: sem t/s"
[ -n "$s" ] && ok "transcript sem resposta: render normal" || falha "quebrou sem resposta"

echo "== qual modo vale =="
# render_modo <valor da variável ou ""> : saída sem cor de um payload com context_window
render_modo() {
  node -e 'process.stdout.write(JSON.stringify({session_id:"m",model:{display_name:"Opus"},workspace:{current_dir:process.env.HOME},context_window:{context_window_size:200000,current_usage:{input_tokens:50000}}}))' \
    | CLAUDE_STATUSLINE_MODO="$1" node "$SL" 2>>"$TMP/err" | sem_cor
}
MF="$HOME/.claude/statusline-modo"
rm -f "$MF"
s="$(render_modo "")"; tem "$s" "Input:" && ok "sem variável nem arquivo: painel" || falha "sem configuração não saiu o painel: $s"
printf 'curto\n' > "$MF"
s="$(render_modo "")"; tem "$s" "ctx:50k" && ! tem "$s" "Input:" && ok "arquivo diz curto: uma linha" || falha "arquivo curto não valeu: $s"
s="$(render_modo painel)"; tem "$s" "Input:" && ok "a variável ganha do arquivo" || falha "variável painel não ganhou do arquivo: $s"
printf 'enorme\n' > "$MF"
s="$(render_modo "")"; tem "$s" "Input:" && ok "valor desconhecido no arquivo: painel" || falha "valor desconhecido quebrou: $s"
rm -f "$MF"

echo "== 👤 e carimbo só em harness de mais de uma pessoa =="
# render_quem <sid> : saída sem cor, sem forçar o CLAUDE_WHO
render_quem() {
  SID="$1" node -e 'process.stdout.write(JSON.stringify({session_id:process.env.SID,model:{display_name:"Opus"},workspace:{current_dir:process.env.HOME}}))' \
    | node "$SL" 2>>"$TMP/err" | sem_cor
}
rm -f "$HOME/.claude/whoami" "$HOME/.claude/session-owners.jsonl"
s="$(render_quem solo)"
tem "$s" "👤" && falha "máquina de uma pessoa só pintou 👤: $(printf '%s' "$s" | head -1)" || ok "sem whoami, CLAUDE_WHO nem .team-manifest: sem 👤"
[ -e "$HOME/.claude/session-owners.jsonl" ] && falha "carimbou a sessão sem identidade" || ok "…e nada em session-owners.jsonl"
[ -e "$HOME/.claude/.cache/session-owner/solo" ] && falha "marcador de dono sem identidade" || ok "…nem marcador de dono"
: > "$HOME/.claude/.team-manifest"
s="$(render_quem time)"
H="$(node -e 'console.log(require("os").hostname().replace(/\.local$/i,"").split(".")[0].slice(0,13))')"
tem "$s" "👤$H" && ok "com .team-manifest e sem whoami: 👤 do hostname" || falha "com .team-manifest sem o hostname: $(printf '%s' "$s" | head -1)"
grep -q '"session":"time"' "$HOME/.claude/session-owners.jsonl" 2>/dev/null && ok "…e carimba a sessão" || falha "com .team-manifest não carimbou"
rm -f "$HOME/.claude/.team-manifest"
s="$(SID=quem; export SID; node -e 'process.stdout.write(JSON.stringify({session_id:"quem",model:{display_name:"Opus"},workspace:{current_dir:process.env.HOME}}))' | CLAUDE_WHO=fulana node "$SL" 2>>"$TMP/err" | sem_cor)"
tem "$s" "👤fulana" && ok "CLAUDE_WHO: 👤 de quem está no terminal" || falha "CLAUDE_WHO não apareceu: $(printf '%s' "$s" | head -1)"
s="$(node -e 'process.stdout.write(JSON.stringify({session_id:"../../fora",model:{display_name:"Opus"},workspace:{current_dir:process.env.HOME}}))' | CLAUDE_WHO=fulana node "$SL" 2>>"$TMP/err")"
[ -n "$s" ] && ok "session_id com ../: render normal" || falha "session_id com ../ quebrou o render"
[ -e "$TMP/fora" ] || [ -e "$HOME/fora" ] && falha "session_id com ../ virou caminho" || ok "…e não vira caminho"

[ -s "$TMP/err" ] && falha "o .js escreveu em stderr: $(head -3 "$TMP/err")" || ok "nenhum erro em stderr"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
