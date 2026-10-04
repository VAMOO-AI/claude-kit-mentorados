// Cenas do Film (16:9 e 9:16, com ou sem narração): um componente por "type" do film.json.
// Toda cena recebe beats/ends (frame local de início/fim de cada fala) e anima em cima deles:
// a voz manda no tempo. f = 0 é o corte na batida (useF). O layout lê o tamanho do vídeo
// (useL), então o mesmo componente serve o master 16:9 e o corte 9:16.
// Cena nova: copie uma daqui, registre em SCENES e, se ela tiver som próprio, espelhe os
// pontos em scripts/track_cinema.py (SFX_BY_TYPE) ou use "cues" no film.json.
import React from "react";
import { AbsoluteFill, Img, staticFile, useVideoConfig } from "remotion";
import { evolvePath } from "@remotion/paths";
import { Motif } from "./motifs";
import { AsstText, Composer, D, Desk, EditCard, UserMsg, Working, fadeIn, typing } from "./desktop";
import { Bg, C, Counter, EASE_INOUT, MONO, MaskUp, hollow, ip, lemniscatePath, shake, useF } from "./lib";

/* ───────────────────────── tipos e utilitários ───────────────────────── */

export type Scene = {
  id: string; type: string; cut: number; in: string; d: number; len: number;
  beats: number[]; ends: number[]; vo: string[]; mark: string | null; energy: number;
  origin?: { cx: number; cy: number; color?: string } | null;
  props: Record<string, any>;
};
export type TL = { name: string; fps: number; total: number; letterbox?: string | null; scenes: Scene[] };
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

const Pill: React.FC<{ f: number; at: number; dark?: boolean; children: React.ReactNode; size?: number }> = ({ f, at, dark = true, children, size = 38 }) => (
  <div style={{ display: "inline-block", background: dark ? C.ink : C.paper, border: `3px solid ${C.ink}`, color: dark ? C.white : C.ink, borderRadius: 100, padding: `${size * 0.5}px ${size * 1.2}px`, fontSize: size, fontWeight: 700, opacity: ip(f, [at, at + 8], [0, 1]), transform: `scale(${ip(f, [at, at + 14], [0.75, 1])})` }}>
    {children}
  </div>
);

/* ───────────────────────── frase em grupos (uma ideia por fala) ───────────────────────── */
// props: bg "night"|"paper", groups [{beat, frac?, lines[], hollowLast?}] — cada grupo entra na
// sua fala e sai quando o próximo entra.
export const Statement: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const dark = p.bg !== "paper";
  const bg = dark ? C.night : C.paper;
  const fg = dark ? C.white : C.ink;
  const groups: { beat: number; frac?: number; lines: string[]; hollowLast?: boolean }[] = p.groups;
  const starts = groups.map((g) => bt(p, g.beat, g.frac ?? 0) - 6);
  const fs = fit(groups.flatMap((g) => g.lines), L.W - L.l - L.r, L.v ? 104 : 124);
  return (
    <Bg color={bg}>
      {groups.map((g, gi) => {
        const at = gi === 0 ? Math.min(starts[0], -8) : starts[gi];
        const out = gi < groups.length - 1 ? starts[gi + 1] - 8 : undefined;
        return (
          <AbsoluteFill key={gi} style={{ justifyContent: "center", paddingLeft: L.l, paddingRight: L.r }}>
            {g.lines.map((ln, li) => {
              const hol = g.hollowLast && li === g.lines.length - 1;
              return (
                <div key={li}>
                  <MaskUp f={f} at={at + li * 5} out={out !== undefined ? out + li * 2 : undefined} dur={16}>
                    <span style={{ ...H1, fontSize: fs, ...(hol ? hollow(dark ? C.white : C.brand, 3, bg) : { color: fg }) }}>{ln}</span>
                  </MaskUp>
                </div>
              );
            })}
          </AbsoluteFill>
        );
      })}
    </Bg>
  );
};

