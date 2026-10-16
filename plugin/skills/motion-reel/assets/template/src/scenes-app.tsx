// Cenas do preset de lançamento de app (presets/lancamento-app.json): minimalista, headline grande
// que entra palavra por palavra com rastro (echo trail), um mockup de UI por frase (os motifs) e
// as peças das telas que se juntam e formam o logo. Mesmo molde do film-scenes.tsx.
// O som de cada uma está no SFX_BY_TYPE do track_cinema.py: mudou um tempo aqui, mude lá.
import React from "react";
import { AbsoluteFill, Img, continueRender, delayRender, random, staticFile } from "remotion";
import { Motif } from "./motifs";
import { BRAND, Bg, C, EASE, EASE_INOUT, ip, useF } from "./lib";
import { FilmCtx, H1, LABEL, type SP, bt, emWords, first, fit, plain, useImgRatio, useL } from "./film-base";

// Rastro: a peça entra com `n` ecos atrás, cada um `lag` frames mais lento e mais apagado; os ecos
// somem quando ela assenta. Tudo determinístico (só depende de f).
const Echo: React.FC<{ f: number; at: number; dur?: number; dy?: number; dx?: number; n?: number; lag?: number; color?: string; children: React.ReactNode }> = ({ f, at, dur = 14, dy = 90, dx = 0, n = 2, lag = 3, color, children }) => {
  const pos = (k: number) => ip(f, [at + k * lag, at + k * lag + dur], [1, 0], EASE);
  const settled = ip(f, [at + dur, at + dur + n * lag + 4], [1, 0]);
  return (
    <span style={{ position: "relative", display: "inline-block" }}>
      {settled > 0
        ? Array.from({ length: n }, (_, j) => {
            const k = n - j;
            const o = pos(k);
            return (
              <span key={k} style={{ position: "absolute", left: 0, top: 0, whiteSpace: "pre", color, opacity: (0.4 / k) * settled * (f >= at ? 1 : 0), transform: `translate(${o * dx}px, ${o * dy}px)` }}>
                {children}
              </span>
            );
          })
        : null}
      <span style={{ display: "inline-block", whiteSpace: "pre", opacity: ip(f, [at, at + 4], [0, 1]), transform: `translate(${pos(0) * dx}px, ${pos(0) * dy}px)` }}>{children}</span>
    </span>
  );
};

