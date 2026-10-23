#!/usr/bin/env bash
# Lê o grupo de controle do RTK e diz quanto o filtro economizou DE VERDADE.
#
# O `rtk gain` é autorreportado: ele compara a saída bruta que ele mesmo capturou
# com a filtrada que devolveu, e chama a diferença de economia. Duas coisas ficam
# de fora, e as duas inflam o número:
#
#   1. o harness TRUNCA a saída de um Bash antes de mostrar ao modelo. Um `eslint`
#      que despeja 360 mil tokens nunca chegaria inteiro ao contexto — o rtk credita
#      a si mesmo tokens que ninguém pagaria;
#   2. não existe grupo de controle. Sem um braço sem filtro, "83,4%" não é medido
#      contra nada.
#
# Com RTK_HOLDOUT_PCT=N ligado (ver hooks/rtk-claude.sh), N% dos comandos elegíveis
# saem SEM filtro e o hook registra os dois braços num ledger. Este script cruza o
# ledger com o transcript da sessão e mede o tamanho do tool_result que o modelo
# recebeu — depois do truncamento, que é o único número que ele de fato pagou.
#
# Uso:
#   scripts/rtk-holdout.sh
#   scripts/rtk-holdout.sh --ledger /caminho/ledger.tsv --transcripts /caminho/projects
#   scripts/rtk-holdout.sh --min 20        # n mínimo por braço para concluir
#   scripts/rtk-holdout.sh --formato json
#
# Sai 1 quando não há amostra suficiente para concluir — é resultado, não erro:
# número de holdout com n pequeno é pior que número nenhum.
set -uo pipefail

LEDGER="${RTK_HOLDOUT_DIR:-$HOME/.claude/.cache/rtk-holdout}/ledger.tsv"
TRANSCRIPTS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
MIN=30
FORMATO=texto

while [ $# -gt 0 ]; do
  case "$1" in
    --ledger) LEDGER="$2"; shift 2 ;;
    --transcripts) TRANSCRIPTS="$2"; shift 2 ;;
    --min) MIN="$2"; shift 2 ;;
    --formato) FORMATO="$2"; shift 2 ;;
    # Até onde o cabeçalho vai é o próprio arquivo que diz: para na primeira linha que
    # não é comentário. Faixa fixa (2,28p) sangrava o `set -uo pipefail` para o --help.
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "argumento desconhecido: $1"; exit 2 ;;
  esac
done

command -v node >/dev/null 2>&1 || { echo "node não está no PATH"; exit 2; }
[ -f "$LEDGER" ] || {
  echo "sem ledger em $LEDGER"
  echo "→ o holdout está desligado. Ligue com RTK_HOLDOUT_PCT=10 no env do settings.json"
  echo "  e deixe rodar alguns dias; ver docs/rtk-holdout.md."
  exit 2
}

# rtk gain é só para contraste — o script funciona sem o rtk instalado.
CLAIM=$(rtk gain -f json 2>/dev/null | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{const j=JSON.parse(s);process.stdout.write(String(j.summary.avg_savings_pct??""))}catch{}
});' 2>/dev/null)

LEDGER="$LEDGER" TRANSCRIPTS="$TRANSCRIPTS" MIN="$MIN" FORMATO="$FORMATO" CLAIM="$CLAIM" node - <<'JS'
const fs = require("fs"), path = require("path");
const { LEDGER, TRANSCRIPTS, MIN, FORMATO, CLAIM } = process.env;
const min = parseInt(MIN, 10);

