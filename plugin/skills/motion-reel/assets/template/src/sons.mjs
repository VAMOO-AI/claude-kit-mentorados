// Sons de cada cena do Film (C6): a cena declara os efeitos dela, nos tempos das mesmas funções
// que a animação usa (tempos.mjs), e o scripts/track_cinema.py lê daqui pelo scripts/sons.mjs.
// Acabou o espelho à mão em Python (SFX_BY_TYPE): mudou o tempo de uma animação, mude o som aqui,
// ao lado; cena nova registrada no SCENES precisa de entrada aqui (vazia vale), o teste confere.
// JavaScript puro (.mjs) para o Node rodar sem compilar; tipos em sons.d.mts.
//
// Cada som: {f, sfx, g, rep?, every?, impacto?}. `f` é o frame local (0 = corte da cena). Por
// padrão o som COMEÇA em f; com `impacto: true` o PICO dele cai em f (o track_cinema mede o pico
// de cada WAV: whoosh e rise têm o pico centenas de ms depois do início). Use impacto no quadro do
// contato (clique, pouso, golpe), não onde o som é uma entrada.
import { DESK_ENVIA, RANKING_PICO, bt, first, hitAt, pilulasCta, temposMorph, temposRanking, trocaSwap } from "./tempos.mjs";

const falas = (s) => s.beats.map((_, k) => bt(s, k));
const vezes = (n, fn) => Array.from({ length: Math.max(0, n) }, (_, i) => fn(i)).flat();
const som = (f, sfx, g = 0.5, extra = {}) => ({ f, sfx, g, ...extra });

