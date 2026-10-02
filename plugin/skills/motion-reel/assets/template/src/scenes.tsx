import React from "react";
import { AbsoluteFill, Img, random, staticFile } from "remotion";
import { MODELS } from "./timeline";
import { evolvePath } from "@remotion/paths";
import {
  BRAND,
  Bg,
  C,
  Counter,
  EASE,
  EASE_IN,
  EASE_INOUT,
  FONT,
  MONO,
  MaskUp,
  Odometer,
  hollow,
  ip,
  lemniscatePath,
  lemniscatePoint,
  shake,
  useF,
} from "./lib";

const W = 1080;
const H = 1920;

/* ---------------------------------------------------------------- INTRO */
export const Intro: React.FC = () => {
  const f = useF();
  const a = 380;
  const cx = W / 2;
  const cy = 860;
  const path = lemniscatePath(a, cx, cy);
  const draw = ip(f, [10, 46], [0, 1], EASE_INOUT);
  const { strokeDasharray, strokeDashoffset } = evolvePath(draw, path);
  const toLogo = ip(f, [44, 54], [0, 1]);
  // Mergulho no cruzamento do infinito.
  const dive = ip(f, [58, 75], [1, 9], EASE_IN);
  const fadeOut = ip(f, [66, 75], [1, 0], EASE_IN);

  const particles = Array.from({ length: 80 }, (_, i) => {
    const t = (i / 80) * Math.PI * 2;
    const target = lemniscatePoint(a, t);
    const ang = random(`ang${i}`) * Math.PI * 2;
    const r = 260 + random(`r${i}`) * 620;
    const start = i % 14;
    const p = ip(f, [start, start + 26], [0, 1], EASE_INOUT);
    const x = cx + Math.cos(ang) * r * (1 - p) + target.x * p;
    const y = cy + Math.sin(ang) * r * (1 - p) + target.y * p;
    const size = 6 + random(`s${i}`) * 14;
    const o = ip(f, [start, start + 6], [0, 1]) * ip(f, [40, 50], [1, 0]);
    return { x, y, size, o, blue: i % 3 !== 0 };
  });

  return (
    <Bg color={C.night}>
      <AbsoluteFill
        style={{
          transform: `scale(${dive})`,
          transformOrigin: `${cx}px ${cy}px`,
          opacity: fadeOut,
        }}
      >
        <svg width={W} height={H} style={{ position: "absolute" }}>
          <defs>
            <linearGradient id="inf" x1="0" x2="1" y1="0" y2="0">
              <stop offset="0" stopColor={C.brandOnDark} />
              <stop offset="0.5" stopColor={C.brand} />
              <stop offset="1" stopColor={C.brandOnDark} />
            </linearGradient>
          </defs>
          {particles.map((p, i) => (
            <circle
              key={i}
              cx={p.x}
              cy={p.y}
              r={p.size / 2}
              fill={p.blue ? C.brandOnDark : C.white}
              opacity={p.o}
            />
          ))}
          <path
            d={path}
            fill="none"
            stroke="url(#inf)"
            strokeWidth={34}
            strokeLinecap="round"
            strokeDasharray={strokeDasharray}
            strokeDashoffset={strokeDashoffset}
            opacity={1 - toLogo}
          />
        </svg>
        <Img
          src={staticFile("marca.png")}
          style={{
            position: "absolute",
            width: 780,
            left: cx - 390,
            top: cy - 181,
            opacity: toLogo,
            transform: `scale(${ip(f, [44, 60], [1.12, 1])})`,
          }}
        />
        <div
          style={{
            position: "absolute",
            top: cy + 290,
            width: "100%",
            textAlign: "center",
            color: C.white,
            fontSize: 44,
            fontWeight: 600,
            letterSpacing: "-0.01em",
          }}
        >
          <MaskUp f={f} at={32}>
            <span style={{ color: C.faint }}>{BRAND} apresenta</span>
          </MaskUp>
        </div>
      </AbsoluteFill>
    </Bg>
  );
};

