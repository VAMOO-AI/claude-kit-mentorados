#!/usr/bin/env node
// Conversa simulada contra um agente n8n de WhatsApp: um lead (Claude) conversa por N turnos
// via injeção no webhook, as respostas saem de /api/v1/executions, e no fim rodam as
// checagens deterministas e o juiz. Formato e uso: references/qa-simulada.md.
//
// node simular-conversa.mjs <cenario.json>... [--rodadas N] [--paralelo K] [--saida DIR] [--manter]
// Saída: 0 tudo passou · 1 algum cenário reprovado · 2 erro de infra/config/limpeza · 130 Ctrl+C
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";

const API_CLAUDE = (process.env.ANTHROPIC_BASE_URL || "https://api.anthropic.com").replace(/\/$/, "");
const MODELOS_COM_FALLBACK = new Set(["claude-opus-5", "claude-fable-5-1"]);
const TIPOS = new Set(["proibido", "numeros_permitidos", "silencio_apos", "comando"]);
const dorme = (ms) => new Promise((r) => setTimeout(r, ms));

class ErroInfra extends Error {}

function args(argv) {
  const o = { cenarios: [], rodadas: 1, paralelo: 1, saida: null, manter: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--rodadas") o.rodadas = Number(argv[++i]);
    else if (a === "--paralelo") o.paralelo = Number(argv[++i]);
    else if (a === "--saida") o.saida = argv[++i];
    else if (a === "--manter") o.manter = true;
    else o.cenarios.push(a);
  }
  if (!o.cenarios.length || !(o.rodadas >= 1) || !(o.paralelo >= 1)) {
    console.error("uso: simular-conversa.mjs <cenario.json>... [--rodadas N] [--paralelo K] [--saida DIR] [--manter]");
    process.exit(2);
  }
  return o;
}

function lerJson(arq) {
  try { return JSON.parse(fs.readFileSync(arq, "utf8")); }
  catch (e) { throw new ErroInfra(`não li ${arq}: ${e.message}`); }
}

function comEnv(s) {
  return s.replace(/\{\{env:([A-Z0-9_]+)\}\}/g, (_, v) => {
    if (!process.env[v]) throw new ErroInfra(`variável de ambiente ${v} não definida`);
    return process.env[v];
  });
}

function regex(fonte, flags, onde) {
  try { return new RegExp(fonte, (flags || "").replace(/[gy]/g, "")); }
  catch (e) { throw new ErroInfra(`${onde}: regex inválida (${e.message})`); }
}

