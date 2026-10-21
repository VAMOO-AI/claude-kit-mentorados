// Cenas do Film (16:9 e 9:16, com ou sem narração): um componente por "type" do film.json.
// Toda cena recebe beats/ends (frame local de início/fim de cada fala) e anima em cima deles:
// a voz manda no tempo. f = 0 é o corte na batida (useF). O layout lê o tamanho do vídeo
// (useL), então o mesmo componente serve o master 16:9 e o corte 9:16.
// Cena nova: copie uma daqui, registre em SCENES e declare os sons dela no SONS do src/sons.mjs
// (vazio vale), nos mesmos tempos da animação (tempos.mjs); ou use "cues" no film.json.
import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import { Motif } from "./motifs";
import { Follow, Highlights, Orbit, PillName } from "./scenes-apresentacao";
import { AppLine, Assemble } from "./scenes-app";
import { LetterSwap, MorphShape, Ranking, Versus } from "./scenes-extras";
import { MapRoute } from "./scenes-mapa";
import { FilmCtx, H1, LABEL, type SP, bt, first, fit, hitAt, useImgRatio, useL } from "./film-base";
import { DESK_ENVIA, pilulasCta } from "./tempos.mjs";
import { AsstText, Composer, Cursor, D, Desk, EditCard, UserMsg, Working, fadeIn, sendButton, typing } from "./desktop";
import { ANTIC, BRAND, Bg, C, Counter, EASE_INOUT, EXIT, MONO, MarkIn, MaskUp, SETTLE, hitStop, hollow, ip, shake, useF } from "./lib";

export { FilmCtx, H1, LABEL, bt, first, fit, hitAt, useImgRatio, useL } from "./film-base";
export type { SP, Scene, TL } from "./film-base";

const Pill: React.FC<{ f: number; at: number; dark?: boolean; children: React.ReactNode; size?: number }> = ({ f, at, dark = true, children, size = 38 }) => (
  <div style={{ display: "inline-block", background: dark ? C.ink : C.paper, border: `3px solid ${C.ink}`, color: dark ? C.white : C.ink, borderRadius: 100, padding: `${size * 0.5}px ${size * 1.2}px`, fontSize: size, fontWeight: 700, opacity: ip(f, [at, at + 3], [0, 1]), transform: `scale(${ip(f, [at, at + 12], [0.75, 1], SETTLE)})` }}>
    {children}
  </div>
);

