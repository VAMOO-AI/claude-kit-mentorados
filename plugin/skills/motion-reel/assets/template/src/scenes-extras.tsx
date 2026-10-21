// Cenas avulsas do Film: sem preset próprio, entram em qualquer film.json pelo `type`. Mesmo molde
// do film-scenes.tsx: useF (f = 0 no corte), useL (guia do formato), bt (fala i), first (o primeiro
// elemento entra antes do corte) e fit (fonte que cabe). Registradas no SCENES do film-scenes.tsx,
// com som no SFX_BY_TYPE do scripts/track_cinema.py e exemplo no EXEMPLOS do galeria.py da skill.
import React from "react";
import { AbsoluteFill, continueRender, delayRender, interpolateColors, spring } from "remotion";
import { H1, LABEL, type SP, bt, first, fit, useL } from "./film-base";
import { ANTIC, Bg, C, Counter, EASE_INOUT, EXIT, POP, SETTLE, fontesProntas, hitStop, ip, useF } from "./lib";
import { corpoNumero, decimaisDe, letras, maiorValor, ordenarRanking, palavras, temposMorph, temposRanking } from "./tempos.mjs";

/* ───────────────────────── troca de frase: as letras viajam pelo portal ───────────────────────── */
// Ideia do wireframe-portal-title do HyperFrames (Apache-2.0), reescrita em SVG e CSS, sem WebGL.

type Pos = { x: number; y: number };
type Medida = { a: Pos[]; b: Pos[]; ha: number; hb: number };

// Cada letra de B pega a letra igual de A ainda livre que está mais perto na posição relativa. A
// letra de A que sobra mergulha no portal; a de B que não achou par nasce dele.
export const parear = (a: string[], b: string[]) => {
  const livre = a.map((ch) => ch.trim() !== "");
  const de = b.map((ch, j) => {
    if (!ch.trim()) return null;
    let melhor = -1;
    let dist = 1e9;
    a.forEach((c, i) => {
      if (!livre[i] || c.toLocaleLowerCase("pt-BR") !== ch.toLocaleLowerCase("pt-BR")) return;
      const d = Math.abs(i / Math.max(1, a.length - 1) - j / Math.max(1, b.length - 1));
      if (d < dist) {
        dist = d;
        melhor = i;
      }
    });
    if (melhor < 0) return null;
    livre[melhor] = false;
    return melhor;
  });
  return { de, sobra: livre };
};

// Uma frase em letras soltas (inline-block), na mesma caixa e no mesmo estilo da frase visível:
// serve de régua. A posição de cada letra sai do layout real da fonte, não da estimativa do fit().
// As letras de cada palavra ficam num inline-block com nowrap: letra solta deixa o Chrome quebrar a
// linha no meio da palavra ("plano pro" / "nto"); assim a quebra só cai entre palavras.
const Regua = React.forwardRef<HTMLDivElement, { chars: string[]; fs: number; w: number }>(({ chars, fs, w }, ref) => (
  <div ref={ref} style={{ position: "absolute", left: 0, top: 0, width: w, textAlign: "center", visibility: "hidden" }}>
    {palavras(chars).map(([a, b]) => (
      <span key={a} style={{ display: "inline-block", whiteSpace: "nowrap" }}>
        {chars.slice(a, b).map((ch, i) => (
          <span key={a + i} data-l="" style={{ ...H1, fontSize: fs, display: "inline-block", whiteSpace: "pre" }}>{ch}</span>
        ))}
      </span>
    ))}
  </div>
));

// Frase longa quebra em duas linhas na régua; a fonte é a que cabe na metade dela.
const metade = (s: string) => (s.length <= 16 ? s : s.slice(0, Math.ceil(s.length / 2) + 2));

