import React, { useId } from "react";
import { AbsoluteFill, random } from "remotion";
import type {
  TransitionPresentation,
  TransitionPresentationComponentProps,
} from "@remotion/transitions";
import { C, EASE_INOUT } from "./lib";

type Props = {
  kind: string;
  cx?: number;
  cy?: number;
  color?: string;
};
type TP = TransitionPresentationComponentProps<Props>;

const W = 1080;
const H = 1920;
const MAX_R = Math.hypot(W, H);

// Blur direcional via SVG (CSS blur é isotrópico): simula motion blur de câmera.
const DirBlur: React.FC<{ x: number; y: number; children: React.ReactNode; style?: React.CSSProperties }> = ({
  x,
  y,
  children,
  style,
}) => {
  const id = "b" + useId().replace(/[^a-zA-Z0-9]/g, "");
  const on = x > 0.3 || y > 0.3;
  return (
    <AbsoluteFill style={{ ...style, filter: on ? `url(#${id})` : undefined }}>
      {on ? (
        <svg width={0} height={0} style={{ position: "absolute" }}>
          <filter id={id} x="-20%" y="-20%" width="140%" height="140%">
            <feGaussianBlur stdDeviation={`${x} ${y}`} />
          </filter>
        </svg>
      ) : null}
      {children}
    </AbsoluteFill>
  );
};

const bell = (p: number) => Math.sin(Math.PI * Math.min(1, Math.max(0, p)));

/* Íris: a cena nova abre num círculo; a antiga empurra a câmera. */
const Iris: React.FC<TP> = ({ children, presentationDirection, presentationProgress, passedProps }) => {
  const p = EASE_INOUT(presentationProgress);
  const cx = passedProps.cx ?? W / 2;
  const cy = passedProps.cy ?? H / 2;
  if (presentationDirection === "exiting") {
    return <AbsoluteFill style={{ transform: `scale(${1 + p * 0.18})`, transformOrigin: `${cx}px ${cy}px` }}>{children}</AbsoluteFill>;
  }
  const r = p * MAX_R;
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ clipPath: `circle(${r}px at ${cx}px ${cy}px)`, transform: `scale(${1.12 - 0.12 * p})`, transformOrigin: `${cx}px ${cy}px` }}>
        {children}
      </AbsoluteFill>
      <svg width={W} height={H} style={{ position: "absolute", pointerEvents: "none" }}>
        <circle cx={cx} cy={cy} r={r} fill="none" stroke={passedProps.color ?? C.brand} strokeWidth={14 * (1 - p)} />
        <circle cx={cx} cy={cy} r={r * 0.82} fill="none" stroke={passedProps.color ?? C.brand} strokeWidth={4 * (1 - p)} opacity={0.6} />
      </svg>
    </AbsoluteFill>
  );
};

/* Whip pan: as duas cenas correm juntas com blur de movimento no eixo. */
const Whip: React.FC<TP> = ({ children, presentationDirection, presentationProgress, passedProps }) => {
  const p = EASE_INOUT(presentationProgress);
  const vertical = passedProps.kind === "whipUp" || passedProps.kind === "push";
  const blur = bell(presentationProgress) * (passedProps.kind === "push" ? 38 : 70);
  const off = presentationDirection === "entering" ? (1 - p) * 100 : -p * 100;
  const t = vertical ? `translateY(${off}%)` : `translateX(${off}%)`;
  return (
    <DirBlur x={vertical ? 0 : blur} y={vertical ? blur : 0} style={{ transform: t }}>
      {children}
    </DirBlur>
  );
};

