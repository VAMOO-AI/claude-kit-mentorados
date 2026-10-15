#!/usr/bin/env bash
# O simular-conversa.mjs da n8n-workflow-agent reprova o agente quando deve, e só quando deve?
#
# Um servidor falso faz os dois lados: o n8n (webhook que grava, debounce que só deixa a
# última mensagem da rajada chegar no nó de resposta, /api/v1/executions com runData) e a
# API do Claude (simulador de lead e juiz, reconhecidos pelo system prompt). O modo do agente
# falso vem de $TMP/modo e o do juiz de $TMP/juiz, relidos a cada request. Cada execução do
# telefone certo vem acompanhada de uma de outro lead, com resposta, no mesmo instante.
# Os casos a partir de "resposta que o runner não viu" saíram do review do PR: todos falham no
# primeiro commit do script.
#
# Uso: bash tests/test-simular-conversa.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SIM="$RAIZ/plugin/skills/n8n-workflow-agent/scripts/simular-conversa.mjs"

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/simular-conversa.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'kill "$SRV" 2>/dev/null; rm -rf "$TMP"' EXIT

cat > "$TMP/falso.mjs" <<'JS'
import http from "node:http";
import fs from "node:fs";
const dir = process.argv[2];
const ler = (f, d) => { try { return fs.readFileSync(`${dir}/${f}`, "utf8").trim(); } catch { return d; } };
const execs = [];
const ultimo = new Map();
let seq = 0;

function respostaDoAgente(historico, turno) {
  const modo = ler("modo", "ok");
  if (modo === "mudo") return null;
  if (historico.some((m) => /\bpara de\b/i.test(m))) return modo.startsWith("ignora-optout") ? ["Tudo bem! Mas antes, temos condição especial"] : null;
  if (turno === 1) return ["Olá! Seja bem-vindo à Imobiliária Teste", "Como posso ajudar?"];
  if (modo === "numero-inventado") return ["Esse apê valoriza 30% ao ano, garantido"];
  if (modo === "numeros-br") return ["Posso te mostrar às 14h do dia 28/09? O valor é R$ 450.000,00"];
  if (modo === "percentual") return ["E rende 2% ao mês de aluguel"];
  if (modo === "ressauda" && turno >= 3) return ["Olá! Seja bem-vindo à Imobiliária Teste"];
  return ["Anotado. O valor é R$ 450 mil, quer agendar visita?"];
}