// props: from (frase A), to (frase B), kicker?, bg? ("night"|"paper"), at? (frame da troca; padrão:
// a 2ª fala, ou 45 sem voz). A entra letra a letra; na troca, cada letra de A voa pelo portal até
// o lugar dela em B, as que sobram mergulham e as que faltam nascem dele.
export const LetterSwap: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const dark = p.bg !== "paper";
  const bg = dark ? C.night : C.paper;
  const fg = dark ? C.white : C.ink;
  const ring = dark ? C.brandOnDark : C.brand;
  const sa = String(p.from ?? "");
  const sb = String(p.to ?? "");
  const A = letras(sa);
  const B = letras(sb);
  const w = L.W - L.l - L.r;
  const fs = fit([metade(sa), metade(sb)], w, L.v ? 150 : 170, 0.62);
  const refA = React.useRef<HTMLDivElement>(null);
  const refB = React.useRef<HTMLDivElement>(null);
  const [handle] = React.useState(() => delayRender("medir as letras da troca de frase"));
  const [m, setM] = React.useState<Medida | null>(null);
  React.useLayoutEffect(() => {
    let vivo = true;
    fontesProntas().then(() => {
      if (!vivo) return;
      const ler = (el: HTMLDivElement | null) =>
        Array.from(el?.querySelectorAll("[data-l]") ?? []).map((c) => ({ x: (c as HTMLElement).offsetLeft, y: (c as HTMLElement).offsetTop }));
      setM({ a: ler(refA.current), b: ler(refB.current), ha: refA.current?.offsetHeight ?? 0, hb: refB.current?.offsetHeight ?? 0 });
    });
    return () => {
      vivo = false;
    };
  }, [sa, sb, fs, w]);
  React.useEffect(() => {
    if (m) continueRender(handle);
  }, [m, handle]);

  const { de, sobra } = React.useMemo(() => parear(A, B), [sa, sb]);
  const tA = first(p);
  const S: number = p.at ?? (p.beats.length > 1 ? bt(p, 1) - 6 : 45);
  const n = Math.max(A.length, B.length, 1);
  const passo = Math.min(1.2, 10 / n);
  const voo = 18;
  const fim = S + n * passo + voo;
  const cx = w / 2;
  const py = fs * 1.15; // o portal fica embaixo da linha: as letras descem por ele e sobem no lugar
  // portal: abre em 14 quadros e fecha em 10, acelerando (saída mais curta que a entrada)
  const abre = ip(f, [S - 10, S + 4], [0, 1], EASE_INOUT) * (1 - ip(f, [fim, fim + 10], [0, 1], EXIT));

  const glifos: React.ReactNode[] = [];
  if (m) {
    const ya = -m.ha / 2;
    const yb = -m.hb / 2;
    const span = (key: string, ch: string, x: number, y: number, s: number, o: number, color = fg) => (
      <span key={key} style={{ ...H1, fontSize: fs, position: "absolute", left: x, top: y, whiteSpace: "pre", color, opacity: o, transform: `scale(${s})`, transformOrigin: "50% 60%" }}>
        {ch}
      </span>
    );
    // A: entra letra a letra; na troca, a que tem par voa, a que sobra mergulha no portal.
    A.forEach((ch, i) => {
      const pa = m.a[i];
      if (!pa || !ch.trim()) return;
      const t = ip(f, [tA + i * 1.2, tA + i * 1.2 + 14], [0, 1]);
      const j = de.indexOf(i);
      if (f < S || (j < 0 && !sobra[i])) {
        glifos.push(span(`a${i}`, ch, pa.x, ya + pa.y + (1 - t) * fs * 0.5, 1, t));
        return;
      }
      if (j >= 0) return; // a letra com par é desenhada pelo lado de B
      const u = ip(f, [S + i * passo, S + i * passo + 10], [0, 1], EXIT);
      const x = pa.x + (cx - fs * 0.25 - pa.x) * u;
      const y = ya + pa.y + (py - ya - pa.y) * u * u;
      glifos.push(span(`a${i}`, ch, x, y, 1 - u, 1 - u * u, u > 0.4 ? ring : fg));
    });
    // B: a letra com par sai da posição de A numa curva que passa pelo portal; a sem par nasce dele.
    B.forEach((ch, j) => {
      const pb = m.b[j];
      if (!pb || !ch.trim()) return;
      const i = de[j];
      const d = S + j * passo;
      if (i !== null && i !== undefined && m.a[i]) {
        if (f < S) return;
        const pa = m.a[i];
        const u = ip(f, [d, d + voo], [0, 1], EASE_INOUT);
        const x0 = pa.x, y0 = ya + pa.y, x2 = pb.x, y2 = yb + pb.y;
        const x1 = (x0 + x2) / 2 + (cx - (x0 + x2) / 2) * 0.35;
        const y1 = py + fs * 0.4;
        const x = (1 - u) ** 2 * x0 + 2 * (1 - u) * u * x1 + u * u * x2;
        const y = (1 - u) ** 2 * y0 + 2 * (1 - u) * u * y1 + u * u * y2;
        // chegada: snap, then hold, com um overshoot de escala só na pousada
        const pouso = f >= d + voo ? ip(f, [d + voo, d + voo + 10], [0.9, 1], POP) : 1 - 0.3 * Math.sin(Math.PI * u);
        glifos.push(span(`b${j}`, ch, x, y, pouso, 1, u > 0.2 && u < 0.8 ? ring : fg));
        return;
      }
      const u = ip(f, [d + 8, d + 8 + 14], [0, 1], EASE_INOUT);
      if (u <= 0) return;
      const x = cx - fs * 0.25 + (pb.x - cx + fs * 0.25) * u;
      const y = py + (yb + pb.y - py) * Math.sqrt(u);
      glifos.push(span(`b${j}`, ch, x, y, ip(f, [d + 8, d + 20], [0, 1], POP), Math.min(1, u * 2), u < 0.7 ? ring : fg));
    });
  }

  const kick = p.kicker ? (
    <div style={{ position: "absolute", left: L.l, right: L.r, top: L.H / 2 - (m ? Math.max(m.ha, m.hb) / 2 : fs) - (L.v ? 110 : 90), textAlign: "center", opacity: ip(f, [tA + 8, tA + 16], [0, 1]) }}>
      <span style={{ ...LABEL, fontSize: L.v ? 30 : 26, color: dark ? C.faint : C.dim }}>{p.kicker}</span>
    </div>
  ) : null;

  return (
    <Bg color={bg}>
      {kick}
      <AbsoluteFill>
        <div style={{ position: "absolute", left: L.l, top: L.H / 2, width: w, height: 0 }}>
          <Regua ref={refA} chars={A} fs={fs} w={w} />
          <Regua ref={refB} chars={B} fs={fs} w={w} />
          {abre > 0.01 ? (
            <svg width={w} height={fs * 2} style={{ position: "absolute", left: 0, top: py - fs * 0.6, overflow: "visible" }}>
              {[1, 0.74, 0.5, 0.28].map((k, i) => (
                <ellipse key={i} cx={cx} cy={fs * 0.6} rx={w * 0.3 * k * abre} ry={fs * 0.26 * k * abre} fill="none" stroke={ring} strokeWidth={i === 0 ? 4 : 2} opacity={(1 - i * 0.22) * abre} strokeDasharray={i % 2 ? "10 8" : undefined} strokeDashoffset={i % 2 ? f * 2 : undefined} />
              ))}
            </svg>
          ) : null}
          {glifos}
        </div>
      </AbsoluteFill>
    </Bg>
  );
};

