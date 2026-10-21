import React, { useEffect, useState } from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  cancelRender,
  continueRender,
  delayRender,
  interpolate,
  staticFile,
  useCurrentFrame,
} from "remotion";

// Paleta do exemplo. Troque pela sua marca; azul sobre --night usa a variante clara.
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
  // Laranja editorial: acento de CONTEÚDO (a palavra em ênfase dos presets de apresentação, o anel
  // do nome). Nunca dado (isso é o azul) nem CTA (pílula preta). Sobre o azul de destaque o
  // contraste é ruim (~1,6:1): ali a ênfase fica em night.
  hot: "#ee591b",
};

export const FONT = "'Plus Jakarta Sans', system-ui, sans-serif";
export const MONO = "ui-monospace, SFMono-Regular, Menlo, monospace";
// Serifada da palavra em itálico dos presets (frase com *uma palavra*). Não é o par da casa: só a
// palavra marcada usa. Instrument Serif Italic (OFL), copiada pelo new.sh para public/serif-italic.ttf
// e carregada no useFont; Georgia só se o arquivo faltar.
export const SERIF = "'Motion Serif', Georgia, serif";

export const EASE = Easing.bezier(0.22, 1, 0.36, 1);
export const EASE_IN = Easing.bezier(0.64, 0, 0.78, 0);
export const EASE_INOUT = Easing.bezier(0.83, 0, 0.17, 1);

// Doutrina (C3): curva por comportamento, não por tipo de elemento. Âncoras do motion-taste.md
// (Copyright (c) 2026 Diffusion Studio Inc., MIT). O EASE da casa segue como padrão de entrada.
export const SETTLE = Easing.bezier(0, 0.65, 0.51, 0.99); // assentamento: contagem que pousa, logo
export const EXIT = Easing.bezier(1, 0.02, 0.54, 0.42); // saída que acelera (a última cena, o fade)
// Overshoot (~10% com s = 1,70158) e antecipação: Easing.back é ease-in (recua antes de ir).
export const POP = Easing.out(Easing.back(1.7));
export const ANTIC = Easing.back(1.7);
// Hit-stop: o tempo do elemento congela `hold` quadros no impacto; o resto da cena segue.
export const hitStop = (f: number, at: number, hold = 3) => (f < at ? f : f < at + hold ? at : f - hold);

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

// Fonte principal: sem ela o filme sairia inteiro em system-ui, então o render para com a mensagem.
// A serifada da ênfase é opcional: projeto antigo sem serif-italic.ttf cai no Georgia e segue.
const FONTE_PRINCIPAL = "PlusJakartaSans.ttf";

export const useFont = () => {
  const [handle] = useState(() => delayRender("font"));
  useEffect(() => {
    const principal = new FontFace("Plus Jakarta Sans", `url(${staticFile(FONTE_PRINCIPAL)})`, { weight: "200 800" });
    const serif = new FontFace("Motion Serif", `url(${staticFile("serif-italic.ttf")})`, { style: "italic", weight: "400" });
    Promise.all([
      principal
        .load()
        .then((f) => document.fonts.add(f))
        .catch((e) => {
          cancelRender(
            new Error(
              `fonte principal não carregou: public/${FONTE_PRINCIPAL} (${e}). ` +
                "Copie o arquivo de novo para public/ (o new.sh da skill faz isso) ou troque FONT e useFont no src/lib.tsx.",
            ),
          );
        }),
      serif
        .load()
        .then((f) => document.fonts.add(f))
        .catch((e) => console.error(e)),
    ]).then(() => continueRender(handle));
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

// Símbolo da marca (public/marca.png, o MOTION_MARK do new.sh) entrando com escala e opacidade.
// Caixa fixa w×h centrada em (cx, cy) com objectFit contain: qualquer proporção cabe sem esticar.
// at = frame em que a entrada começa; dur = duração da entrada; out = [início, fim] da saída.
export const MarkIn: React.FC<{
  f: number;
  cx: number;
  cy: number;
  w: number;
  h: number;
  at?: number;
  dur?: number;
  from?: number;
  out?: [number, number];
}> = ({ f, cx, cy, w, h, at = 0, dur = 18, from = 0.6, out }) => {
  const t = ip(f, [at, at + dur], [0, 1]);
  const o = ip(f, [at, at + dur * 0.6], [0, 1]) * (out ? ip(f, out, [1, 0]) : 1);
  return (
    <Img
      src={staticFile("marca.png")}
      style={{
        position: "absolute",
        left: cx - w / 2,
        top: cy - h / 2,
        width: w,
        height: h,
        objectFit: "contain",
        opacity: o,
        transform: `scale(${from + (1 - from) * t})`,
      }}
    />
  );
};

// Contador: inteiro interpolado até o alvo, formatado em pt-BR ("2.700"). O alvo invisível
// na mesma célula reserva a largura final, então o número não empurra o layout ao crescer.
export const Counter: React.FC<{
  value: number;
  progress: number;
  size: number;
  color: string;
  weight?: number;
  ease?: (t: number) => number;
}> = ({ value, progress, size, color, weight = 800, ease = EASE }) => {
  const p = Math.min(1, Math.max(0, progress));
  const n = Math.round(value * ease(p));
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