/* ───────────────────────── título (impacto + tremor + traço que se desenha) ───────────────────────── */
// props: line1, line2 (vazada), sub?, pill? (entram na 2ª fala), symbol? (false tira o infinito)
export const Title: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const sh = shake(f, 0, 26, 14);
  const a = L.v ? 150 : 170;
  const cx = L.W / 2;
  const cy = L.v ? 640 : 250;
  const path = lemniscatePath(a, cx, cy);
  const draw = evolvePath(ip(f, [-8, 26], [0, 1], EASE_INOUT), path);
  const w1: string = p.line1 ?? "";
  const w2: string = p.line2 ?? "";
  const fs = fit([w1, w2], L.W - L.l - L.r, L.v ? 170 : 196, 0.62);
  const sub = bt(p, 1) - 4;
  const tilt = ip(f, [0, 40], [18, 0]);
  const letters = (w: string, d0: number, style: (t: number) => React.CSSProperties) =>
    w.split("").map((ch, i) => {
      const t = ip(f, [d0 + i * 1.5, d0 + 14 + i * 1.5], [0, 1]);
      return (
        <span key={i} style={{ ...H1, fontSize: fs, display: "inline-block", whiteSpace: "pre", opacity: t, transform: `translateY(${(1 - t) * 60}px) scale(${1.5 - 0.5 * t})`, ...style(t) }}>
          {ch}
        </span>
      );
    });
  return (
    <Bg color={C.night}>
      <AbsoluteFill style={{ transform: `translate(${sh.x}px, ${sh.y}px)` }}>
        {p.symbol !== false ? (
          <svg width={L.W} height={L.H} style={{ position: "absolute" }}>
            <path d={path} fill="none" stroke={C.brandOnDark} strokeWidth={18} strokeLinecap="round" strokeDasharray={draw.strokeDasharray} strokeDashoffset={draw.strokeDashoffset} />
          </svg>
        ) : null}
        <AbsoluteFill style={{ perspective: 1400, alignItems: "center", justifyContent: "center", paddingTop: p.symbol !== false ? (L.v ? 260 : 210) : 0 }}>
          <div style={{ transform: `rotateX(${tilt}deg)`, textAlign: "center" }}>
            <div style={{ display: "flex", justifyContent: "center" }}>{letters(w1, 2, () => ({ color: C.white }))}</div>
            {w2 ? <div style={{ display: "flex", justifyContent: "center", marginTop: -fs * 0.06 }}>{letters(w2, 10, () => hollow(C.brandOnDark, 3.5, C.night))}</div> : null}
            {p.sub && p.beats.length > 1 ? (
              <div style={{ marginTop: L.v ? 70 : 48, display: "flex", flexDirection: "column", alignItems: "center", gap: 22, paddingLeft: L.l, paddingRight: L.r }}>
                <MaskUp f={f} at={sub}>
                  <span style={{ fontSize: 44, fontWeight: 500, color: C.faint, letterSpacing: "-0.02em" }}>{p.sub}</span>
                </MaskUp>
                {p.pill ? (
                  <div style={{ opacity: ip(f, [bt(p, 1, 0.6), bt(p, 1, 0.6) + 10], [0, 1]), transform: `scale(${ip(f, [bt(p, 1, 0.6), bt(p, 1, 0.6) + 12], [0.8, 1])})`, background: C.white, color: C.ink, borderRadius: 100, padding: "18px 44px", fontSize: 38, fontWeight: 700 }}>
                    {p.pill}
                  </div>
                ) : null}
              </div>
            ) : null}
          </div>
        </AbsoluteFill>
      </AbsoluteFill>
    </Bg>
  );
};