/* ───────────────────────── forma única que morfa (mola com vários alvos) ───────────────────────── */
// Uma caixa só muda de largura, altura, canto, giro e cor de estado em estado. Cada propriedade é a
// soma das molas de cada troca (valor = estado 0 + Σ (estado k − estado k−1) · mola(f − t_k)), então
// a troca nova parte de onde a anterior estiver, sem corte. A palavra do estado entra depois que a
// caixa assenta e sai, mais rápida, antes da próxima troca.

type Forma = { w: number; h: number; r: number; rot: number };
// Formas padrão em fração do lado útil (r = fração do menor lado): círculo, pílula, losango, cartão,
// coluna, quadrado arredondado, barra e anel achatado.
const FORMAS: Forma[] = [
  { w: 0.34, h: 0.34, r: 0.5, rot: 0 },
  { w: 0.66, h: 0.2, r: 0.5, rot: 0 },
  { w: 0.32, h: 0.32, r: 0.08, rot: 45 },
  { w: 0.56, h: 0.36, r: 0.08, rot: 0 },
  { w: 0.24, h: 0.52, r: 0.12, rot: 0 },
  { w: 0.42, h: 0.42, r: 0.24, rot: 90 },
  { w: 0.74, h: 0.13, r: 0.1, rot: 0 },
  { w: 0.46, h: 0.28, r: 0.5, rot: 0 },
];
type Estado = { label: string; shape?: number; color?: "brand" | "fill" | "light" };
const TINTAS = {
  fill: { bg: C.accentFill, fg: C.white },
  light: { bg: C.white, fg: C.ink },
  brand: { bg: C.brand, fg: C.white },
};
const ORDEM: (keyof typeof TINTAS)[] = ["fill", "light", "brand"];