// ── ledger: sessao+hash → braço ────────────────────────────────────────────────
// O mesmo comando pode cair nos dois braços em sorteios diferentes da mesma sessão.
// Quando isso acontece o par vira ambíguo e sai da conta, contado à parte: atribuir
// no chute é como inventar o dado.
const arm = new Map(), fam = new Map(), sessoes = new Set();
let linhas = 0, primeiro = null, ultimo = null;
for (const l of fs.readFileSync(LEDGER, "utf8").split("\n")) {
  if (!l.trim()) continue;
  const [ts, braco, familia, hash, sess] = l.split("\t");
  if (!hash || !sess) continue;
  linhas++;
  if (!primeiro || ts < primeiro) primeiro = ts;
  if (!ultimo || ts > ultimo) ultimo = ts;
  sessoes.add(sess);
  const k = sess + "\t" + hash;
  const anterior = arm.get(k);
  arm.set(k, anterior && anterior !== braco ? "ambiguo" : braco);
  fam.set(k, familia);
}

// ── transcripts: quanto o modelo recebeu em cada comando ───────────────────────
function arquivos() {
  const out = [];
  const anda = (d) => {
    let e; try { e = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const it of e) {
      const p = path.join(d, it.name);
      if (it.isDirectory()) anda(p);
      else if (it.name.endsWith(".jsonl")) out.push(p);
    }
  };
  anda(TRANSCRIPTS);
  // Sessão do ledger primeiro: o nome do arquivo é o session_id. O resto do diretório
  // entra depois só para achar sessão gravada com outro nome.
  const pref = [], resto = [];
  for (const f of out) (sessoes.has(path.basename(f, ".jsonl")) ? pref : resto).push(f);
  return pref.concat(resto);
}

const crypto = require("crypto");
const sha = (s) => crypto.createHash("sha256").update(s).digest("hex").slice(0, 16);
const tam = (c) => typeof c === "string" ? c.length
  : Array.isArray(c) ? c.reduce((a, b) => a + (typeof b === "string" ? b.length : (b && b.text ? b.text.length : 0)), 0)
  : 0;

const dados = { controle: [], tratado: [] };   // {familia, chars}
let ambiguos = 0, semPar = 0, vistos = new Set();

for (const f of arquivos()) {
  let txt; try { txt = fs.readFileSync(f, "utf8"); } catch { continue; }
  const pend = new Map();   // tool_use_id → {chave, familia}
  for (const linha of txt.split("\n")) {
    if (!linha) continue;
    let o; try { o = JSON.parse(linha); } catch { continue; }
    const sess = o.sessionId || path.basename(f, ".jsonl");
    const blocos = o?.message?.content;
    if (!Array.isArray(blocos)) continue;
    for (const b of blocos) {
      if (b.type === "tool_use" && b.name === "Bash" && b.input && b.input.command) {
        const k = sess + "\t" + sha(b.input.command);
        if (arm.has(k)) pend.set(b.id, k);
      } else if (b.type === "tool_result" && pend.has(b.tool_use_id)) {
        const k = pend.get(b.tool_use_id);
        pend.delete(b.tool_use_id);
        vistos.add(k);
        const braco = arm.get(k);
        if (braco === "ambiguo") { ambiguos++; continue; }
        if (!dados[braco]) continue;
        dados[braco].push({ familia: fam.get(k) || "?", chars: tam(b.content) });
      }
    }
  }
}
for (const k of arm.keys()) if (!vistos.has(k)) semPar++;