/* ───────────────────────── números (um contador por fala) ───────────────────────── */
// props: items [{v, label}] — o contador i entra na fala i; os anteriores esmaecem.
export const Numbers: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const items: { v: number; label: string }[] = p.items;
  return (
    <Bg color={C.paper}>
      <AbsoluteFill style={{ padding: `${L.t}px ${L.r}px ${L.b}px ${L.l}px`, justifyContent: "center" }}>
        <div style={{ display: "flex", flexDirection: L.v ? "column" : "row", gap: L.v ? 70 : 40, justifyContent: "space-between" }}>
          {items.map((it, i) => {
            const at = i === 0 ? first(p) : bt(p, i) - 4;
            const prog = ip(f, [at, at + 22], [0, 1], (x) => x);
            const next = i + 1 < items.length ? bt(p, i + 1) - 4 : 1e9;
            const dim = f >= next ? 0.35 : 1;
            return (
              <div key={i} style={{ flex: 1, opacity: f >= at ? 1 : 0.1, display: "flex", flexDirection: L.v ? "row" : "column", alignItems: L.v ? "center" : "flex-start", gap: L.v ? 36 : 18 }}>
                {!L.v ? <div style={{ width: 380 * ip(f, [at, at + 18], [0, 1], EASE_INOUT), height: 3, background: dim < 1 ? C.line : C.brand }} /> : null}
                <div style={{ opacity: Math.max(dim, 0.35), minWidth: L.v ? 300 : undefined }}>
                  <Counter value={it.v} progress={prog} size={L.v ? 190 : 210} color={C.ink} />
                </div>
                <MaskUp f={f} at={at + 6}>
                  <span style={{ fontSize: L.v ? 46 : 40, fontWeight: 600, color: dim < 1 ? C.faint : C.dim, letterSpacing: "-0.02em" }}>{it.label}</span>
                </MaskUp>
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </Bg>
  );
};

/* ───────────────────────── conversa no Claude Code Desktop ───────────────────────── */
// props: kicker?, prompt, working?, files? [[arquivo, linhas]], reply, session?
// O pedido é digitado antes do corte, enviado no frame 24; a resposta chega no meio da 1ª fala.
export const DeskDemo: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const reply = bt(p, 0, 0.5);
  const send = 24;
  const sent = f >= send;
  const push = 1 + 0.07 * Math.min(1, Math.max(0, (f + 18) / (p.len + 18)));
  const sc = L.v ? 1.3 : 1.2;
  return (
    <Bg color={C.night}>
      <AbsoluteFill style={{ transform: `scale(${push})`, alignItems: "center", justifyContent: "center", flexDirection: "column", gap: L.v ? 50 : 28, paddingLeft: L.v ? L.l : 0, paddingRight: L.v ? L.r : 0 }}>
        {p.kicker ? (
          <div style={{ alignSelf: "stretch", paddingLeft: L.v ? 0 : 180 }}>
            <MaskUp f={f} at={first(p)} dur={18}>
              <span style={{ ...H1, fontSize: L.v ? 76 : 52, color: C.white }}>{p.kicker}</span>
            </MaskUp>
          </div>
        ) : null}
        <Desk
          w={L.v ? L.W - L.l - L.r : 1560} h={L.v ? 1120 : 640} sidebar={!L.v} pad={L.v ? 30 : 44} title={p.session}
          composer={<Composer text={sent ? "" : typing(p.prompt, f, -14, 1.1)} cursor={!sent && Math.floor(f / 9) % 2 === 0} scale={L.v ? 1.25 : 1.15} />}
        >
          {sent ? <UserMsg t={fadeIn(f, send, 6)} scale={sc}>{p.prompt}</UserMsg> : null}
          {sent && f < reply ? <Working f={f} scale={sc} label={p.working ?? "Trabalhando…"} /> : null}
          {p.files && f >= reply - 14 ? <EditCard t={fadeIn(f, reply - 14, 8)} scale={1.15} files={p.files} /> : null}
          {f >= reply ? (
            <AsstText t={fadeIn(f, reply, 6)} scale={1.45}>
              <span style={{ color: D.green, fontWeight: 700 }}>✓</span> <b>{p.reply}</b>
            </AsstText>
          ) : null}
        </Desk>
      </AbsoluteFill>
    </Bg>
  );
};

/* ───────────────────────── comandos digitados em sequência ───────────────────────── */
// props: line1, line2 (vazada), cmds [{cmd, reply}], badge? (entra na 2ª fala), placeholder?
// Comando na tela é comando REAL: o público digita o que vê.
export const Commands: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const t0 = first(p);
  const per = 30;
  const cmds: { cmd: string; reply: string }[] = p.cmds;
  const sc = L.v ? 1.2 : 1.1;
  const cur = Math.max(0, Math.min(cmds.length - 1, Math.floor((f - t0 - 6) / per)));
  const local = f - t0 - 6 - cur * per;
  const typingNow = local < 16;
  const badge = bt(p, 1) - 2;
  return (
    <Bg color={C.paper}>
      <AbsoluteFill style={{ padding: `${L.t}px ${L.r}px ${L.b}px ${L.l}px`, flexDirection: L.v ? "column" : "row", alignItems: L.v ? "flex-start" : "center", gap: L.v ? 40 : 50 }}>
        <div style={{ flexShrink: 0 }}>
          <MaskUp f={f} at={t0}>
            <span style={{ ...H1, fontSize: L.v ? 84 : 72, color: C.ink }}>{p.line1}</span>
          </MaskUp>
          <br />
          <MaskUp f={f} at={t0 + 6}>
            <span style={{ ...H1, fontSize: L.v ? 84 : 72, ...hollow(C.ink, 2.4, C.paper) }}>{p.line2}</span>
          </MaskUp>
          {p.badge && p.beats.length > 1 ? (
            <div style={{ marginTop: 40 }}>
              <div style={{ display: "inline-flex", alignItems: "center", gap: 16, background: C.ink, color: C.white, borderRadius: 100, padding: "20px 40px", fontSize: 34, fontWeight: 700, opacity: ip(f, [badge, badge + 8], [0, 1]), transform: `scale(${ip(f, [badge, badge + 12], [0.7, 1])})` }}>
                {p.badge}
              </div>
            </div>
          ) : null}
        </div>
        <div style={{ transform: `translateY(${ip(f, [t0, t0 + 20], [40, 0])}px)`, opacity: ip(f, [t0 - 4, t0 + 8], [0, 1]) }}>
          <Desk w={L.v ? L.W - L.l - L.r : 880} h={L.v ? 900 : 680} sidebar={false} title={p.session ?? "MEU PROJETO"} pad={30}
            composer={<Composer text={typingNow && f >= t0 + 6 ? typing(cmds[cur].cmd, local, 0, 4) : ""} cursor={typingNow && f >= t0 + 6} scale={sc} placeholder={p.placeholder ?? "Digite / para comandos"} />}>
            {cmds.map((c, i) => {
              const sentAt = t0 + 6 + i * per + 16;
              if (f < sentAt) return null;
              return (
                <React.Fragment key={c.cmd}>
                  <UserMsg t={fadeIn(f, sentAt, 5)} scale={sc}><span style={{ fontFamily: D.mono, fontSize: 17 * sc }}>{c.cmd}</span></UserMsg>
                  {f >= sentAt + 8 ? <AsstText t={fadeIn(f, sentAt + 8, 6)} scale={sc}><span style={{ color: D.green }}>✓</span> {c.reply}</AsstText> : null}
                </React.Fragment>
              );
            })}
          </Desk>
        </div>
      </AbsoluteFill>
    </Bg>
  );
};

/* ───────────────────────── capítulo ───────────────────────── */
// props: n, name, count?, label? ("Capítulo")
export const Chapter: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const num = String(p.n).padStart(2, "0");
  const nameFs = fit([p.name], L.W - L.l - L.r, L.v ? 96 : 110);
  const rot = ip(f, [-10, 22], [70, 0]);
  const sweep = ip(f, [-6, 30], [0, 1], EASE_INOUT);
  return (
    <Bg color={C.accentFill}>
      <div style={{ position: "absolute", left: 0, top: L.H * (L.v ? 0.62 : 0.7), height: 4, width: L.W * sweep, background: C.white, opacity: 0.5 }} />
      <AbsoluteFill style={{ perspective: 1600, padding: `${L.t}px ${L.r}px ${L.b}px ${L.l}px`, justifyContent: "center" }}>
        <div style={{ ...LABEL, fontSize: 26, color: "rgba(255,255,255,0.75)", opacity: ip(f, [-8, 4], [0, 1]) }}>{p.label ?? "Capítulo"}</div>
        <div style={{ transformOrigin: "left center", transform: `rotateY(${rot}deg)` }}>
          <span style={{ ...H1, fontSize: L.v ? 380 : 420, lineHeight: 0.9, ...hollow(C.white, 3, C.accentFill) }}>{num}</span>
        </div>
        <MaskUp f={f} at={4} dur={16}>
          <span style={{ ...H1, fontSize: nameFs, color: C.white }}>{p.name}</span>
        </MaskUp>
        {p.count ? (
          <div style={{ marginTop: 22 }}>
            <MaskUp f={f} at={10}>
              <span style={{ fontSize: 36, fontWeight: 600, color: "rgba(255,255,255,0.8)" }}>{p.count}</span>
            </MaskUp>
          </div>
        ) : null}
      </AbsoluteFill>
    </Bg>
  );
};

