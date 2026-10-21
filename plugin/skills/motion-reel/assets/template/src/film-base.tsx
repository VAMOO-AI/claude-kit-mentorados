// Base das cenas do Film: tipos da timeline, guia segura do formato e utilitários de tempo e
// tamanho. Mora aqui (e não no film-scenes.tsx) para que arquivo de cena novo importe sem ciclo;
// o film-scenes.tsx reexporta tudo, então quem importava de lá continua igual.
import React from "react";
import { continueRender, delayRender, useVideoConfig } from "remotion";

/* ───────────────────────── tipos e utilitários ───────────────────────── */

export type Scene = {
  id: string; type: string; cut: number; in: string; d: number; len: number;
  beats: number[]; ends: number[]; vo: string[]; mark: string | null; energy: number;
  origin?: { cx: number; cy: number; color?: string } | null;
  props: Record<string, any>;
};
// motionBlur: motion blur real nas transições rápidas (film.json → build-timeline.py); null = desligado.
export type TL = {
  name: string; fps: number; total: number; letterbox?: string | null;
  motionBlur?: { samples: number; shutter: number } | null; scenes: Scene[];
};
export type SP = { beats: number[]; ends: number[]; len: number; energy: number } & Record<string, any>;

export const FilmCtx = React.createContext<{ tl: TL | null; idx: number }>({ tl: null, idx: 0 });

// Guia segura do formato: 16:9 = title-safe (~6%); 9:16 = guia do Reel (botões do Instagram à
// direita e embaixo). O qa.sh desenha a mesma guia no safe.jpg.
export const useL = () => {
  const { width: W, height: H } = useVideoConfig();
  const v = H > W;
  return { W, H, v, l: v ? 90 : 120, r: v ? 180 : 120, t: v ? 200 : 96, b: v ? 340 : 96 };
};

// Frame local da fala i (frac = 0 início, 1 fim). Sem fala i: começo + 30.
export const bt = (p: SP, i: number, frac = 0) => {
  const b = p.beats[i] ?? 0;
  const e = p.ends[i] ?? b + 30;
  return Math.round(b + frac * (e - b));
};

// Fonte que cabe na largura: Plus Jakarta 600 ≈ 0,56 em por caractere (800 em caixa alta ≈ 0,62–0,72).
export const fit = (lines: string[], maxW: number, base: number, k = 0.56) => {
  const n = Math.max(...lines.map((s) => s.length));
  return Math.min(base, Math.floor(maxW / (n * k)));
};

// O primeiro elemento da cena entra ANTES do corte (f < 0): a transição de entrada nunca revela
// tela vazia. Use first(p) como `at` do primeiro MaskUp/fade de toda cena.
export const first = (p: SP) => Math.min(bt(p, 0) - 6, -8);

export const H1: React.CSSProperties = { fontWeight: 600, letterSpacing: "-0.04em", lineHeight: 1.04, wordSpacing: "0.04em" };
export const LABEL: React.CSSProperties = { fontWeight: 800, letterSpacing: "0.16em", textTransform: "uppercase" };

// Sem fala, o ritmo é da trilha: o elemento i cai na batida i·passo (15 frames = 1 batida a
// 120 BPM, a grade do track_cinema.py). Com fala i, cai na fala. O índice 0 entra em first(p).
export const hitAt = (p: SP, i: number, step: number) =>
  i === 0 ? first(p) : i < p.beats.length ? bt(p, i) - 4 : i * step;

// Proporção do PNG para dar largura às camadas e à máscara do brilho. Segura o render até a
// imagem carregar: o Remotion não espera background/mask de CSS sozinho.
export const useImgRatio = (src: string, fallback = 1) => {
  const [ratio, setRatio] = React.useState(fallback);
  const [handle] = React.useState(() => delayRender(`img ${src}`));
  React.useEffect(() => {
    const img = new Image();
    img.onload = () => {
      if (img.naturalHeight) setRatio(img.naturalWidth / img.naturalHeight);
      continueRender(handle);
    };
    img.onerror = () => continueRender(handle);
    img.src = src;
  }, [src, handle]);
  return ratio;
};

// Frase com *uma palavra* marcada → palavras com a marca. A marcada vira itálico serifado colorido
// (emStyle) nos presets de apresentação; o resto segue o H1 da casa.
export type Word = { t: string; em: boolean };
export const emWords = (s: string): Word[] =>
  s
    .split(/(\*[^*]+\*)/)
    .filter(Boolean)
    .flatMap((part) => {
      const em = part.length > 2 && part.startsWith("*") && part.endsWith("*");
      return (em ? part.slice(1, -1) : part).split(/\s+/).filter(Boolean).map((t) => ({ t, em }));
    })
    // pontuação logo depois da marca ("*no azul*.") gruda na palavra anterior
    .reduce<Word[]>((out, w) => {
      if (out.length && /^[.,!?;:…]+$/.test(w.t)) out[out.length - 1] = { ...out[out.length - 1], t: out[out.length - 1].t + w.t };
      else out.push(w);
      return out;
    }, []);
export const plain = (s: string) => s.replace(/\*/g, "");
