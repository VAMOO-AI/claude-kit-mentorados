import React, { useEffect, useState } from "react";
import {
  AbsoluteFill,
  Easing,
  continueRender,
  delayRender,
  interpolate,
  staticFile,
  useCurrentFrame,
} from "remotion";

// Paleta do exemplo (identidade VAMOO AI). Troque pela sua marca; azul sobre --night usa a variante clara.
// Nome da marca nas cenas (Intro). Os logos são public/logo-light.png, logo-dark.png e marca.png.
export const BRAND = "Sua Marca";

export const C = {
  paper: "#fcfcfc",
  ink: "#000000",
  brand: "#007dff",
  brandOnDark: "#4da3ff",
  accentFill: "#0063cc",
  night: "#05070a",
  dim: "#677294",
  faint: "#97a3b7",
  line: "#e6e8ec",
  shellLine: "rgba(255,255,255,0.12)",
  white: "#ffffff",
};

export const FONT = "'Plus Jakarta Sans', system-ui, sans-serif";
export const MONO = "ui-monospace, SFMono-Regular, Menlo, monospace";

export const EASE = Easing.bezier(0.22, 1, 0.36, 1);
export const EASE_IN = Easing.bezier(0.64, 0, 0.78, 0);
export const EASE_INOUT = Easing.bezier(0.83, 0, 0.17, 1);

