// Mapa animado do Film: destaque de região e rota que se desenha parada a parada. Mapa-múndi do
// Natural Earth (domínio público) pelo world-atlas (countries-110m, ISC), decodificado pelo
// topojson-client (ISC) e projetado pelo d3-geo (ISC) em Natural Earth 1. Mesmo molde das cenas do
// film-scenes.tsx: useF, useL, bt, first, fit.
import React from "react";
import { Easing } from "remotion";
import { geoInterpolate, geoNaturalEarth1, geoPath } from "d3-geo";
import { feature } from "topojson-client";
import type { GeometryCollection, Topology } from "topojson-specification";
import type { Feature, FeatureCollection, Geometry } from "geojson";
import world from "world-atlas/countries-110m.json";
import { H1, LABEL, type SP, bt, first, fit, useL } from "./film-base";
import { Bg, C, EASE_INOUT, ip, useF } from "./lib";
import { enquadramento } from "./tempos.mjs";

// Curvas da doutrina de motion (vocabulario.md). Atalho: definidas aqui enquanto o lib.tsx não as
// exporta; quando exportar, troque por import de ./lib.
const SETTLE = Easing.bezier(0, 0.65, 0.51, 0.99);
const POP = Easing.out(Easing.back(1.7));

type Pais = Feature<Geometry, { name: string }>;
const topo = world as unknown as Topology<{ countries: GeometryCollection<{ name: string }> }>;
const PAISES = (feature(topo, topo.objects.countries) as FeatureCollection<Geometry, { name: string }>).features as Pais[];

type Parada = { name?: string; at: [number, number] };

// Pontos da rota em lon/lat, seguindo o arco de círculo máximo entre as paradas: u vai de 0 a n−1
// (u = j é a parada j).
const arco = (paradas: Parada[], u: number, passos = 48) => {
  const pts: [number, number][] = [];
  for (let j = 0; j < paradas.length - 1 && j < u; j++) {
    const ir = geoInterpolate(paradas[j].at, paradas[j + 1].at);
    const ate = Math.min(1, u - j);
    const n = Math.max(1, Math.ceil(passos * ate));
    for (let k = 0; k <= n; k++) pts.push(ir((k / n) * ate) as [number, number]);
  }
  return pts;
};