/* --------------------------------------------------------------- GRANDE */
export const Grande: React.FC = () => {
  const f = useF();
  const letters = "GRANDE".split("");
  const push = ip(f, [0, 30], [1, 1.08], (t) => t);
  return (
    <Bg color={C.paper}>
      <AbsoluteFill
        style={{
          justifyContent: "center",
          alignItems: "center",
          transform: `scale(${push})`,
        }}
      >
        <div style={{ display: "flex" }}>
          {letters.map((l, i) => {
            const s = i * 2;
            const p = ip(f, [s, s + 9], [0, 1]);
            return (
              <span
                key={i}
                style={{
                  display: "inline-block",
                  fontSize: 226,
                  fontWeight: 800,
                  letterSpacing: "-0.05em",
                  color: C.ink,
                  lineHeight: 1,
                  transform: `translateY(${(1 - p) * 180}px) scale(${1 + (1 - p) * 1.4})`,
                  filter: `blur(${(1 - p) * 16}px)`,
                  opacity: p,
                }}
              >
                {l}
              </span>
            );
          })}
        </div>
        <div
          style={{
            position: "absolute",
            top: 1180,
            left: 90,
            height: 10,
            width: ip(f, [10, 26], [0, 900]),
            background: C.brand,
            borderRadius: 100,
          }}
        />
      </AbsoluteFill>
    </Bg>
  );
};

/* ------------------------------------------------------------- MARQUEE */
const Marquee: React.FC<{
  word: string;
  bannerBg: string;
  bannerFg: string;
  size: number;
  bannerSize: number;
  bg: string;
  stroke: string;
}> = ({ word, bannerBg, bannerFg, size, bannerSize, bg, stroke }) => {
  const f = useF();
  const rows = 9;
  const center = Math.floor(rows / 2);
  const rowH = size * 1.02;
  return (
    <Bg color={bg}>
      <AbsoluteFill
        style={{
          transform: `rotate(-9deg) scale(${ip(f, [0, 60], [1.25, 1.12], (t) => t)})`,
          justifyContent: "center",
        }}
      >
        {Array.from({ length: rows }, (_, i) => {
          const d = Math.abs(i - center);
          const dir = i % 2 === 0 ? 1 : -1;
          const reveal = ip(f, [d * 2, d * 2 + 12], [0, 1]);
          const x = dir * (f * (9 + d * 2)) - 900;
          if (i === center) {
            const band = ip(f, [0, 10], [0, 1]);
            return (
              <div
                key={i}
                style={{
                  height: rowH,
                  background: bannerBg,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  margin: "0 -400px",
                  transform: `scaleY(${band})`,
                  // Acima das vizinhas: o fill na cor do fundo de um til ou cedilha da linha
                  // de baixo vazaria como mancha clara sobre a faixa.
                  position: "relative",
                  zIndex: 1,
                }}
              >
                <MaskUp f={f} at={4}>
                  <span
                    style={{
                      fontSize: bannerSize,
                      fontWeight: 800,
                      letterSpacing: "-0.045em",
                      color: bannerFg,
                      lineHeight: 1.1,
                      display: "block",
                    }}
                  >
                    {word}
                  </span>
                </MaskUp>
              </div>
            );
          }
          return (
            <div
              key={i}
              style={{
                height: rowH,
                whiteSpace: "nowrap",
                fontSize: size,
                fontWeight: 800,
                letterSpacing: "-0.045em",
                lineHeight: 1,
                transform: `translateX(${x}px)`,
                opacity: reveal * (d === 1 ? 0.9 : 0.55),
                ...hollow(stroke, 2.5, bg),
              }}
            >
              {`${word} · `.repeat(5)}
            </div>
          );
        })}
      </AbsoluteFill>
    </Bg>
  );
};

export const Atualizacao: React.FC = () => (
  <Marquee
    word="ATUALIZAÇÃO"
    bannerBg={C.ink}
    bannerFg={C.white}
    size={176}
    bannerSize={136}
    bg={C.paper}
    stroke={C.ink}
  />
);

export const Performar: React.FC = () => (
  <Marquee
    word="PERFORMAR"
    bannerBg={C.accentFill}
    bannerFg={C.white}
    size={176}
    bannerSize={160}
    bg={C.paper}
    stroke={C.ink}
  />
);

/* -------------------------------------------------------------- MOSAIC */
const CARD_W = 340;
const CARD_H = 440;
const GAP = 26;
const COLS = 7;
const ROWS = 9;
export const MOSAIC_ZOOM = 2.8;