/* ───────────────────────── frase + mockup de UI (uma por cena) ───────────────────────── */
// A headline entra palavra por palavra com rastro; *palavra* sai no laranja de conteúdo (C.hot). Embaixo (à direita
// no 16:9) o mockup da UI que ilustra a frase, um motif de motifs.tsx, entra com rastro também.
// props: line (com *palavra*), ui ({kind, ...props do motif}), n?, total?, kicker?, dark?
export const AppLine: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const dark: boolean = p.dark ?? false;
  const bg = dark ? C.night : C.paper;
  const fg = dark ? C.white : C.ink;
  const acc = dark ? C.brandOnDark : C.brand;
  const t0 = first(p);
  const words = emWords(p.line ?? "");
  const colW = L.v ? L.W - L.l - L.r : (L.W - L.l - L.r) * 0.48;
  const fs = fit([plain(p.line ?? "")], colW * (L.v ? 2.3 : 2.4), L.v ? 112 : 104, 0.6);
  const gap = p.beats.length ? Math.max(2, Math.floor((bt(p, 0, 0.6) - t0) / Math.max(1, words.length))) : 4;
  const uiAt = p.beats.length ? bt(p, 0, 0.3) : t0 + words.length * gap + 6;
  const sc = L.v ? (L.W - L.l - L.r) / 680 : Math.min(1.25, ((L.W - L.l - L.r) * 0.5) / 680);
  const n: number = p.n ?? 0;
  const total: number = p.total ?? 0;
  return (
    <Bg color={bg}>
      <AbsoluteFill style={{ padding: `${L.t}px ${L.r}px ${L.b}px ${L.l}px`, flexDirection: L.v ? "column" : "row", alignItems: L.v ? "flex-start" : "center", justifyContent: L.v ? "center" : "space-between", gap: L.v ? 80 : 40 }}>
        <div style={{ width: colW }}>
          {n ? (
            <div style={{ ...LABEL, fontSize: 24, color: acc, marginBottom: 26, opacity: ip(f, [t0, t0 + 8], [0, 1]) }}>
              {String(n).padStart(2, "0")}{total ? ` / ${String(total).padStart(2, "0")}` : ""}{p.kicker ? `  ·  ${p.kicker}` : ""}
            </div>
          ) : null}
          <div style={{ display: "flex", flexWrap: "wrap", columnGap: fs * 0.26, rowGap: fs * 0.02 }}>
            {words.map((w, i) => (
              <span key={i} style={{ ...H1, fontSize: fs, color: w.em ? C.hot : fg }}>
                <Echo f={f} at={t0 + i * gap} dy={fs * 0.7} color={acc}>{w.t}</Echo>
              </span>
            ))}
          </div>
        </div>
        {p.ui ? (
          <div style={{ width: 680 * sc, height: 440 * sc, flexShrink: 0, position: "relative" }}>
            {[2, 1, 0].map((k) => {
              const o = ip(f, [uiAt + k * 3, uiAt + k * 3 + 16], [1, 0], EASE);
              const ghost = k > 0;
              const vis = ghost ? (0.22 / k) * ip(f, [uiAt + 16, uiAt + 26], [1, 0]) * (f >= uiAt ? 1 : 0) : ip(f, [uiAt, uiAt + 6], [0, 1]);
              if (vis <= 0.001) return null;
              return (
                <div key={k} style={{ position: "absolute", left: 0, top: 0, transformOrigin: "top left", transform: `translateY(${o * 160}px) scale(${sc})`, opacity: vis }}>
                  {ghost ? (
                    <div style={{ width: 680, height: 440, borderRadius: 28, border: `3px solid ${acc}` }} />
                  ) : (
                    <Motif {...p.ui} f={f} a={uiAt + 8} dark={dark} />
                  )}
                </div>
              );
            })}
          </div>
        ) : null}
      </AbsoluteFill>
      {total > 1 ? (
        <div style={{ position: "absolute", left: L.l, right: L.r, bottom: L.v ? L.b - 40 : 56, display: "flex", gap: 8 }}>
          {Array.from({ length: total }, (_, i) => (
            <div key={i} style={{ flex: 1, height: i + 1 === n ? 8 : 4, alignSelf: "flex-end", borderRadius: 4, background: i + 1 === n ? acc : i + 1 < n ? (dark ? "rgba(255,255,255,0.45)" : C.faint) : dark ? C.shellLine : C.line }} />
          ))}
        </div>
      ) : null}
    </Bg>
  );
};

// Quais células de uma grade cols×rows o PNG cobre (alfa > 40% em boa parte da célula). Lê o
// arquivo num canvas e segura o render até terminar: as peças só voam para onde há logo.
const useLogoCells = (src: string, cols: number, rows: number) => {
  const [cells, setCells] = React.useState<boolean[] | null>(null);
  const [handle] = React.useState(() => delayRender(`cells ${src}`));
  React.useEffect(() => {
    const img = new Image();
    const done = (v: boolean[]) => {
      setCells(v);
      continueRender(handle);
    };
    img.onload = () => {
      const cv = document.createElement("canvas");
      cv.width = cols * 8;
      cv.height = rows * 8;
      const ctx = cv.getContext("2d");
      if (!ctx) return done(Array(cols * rows).fill(true));
      ctx.drawImage(img, 0, 0, cv.width, cv.height);
      const px = ctx.getImageData(0, 0, cv.width, cv.height).data;
      const out: boolean[] = [];
      for (let r = 0; r < rows; r++)
        for (let c = 0; c < cols; c++) {
          let on = 0;
          for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) if (px[((r * 8 + y) * cv.width + c * 8 + x) * 4 + 3] > 102) on++;
          out.push(on >= 20);
        }
      done(out);
    };
    img.onerror = () => done(Array(cols * rows).fill(true));
    img.src = src;
  }, [src, cols, rows, handle]);
  return cells;
};

