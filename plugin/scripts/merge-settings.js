#!/usr/bin/env node
//
// Mescla o settings.json do kit no da pessoa. Extraído do kit-setup.sh em 0.8.1
// para poder ser testado sozinho (tests/test-merge-settings.sh) — antes o merge
// vivia num heredoc dentro do instalador e só dava pra exercitar rodando o
// instalador inteiro contra o ~/.claude de verdade.
//
//   node merge-settings.js <kit.json> <meu.json>
//
// Regras, em uma linha cada:
//   • chave que você já tem ganha da do kit — o kit só preenche o que falta;
//   • allow, deny e ask são UNIÃO: o kit acrescenta e nunca tira o que é seu;
//   • defaultMode é preferência sua: o kit só define se você nunca escolheu, e
//     avisa (sem mexer) quando o seu é diferente do recomendado;
//   • extraKnownMarketplaces é mesclado POR marketplace: a fonte que você já
//     tem nunca é trocada, e o kit só acrescenta o `autoUpdate` que falta.
//
// Perder um `deny` é abrir buraco de segurança — por isso ele entra na união em
// vez de ficar de fora, que era o caso até 0.8.0: quem já tinha o kit instalado
// nunca recebia barreira nova.
//
// O caso do `extraKnownMarketplaces` é o mesmo defeito com outra cara, achado em
// 10/09/2026: o `/plugin marketplace add` escreve essa chave no settings de quem
// instala, então ela JÁ existe em toda máquina com o kit — e "o seu ganha"
// significava que o `autoUpdate: true` nunca chegava em ninguém. O kit ficava
// parado na versão do dia da instalação, que é justamente o que ele não deve
// fazer.
const fs = require('fs');
const [, , kitPath, userPath] = process.argv;
if (!kitPath || !userPath) {
  console.error('uso: merge-settings.js <kit.json> <meu.json>');
  process.exit(2);
}
const kit = JSON.parse(fs.readFileSync(kitPath, 'utf8'));
let user = {};
if (fs.existsSync(userPath)) {
  try {
    user = JSON.parse(fs.readFileSync(userPath, 'utf8'));
  } catch {
    console.log('! settings.json existente está com JSON inválido — mantive o seu e não mesclei nada.');
    process.exit(0);
  }
}

const novas = [];
for (const [k, v] of Object.entries(kit)) {
  if (k === 'permissions' || k === 'extraKnownMarketplaces') continue;
  if (user[k] === undefined) { user[k] = v; novas.push(k); }
}

const kitMarkets = kit.extraKnownMarketplaces || {};
if (Object.keys(kitMarkets).length) {
  user.extraKnownMarketplaces = user.extraKnownMarketplaces || {};
  for (const [nome, entradaKit] of Object.entries(kitMarkets)) {
    const meu = user.extraKnownMarketplaces[nome];
    if (!meu) {
      user.extraKnownMarketplaces[nome] = entradaKit;
      novas.push(`extraKnownMarketplaces.${nome}`);
      continue;
    }
    if (entradaKit.autoUpdate === undefined) continue;
    if (meu.autoUpdate === undefined) {
      meu.autoUpdate = entradaKit.autoUpdate;
      novas.push(`extraKnownMarketplaces.${nome}.autoUpdate (${entradaKit.autoUpdate})`);
    } else if (meu.autoUpdate !== entradaKit.autoUpdate) {
      console.log(`  o auto-update do marketplace "${nome}" está como ${meu.autoUpdate} no seu settings — mantive o seu.`);
      console.log(`  pra ligar: mude autoUpdate para true em extraKnownMarketplaces.${nome} no ~/.claude/settings.json`);
    }
  }
}

const kitPerms = kit.permissions || {};
user.permissions = user.permissions || {};
for (const lista of ['allow', 'deny', 'ask']) {
  const meus = user.permissions[lista] || [];
  const vistos = new Set(meus);
  const acrescentar = (kitPerms[lista] || []).filter((p) => !vistos.has(p));
  if (acrescentar.length) novas.push(`permissions.${lista} (+${acrescentar.length})`);
  if (meus.length || acrescentar.length) user.permissions[lista] = [...meus, ...acrescentar];
}

const meuModo = user.permissions.defaultMode;
if (meuModo === undefined && kitPerms.defaultMode) {
  user.permissions.defaultMode = kitPerms.defaultMode;
  novas.push(`permissions.defaultMode (${kitPerms.defaultMode})`);
} else if (meuModo && kitPerms.defaultMode && meuModo !== kitPerms.defaultMode) {
  console.log(`  seu modo de permissão é "${meuModo}" e o kit recomenda "${kitPerms.defaultMode}" — mantive o seu.`);
  console.log(`  pra trocar: /config, ou mude permissions.defaultMode no ~/.claude/settings.json`);
}

fs.writeFileSync(userPath, JSON.stringify(user, null, 2) + '\n');
console.log(novas.length ? `  acrescentado: ${novas.join(', ')}` : '  já estava tudo lá — nada mudou');
