// Tipos do sons.mjs (sons declarados por cena, lidos pelo track_cinema.py).
import type { Falas } from "./tempos.mjs";
export type Som = { f: number; sfx: string; g: number; rep?: number; every?: number; impacto?: boolean; sintese?: number };
export declare const SONS: Record<string, (s: Falas & Record<string, any>, p: Record<string, any>) => Som[]>;
export declare function sonsDaTimeline(tl: { scenes: (Falas & { type: string; props?: Record<string, any> })[] }): (Som & { cena: number })[];
