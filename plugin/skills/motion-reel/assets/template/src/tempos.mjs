// Contas puras das cenas avulsas (sem React): tempo de cada estado e posição, ordem do ranking,
// letras e palavras da troca de frase, número com decimais em pt-BR e enquadramento do mapa.
// JavaScript puro (.mjs) para o teste rodar no Node sem compilar; os tipos estão em tempos.d.mts.
// O scripts/tempos.py espelha temposMorph e temposRanking para o som (track_cinema.py): mudou
// aqui, mude lá; o tests/test-motion-reel-galeria.sh compara os dois.

// Intervalo mínimo entre dois estados do morph: a palavra entra 8 quadros depois da troca e sai 5
// antes da próxima, então menos que isso ela nunca aparece.
export const GAP_MORPH = 16;
// Intervalo mínimo entre duas posições do ranking.
export const GAP_RANKING = 6;

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
