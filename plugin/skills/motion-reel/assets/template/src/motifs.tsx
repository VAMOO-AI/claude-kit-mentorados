// Mini-animações de painel (680×440): uma ideia mostrada em imagem, sem jargão. Cada uma parte
// de `a` (frame local em que o painel entra) e cabe em ~90 frames. Escolha pelo `kind` e passe
// os textos por props — no film.json: "motif": {"kind": "rows", "title": "...", "items": [...]}.
import React from "react";
import { C, EASE_INOUT, MONO, ip } from "./lib";

type MP = { f: number; a: number; dark: boolean };
const PW = 680;
const PH = 440;

const T = (f: number, at: number, d = 10) => ip(f, [at, at + d], [0, 1]);

const useCol = (dark: boolean) => ({
  bg: dark ? "#0b0e13" : C.white,
  line: dark ? C.shellLine : C.line,
  fg: dark ? C.white : C.ink,
  sub: dark ? C.faint : C.dim,
  acc: dark ? C.brandOnDark : C.brand,
  soft: dark ? "rgba(255,255,255,0.08)" : "#eef1f6",
});

const Panel: React.FC<{ dark: boolean; children: React.ReactNode; title?: string }> = ({ dark, children, title }) => {
  const c = useCol(dark);
  return (
    <div style={{ width: PW, height: PH, background: c.bg, border: `2px solid ${c.line}`, borderRadius: 28, padding: 40, position: "relative", overflow: "hidden", boxShadow: dark ? undefined : "0 30px 60px rgba(5,7,10,0.08)" }}>
      {title ? <div style={{ fontSize: 20, fontWeight: 800, letterSpacing: "0.14em", textTransform: "uppercase", color: c.sub, marginBottom: 24 }}>{title}</div> : null}
      {children}
    </div>
  );
};

const Foot: React.FC<{ f: number; at: number; dark: boolean; children?: React.ReactNode }> = ({ f, at, dark, children }) =>
  children ? <div style={{ position: "absolute", left: 40, bottom: 32, fontSize: 26, fontWeight: 800, color: useCol(dark).acc, opacity: T(f, at) }}>{children}</div> : null;

const Check: React.FC<{ on: number; color: string }> = ({ on, color }) => (
  <svg width={34} height={34} viewBox="0 0 34 34" style={{ flexShrink: 0 }}>
    <circle cx={17} cy={17} r={15} fill="none" stroke={color} strokeWidth={3} opacity={0.35 + 0.65 * on} />
    <path d="M10 17.5 L15 22 L24 12" fill="none" stroke={color} strokeWidth={3.5} strokeLinecap="round" strokeLinejoin="round" strokeDasharray={24} strokeDashoffset={24 * (1 - on)} />
  </svg>
);

/* checklist que vai marcando */
const Rows: React.FC<MP & { items: string[]; step?: number; title?: string; foot?: string }> = ({ f, a, dark, items, step = 12, title, foot }) => {
  const c = useCol(dark);
  return (
    <Panel dark={dark} title={title}>
      {items.map((it, i) => {
        const at = a + 8 + i * step;
        return (
          <div key={i} style={{ display: "flex", alignItems: "center", gap: 18, marginBottom: 20, opacity: 0.25 + 0.75 * T(f, at - 6, 6) }}>
            <Check on={T(f, at)} color={c.acc} />
            <span style={{ fontSize: 30, fontWeight: 600, color: c.fg, letterSpacing: "-0.02em" }}>{it}</span>
          </div>
        );
      })}
      <Foot f={f} at={a + 8 + items.length * step} dark={dark}>{foot}</Foot>
    </Panel>
  );
};

