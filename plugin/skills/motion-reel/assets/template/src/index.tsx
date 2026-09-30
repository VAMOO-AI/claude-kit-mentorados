import React from "react";
import { Composition, registerRoot } from "remotion";
import { Reel } from "./Reel";
import { FPS, TOTAL } from "./timeline";

const Root: React.FC = () => (
  <Composition id="Reel" component={Reel} durationInFrames={TOTAL} fps={FPS} width={1080} height={1920} defaultProps={{ withAudio: true }} />
);
registerRoot(Root);
