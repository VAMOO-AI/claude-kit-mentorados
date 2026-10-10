import React from "react";
import { AbsoluteFill, Audio, staticFile, useCurrentFrame } from "remotion";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { C, LeadCtx, useFont } from "./lib";
import { SLOTS } from "./timeline";
import { presentation } from "./transitions";
import * as S from "./scenes";

const SCENES: Record<string, React.FC<{ symbol?: boolean }>> = {
  intro: S.Intro,
  grande: S.Grande,
  atualizacao: S.Atualizacao,
  mosaic: S.Mosaic,
  title: S.Title,
  models: S.Models,
  hours: S.Hours,
  terminals: S.Terminals,
  credit: S.Credit,
  voce: S.Voce,
  performar: S.Performar,
  claude: S.NoUsoDoClaude,
  outro: S.Outro,
};

// Origem de cada íris: onde o olho já está na cena seguinte.
const ORIGIN: Record<string, { cx: number; cy: number; color?: string }> = {
  grande: { cx: 540, cy: 860, color: C.brand },
  hours: { cx: 540, cy: 820, color: C.brandOnDark },
  outro: { cx: 870, cy: 1240, color: C.brand },
};

// Deriva lenta de câmera — nunca estática. Mosaico e título ficam fora: são um match cut.
const Breathe: React.FC<{ dur: number; on: boolean; children: React.ReactNode }> = ({ dur, on, children }) => {
  const f = useCurrentFrame();
  const s = on ? 1 + 0.035 * (f / dur) : 1;
  return <AbsoluteFill style={{ transform: `scale(${s})` }}>{children}</AbsoluteFill>;
};

export const Reel: React.FC<{ withAudio?: boolean }> = ({ withAudio = true }) => {
  useFont();
  const items: React.ReactNode[] = [];
  SLOTS.forEach((slot, i) => {
    const Scene = SCENES[slot.id];
    if (i > 0 && slot.dIn > 0) {
      items.push(
        <TransitionSeries.Transition
          key={`t-${slot.id}`}
          timing={linearTiming({ durationInFrames: slot.dIn })}
          presentation={presentation(slot.inType, ORIGIN[slot.id] ?? {})}
        />,
      );
    }
    items.push(
      <TransitionSeries.Sequence key={slot.id} durationInFrames={slot.dur} name={slot.id}>
        <LeadCtx.Provider value={slot.lead}>
          <Breathe dur={slot.dur} on={slot.id !== "mosaic" && slot.id !== "title"}>
            <Scene symbol={slot.symbol} />
          </Breathe>
        </LeadCtx.Provider>
      </TransitionSeries.Sequence>,
    );
  });
  return (
    <AbsoluteFill style={{ backgroundColor: C.night }}>
      <TransitionSeries>{items}</TransitionSeries>
      {withAudio ? <Audio src={staticFile("track.wav")} /> : null}
    </AbsoluteFill>
  );
};
