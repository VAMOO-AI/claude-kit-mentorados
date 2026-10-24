// CPU de uma página em execução, por fase: parada no topo, rolando, parada no meio.
//
//   node runtime-bench.mjs <url> [desktop|mobile] [--runs 3] [--segundos 10]
//
// Saída (JSON, mediana dos runs), por fase:
//   cpu_main    % de uma CPU gasto na main thread (TaskDuration / tempo de parede)
//   script_ms   ms de JavaScript na fase (na rolagem, inclui o scrollTo do próprio bench)
//   style_por_s recálculos de estilo por segundo (≈60 parado = algo anima a cada frame)
//   layouts     layouts forçados na fase
//   cpu_chrome  % de CPU de todos os processos do Chrome (raster, GPU, compositor);
//               no perfil mobile o piso é ~78% numa página em branco (composição por software)
import { abrir, cpuDosProcessos, sleep, mediana } from './cdp.mjs';

const args = process.argv.slice(2);
const opcao = (nome, padrao) => { const i = args.indexOf(nome); return i >= 0 ? Number(args[i + 1]) : padrao; };
const [url, perfil = 'desktop'] = args.filter((a, i) => !a.startsWith('--') && !args[i - 1]?.startsWith('--'));
const runs = opcao('--runs', 3);
const segundos = opcao('--segundos', 10);

if (!url) {
  console.error('uso: node runtime-bench.mjs <url> [desktop|mobile] [--runs 3] [--segundos 10]');
  process.exit(2);
}

async function umaRodada() {
  const b = await abrir(perfil);
  try {
    await b.send('Performance.enable');
    await b.navegar(url);
    const metricas = async () => Object.fromEntries((await b.send('Performance.getMetrics')).metrics.map(m => [m.name, m.value]));

    const fase = async (nome, acao) => {
      const a = await metricas(); const c0 = cpuDosProcessos(b.marca); const t0 = Date.now();
      await acao();
      const d = await metricas(); const c1 = cpuDosProcessos(b.marca); const parede = (Date.now() - t0) / 1000;
      return {
        fase: nome,
        cpu_main: +(100 * (d.TaskDuration - a.TaskDuration) / parede).toFixed(1),
        script_ms: Math.round(1000 * (d.ScriptDuration - a.ScriptDuration)),
        style_por_s: +((d.RecalcStyleCount - a.RecalcStyleCount) / parede).toFixed(1),
        layouts: d.LayoutCount - a.LayoutCount,
        cpu_chrome: +(100 * (c1 - c0) / parede).toFixed(1),
      };
    };

    const ms = segundos * 1000;
    const out = [];
    out.push(await fase('parado no topo', () => sleep(ms)));
    out.push(await fase('rolando a página inteira', () => b.ev(`new Promise(r => {
      const H = document.documentElement.scrollHeight - innerHeight, t0 = performance.now();
      (function passo(t) { const p = Math.min((t - t0) / ${ms}, 1); scrollTo(0, H * p); p < 1 ? requestAnimationFrame(passo) : r(); })(t0);
    })`)));
    await b.ev('scrollTo(0, document.documentElement.scrollHeight * 0.55)');
    await sleep(1500);
    out.push(await fase('parado no meio', () => sleep(ms)));
    return out;
  } finally {
    await b.fechar();
  }
}

const rodadas = [];
for (let i = 0; i < runs; i++) rodadas.push(await umaRodada());

const campos = ['cpu_main', 'script_ms', 'style_por_s', 'layouts', 'cpu_chrome'];
const fases = rodadas[0].map((f, j) => ({
  fase: f.fase,
  ...Object.fromEntries(campos.map(k => [k, mediana(rodadas.map(r => r[j][k]))])),
}));
console.log(JSON.stringify({ url, perfil, runs, segundos, medido_em: new Date().toISOString(), fases }, null, 1));