/* conversa em balões (me = quem pergunta, à direita) */
const Chat: React.FC<MP & { msgs: { me?: boolean; t: string }[]; step?: number; title?: string }> = ({ f, a, dark, msgs, step = 16, title }) => {
  const c = useCol(dark);
  return (
    <Panel dark={dark} title={title}>
      <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
        {msgs.map((m, i) => {
          const t = T(f, a + 6 + i * step, 8);
          return (
            <div key={i} style={{ alignSelf: m.me ? "flex-end" : "flex-start", maxWidth: 480, padding: "16px 24px", borderRadius: 22, fontSize: 28, fontWeight: 600, letterSpacing: "-0.02em", background: m.me ? c.acc : c.soft, color: m.me ? (dark ? C.night : C.white) : c.fg, opacity: t, transform: `translateY(${(1 - t) * 20}px) scale(${0.92 + 0.08 * t})` }}>
              {m.t}
            </div>
          );
        })}
      </div>
    </Panel>
  );
};

/* etapas em linha que acendem uma a uma (até 4) */
const Pipeline: React.FC<MP & { gates: string[]; title?: string; foot?: string }> = ({ f, a, dark, gates, title, foot }) => {
  const c = useCol(dark);
  return (
    <Panel dark={dark} title={title}>
      <div style={{ display: "flex", alignItems: "center", marginTop: 60 }}>
        {gates.map((g, i) => {
          const on = T(f, a + 10 + i * 14, 8);
          return (
            <React.Fragment key={g}>
              <div style={{ textAlign: "center" }}>
                <div style={{ width: 92, height: 92, borderRadius: 46, border: `3px solid ${c.acc}`, background: on > 0.5 ? c.acc : "transparent", display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${0.85 + 0.15 * on})` }}>
                  <span style={{ fontSize: 40, fontWeight: 800, color: on > 0.5 ? (dark ? C.night : C.white) : c.acc }}>{on > 0.5 ? "✓" : i + 1}</span>
                </div>
                <div style={{ marginTop: 14, fontSize: 24, fontWeight: 700, color: c.fg }}>{g}</div>
              </div>
              {i < gates.length - 1 ? <div style={{ flex: 1, height: 4, margin: "0 8px 40px", background: c.line }}><div style={{ width: `${T(f, a + 16 + i * 14, 8) * 100}%`, height: "100%", background: c.acc }} /></div> : null}
            </React.Fragment>
          );
        })}
      </div>
      <Foot f={f} at={a + 10 + gates.length * 14} dark={dark}>{foot}</Foot>
    </Panel>
  );
};

/* raias com barra de progresso em velocidades diferentes (trabalho em paralelo) */
const Lanes: React.FC<MP & { labels: string[]; title?: string; foot?: string }> = ({ f, a, dark, labels, title, foot }) => {
  const c = useCol(dark);
  const speeds = [1, 0.8, 1.15, 0.9];
  return (
    <Panel dark={dark} title={title}>
      {labels.map((l, i) => {
        const p = Math.min(1, Math.max(0, ((f - a - 6) * speeds[i % 4]) / 60));
        return (
          <div key={l} style={{ marginBottom: 26 }}>
            <div style={{ display: "flex", justifyContent: "space-between", fontSize: 24, fontWeight: 700, color: c.fg, marginBottom: 10 }}>
              <span>{l}</span><span style={{ color: p >= 1 ? c.acc : c.sub }}>{p >= 1 ? "✓ pronto" : `${Math.round(p * 100)}%`}</span>
            </div>
            <div style={{ height: 12, borderRadius: 6, background: c.soft }}><div style={{ width: `${EASE_INOUT(p) * 100}%`, height: "100%", borderRadius: 6, background: c.acc }} /></div>
          </div>
        );
      })}
      <Foot f={f} at={a + 70} dark={dark}>{foot}</Foot>
    </Panel>
  );
};

/* um tronco que se divide em 3 ramos rotulados */
const Branches: React.FC<MP & { names: string[]; title?: string; foot?: string }> = ({ f, a, dark, names, title, foot }) => {
  const c = useCol(dark);
  const ys = [90, 190, 290];
  return (
    <Panel dark={dark} title={title}>
      <svg width={PW - 80} height={330} style={{ position: "absolute", left: 40, top: 80 }}>
        <line x1={10} y1={190} x2={590} y2={190} stroke={c.line} strokeWidth={6} strokeLinecap="round" />
        {ys.map((y, i) => {
          const p = T(f, a + 8 + i * 10, 22);
          const d = `M40 190 C 120 190, 120 ${y}, 200 ${y} L ${200 + 380 * p} ${y}`;
          return <path key={i} d={d} fill="none" stroke={c.acc} strokeWidth={6} strokeLinecap="round" opacity={0.45 + 0.55 * p} />;
        })}
        {ys.map((y, i) => (
          <text key={`t${i}`} x={220} y={y - 16} fill={c.fg} fontSize={22} fontWeight={700} fontFamily="'Plus Jakarta Sans'" opacity={T(f, a + 20 + i * 10)}>{names[i] ?? ""}</text>
        ))}
      </svg>
      <Foot f={f} at={a + 60} dark={dark}>{foot}</Foot>
    </Panel>
  );
};

/* duas caixas trocando pontos nos dois sentidos */
const Sync: React.FC<MP & { left: string; right: string; foot?: string }> = ({ f, a, dark, left, right, foot }) => {
  const c = useCol(dark);
  const dot = ((((f - a) % 30) + 30) % 30) / 30;
  const box = (t: string) => (
    <div style={{ width: 210, height: 150, borderRadius: 22, border: `3px solid ${c.acc}`, display: "flex", alignItems: "center", justifyContent: "center", textAlign: "center", fontSize: 26, fontWeight: 700, color: c.fg, padding: 12 }}>{t}</div>
  );
  return (
    <Panel dark={dark}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginTop: 70 }}>
        {box(left)}
        <div style={{ flex: 1, position: "relative", height: 60, margin: "0 16px" }}>
          <div style={{ position: "absolute", top: 18, left: 0, right: 0, height: 3, background: c.line }} />
          <div style={{ position: "absolute", top: 40, left: 0, right: 0, height: 3, background: c.line }} />
          <div style={{ position: "absolute", top: 12, left: `${dot * 92}%`, width: 16, height: 16, borderRadius: 8, background: c.acc, opacity: f > a ? 1 : 0 }} />
          <div style={{ position: "absolute", top: 34, left: `${(1 - dot) * 92}%`, width: 16, height: 16, borderRadius: 8, background: c.acc, opacity: f > a ? 1 : 0 }} />
        </div>
        {box(right)}
      </div>
      <Foot f={f} at={a + 40} dark={dark}>{foot}</Foot>
    </Panel>
  );
};

/* lista com selo sim/não por linha (comprovado × achismo, feito × pendente) */
const Tags: React.FC<MP & { rows: [string, boolean][]; yes?: string; no?: string; title?: string }> = ({ f, a, dark, rows, yes = "sim", no = "não", title }) => {
  const c = useCol(dark);
  return (
    <Panel dark={dark} title={title}>
      {rows.map(([t, ok], i) => {
        const on = T(f, a + 8 + i * 12, 8);
        return (
          <div key={i} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 22, opacity: on }}>
            <span style={{ fontSize: 28, fontWeight: 600, color: c.fg }}>{t}</span>
            <span style={{ fontSize: 20, fontWeight: 800, letterSpacing: "0.08em", textTransform: "uppercase", padding: "8px 16px", borderRadius: 10, background: ok ? c.acc : "transparent", border: ok ? "none" : `2px dashed ${c.sub}`, color: ok ? (dark ? C.night : C.white) : c.sub }}>
              {ok ? yes : no}
            </span>
          </div>
        );
      })}
    </Panel>
  );
};

/* linha de varredura descendo e marcando achados */
const Scan: React.FC<MP & { title?: string; foot?: string; mark?: string; hits?: number[] }> = ({ f, a, dark, title, foot, mark = "! achado", hits = [2, 5, 7] }) => {
  const c = useCol(dark);
  const n = 9;
  const y = ip(f, [a + 4, a + 60], [0, 1]) * 300;
  return (
    <Panel dark={dark} title={title}>
      <div style={{ position: "relative" }}>
        {Array.from({ length: n }, (_, i) => {
          const hit = hits.includes(i) && y > i * 32 + 10;
          return (
            <div key={i} style={{ display: "flex", alignItems: "center", gap: 12, height: 32 }}>
              <div style={{ width: 60 + ((i * 97) % 260), height: 12, borderRadius: 6, background: hit ? c.acc : c.soft }} />
              {hit ? <span style={{ fontSize: 20, fontWeight: 800, color: c.acc }}>{mark}</span> : null}
            </div>
          );
        })}
        <div style={{ position: "absolute", left: -10, right: -10, top: y, height: 3, background: c.acc, opacity: y < 295 ? 0.9 : 0 }} />
      </div>
      <Foot f={f} at={a + 62} dark={dark}>{foot}</Foot>
    </Panel>
  );
};

/* documento que se escreve + selos ao lado */
const Doc: React.FC<MP & { kind_label?: string; headline: string; chips: string[] }> = ({ f, a, dark, kind_label = "PDF", headline, chips }) => {
  const c = useCol(dark);
  return (
    <Panel dark={dark}>
      <div style={{ display: "flex", gap: 34 }}>
        <div style={{ width: 230, height: 300, borderRadius: 16, border: `3px solid ${c.line}`, padding: 22, transform: `translateY(${(1 - T(f, a + 4, 16)) * 40}px)`, opacity: T(f, a + 4, 10) }}>
          <div style={{ fontSize: 22, fontWeight: 800, color: c.acc }}>{kind_label}</div>
          {Array.from({ length: 7 }, (_, i) => <div key={i} style={{ height: 10, borderRadius: 5, marginTop: 18, width: `${60 + ((i * 37) % 40)}%`, background: c.soft, opacity: T(f, a + 10 + i * 4) }} />)}
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 16, marginTop: 10 }}>
          <div style={{ fontSize: 28, fontWeight: 700, color: c.fg, lineHeight: 1.2, maxWidth: 300 }}>{headline}</div>
          {chips.map((ch, i) => (
            <div key={ch} style={{ alignSelf: "flex-start", fontSize: 22, fontWeight: 800, padding: "8px 18px", borderRadius: 100, border: `2px solid ${c.acc}`, color: c.acc, opacity: T(f, a + 30 + i * 8) }}>{ch}</div>
          ))}
        </div>
      </div>
    </Panel>
  );
};

/* N colunas que enchem + contador "k/N <label>" */
const Pillars: React.FC<MP & { n?: number; label: string; accent?: string; title?: string }> = ({ f, a, dark, n = 8, label, accent, title }) => {
  const c = useCol(dark);
  return (
    <Panel dark={dark} title={title}>
      <div style={{ display: "flex", alignItems: "flex-end", gap: 18, height: 230 }}>
        {Array.from({ length: n }, (_, i) => {
          const p = T(f, a + 6 + i * 6, 14);
          return (
            <div key={i} style={{ flex: 1, height: "100%", borderRadius: 10, background: c.soft, display: "flex", alignItems: "flex-end" }}>
              <div style={{ width: "100%", height: `${p * 100}%`, borderRadius: 10, background: c.acc }} />
            </div>
          );
        })}
      </div>
      <div style={{ marginTop: 22, fontSize: 32, fontWeight: 800, color: c.fg }}>
        {Math.min(n, Math.max(0, Math.floor((f - a - 6) / 6) + 1))}/{n} {label} {accent ? <span style={{ color: c.acc }}>{accent}</span> : null}
      </div>
    </Panel>
  );
};

/* porcentagem que desce/sobe com barra */
const Meter: React.FC<MP & { from: number; to: number; label: string; foot?: string; title?: string }> = ({ f, a, dark, from, to, label, foot, title }) => {
  const c = useCol(dark);
  const v = from + (to - from) * EASE_INOUT(T(f, a + 10, 50));
  return (
    <Panel dark={dark} title={title}>
      <div style={{ fontSize: 110, fontWeight: 700, letterSpacing: "-0.05em", color: c.fg, lineHeight: 1 }}>{Math.round(v)}%</div>
      <div style={{ fontSize: 26, fontWeight: 600, color: c.sub, marginTop: 6 }}>{label}</div>
      <div style={{ height: 22, borderRadius: 11, background: c.soft, marginTop: 30 }}><div style={{ width: `${v}%`, height: "100%", borderRadius: 11, background: c.acc }} /></div>
      <Foot f={f} at={a + 60} dark={dark}>{foot}</Foot>
    </Panel>
  );
};

/* barra única dividida em partes (para onde vai o total) */
const Split: React.FC<MP & { parts: [string, number][]; title?: string }> = ({ f, a, dark, parts, title }) => {
  const c = useCol(dark);
  return (
    <Panel dark={dark} title={title}>
      <div style={{ display: "flex", height: 46, borderRadius: 12, overflow: "hidden", marginTop: 10 }}>
        {parts.map(([, v], i) => (
          <div key={i} style={{ width: `${v * T(f, a + 6 + i * 8, 14)}%`, background: c.acc, opacity: 1 - i * 0.22, borderRight: `3px solid ${c.bg}` }} />
        ))}
      </div>
      <div style={{ marginTop: 30, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
        {parts.map(([l, v], i) => (
          <div key={l} style={{ display: "flex", alignItems: "center", gap: 12, opacity: T(f, a + 14 + i * 8) }}>
            <div style={{ width: 18, height: 18, borderRadius: 5, background: c.acc, opacity: 1 - i * 0.22 }} />
            <span style={{ fontSize: 24, fontWeight: 700, color: c.fg }}>{l}</span>
            <span style={{ fontSize: 24, fontWeight: 600, color: c.sub }}>{v}%</span>
          </div>
        ))}
      </div>
    </Panel>
  );
};

/* barras com teto tracejado; as acima de `limit` apagam */
const Ceiling: React.FC<MP & { heights?: number[]; limit: number; label: string; cut?: string; title?: string }> = ({ f, a, dark, heights = [70, 55, 90, 40, 62, 30, 80, 48, 25, 35, 20], limit, label, cut, title }) => {
  const c = useCol(dark);
  const k = T(f, a + 40, 14);
  return (
    <Panel dark={dark} title={title}>
      <div style={{ position: "relative", display: "flex", alignItems: "flex-end", gap: 12, height: 250 }}>
        {heights.map((h, i) => {
          const over = i >= limit;
          return <div key={i} style={{ flex: 1, height: `${h * T(f, a + 4 + i * 3, 12)}%`, borderRadius: 8, background: over ? c.sub : c.acc, opacity: over ? 1 - k * 0.85 : 1 }} />;
        })}
        <div style={{ position: "absolute", left: 0, right: 0, top: -6, borderTop: `3px dashed ${c.fg}`, opacity: T(f, a + 30) }} />
      </div>
      <div style={{ marginTop: 24, fontSize: 28, fontWeight: 800, color: c.fg }}>{label} {cut ? <span style={{ color: c.acc, opacity: k }}>{cut}</span> : null}</div>
    </Panel>
  );
};

/* passos numerados + "no ar" pulsando no fim */
const Steps: React.FC<MP & { steps: string[]; foot?: string; title?: string }> = ({ f, a, dark, steps, foot, title }) => {
  const c = useCol(dark);
  const live = f > a + 8 + steps.length * 14;
  return (
    <Panel dark={dark} title={title}>
      {steps.map((s, i) => {
        const on = T(f, a + 8 + i * 14, 8);
        return (
          <div key={s} style={{ display: "flex", alignItems: "center", gap: 18, marginBottom: 18 }}>
            <div style={{ width: 40, height: 40, borderRadius: 20, background: on > 0.5 ? c.acc : c.soft, color: dark ? C.night : C.white, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 22, fontWeight: 800 }}>{on > 0.5 ? "✓" : ""}</div>
            <span style={{ fontSize: 28, fontWeight: 600, color: c.fg, opacity: 0.35 + 0.65 * on }}>{s}</span>
          </div>
        );
      })}
      {foot ? (
        <div style={{ position: "absolute", left: 40, bottom: 30, display: "flex", alignItems: "center", gap: 12, fontSize: 28, fontWeight: 800, color: c.acc, opacity: live ? 1 : 0 }}>
          <span style={{ width: 16, height: 16, borderRadius: 8, background: c.acc, opacity: 0.4 + 0.6 * Math.abs(Math.sin(f / 6)) }} />{foot}
        </div>
      ) : null}
    </Panel>
  );
};

/* centro + ramos com rótulo e detalhe (quem vê o quê) */
const Graph: React.FC<MP & { hub: string; spokes: [string, string][] }> = ({ f, a, dark, hub, spokes }) => {
  const c = useCol(dark);
  return (
    <Panel dark={dark}>
      <div style={{ display: "flex", alignItems: "center", gap: 30, height: "100%" }}>
        <div style={{ width: 170, height: 170, borderRadius: 85, border: `3px solid ${c.acc}`, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 28, fontWeight: 800, color: c.fg, textAlign: "center", flexShrink: 0, padding: 16 }}>{hub}</div>
        <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          {spokes.map(([r, s], i) => {
            const on = T(f, a + 10 + i * 12, 10);
            return (
              <div key={r} style={{ display: "flex", alignItems: "center", gap: 14, opacity: on, transform: `translateX(${(1 - on) * 30}px)` }}>
                <div style={{ width: 40 * on, height: 3, background: c.acc }} />
                <span style={{ fontSize: 28, fontWeight: 800, color: c.fg }}>{r}</span>
                <span style={{ fontSize: 24, fontWeight: 600, color: c.sub }}>{s}</span>
              </div>
            );
          })}
        </div>
      </div>
    </Panel>
  );
};

/* visor de câmera com o pedido sendo digitado */
const Viewfinder: React.FC<MP & { prompt: string; foot?: string }> = ({ f, a, dark, prompt, foot }) => {
  const c = useCol(dark);
  const shown = prompt.slice(0, Math.max(0, Math.floor((f - a - 6) * 1.4)));
  const corner: React.CSSProperties = { position: "absolute", width: 44, height: 44, borderColor: c.acc, borderStyle: "solid", borderWidth: 0 };
  const z = ip(f, [a, a + 40], [1.12, 1]);
  return (
    <Panel dark={dark}>
      <div style={{ position: "absolute", inset: 40, transform: `scale(${z})` }}>
        <div style={{ ...corner, left: 0, top: 0, borderLeftWidth: 5, borderTopWidth: 5 }} />
        <div style={{ ...corner, right: 0, top: 0, borderRightWidth: 5, borderTopWidth: 5 }} />
        <div style={{ ...corner, left: 0, bottom: 0, borderLeftWidth: 5, borderBottomWidth: 5 }} />
        <div style={{ ...corner, right: 0, bottom: 0, borderRightWidth: 5, borderBottomWidth: 5 }} />
        <div style={{ position: "absolute", left: "50%", top: "50%", width: 30, height: 30, marginLeft: -15, marginTop: -15, borderRadius: 15, border: `3px solid ${c.acc}` }} />
      </div>
      <div style={{ position: "absolute", left: 70, right: 70, top: 90, fontSize: 30, fontWeight: 600, color: c.fg, lineHeight: 1.3 }}>“{shown}”</div>
      {foot ? <div style={{ position: "absolute", left: 70, bottom: 70, fontSize: 24, fontWeight: 800, color: c.acc, opacity: T(f, a + 60) }}>{foot}</div> : null}
    </Panel>
  );
};

/* arquivo sendo gerado faixa a faixa */
const Develop: React.FC<MP & { file: string; done?: string; note?: string }> = ({ f, a, dark, file, done = "✓ arquivo pronto", note }) => {
  const c = useCol(dark);
  const rows = 10;
  const p = T(f, a + 6, 50);
  return (
    <Panel dark={dark}>
      <div style={{ display: "flex", gap: 30 }}>
        <div style={{ width: 300, height: 340, borderRadius: 18, overflow: "hidden", background: c.soft }}>
          {Array.from({ length: rows }, (_, i) => (
            <div key={i} style={{ height: 34, background: c.acc, opacity: p * rows > i ? 0.25 + 0.75 * (1 - i / rows) : 0 }} />
          ))}
        </div>
        <div style={{ marginTop: 20 }}>
          <div style={{ fontFamily: MONO, fontSize: 24, color: c.fg }}>{file}</div>
          <div style={{ fontSize: 24, fontWeight: 600, color: c.sub, marginTop: 10 }}>{Math.round(p * 100)}% gerado</div>
          <div style={{ marginTop: 40, fontSize: 26, fontWeight: 800, color: c.acc, opacity: T(f, a + 58) }}>{done}</div>
          {note ? <div style={{ marginTop: 10, fontSize: 24, fontWeight: 700, color: c.fg, opacity: T(f, a + 64) }}>{note}</div> : null}
        </div>
      </div>
    </Panel>
  );
};

/* trilhas de edição com agulha correndo */
const MiniTimeline: React.FC<MP & { title?: string }> = ({ f, a, dark, title }) => {
  const c = useCol(dark);
  const blocks = [0, 9, 17, 22, 31, 40, 46, 55, 63, 70, 79, 88];
  const head = ip(f, [a, a + 90], [0, 100], (x) => x);
  return (
    <Panel dark={dark} title={title}>
      {[0, 1, 2].map((t) => (
        <div key={t} style={{ position: "relative", height: t === 0 ? 70 : 34, marginBottom: 12, background: c.soft, borderRadius: 6 }}>
          {t === 0
            ? blocks.map((b, i) => <div key={i} style={{ position: "absolute", left: `${b}%`, width: `${(blocks[i + 1] ?? 100) - b - 1}%`, top: 6, bottom: 6, borderRadius: 4, background: c.acc, opacity: i % 2 ? 0.55 : 1 }} />)
            : t === 1
              ? Array.from({ length: 24 }, (_, i) => <div key={i} style={{ position: "absolute", left: `${i * 4.2}%`, width: 3, top: 8, bottom: 8, background: c.acc, opacity: 0.6 }} />)
              : <div style={{ position: "absolute", left: 0, right: 0, top: 14, height: 6, background: c.acc, opacity: 0.35 }} />}
        </div>
      ))}
      <div style={{ position: "absolute", left: `calc(40px + ${head}% * 0.88)`, top: 80, width: 3, height: 190, background: c.fg }} />
    </Panel>
  );
};

const KINDS: Record<string, React.FC<any>> = {
  rows: Rows, chat: Chat, pipeline: Pipeline, lanes: Lanes, branches: Branches, sync: Sync, tags: Tags, scan: Scan,
  doc: Doc, pillars: Pillars, meter: Meter, split: Split, ceiling: Ceiling, steps: Steps, graph: Graph,
  viewfinder: Viewfinder, develop: Develop, timeline: MiniTimeline,
};

export const MOTIF_KINDS = Object.keys(KINDS);

// <Motif kind="rows" items={[...]} f={f} a={a} dark />. `kind` desconhecido não quebra o render:
// sai um painel vazio com o nome, que a folha de QA mostra.
export const Motif: React.FC<MP & { kind: string } & Record<string, any>> = ({ kind, ...p }) => {
  const K = KINDS[kind];
  if (!K) return <Panel dark={p.dark} title={`motif "${kind}"?`}>{null}</Panel>;
  return <K {...p} />;
};
