// Avisa o IndexNow (Bing, Copilot e outros) de todas as URLs do sitemap. Rode no fim do deploy de produção.
// Uso: node indexnow.mjs https://<dominio> <chave>
// A chave é pública por protocolo: https://<dominio>/<chave>.txt precisa servir só ela.
const [site, key] = process.argv.slice(2);
if (!site || !key) {
  console.error('uso: node indexnow.mjs https://<dominio> <chave>');
  process.exit(2);
}
const base = site.replace(/\/$/, '');
const keyLocation = `${base}/${key}.txt`;

const keyFile = await fetch(keyLocation);
if (!keyFile.ok || (await keyFile.text()).trim() !== key) {
  throw new Error(`IndexNow: ${keyLocation} não serve a chave (HTTP ${keyFile.status})`);
}

const sitemap = await fetch(`${base}/sitemap.xml`);
if (!sitemap.ok) throw new Error(`IndexNow: sitemap.xml respondeu ${sitemap.status}`);
const urlList = [...(await sitemap.text()).matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1].trim());
if (urlList.length === 0) throw new Error('IndexNow: sitemap.xml sem <loc>');

const response = await fetch('https://api.indexnow.org/indexnow', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
  body: JSON.stringify({ host: new URL(base).host, key, keyLocation, urlList }),
});
// 200 e 202 são aceite; 422 é URL fora do host ou chave que não bate.
if (response.status !== 200 && response.status !== 202) {
  throw new Error(`IndexNow respondeu ${response.status}: ${await response.text()}`);
}
console.log(`IndexNow: ${urlList.length} URLs aceitas (HTTP ${response.status})`);