const srv = http.createServer((req, res) => {
  let corpo = "";
  req.on("data", (c) => (corpo += c));
  req.on("end", () => {
    const url = new URL(req.url, "http://x");
    const json = (code, obj) => { res.writeHead(code, { "content-type": "application/json" }); res.end(JSON.stringify(obj)); };

    if (url.pathname === "/webhook/agente") {
      const body = JSON.parse(corpo);
      if (url.searchParams.get("token") !== "segredo") return json(401, { erro: "token" });
      const tel = body.message.chatid;
      const texto = body.message.text;
      fs.appendFileSync(`${dir}/injetados`, `${tel}\t${texto}\n`);
      const hist = (ultimo.get(tel)?.hist || []).concat(texto);
      const eu = ++seq;
      ultimo.set(tel, { eu, hist, turno: ultimo.get(tel)?.turno || 0 });
      const inicio = new Date().toISOString();
      const lento = ler("modo", "") === "ignora-optout-lento" && hist.some((m) => /\bpara de\b/i.test(m));
      setTimeout(() => {
        const venceu = ultimo.get(tel).eu === eu;
        const runData = { Webhook: [{ data: { main: [[{ json: { body } }]] } }] };
        const u = ultimo.get(tel);
        if (venceu) u.turno++;
        const quebrado = venceu && ler("modo", "") === "quebrado";
        const resp = venceu && !quebrado ? respostaDoAgente(u.hist, u.turno) : null;
        if (resp) runData["Validar JSON resposta"] = [{ data: { main: [[{ json: { mensagens: resp } }]] } }];
        const resultData = quebrado ? { runData, lastNodeExecuted: "AI Agent", error: { message: "credencial OpenAI inválida" } } : { runData };
        // o debounce decide aos 400ms; no modo lento o agente leva mais 3,6s para terminar
        setTimeout(() => execs.push({ id: String(eu), workflowId: "wf1", startedAt: inicio, stoppedAt: new Date().toISOString(),
          status: resp || quebrado ? "error" : "success", data: { resultData } }), lento && venceu ? 3600 : 0);
        // execução de outro telefone chegando no meio, com resposta — não pode vazar para o cenário
        execs.push({ id: `x${eu}`, workflowId: "wf1", startedAt: inicio, stoppedAt: new Date().toISOString(), status: "error",
          data: { resultData: { runData: { Webhook: [{ data: { main: [[{ json: { body: { message: { chatid: "5500999999999" } } } }]] } }],
            "Validar JSON resposta": [{ data: { main: [[{ json: { mensagens: ["RESPOSTA DE OUTRO LEAD"] } }]] } }] } } } });
      }, 400);
      return json(200, { ok: true });
    }

    if (url.pathname.startsWith("/api/v1/executions")) {
      if (req.headers["x-n8n-api-key"] !== "chave-n8n") return json(401, { message: "unauthorized" });
      fs.appendFileSync(`${dir}/polls`, `${url.pathname}?${url.searchParams}\n`);
      const comDados = (e) => (url.searchParams.get("includeData") === "true" ? e : { ...e, data: undefined });
      const id = url.pathname.split("/")[4];
      if (id) { const e = execs.find((x) => x.id === id); return e ? json(200, comDados(e)) : json(404, {}); }
      const data = execs.filter((e) => e.workflowId === url.searchParams.get("workflowId")).slice().reverse().map(comDados);
      return json(200, { data, nextCursor: null });
    }

    if (url.pathname === "/v1/messages") {
      if (req.headers["x-api-key"] !== "chave-claude") return json(401, { type: "error" });
      const r = JSON.parse(corpo);
      fs.appendFileSync(`${dir}/llm`, JSON.stringify({ model: r.model, beta: req.headers["anthropic-beta"] || "", fallbacks: r.fallbacks ?? null, effort: r.output_config?.effort, temp: "temperature" in r }) + "\n");
      const texto = (t) => json(200, { model: r.model, stop_reason: "end_turn", content: [{ type: "thinking", thinking: "" }, { type: "text", text: t }] });
      if (r.system.includes("JUIZ")) {
        const modo = ler("juiz", "aprova");
        if (modo === "recusa") return json(200, { model: r.model, stop_reason: "refusal", content: [] });
        if (modo === "invalido") return texto('{"criterios": []}');
        const n = (r.messages[0].content.match(/^\d+\. /gm) || []).length;
        const vs = Array.from({ length: n }, (_, i) => ({ indice: i + 1, criterio: `c${i + 1}`, passou: modo === "aprova" || (modo === "reordena" && i !== 1), motivo: "falso" }));
        return texto(JSON.stringify({ criterios: modo === "reordena" ? vs.reverse() : vs }));
      }
      const turno = r.messages.filter((m) => m.role === "assistant").length + 1;
      return texto(JSON.stringify({ mensagens: turno === 1 ? ["oi", "vi o anúncio do apê"] : [`pergunta ${turno}`], fim: ler("lead", "") === "fim" }));
    }
    json(404, {});
  });
});
srv.listen(0, "127.0.0.1", () => fs.writeFileSync(`${dir}/porta`, String(srv.address().port)));
JS

# runner frio do CI já levou mais de 5s para o node subir: espera até 30s, sai assim que a porta aparece
node "$TMP/falso.mjs" "$TMP" 2> "$TMP/falso.err" & SRV=$!; disown
for _ in $(seq 300); do [ -s "$TMP/porta" ] || ! kill -0 "$SRV" 2>/dev/null && break; sleep 0.1; done
PORTA="$(cat "$TMP/porta" 2>/dev/null)"
if [ -z "$PORTA" ]; then
  if kill -0 "$SRV" 2>/dev/null; then echo "servidor falso não subiu em 30s"
  else echo "servidor falso morreu antes de subir; stderr do node:"; cat "$TMP/falso.err"; fi
  exit 2
fi

