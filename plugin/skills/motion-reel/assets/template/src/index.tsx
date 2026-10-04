import React from "react";
import { Composition, registerRoot } from "remotion";
import { Reel } from "./Reel";
import { FPS, TOTAL } from "./timeline";
import { Film } from "./Film";
import type { TL } from "./film-scenes";
import master from "./tl-master.json";
import reel from "./tl-reel.json";

// Reel: o reel-exemplo guiado pela música (timeline.json + scenes.tsx), só 9:16.
// Master169 / Reel916: o Film (film.json → build-timeline.py → tl-*.json), guiado pela voz ou
// pelos `min` de cada cena, com a mesma base de cenas nos dois formatos.
const M = master as unknown as TL;
const R = reel as unknown as TL;

const Root: React.FC = () => (
  <>
    <Composition id="Reel" component={Reel} durationInFrames={TOTAL} fps={FPS} width={1080} height={1920} defaultProps={{ withAudio: true }} />
    <Composition id="Master169" component={Film} durationInFrames={M.total} fps={M.fps} width={1920} height={1080} defaultProps={{ tl: M, audio: "mix-master.wav", withAudio: true }} />
    <Composition id="Reel916" component={Film} durationInFrames={R.total} fps={R.fps} width={1080} height={1920} defaultProps={{ tl: R, audio: "mix-reel.wav", withAudio: true }} />
  </>
);
registerRoot(Root);