// Tudo que pode estar errado no cenário quebra aqui, antes da primeira injeção no webhook de produção.
function carregar(arqCenario) {
  const cenario = lerJson(arqCenario);
  const dirCenario = path.dirname(path.resolve(arqCenario));
  const onde = path.basename(arqCenario);
  if (!/^[\w.-]+$/.test(cenario.nome || "")) throw new ErroInfra(`${onde}: "nome" ausente ou com caractere fora de [A-Za-z0-9_.-]`);
  if (!cenario.agente) throw new ErroInfra(`${onde}: falta "agente"`);
  if (!cenario.persona) throw new ErroInfra(`${onde}: falta "persona"`);
  if (!cenario.criterios?.length) throw new ErroInfra(`${onde}: sem "criterios" — o juiz precisa de pelo menos um`);
  const roteiro = cenario.roteiro || [];
  const total = Math.max(cenario.turnos || 0, roteiro.length);
  if (!total) throw new ErroInfra(`${onde}: sem "turnos" nem "roteiro"`);

  const arqAgente = path.resolve(dirCenario, cenario.agente);
  const bruto = lerJson(arqAgente);
  const dirAgente = path.dirname(arqAgente);
  for (const k of ["n8n_url", "webhook_url", "workflow_id", "payload", "no_resposta", "telefone_prefixo"])
    if (!bruto[k]) throw new ErroInfra(`${cenario.agente}: falta "${k}"`);
  // DDD 00: o /send do provider falha e ninguém real recebe nada (troubleshooting.md § QA).
  if (!/^5500\d*$/.test(bruto.telefone_prefixo))
    throw new ErroInfra(`telefone_prefixo "${bruto.telefone_prefixo}" não começa com 5500 — o agente responderia a um número que pode existir`);
  const agente = {
    timeout_turno_s: 90, quieto_s: 5, pausa_entre_turnos_s: 2, intervalo_rajada_ms: 1000, intervalo_poll_s: 2,
    campo_resposta: "", limpeza: [], n8n_api_key_env: "N8N_API_KEY", llm: {}, ...bruto,
  };
  const payload = lerJson(path.resolve(dirAgente, agente.payload));
  if (!JSON.stringify(payload).includes("{{message_id}}"))
    throw new ErroInfra(`${agente.payload}: sem {{message_id}} — é por ele que a resposta é casada com o turno`);
  if (!process.env[agente.n8n_api_key_env]) throw new ErroInfra(`${agente.n8n_api_key_env} não definida`);
  if (!process.env.ANTHROPIC_API_KEY) throw new ErroInfra("ANTHROPIC_API_KEY não definida");
  for (const s of [agente.n8n_url, agente.webhook_url, ...agente.limpeza]) comEnv(s);

  const checagens = (cenario.checagens || []).map((c, i) => {
    const aqui = `${onde} checagem ${i + 1}`;
    if (!TIPOS.has(c.tipo)) throw new ErroInfra(`${aqui}: tipo desconhecido "${c.tipo}"`);
    if (c.tipo === "proibido") return { ...c, re: regex(c.regex, c.flags, aqui) };
    if (c.tipo === "numeros_permitidos") {
      const lista = c.lista || (c.arquivo && lerJson(path.resolve(dirCenario, c.arquivo))[c.chave]);
      if (!Array.isArray(lista) || !lista.length) throw new ErroInfra(`${aqui}: lista vazia ou chave "${c.chave}" ausente`);
      return { ...c, lista };
    }
    if (c.tipo === "silencio_apos") {
      if (!Number.isInteger(c.turno) || c.turno < 2 || roteiro[c.turno - 1] == null)
        throw new ErroInfra(`${aqui}: "turno" tem que apontar para uma fala fixa do roteiro a partir do turno 2 (o gatilho não pode depender do lead simulado, e sem resposta antes dele o silêncio não prova nada)`);
      return c;
    }
    if (!c.cmd || (c.espera == null && !c.regex)) throw new ErroInfra(`${aqui}: comando precisa de "cmd" e de "espera" ou "regex"`);
    comEnv(c.cmd);
    return { ...c, re: c.regex ? regex(c.regex, "", aqui) : null };
  });
  return { cenario, checagens, roteiro, total, dirCenario, dirAgente, agente, payload };
}

function preencher(no, vars) {
  if (typeof no === "string") {
    const exato = no.match(/^\{\{(\w+)\}\}$/);
    if (exato && typeof vars[exato[1]] === "number") return vars[exato[1]];
    return no.replace(/\{\{(\w+)\}\}/g, (m, k) => (k in vars ? String(vars[k]) : m));
  }
  if (Array.isArray(no)) return no.map((x) => preencher(x, vars));
  if (no && typeof no === "object") return Object.fromEntries(Object.entries(no).map(([k, v]) => [k, preencher(v, vars)]));
  return no;
}

async function http(url, opts = {}) {
  const nome = `${opts.method || "GET"} ${url.split("?")[0]}`;
  let r;
  try { r = await fetch(url, opts); }
  catch (e) { throw new ErroInfra(`${nome}: ${e.message}`); }
  const txt = await r.text();
  if (!r.ok) throw new ErroInfra(`${nome} → HTTP ${r.status}: ${txt.slice(0, 300)}`);
  try { return JSON.parse(txt); } catch { return txt; }
}