export TMP N8N_API_KEY=chave-n8n ANTHROPIC_API_KEY=chave-claude ANTHROPIC_BASE_URL="http://127.0.0.1:$PORTA" TOKEN_WEBHOOK=segredo
mkdir -p "$TMP/qa/cenarios"
cat > "$TMP/qa/payload.json" <<'J'
{ "EventType": "messages", "message": { "chatid": "{{telefone}}", "text": "{{texto}}", "messageid": "{{message_id}}", "senderName": "{{nome}}", "messageTimestamp": "{{agora_ms}}" } }
J
cat > "$TMP/qa/negocio.json" <<'J'
{ "alegacoes_verificadas": ["Apartamento de 2 quartos por R$ 450 mil"] }
J
cat > "$TMP/qa/agente.json" <<J
{
  "n8n_url": "http://127.0.0.1:$PORTA",
  "webhook_url": "http://127.0.0.1:$PORTA/webhook/agente?token={{env:TOKEN_WEBHOOK}}",
  "workflow_id": "wf1",
  "payload": "payload.json",
  "no_resposta": "Validar JSON resposta",
  "campo_resposta": "mensagens",
  "telefone_prefixo": "5500",
  "timeout_turno_s": 3,
  "quieto_s": 0.6,
  "pausa_entre_turnos_s": 0,
  "intervalo_rajada_ms": 100,
  "intervalo_poll_s": 0.2,
  "limpeza": ["echo {{telefone}} >> $TMP/limpos"]
}
J
cenario() { # cenario <arquivo> <json do corpo sem chaves externas>
  printf '{ "agente": "../agente.json", "persona": "Lead de imóvel", %s }\n' "$2" > "$TMP/qa/cenarios/$1.json"
}
roda() { node "$SIM" "$@" --saida "$TMP/saida" > "$TMP/out" 2>&1; echo $?; }

cenario feliz '"nome": "feliz", "turnos": 3, "criterios": ["não inventa preço"],
  "checagens": [
    { "tipo": "proibido", "regex": "bem-vindo", "flags": "i", "a_partir_do_turno": 2 },
    { "tipo": "numeros_permitidos", "arquivo": "../negocio.json", "chave": "alegacoes_verificadas" },
    { "tipo": "comando", "cmd": "grep -c {{telefone}} {{env:TMP}}/injetados", "espera": "4" }
  ]'
cenario ressauda '"nome": "ressauda", "turnos": 3, "criterios": ["x"],
  "checagens": [ { "tipo": "proibido", "regex": "bem-vindo", "flags": "i", "a_partir_do_turno": 2 } ]'
cenario numero '"nome": "numero", "turnos": 2, "criterios": ["x"],
  "checagens": [ { "tipo": "numeros_permitidos", "arquivo": "../negocio.json", "chave": "alegacoes_verificadas" } ]'
cenario optout '"nome": "optout", "roteiro": [null, "para de me mandar mensagem", "oi?"], "criterios": ["x"],
  "checagens": [ { "tipo": "silencio_apos", "turno": 2 } ]'
cenario telreal '"nome": "telreal", "turnos": 1, "criterios": ["x"]'
sed 's/"telefone_prefixo": "5500"/"telefone_prefixo": "5511"/' "$TMP/qa/agente.json" > "$TMP/qa/agente-real.json"
sed -i.bak 's#../agente.json#../agente-real.json#' "$TMP/qa/cenarios/telreal.json"

echo "caminho feliz"
echo ok > "$TMP/modo"; echo aprova > "$TMP/juiz"
check "agente correto passa (exit 0)" "$([ "$(roda "$TMP/qa/cenarios/feliz.json")" = 0 ] && echo ok || echo fail)"
check "rajada do lead vira duas injeções e um turno" "$(grep -q 'vi o anúncio' "$TMP/injetados" && grep -c 'oi$' "$TMP/injetados" | grep -q 1 && echo ok || echo fail)"
check "resposta de outro telefone não entra no transcript" "$(grep -rq 'RESPOSTA DE OUTRO LEAD' "$TMP/saida" && echo fail || echo ok)"
check "limpeza rodou com o telefone do cenário" "$(grep -q '^5500' "$TMP/limpos" && echo ok || echo fail)"
check "sem --saida o relatório vai para qa/resultados" "$(node "$SIM" "$TMP/qa/cenarios/numero.json" >/dev/null 2>&1; ls "$TMP"/qa/resultados/numero-*.json >/dev/null 2>&1 && echo ok || echo fail)"
check "relatório JSON gravado com veredito" "$(ls "$TMP"/saida/feliz-*.json >/dev/null 2>&1 && grep -q '"passou": true' "$TMP"/saida/feliz-*.json && echo ok || echo fail)"
check "juiz em claude-opus-5 com fallbacks default e beta" "$(grep -q '"model":"claude-opus-5","beta":"server-side-fallback-2026-07-01","fallbacks":"default"' "$TMP/llm" && echo ok || echo fail)"
check "sem temperature (400 no Opus 5)" "$(grep -q '"temp":true' "$TMP/llm" && echo fail || echo ok)"

