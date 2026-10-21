// Ponte do som: lê src/tl-<formato>.json e imprime em JSON os sons que cada cena declara em
// src/sons.mjs. Chamado pelo scripts/track_cinema.py (node scripts/sons.mjs src/tl-master.json).
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const { sonsDaTimeline } = await import(pathToFileURL(path.join(raiz, "src/sons.mjs")).href);
const tl = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
process.stdout.write(JSON.stringify(sonsDaTimeline(tl)));