const KitCard: React.FC<{ variant: number }> = ({ variant }) => {
  const v = [
    { bg: C.paper, fg: C.ink, border: C.line, hollow: false, mark: "logo-light.png" },
    { bg: C.accentFill, fg: C.white, border: C.accentFill, hollow: false, mark: "logo-dark.png" },
    { bg: C.night, fg: C.white, border: C.shellLine, hollow: false, mark: "logo-dark.png" },
    { bg: C.paper, fg: C.ink, border: C.line, hollow: true, mark: "logo-light.png" },
  ][variant];
  return (
    <div
      style={{
        width: CARD_W,
        height: CARD_H,
        background: v.bg,
        border: `2px solid ${v.border}`,
        borderRadius: 6,
        padding: 26,
        boxSizing: "border-box",
        display: "flex",
        flexDirection: "column",
        justifyContent: "space-between",
        fontFamily: FONT,
      }}
    >
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <Img src={staticFile(v.mark)} style={{ height: 24 }} />
        <span style={{ fontSize: 15, fontWeight: 700, color: v.fg, opacity: 0.6 }}>
          Opus 5.5
        </span>
      </div>
      <div
        style={{
          fontSize: 42,
          fontWeight: 800,
          letterSpacing: "-0.045em",
          lineHeight: 0.98,
          color: v.fg,
        }}
      >
        Claude
        <br />
        Kit
        <br />
        <span style={v.hollow ? hollow(v.fg, 1.4, v.bg) : undefined}>Mentorados</span>
      </div>
    </div>
  );
};

