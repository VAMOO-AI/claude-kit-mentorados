// Cenas do preset de apresentação pessoal (presets/apresentacao.json): fundo escuro alternando com
// a cor de destaque, tipografia pesada com UMA palavra por frase em itálico serifado colorido
// (*palavra* no texto) e número que conta. Mesmo molde do film-scenes.tsx: useF, useL, bt, first.
// O som de cada uma está no SFX_BY_TYPE do track_cinema.py: mudou um tempo aqui, mude lá.
import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import { Bg, C, Counter, EASE_INOUT, SERIF, ip, useF } from "./lib";
import { FilmCtx, H1, LABEL, type SP, type Word, bt, emWords, first, fit, hitAt, plain, useL } from "./film-base";

// Palavra marcada: itálico serifado, peso normal; laranja (C.hot) no escuro, night sobre o azul.
const emStyle = (color: string): React.CSSProperties => ({ fontFamily: SERIF, fontStyle: "italic", fontWeight: 400, letterSpacing: "-0.01em", color });

// Frase palavra a palavra: cada palavra sobe da máscara, `gap` frames depois da anterior.
const Phrase: React.FC<{ words: Word[]; f: number; at: number; gap?: number; fs: number; color: string; em: string; align?: "left" | "center" }> = ({ words, f, at, gap = 3, fs, color, em, align = "left" }) => (
  <div style={{ display: "flex", flexWrap: "wrap", justifyContent: align === "center" ? "center" : "flex-start", columnGap: fs * 0.26 }}>
    {words.map((w, i) => {
      const t = ip(f, [at + i * gap, at + i * gap + 14], [0, 1]);
      return (
        <span key={i} style={{ display: "inline-block", overflow: "hidden", paddingBottom: fs * 0.12, marginBottom: -fs * 0.12 }}>
          <span style={{ ...H1, display: "inline-block", fontSize: w.em ? fs * 1.08 : fs, transform: `translateY(${(1 - t) * 110}%)`, ...(w.em ? emStyle(em) : { color }) }}>{w.t}</span>
        </span>
      );
    })}
  </div>
);

// Foto em círculo; sem foto, as iniciais do nome. Sem `photo` nada de <Img>: arquivo ausente
// derruba o render (a galeria e o projeto novo não têm foto).
const Portrait: React.FC<{ photo?: string; name?: string; size: number; bg: string; fg: string; ring?: string }> = ({ photo, name, size, bg, fg, ring }) => {
  const ini = (name ?? "")
    .split(/\s+/)
    .filter(Boolean)
    .map((s) => s[0])
    .slice(0, 2)
    .join("")
    .toUpperCase();
  return (
    <div style={{ width: size, height: size, borderRadius: "50%", overflow: "hidden", background: bg, boxShadow: ring ? `0 0 0 ${Math.round(size * 0.025)}px ${ring}` : undefined, display: "flex", alignItems: "center", justifyContent: "center" }}>
      {photo ? (
        <Img src={staticFile(photo)} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
      ) : (
        <span style={{ ...H1, fontSize: size * 0.4, color: fg, letterSpacing: "-0.02em" }}>{ini}</span>
      )}
    </div>
  );
};

// Última cena da peça some no fim (como o logo3d).
const useOutFade = (len: number) => {
  const f = useF();
  const { tl, idx } = React.useContext(FilmCtx);
  const last = tl ? idx === tl.scenes.length - 1 : false;
  return last ? ip(f, [len - 20, len], [1, 0]) : 1;
};