export const ip = (
  f: number,
  input: [number, number],
  output: [number, number],
  easing = EASE,
) =>
  interpolate(f, input, output, {
    easing,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

export const useFont = () => {
  const [handle] = useState(() => delayRender("font"));
  useEffect(() => {
    const face = new FontFace(
      "Plus Jakarta Sans",
      `url(${staticFile("PlusJakartaSans.ttf")})`,
      { weight: "200 800" },
    );
    face
      .load()
      .then((f) => {
        document.fonts.add(f);
        continueRender(handle);
      })
      .catch((e) => {
        console.error(e);
        continueRender(handle);
      });
  }, [handle]);
};

export const Bg: React.FC<{ color: string; children?: React.ReactNode }> = ({
  color,
  children,
}) => (
  <AbsoluteFill style={{ backgroundColor: color, fontFamily: FONT }}>
    {children}
  </AbsoluteFill>
);

// Texto vazado. O preenchimento na cor do fundo é pintado por cima do traço e esconde os
// contornos sobrepostos de dentro dos glifos da fonte variável; por isso o traço dobra (metade
// fica por baixo do fill). Só vale sobre fundo sólido: em gradiente ou foto o fill aparece.
export const hollow = (color: string, w: number, bg: string): React.CSSProperties => ({
  color: bg,
  WebkitTextStroke: `${w * 2}px ${color}`,
  paintOrder: "stroke fill",
});

// Máscara: o filho sobe de dentro de uma janela com overflow hidden.
export const MaskUp: React.FC<{
  f: number;
  at: number;
  dur?: number;
  children: React.ReactNode;
  style?: React.CSSProperties;
  out?: number;
}> = ({ f, at, dur = 14, children, style, out }) => {
  const y = ip(f, [at, at + dur], [110, 0]);
  const yOut = out !== undefined ? ip(f, [out, out + 10], [0, -110], EASE_IN) : 0;
  return (
    <div style={{ overflow: "hidden", display: "inline-block", ...style }}>
      <div style={{ transform: `translateY(${y + yOut}%)` }}>{children}</div>
    </div>
  );
};

// Lemniscata de Bernoulli — o motivo do infinito em movimento (o logo real é o PNG).
export const lemniscatePath = (a: number, cx: number, cy: number, n = 240) => {
  const pts: string[] = [];
  for (let i = 0; i <= n; i++) {
    const t = (i / n) * Math.PI * 2;
    const d = 1 + Math.sin(t) ** 2;
    const x = cx + (a * Math.cos(t)) / d;
    const y = cy + (a * Math.sin(t) * Math.cos(t)) / d;
    pts.push(`${i === 0 ? "M" : "L"}${x.toFixed(2)} ${y.toFixed(2)}`);
  }
  return pts.join(" ");
};

export const lemniscatePoint = (a: number, t: number) => {
  const d = 1 + Math.sin(t) ** 2;
  return { x: (a * Math.cos(t)) / d, y: (a * Math.sin(t) * Math.cos(t)) / d };
};

// Contador: inteiro interpolado até o alvo, formatado em pt-BR ("2.700"). O alvo invisível
// na mesma célula reserva a largura final, então o número não empurra o layout ao crescer.
export const Counter: React.FC<{
  value: number;
  progress: number;
  size: number;
  color: string;
  weight?: number;
}> = ({ value, progress, size, color, weight = 800 }) => {
  const p = Math.min(1, Math.max(0, progress));
  const n = Math.round(value * EASE(p));
  return (
    <div
      style={{
        display: "inline-grid",
        justifyItems: "end",
        fontSize: size,
        fontWeight: weight,
        color,
        lineHeight: 1,
        letterSpacing: "-0.04em",
        fontVariantNumeric: "tabular-nums",
      }}
    >
      <span style={{ gridArea: "1 / 1", visibility: "hidden" }}>{value.toLocaleString("pt-BR")}</span>
      <span style={{ gridArea: "1 / 1" }}>{n.toLocaleString("pt-BR")}</span>
    </div>
  );
};

// Odômetro: cada dígito é uma coluna que rola até o alvo. Para versão ou código ("5.5");
// em contagem os dígitos rolam soltos e o meio da animação passa do alvo — use o Counter.
export const Odometer: React.FC<{
  value: string;
  progress: number;
  size: number;
  color: string;
  spins?: number;
  weight?: number;
}> = ({ value, progress, size, color, spins = 1, weight = 800 }) => {
  const chars = value.split("");
  let digitIndex = 0;
  return (
    <div
      style={{
        display: "flex",
        fontSize: size,
        fontWeight: weight,
        color,
        lineHeight: 1,
        letterSpacing: "-0.04em",
        fontVariantNumeric: "tabular-nums",
      }}
    >
      {chars.map((ch, i) => {
        if (!/[0-9]/.test(ch)) {
          return (
            <span key={i} style={{ display: "inline-block" }}>
              {ch}
            </span>
          );
        }
        const di = digitIndex++;
        const target = Number(ch) + 10 * (spins + di);
        const p = Math.min(1, Math.max(0, progress * (1 + di * 0.12) - di * 0.12));
        const pos = target * EASE(p);
        const col = Array.from({ length: 10 * (spins + di + 2) }, (_, k) => k % 10);
        return (
          <span
            key={i}
            style={{ display: "inline-block", height: size, overflow: "hidden" }}
          >
            <span
              style={{
                display: "flex",
                flexDirection: "column",
                transform: `translateY(${-pos * size}px)`,
              }}
            >
              {col.map((d, k) => (
                <span key={k} style={{ height: size, display: "block" }}>
                  {d}
                </span>
              ))}
            </span>
          </span>
        );
      })}
    </div>
  );
};

// Painel azul que varre a tela na troca de cena.
export const Wipe: React.FC<{ f: number; at: number; color?: string; dir?: 1 | -1 }> = ({
  f,
  at,
  color = C.brand,
  dir = 1,
}) => {
  if (f < at - 1 || f > at + 16) return null;
  const inP = ip(f, [at, at + 7], [100, 0], EASE_INOUT);
  const outP = ip(f, [at + 8, at + 15], [0, -100], EASE_INOUT);
  return (
    <AbsoluteFill
      style={{
        backgroundColor: color,
        transform: `translateY(${(inP + outP) * dir}%)`,
      }}
    />
  );
};

export const shake = (f: number, at: number, amp = 18, dur = 10) => {
  if (f < at || f > at + dur) return { x: 0, y: 0 };
  const k = 1 - (f - at) / dur;
  return {
    x: Math.sin((f - at) * 2.7) * amp * k,
    y: Math.cos((f - at) * 3.3) * amp * k,
  };
};

// Cada cena entra no meio de uma transição; o "lead" desloca o relógio dela para que
// f = 0 continue sendo o corte na batida.
export const LeadCtx = React.createContext(0);
export const useF = () => useCurrentFrame() - React.useContext(LeadCtx);