echo "reprova o que deve"
echo ressauda > "$TMP/modo"
check "re-saudação no turno 3 reprova (exit 1)" "$([ "$(roda "$TMP/qa/cenarios/ressauda.json")" = 1 ] && echo ok || echo fail)"
check "motivo cita o turno" "$(grep -q 'turno 3' "$TMP/out" && echo ok || echo fail)"
echo numero-inventado > "$TMP/modo"
check "número fora da lista reprova (exit 1)" "$([ "$(roda "$TMP/qa/cenarios/numero.json")" = 1 ] && echo ok || echo fail)"
check "motivo cita o 30" "$(grep -q '30' "$TMP/out" && echo ok || echo fail)"
echo ok > "$TMP/modo"
check "450 da lista não reprova" "$([ "$(roda "$TMP/qa/cenarios/numero.json")" = 0 ] && echo ok || echo fail)"
echo reprova > "$TMP/juiz"
check "juiz reprovando reprova (exit 1)" "$([ "$(roda "$TMP/qa/cenarios/feliz.json")" = 1 ] && echo ok || echo fail)"

echo "opt-out"
echo ok > "$TMP/modo"; echo aprova > "$TMP/juiz"
check "agente calado depois do 'para' passa" "$([ "$(roda "$TMP/qa/cenarios/optout.json")" = 0 ] && echo ok || echo fail)"
check "roteiro fixo foi injetado" "$(grep -q 'para de me mandar mensagem' "$TMP/injetados" && echo ok || echo fail)"
echo ignora-optout > "$TMP/modo"
check "agente que responde depois do 'para' reprova" "$([ "$(roda "$TMP/qa/cenarios/optout.json")" = 1 ] && echo ok || echo fail)"

echo ignora-optout-lento > "$TMP/modo"
check "resposta lenta ao 'para' (chega no turno seguinte) conta no turno dela e reprova" "$([ "$(roda "$TMP/qa/cenarios/optout.json")" = 1 ] && grep -q 'turno 2' "$TMP/out" && echo ok || echo fail)"

echo ok > "$TMP/modo"; echo fim > "$TMP/lead"; : > "$TMP/injetados"
check "lead que se despede (fim:true) não pula a fala fixa do roteiro" "$(roda "$TMP/qa/cenarios/optout.json" >/dev/null; grep -q 'para de me mandar mensagem' "$TMP/injetados" && echo ok || echo fail)"
rm -f "$TMP/lead"

echo "resposta que o runner não viu não pode passar por silêncio"
echo mudo > "$TMP/modo"
check "agente mudo o tempo todo → exit 2, não opt-out aprovado" "$([ "$(roda "$TMP/qa/cenarios/optout.json")" = 2 ] && echo ok || echo fail)"
echo quebrado > "$TMP/modo"
check "agente que quebra antes do nó de resposta → exit 2 com o nó e o erro" "$([ "$(roda "$TMP/qa/cenarios/optout.json")" = 2 ] && grep -q 'AI Agent' "$TMP/out" && grep -q 'credencial OpenAI' "$TMP/out" && echo ok || echo fail)"
cenario optout1 '"nome": "optout1", "roteiro": ["para de me mandar mensagem", "oi?"], "criterios": ["x"],
  "checagens": [ { "tipo": "silencio_apos", "turno": 1 } ]'
echo ok > "$TMP/modo"
check "gatilho no turno 1 (nenhuma resposta antes) é recusado como config (exit 2)" "$([ "$(roda "$TMP/qa/cenarios/optout1.json")" = 2 ] && echo ok || echo fail)"

echo "números em formato BR"
echo numeros-br > "$TMP/modo"
check "R$ 450.000,00 bate com '450 mil'; 14h e 28/09 não contam" "$([ "$(roda "$TMP/qa/cenarios/numero.json")" = 0 ] && echo ok || echo fail)"
echo percentual > "$TMP/modo"
check "2% não é liberado pelo '2 quartos' da lista" "$([ "$(roda "$TMP/qa/cenarios/numero.json")" = 1 ] && grep -q '2%' "$TMP/out" && echo ok || echo fail)"

echo "juiz"
echo ok > "$TMP/modo"; echo reordena > "$TMP/juiz"
cenario dois '"nome": "dois", "turnos": 1, "criterios": ["primeiro critério", "segundo critério"]'
check "veredito vai para o critério pelo índice, não pela posição" "$([ "$(roda "$TMP/qa/cenarios/dois.json")" = 1 ] && grep -q 'FALHA juiz: segundo critério' "$TMP/out" && grep -q 'ok    juiz: primeiro critério' "$TMP/out" && echo ok || echo fail)"
echo aprova > "$TMP/juiz"