/* ───────────────────────── frase em grupos (uma ideia por fala) ───────────────────────── */
// props: bg "night"|"paper", groups [{beat, frac?, lines[], lineFracs?, hollowLast?}] — cada grupo entra na
// sua fala e sai quando o próximo entra.
export const Statement: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const dark = p.bg !== "paper";
  const bg = dark ? C.night : C.paper;
  const fg = dark ? C.white : C.ink;
  const groups: { beat: number; frac?: number; lineFracs?: number[]; lines: string[]; hollowLast?: boolean }[] = p.groups;
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
              // lineFracs: a linha entra na fração da fala que a diz. A 1ª linha (e a que não passa do frac do grupo)
              // fica com a entrada do grupo: na 1ª cena, first(p), antes do corte (a transição nunca revela tela vazia).
              const lf = g.lineFracs?.[li];
              const lineAt = lf !== undefined && li > 0 && lf > (g.frac ?? 0) ? Math.max(at + li * 5, bt(p, g.beat, lf) - 6) : at + li * 5;
              // troca no mesmo lugar (doutrina, regra 9): o grupo que sai desfoca até 2 px e o que entra na troca
              // parte de 2 px; filtro calculado pelo frame, só durante a troca, nunca num nó preserve-3d
              const oi = out !== undefined ? out + li * 2 : 1e9;
              const bOut = f >= oi && f < oi + 10 ? ip(f, [oi, oi + 10], [0, 2]) : 0;
              const bIn = gi > 0 && lineAt < at + 12 ? ip(f, [lineAt, lineAt + 8], [2, 0]) : 0;
              const blur = Math.max(bOut, bIn);
              return (
                <div key={li}>
                  <MaskUp f={f} at={lineAt} out={out !== undefined ? out + li * 2 : undefined} dur={16}>
                    <span style={{ ...H1, fontSize: fs, ...(hol ? hollow(dark ? C.white : C.brand, 3, bg) : { color: fg }), filter: blur > 0.05 ? `blur(${blur.toFixed(2)}px)` : undefined }}>{ln}</span>
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

/* ───────────────────────── título (impacto + tremor + símbolo da marca) ───────────────────────── */
// props: line1, line2 (vazada), sub?, pill? (entram na 2ª fala), symbol? (false tira o símbolo,
// o public/marca.png, que entra com escala acima do título)
export const Title: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const sh = shake(f, 0, 26, 14);
  const cx = L.W / 2;
  const cy = L.v ? 640 : 250;
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
        {p.symbol !== false ? <MarkIn f={f} cx={cx} cy={cy} w={L.v ? 360 : 400} h={L.v ? 220 : 190} at={-8} dur={22} /> : null}
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
// props: items [{v, label}], focus? ("last": o último é o clímax) — o contador i entra na fala i; os anteriores esmaecem.
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
            const focal = p.focus === "last" && i === items.length - 1; // clímax: antecipa, passa, congela e assenta
            const g = focal ? hitStop(f, at + 6, 3) : f;
            const prog = focal ? ip(g, [at, at + 6], [0, 1], (x) => x) : ip(f, [at, at + 18], [0, 1], (x) => x);
            const scl = focal
              ? g < at ? ip(f, [at - 4, at], [1, 0.92], ANTIC) : g < at + 6 ? ip(g, [at, at + 6], [0.92, 1.12]) : ip(g, [at + 6, at + 18], [1.12, 1], SETTLE)
              : 1;
            const next = i + 1 < items.length ? bt(p, i + 1) - 4 : 1e9;
            const dim = f >= next ? 0.35 : 1;
            return (
              <div key={i} style={{ flex: 1, opacity: f >= at ? 1 : 0.1, display: "flex", flexDirection: L.v ? "row" : "column", alignItems: L.v ? "center" : "flex-start", gap: L.v ? 36 : 18 }}>
                {!L.v ? <div style={{ width: 380 * ip(f, [at, at + 18], [0, 1], EASE_INOUT), height: 3, background: dim < 1 ? C.line : C.brand }} /> : null}
                <div style={{ opacity: Math.max(dim, 0.35), minWidth: L.v ? 300 : undefined }}>
                  <div style={{ transform: `scale(${scl})`, transformOrigin: L.v ? "left center" : "left bottom" }}>
                    <Counter value={it.v} progress={prog} size={L.v ? 190 : 210} color={C.ink} ease={focal ? (x) => x : SETTLE} />
                  </div>
                </div>
                <MaskUp f={f} at={focal ? Math.max(at + 18, bt(p, i, 0.45)) : at + 6} dur={focal ? 6 : 14}>
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
// props: kicker?, prompt, working?, files? [[arquivo, linhas]], reply, session?, click?
// O pedido é digitado antes do corte, enviado no frame 24; a resposta chega no meio da 1ª fala.
// click: true → o cursor viaja até o botão de enviar, clica (a onda sai do botão) e o botão vira
// o quadrado de parar enquanto o Claude trabalha.
export const DeskDemo: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const reply = bt(p, 0, 0.5);
  const send = DESK_ENVIA; // o som (sons.mjs) lê o mesmo quadro
  const sent = f >= send;
  const push = 1 + 0.07 * Math.min(1, Math.max(0, (f + 18) / (p.len + 18)));
  const sc = L.v ? 1.3 : 1.2;
  const dw = L.v ? L.W - L.l - L.r : 1560;
  const dh = L.v ? 1120 : 640;
  const dpad = L.v ? 30 : 44;
  const csc = L.v ? 1.25 : 1.15;
  const alvo = sendButton(dw, dh, dpad, csc);
  const cursor = p.click ? <Cursor f={f} at={send - 1} from={[dw * 0.55, dh * 0.3]} to={alvo} trip={18} size={L.v ? 1.6 : 1.4} hide={send + 18} /> : null;
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
          w={dw} h={dh} sidebar={!L.v} pad={dpad} title={p.session} overlay={cursor}
          composer={<Composer text={sent ? "" : typing(p.prompt, f, -14, 1.1)} cursor={!sent && Math.floor(f / 9) % 2 === 0} scale={csc} busy={!!p.click && sent && f < reply} />}
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
  const fw = f - 10; // a janela entra depois do nome: um foco por vez
  const cardRot = ip(fw, [-12, p.len], [-22, -10], (x) => x);
  const cardY = ip(fw, [-12, 18], [60, 0]);
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
          <div style={{ transform: `translateY(${cardY}px) rotateY(${L.v ? 0 : cardRot * 0.5}deg) rotateX(${L.v ? -cardRot * 0.25 : 0}deg)`, opacity: ip(fw, [-14, 0], [0, 1]) }}>
            <Desk w={L.v ? L.W - L.l - L.r : 800} h={760} sidebar={false} title={p.session} pad={30}
              composer={<Composer text={p.cmd && fw < a + 16 ? typing(p.cmd, fw, a - 10, 1.6) : ""} cursor={!!p.cmd && fw < a + 16} scale={1} />}>
              {p.cmd && fw >= a + 16 ? <UserMsg t={fadeIn(fw, a + 16, 5)}><span style={{ fontFamily: D.mono, fontSize: 17 }}>{p.cmd}</span></UserMsg> : null}
              <div style={{ opacity: fadeIn(fw, a + 22, 8), transform: `translateY(${(1 - fadeIn(fw, a + 22, 10)) * 20}px) scale(0.97)`, transformOrigin: "left bottom" }}>
                <Motif {...p.motif} f={fw} a={a + 22} dark />
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
  const { a, b, p1, p2 } = pilulasCta(p); // o som (sons.mjs) toca nos mesmos quadros
  const fs = L.v ? 80 : 92;
  return (
    <Bg color={C.paper}>
      <AbsoluteFill style={{ padding: `${L.t}px ${L.r}px ${L.b}px ${L.l}px`, justifyContent: "center" }}>
        <div style={{ display: "flex", flexDirection: L.v ? "column" : "row", gap: L.v ? 70 : 120 }}>
          <div>
            <MaskUp f={f} at={a}>
              <span style={{ ...H1, fontSize: fs, color: C.ink }}>{p.q1}</span>
            </MaskUp>
            <div style={{ marginTop: 20 }}><Pill f={f} at={p1} size={L.v ? 44 : 50}>{p.pill1}</Pill></div>
          </div>
          {p.q2 ? (
            <div>
              <MaskUp f={f} at={b}>
                <span style={{ ...H1, fontSize: fs, ...hollow(C.ink, 2.2, C.paper) }}>{p.q2}</span>
              </MaskUp>
              {p.pill2 ? <div style={{ marginTop: 20 }}><Pill f={f} at={p2} dark={false} size={L.v ? 44 : 50}>{p.pill2}</Pill></div> : null}
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

/* ───────────────────────── assinatura: símbolo → logo PNG → nome ───────────────────────── */
// props: name, sub?, logo? (default "logo-dark.png", em public/), symbol? (false começa direto pelo
// logo). O símbolo é o public/marca.png; o logo é sempre o PNG da marca, sem esticar: a largura
// manda e a altura segue a proporção do arquivo.
export const Outro: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const cx = L.W / 2;
  const cy = L.v ? 800 : 420;
  const symbol = p.symbol !== false;
  const logoW = L.v ? 760 : 900;
  // Sem símbolo, o logo já começa a aparecer no corte (nunca tela vazia na transição).
  const wipe = symbol ? ip(f, [26, 48], [0, 100], EASE_INOUT) : ip(f, [-6, 20], [0, 100], EASE_INOUT);
  const fade = ip(f, [p.len - 16, p.len], [1, 0], EXIT);
  return (
    <Bg color={C.night}>
      <AbsoluteFill style={{ opacity: fade }}>
        {symbol ? <MarkIn f={f} cx={cx} cy={cy} w={L.v ? 480 : 520} h={L.v ? 340 : 300} at={-6} dur={22} out={[24, 32]} /> : null}
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

/* ───────────────────────── presets: lançamento, batidas, vidro e logo 3D ───────────────────────── */
// Cor da paleta C com transparência: os presets pintam brilho e luz com a cor da marca de quem
// cria o projeto, nunca com um azul fixo. Aceita #rgb e #rrggbb; outro formato volta como veio.
const alpha = (cor: string, a: number) => {
  const h = cor.replace("#", "");
  const hex = h.length === 3 ? h.replace(/./g, (c) => c + c) : h;
  if (!/^[0-9a-fA-F]{6}$/.test(hex)) return cor;
  const n = parseInt(hex, 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
};

// Lançamento: palavras do título batem uma por batida, com tremor; uma batida de pausa e uma fenda
// de luz abre a tela clara com o nome do produto (o espaçamento das letras fecha).
// props: words [2–4 palavras], name, tag?, kicker?, step? (frames por palavra, padrão 15)
export const Launch: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const words: string[] = p.words ?? [];
  const step: number = p.step ?? 15;
  const voz = p.beats.length > 0;
  const hits = words.map((_, i) => (i === 0 ? first(p) : voz ? bt(p, 0, i / words.length) - 4 : i * step));
  const reveal = voz && p.beats.length > 1 ? bt(p, 1) - 4 : (words.length + 1) * step;
  const cur = hits.reduce((c, h, i) => (f >= h ? i : c), 0);
  const k = f - (hits[cur] ?? 0);
  const sh = shake(f, hits[cur] ?? 0, 22, 10);
  const fs = fit(words, L.W - L.l - L.r, L.v ? 250 : 300, 0.66);
  const slit = ip(f, [reveal - 8, reveal], [0, 1], EASE_INOUT);
  const open = ip(f, [reveal, reveal + 14], [0, 1], EASE_INOUT);
  const nameFs = fit([p.name ?? ""], L.W - L.l - L.r, L.v ? 190 : 230, 0.66);
  const blur = ip(k, [0, 6], [14, 0]);
  const w = words[cur] ?? "";
  return (
    <Bg color={C.night}>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", paddingLeft: L.l, paddingRight: L.r, transform: `translate(${sh.x}px, ${sh.y}px)` }}>
        <span style={{ ...H1, fontSize: fs, whiteSpace: "pre", opacity: ip(k, [0, 3], [0, 1]), transform: `scale(${ip(k, [0, 9], [1.8, 1])})`, filter: blur > 0.1 ? `blur(${blur}px)` : undefined, ...(cur % 2 ? hollow(C.brandOnDark, 4, C.night) : { color: C.white }) }}>
          {w}
        </span>
      </AbsoluteFill>
      <div style={{ position: "absolute", left: L.l, right: L.r, bottom: L.b, display: "flex", gap: 14 }}>
        {words.map((_, i) => (
          <div key={i} style={{ flex: 1, height: 6, borderRadius: 3, background: f >= hits[i] ? C.brandOnDark : C.shellLine }} />
        ))}
      </div>
      {slit > 0 && open < 1 ? (
        <div style={{ position: "absolute", top: L.H / 2 - 2, height: 4, left: (L.W * (1 - slit)) / 2, width: L.W * slit, background: C.white }} />
      ) : null}
      {open > 0 ? (
        <AbsoluteFill style={{ background: C.paper, clipPath: `inset(${50 * (1 - open)}% 0 ${50 * (1 - open)}% 0)`, alignItems: "center", justifyContent: "center", flexDirection: "column", gap: 26, paddingLeft: L.l, paddingRight: L.r }}>
          {p.kicker ? <div style={{ ...LABEL, fontSize: 26, color: C.brand, opacity: ip(f, [reveal + 8, reveal + 16], [0, 1]) }}>{p.kicker}</div> : null}
          <span style={{ ...H1, fontSize: nameFs, color: C.ink, whiteSpace: "nowrap", letterSpacing: `${ip(f, [reveal, reveal + 34], [0.45, -0.04])}em`, transform: `scale(${ip(f, [reveal, reveal + 34], [1.12, 1])})` }}>
            {p.name}
          </span>
          {p.tag ? (
            <MaskUp f={f} at={reveal + 18}>
              <span style={{ fontSize: L.v ? 46 : 44, fontWeight: 500, color: C.dim, letterSpacing: "-0.02em" }}>{p.tag}</span>
            </MaskUp>
          ) : null}
        </AbsoluteFill>
      ) : null}
    </Bg>
  );
};

// Batidas de benefício: um benefício por batida (ou por fala); a cor nova varre a tela na
// horizontal e o texto sobe na máscara. 3 itens é o ponto; mais que 4 vira lista, use cards.
// props: items [string], kicker?, step? (frames por item, padrão 30 = 2 batidas)
export const BeatsScene: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const items: string[] = p.items ?? [];
  const step: number = p.step ?? 30;
  const pal = [
    { bg: C.accentFill, fg: C.white, sub: "rgba(255,255,255,0.75)" },
    { bg: C.night, fg: C.white, sub: C.faint },
    { bg: C.paper, fg: C.ink, sub: C.dim },
  ];
  const fs = fit(items, L.W - L.l - L.r, L.v ? 170 : 260, 0.62);
  return (
    <Bg color={pal[0].bg}>
      {items.map((it, i) => {
        const h = hitAt(p, i, step);
        const c = pal[i % pal.length];
        const wipe = i === 0 ? 100 : ip(f, [h - 4, h + 6], [0, 100], EASE_INOUT);
        if (wipe <= 0) return null;
        const punch = 1 + 0.06 * (1 - ip(f, [h, h + 12], [0, 1]));
        return (
          <AbsoluteFill key={i} style={{ background: c.bg, clipPath: `inset(0 ${100 - wipe}% 0 0)`, padding: `${L.t}px ${L.r}px ${L.b}px ${L.l}px`, justifyContent: "center" }}>
            <div style={{ display: "flex", gap: 22, alignItems: "baseline", opacity: ip(f, [h, h + 6], [0, 1]) }}>
              <span style={{ ...LABEL, fontSize: 26, color: c.sub }}>{String(i + 1).padStart(2, "0")} / {String(items.length).padStart(2, "0")}</span>
              {p.kicker ? <span style={{ ...LABEL, fontSize: 26, color: c.sub }}>{p.kicker}</span> : null}
            </div>
            <div style={{ marginTop: 18, transform: `scale(${punch})`, transformOrigin: "left center" }}>
              <MaskUp f={f} at={h} dur={10}>
                <span style={{ ...H1, fontSize: fs, color: c.fg }}>{it}</span>
              </MaskUp>
            </div>
          </AbsoluteFill>
        );
      })}
    </Bg>
  );
};

// Fundo com estrutura para o vidro ter o que refratar: três anéis nas cores da paleta à deriva,
// grade e uma palavra grande. Desenhado duas vezes: na tela e, deslocado, dentro de cada painel.
const GlassArt: React.FC<{ f: number; W: number; H: number; word?: string }> = ({ f, W, H, word }) => {
  const s = Math.min(W, H);
  const rings = [
    { r: s * 0.26, x: 0.3, y: 0.35, c: C.brand, w: s * 0.09 },
    { r: s * 0.2, x: 0.72, y: 0.68, c: C.accentFill, w: s * 0.07 },
    { r: s * 0.13, x: 0.6, y: 0.22, c: C.brandOnDark, w: s * 0.035 },
  ];
  return (
    <AbsoluteFill style={{ background: C.night }}>
      <svg width={W} height={H} style={{ position: "absolute" }}>
        {Array.from({ length: Math.ceil(W / 80) }, (_, i) => (
          <line key={`v${i}`} x1={i * 80} y1={0} x2={i * 80} y2={H} stroke="rgba(255,255,255,0.06)" strokeWidth={2} />
        ))}
        {Array.from({ length: Math.ceil(H / 80) }, (_, i) => (
          <line key={`h${i}`} x1={0} y1={i * 80} x2={W} y2={i * 80} stroke="rgba(255,255,255,0.06)" strokeWidth={2} />
        ))}
        {rings.map((o, i) => (
          <circle key={i} cx={W * o.x + Math.sin(f / 40 + i) * 20} cy={H * o.y + Math.cos(f / 52 + i) * 14} r={o.r} fill="none" stroke={o.c} strokeWidth={o.w} />
        ))}
      </svg>
      {word ? (
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
          <span style={{ ...H1, fontSize: (W / Math.max(4, word.length)) * 1.5, color: "rgba(255,255,255,0.1)", whiteSpace: "nowrap", transform: `translateX(${-f * 0.6}px)` }}>{word}</span>
        </AbsoluteFill>
      ) : null}
    </AbsoluteFill>
  );
};

// Vidro com refração: painéis de vidro sobre um fundo com estrutura. Dentro de cada painel o fundo
// é redesenhado, ampliado e deslocado por um feDisplacementMap (seed fixa), com borda acesa e um
// brilho que atravessa na entrada. Nada de backdrop-filter: dentro de uma transição o que ele
// amostra muda. O texto sobre o vidro é sólido (vazado aqui deixa o fill aparecer).
// props: title?, cards [{value (número conta; texto fica), label}] (1–3), word? (palavra do fundo), step?
export const Glass: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const uid = React.useId().replace(/[^a-zA-Z0-9]/g, "");
  const cards: { value: number | string; label: string }[] = p.cards ?? [];
  const n = Math.max(1, cards.length);
  const step: number = p.step ?? 15;
  const gap = L.v ? 40 : 44;
  const top = L.v ? (p.title ? 520 : 380) : (L.H - 400) / 2 + (p.title ? 70 : 0);
  const cw = L.v ? L.W - L.l - L.r : (L.W - L.l - L.r - gap * (n - 1)) / n;
  const ch = L.v ? Math.min(300, (L.H - top - L.b - gap * (n - 1)) / n) : 400;
  const R = 44;
  const t0 = first(p);
  return (
    <Bg color={C.night}>
      <GlassArt f={f} W={L.W} H={L.H} word={p.word} />
      <svg width={0} height={0} style={{ position: "absolute" }}>
        <defs>
          {cards.map((_, i) => {
            const h = hitAt(p, i, step) + 4;
            return (
              <filter key={i} id={`${uid}g${i}`} x="-5%" y="-5%" width="110%" height="110%">
                <feTurbulence type="fractalNoise" baseFrequency="0.0035 0.005" numOctaves={1} seed={7 + i} result="n" />
                <feDisplacementMap in="SourceGraphic" in2="n" scale={ip(f, [h, h + 30], [120, 34])} xChannelSelector="R" yChannelSelector="G" />
              </filter>
            );
          })}
        </defs>
      </svg>
      {p.title ? (
        <div style={{ position: "absolute", left: L.l, right: L.r, top: L.v ? L.t + 80 : L.t + 20 }}>
          <MaskUp f={f} at={t0}>
            <span style={{ ...H1, fontSize: fit([p.title], L.W - L.l - L.r, L.v ? 96 : 100), color: C.white }}>{p.title}</span>
          </MaskUp>
        </div>
      ) : null}
      {cards.map((c, i) => {
        const h = hitAt(p, i, step) + (i === 0 ? 4 : 0);
        const x = L.l + (L.v ? 0 : i * (cw + gap));
        const y = top + (L.v ? i * (ch + gap) : 0);
        const ty = ip(f, [h - 2, h + 18], [90, 0]);
        const sheen = ip(f, [h + 4, h + 30], [-0.6, 1.6], EASE_INOUT);
        const num = typeof c.value === "number";
        const vs = L.v ? 130 : 170;
        return (
          <div key={i} style={{ position: "absolute", left: x, top: y + ty, width: cw, height: ch, borderRadius: R, overflow: "hidden", opacity: ip(f, [h - 2, h + 6], [0, 1]), boxShadow: "0 30px 80px rgba(0,0,0,0.45)" }}>
            <div style={{ position: "absolute", left: -x, top: -(y + ty), width: L.W, height: L.H, transform: "scale(1.18)", transformOrigin: `${x + cw / 2}px ${y + ch / 2}px`, filter: `url(#${uid}g${i}) blur(3px)` }}>
              <GlassArt f={f} W={L.W} H={L.H} word={p.word} />
            </div>
            <div style={{ position: "absolute", inset: 0, background: "linear-gradient(140deg, rgba(255,255,255,0.22), rgba(255,255,255,0.05) 45%, rgba(255,255,255,0.12))" }} />
            <div style={{ position: "absolute", top: 0, bottom: 0, width: cw * 0.35, left: cw * sheen, background: "linear-gradient(100deg, transparent, rgba(255,255,255,0.35), transparent)", transform: "skewX(-18deg)" }} />
            <div style={{ position: "absolute", inset: 0, borderRadius: R, boxShadow: `inset 0 0 0 2px rgba(255,255,255,0.32), inset 0 2px 0 rgba(255,255,255,0.75), inset 0 -2px 0 ${alpha(C.brandOnDark, 0.45)}` }} />
            <div style={{ position: "absolute", inset: 0, padding: L.v ? "0 56px" : "0 48px", display: "flex", flexDirection: L.v ? "row" : "column", alignItems: L.v ? "center" : "flex-start", justifyContent: L.v ? "flex-start" : "center", gap: L.v ? 36 : 14 }}>
              {num ? (
                <Counter value={c.value as number} progress={ip(f, [h, h + 24], [0, 1], (t) => t)} size={vs} color={C.white} />
              ) : (
                <span style={{ ...H1, fontSize: fit([String(c.value)], cw - 100, vs, 0.62), color: C.white, lineHeight: 1 }}>{c.value}</span>
              )}
              <span style={{ fontSize: L.v ? 40 : 36, fontWeight: 600, color: "rgba(255,255,255,0.82)", letterSpacing: "-0.02em", lineHeight: 1.15 }}>{c.label}</span>
            </div>
          </div>
        );
      })}
    </Bg>
  );
};

// O símbolo da marca extrudado: N cópias do PNG em translateZ (as do meio escurecidas viram a
// lateral), brilho na face da frente preso ao ângulo e reflexo no chão. Gira e assenta numa
// pose com ângulo residual (de frente vira PNG chapado). O filtro fica só na Img folha: no nó
// preserve-3d ele achata o 3D. Logo nunca é redesenhado: é o PNG da marca de quem cria o projeto
// (public/marca.png, o --mark do new.sh), com a proporção que ele tiver.
// props: mark? (padrão "marca.png"), name? (padrão BRAND), sub?, turns? (voltas, padrão 1), settle? (frame da pose, padrão 60)
export const Logo3D: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const { tl, idx } = React.useContext(FilmCtx);
  const src = staticFile(p.mark ?? "marca.png");
  const ratio = useImgRatio(src);
  // Logo largo (wordmark 5:1) não pode passar da guia: a altura cede para a largura caber,
  // contando o soco de escala (bump, até 1,05) na pose.
  const mh = Math.min(L.v ? 250 : 300, (L.W - L.l - L.r) / (ratio * 1.05));
  const mw = mh * ratio;
  const depth = mh * 0.18;
  const N = 36;
  const S: number = p.settle ?? (p.beats.length ? bt(p, 0, 0.5) : 60);
  const t0 = first(p);
  const turns: number = p.turns ?? 1;
  const float = f > S ? Math.sin((f - S) / 26) * 5 : 0;
  const ry = ip(f, [t0, S], [-(360 * turns + 60), -16]) + float;
  const rx = ip(f, [t0, S], [28, 10]);
  const bump = 1 + 0.05 * Math.max(0, 1 - Math.abs(f - S) / 8);
  const scale = ip(f, [t0, S], [0.55, 1]) * bump;
  const cy = L.H * 0.4;
  const floor = cy + mh * 0.6;
  const spec = ((((ry % 360) + 360) % 360) / 360) * 260 - 80;
  const last = tl ? idx === tl.scenes.length - 1 : false;
  const fade = last ? ip(f, [p.len - 20, p.len], [1, 0]) : 1;
  const sh = shake(f, S, 10, 8);
  const solid = (
    <div style={{ position: "relative", width: 0, height: 0, transformStyle: "preserve-3d", transform: `rotateX(${rx}deg) rotateY(${ry}deg) scale(${scale})` }}>
      {Array.from({ length: N }, (_, i) => {
        const z = depth / 2 - (i / (N - 1)) * depth;
        const face = i === 0 || i === N - 1;
        return (
          <Img key={i} src={src} style={{ position: "absolute", left: -mw / 2, top: -mh / 2, width: mw, height: mh, transform: `translateZ(${z}px)`, filter: face ? undefined : `brightness(${0.42 + 0.2 * (i / N)}) saturate(1.2)` }} />
        );
      })}
      <div style={{ position: "absolute", left: -mw / 2, top: -mh / 2, width: mw, height: mh, transform: `translateZ(${depth / 2 + 0.5}px)`, WebkitMaskImage: `url(${src})`, WebkitMaskSize: "100% 100%", maskImage: `url(${src})`, maskSize: "100% 100%", background: `linear-gradient(115deg, transparent ${spec - 18}%, rgba(255,255,255,0.75) ${spec}%, transparent ${spec + 18}%)` }} />
    </div>
  );
  return (
    <Bg color={C.night}>
      <AbsoluteFill style={{ opacity: fade, transform: `translate(${sh.x}px, ${sh.y}px)` }}>
        <AbsoluteFill style={{ background: `radial-gradient(ellipse ${L.v ? 70 : 45}% 38% at 50% ${(cy / L.H) * 100}%, ${alpha(C.brand, 0.22)}, transparent 70%)` }} />
        <div style={{ position: "absolute", left: 0, right: 0, top: floor, height: 2, background: `linear-gradient(90deg, transparent, ${alpha(C.brandOnDark, 0.35)}, transparent)` }} />
        {/* reflexo: espelho do sólido em torno do chão; a máscara precisa de caixa com tamanho */}
        <div style={{ position: "absolute", left: 0, top: floor, width: L.W, height: mh * 1.2, opacity: 0.22, WebkitMaskImage: "linear-gradient(to bottom, black, transparent 60%)", maskImage: "linear-gradient(to bottom, black, transparent 60%)" }}>
          <div style={{ position: "absolute", left: L.W / 2, top: floor - cy, transform: "scaleY(-1)", perspective: 1600, width: 0, height: 0 }}>{solid}</div>
        </div>
        <div style={{ position: "absolute", left: L.W / 2, top: cy, perspective: 1600, width: 0, height: 0 }}>{solid}</div>
        <div style={{ position: "absolute", left: L.l, right: L.r, top: cy + mh * (L.v ? 1.15 : 1.0), textAlign: "center" }}>
          <MaskUp f={f} at={S + 4}>
            <span style={{ ...H1, fontSize: fit([p.name ?? BRAND], L.W - L.l - L.r, L.v ? 96 : 92), color: C.white }}>{p.name ?? BRAND}</span>
          </MaskUp>
          <br />
          {p.sub ? (
            <MaskUp f={f} at={S + 10}>
              <span style={{ fontSize: L.v ? 40 : 38, fontWeight: 500, color: C.faint }}>{p.sub}</span>
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
  launch: Launch, beats: BeatsScene, glass: Glass, logo3d: Logo3D,
  // apresentação pessoal (scenes-apresentacao.tsx) e lançamento de app (scenes-app.tsx)
  pillname: PillName, orbit: Orbit, highlights: Highlights, follow: Follow,
  appline: AppLine, assemble: Assemble,
  // cenas avulsas (scenes-extras.tsx, scenes-mapa.tsx)
  swap: LetterSwap, morph: MorphShape, map: MapRoute, ranking: Ranking, versus: Versus,
};