async function claude(llm, papel, system, messages, schema) {
  const model = llm.modelo || "claude-opus-5";
  const body = {
    model, max_tokens: 16000, system, messages,
    output_config: { effort: papel === "juiz" ? llm.effort_juiz || "high" : llm.effort_lead || "low",
      format: { type: "json_schema", schema } },
  };
  const headers = { "content-type": "application/json", "x-api-key": process.env.ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01" };
  if (MODELOS_COM_FALLBACK.has(model)) {
    body.fallbacks = "default";
    headers["anthropic-beta"] = "server-side-fallback-2026-07-01";
  }
  const r = await http(`${API_CLAUDE}/v1/messages`, { method: "POST", headers, body: JSON.stringify(body) });
  if (r.stop_reason === "refusal") throw new ErroInfra(`Claude recusou o pedido do ${papel} (${r.stop_details?.category ?? "sem categoria"})`);
  if (r.stop_reason === "max_tokens") throw new ErroInfra(`resposta do ${papel} cortada em max_tokens`);
  const texto = r.content?.find((b) => b.type === "text")?.text;
  try { return JSON.parse(texto); }
  catch { throw new ErroInfra(`${papel} devolveu algo que não é JSON: ${String(texto).slice(0, 200)}`); }
}

const SCHEMA_LEAD = {
  type: "object", additionalProperties: false, required: ["mensagens"],
  properties: { mensagens: { type: "array", items: { type: "string" } } },
};
const SCHEMA_JUIZ = {
  type: "object", additionalProperties: false, required: ["criterios"],
  properties: { criterios: { type: "array", items: {
    type: "object", additionalProperties: false, required: ["indice", "passou", "motivo"],
    properties: { indice: { type: "integer" }, passou: { type: "boolean" }, motivo: { type: "string" } },
  } } },
};

async function falaDoLead(ctx, turnos) {
  const system = `SIMULADOR. Você é um lead conversando pelo WhatsApp com o atendimento de uma empresa. Persona e situação:
${ctx.cenario.persona}

Escreva como gente escreve no WhatsApp: português do Brasil informal, mensagens curtas, às vezes duas ou três seguidas. Nunca diga que é um teste ou uma IA, e não encerre a conversa: se o assunto acabar, puxe outro dentro da persona. Cada item de "mensagens" é um balão separado.`;
  const messages = [{ role: "user", content: "(a conversa começa agora — mande sua primeira mensagem)" }];
  for (const t of turnos) {
    messages.push({ role: "assistant", content: t.lead.join("\n") });
    messages.push({ role: "user", content: t.agente.length ? t.agente.join("\n") : "(o atendimento não respondeu)" });
  }
  const r = await claude(ctx.agente.llm, "lead", system, messages, SCHEMA_LEAD);
  const msgs = (r.mensagens || []).map((m) => m.trim()).filter(Boolean);
  if (!msgs.length) throw new ErroInfra("simulador devolveu zero mensagens");
  return msgs;
}

async function injetar(ctx, telefone, texto, messageId) {
  const agora = Date.now();
  const corpo = preencher(ctx.payload, {
    texto, telefone, nome: ctx.cenario.nome_lead || "Lead Teste", message_id: messageId,
    agora_ms: agora, agora_s: Math.floor(agora / 1000), agora_iso: new Date(agora).toISOString(),
  });
  await http(comEnv(ctx.agente.webhook_url), { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(corpo) });
}

function respostasDaExecucao(exec, noResposta, campo) {
  const runs = exec.data?.resultData?.runData?.[noResposta];
  if (!runs?.length) return null;
  const out = [];
  for (const item of runs.at(-1).data?.main?.[0] || []) {
    const v = campo ? campo.split(".").reduce((o, k) => o?.[k], item.json) : item.json;
    for (const x of Array.isArray(v) ? v : [v]) {
      if (typeof x === "string") out.push(x);
      else if (x && typeof x === "object") out.push(x.text ?? x.content ?? x.mensagem ?? JSON.stringify(x));
    }
  }
  return out;
}

function n8n(ctx) {
  const a = ctx.agente;
  const base = `${comEnv(a.n8n_url).replace(/\/$/, "")}/api/v1/executions`;
  const headers = { "X-N8N-API-KEY": process.env[a.n8n_api_key_env] };
  return {
    // A lista vem sem runData (barata); o detalhe só das execuções novas e terminadas.
    lista: async () => (await http(`${base}?workflowId=${encodeURIComponent(a.workflow_id)}&limit=100`, { headers })).data || [],
    detalhe: (id) => http(`${base}/${encodeURIComponent(id)}?includeData=true`, { headers }),
  };
}

// Casa execução com turno pelo message_id injetado, não pelo relógio: resposta que chega
// atrasada entra no turno a que pertence, mesmo se o próximo já começou.
async function coletar(ctx, conv, turnoAtual) {
  const a = ctx.agente;
  const fimEm = Date.now() + a.timeout_turno_s * 1000;
  let quietoAte = null;
  while (Date.now() < (quietoAte ?? fimEm)) {
    for (const e of await conv.api.lista()) {
      if (conv.vistas.has(e.id) || !e.stoppedAt) continue;
      conv.vistas.add(e.id);
      const d = await conv.api.detalhe(e.id);
      const s = JSON.stringify(d.data?.resultData?.runData ?? {});
      const id = [...conv.idParaTurno.keys()].find((m) => s.includes(m));
      if (!id) continue;
      const turno = conv.turnos[conv.idParaTurno.get(id)];
      const r = respostasDaExecucao(d, a.no_resposta, a.campo_resposta);
      if (r) {
        turno.agente.push(...r);
        if (turno.turno === turnoAtual) quietoAte = Date.now() + a.quieto_s * 1000;
      } else if (d.status === "error" || d.data?.resultData?.error) {
        const rd = d.data?.resultData || {};
        throw new ErroInfra(`execução ${e.id} (turno ${turno.turno}) quebrou em "${rd.lastNodeExecuted ?? "?"}" antes de "${a.no_resposta}": ${rd.error?.message ?? d.status}`);
      }
    }
    await dorme(a.intervalo_poll_s * 1000);
  }
}

function numeros(texto) {
  const semDataHora = texto
    .replace(/\b\d{1,2}\/\d{1,2}(\/\d{2,4})?\b/g, " ")
    .replace(/\b\d{1,2}(:\d{2}|h\d{0,2})\b/gi, " ");
  const re = /(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d+))?(\s*%|\s*(?:milh(?:ão|ao|ões|oes)|bilh(?:ão|ao|ões|oes)|mil)\b)?/gi;
  return [...semDataHora.matchAll(re)].map((m) => {
    let v = Number(m[1].replace(/\./g, "")) + (m[2] ? Number(`0.${m[2]}`) : 0);
    const suf = (m[3] || "").trim().toLowerCase();
    if (suf.startsWith("milh")) v *= 1e6;
    else if (suf.startsWith("bilh")) v *= 1e9;
    else if (suf === "mil") v *= 1e3;
    return { bruto: m[0].trim(), chave: (suf === "%" ? "%" : "") + v };
  });
}