export const Mosaic: React.FC = () => {
  const f = useF();
  const cc = Math.floor(COLS / 2);
  const cr = Math.floor(ROWS / 2);
  const out = ip(f, [8, 44], [0, 1], EASE_INOUT);
  const back = ip(f, [50, 75], [0, 1], EASE_INOUT);
  const zoomOut = MOSAIC_ZOOM + (0.58 - MOSAIC_ZOOM) * out;
  const scale = zoomOut + (MOSAIC_ZOOM - zoomOut) * back;
  const tilt = 22 * out * (1 - back);
  const spin = -10 * out * (1 - back);
  const gridW = COLS * CARD_W + (COLS - 1) * GAP;
  const gridH = ROWS * CARD_H + (ROWS - 1) * GAP;
  return (
    <Bg color={C.night}>
      <AbsoluteFill style={{ perspective: 2000 }}>
        <div
          style={{
            position: "absolute",
            left: W / 2 - gridW / 2,
            top: H / 2 - gridH / 2,
            width: gridW,
            height: gridH,
            transform: `scale(${scale}) rotateX(${tilt}deg) rotateZ(${spin}deg)`,
            transformOrigin: "50% 50%",
          }}
        >
          {Array.from({ length: COLS * ROWS }, (_, k) => {
            const c = k % COLS;
            const r = Math.floor(k / COLS);
            const isCenter = c === cc && r === cr;
            const d = Math.hypot(c - cc, r - cr);
            const s = 6 + d * 3.2;
            const p = isCenter ? 1 : ip(f, [s, s + 12], [0, 1]);
            const variant = isCenter ? 0 : (c * 3 + r * 5 + (c + r) % 2) % 4;
            return (
              <div
                key={k}
                style={{
                  position: "absolute",
                  left: c * (CARD_W + GAP),
                  top: r * (CARD_H + GAP),
                  transform: `scale(${0.4 + 0.6 * p}) rotateY(${(1 - p) * 90}deg)`,
                  opacity: p,
                }}
              >
                <KitCard variant={variant} />
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </Bg>
  );
};

/* --------------------------------------------------------------- TITLE */
// Match cut: começa exatamente como o card central na escala MOSAIC_ZOOM.
export const Title: React.FC = () => {
  const f = useF();
  const z = MOSAIC_ZOOM;
  const cardLeft = W / 2 - (CARD_W * z) / 2;
  const cardBottom = H / 2 + (CARD_H * z) / 2;
  const grow = ip(f, [6, 26], [1, 1.11]);
  const lift = ip(f, [6, 26], [0, -260]);
  const hol = ip(f, [16, 22], [0, 1]);
  const cardFade = ip(f, [4, 14], [1, 0]);
  const open = ip(f, [2, 16], [0, 1], EASE_INOUT);
  const rx = cardLeft * (1 - open);
  const ry = (H / 2 - (CARD_H * z) / 2) * (1 - open);
  return (
    <Bg color={C.night}>
      <div
        style={{
          position: "absolute",
          left: rx,
          top: ry,
          width: W - 2 * rx,
          height: H - 2 * ry,
          background: C.paper,
          border: `${2 * z * (1 - open)}px solid ${C.line}`,
          borderRadius: 6 * z * (1 - open),
          boxSizing: "border-box",
        }}
      />
      <Img
        src={staticFile("logo-light.png")}
        style={{
          position: "absolute",
          left: cardLeft + 26 * z,
          top: H / 2 - (CARD_H * z) / 2 + 26 * z,
          height: 24 * z,
          opacity: cardFade,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: cardLeft + 26 * z,
          top: cardBottom - 26 * z,
          transform: `translateY(-100%) translateY(${lift}px) scale(${grow})`,
          transformOrigin: "0% 100%",
          color: C.ink,
          fontWeight: 800,
          letterSpacing: "-0.045em",
          lineHeight: 0.98,
          fontSize: 42 * z,
        }}
      >
        <div style={{ fontSize: 34, fontWeight: 600, letterSpacing: 0, color: C.dim, marginBottom: 18 }}>
          <MaskUp f={f} at={14}>
            <span>do plugin</span>
          </MaskUp>
        </div>
        Claude
        <br />
        Kit
        <br />
        <span style={{ position: "relative", display: "inline-block" }}>
          <span style={{ opacity: 1 - hol }}>Mentorados</span>
          <span style={{ position: "absolute", left: 0, top: 0, opacity: hol, ...hollow(C.ink, 3, C.paper) }}>
            Mentorados
          </span>
        </span>
      </div>
      <div
        style={{
          position: "absolute",
          left: 90,
          bottom: 330,
          height: 8,
          borderRadius: 100,
          width: ip(f, [24, 44], [0, 460]),
          background: C.brand,
        }}
      />
    </Bg>
  );
};

/* ---------------------------------------------------------------- OPUS */
const Orbit: React.FC<{ f: number; rx: number; ry: number; rot: number; delay: number; cy: number }> = ({
  f,
  rx,
  ry,
  rot,
  delay,
  cy,
}) => {
  const cx = W / 2;
  const d = `M ${cx - rx} ${cy} a ${rx} ${ry} 0 1 0 ${rx * 2} 0 a ${rx} ${ry} 0 1 0 ${-rx * 2} 0`;
  const { strokeDasharray, strokeDashoffset } = evolvePath(ip(f, [delay, delay + 30], [0, 1], EASE_INOUT), d);
  const t = (f - delay) / 22;
  const px = cx + Math.cos(t) * rx;
  const py = cy + Math.sin(t) * ry;
  return (
    <g transform={`rotate(${rot} ${cx} ${cy})`}>
      <path d={d} fill="none" stroke={C.shellLine} strokeWidth={2} strokeDasharray={strokeDasharray} strokeDashoffset={strokeDashoffset} />
      <circle cx={px} cy={py} r={8 + 5 * Math.sin(t)} fill={C.brandOnDark} opacity={ip(f, [delay + 10, delay + 18], [0, 1])} />
    </g>
  );
};

const ModelFace: React.FC<{ f: number; name: string; ver: string; at: number; size: number }> = ({ f, name, ver, at, size }) => (
  <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
    <span style={{ display: "block", color: C.white, fontSize: size, fontWeight: 800, letterSpacing: "-0.055em", lineHeight: 1 }}>
      {name}
    </span>
    <div style={{ opacity: ip(f, [at, at + 4], [0, 1]) }}>
      <Odometer value={ver} progress={ip(f, [at, at + 34], [0, 1], (t) => t)} size={size} color={C.brandOnDark} spins={1} />
    </div>
  </div>
);

export const Models: React.FC = () => {
  const f = useF();
  const faceH = 560;
  const turn = ip(f, [56, 72], [0, 90], EASE_INOUT);
  const collapse = ip(f, [96, 110], [0, 1], EASE_INOUT);
  const rows = [
    { name: MODELS.a, ver: MODELS.aVer, at: 104 },
    { name: MODELS.b, ver: MODELS.bVer, at: 110 },
  ];
  return (
    <Bg color={C.night}>
      <svg width={W} height={H} style={{ position: "absolute" }}>
        <Orbit f={f} rx={560} ry={150} rot={-16} delay={4} cy={980} />
        <Orbit f={f} rx={470} ry={110} rot={12} delay={12} cy={980} />
      </svg>
      <div style={{ position: "absolute", top: 440, width: "100%", textAlign: "center", color: C.faint, fontSize: 52, fontWeight: 600 }}>
        <div style={{ position: "relative", height: 70 }}>
          <div style={{ position: "absolute", width: "100%" }}>
            <MaskUp f={f} at={0} out={52}>
              <span>para acompanhar o</span>
            </MaskUp>
          </div>
          <div style={{ position: "absolute", width: "100%" }}>
            <MaskUp f={f} at={60} out={94}>
              <span>e o</span>
            </MaskUp>
          </div>
          <div style={{ position: "absolute", width: "100%" }}>
            <MaskUp f={f} at={100}>
              <span>novos modelos</span>
            </MaskUp>
          </div>
        </div>
      </div>
      <AbsoluteFill style={{ perspective: 2400, opacity: 1 - collapse, filter: collapse > 0 ? `blur(${collapse * 10}px)` : undefined }}>
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            top: 980 - faceH / 2,
            height: faceH,
            transformStyle: "preserve-3d",
            transform: `scale(${1 - collapse * 0.35}) translateZ(${-faceH / 2}px) rotateX(${turn}deg)`,
          }}
        >
          <div style={{ position: "absolute", inset: 0, backfaceVisibility: "hidden", transform: `translateZ(${faceH / 2}px)`, display: "flex", justifyContent: "center", alignItems: "center" }}>
            <MaskUp f={f} at={8} dur={16}>
              <ModelFace f={f} name={MODELS.a} ver={MODELS.aVer} at={14} size={250} />
            </MaskUp>
          </div>
          <div style={{ position: "absolute", inset: 0, backfaceVisibility: "hidden", transform: `rotateX(-90deg) translateZ(${faceH / 2}px)`, display: "flex", justifyContent: "center", alignItems: "center" }}>
            <ModelFace f={f} name={MODELS.b} ver={MODELS.bVer} at={62} size={226} />
          </div>
        </div>
      </AbsoluteFill>
      <div style={{ position: "absolute", left: 90, right: 180, top: 760 }}>
        {rows.map((r, i) => (
          <div key={r.name} style={{ borderTop: `2px solid ${C.shellLine}`, padding: "26px 0", display: "flex", justifyContent: "space-between", alignItems: "baseline", opacity: ip(f, [r.at - 2, r.at + 4], [0, 1]) }}>
            <MaskUp f={f} at={r.at}>
              <span style={{ display: "block", color: C.white, fontSize: 132, fontWeight: 800, letterSpacing: "-0.05em", lineHeight: 1.05 }}>{r.name}</span>
            </MaskUp>
            <MaskUp f={f} at={r.at + 3}>
              <span style={{ display: "block", color: C.brandOnDark, fontSize: 132, fontWeight: 800, letterSpacing: "-0.04em", lineHeight: 1.05 }}>{r.ver}</span>
            </MaskUp>
          </div>
        ))}
        <div style={{ borderTop: `2px solid ${C.shellLine}`, transform: `scaleX(${ip(f, [112, 126], [0, 1])})`, transformOrigin: "0 0" }} />
      </div>
    </Bg>
  );
};

/* --------------------------------------------------------------- HOURS */
export const Hours: React.FC = () => {
  const f = useF();
  const cx = W / 2;
  const cy = 820;
  const R = 400;
  const prog = ip(f, [8, 58], [0, 1], EASE_INOUT);
  const handAngle = prog * 14 * 360;
  const arcLen = 2 * Math.PI * (R + 44);
  return (
    <Bg color={C.night}>
      <svg width={W} height={H} style={{ position: "absolute" }}>
        {Array.from({ length: 60 }, (_, i) => {
          const a = (i / 60) * Math.PI * 2 - Math.PI / 2;
          const p = ip(f, [i * 0.25, i * 0.25 + 8], [0, 1]);
          const long = i % 5 === 0;
          const r1 = R - (long ? 40 : 20);
          const lit = i / 60 <= prog + 0.001;
          return (
            <line
              key={i}
              x1={cx + Math.cos(a) * r1}
              y1={cy + Math.sin(a) * r1}
              x2={cx + Math.cos(a) * (r1 + (R - r1) * p)}
              y2={cy + Math.sin(a) * (r1 + (R - r1) * p)}
              stroke={lit ? C.brandOnDark : "rgba(255,255,255,0.28)"}
              strokeWidth={long ? 6 : 3}
              strokeLinecap="round"
            />
          );
        })}
        <circle
          cx={cx}
          cy={cy}
          r={R + 44}
          fill="none"
          stroke={C.brandOnDark}
          strokeWidth={10}
          strokeLinecap="round"
          strokeDasharray={`${arcLen * prog} ${arcLen}`}
          transform={`rotate(-90 ${cx} ${cy})`}
        />
        {Array.from({ length: 6 }, (_, k) => {
          const ang = ((handAngle - k * 9) * Math.PI) / 180 - Math.PI / 2;
          return (
            <line
              key={k}
              x1={cx}
              y1={cy}
              x2={cx + Math.cos(ang) * (R - 70)}
              y2={cy + Math.sin(ang) * (R - 70)}
              stroke={C.white}
              strokeWidth={4}
              strokeLinecap="round"
              opacity={(1 - k / 6) * 0.5 * ip(f, [4, 10], [0, 1]) * (1 - ip(f, [58, 64], [0, 1]))}
            />
          );
        })}
      </svg>
      <div
        style={{
          position: "absolute",
          top: cy - 150,
          width: "100%",
          display: "flex",
          justifyContent: "center",
          alignItems: "baseline",
          filter: `drop-shadow(0 0 0 ${C.night})`,
        }}
      >
        <div style={{ background: C.night, padding: "0 20px", display: "flex", alignItems: "baseline", borderRadius: 12 }}>
          <Counter value={14} progress={prog} size={270} color={C.brandOnDark} />
          <span style={{ fontSize: 150, fontWeight: 800, color: C.brandOnDark, letterSpacing: "-0.04em" }}>h</span>
        </div>
      </div>
      <div style={{ position: "absolute", top: cy + R + 120, width: "100%", textAlign: "center" }}>
        <MaskUp f={f} at={26}>
          <span style={{ display: "block", color: C.white, fontSize: 70, fontWeight: 800, letterSpacing: "-0.03em", lineHeight: 1.15 }}>
            de sessões de análise
          </span>
        </MaskUp>
      </div>
    </Bg>
  );
};

/* ----------------------------------------------------------- TERMINALS */
const MiniTerm: React.FC<{ seed: number; active: boolean }> = ({ seed, active }) => (
  <div
    style={{
      width: 250,
      height: 160,
      background: C.night,
      border: `2px solid ${active ? C.brandOnDark : "rgba(255,255,255,0.28)"}`,
      borderRadius: 6,
      padding: 14,
      boxSizing: "border-box",
      fontFamily: MONO,
      fontSize: 15,
    }}
  >
    <div style={{ display: "flex", gap: 6, marginBottom: 14 }}>
      {[0, 1, 2].map((i) => (
        <div key={i} style={{ width: 9, height: 9, borderRadius: 9, background: "rgba(255,255,255,0.22)" }} />
      ))}
    </div>
    <div style={{ color: C.brandOnDark, marginBottom: 10 }}>$ claude</div>
    {[0, 1, 2].map((i) => (
      <div
        key={i}
        style={{
          height: 7,
          width: `${35 + random(`w${seed}-${i}`) * 60}%`,
          background: "rgba(255,255,255,0.4)",
          borderRadius: 4,
          marginBottom: 9,
        }}
      />
    ))}
  </div>
);

export const Terminals: React.FC = () => {
  const f = useF();
  const cols = 9;
  const rows = 15;
  const total = cols * rows;
  const shown = ip(f, [-6, 40], [total * 0.4, total], (t) => t);
  const pan = ip(f, [0, 105], [300, -300], (t) => t);
  const cmd = "$ claude";
  const typed = Math.floor(ip(f, [22, 40], [0, cmd.length], (t) => t));
  const hero = ip(f, [16, 30], [0, 1]);
  return (
    <Bg color={C.night}>
      <AbsoluteFill style={{ perspective: 1600 }}>
        <div
          style={{
            position: "absolute",
            left: W / 2 - (cols * 268) / 2,
            top: H / 2 - (rows * 178) / 2,
            width: cols * 268,
            height: rows * 178,
            transform: `translateY(${pan}px) rotateX(46deg) rotateZ(-24deg) scale(1.25)`,
          }}
        >
          {Array.from({ length: total }, (_, k) => {
            const order = Math.floor(random(`o${k}`) * total);
            const p = ip(shown, [order, order + 6], [0, 1], (t) => t);
            return (
              <div
                key={k}
                style={{
                  position: "absolute",
                  left: (k % cols) * 268,
                  top: Math.floor(k / cols) * 178,
                  opacity: p,
                  transform: `translateZ(${(1 - p) * 220}px)`,
                }}
              >
                <MiniTerm seed={k} active={random(`a${k}`) > 0.86} />
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
      <div
        style={{
          position: "absolute",
          left: 90,
          right: 180,
          top: 560,
          background: C.night,
          border: `2px solid ${C.shellLine}`,
          borderRadius: 6,
          padding: "40px 48px 56px",
          boxShadow: `0 0 0 24px ${C.night}`,
          opacity: hero,
          transform: `scale(${0.92 + 0.08 * hero})`,
        }}
      >
        <div style={{ display: "flex", gap: 10, marginBottom: 34 }}>
          {[0, 1, 2].map((i) => (
            <div key={i} style={{ width: 16, height: 16, borderRadius: 16, background: "rgba(255,255,255,0.25)" }} />
          ))}
        </div>
        <div style={{ fontFamily: MONO, fontSize: 34, color: C.brandOnDark, height: 44 }}>
          {cmd.slice(0, typed)}
          <span style={{ opacity: Math.floor(f / 8) % 2 ? 1 : 0, color: C.white }}>▍</span>
        </div>
        <div style={{ marginTop: 40, color: C.faint, fontSize: 46, fontWeight: 600 }}>
          <MaskUp f={f} at={34}>
            <span>em mais de</span>
          </MaskUp>
        </div>
        <div style={{ opacity: ip(f, [36, 40], [0, 1]), marginTop: 6 }}>
          <Counter value={715} progress={ip(f, [36, 72], [0, 1], (t) => t)} size={250} color={C.brandOnDark} />
        </div>
        <div style={{ color: C.white, fontSize: 64, fontWeight: 800, letterSpacing: "-0.03em", marginTop: 12 }}>
          <MaskUp f={f} at={46}>
            <span>terminais executados</span>
          </MaskUp>
        </div>
      </div>
    </Bg>
  );
};

/* -------------------------------------------------------------- CREDIT */
export const Credit: React.FC = () => {
  const f = useF();
  const fill = ip(f, [10, 42], [0, 26]);
  const shift = ip(f, [56, 72], [0, -300], EASE_INOUT);
  const words = ["para", "trazer", "o", "que", "há", "de", "melhor", "para:"];
  return (
    <Bg color={C.paper}>
      <div style={{ position: "absolute", left: 90, right: 180, top: 520, transform: `translateY(${shift}px)` }}>
        <div style={{ display: "flex", alignItems: "baseline" }}>
          <Counter value={26} progress={ip(f, [8, 42], [0, 1], (t) => t)} size={330} color={C.brand} />
          <span style={{ fontSize: 200, fontWeight: 800, color: C.brand, letterSpacing: "-0.04em" }}>%</span>
        </div>
        <div
          style={{
            marginTop: 40,
            height: 64,
            borderRadius: 100,
            background: "#f5f7fb",
            border: `2px solid ${C.line}`,
            position: "relative",
            overflow: "hidden",
          }}
        >
          <div style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: `${fill}%`, background: C.brand, borderRadius: 100 }} />
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", marginTop: 14, color: C.faint, fontSize: 26, fontWeight: 600 }}>
          {["0", "25", "50", "75", "100%"].map((t) => (
            <span key={t}>{t}</span>
          ))}
        </div>
        <div style={{ marginTop: 44, color: C.dim, fontSize: 60, fontWeight: 700, letterSpacing: "-0.02em", lineHeight: 1.15 }}>
          <MaskUp f={f} at={20}>
            <span>do crédito semanal</span>
          </MaskUp>
          <br />
          <MaskUp f={f} at={25}>
            <span>utilizado</span>
          </MaskUp>
        </div>
        <div
          style={{
            marginTop: 70,
            fontSize: 96,
            fontWeight: 800,
            letterSpacing: "-0.045em",
            lineHeight: 1.02,
            color: C.ink,
            display: "flex",
            flexWrap: "wrap",
            columnGap: 26,
          }}
        >
          {words.map((w, i) => (
            <MaskUp key={i} f={f} at={62 + i * 3}>
              <span style={{ display: "block", paddingBottom: 8 }}>{w}</span>
            </MaskUp>
          ))}
        </div>
      </div>
    </Bg>
  );
};

/* ---------------------------------------------------------------- VOCÊ */
export const Voce: React.FC = () => {
  const f = useF();
  const s = shake(f, 7, 22, 12);
  const scale = ip(f, [2, 9], [3.2, 1], EASE);
  const flash = ip(f, [0, 4], [1, 0], (t) => t);
  return (
    <Bg color={C.night}>
      <svg width={W} height={H} style={{ position: "absolute" }}>
        {[0, 1, 2].map((k) => {
          const p = ip(f, [7 + k * 3, 30 + k * 3], [0, 1], EASE);
          return (
            <circle key={k} cx={W / 2} cy={H / 2} r={120 + p * 900} fill="none" stroke={C.brandOnDark} strokeWidth={6 * (1 - p)} opacity={1 - p} />
          );
        })}
      </svg>
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", transform: `translate(${s.x}px, ${s.y}px)` }}>
        <span
          style={{
            fontSize: 330,
            fontWeight: 800,
            letterSpacing: "-0.055em",
            color: C.white,
            transform: `scale(${scale})`,
            filter: `blur(${ip(f, [2, 9], [14, 0])}px)`,
            opacity: ip(f, [2, 5], [0, 1]),
          }}
        >
          VOCÊ
        </span>
      </AbsoluteFill>
      <AbsoluteFill style={{ background: C.accentFill, opacity: flash }} />
    </Bg>
  );
};

/* -------------------------------------------------------------- CLAUDE */
export const NoUsoDoClaude: React.FC = () => {
  const f = useF();
  const exit = ip(f, [50, 60], [0, 1], EASE_IN);
  return (
    <Bg color={C.night}>
      <div
        style={{
          position: "absolute",
          left: 90,
          top: 600,
          color: C.white,
          fontSize: 205,
          fontWeight: 800,
          letterSpacing: "-0.05em",
          lineHeight: 1.02,
          transform: `translateY(${-exit * 200}px)`,
          opacity: 1 - exit,
        }}
      >
        <MaskUp f={f} at={0}>
          <span style={{ display: "block", color: C.faint, fontSize: 140 }}>no uso</span>
        </MaskUp>
        <br />
        <MaskUp f={f} at={5}>
          <span style={{ display: "block" }}>do</span>
        </MaskUp>
        <br />
        <MaskUp f={f} at={10}>
          <span style={{ display: "block", ...hollow(C.white, 4, C.night) }}>Claude!</span>
        </MaskUp>
        <div style={{ height: 12, borderRadius: 100, background: C.brandOnDark, width: ip(f, [18, 34], [0, 780]), marginTop: 18 }} />
      </div>
    </Bg>
  );
};

/* --------------------------------------------------------------- OUTRO */
export const Outro: React.FC = () => {
  const f = useF();
  const a = 200;
  const cx = W / 2;
  const cy = 820;
  const path = lemniscatePath(a, cx, cy);
  const { strokeDasharray, strokeDashoffset } = evolvePath(ip(f, [0, 24], [0, 1], EASE_INOUT), path);
  const swap = ip(f, [22, 30], [0, 1]);
  const logoW = 820;
  const wipe = ip(f, [24, 44], [0, 100], EASE_INOUT);
  const pill = ip(f, [54, 66], [0, 1]);
  return (
    <Bg color={C.paper}>
      <svg width={W} height={H} style={{ position: "absolute", opacity: 1 - swap }}>
        <path d={path} fill="none" stroke={C.brand} strokeWidth={26} strokeLinecap="round" strokeDasharray={strokeDasharray} strokeDashoffset={strokeDashoffset} />
      </svg>
      <div
        style={{
          position: "absolute",
          left: cx - logoW / 2,
          top: cy - (logoW * 1202) / 4958 / 2,
          width: logoW,
          clipPath: `inset(0 ${100 - wipe}% 0 0)`,
        }}
      >
        <Img src={staticFile("logo-light.png")} style={{ width: logoW, display: "block" }} />
      </div>
      <div style={{ position: "absolute", top: cy + 220, width: "100%", textAlign: "center" }}>
        <MaskUp f={f} at={40}>
          <span style={{ display: "block", fontSize: 64, fontWeight: 800, color: C.ink, letterSpacing: "-0.035em" }}>
            Claude Kit Mentorados
          </span>
        </MaskUp>
        <br />
        <MaskUp f={f} at={45}>
          <span style={{ display: "block", fontSize: 40, fontWeight: 600, color: C.dim, marginTop: 6 }}>
            atualizado para o Opus 5.5
          </span>
        </MaskUp>
      </div>
      <div style={{ position: "absolute", top: cy + 470, width: "100%", display: "flex", justifyContent: "center" }}>
        <div
          style={{
            background: C.ink,
            color: C.white,
            borderRadius: 100,
            padding: "30px 64px",
            fontSize: 42,
            fontWeight: 700,
            letterSpacing: "-0.01em",
            transform: `scale(${0.7 + 0.3 * pill}) translateY(${(1 - pill) * 40}px)`,
            opacity: pill,
          }}
        >
          Atualize seu plugin →
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          top: cy + 610,
          width: "100%",
          textAlign: "center",
          fontFamily: MONO,
          fontSize: 34,
          color: C.dim,
          opacity: ip(f, [64, 74], [0, 1]),
        }}
      >
        /plugin update kit-vamoo
      </div>
    </Bg>
  );
};
