// Fonte única de tempo: vídeo e trilha (scripts/track.py) leem o mesmo JSON.
// "cut" = frame em que a transição passa do meio — sempre na batida (120 BPM = 15 frames).
import data from "./timeline.json";

export type SceneId = (typeof data.scenes)[number]["id"];
export const FPS = data.fps;
export const TOTAL = data.total;
export const MODELS = data.models;

export type Slot = { id: string; cut: number; inType: string; dIn: number; dOut: number; from: number; dur: number; lead: number };

export const SLOTS: Slot[] = data.scenes.map((s, i) => {
  const next = data.scenes[i + 1] as (typeof data.scenes)[number] | undefined;
  const dIn = (s as { d?: number }).d ?? 0;
  const dOut = next ? ((next as { d?: number }).d ?? 0) : 0;
  const from = s.cut - dIn / 2;
  const end = next ? next.cut + dOut / 2 : data.total;
  return { id: s.id, cut: s.cut, inType: (s as { in?: string }).in ?? "cut", dIn, dOut, from, dur: end - from, lead: dIn / 2 };
});