/* ───────────────────────── peças que se juntam e formam o logo ───────────────────────── */
// Peças das telas (quadrados e pílulas nas cores da marca) voam de fora, giram e pousam numa grade
// com a forma do logo; o PNG real assume no lugar, nome e tagline sobem. Logo nunca é redesenhado:
// a forma vem do alfa do PNG. Se for a última cena, some no fim.
// props: logo? (padrão "marca.png"), name? (padrão BRAND), tag?, cols? (padrão 26), land? (frame em que tudo pousou, padrão 46)
export const Assemble: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const { tl, idx } = React.useContext(FilmCtx);
  const src = staticFile(p.logo ?? "marca.png");
  const ratio = useImgRatio(src);
  const lw = Math.min(L.v ? 760 : 820, (L.v ? 420 : 380) * ratio);
  const lh = lw / ratio;
  const cols: number = p.cols ?? 26;
  const cell = lw / cols;
  const rows = Math.max(1, Math.round(lh / cell));
  const cells = useLogoCells(src, cols, rows);
  const t0 = first(p);
  const land: number = p.land ?? (p.beats.length ? bt(p, 0, 0.5) : 46);
  const cx = L.W / 2;
  const cy = L.H * (L.v ? 0.42 : 0.42);
  const x0 = cx - lw / 2;
  const y0 = cy - lh / 2;
  const swap = ip(f, [land, land + 10], [0, 1]);
  const bump = 1 + 0.06 * Math.max(0, 1 - Math.abs(f - land - 4) / 8);
  const last = tl ? idx === tl.scenes.length - 1 : false;
  const fade = last ? ip(f, [p.len - 20, p.len], [1, 0]) : 1;
  const pal = [C.brand, C.brandOnDark, C.accentFill, C.white];
  const name: string = p.name ?? BRAND;
  return (
    <Bg color={C.night}>
      <AbsoluteFill style={{ opacity: fade }}>
        <AbsoluteFill style={{ background: `radial-gradient(ellipse ${L.v ? 70 : 45}% 34% at 50% ${(cy / L.H) * 100}%, rgba(0,125,255,${0.2 * swap}), transparent 70%)` }} />
        <div style={{ position: "absolute", left: 0, top: 0, width: L.W, height: L.H, opacity: 1 - swap, transform: `scale(${bump})`, transformOrigin: `${cx}px ${cy}px` }}>
          {(cells ?? []).map((on, i) => {
            if (!on) return null;
            const c = i % cols;
            const r = Math.floor(i / cols);
            const delay = Math.floor(random(`as-d${i}`) * 18);
            const start = t0 + delay;
            const end = Math.max(start + 10, land - 2 - Math.floor(random(`as-e${i}`) * 6));
            const q = ip(f, [start, end], [0, 1], EASE_INOUT);
            const ang = random(`as-a${i}`) * Math.PI * 2;
            const dist = Math.hypot(L.W, L.H) * (0.45 + 0.4 * random(`as-r${i}`));
            const fx = cx + Math.cos(ang) * dist;
            const fy = cy + Math.sin(ang) * dist;
            const tx = x0 + c * cell;
            const ty = y0 + r * cell;
            const x = fx + (tx - fx) * q;
            const y = fy + (ty - fy) * q;
            const rot = (1 - q) * (random(`as-t${i}`) - 0.5) * 540;
            const pill = random(`as-k${i}`) < 0.3;
            const s = cell * (1 + (1 - q) * (pill ? 1.6 : 1.1));
            return (
              <div key={i} style={{ position: "absolute", left: x, top: y, width: s * (pill ? 1.8 - 0.8 * ip(q, [0.8, 1], [0, 1]) : 1), height: s, borderRadius: pill ? s * (1 - 0.78 * ip(q, [0.8, 1], [0, 1])) : cell * 0.22, background: pal[i % pal.length], transform: `rotate(${rot}deg) scale(${q >= 1 ? 0.92 : 1})`, opacity: f < start ? 0 : 1 }} />
            );
          })}
        </div>
        <div style={{ position: "absolute", left: x0, top: y0, width: lw, opacity: swap, transform: `scale(${bump})` }}>
          <Img src={src} style={{ width: lw, display: "block" }} />
        </div>
        <div style={{ position: "absolute", left: L.l, right: L.r, top: cy + lh / 2 + (L.v ? 90 : 60), textAlign: "center" }}>
          <div style={{ overflow: "hidden", display: "inline-block" }}>
            <div style={{ ...H1, fontSize: fit([name], L.W - L.l - L.r, L.v ? 104 : 96), color: C.white, transform: `translateY(${ip(f, [land + 6, land + 20], [110, 0])}%)` }}>{name}</div>
          </div>
          <br />
          {p.tag ? (
            <div style={{ overflow: "hidden", display: "inline-block", marginTop: 14 }}>
              <div style={{ fontSize: L.v ? 44 : 40, fontWeight: 500, color: C.faint, letterSpacing: "-0.02em", transform: `translateY(${ip(f, [land + 14, land + 28], [110, 0])}%)` }}>{p.tag}</div>
            </div>
          ) : null}
        </div>
      </AbsoluteFill>
    </Bg>
  );
};