/* ───────────────────────── card de item (um por cena) ───────────────────────── */
// props: n, total, kicker?, name, line, before?, beforeLabel?, solved?, proof?, cmd?, motif?, dark?, session?
// Esquerda: nome + o que faz + o "antes" riscado. Direita (embaixo no 9:16): janela do Desktop
// com o comando e a mini-animação (motif) do benefício.
export const Card: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const dark = p.dark ?? false;
  const bg = dark ? C.night : C.paper;
  const fg = dark ? C.white : C.ink;
  const acc = dark ? C.brandOnDark : C.brand;
  const sub = dark ? C.faint : C.dim;
  const a = first(p);
  const trapAt = bt(p, 0, 0.45);
  const strike = ip(f, [trapAt + 8, trapAt + 20], [0, 1], EASE_INOUT);
  const proofAt = bt(p, 0, 0.7);
  const colW = L.v ? L.W - L.l - L.r : 820;
  const nameFs = fit([p.name], colW, L.v ? 120 : 170, 0.6);
  const cardRot = ip(f, [-12, p.len], [-22, -10], (x) => x);
  const cardY = ip(f, [-12, 18], [60, 0]);
  const total = p.total ?? 0;
  const solved = p.solved ?? "evitado";
  return (
    <Bg color={bg}>
      {p.n ? (
        <div style={{ position: "absolute", right: L.v ? 40 : 80, top: L.v ? 120 : -40, transform: `translateY(${ip(f, [-12, p.len], [30, -30], (x) => x)}px)` }}>
          <span style={{ ...H1, fontSize: L.v ? 420 : 560, ...hollow(dark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.07)", 2, bg) }}>{String(p.n).padStart(2, "0")}</span>
        </div>
      ) : null}
      <AbsoluteFill style={{ padding: `${L.v ? L.t - 20 : L.t}px ${L.r}px ${L.b}px ${L.l}px`, justifyContent: L.v ? "flex-start" : "center" }}>
        <div style={{ width: colW }}>
          <div style={{ display: "flex", gap: 22, alignItems: "center", opacity: ip(f, [a, a + 8], [0, 1]) }}>
            {p.n ? <span style={{ ...LABEL, fontSize: 22, color: acc }}>{String(p.n).padStart(2, "0")}{total ? ` / ${total}` : ""}</span> : null}
            {p.kicker ? <span style={{ ...LABEL, fontSize: 22, color: sub }}>{p.kicker}</span> : null}
          </div>
          <div style={{ marginTop: 18 }}>
            <MaskUp f={f} at={a} dur={14}>
              <span style={{ ...H1, fontSize: nameFs, color: fg }}>{p.name}</span>
            </MaskUp>
          </div>
          <div style={{ marginTop: 20 }}>
            <MaskUp f={f} at={a + 6}>
              <span style={{ fontSize: L.v ? 46 : 52, fontWeight: 500, color: fg, letterSpacing: "-0.025em", lineHeight: 1.2 }}>{p.line}</span>
            </MaskUp>
          </div>
          {p.before ? (
            <div style={{ marginTop: L.v ? 30 : 54, opacity: ip(f, [trapAt - 4, trapAt + 6], [0, 1]), transform: `translateY(${ip(f, [trapAt - 4, trapAt + 10], [20, 0])}px)` }}>
              <div style={{ ...LABEL, fontSize: 20, color: sub }}>{p.beforeLabel ?? "Antes"}</div>
              <div style={{ position: "relative", display: "inline-block", marginTop: 10 }}>
                <span style={{ fontSize: fit([`${p.before}  ${solved}`], colW, L.v ? 40 : 44, 0.53), fontWeight: 600, color: strike > 0.5 ? sub : fg, letterSpacing: "-0.02em", whiteSpace: "nowrap" }}>{p.before}</span>
                <div style={{ position: "absolute", left: -6, top: "54%", height: 5, width: `calc(${strike * 100}% + 12px)`, background: acc }} />
              </div>
              <span style={{ marginLeft: 24, fontSize: 30, fontWeight: 800, color: acc, whiteSpace: "nowrap", opacity: ip(f, [trapAt + 18, trapAt + 26], [0, 1]) }}>{solved}</span>
            </div>
          ) : null}
          {p.proof ? (
            <div style={{ marginTop: 30, display: "inline-block", background: dark ? C.accentFill : C.ink, color: C.white, borderRadius: 100, padding: "14px 30px", fontSize: 28, fontWeight: 700, opacity: ip(f, [proofAt, proofAt + 8], [0, 1]), transform: `scale(${ip(f, [proofAt, proofAt + 12], [0.85, 1])})` }}>
              {p.proof}
            </div>
          ) : null}
        </div>
      </AbsoluteFill>
      {p.motif ? (
        <AbsoluteFill style={{ perspective: 1800, alignItems: L.v ? "flex-start" : "flex-end", justifyContent: L.v ? "flex-end" : "center", paddingLeft: L.v ? L.l : 0, paddingRight: L.v ? 0 : 100, paddingBottom: L.v ? L.b + 30 : 0 }}>
          <div style={{ transform: `translateY(${cardY}px) rotateY(${L.v ? 0 : cardRot * 0.5}deg) rotateX(${L.v ? -cardRot * 0.25 : 0}deg)`, opacity: ip(f, [-14, 0], [0, 1]) }}>
            <Desk w={L.v ? L.W - L.l - L.r : 800} h={760} sidebar={false} title={p.session} pad={30}
              composer={<Composer text={p.cmd && f < a + 16 ? typing(p.cmd, f, a - 10, 1.6) : ""} cursor={!!p.cmd && f < a + 16} scale={1} />}>
              {p.cmd && f >= a + 16 ? <UserMsg t={fadeIn(f, a + 16, 5)}><span style={{ fontFamily: D.mono, fontSize: 17 }}>{p.cmd}</span></UserMsg> : null}
              <div style={{ opacity: fadeIn(f, a + 22, 8), transform: `translateY(${(1 - fadeIn(f, a + 22, 10)) * 20}px) scale(0.97)`, transformOrigin: "left bottom" }}>
                <Motif {...p.motif} f={f} a={a + 22} dark />
              </div>
            </Desk>
          </div>
        </AbsoluteFill>
      ) : null}
      {total > 1 ? (
        <div style={{ position: "absolute", left: L.l, right: L.r, bottom: L.v ? L.b - 20 : 60, display: "flex", gap: 8 }}>
          {Array.from({ length: total }, (_, i) => {
            const on = i + 1 === p.n;
            const past = i + 1 < p.n;
            return (
              <div key={i} style={{ flex: 1, height: on ? 10 : 4, borderRadius: 4, alignSelf: "flex-end", background: on ? acc : past ? (dark ? "rgba(255,255,255,0.45)" : C.faint) : dark ? "rgba(255,255,255,0.12)" : C.line, transform: on ? `scaleY(${ip(f, [0, 10], [0.3, 1])})` : undefined }} />
            );
          })}
        </div>
      ) : null}
    </Bg>
  );
};

/* ───────────────────────── chamada para ação (duas frentes) ───────────────────────── */
// props: q1, pill1, q2?, pill2? (entram na 2ª fala), cmds? [string] em mono embaixo
export const Cta: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const a = first(p);
  const b = p.beats.length > 1 ? bt(p, 1) - 6 : a + 24;
  const fs = L.v ? 80 : 92;
  return (
    <Bg color={C.paper}>
      <AbsoluteFill style={{ padding: `${L.t}px ${L.r}px ${L.b}px ${L.l}px`, justifyContent: "center" }}>
        <div style={{ display: "flex", flexDirection: L.v ? "column" : "row", gap: L.v ? 70 : 120 }}>
          <div>
            <MaskUp f={f} at={a}>
              <span style={{ ...H1, fontSize: fs, color: C.ink }}>{p.q1}</span>
            </MaskUp>
            <div style={{ marginTop: 20 }}><Pill f={f} at={a + 14} size={L.v ? 44 : 50}>{p.pill1}</Pill></div>
          </div>
          {p.q2 ? (
            <div>
              <MaskUp f={f} at={b}>
                <span style={{ ...H1, fontSize: fs, ...hollow(C.ink, 2.2, C.paper) }}>{p.q2}</span>
              </MaskUp>
              {p.pill2 ? <div style={{ marginTop: 20 }}><Pill f={f} at={b + 14} dark={false} size={L.v ? 44 : 50}>{p.pill2}</Pill></div> : null}
            </div>
          ) : null}
        </div>
        {p.cmds ? (
          <div style={{ marginTop: L.v ? 80 : 90, fontFamily: MONO, fontSize: L.v ? 22 : 26, color: C.dim, lineHeight: 1.7, opacity: ip(f, [b + 24, b + 34], [0, 1]) }}>
            {(p.cmds as string[]).map((c) => <div key={c}>› {c}</div>)}
          </div>
        ) : null}
      </AbsoluteFill>
    </Bg>
  );
};

