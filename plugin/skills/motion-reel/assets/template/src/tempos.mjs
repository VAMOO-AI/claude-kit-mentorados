// Contas puras das cenas avulsas (sem React): tempo de cada estado e posição, ordem do ranking,
// letras e palavras da troca de frase, número com decimais em pt-BR e enquadramento do mapa.
// JavaScript puro (.mjs) para o teste rodar no Node sem compilar; os tipos estão em tempos.d.mts.
// O som (sons.mjs, lido pelo track_cinema.py via Node) usa estas mesmas funções: sem espelho.

// Intervalo mínimo entre dois estados do morph: a palavra entra 8 quadros depois da troca e sai 5
// antes da próxima, então menos que isso ela nunca aparece.
export const GAP_MORPH = 16;
// Intervalo mínimo entre duas posições do ranking.
export const GAP_RANKING = 6;

// Tempos que a cena e o som (sons.mjs) leem do mesmo lugar: o desk envia o pedido no quadro 24 (o
// cursor toca o botão 1 quadro antes) e o 1º do ranking chega ao pico do overshoot 5 quadros depois
// de entrar.
export const DESK_ENVIA = 24;
export const RANKING_PICO = 5;

// Quadro de cada troca do morph. `falas` = início de cada fala (bt(p, k)); `t0` = first(p).
// Estado k troca na fala k (4 quadros antes); sem fala, `step` quadros depois do anterior, a partir
// da última fala. Com `loop`, há uma troca a mais (a volta ao 1º estado), que segue a mesma regra.
// Os tempos sempre crescem.
export function temposMorph(nEstados, falas, t0, step, loop) {
  const n = nEstados + (loop && nEstados > 1 ? 1 : 0);
  const at = [];
  for (let k = 0; k < n; k++) {
    if (k === 0) {
      at.push(t0);
      continue;
    }
    const alvo = k < falas.length ? falas[k] - 4 : at[k - 1] + step;
    at.push(Math.max(alvo, at[k - 1] + GAP_MORPH));
  }
  return at;
}

// Quadro de entrada de cada posição do ranking, na ordem de entrada (e = 0 é o último lugar, que
// entra primeiro; e = n − 1 é o 1º, que entra por último). Com fala e, na fala; sem, `step` quadros
// depois da anterior, a partir da última fala. Sempre crescente: o 1º nunca entra antes de outro.
export function temposRanking(n, falas, t0, step) {
  const at = [];
  for (let e = 0; e < n; e++) {
    if (e === 0) {
      at.push(t0 + 6);
      continue;
    }
    const alvo = e < falas.length ? falas[e] - 4 : at[e - 1] + step;
    at.push(Math.max(alvo, at[e - 1] + GAP_RANKING));
  }
  return at;
}

// Ordena antes de cortar: com 7 itens, o maior fica mesmo que venha por último.
export function ordenarRanking(items, low, max = 6) {
  return [...items].sort((a, b) => (low ? a.v - b.v : b.v - a.v)).slice(0, max);
}

// Letras da frase em NFC: "é" decomposto (e + acento) vira uma letra só, como na tela.
export function letras(s) {
  return Array.from(String(s ?? "").normalize("NFC"));
}

// Grupos [início, fim) de letras: cada palavra é um grupo e cada espaço é um grupo. A régua e a
// frase põem cada palavra num inline-block com nowrap, então a linha só quebra entre palavras.
export function palavras(chars) {
  const grupos = [];
  let i = 0;
  while (i < chars.length) {
    const espaco = !chars[i].trim();
    let j = i + 1;
    while (j < chars.length && !chars[j].trim() === espaco) j++;
    grupos.push([i, j]);
    i = j;
  }
  return grupos;
}

// Casas decimais do valor (até 2): 4.5 → 1, 1250000 → 0.
export function decimaisDe(v) {
  if (!Number.isFinite(v) || Number.isInteger(v)) return 0;
  const s = String(v);
  const casas = s.includes("e") ? 2 : (s.split(".")[1] ?? "").length;
  return Math.min(2, casas);
}

// Número em pt-BR com `casas` decimais fixas: 4.5 → "4,5"; 1250000 → "1.250.000".
export function fmtNum(v, casas = 0) {
  return v.toLocaleString("pt-BR", { minimumFractionDigits: casas, maximumFractionDigits: casas });
}

// Maior valor para a proporção das barras; só cai para 1 se nenhum for positivo.
export function maiorValor(valores) {
  const m = Math.max(...valores.filter((v) => Number.isFinite(v)));
  return m > 0 ? m : 1;
}

// Corpo do número que cabe na largura: dígitos a ~0,62 em; prefixo e sufixo saem a 60% do corpo.
export function corpoNumero(it, largura, base) {
  const meio = fmtNum(it.v, decimaisDe(it.v)).length;
  const lados = String(it.prefix ?? "").length + String(it.suffix ?? "").length;
  const em = 0.62 * (meio + 0.6 * lados) + 0.12;
  return Math.max(12, Math.min(base, Math.floor(largura / em)));
}

// Pontos que a câmera do mapa enquadra. Paradas iguais contam uma vez. Sem região e com menos de
// 2 paradas distintas, entra uma caixa de ±6° em volta da parada (ou do 0,0): o fitExtent nunca
// recebe um ponto só (escala sem limite, quadro vazio).
export function enquadramento(paradas, temRegiao) {
  const vistos = new Set();
  const pts = [];
  for (const p of paradas) {
    const chave = `${p[0]},${p[1]}`;
    if (!vistos.has(chave)) {
      vistos.add(chave);
      pts.push(p);
    }
  }
  if (temRegiao || pts.length >= 2) return pts;
  const [lon, lat] = pts[0] ?? [0, 0];
  return [...pts, [lon - 6, lat - 6], [lon + 6, lat + 6]];
}

// Tempo da cena a partir das falas (o mesmo bt/first/hitAt do film-base.tsx, que reexporta estes):
// `s` = {beats, ends} da cena na timeline. O som (sons.mjs) e a cena usam as mesmas funções.
// Frame local da fala i (frac 0 = início, 1 = fim). Sem fala i: começo + 30.
export function bt(s, i, frac = 0) {
  const b = s.beats[i] ?? 0;
  const e = s.ends[i] ?? b + 30;
  return Math.round(b + frac * (e - b));
}

// O primeiro elemento da cena entra ANTES do corte (f < 0): a transição nunca revela tela vazia.
export function first(s) {
  return Math.min(bt(s, 0) - 6, -8);
}

// Sem fala, o elemento i cai na batida i·passo; com fala i, na fala. O índice 0 entra em first.
export function hitAt(s, i, step) {
  return i === 0 ? first(s) : i < s.beats.length ? bt(s, i) - 4 : i * step;
}

// Quadros em que as pílulas do CTA entram (a cena desenha, o som toca): a 1ª no meio da 1ª fala
// (nunca antes de 14 quadros do começo); a 2ª no meio da 2ª fala, ou 14 depois da 2ª pergunta.
export function pilulasCta(s) {
  const a = first(s);
  const b = s.beats.length > 1 ? bt(s, 1) - 6 : a + 24;
  return { a, b, p1: Math.max(a + 14, bt(s, 0, 0.5)), p2: s.beats.length > 1 ? Math.max(b + 14, bt(s, 1, 0.55)) : b + 14 };
}

// Frame da troca do swap: `at`, ou a 2ª fala − 6, ou 45 sem voz.
export function trocaSwap(s, p) {
  return p.at ?? (s.beats.length > 1 ? bt(s, 1) - 6 : 45);
}
