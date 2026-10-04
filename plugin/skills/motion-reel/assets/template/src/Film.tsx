import React from "react";
import { AbsoluteFill, Audio, random, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { C, EASE_INOUT, LeadCtx, ip, useFont } from "./lib";
import { presentation } from "./transitions";
import { FilmCtx, SCENES, TL } from "./film-scenes";

// Composição genérica: lê a timeline (src/tl-<formato>.json, gerada pelo build-timeline.py) por
// props. Serve 16:9 e 9:16; quem decide o tamanho é a Composition no index.tsx.

// Deriva lenta de câmera: nenhuma cena fica estática.
const Breathe: React.FC<{ dur: number; children: React.ReactNode }> = ({ dur, children }) => {
  const f = useCurrentFrame();
  return <AbsoluteFill style={{ transform: `scale(${1 + 0.03 * (f / dur)})` }}>{children}</AbsoluteFill>;
};

// Letterbox 2.39:1 (no 9:16, faixas de 11%) até o corte da cena-âncora; abre no impacto.
const Letterbox: React.FC<{ until: number }> = ({ until }) => {
  const f = useCurrentFrame();
  const { width: W, height: H } = useVideoConfig();
  const full = H > W ? H * 0.11 : (H - W / 2.39) / 2;
  const h = full * (1 - ip(f, [until - 2, until + 16], [0, 1], EASE_INOUT));
  if (h <= 0.5) return null;
  return (
    <>
      <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: h, background: "#000" }} />
      <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: h, background: "#000" }} />
    </>
  );
};

// Grão de película: um tile de ruído (public/grain.png, gerado pelo new.sh) que salta de
// posição a cada 2 frames.
const Grain: React.FC = () => {
  const f = useCurrentFrame();
  const k = Math.floor(f / 2);
  return (
    <AbsoluteFill
      style={{
        backgroundImage: `url(${staticFile("grain.png")})`,
        backgroundPosition: `${Math.floor(random(`gx${k}`) * 512)}px ${Math.floor(random(`gy${k}`) * 512)}px`,
        mixBlendMode: "overlay",
        opacity: 0.07,
        pointerEvents: "none",
      }}
    />
  );
};

export const Film: React.FC<{ tl: TL; audio: string; withAudio?: boolean }> = ({ tl, audio, withAudio = true }) => {
  useFont();
  const sc = tl.scenes;
  const items: React.ReactNode[] = [];
  sc.forEach((s, i) => {
    const Scene = SCENES[s.type];
    if (!Scene) throw new Error(`cena "${s.type}" não registrada em SCENES (film-scenes.tsx)`);
    const next = sc[i + 1];
    const dIn = i > 0 ? s.d : 0;
    const dOut = next ? next.d : 0;
    const from = s.cut - dIn / 2;
    const end = next ? next.cut + dOut / 2 : tl.total;
    if (dIn > 0) {
      items.push(
        <TransitionSeries.Transition key={`t-${s.id}`} timing={linearTiming({ durationInFrames: dIn })} presentation={presentation(s.in, s.origin ?? {})} />,
      );
    }
    items.push(
      <TransitionSeries.Sequence key={s.id} durationInFrames={end - from} name={s.id}>
        <FilmCtx.Provider value={{ tl, idx: i }}>
          <LeadCtx.Provider value={dIn / 2}>
            <Breathe dur={end - from}>
              <Scene {...s.props} beats={s.beats} ends={s.ends} len={s.len} energy={s.energy} />
            </Breathe>
          </LeadCtx.Provider>
        </FilmCtx.Provider>
      </TransitionSeries.Sequence>,
    );
  });
  const lbCut = tl.letterbox ? sc.find((s) => s.type === tl.letterbox)?.cut : undefined;
  return (
    <AbsoluteFill style={{ backgroundColor: C.night }}>
      <TransitionSeries>{items}</TransitionSeries>
      <Grain />
      {lbCut !== undefined ? <Letterbox until={lbCut} /> : null}
      {withAudio ? <Audio src={staticFile(audio)} /> : null}
    </AbsoluteFill>
  );
};