/* ───────────────────────── assinatura: traço → logo PNG → nome ───────────────────────── */
// props: name, sub?, logo? (default "logo-dark.png", em public/). O logo é sempre o PNG da marca,
// sem esticar: a largura manda e a altura segue a proporção do arquivo.
export const Outro: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const a = L.v ? 190 : 200;
  const cx = L.W / 2;
  const cy = L.v ? 800 : 420;
  const path = lemniscatePath(a, cx, cy);
  const draw = evolvePath(ip(f, [-6, 26], [0, 1], EASE_INOUT), path);
  const swap = ip(f, [24, 32], [0, 1]);
  const logoW = L.v ? 760 : 900;
  const wipe = ip(f, [26, 48], [0, 100], EASE_INOUT);
  const fade = ip(f, [p.len - 24, p.len], [1, 0]);
  return (
    <Bg color={C.night}>
      <AbsoluteFill style={{ opacity: fade }}>
        <svg width={L.W} height={L.H} style={{ position: "absolute", opacity: 1 - swap }}>
          <path d={path} fill="none" stroke={C.brandOnDark} strokeWidth={22} strokeLinecap="round" strokeDasharray={draw.strokeDasharray} strokeDashoffset={draw.strokeDashoffset} />
        </svg>
        <div style={{ position: "absolute", left: 0, right: 0, top: cy, display: "flex", justifyContent: "center", transform: "translateY(-50%)" }}>
          <div style={{ width: logoW, clipPath: `inset(0 ${100 - wipe}% 0 0)` }}>
            <Img src={staticFile(p.logo ?? "logo-dark.png")} style={{ width: logoW, display: "block" }} />
          </div>
        </div>
        <div style={{ position: "absolute", top: cy + (L.v ? 200 : 180), width: "100%", textAlign: "center" }}>
          <MaskUp f={f} at={44}>
            <span style={{ ...H1, fontSize: L.v ? 70 : 72, color: C.white }}>{p.name}</span>
          </MaskUp>
          <br />
          {p.sub ? (
            <MaskUp f={f} at={50}>
              <span style={{ fontSize: 38, fontWeight: 500, color: C.faint }}>{p.sub}</span>
            </MaskUp>
          ) : null}
        </div>
      </AbsoluteFill>
    </Bg>
  );
};

export const SCENES: Record<string, React.FC<SP>> = {
  statement: Statement, title: Title, numbers: Numbers, desk: DeskDemo, commands: Commands,
  chapter: Chapter, card: Card, cta: Cta, outro: Outro,
};
