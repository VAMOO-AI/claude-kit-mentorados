// Cliente CDP mínimo: Chrome headless + WebSocket nativo do Node 22. Zero npm install.
import { spawn, execSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export const sleep = ms => new Promise(r => setTimeout(r, ms));

export const PERFIS = {
  desktop: { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false, cpu: 1 },
  // iPhone 12-14 com CPU 4x mais lenta: o celular médio do cliente, não o MacBook.
  mobile: { width: 390, height: 844, deviceScaleFactor: 3, mobile: true, cpu: 4 },
};

export function chromePath() {
  const candidatos = [
    process.env.CHROME,
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
  ];
  const achado = candidatos.find(p => p && existsSync(p));
  if (!achado) throw new Error('Chrome não encontrado — defina CHROME=/caminho/do/chrome');
  return achado;
}

// CPU acumulada (s) de todos os processos cujo comando contém `marca`.
// macOS: "m:ss.cc"; Linux: "hh:mm:ss" (resolução de 1 s — em janela de 10 s, ±10%).
export function cpuDosProcessos(marca) {
  return execSync('ps -A -o time=,command=').toString().split('\n')
    .filter(l => l.includes(marca))
    .reduce((soma, l) => soma + l.trim().split(/\s+/)[0].replace(/^\d+-/, '').split(':')
      .reduce((acc, parte) => acc * 60 + parseFloat(parte), 0), 0);
}

export async function abrir(perfil = 'desktop', ajustes = {}) {
  if (typeof WebSocket === 'undefined') throw new Error('precisa de Node 22+ (WebSocket nativo)');
  if (!PERFIS[perfil]) throw new Error(`perfil desconhecido: ${perfil} (use desktop|mobile)`);
  const p = { ...PERFIS[perfil], ...ajustes };

  const port = 9300 + Math.floor(Math.random() * 500);
  const dir = mkdtempSync(join(tmpdir(), 'otimizar-app-'));
  const proc = spawn(chromePath(), [
    '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${dir}`,
    '--no-first-run', '--no-default-browser-check', 'about:blank',
  ], { stdio: 'ignore' });

  let alvo;
  for (let i = 0; i < 75 && !alvo; i++) {
    await sleep(200);
    try { alvo = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t => t.type === 'page'); } catch {}
  }
  if (!alvo) { proc.kill(); throw new Error('Chrome não abriu a porta de debug em 15 s'); }

  const ws = new WebSocket(alvo.webSocketDebuggerUrl);
  await new Promise((ok, falha) => { ws.onopen = ok; ws.onerror = falha; });
  let id = 0;
  const pendentes = new Map();
  ws.onmessage = e => {
    const m = JSON.parse(e.data);
    if (m.id && pendentes.has(m.id)) { pendentes.get(m.id)(m.result ?? { erro: m.error }); pendentes.delete(m.id); }
  };
  const send = (method, params = {}) => new Promise(r => { const i = ++id; pendentes.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
  const ev = async expr => (await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true })).result?.value;

  await send('Emulation.setDeviceMetricsOverride', { width: p.width, height: p.height, deviceScaleFactor: p.deviceScaleFactor, mobile: p.mobile });
  if (p.mobile) await send('Emulation.setTouchEmulationEnabled', { enabled: true });
  if (p.cpu > 1) await send('Emulation.setCPUThrottlingRate', { rate: p.cpu });

  const navegar = async (url, esperaMs = 5000) => { await send('Page.navigate', { url }); await sleep(esperaMs); };
  const fechar = async () => {
    ws.close(); proc.kill();
    await sleep(500);
    try { rmSync(dir, { recursive: true, force: true }); } catch {}
  };
  return { send, ev, navegar, fechar, marca: dir };
}

export const mediana = xs => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)];
