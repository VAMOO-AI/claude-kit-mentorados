// Prova de "não mudou a estrutura": posição e tamanho das caixas da página, sem screenshot.
//
//   node layout-snapshot.mjs <url> [desktop|mobile] > antes.json
//   node layout-snapshot.mjs --compare antes.json depois.json [--tol 2]
//
// Mede o layout sem transform (offsetTop/offsetWidth), com setInterval desligado e
// content-visibility forçado a visible, então animação, parallax, carrossel com autoplay
// e seção fora da tela não geram diferença falsa. O que o snapshot
// não vê — cor, blur, opacidade, a animação em si — se prova com um screenshot de cada lado.
// --compare sai com código 1 quando há diferença.
import { readFileSync } from 'node:fs';
import { abrir, sleep } from './cdp.mjs';

const args = process.argv.slice(2);

if (args[0] === '--compare') {
  const [, arqA, arqB] = args;
  const i = args.indexOf('--tol');
  const tol = i >= 0 ? Number(args[i + 1]) : 2;
  const A = JSON.parse(readFileSync(arqA, 'utf8'));
  const B = JSON.parse(readFileSync(arqB, 'utf8'));
  const porChave = s => new Map(s.caixas.map(c => [c.chave, c]));
  const [mA, mB] = [porChave(A), porChave(B)];
  const linhas = [];

  if (Math.abs(A.altura - B.altura) > tol) linhas.push(`altura da página  ${A.altura} → ${B.altura} (${B.altura - A.altura > 0 ? '+' : ''}${B.altura - A.altura})`);
  for (const [chave, a] of mA) {
    const b = mB.get(chave);
    if (!b) { linhas.push(`sumiu   ${chave}`); continue; }
    const deltas = ['top', 'left', 'w', 'h'].filter(k => Math.abs(a[k] - b[k]) > tol).map(k => `${k} ${a[k]}→${b[k]}`);
    if (deltas.length) linhas.push(`mudou   ${chave}  ${deltas.join('  ')}`);
  }
  for (const chave of mB.keys()) if (!mA.has(chave)) linhas.push(`novo    ${chave}`);

  console.log(linhas.length ? linhas.join('\n') : `0 diferenças (${mA.size} caixas, tolerância ${tol}px)`);
  process.exit(linhas.length ? 1 : 0);
}

const [url, perfil = 'desktop'] = args;
if (!url) {
  console.error('uso: node layout-snapshot.mjs <url> [desktop|mobile]  |  --compare a.json b.json [--tol 2]');
  process.exit(2);
}

// CPU sem throttle aqui: o snapshot é sobre geometria, não sobre tempo.
const b = await abrir(perfil, { cpu: 1, deviceScaleFactor: 1 });
try {
  // Carrossel/rotativo com autoplay gira por setInterval e troca quais itens existem:
  // dois snapshots da mesma página davam "novo IMG" no mobile. Sem intervalo, fica no estado inicial.
  await b.send('Page.enable');
  await b.send('Page.addScriptToEvaluateOnNewDocument', { source: 'window.setInterval = () => 0;' });
  await b.navegar(url, 4000);
  // content-visibility: auto pula o layout do que está fora da tela, e a caixa sai 0x0
  // em um run e com tamanho no outro (landing com `img { content-visibility: auto }`, 24/09).
  await b.ev(`document.head.insertAdjacentHTML('beforeend', '<style>*, *::before, *::after { content-visibility: visible !important }</style>')`);
  // Rola a página toda para disparar lazy load e IntersectionObserver, e volta ao topo.
  await b.ev(`new Promise(async r => {
    for (let y = 0; y < document.documentElement.scrollHeight; y += 400) { scrollTo(0, y); await new Promise(q => setTimeout(q, 80)); }
    scrollTo(0, 0); setTimeout(r, 1500);
  })`);
  await sleep(500);
  const dados = await b.ev(`(() => {
    const vistos = new Map();
    const caixas = [];
    document.querySelectorAll('header,nav,main,section,footer,h1,h2,h3,button,a,img,video,canvas,form,input').forEach(el => {
      if (!el.offsetWidth && !el.offsetHeight) return;
      let top = 0, left = 0;
      for (let e = el; e; e = e.offsetParent) { top += e.offsetTop; left += e.offsetLeft; }
      const rotulo = (el.id || el.getAttribute('aria-label') || el.getAttribute('alt') || el.innerText || el.getAttribute('src') || '')
        .trim().replace(/\\s+/g, ' ').slice(0, 40);
      const base = el.tagName + ' "' + rotulo + '"';
      const n = (vistos.get(base) || 0) + 1; vistos.set(base, n);
      caixas.push({ chave: n > 1 ? base + ' #' + n : base, top, left, w: el.offsetWidth, h: el.offsetHeight });
    });
    return { altura: document.documentElement.scrollHeight, caixas };
  })()`);
  console.log(JSON.stringify({ url, perfil, medido_em: new Date().toISOString(), ...dados }));
} finally {
  await b.fechar();
}
