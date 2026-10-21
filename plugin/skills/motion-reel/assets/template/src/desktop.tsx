// Recriação estilizada do app Claude Code Desktop (tema escuro): janela, sidebar de sessões,
// conversa e caixa de mensagem. Para mostrar alguém usando o Claude de verdade, sem cara de
// terminal. Peças soltas (Composer, UserMsg, AsstText, Working, EditCard) montam a conversa
// dentro do `Desk`; os textos vêm todos por props.
import React from "react";
import { EASE_INOUT, ip } from "./lib";

export const D = {
  win: "#1b1b1b",
  side: "#151515",
  line: "#2b2b2b",
  bubble: "#2a2a2a",
  card: "#202020",
  fg: "#ececec",
  dim: "#9a9a9a",
  faint: "#6b6b6b",
  link: "#5aa2ff",
  green: "#5fbf6a",
  ui: "-apple-system, 'SF Pro Text', 'Helvetica Neue', system-ui, sans-serif",
  mono: "ui-monospace, SFMono-Regular, Menlo, monospace",
};

const Dots: React.FC = () => (
  <div style={{ display: "flex", gap: 9 }}>
    {["#ff5f57", "#febc2e", "#28c840"].map((c) => <div key={c} style={{ width: 13, height: 13, borderRadius: 7, background: c }} />)}
  </div>
);

export const SESSIONS = ["SITE · CONTATO", "PAINEL DE VENDAS", "AGENTE DE ATENDIMENTO", "LOJA · CHECKOUT", "RELATÓRIO MENSAL"];