// props: states [{label, shape? (0–7, padrão: o índice), color? "brand"|"fill"|"light"}] (1–8), kicker?,
// step? (frames por estado sem voz, padrão 30), loop? (padrão true: volta ao 1º estado no fim, e o
// último quadro casa com o primeiro). Com voz, o estado i troca na fala i; estado sem fala (e a volta
// do loop) vem `step` quadros depois do anterior, a partir da última fala (temposMorph).
export const MorphShape: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const states: Estado[] = p.states ?? [];
  if (states.length < 1 || states.length > 8) throw new Error(`morph: states precisa de 1 a 8 estados (veio ${states.length})`);
  const step: number = p.step ?? 30;
  const loop = p.loop !== false && states.length > 1;
  const seq = loop ? [...states, states[0]] : states;
  const lado = Math.min(L.W - L.l - L.r, L.H - L.t - L.b) * (L.v ? 1.6 : 1.1);
  const t0 = first(p);
  const at = temposMorph(states.length, p.beats.map((_: number, k: number) => bt(p, k)), t0, step, loop);
  const forma = (k: number) => FORMAS[(seq[k].shape ?? (k === seq.length - 1 && loop ? 0 : k)) % FORMAS.length];
  const tinta = (k: number) => TINTAS[seq[k].color ?? ORDEM[(k === seq.length - 1 && loop ? 0 : k) % ORDEM.length]];
  const mola = (k: number) => spring({ frame: f - at[k], fps: 30, config: { damping: 21, stiffness: 150, mass: 0.7 } }); // amortecida: sem passar do alvo
  const prop = (key: keyof Forma) =>
    seq.reduce((v, _, k) => (k === 0 ? forma(0)[key] : v + (forma(k)[key] - forma(k - 1)[key]) * mola(k)), 0);
  const cur = at.reduce((c, a, k) => (f >= a ? k : c), 0);
  const cor = cur === 0 ? tinta(0) : { bg: interpolateColors(mola(cur), [0, 1], [tinta(cur - 1).bg, tinta(cur).bg]), fg: tinta(cur).fg };
  const w = prop("w") * lado;
  const h = prop("h") * lado;
  const r = Math.min(w, h) * Math.min(0.5, prop("r"));
  // entrada da caixa: cresce e assenta (o foco); o resto da cena é mola
  const nasce = ip(f, [t0, t0 + 12], [0, 1], SETTLE); // nasce por escala, sem velocidade: assenta sem passar do alvo
  // a palavra: entra 8 quadros depois da troca (apoio depois do foco), sai em 4 antes da próxima
  const prox = cur + 1 < at.length ? at[cur + 1] : 1e9; // 1e9 = sem próxima troca
  const tin = at[cur] + (cur === 0 ? 4 : 8);
  const sai = prox < 1e9 ? ip(f, [prox - 5, prox - 1], [0, 1], EXIT) : 0;
  const txt = ip(f, [tin, tin + 8], [0, 1]) * (1 - sai);
  const label = seq[cur]?.label ?? "";
  // largura útil na horizontal (o texto fica de pé): a reta que passa pelo centro da caixa girada
  const th = (Math.abs(prop("rot")) % 180) * (Math.PI / 180);
  const corda = Math.min(Math.abs(Math.cos(th)) > 1e-3 ? w / Math.abs(Math.cos(th)) : 1e9, Math.abs(Math.sin(th)) > 1e-3 ? h / Math.abs(Math.sin(th)) : 1e9);
  const fs = fit([label], corda * 0.78, L.v ? 96 : 84, 0.6);
  return (
    <Bg color={C.night}>
      {p.kicker ? (
        <div style={{ position: "absolute", left: L.l, right: L.r, top: L.t + (L.v ? 60 : 10), textAlign: "center", opacity: ip(f, [t0 + 6, t0 + 14], [0, 1]) }}>
          <span style={{ ...LABEL, fontSize: L.v ? 30 : 26, color: C.faint }}>{p.kicker}</span>
        </div>
      ) : null}
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
        <div style={{ width: w, height: h, borderRadius: r, background: cor.bg, transform: `rotate(${prop("rot")}deg) scale(${nasce})`, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <span style={{ ...H1, fontSize: fs, color: cor.fg, opacity: txt, whiteSpace: "nowrap", transform: `rotate(${-prop("rot")}deg) translateY(${(1 - txt) * 18}px)` }}>{label}</span>
        </div>
      </AbsoluteFill>
      <div style={{ position: "absolute", left: L.l, right: L.r, bottom: L.b, display: "flex", justifyContent: "center", gap: 12 }}>
        {states.map((_, k) => (
          <div key={k} style={{ width: 14, height: 14, borderRadius: 7, background: k === cur % states.length ? C.brandOnDark : C.shellLine }} />
        ))}
      </div>
    </Bg>
  );
};

/* ───────────────────────── ranking e comparação lado a lado ───────────────────────── */
// Número na tela só com fonte (SKILL.md, passo 8). Sem fala, o item i entra na batida i·step; com
// fala, na fala i. O foco é o item que entra; os que já entraram esmaecem.

type Valor = { label: string; v: number; prefix?: string; suffix?: string };
const fmt = (n: number) => n.toLocaleString("pt-BR");

// Número que conta quase linear e pousa com SETTLE: a contagem leva `dur` quadros.
const Conta: React.FC<{ it: Valor; f: number; at: number; dur?: number; size: number; color: string }> = ({ it, f, at, dur = 18, size, color }) => (
  <span style={{ display: "inline-flex", alignItems: "baseline", gap: size * 0.06 }}>
    {it.prefix ? <span style={{ ...H1, fontSize: size * 0.6, fontWeight: 800, color }}>{it.prefix}</span> : null}
    <Counter value={it.v} progress={ip(f, [at, at + dur], [0, 1], SETTLE)} size={size} color={color} decimals={decimaisDe(it.v)} />
    {it.suffix ? <span style={{ ...H1, fontSize: size * 0.6, fontWeight: 800, color }}>{it.suffix}</span> : null}
  </span>
);

// props: items [{label, v, prefix?, suffix?}] (2–6; a ordem do ranking sai do v, maior em cima),
// title?, kicker?, step? (frames por posição sem voz, padrão 15), low? (true = menor é melhor).
// Ordena antes de cortar em 6. As posições entram de baixo para cima (temposRanking: sem fala, a
// partir da última); a 1ª entra por último, com antecipação, overshoot de escala, hit-stop e a barra
// de destaque; as outras ficam cinza.
export const Ranking: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const step: number = p.step ?? 15;
  const itens: Valor[] = ordenarRanking(p.items ?? [], !!p.low);
  const n = itens.length;
  const max = maiorValor(itens.map((i) => i.v));
  const t0 = first(p);
  const titulo = p.title ? (L.v ? 220 : 130) : 0;
  const alto = (L.H - L.t - L.b - titulo) / Math.max(n, 1);
  const linha = Math.min(alto * 0.78, L.v ? 190 : 120);
  const larg = L.W - L.l - L.r;
  // colunas: posição, nome, barra e, depois da barra cheia, o número (reservado pelo maior)
  // no 9:16 o nome vai em cima da barra (duas camadas por linha); no 16:9, ao lado
  const barH = linha * (L.v ? 0.3 : 0.42);
  const numW = barH * 0.62 * Math.max(...itens.map((i) => `${i.prefix ?? ""}${fmt(i.v)}${i.suffix ?? ""}`.length), 2);
  const rankW = linha * (L.v ? 0.62 : 0.9);
  const barMax = L.v ? larg - rankW - 24 - numW - 18 : larg * 0.5 - numW - 18;
  const nomeW = L.v ? larg - rankW - 24 : larg - (barMax + numW + 18) - rankW - 48;
  const nome = fit(itens.map((i) => i.label), nomeW, L.v ? 48 : 40);
  // ordem de entrada: do último lugar ao 1º (e = 0 entra primeiro)
  const tr = temposRanking(n, p.beats.map((_: number, k: number) => bt(p, k)), t0, step);
  const entra = (pos: number) => tr[n - 1 - pos];
  return (
    <Bg color={C.paper}>
      {p.title ? (
        <div style={{ position: "absolute", left: L.l, right: L.r, top: L.t }}>
          {p.kicker ? <div style={{ ...LABEL, fontSize: L.v ? 28 : 24, color: C.dim, opacity: ip(f, [t0 + 4, t0 + 12], [0, 1]) }}>{p.kicker}</div> : null}
          <div style={{ ...H1, marginTop: 8, fontSize: fit([p.title], larg, L.v ? 84 : 72), color: C.ink, opacity: ip(f, [t0, t0 + 10], [0, 1]), transform: `translateY(${ip(f, [t0, t0 + 14], [24, 0])}px)` }}>{p.title}</div>
        </div>
      ) : null}
      {itens.map((it, pos) => {
        const a = entra(pos);
        const topo = pos === 0;
        if (f < a - (topo ? 8 : 2)) return null;
        // o 1º: já visível, recua (1 → 0,92 em 4 quadros), estala até 1,12 em 5, congela 3 quadros no
        // pico (hit-stop) e assenta em 1 com SETTLE em 12
        const pico = a + 5;
        const pop = !topo ? 1 : f < a ? ip(f, [a - 4, a], [1, 0.92], ANTIC) : f < pico ? ip(f, [a, pico], [0.92, 1.12]) : ip(hitStop(f, pico, 3), [pico, pico + 12], [1.12, 1], SETTLE);
        const proxima = pos > 0 ? entra(pos - 1) : 1e9;
        const dim = f >= proxima ? 0.35 : 1; // quem já foi dito esmaece (doutrina: 35% ou menos)
        const w = barMax * (it.v / max) * ip(f, [a, a + 18], [0, 1], SETTLE);
        const y = L.t + titulo + pos * alto + (alto - linha) / 2;
        return (
          <div key={it.label} style={{ position: "absolute", left: L.l, width: larg, top: y, height: linha, display: "flex", alignItems: "center", gap: 24, opacity: (topo ? ip(f, [a - 8, a - 5], [0, 1]) : ip(f, [a - 2, a + 4], [0, 1])) * (topo ? 1 : dim), transform: `translateX(${ip(f, [a - 2, a + 10], [-40, 0])}px) scale(${pop})`, transformOrigin: "left center" }}>
            <span style={{ ...H1, fontSize: linha * (L.v ? 0.36 : 0.5), fontWeight: 800, color: topo ? C.brand : C.faint, width: rankW, flexShrink: 0 }}>{pos + 1}º</span>
            <div style={{ flex: 1, display: "flex", flexDirection: L.v ? "column" : "row", alignItems: L.v ? "flex-start" : "center", gap: L.v ? 10 : 24 }}>
              <span style={{ ...H1, fontSize: nome, color: C.ink, width: nomeW, flexShrink: 0, whiteSpace: "nowrap", overflow: "hidden" }}>{it.label}</span>
              <div style={{ flex: 1, display: "flex", alignItems: "center", gap: 18 }}>
                <div style={{ width: w, height: barH, borderRadius: barH * 0.3, background: topo ? C.brand : C.line }} />
                <Conta it={it} f={f} at={a} size={barH} color={topo ? C.ink : C.dim} />
              </div>
            </div>
          </div>
        );
      })}
    </Bg>
  );
};