/* ───────────────────────── linha → pílula → o "O" do nome ───────────────────────── */
// Uma linha corta a tela, engrossa até virar pílula e encolhe num anel: o primeiro "o" do nome.
// As outras letras nascem do anel para fora; cargo e rótulo depois. Nome sem "o": o anel abre o nome.
// props: name, role?, kicker?
export const PillName: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const name: string = p.name ?? "";
  const chars = name.split("");
  const oi = chars.findIndex((c) => c === "o" || c === "O");
  const low = oi >= 0 && chars[oi] === "o";
  // sem "o" no nome o anel entra antes dele e ocupa ~0,88 do corpo (anel + margem): sai da largura
  const fs0 = fit([name], L.W - L.l - L.r, L.v ? 190 : 230, 0.66);
  const fs = oi >= 0 ? fs0 : Math.floor((fs0 * (L.W - L.l - L.r)) / (L.W - L.l - L.r + 0.88 * fs0));
  const ringH = fs * (low ? 0.52 : 0.72);
  const ringW = fs * (low ? 0.5 : 0.66);
  const th = fs * 0.12;
  const slotW = ringW + fs * 0.04;
  const t0 = first(p);
  const lineW = ip(f, [t0, t0 + 14], [0, L.W * 0.9], EASE_INOUT);
  const pill = ip(f, [t0 + 14, t0 + 24], [0, 1], EASE_INOUT);
  const shrink = ip(f, [t0 + 24, t0 + 36], [0, 1], EASE_INOUT);
  const hole = ip(f, [t0 + 32, t0 + 40], [0, 1], EASE_INOUT);
  const w = shrink > 0 ? L.W * 0.62 + (ringW - L.W * 0.62) * shrink : lineW * (1 - 0.31 * pill);
  const h = 6 + (fs * 0.34 - 6) * pill + (ringH - fs * 0.34) * shrink;
  const lettersAt = t0 + 36;
  const roleAt = p.beats.length ? bt(p, 0, 0.5) : lettersAt + 16;
  const ring = (
    <div style={{ position: "relative", display: "inline-block", width: slotW, height: fs * 1.04 }}>
      <div style={{ position: "absolute", left: "50%", top: low ? "60%" : "52%", width: w, height: h, transform: "translate(-50%, -50%)", borderRadius: 999, background: C.hot }}>
        <div style={{ position: "absolute", left: "50%", top: "50%", width: (ringW - 2 * th) * hole, height: (ringH - 2 * th) * hole, transform: "translate(-50%, -50%)", borderRadius: 999, background: C.night }} />
      </div>
    </div>
  );
  const slot = oi >= 0 ? oi : -1;
  return (
    <Bg color={C.night}>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column", paddingLeft: L.l, paddingRight: L.r }}>
        {p.kicker ? (
          <div style={{ ...LABEL, fontSize: 26, color: C.brandOnDark, marginBottom: 24, opacity: ip(f, [roleAt - 6, roleAt + 4], [0, 1]) }}>{p.kicker}</div>
        ) : null}
        <div style={{ display: "flex", alignItems: "center", whiteSpace: "pre" }}>
          {slot < 0 ? <span style={{ marginRight: fs * 0.18 }}>{ring}</span> : null}
          {chars.map((ch, i) => {
            if (i === slot) return <React.Fragment key={i}>{ring}</React.Fragment>;
            const d = Math.abs(i - (slot < 0 ? -1 : slot));
            const t = ip(f, [lettersAt + d * 2, lettersAt + d * 2 + 12], [0, 1]);
            return (
              <span key={i} style={{ ...H1, fontSize: fs, color: C.white, display: "inline-block", opacity: t, transform: `translateX(${(1 - t) * (i < slot ? 40 : -40)}px) scale(${0.7 + 0.3 * t})` }}>
                {ch}
              </span>
            );
          })}
        </div>
        {p.role ? (
          <div style={{ marginTop: L.v ? 36 : 28, overflow: "hidden" }}>
            <div style={{ transform: `translateY(${ip(f, [roleAt, roleAt + 14], [110, 0])}%)`, fontSize: L.v ? 48 : 44, fontWeight: 500, color: C.faint, letterSpacing: "-0.02em", textAlign: "center" }}>{p.role}</div>
          </div>
        ) : null}
      </AbsoluteFill>
    </Bg>
  );
};