const Sidebar: React.FC<{ active: number; sessions: string[]; user: string; plan: string }> = ({ active, sessions, user, plan }) => (
  <div style={{ width: 300, background: D.side, borderRight: `1px solid ${D.line}`, padding: "18px 14px", fontFamily: D.ui, flexShrink: 0 }}>
    <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "8px 10px", fontSize: 17, color: D.fg }}>
      <span style={{ width: 22, height: 22, borderRadius: 11, border: `1.5px solid ${D.dim}`, display: "inline-flex", alignItems: "center", justifyContent: "center", fontSize: 15 }}>+</span>Novo
    </div>
    <div style={{ padding: "8px 10px", fontSize: 17, color: D.fg }}>Artifacts</div>
    <div style={{ padding: "22px 10px 8px", fontSize: 14, color: D.faint }}>Fixados</div>
    {sessions.map((s, i) => (
      <div key={s} style={{ padding: "9px 10px", borderRadius: 8, fontSize: 15, color: i === active ? D.fg : D.dim, background: i === active ? "#262626" : "transparent", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
        <span style={{ color: i === active ? D.link : D.faint, marginRight: 10 }}>●</span>{s}
      </div>
    ))}
    <div style={{ position: "absolute", bottom: 18, left: 24, display: "flex", alignItems: "center", gap: 10, fontSize: 15, color: D.fg }}>
      <span style={{ width: 26, height: 26, borderRadius: 13, background: "#3a5f8f" }} />{user} <span style={{ color: D.faint }}>· {plan}</span>
    </div>
  </div>
);

// Caixa de mensagem. `mode`/`model`/`effort` = os três rótulos da barra ("Automático · Opus 5.5 · Alto").
// `busy`: o Claude está trabalhando e o botão de enviar vira o quadrado de parar, como no app.
export const Composer: React.FC<{
  text: string; cursor?: boolean; placeholder?: string; scale?: number; mode?: string; model?: string; effort?: string; busy?: boolean;
}> = ({ text, cursor, placeholder = "Pergunte ao Claude…", scale = 1, mode = "Automático", model = "Opus 5.5", effort = "Alto", busy = false }) => (
  <div style={{ border: `1px solid ${D.line}`, borderRadius: 18 * scale, background: "#202020", padding: `${14 * scale}px ${18 * scale}px ${10 * scale}px`, fontFamily: D.ui }}>
    <div style={{ minHeight: 30 * scale, fontSize: 19 * scale, color: text ? D.fg : D.faint, lineHeight: 1.4 }}>
      {text || placeholder}
      {cursor ? <span style={{ display: "inline-block", width: 2, height: 22 * scale, background: D.fg, marginLeft: 2, verticalAlign: "middle" }} /> : null}
    </div>
    <div style={{ display: "flex", alignItems: "center", gap: 18 * scale, marginTop: 8 * scale, fontSize: 15 * scale, color: D.dim }}>
      <span style={{ fontSize: 20 * scale }}>+</span><span>{mode}</span>
      <span style={{ marginLeft: "auto" }}>{model}</span><span>{effort}</span>
      <span style={{ width: 28 * scale, height: 28 * scale, borderRadius: 14 * scale, background: text || busy ? D.fg : "#3a3a3a", color: "#111", display: "inline-flex", alignItems: "center", justifyContent: "center", fontSize: 16 * scale, fontWeight: 700 }}>
        {busy ? <span style={{ width: 10 * scale, height: 10 * scale, borderRadius: 2 * scale, background: "#111" }} /> : "↑"}
      </span>
    </div>
  </div>
);

export const UserMsg: React.FC<{ children: React.ReactNode; t?: number; scale?: number }> = ({ children, t = 1, scale = 1 }) => (
  <div style={{ alignSelf: "flex-end", maxWidth: "80%", background: D.bubble, color: D.fg, borderRadius: 16 * scale, padding: `${12 * scale}px ${18 * scale}px`, fontSize: 19 * scale, fontFamily: D.ui, lineHeight: 1.4, opacity: t, transform: `translateY(${(1 - t) * 16}px)` }}>
    {children}
  </div>
);

export const AsstText: React.FC<{ children: React.ReactNode; t?: number; scale?: number; color?: string }> = ({ children, t = 1, scale = 1, color = D.fg }) => (
  <div style={{ color, fontSize: 19 * scale, fontFamily: D.ui, lineHeight: 1.5, opacity: t, transform: `translateY(${(1 - t) * 10}px)` }}>{children}</div>
);

export const Working: React.FC<{ f: number; label?: string; scale?: number }> = ({ f, label = "Trabalhando…", scale = 1 }) => (
  <div style={{ display: "flex", alignItems: "center", gap: 10 * scale, color: D.dim, fontSize: 17 * scale, fontFamily: D.ui }}>
    <span style={{ color: "#d97757", display: "inline-block", transform: `rotate(${f * 12}deg)` }}>✻</span>{label}
  </div>
);

export const EditCard: React.FC<{ files: [string, number][]; t?: number; scale?: number }> = ({ files, t = 1, scale = 1 }) => {
  const tot = files.reduce((a, [, n]) => a + n, 0);
  return (
    <div style={{ border: `1px solid ${D.line}`, borderRadius: 14 * scale, background: D.card, fontFamily: D.ui, overflow: "hidden", opacity: t, transform: `translateY(${(1 - t) * 12}px)` }}>
      <div style={{ display: "flex", justifyContent: "space-between", padding: `${12 * scale}px ${18 * scale}px`, fontSize: 17 * scale, color: D.fg, borderBottom: `1px solid ${D.line}` }}>
        <span>Editou {files.length} arquivos</span><span style={{ color: D.green }}>+{tot} -0</span>
      </div>
      {files.map(([fn, n]) => (
        <div key={fn} style={{ display: "flex", justifyContent: "space-between", padding: `${9 * scale}px ${18 * scale}px`, fontSize: 16 * scale, color: D.dim }}>
          <span style={{ fontFamily: D.mono }}>{fn}</span><span style={{ color: D.green }}>+{n} -0</span>
        </div>
      ))}
    </div>
  );
};

// Janela inteira. `children` = a conversa (coluna, de cima pra baixo, colada no composer).
export const Desk: React.FC<{
  w: number; h: number; sidebar?: boolean; title?: string; active?: number; sessions?: string[]; user?: string; plan?: string;
  composer: React.ReactNode; children: React.ReactNode; style?: React.CSSProperties; pad?: number; overlay?: React.ReactNode;
}> = ({ w, h, sidebar = true, title, active = 0, sessions: list = SESSIONS, user = "Você", plan = "Max", composer, children, style, pad = 40, overlay }) => {
  // Título que não está na lista vira a sessão ativa: janela e sidebar sempre concordam.
  const sessions = title && !list.includes(title) ? [title, ...list.slice(0, 4)] : list;
  if (title && sessions.includes(title)) active = sessions.indexOf(title);
  return (
  <div style={{ position: "relative", width: w, height: h, background: D.win, borderRadius: 16, border: `1px solid ${D.line}`, overflow: "hidden", display: "flex", flexDirection: "column", boxShadow: "0 40px 90px rgba(0,0,0,0.45)", ...style }}>
    <div style={{ height: 52, display: "flex", alignItems: "center", gap: 18, padding: "0 20px", borderBottom: `1px solid ${D.line}`, fontFamily: D.ui, flexShrink: 0 }}>
      <Dots />
      <div style={{ marginLeft: sidebar ? 220 : 16, fontSize: 16, fontWeight: 600, color: D.fg, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{title ?? sessions[active]}</div>
    </div>
    <div style={{ flex: 1, display: "flex", position: "relative", minHeight: 0 }}>
      {sidebar ? <Sidebar active={active} sessions={sessions} user={user} plan={plan} /> : null}
      <div style={{ flex: 1, display: "flex", flexDirection: "column", padding: `${pad * 0.7}px ${pad}px ${pad * 0.6}px`, minWidth: 0 }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "flex-end", gap: 18, overflow: "hidden" }}>{children}</div>
        <div style={{ marginTop: 18 }}>{composer}</div>
      </div>
    </div>
    {overlay ? <div style={{ position: "absolute", inset: 0, pointerEvents: "none" }}>{overlay}</div> : null}
  </div>
  );
};

// Centro do botão de enviar do Composer, em coordenadas da janela (Desk de w×h, `pad` e `scale`
// iguais aos do Desk e do Composer): onde o Cursor clica.
export const sendButton = (w: number, h: number, pad: number, scale: number): [number, number] => [
  w - 1 - pad - 18 * scale - 14 * scale,
  h - 1 - pad * 0.6 - 10 * scale - 14 * scale,
];

// Cursor com clique (ficha do MDE): viaja `trip` quadros (15–21 = 500–700 ms a 30 fps) numa curva
// de Bézier de `from` até `to`, aperta a 85% no quadro `at` e solta uma onda de 9 quadros (300 ms).
// Snap, then hold: o aperto acontece em 2 quadros e a volta assenta. Some em 6 quadros depois de
// `hide` (a saída é mais curta que a viagem). Coordenadas do pai (no Desk, use o `overlay`).
export const Cursor: React.FC<{
  f: number; at: number; from: [number, number]; to: [number, number]; trip?: number; bend?: number;
  size?: number; hide?: number; ripple?: string;
}> = ({ f, at, from, to, trip = 18, bend = 0.25, size = 1, hide, ripple = "rgba(255,255,255,0.55)" }) => {
  const t0 = at - trip;
  if (f < t0 - 2) return null;
  const u = ip(f, [t0, at], [0, 1], EASE_INOUT);
  const [x0, y0] = from;
  const [x2, y2] = to;
  // ponto de controle afastado da reta, para o trajeto curvar como a mão
  const x1 = (x0 + x2) / 2 - (y2 - y0) * bend;
  const y1 = (y0 + y2) / 2 + (x2 - x0) * bend;
  const x = (1 - u) ** 2 * x0 + 2 * (1 - u) * u * x1 + u * u * x2;
  const y = (1 - u) ** 2 * y0 + 2 * (1 - u) * u * y1 + u * u * y2;
  const press = f < at ? 1 : f < at + 2 ? ip(f, [at, at + 2], [1, 0.85]) : ip(f, [at + 3, at + 9], [0.85, 1]);
  const wave = ip(f, [at, at + 9], [0, 1], (k) => k);
  const fade = hide === undefined ? 1 : 1 - ip(f, [hide, hide + 6], [0, 1]);
  const appear = ip(f, [t0 - 2, t0 + 2], [0, 1]);
  return (
    <>
      {f >= at && f <= at + 9 ? (
        <div style={{ position: "absolute", left: x2 - 34 * size * wave, top: y2 - 34 * size * wave, width: 68 * size * wave, height: 68 * size * wave, borderRadius: "50%", border: `${3 * size}px solid ${ripple}`, opacity: 1 - wave }} />
      ) : null}
      <svg width={30 * size} height={38 * size} viewBox="0 0 28 35" style={{ position: "absolute", left: x - 3 * size, top: y - 2 * size, opacity: appear * fade, transform: `scale(${press})`, transformOrigin: "3px 2px", filter: "drop-shadow(0 3px 6px rgba(0,0,0,0.45))" }}>
        <path d="M3 2 L3 27 L9.5 21 L14 31 L18 29 L13.6 19.4 L22 19.4 Z" fill="#111" stroke="#fff" strokeWidth={2} strokeLinejoin="round" />
      </svg>
    </>
  );
};

// Digitação: quanto do texto aparece no frame f, começando em `at` (cps = caracteres por frame).
export const typing = (s: string, f: number, at: number, cps = 1.4) => s.slice(0, Math.max(0, Math.floor((f - at) * cps)));
export const fadeIn = (f: number, at: number, d = 8) => ip(f, [at, at + d], [0, 1]);
