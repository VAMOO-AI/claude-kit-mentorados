// Base das cenas do Film: tipos da timeline, guia segura do formato e utilitários de tempo e
// tamanho. Mora aqui (e não no film-scenes.tsx) para que arquivo de cena novo importe sem ciclo;
// o film-scenes.tsx reexporta tudo, então quem importava de lá continua igual.
import React from "react";
import { measureText } from "@remotion/layout-utils";
import { continueRender, delayRender, useVideoConfig } from "remotion";
import { FONT, fontesCarregadas } from "./lib";
import { bt, corpoNumero, decimaisDe, first, fmtNum, hitAt } from "./tempos.mjs";

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

// bt (frame local da fala i), first (o 1º elemento entra antes do corte, f < 0: use first(p)
// como `at` do primeiro MaskUp/fade de toda cena) e hitAt (sem fala, o elemento i cai na batida
// i·passo, 15 frames = 1 batida a 120 BPM; com fala i, na fala) moram no tempos.mjs: a cena e o
// som (sons.mjs) usam as mesmas funções.
export { bt, first, hitAt };

// Estilo do texto que o fit() mede. O padrão é o do H1 (600, −0,04em); passe o que a cena muda
// (peso 800, outro letterSpacing, caixa alta do LABEL).
export type Estilo = {
  fontWeight?: number; letterSpacing?: string; wordSpacing?: string;
  textTransform?: "uppercase" | "none"; fontFamily?: string; fontVariantNumeric?: string;
};
const ESTILO_H1: Estilo = { fontWeight: 600, letterSpacing: "-0.04em", wordSpacing: "0.04em" };

// Largura real do texto em px, medida no navegador com a fonte já carregada (layout-utils).
export const largura = (s: string, fs: number, st: Estilo = {}) => {
  const e = { ...ESTILO_H1, ...st };
  return measureText({
    text: s, fontFamily: e.fontFamily ?? FONT, fontSize: fs, fontWeight: e.fontWeight,
    letterSpacing: e.letterSpacing, textTransform: e.textTransform, fontVariantNumeric: e.fontVariantNumeric,
    additionalStyles: e.wordSpacing ? { wordSpacing: e.wordSpacing } : undefined, validateFontIsLoaded: true,
  }).width;
};
export const mede = () => typeof document !== "undefined" && fontesCarregadas();

// Fonte que cabe na largura, medida: a linha mais larga, no corpo `base`, com a fonte real (C5).
// `folga` cobre o que cresce depois do layout (Breathe 1,035; push; scale de entrada que assenta
// em 1). Antes da fonte carregar (ou fora do navegador) cai na estimativa por caractere: Plus
// Jakarta 600 ≈ 0,56 em (800 em caixa alta ≈ 0,62–0,72), que é o `k`. Film e Reel só montam as
// cenas depois do useFont, então no render a estimativa não aparece.
export const fit = (lines: string[], maxW: number, base: number, k = 0.56, st: Estilo = {}, folga = 1.05) => {
  const texto = lines.filter((s) => s.length > 0);
  if (!texto.length) return base;
  if (!mede()) return Math.min(base, Math.floor(maxW / (Math.max(...texto.map((s) => s.length)) * k)));
  const w = Math.max(...texto.map((s) => largura(s, base, st)));
  return Math.max(1, Math.min(base, Math.floor((base * maxW) / (w * folga))));
};

// Número do Counter (800, tabular) com prefixo e sufixo a 60% do corpo, como o Conta das cenas
// avulsas desenha: largura medida no corpo `fs`.
const NUMERO: Estilo = { fontWeight: 800, letterSpacing: "-0.04em", wordSpacing: undefined, fontVariantNumeric: "tabular-nums" };
type Num = { v: number; prefix?: string; suffix?: string };
export const larguraNumero = (it: Num, fs: number) =>
  largura(fmtNum(it.v, decimaisDe(it.v)), fs, NUMERO) +
  [it.prefix, it.suffix].reduce((s, x) => s + (x ? largura(String(x), fs * 0.6, { fontWeight: 800 }) + fs * 0.06 : 0), 0);
// Corpo do número que cabe na largura (medido; sem fonte, a estimativa do corpoNumero do tempos.mjs).
export const corpoNumeroMedido = (it: Num, maxW: number, base: number, folga = 1.05) =>
  mede() ? Math.max(12, Math.min(base, Math.floor((base * maxW) / (larguraNumero(it, base) * folga)))) : corpoNumero(it, maxW, base);

// Quebra equilibrada: a frase numa linha se ela cabe com pelo menos `minimo` do corpo base; senão
// em duas linhas de largura parecida (o corte entre palavras que deixa a linha mais larga menor).
// Devolve as linhas e o corpo; a cena desenha com textWrap "balance" para o navegador quebrar igual.
export const equilibrar = (s: string, maxW: number, base: number, k = 0.56, st: Estilo = {}, folga = 1.05, minimo = 0.7) => {
  const uma = fit([s], maxW, base, k, st, folga);
  const pal = s.split(/\s+/).filter(Boolean);
  if (uma >= base * minimo || pal.length < 2) return { linhas: [s], fs: uma };
  let melhor = { linhas: [s], fs: uma };
  for (let i = 1; i < pal.length; i++) {
    const linhas = [pal.slice(0, i).join(" "), pal.slice(i).join(" ")];
    const fs = fit(linhas, maxW, base, k, st, folga);
    if (fs > melhor.fs) melhor = { linhas, fs };
  }
  return melhor;
};


export const H1: React.CSSProperties = { fontWeight: 600, letterSpacing: "-0.04em", lineHeight: 1.04, wordSpacing: "0.04em" };
export const LABEL: React.CSSProperties = { fontWeight: 800, letterSpacing: "0.16em", textTransform: "uppercase" };


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