function checar(ctx, turnos, telefone) {
  const out = [];
  const falas = (quem) => turnos.flatMap((t) => t[quem].map((texto) => ({ turno: t.turno, texto })));
  for (const c of ctx.checagens) {
    if (c.tipo === "proibido") {
      const hit = falas("agente").find((f) => f.turno >= (c.a_partir_do_turno || 1) && c.re.test(f.texto));
      out.push({ checagem: `proibido /${c.regex}/`, passou: !hit, motivo: hit ? `turno ${hit.turno}: "${hit.texto}"` : "" });
    } else if (c.tipo === "numeros_permitidos") {
      const conhecidos = new Set([...c.lista, ...falas("lead").map((f) => f.texto)].flatMap(numeros).map((n) => n.chave));
      const hit = falas("agente").flatMap((f) => numeros(f.texto).filter((n) => !conhecidos.has(n.chave)).map((n) => ({ ...f, n })))[0];
      out.push({ checagem: "números só da lista ou do lead", passou: !hit, motivo: hit ? `turno ${hit.turno}: "${hit.n.bruto}" em "${hit.texto}"` : "" });
    } else if (c.tipo === "silencio_apos") {
      const antes = turnos.some((t) => t.turno < c.turno && t.agente.length);
      const fala = turnos.find((t) => t.turno >= c.turno && t.agente.length);
      out.push({ checagem: `silêncio a partir do turno ${c.turno}`, passou: antes && !fala,
        motivo: !antes ? "o agente não respondeu nada antes do gatilho — silêncio aqui não prova nada" : fala ? `turno ${fala.turno}: "${fala.agente[0]}"` : "" });
    } else {
      const cmd = comEnv(c.cmd).replaceAll("{{telefone}}", telefone);
      let saida;
      try { saida = execSync(cmd, { cwd: ctx.dirCenario, encoding: "utf8", timeout: 60000, stdio: ["ignore", "pipe", "pipe"] }).trim(); }
      catch (e) { saida = `(saiu ${e.status ?? e.signal}) ${String(e.stderr || e.stdout || "").trim()}`; }
      const ok = c.re ? c.re.test(saida) : saida === String(c.espera);
      out.push({ checagem: `comando: ${c.cmd}`, passou: ok, motivo: ok ? "" : `esperava ${c.re ? `/${c.regex}/` : `"${c.espera}"`}, veio "${saida}"` });
    }
  }
  return out;
}