export const SONS = {
  desk: (s, p) => {
    const reply = bt(s, 0, 0.5);
    return [
      som(-12, "soft-click", 0.12, { rep: 12, every: 3 }), // digitando o pedido
      ...(p.click ? [som(DESK_ENVIA - 1, "soft-click", 0.6, { impacto: true })] : []), // o cursor toca o enviar
      som(DESK_ENVIA, "dry-pop", 0.45), // enviou
      ...(p.files ? [som(reply - 14, "paper-tap", 0.35)] : []), // card de edição
      som(reply, "soft-chime", 0.45), // resposta
    ];
  },
  numbers: (s, p) =>
    vezes((p.items ?? []).length, (i) => {
      const f0 = i === 0 ? first(s) : bt(s, i) - 4;
      return [som(f0, "dry-pop", 0.55), som(f0 + 2, "soft-click", 0.12, { rep: 6, every: 3 })];
    }),
  commands: (s, p) => {
    const A = first(s);
    return [
      ...vezes((p.cmds ?? []).length, (i) => [som(A + 6 + i * 30, "soft-click", 0.1, { rep: 7, every: 2 }), som(A + 6 + i * 30 + 16, "dry-pop", 0.45)]),
      ...(p.badge && s.beats.length > 1 ? [som(bt(s, 1) - 2, "dry-pop", 0.6)] : []),
    ];
  },
  card: (s, p) => {
    const A = first(s);
    return [
      ...(p.cmd && p.motif ? [som(A - 10, "soft-click", 0.1, { rep: 8, every: 3 }), som(A + 16, "dry-pop", 0.4)] : []),
      ...(p.before ? [som(bt(s, 0, 0.45) + 8, "paper-tap", 0.45)] : []),
      ...(p.proof ? [som(bt(s, 0, 0.7), "dry-pop", 0.45)] : []),
    ];
  },
  cta: (s, p) => {
    const { p1, p2 } = pilulasCta(s); // as pílulas entram aqui (a cena usa a mesma conta)
    return [som(p1, "dry-pop", 0.55), ...(p.q2 && p.pill2 ? [som(p2, "dry-pop", 0.55)] : [])];
  },
  outro: () => [som(26, "soft-chime", 0.6), som(26, "impact", 0.5, { sintese: 0.9 })],
  launch: (s, p) => {
    const words = p.words ?? [];
    const step = p.step ?? 15;
    const voz = s.beats.length > 0;
    const reveal = voz && s.beats.length > 1 ? bt(s, 1) - 4 : (words.length + 1) * step;
    return [
      ...vezes(words.length, (i) => {
        const f0 = i === 0 ? first(s) : voz ? bt(s, 0, i / words.length) - 4 : i * step;
        return [som(f0, "low-hit", 0.5), som(f0, "dry-pop", 0.25)];
      }),
      som(reveal - 12, "short-rise", 0.4),
      som(reveal, "soft-chime", 0.55),
      som(reveal, "impact", 0.45, { sintese: 0.8 }),
    ];
  },
  beats: (s, p) => vezes((p.items ?? []).length, (i) => {
    const f0 = hitAt(s, i, p.step ?? 30);
    return [som(f0, "low-hit", 0.4), som(f0, "paper-tap", 0.35)];
  }),
  glass: (s, p) => vezes((p.cards ?? []).length, (i) => {
    const f0 = hitAt(s, i, p.step ?? 15) + (i === 0 ? 4 : 0);
    return [som(f0 - 2, "soft-whoosh", 0.35), som(f0 + 6, "dry-pop", 0.4)];
  }),
  logo3d: (s, p) => {
    const settle = p.settle ?? (s.beats.length ? bt(s, 0, 0.5) : 60);
    return [som(first(s), "soft-whoosh", 0.5), som(settle, "low-hit", 0.5), som(settle + 4, "soft-chime", 0.5)];
  },
  // Apresentação pessoal (scenes-apresentacao.tsx) e lançamento de app (scenes-app.tsx).
  pillname: (s) => {
    const A = first(s);
    return [som(A, "soft-whoosh", 0.4), som(A + 24, "dry-pop", 0.45), som(A + 36, "soft-chime", 0.45)]; // linha, pílula no anel, letras
  },
  orbit: (s) => {
    const A = first(s);
    return [som(A, "soft-whoosh", 0.45), som(s.beats.length ? bt(s, 0) - 4 : A + 26, "paper-tap", 0.4)];
  },
  highlights: (s, p) => vezes((p.items ?? []).length, (i) => {
    const f0 = hitAt(s, i, p.step ?? 30) + (i === 0 ? 10 : 0);
    return [som(f0, "dry-pop", 0.45), som(f0 + 2, "soft-click", 0.1, { rep: 6, every: 4 })];
  }),
  follow: (s, p) => {
    const click = p.click ?? (s.beats.length > 1 ? bt(s, 1) : 48);
    return [som(click, "soft-click", 0.7), som(click + 3, "soft-chime", 0.5)];
  },
  appline: (s, p) => {
    const n = String(p.line ?? "").split(/\s+/).filter(Boolean).length;
    const A = first(s);
    const gap = s.beats.length ? Math.max(2, Math.floor((bt(s, 0, 0.6) - A) / Math.max(1, n))) : 4;
    return [
      ...vezes(Math.min(n, 8), (i) => [som(A + i * gap, "soft-click", 0.12)]),
      ...(p.ui ? [som(s.beats.length ? bt(s, 0, 0.3) : A + n * gap + 6, "soft-whoosh", 0.35)] : []),
    ];
  },
  assemble: (s, p) => {
    const land = p.land ?? (s.beats.length ? bt(s, 0, 0.5) : 46);
    return [som(first(s), "short-rise", 0.35), som(land, "low-hit", 0.5), som(land + 4, "soft-chime", 0.5)];
  },
  // Cenas avulsas (scenes-extras.tsx, scenes-mapa.tsx).
  swap: (s, p) => {
    const S = trocaSwap(s, p);
    return [som(first(s), "paper-tap", 0.3), som(S - 10, "soft-whoosh", 0.45), som(S + 18, "dry-pop", 0.4)]; // A sobe, o portal abre, as letras pousam
  },
  morph: (s, p) => {
    const trocas = temposMorph((p.states ?? []).length, falas(s), first(s), p.step ?? 30, (p.loop ?? true) !== false);
    return trocas.flatMap((f0, k) => [som(f0 - 1, k ? "soft-whoosh" : "dry-pop", 0.3), som(f0 + 8, "paper-tap", 0.2)]);
  },
  map: (s, p) => {
    const A = first(s);
    const n = (p.route ?? []).slice(0, 6).length;
    const tR = s.beats.length > 1 ? bt(s, 1) - 4 : 30;
    const seg = p.seg ?? 24;
    return [
      som(A, "soft-whoosh", 0.35),
      ...(p.region ? [som(A + 10, "paper-tap", 0.35)] : []),
      ...vezes(n, (j) => (j === n - 1 ? [som(tR + j * seg - 1, "soft-chime", 0.45)] : [som(tR + j * seg, "dry-pop", 0.3)])),
    ];
  },
  ranking: (s, p) => {
    const n = Math.min((p.items ?? []).length, 6);
    const entradas = temposRanking(n, falas(s), first(s), p.step ?? 15);
    return entradas.flatMap((f0, e) =>
      e === n - 1
        ? [som(f0 + RANKING_PICO, "low-hit", 0.45, { impacto: true }), som(f0 + 20, "soft-chime", 0.4)] // o 1º: golpe no pico do overshoot, pouso
        : [som(f0, "dry-pop", 0.3), som(f0 + 2, "soft-click", 0.08, { rep: 5, every: 3 })],
    );
  },
  versus: (s, p) => {
    const A = first(s);
    const step = p.step ?? 30;
    const b1 = s.beats.length > 1 ? bt(s, 1) - 4 : A + 6 + step;
    const ver = s.beats.length > 2 ? bt(s, 2) - 4 : b1 + 30;
    return [
      ...[A + 6, b1].flatMap((f0) => [som(f0, "soft-whoosh", 0.3), som(f0 + 2, "soft-click", 0.08, { rep: 6, every: 3 })]),
      som(ver - 1, "dry-pop", 0.5),
      som(ver + 4, "soft-chime", 0.4), // o selo do melhor
    ];
  },
  // Sem som próprio: só o da transição e os "cues" do film.json.
  statement: () => [],
  title: () => [],
  chapter: () => [],
};

// Sons de toda a timeline: [{cena (índice), f, sfx, g, rep, every, impacto, sintese?}].
export function sonsDaTimeline(tl) {
  return tl.scenes.flatMap((s, i) => {
    const fn = SONS[s.type];
    if (!fn) return [];
    return fn(s, s.props ?? {}).map((x) => ({ cena: i, rep: 1, every: 0, impacto: false, ...x }));
  });
}
