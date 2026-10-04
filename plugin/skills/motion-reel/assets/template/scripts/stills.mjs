// node scripts/stills.mjs <Master169|Reel916|Reel> [frac=0.7] [scale=0.4] [idx...]
// 1 quadro por cena (em cut + frac·len; várias frações com vírgula: 0.2,0.8) via renderStill,
// sem render do vídeo inteiro, + folhas de contato em out/stills-<comp>/sheet-NN.jpg.
// Bom para revisar layout depois de mexer em poucas cenas: passe só os índices delas.
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const [comp = "Master169", fracS = "0.7", scaleS = "0.4", ...only] = process.argv.slice(2);

let scenes, total, inputProps;
if (comp === "Reel") {
  const d = JSON.parse(fs.readFileSync(path.join(root, "src/timeline.json"), "utf8"));
  total = d.total;
  scenes = d.scenes.map((s, i) => ({ cut: s.cut, len: (d.scenes[i + 1]?.cut ?? d.total) - s.cut }));
  inputProps = { withAudio: false };
} else {
  const tl = JSON.parse(fs.readFileSync(path.join(root, `src/tl-${comp === "Master169" ? "master" : "reel"}.json`), "utf8"));
  total = tl.total;
  scenes = tl.scenes;
  inputProps = { tl, audio: "x.wav", withAudio: false };
}

const out = path.join(root, `out/stills-${comp}`);
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
const serveUrl = await bundle({ entryPoint: path.join(root, "src/index.tsx") });
const composition = await selectComposition({ serveUrl, id: comp, inputProps });
const fracs = fracS.split(",").map(Number);
let n = 0;
for (const [i, s] of scenes.entries()) {
  if (only.length && !only.includes(String(i))) continue;
  for (const fr of fracs) {
    const frame = Math.min(total - 1, Math.round(s.cut + fr * s.len));
    const file = path.join(out, `${String(n++).padStart(3, "0")}.png`);
    await renderStill({ composition, serveUrl, output: file, frame, inputProps, scale: Number(scaleS) });
  }
}
const cols = composition.width > composition.height ? 4 : 6;
execFileSync("ffmpeg", ["-v", "error", "-y", "-pattern_type", "glob", "-i", `${out}/*.png`, "-vf", `tile=${cols}x4:padding=6:color=white`, `${out}/sheet-%02d.jpg`]);
console.log(`ok: ${n} quadros → ${out}`);