async function julgar(ctx, turnos) {
  const criterios = ctx.cenario.criterios;
  const transcript = turnos.map((t) => [
    ...t.lead.map((m) => `[turno ${t.turno}] LEAD: ${m}`),
    ...(t.agente.length ? t.agente.map((m) => `[turno ${t.turno}] AGENTE: ${m}`) : [`[turno ${t.turno}] (agente não respondeu)`]),
  ].join("\n")).join("\n");
  const system = `JUIZ. Você avalia a conversa de um agente de WhatsApp com um lead simulado. Julgue cada critério só pelo que está no transcript: passou=false quando o transcript mostra a violação, ou quando o critério exige algo que não aconteceu. Devolva um item por critério, com o "indice" do critério; o motivo cita o turno.`;
  const user = `Persona do lead: ${ctx.cenario.persona}\n\nCritérios:\n${criterios.map((c, i) => `${i + 1}. ${c}`).join("\n")}\n\nTranscript:\n${transcript}`;
  for (let tentativa = 1; ; tentativa++) {
    const r = await claude(ctx.agente.llm, "juiz", system, [{ role: "user", content: user }], SCHEMA_JUIZ);
    const porIndice = new Map((r.criterios || []).map((v) => [v.indice, v]));
    if (porIndice.size === criterios.length && criterios.every((_, i) => porIndice.has(i + 1)))
      return criterios.map((criterio, i) => ({ criterio, passou: porIndice.get(i + 1).passou, motivo: porIndice.get(i + 1).motivo }));
    if (tentativa === 2) throw new ErroInfra(`juiz devolveu índices [${[...porIndice.keys()]}] para ${criterios.length} critérios`);
  }
}

const ativos = new Map();
let limpezaFalhou = false;

function limpar(ctx, telefone) {
  const cmds = ctx.agente.limpeza;
  cmds.forEach((cmd, i) => {
    try { execSync(comEnv(cmd).replaceAll("{{telefone}}", telefone), { cwd: ctx.dirAgente, stdio: "ignore", timeout: 60000 }); }
    catch (e) {
      limpezaFalhou = true;
      // Só o número do comando: a mensagem do execSync traz o comando com o {{env:}} já expandido.
      console.error(`limpeza falhou (${telefone}): comando ${i + 1} de ${cmds.length} saiu ${e.status ?? e.signal ?? "com erro"}`);
    }
  });
}