// props: left {label, v, prefix?, suffix?}, right {...}, title?, kicker?, low? (true = menor é
// melhor), badge? (selo do melhor, padrão "melhor"), step? (padrão 30). Dois lados, lado a lado nos
// dois formatos: a coluna da esquerda cresce na 1ª fala, a da direita na 2ª; depois o melhor
// ganha a cor de dado, o selo aparece e assenta (sem passar do alvo) e o outro esmaece.
export const Versus: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const lados: Valor[] = [p.left, p.right].filter(Boolean);
  const step: number = p.step ?? 30;
  const t0 = first(p);
  const ats = [t0 + 6, p.beats.length > 1 ? bt(p, 1) - 4 : t0 + 6 + step];
  const veredito = p.beats.length > 2 ? bt(p, 2) - 4 : ats[1] + 30;
  const melhor = lados.length === 2 ? ((p.low ? lados[0].v <= lados[1].v : lados[0].v >= lados[1].v) ? 0 : 1) : 0;
  const max = maiorValor(lados.map((l) => l.v));
  const larg = L.W - L.l - L.r;
  const titulo = p.title ? (L.v ? 240 : 140) : 0;
  const colW = (larg - (L.v ? 40 : 120)) / 2;
  const base = L.H - L.b - (L.v ? 120 : 90);
  const barMax = base - (L.t + titulo) - (L.v ? 260 : 190);
  // o número cabe na coluna (no 9:16 ela tem ~385 px): "R$ 1.250.000" encolhe, "6 min" fica no corpo cheio
  const num = Math.min(...lados.map((l) => corpoNumero(l, colW, L.v ? 104 : 96)));
  const nome = fit(lados.map((l) => l.label), colW, L.v ? 46 : 42);
  return (
    <Bg color={C.night}>
      {p.title ? (
        <div style={{ position: "absolute", left: L.l, right: L.r, top: L.t, textAlign: "center" }}>
          {p.kicker ? <div style={{ ...LABEL, fontSize: L.v ? 28 : 24, color: C.faint, opacity: ip(f, [t0 + 4, t0 + 12], [0, 1]) }}>{p.kicker}</div> : null}
          <div style={{ ...H1, marginTop: 8, fontSize: fit([p.title], larg, L.v ? 84 : 72), color: C.white, opacity: ip(f, [t0, t0 + 10], [0, 1]), transform: `translateY(${ip(f, [t0, t0 + 14], [24, 0])}px)` }}>{p.title}</div>
        </div>
      ) : null}
      {lados.map((it, i) => {
        const a = ats[i];
        const ganha = i === melhor && f >= veredito;
        const perde = i !== melhor && f >= veredito;
        const h = barMax * (it.v / max) * ip(f, [a, a + 20], [0, 1], SETTLE);
        const x = L.l + i * (colW + (L.v ? 40 : 120));
        const cor = ganha ? C.brandOnDark : "rgba(255,255,255,0.22)";
        const sel = ip(f, [veredito, veredito + 10], [0, 1], SETTLE); // o selo aparece (não voou): assenta sem passar
        return (
          <div key={i} style={{ position: "absolute", left: x, width: colW, top: 0, height: L.H, opacity: (f >= a - 2 ? 1 : 0) * (perde ? 1 - 0.65 * ip(f, [veredito, veredito + 8], [0, 1]) : 1) }}>
            <div style={{ position: "absolute", left: 0, right: 0, top: base - h - num * 1.25, textAlign: "center", opacity: ip(f, [a, a + 6], [0, 1]) }}>
              <Conta it={it} f={f} at={a} dur={20} size={num} color={C.white} />
            </div>
            <div style={{ position: "absolute", left: colW * 0.18, right: colW * 0.18, top: base - h, height: h, borderRadius: "18px 18px 4px 4px", background: cor }} />
            <div style={{ position: "absolute", left: 0, right: 0, top: base + 24, textAlign: "center", opacity: ip(f, [a + 6, a + 14], [0, 1]) }}>
              <span style={{ ...H1, fontSize: nome, color: C.white }}>{it.label}</span>
            </div>
            {i === melhor && f >= veredito ? (
              <div style={{ position: "absolute", left: 0, right: 0, top: base - h - num * 1.25 - (L.v ? 86 : 76), textAlign: "center" }}>
                <span style={{ display: "inline-block", background: C.white, color: C.ink, borderRadius: 100, padding: "12px 30px", fontSize: L.v ? 32 : 28, fontWeight: 800, transform: `scale(${0.9 + 0.1 * sel})`, opacity: Math.min(1, sel * 3) }}>{p.badge ?? "melhor"}</span>
              </div>
            ) : null}
          </div>
        );
      })}
      <div style={{ position: "absolute", left: L.l, right: L.r, top: base, height: 2, background: "rgba(255,255,255,0.25)", transform: `scaleX(${ip(f, [t0, t0 + 14], [0, 1], EASE_INOUT)})` }} />
    </Bg>
  );
};