/* ───────────────────────── retrato com texto em órbita + frase de impacto ───────────────────────── */
// A foto abre num círculo; um texto gira em volta dela; a frase entra palavra a palavra com a
// palavra *marcada* em itálico serifado. Fundo na cor de destaque.
// props: photo? (arquivo em public/), name? (iniciais sem foto), ring (texto da órbita), quote (com *palavra*)
export const Orbit: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const uid = React.useId().replace(/[^a-zA-Z0-9]/g, "");
  const t0 = first(p);
  const R = L.v ? 240 : 190;
  const RT = R + (L.v ? 62 : 52);
  const cx = L.v ? L.W / 2 : L.l + RT + 40;
  const cy = L.v ? L.t + 120 + RT : L.H / 2;
  const open = ip(f, [t0, t0 + 18], [0, 1], EASE_INOUT);
  const ringTxt = `${plain(p.ring ?? "")}  •  `;
  const reps = Math.max(1, Math.round((2 * Math.PI * RT) / (ringTxt.length * 0.62 * 30)));
  const quoteAt = p.beats.length ? bt(p, 0) - 4 : t0 + 26;
  const qW = L.v ? L.W - L.l - L.r : L.W - (cx + RT + 80) - L.r;
  const words = emWords(p.quote ?? "");
  const qfs = fit(words.map((w) => w.t), qW, L.v ? 104 : 84, 0.6);
  return (
    <Bg color={C.accentFill}>
      <svg width={L.W} height={L.H} style={{ position: "absolute", opacity: ip(f, [t0 + 6, t0 + 18], [0, 1]) }}>
        <defs>
          <path id={`${uid}o`} d={`M ${cx - RT} ${cy} a ${RT} ${RT} 0 1 1 ${2 * RT} 0 a ${RT} ${RT} 0 1 1 ${-2 * RT} 0`} />
        </defs>
        <g transform={`rotate(${-90 + f * 0.9} ${cx} ${cy})`}>
          <text style={{ ...LABEL, fontSize: 30, letterSpacing: "0.22em" }} fill={C.white}>
            <textPath href={`#${uid}o`}>{ringTxt.repeat(reps)}</textPath>
          </text>
        </g>
      </svg>
      <div style={{ position: "absolute", left: cx - R, top: cy - R, clipPath: `circle(${open * 51}% at 50% 50%)`, transform: `scale(${1.15 - 0.15 * open})` }}>
        <Portrait photo={p.photo} name={p.name} size={2 * R} bg={C.night} fg={C.white} ring={C.white} />
      </div>
      <div style={{ position: "absolute", left: L.v ? L.l : cx + RT + 80, width: qW, top: L.v ? cy + RT + 90 : cy - qfs * 1.6 }}>
        <Phrase words={words} f={f} at={quoteAt} fs={qfs} color={C.white} em={C.night} />
      </div>
    </Bg>
  );
};