async function rodar(ctx, rodada, opts) {
  const a = ctx.agente;
  const telefone = a.telefone_prefixo + Array.from({ length: Math.max(13 - a.telefone_prefixo.length, 4) }, () => Math.floor(Math.random() * 10)).join("");
  const conv = { api: n8n(ctx), vistas: new Set(), idParaTurno: new Map(), turnos: [] };
  if (!opts.manter) ativos.set(telefone, ctx);
  try {
    for (const e of await conv.api.lista()) conv.vistas.add(e.id);
    for (let turno = 1; turno <= ctx.total; turno++) {
      const fixo = ctx.roteiro[turno - 1];
      const msgs = fixo != null ? [].concat(fixo) : await falaDoLead(ctx, conv.turnos);
      conv.turnos.push({ turno, lead: msgs, agente: [] });
      for (const [i, m] of msgs.entries()) {
        if (i) await dorme(a.intervalo_rajada_ms);
        const id = `sim${telefone.slice(-6)}t${turno}m${i}x${Date.now()}`;
        conv.idParaTurno.set(id, turno - 1);
        await injetar(ctx, telefone, m, id);
      }
      await coletar(ctx, conv, turno);
      if (turno < ctx.total) await dorme(a.pausa_entre_turnos_s * 1000);
    }
    const turnos = conv.turnos;
    if (!turnos.some((t) => t.agente.length))
      throw new ErroInfra(`nenhuma resposta do agente em ${turnos.length} turnos — workflow ativo? "${a.no_resposta}" é o nó certo? execuções com sucesso estão sendo salvas?`);
    const checagens = checar(ctx, turnos, telefone);
    const juiz = await julgar(ctx, turnos);
    const passou = checagens.every((c) => c.passou) && juiz.every((c) => c.passou);
    const rel = { cenario: ctx.cenario.nome, rodada, telefone, passou, checagens, juiz, turnos };
    fs.mkdirSync(opts.saida, { recursive: true });
    fs.writeFileSync(path.join(opts.saida, `${ctx.cenario.nome}-${rodada}-${Date.now()}.json`), JSON.stringify(rel, null, 2));
    return rel;
  } finally {
    if (ativos.delete(telefone)) limpar(ctx, telefone);
  }
}

function imprimir(rel) {
  console.log(`\n── ${rel.cenario} #${rel.rodada} (${rel.telefone}) ${rel.passou ? "PASSOU" : "REPROVOU"}`);
  for (const t of rel.turnos) {
    for (const m of t.lead) console.log(`  ${t.turno}. lead:   ${m}`);
    for (const m of t.agente.length ? t.agente : ["(sem resposta)"]) console.log(`  ${t.turno}. agente: ${m}`);
  }
  for (const c of [...rel.checagens.map((c) => ({ ...c, nome: c.checagem })), ...rel.juiz.map((c) => ({ ...c, nome: `juiz: ${c.criterio}` }))])
    console.log(`  ${c.passou ? "ok   " : "FALHA"} ${c.nome}${c.passou ? "" : ` — ${c.motivo}`}`);
}

for (const [sinal, codigo] of [["SIGINT", 130], ["SIGTERM", 143]])
  process.on(sinal, () => {
    console.error(`\n${sinal}: limpando ${ativos.size} lead(s) de teste antes de sair`);
    for (const [telefone, ctx] of ativos) limpar(ctx, telefone);
    process.exit(codigo);
  });

async function main() {
  const opts = args(process.argv.slice(2));
  let ctxs;
  try { ctxs = opts.cenarios.map(carregar); }
  catch (e) { console.error(`erro: ${e.message}`); process.exit(2); }
  if (!opts.saida) opts.saida = path.join(ctxs[0].dirAgente, "resultados");

  const fila = ctxs.flatMap((ctx) => Array.from({ length: opts.rodadas }, (_, i) => ({ ctx, rodada: i + 1 })));
  const resultados = [];
  let erroInfra = false;
  const trabalhador = async () => {
    for (let job; (job = fila.shift()); ) {
      try { const rel = await rodar(job.ctx, job.rodada, opts); imprimir(rel); resultados.push(rel); }
      catch (e) {
        erroInfra = true;
        console.error(`\n── ${job.ctx.cenario.nome} #${job.rodada} ERRO: ${e instanceof ErroInfra ? e.message : e.stack}`);
      }
    }
  };
  await Promise.all(Array.from({ length: opts.paralelo }, trabalhador));

  console.log("\nresumo");
  for (const ctx of ctxs) {
    const rs = resultados.filter((r) => r.cenario === ctx.cenario.nome);
    console.log(`  ${ctx.cenario.nome}: ${rs.filter((r) => r.passou).length}/${opts.rodadas} passaram${rs.length < opts.rodadas ? ` (${opts.rodadas - rs.length} com erro)` : ""}`);
  }
  if (limpezaFalhou) console.error("\nlimpeza falhou em alguma rodada — confira leads, mensagens e chaves Redis dos telefones acima");
  process.exit(erroInfra || limpezaFalhou ? 2 : resultados.every((r) => r.passou) ? 0 : 1);
}

main();