echo "config errada sai 2 antes de injetar"
cenario tipo '"nome": "tipo", "turnos": 1, "criterios": ["x"], "checagens": [ { "tipo": "xpto" } ]'
cenario gatilho '"nome": "gatilho", "roteiro": [null, "para de me mandar mensagem"], "criterios": ["x"], "checagens": [ { "tipo": "silencio_apos", "turno": 1 } ]'
cenario regex '"nome": "regex", "turnos": 1, "criterios": ["x"], "checagens": [ { "tipo": "proibido", "regex": "(" } ]'
for c in tipo gatilho regex; do
  check "cenário '$c' inválido → exit 2 sem injetar" "$(n=$(wc -l < "$TMP/injetados"); r=$(roda "$TMP/qa/cenarios/$c.json"); [ "$r" = 2 ] && [ "$(wc -l < "$TMP/injetados")" = "$n" ] && echo ok || echo fail)"
done
check "sem N8N_API_KEY → exit 2 sem injetar" "$(n=$(wc -l < "$TMP/injetados"); r=$(N8N_API_KEY= roda "$TMP/qa/cenarios/numero.json"); [ "$r" = 2 ] && [ "$(wc -l < "$TMP/injetados")" = "$n" ] && echo ok || echo fail)"

echo "polling"
check "lista de execuções sem includeData; detalhe só por id" "$(if grep -q '^/api/v1/executions?.*includeData=true' "$TMP/polls"; then echo fail; elif grep -q '^/api/v1/executions/[0-9]*?includeData=true' "$TMP/polls"; then echo ok; else echo fail; fi)"

echo "erros de infra saem 2, e a limpeza roda mesmo assim"
echo ok > "$TMP/modo"; echo invalido > "$TMP/juiz"; : > "$TMP/limpos"
check "juiz com número errado de critérios → exit 2" "$([ "$(roda "$TMP/qa/cenarios/feliz.json")" = 2 ] && echo ok || echo fail)"
check "limpeza rodou no erro" "$([ -s "$TMP/limpos" ] && echo ok || echo fail)"
echo recusa > "$TMP/juiz"
check "refusal do Claude → exit 2" "$([ "$(roda "$TMP/qa/cenarios/feliz.json")" = 2 ] && echo ok || echo fail)"
echo aprova > "$TMP/juiz"
check "prefixo de telefone real é recusado antes de injetar (exit 2)" "$(n=$(wc -l < "$TMP/injetados"); r=$(roda "$TMP/qa/cenarios/telreal.json"); [ "$r" = 2 ] && [ "$(wc -l < "$TMP/injetados")" = "$n" ] && echo ok || echo fail)"
sed 's#"limpeza": \[.*\]#"limpeza": ["false {{env:TOKEN_WEBHOOK}}"]#' "$TMP/qa/agente.json" > "$TMP/qa/agente-limpeza.json"
cenario limpeza '"nome": "limpeza", "turnos": 1, "criterios": ["x"]'
sed -i.bak 's#../agente.json#../agente-limpeza.json#' "$TMP/qa/cenarios/limpeza.json"
check "limpeza que falha → exit 2, sem vazar o segredo do env" "$([ "$(roda "$TMP/qa/cenarios/limpeza.json")" = 2 ] && ! grep -q segredo "$TMP/out" && echo ok || echo fail)"
cenario longo '"nome": "longo", "turnos": 6, "criterios": ["x"]'
check "Ctrl+C no meio → limpeza roda e sai 130" "$(: > "$TMP/limpos"; : > "$TMP/injetados"
  node "$SIM" "$TMP/qa/cenarios/longo.json" --saida "$TMP/saida" > "$TMP/out" 2>&1 & P=$!
  for _ in $(seq 300); do [ -s "$TMP/injetados" ] || ! kill -0 $P 2>/dev/null && break; sleep 0.1; done; sleep 0.3
  kill -INT $P; wait $P; r=$?; [ "$r" = 130 ] && grep -q '^5500' "$TMP/limpos" && echo ok || echo fail)"
check "--manter pula a limpeza" "$(: > "$TMP/limpos"; roda "$TMP/qa/cenarios/numero.json" --manter >/dev/null; [ -s "$TMP/limpos" ] && echo fail || echo ok)"

echo "rodadas"
check "--rodadas 2 --paralelo 2 reporta 2/2" "$([ "$(roda "$TMP/qa/cenarios/numero.json" --rodadas 2 --paralelo 2)" = 0 ] && grep -q '2/2' "$TMP/out" && echo ok || echo fail)"

echo
[ "$falhas" = 0 ] && echo "tudo ok" || { echo "$falhas falha(s)"; cat "$TMP/out"; exit 1; }