/* ───────────────────────── destaques com infográfico (count-up) ───────────────────────── */
// Um destaque por batida (ou por fala): anel ou barra que enche enquanto o número conta.
// Título opcional com *palavra* em itálico. Fundo escuro.
// props: title?, items [{v, label, prefix?, suffix?, of? (100), kind? "ring"|"bar"}] (1–3), step?
export const Highlights: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const items: { v: number; label: string; prefix?: string; suffix?: string; of?: number; kind?: string }[] = p.items ?? [];
  const step: number = p.step ?? 30;
  const t0 = first(p);
  const n = Math.max(1, items.length);
  const top = L.v ? L.t + (p.title ? 260 : 60) : L.t + (p.title ? 200 : 60);
  const gap = L.v ? 46 : 40;
  const cw = L.v ? L.W - L.l - L.r : (L.W - L.l - L.r - gap * (n - 1)) / n;
  const ch = L.v ? Math.min(330, (L.H - top - L.b - gap * (n - 1)) / n) : L.H - top - L.b;
  const D = L.v ? ch - 40 : Math.min(300, cw - 40);
  return (
    <Bg color={C.night}>
      {p.title ? (
        <div style={{ position: "absolute", left: L.l, right: L.r, top: L.t + (L.v ? 30 : 0) }}>
          <Phrase words={emWords(p.title)} f={f} at={t0} fs={fit([plain(p.title)], L.W - L.l - L.r, L.v ? 110 : 90)} color={C.white} em={C.hot} />
        </div>
      ) : null}
      {items.map((it, i) => {
        const h = hitAt(p, i, step) + (i === 0 ? 10 : 0);
        const prog = ip(f, [h, h + 26], [0, 1], (x) => x);
        const frac = Math.min(1, it.v / (it.of ?? 100)) * ip(f, [h, h + 26], [0, 1]);
        const x = L.l + (L.v ? 0 : i * (cw + gap));
        const y = top + (L.v ? i * (ch + gap) : 0);
        const vs = L.v ? 92 : 96;
        const num = (
          <div style={{ display: "flex", alignItems: "baseline", color: C.white, fontWeight: 800, fontSize: vs, letterSpacing: "-0.04em", lineHeight: 1 }}>
            {it.prefix ? <span>{it.prefix}</span> : null}
            <Counter value={it.v} progress={prog} size={vs} color={C.white} />
            {it.suffix ? <span style={{ fontSize: vs * 0.6, marginLeft: 4, color: C.brandOnDark }}>{it.suffix}</span> : null}
          </div>
        );
        const sw = Math.max(10, D * 0.07);
        const r = D / 2 - sw;
        const circ = 2 * Math.PI * r;
        const bar = it.kind === "bar";
        return (
          <div key={i} style={{ position: "absolute", left: x, top: y + ip(f, [h - 4, h + 14], [50, 0]), width: cw, height: ch, opacity: ip(f, [h - 4, h + 4], [0, 1]), display: "flex", flexDirection: L.v ? "row" : "column", alignItems: L.v ? "center" : "flex-start", gap: L.v ? 44 : 28 }}>
            {bar ? (
              <div style={{ width: L.v ? D : cw, flexShrink: 0, display: "flex", flexDirection: "column", gap: 22 }}>
                {num}
                <div style={{ height: 22, borderRadius: 11, background: C.shellLine, overflow: "hidden" }}>
                  <div style={{ width: `${frac * 100}%`, height: "100%", borderRadius: 11, background: C.brandOnDark }} />
                </div>
              </div>
            ) : (
              <div style={{ position: "relative", width: D, height: D, flexShrink: 0 }}>
                <svg width={D} height={D} style={{ position: "absolute", transform: "rotate(-90deg)" }}>
                  <circle cx={D / 2} cy={D / 2} r={r} fill="none" stroke={C.shellLine} strokeWidth={sw} />
                  <circle cx={D / 2} cy={D / 2} r={r} fill="none" stroke={C.brandOnDark} strokeWidth={sw} strokeLinecap="round" strokeDasharray={circ} strokeDashoffset={circ * (1 - frac)} />
                </svg>
                <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${Math.min(1, (D * 0.78) / (vs * 0.62 * (String(it.v).length + (it.prefix?.length ?? 0) + (it.suffix?.length ?? 0) * 0.6)))})` }}>{num}</div>
              </div>
            )}
            <span style={{ fontSize: L.v ? 44 : 38, fontWeight: 600, color: "rgba(255,255,255,0.86)", letterSpacing: "-0.02em", lineHeight: 1.15 }}>{it.label}</span>
          </div>
        );
      })}
    </Bg>
  );
};

/* ───────────────────────── foto + nome + CTA com o botão Seguir clicado ───────────────────────── */
// Cartão de perfil (foto, nome, @) e a chamada com *palavra* em itálico; o cursor entra, clica no
// botão e ele vira "Seguindo ✓". Fundo na cor de destaque; se for a última cena, some no fim.
// props: name, handle, photo?, cta (com *palavra*), button? ("Seguir"), done? ("Seguindo"), click? (frame do clique)
export const Follow: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const fade = useOutFade(p.len);
  const t0 = first(p);
  const click: number = p.click ?? (p.beats.length > 1 ? bt(p, 1) : 48);
  const cardW = L.v ? L.W - L.l - L.r : 760;
  const av = L.v ? 190 : 170;
  const words = emWords(p.cta ?? "");
  const cfs = fit([plain(p.cta ?? "")], (L.W - L.l - L.r) * (L.v ? 1.7 : 1), L.v ? 88 : 80);
  const on = f >= click + 2;
  const press = 1 - 0.08 * Math.max(0, 1 - Math.abs(f - (click + 2)) / 5);
  const ripple = ip(f, [click, click + 18], [0, 1]);
  const cardTop = L.v ? L.H * 0.4 : L.H * 0.44;
  const btnH = L.v ? 104 : 92;
  const btnY = cardTop + 56 + av + 40 + (L.v ? 160 : 150);
  const btnX = L.W / 2;
  const cur = ip(f, [click - 26, click - 2], [0, 1], EASE_INOUT);
  const curX = btnX + (1 - cur) * L.W * 0.32 + 30;
  const curY = btnY + btnH / 2 + (1 - cur) * L.H * 0.18 + 18;
  return (
    <Bg color={C.accentFill}>
      <AbsoluteFill style={{ opacity: fade }}>
        <div style={{ position: "absolute", left: L.l, right: L.r, top: L.v ? L.t + 40 : L.t + 20 }}>
          <Phrase words={words} f={f} at={t0} fs={cfs} color={C.white} em={C.night} align="center" />
        </div>
        <div style={{ position: "absolute", left: (L.W - cardW) / 2, top: cardTop + ip(f, [t0, t0 + 16], [60, 0]), width: cardW, opacity: ip(f, [t0, t0 + 8], [0, 1]), background: C.paper, borderRadius: 40, padding: "56px 48px 48px", display: "flex", flexDirection: "column", alignItems: "center", boxShadow: "0 30px 80px rgba(5,7,10,0.35)" }}>
          <Portrait photo={p.photo} name={p.name} size={av} bg={C.night} fg={C.white} />
          <div style={{ ...H1, fontSize: fit([p.name ?? ""], cardW - 96, L.v ? 64 : 58), color: C.ink, marginTop: 30 }}>{p.name}</div>
          <div style={{ fontSize: L.v ? 38 : 34, fontWeight: 600, color: C.dim, marginTop: 8 }}>{p.handle}</div>
          <div style={{ position: "relative", marginTop: 40, transform: `scale(${press})` }}>
            <div style={{ height: btnH, minWidth: L.v ? 420 : 380, padding: "0 56px", borderRadius: 100, display: "flex", alignItems: "center", justifyContent: "center", gap: 14, fontSize: L.v ? 42 : 38, fontWeight: 700, background: on ? C.line : C.brand, color: on ? C.ink : C.white }}>
              {on ? `${p.done ?? "Seguindo"} ✓` : (p.button ?? "Seguir")}
            </div>
            {ripple > 0 && ripple < 1 ? (
              <div style={{ position: "absolute", left: "50%", top: "50%", width: 600 * ripple, height: 600 * ripple, transform: "translate(-50%, -50%)", borderRadius: "50%", border: `4px solid ${C.brand}`, opacity: 1 - ripple }} />
            ) : null}
          </div>
        </div>
        {cur > 0 && f < click + 30 ? (
          <svg width={56} height={70} viewBox="0 0 28 35" style={{ position: "absolute", left: curX, top: curY, transform: `scale(${f >= click && f < click + 5 ? 0.88 : 1})`, opacity: ip(f, [click + 20, click + 30], [1, 0]) }}>
            <path d="M2 2 L2 27 L9 20 L14 32 L19 30 L14 18 L24 18 Z" fill={C.white} stroke={C.ink} strokeWidth={2} strokeLinejoin="round" />
          </svg>
        ) : null}
      </AbsoluteFill>
    </Bg>
  );
};
