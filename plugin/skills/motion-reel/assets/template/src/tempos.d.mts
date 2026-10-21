// Tipos do tempos.mjs (contas puras das cenas avulsas).
export declare const GAP_MORPH: number;
export declare const GAP_RANKING: number;
export declare function temposMorph(nEstados: number, falas: number[], t0: number, step: number, loop: boolean): number[];
export declare function temposRanking(n: number, falas: number[], t0: number, step: number): number[];
export declare function ordenarRanking<T extends { v: number }>(items: T[], low: boolean, max?: number): T[];
export declare function letras(s: unknown): string[];
export declare function palavras(chars: string[]): [number, number][];
export declare function decimaisDe(v: number): number;
export declare function fmtNum(v: number, casas?: number): string;
export declare function maiorValor(valores: number[]): number;
export declare function corpoNumero(it: { v: number; prefix?: string; suffix?: string }, largura: number, base: number): number;
export declare function enquadramento(paradas: [number, number][], temRegiao: boolean): [number, number][];