// ── estatística ───────────────────────────────────────────────────────────────
const media = (a) => a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0;
const mediana = (a) => {
  if (!a.length) return 0;
  const s = [...a].sort((x, y) => x - y), m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const porFamilia = {};
for (const braco of ["controle", "tratado"])
  for (const d of dados[braco]) (porFamilia[d.familia] ??= { controle: [], tratado: [] })[braco].push(d.chars);

const c = dados.controle.map(d => d.chars), t = dados.tratado.map(d => d.chars);
const naive = media(c) > 0 ? 1 - media(t) / media(c) : null;

// Estimativa estratificada por família: dentro de uma família os comandos têm
// tamanho parecido, então comparar médias lá dentro tira o ruído de composição
// (uma amostra pequena que sorteou dois `eslint` para um braço só desloca o total).
let pesoC = 0, pesoEcon = 0, familias = [];
for (const [f, v] of Object.entries(porFamilia)) {
  const nC = v.controle.length, nT = v.tratado.length;
  const mC = media(v.controle), mT = media(v.tratado);
  familias.push({ familia: f, nC, nT, mC, mT, econ: nC && nT && mC > 0 ? 1 - mT / mC : null });
  if (nC && nT && mC > 0) { const n = nC + nT; pesoC += n * mC; pesoEcon += n * (mC - mT); }
}
familias.sort((a, b) => (b.nC + b.nT) - (a.nC + a.nT));
const estratificada = pesoC > 0 ? pesoEcon / pesoC : null;
const suficiente = c.length >= min && t.length >= min;

const res = {
  ledger: LEDGER, linhas, sessoes: sessoes.size, de: primeiro, ate: ultimo,
  pareados: { controle: c.length, tratado: t.length }, ambiguos, sem_par: semPar,
  chars: { controle: { media: media(c), mediana: mediana(c) }, tratado: { media: media(t), mediana: mediana(t) } },
  economia_medida_naive: naive, economia_medida_estratificada: estratificada,
  rtk_gain_declara: CLAIM ? Number(CLAIM) / 100 : null,
  amostra_suficiente: suficiente, min_por_braco: min,
  familias,
};

if (FORMATO === "json") { console.log(JSON.stringify(res, null, 2)); process.exit(suficiente ? 0 : 1); }

const pct = (x) => x === null || Number.isNaN(x) ? "—" : (x * 100).toFixed(1).replace(".", ",") + "%";
const num = (x) => Math.round(x).toLocaleString("pt-BR");
console.log("Grupo de controle do RTK — o que o modelo REALMENTE recebeu");
console.log("═".repeat(62));
console.log(`ledger: ${LEDGER}`);
console.log(`${linhas} sorteio(s), ${sessoes.size} sessão(ões), de ${primeiro || "?"} a ${ultimo || "?"}`);
console.log("");
console.log("braço      pareados   média(chars)  mediana(chars)");
console.log("─".repeat(62));
for (const b of ["controle", "tratado"])
  console.log(`${b.padEnd(10)} ${String(res.pareados[b]).padStart(8)}   ${num(res.chars[b].media).padStart(11)}   ${num(res.chars[b].mediana).padStart(13)}`);
console.log("");
if (ambiguos || semPar)
  console.log(`fora da conta: ${ambiguos} ambíguo(s) (mesmo comando nos dois braços), ${semPar} sem par no transcript`);
if (!suficiente) {
  console.log("");
  console.log(`AMOSTRA INSUFICIENTE: menos de ${min} pareados em algum braço.`);
  console.log("Deixe a campanha rodar mais; número de holdout com n pequeno mente mais que o do rtk gain.");
  process.exit(1);
}
console.log("");
console.log(`economia medida (estratificada por família): ${pct(estratificada)}`);
console.log(`economia medida (média simples):             ${pct(naive)}`);
console.log(`rtk gain declara:                            ${pct(res.rtk_gain_declara)}`);
console.log("");
console.log("família        n(ctrl)  n(trat)   média ctrl   média trat   economia");
console.log("─".repeat(72));
for (const f of familias.slice(0, 15))
  console.log(`${f.familia.slice(0, 13).padEnd(14)} ${String(f.nC).padStart(7)}  ${String(f.nT).padStart(7)}   ${num(f.mC).padStart(10)}   ${num(f.mT).padStart(10)}   ${pct(f.econ).padStart(8)}`);
console.log("");
console.log("O que este número é: chars do tool_result que o modelo recebeu, já truncado");
console.log("pelo harness — ~4 chars por token. O que ele NÃO é: custo por tarefa. Saída");
console.log("filtrada que esconde o dado faz o agente rodar o comando de novo, e essa");
console.log("segunda chamada não aparece em nenhum dos dois braços.");
process.exit(0);
JS