// props: route [{name?, at: [lon, lat]}] (2–6 paradas), region? (nome do país em inglês, como no
// Natural Earth: "Brazil"), title?, kicker?, seg? (frames por trecho, padrão 24). O mapa entra com a
// câmera assentando; a região acende; a rota sai na 2ª fala (ou no frame 30) e cada parada acende
// quando a linha chega; a última pousa com overshoot e pulsa.
export const MapRoute: React.FC<SP> = (p) => {
  const f = useF();
  const L = useL();
  const paradas: Parada[] = (p.route ?? []).slice(0, 6);
  const seg: number = p.seg ?? 24;
  const regiao = p.region ? PAISES.find((c) => c.properties.name === p.region) : undefined;
  if (p.region && !regiao) throw new Error(`map: a região "${p.region}" não existe no Natural Earth (use o nome em inglês do world-atlas, ex.: "Brazil")`);
  const t0 = first(p);
  const tReg = t0 + 10;
  const tR: number = p.beats.length > 1 ? bt(p, 1) - 4 : 30;
  const chega = (j: number) => tR + j * seg;
  const u = paradas.length > 1 ? Math.min(paradas.length - 1, paradas.reduce((acc, _, j) => (j ? acc + ip(f, [chega(j - 1), chega(j)], [0, 1], EASE_INOUT) : 0), 0)) : 0;

  // câmera: enquadra a região e as paradas e assenta de longe para perto
  const alto = p.title ? (L.v ? 300 : 150) : 0;
  const caixa: [[number, number], [number, number]] = [[L.l, L.t + alto], [L.W - L.r, L.H - L.b]];
  const alvo = {
    type: "FeatureCollection" as const,
    features: [
      ...(regiao ? [regiao] : []),
      // nunca um ponto só: sem região e com menos de 2 paradas distintas, entra uma caixa em volta
      { type: "Feature" as const, properties: {}, geometry: { type: "MultiPoint" as const, coordinates: enquadramento(paradas.map((s) => s.at), !!regiao) } },
    ],
  };
  const proj = geoNaturalEarth1().fitExtent(caixa, alvo);
  const k = ip(f, [t0, t0 + 40], [0.5, 0.9], SETTLE);
  const cx = (caixa[0][0] + caixa[1][0]) / 2;
  const cy = (caixa[0][1] + caixa[1][1]) / 2;
  const meio = proj.invert?.([cx, cy]) ?? [0, 0];
  proj.scale(proj.scale() * k).translate([cx, cy]).center([0, 0]).rotate([-meio[0], -meio[1]]);
  const path = geoPath(proj);
  const xy = (ll: [number, number]) => proj(ll) ?? [-999, -999];

  const rota = arco(paradas, u);
  const d = rota.length > 1 ? "M" + rota.map((q) => xy(q).map((n) => n.toFixed(1)).join(" ")).join(" L") : "";
  const cabeca = rota.length ? xy(rota[rota.length - 1]) : null;
  const acende = ip(f, [tReg, tReg + 14], [0, 1]);
  const ultima = paradas.length - 1;
  const fs = L.v ? 40 : 36;

  return (
    <Bg color={C.night}>
      <svg width={L.W} height={L.H} style={{ position: "absolute", opacity: ip(f, [t0, t0 + 8], [0, 1]) }}>
        {PAISES.map((c, i) => (
          <path key={i} d={path(c) ?? ""} fill={c === regiao ? "#141c2a" : "#10151d"} stroke="rgba(255,255,255,0.10)" strokeWidth={1} />
        ))}
        {regiao ? <path d={path(regiao) ?? ""} fill={C.accentFill} fillOpacity={0.55 * acende} stroke={C.brandOnDark} strokeOpacity={acende} strokeWidth={2.5} /> : null}
        {d ? <path d={d} fill="none" stroke={C.brandOnDark} strokeWidth={L.v ? 7 : 6} strokeLinecap="round" strokeLinejoin="round" /> : null}
        {paradas.map((s, j) => {
          const t = chega(j);
          if (f < t - (j === 0 ? 2 : 0)) return null;
          const [x, y] = xy(s.at);
          const fim = j === ultima;
          const pop = ip(f, [t, t + 10], [0, 1], POP);
          const ping = fim ? ((f - t) % 30) / 30 : -1;
          return (
            <g key={j}>
              {fim && f >= t ? <circle cx={x} cy={y} r={(10 + 34 * ping) * (L.v ? 1.6 : 1)} fill="none" stroke={C.brandOnDark} strokeWidth={3} opacity={1 - ping} /> : null}
              <circle cx={x} cy={y} r={(fim ? 13 : 9) * pop} fill={C.white} stroke={C.brandOnDark} strokeWidth={4} />
            </g>
          );
        })}
        {cabeca && u > 0 && u < ultima ? <circle cx={cabeca[0]} cy={cabeca[1]} r={7} fill={C.white} /> : null}
      </svg>
      {paradas.map((s, j) => {
        if (!s.name) return null;
        const t = chega(j) + 4; // o nome entra depois do ponto (apoio depois do foco)
        if (f < t) return null;
        const [x, y] = xy(s.at);
        const esq = x > L.W - L.r - 260;
        return (
          <div key={j} style={{ position: "absolute", left: esq ? undefined : x + 22, right: esq ? L.W - x + 22 : undefined, top: y - fs * 0.7, opacity: ip(f, [t, t + 8], [0, 1]), transform: `translateY(${ip(f, [t, t + 10], [10, 0])}px)` }}>
            <span style={{ ...H1, fontSize: fs, color: C.white, whiteSpace: "nowrap", textShadow: "0 2px 12px rgba(0,0,0,0.8)" }}>{s.name}</span>
          </div>
        );
      })}
      {p.title || p.kicker ? (
        <div style={{ position: "absolute", left: L.l, right: L.r, top: L.t }}>
          {p.kicker ? <div style={{ ...LABEL, fontSize: L.v ? 28 : 24, color: C.faint, opacity: ip(f, [t0 + 4, t0 + 12], [0, 1]) }}>{p.kicker}</div> : null}
          {p.title ? (
            <div style={{ ...H1, marginTop: 10, fontSize: fit([p.title], L.W - L.l - L.r, L.v ? 84 : 76), color: C.white, opacity: ip(f, [t0, t0 + 10], [0, 1]), transform: `translateY(${ip(f, [t0, t0 + 14], [24, 0])}px)` }}>
              {p.title}
            </div>
          ) : null}
        </div>
      ) : null}
    </Bg>
  );
};