/* Persianas: barras em cascata cobrem e descobrem, trocando a cena por baixo. */
const Bars: React.FC<TP> = ({ children, presentationDirection, presentationProgress }) => {
  const n = 8;
  if (presentationDirection === "exiting") {
    return <AbsoluteFill style={{ transform: `scale(${1 - presentationProgress * 0.06})` }}>{children}</AbsoluteFill>;
  }
  const p = presentationProgress;
  const cols = [C.brand, C.night, C.accentFill, C.night];
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ opacity: p >= 0.5 ? 1 : 0 }}>{children}</AbsoluteFill>
      {Array.from({ length: n }, (_, i) => {
        const st = (i / n) * 0.22;
        const cover = EASE_INOUT(Math.min(1, Math.max(0, (p - st) / 0.28)));
        const unc = EASE_INOUT(Math.min(1, Math.max(0, (p - 0.5 - st) / 0.28)));
        const h = cover - unc;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: `${(i / n) * 100}%`,
              width: `${100 / n + 0.2}%`,
              top: `${unc * 100}%`,
              height: `${h * 100}%`,
              background: cols[i % cols.length],
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

/* Glitch digital: fatias deslocadas + separação de canal, só no meio da troca. */
const Glitch: React.FC<TP> = ({ children, presentationDirection, presentationProgress }) => {
  const p = presentationProgress;
  const visible = presentationDirection === "entering" ? p >= 0.5 : p < 0.5;
  if (!visible) return null;
  const k = Math.floor(p * 24);
  const intensity = bell(p);
  const slices = 7;
  return (
    <AbsoluteFill>
      {Array.from({ length: slices }, (_, i) => {
        const top = (i / slices) * 100;
        const dx = (random(`gx${k}-${i}`) - 0.5) * 220 * intensity;
        return (
          <AbsoluteFill key={i} style={{ clipPath: `inset(${top}% 0 ${100 - top - 100 / slices}% 0)`, transform: `translateX(${dx}px)` }}>
            {children}
          </AbsoluteFill>
        );
      })}
      <AbsoluteFill style={{ mixBlendMode: "screen", pointerEvents: "none" }}>
        {Array.from({ length: 5 }, (_, i) => (
          <div
            key={i}
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              top: `${random(`gl${k}-${i}`) * 100}%`,
              height: 4 + random(`gh${k}-${i}`) * 26,
              background: i % 2 ? C.brandOnDark : C.white,
              opacity: 0.55 * intensity,
            }}
          />
        ))}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/* Painel diagonal duplo: azul e night varrem em chanfro. */
const Panel: React.FC<TP> = ({ children, presentationDirection, presentationProgress }) => {
  if (presentationDirection === "exiting") {
    return <AbsoluteFill style={{ transform: `translateX(${-EASE_INOUT(presentationProgress) * 12}%)` }}>{children}</AbsoluteFill>;
  }
  const p = presentationProgress;
  const layer = (delay: number, color: string) => {
    const a = EASE_INOUT(Math.min(1, Math.max(0, (p - delay) / 0.45)));
    const b = EASE_INOUT(Math.min(1, Math.max(0, (p - 0.5 - delay) / 0.45)));
    const lead = 130 - a * 160; // borda que cobre
    const trail = 160 - b * 190; // borda que descobre
    return (
      <AbsoluteFill
        style={{
          background: color,
          clipPath: `polygon(${lead}% 0, ${trail}% 0, ${trail - 30}% 100%, ${lead - 30}% 100%)`,
        }}
      />
    );
  };
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ opacity: p >= 0.5 ? 1 : 0, transform: `translateX(${(1 - EASE_INOUT(p)) * 10}%)` }}>{children}</AbsoluteFill>
      {layer(0, C.brand)}
      {layer(0.06, C.night)}
    </AbsoluteFill>
  );
};

/* Spin zoom: as duas cenas giram no mesmo sentido, com escala e blur. */
const Spin: React.FC<TP> = ({ children, presentationDirection, presentationProgress }) => {
  const p = EASE_INOUT(presentationProgress);
  const blur = bell(presentationProgress) * 14;
  if (presentationDirection === "exiting") {
    return (
      <AbsoluteFill style={{ transform: `rotate(${p * 32}deg) scale(${1 + p * 1.6})`, filter: `blur(${blur}px)`, opacity: 1 - p * 0.4 }}>
        {children}
      </AbsoluteFill>
    );
  }
  return (
    <AbsoluteFill style={{ transform: `rotate(${(p - 1) * 32}deg) scale(${1 + (1 - p) * 1.1})`, filter: `blur(${blur}px)`, opacity: Math.min(1, p * 2.5) }}>
      {children}
    </AbsoluteFill>
  );
};

const byKind: Record<string, React.FC<TP>> = {
  iris: Iris,
  ink: Iris,
  whip: Whip,
  whipUp: Whip,
  push: Whip,
  bars: Bars,
  glitch: Glitch,
  panel: Panel,
  spin: Spin,
};

const Router: React.FC<TP> = (props) => {
  const Comp = byKind[props.passedProps.kind];
  return <Comp {...props} />;
};

export const presentation = (kind: string, extra: Partial<Props> = {}): TransitionPresentation<Props> => ({
  component: Router,
  props: { kind, ...extra },
});
