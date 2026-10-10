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
//   • defaultMode: Manual ("default") ou ausente vira o do kit, salvo o marcador
//     kit-vamoo/manter-modo-manual; auto, bypass, plan e dontAsk ficam;
//   • extraKnownMarketplaces é mesclado POR marketplace: a fonte que você já
//     tem nunca é trocada, e o kit só acrescenta o `autoUpdate` que falta;
//   • hooks são seus — o único que sai é o dispatch do dotcontext que o
//     instalador antigo gravou, casado pelo comando exato.
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
const path = require('path');
const [, , kitPath, userPath] = process.argv;
if (!kitPath || !userPath) {
  console.error('uso: merge-settings.js <kit.json> <meu.json>');
  process.exit(2);
}
const kit = JSON.parse(fs.readFileSync(kitPath, 'utf8'));
let user = {};
// Arquivo vazio não tem o que perder e vira {}; JSON inválido é mantido, e o aviso traz o
// lugar do erro (linha e coluna) para a pessoa achar a vírgula sem abrir o arquivo às cegas.
if (fs.existsSync(userPath)) {
  const bruto = fs.readFileSync(userPath, 'utf8');
  if (bruto.trim()) {
    try {
      user = JSON.parse(bruto);
    } catch (e) {
      // Node < 22 só diz a posição; linha e coluna saem dela.
      const pos = /position (\d+)/.exec(e.message);
      // Sem posição (ex.: BOM no início), a mensagem do V8 cita o conteúdo do arquivo — corta.
      let onde = e.message.replace(/,\s*".*" is not valid JSON$/s, '');
      if (pos) {
        const antes = bruto.slice(0, Number(pos[1])).split('\n');
        onde = `linha ${antes.length}, coluna ${antes[antes.length - 1].length + 1}`;
      }
      console.log(`! settings.json existente está com JSON inválido (${onde}) — mantive o seu e não mesclei nada.`);
      process.exit(0);
    }
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
const allowAntes = [...(user.permissions.allow || [])];
const askAntes = new Set(user.permissions.ask || []);
for (const lista of ['allow', 'deny', 'ask']) {
  const meus = user.permissions[lista] || [];
  const vistos = new Set(meus);
  const acrescentar = (kitPerms[lista] || []).filter((p) => !vistos.has(p));
  if (acrescentar.length) novas.push(`permissions.${lista} (+${acrescentar.length})`);
  if (meus.length || acrescentar.length) user.permissions[lista] = [...meus, ...acrescentar];
}

// Modo de permissão (0.48.0). Manual (`default`) ou modo ausente vira o do kit
// (`acceptEdits`): o kit não quer mentorado aprovando edição por edição. `auto`,
// `bypassPermissions`, `plan` e `dontAsk` ficam — são escolhas mais permissivas ou
// deliberadas. Quem quer o manual de vez cria o marcador ao lado do settings.json
// (~/.claude/kit-vamoo/manter-modo-manual) e o kit não troca mais. O marcador sai de
// dirname(userPath) para o teste nunca tocar o ~/.claude de verdade.
// Um `ask` do kit vence o allow que a pessoa escreveu de propósito (ordem deny → ask →
// allow). Quem tinha `Bash(git push origin main)` ou `Bash(env)` passa a ver pergunta — o
// setup diz quais, em vez de a pessoa descobrir no meio do trabalho. Mesmo casamento da doc
// (code.claude.com/docs/en/permissions#wildcard-patterns): `*` é qualquer texto e o ` *`
// final, quando é o único curinga, casa também o comando sem argumento.
const casaRegra = (padrao, cmd, semCaixa) => {
  let p = padrao.endsWith(':*') ? padrao.slice(0, -2) + ' *' : padrao;
  const esc = (t) => t.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '[\\s\\S]*');
  const so1 = (p.match(/\*/g) || []).length === 1;
  const re = so1 && p.endsWith(' *') ? '^' + esc(p.slice(0, -2)) + '( [\\s\\S]*)?$' : '^' + esc(p) + '$';
  return new RegExp(re, semCaixa ? 'i' : '').test(cmd);
};
const partes = (r) => { const m = /^([A-Za-z]+)\(([\s\S]*)\)$/.exec(r); return m ? [m[1], m[2]] : null; };
const asksNovos = (user.permissions.ask || []).filter((r) => !askAntes.has(r));
const anulados = [];
for (const r of allowAntes) {
  const pr = partes(r);
  if (!pr || (pr[0] !== 'Bash' && pr[0] !== 'PowerShell')) continue;
  const exemplo = pr[1].replace(/:\*$/, '').replace(/ \*$/, '');
  if (exemplo.includes('*')) continue;
  const quem = asksNovos.find((a) => { const pa = partes(a); return pa && pa[0] === pr[0] && casaRegra(pa[1], exemplo, pr[0] === 'PowerShell'); });
  if (quem) anulados.push(`${r} (agora pergunta por ${quem})`);
}
if (anulados.length) {
  console.log(`  aviso: ${anulados.length} permissão(ões) sua(s) passa(m) a perguntar, porque o kit pôs um ask por cima:`);
  for (const a of anulados) console.log(`    - ${a}`);
  console.log('  é de propósito: força push, push na main, descartar alteração e listar segredo têm volta difícil. Pra manter o seu, tire a linha correspondente de permissions.ask.');
}

const MARCADOR = path.join(path.dirname(userPath), 'kit-vamoo', 'manter-modo-manual');
const MODOS_MANTIDOS = ['auto', 'bypassPermissions', 'plan', 'dontAsk', 'acceptEdits'];
const meuModo = user.permissions.defaultMode;
const modoKit = kitPerms.defaultMode;
if (modoKit && meuModo !== modoKit && (meuModo === undefined || meuModo === 'default')) {
  if (fs.existsSync(MARCADOR)) {
    console.log(`  modo de permissão: mantive o manual porque existe ${MARCADOR}`);
  } else {
    user.permissions.defaultMode = modoKit;
    novas.push(`permissions.defaultMode (${meuModo || 'sem modo'} → ${modoKit})`);
    console.log(`  modo de permissão: ${meuModo === 'default' ? 'Manual ("default")' : 'sem modo definido'} → "${modoKit}" (Accept edits: edita e roda os comandos comuns sem pedir; o que é destrutivo continua pedindo).`);
    console.log(`  pra voltar ao manual de vez: crie o arquivo ${MARCADOR} e ponha permissions.defaultMode em "default" no settings.json (sem o arquivo, o próximo setup troca de novo).`);
  }
} else if (meuModo && modoKit && meuModo !== modoKit && !MODOS_MANTIDOS.includes(meuModo)) {
  console.log(`  seu modo de permissão é "${meuModo}", que o kit não conhece — mantive o seu.`);
}

// Até a 0.7.0 (24/08) o install.sh SOBRESCREVIA o settings.json com o da raiz do
// repo, que chamava o dispatch do dotcontext no SessionStart e depois de todo
// Write/Edit/Bash. Desde então o merge preserva os seus hooks — e preservava esse
// junto, que relê o repo inteiro a cada chamada (vinilana/dotcontext#93). Só sai o
// comando que o kit escreveu: um dispatch que você configurou de outro jeito não
// casa e fica.
const DISPATCH_LEGADO = '@dotcontext/cli@latest hook dispatch --source claude-code';
let legados = 0;
if (user.hooks && typeof user.hooks === 'object' && !Array.isArray(user.hooks)) {
  for (const [evento, grupos] of Object.entries(user.hooks)) {
    if (!Array.isArray(grupos)) continue;
    let mexeu = false;
    const restantes = grupos.filter((g) => {
      if (!g || !Array.isArray(g.hooks)) return true;
      const antes = g.hooks.length;
      g.hooks = g.hooks.filter((h) => !(h && typeof h.command === 'string' && h.command.includes(DISPATCH_LEGADO)));
      if (g.hooks.length === antes) return true;
      legados += antes - g.hooks.length;
      mexeu = true;
      return g.hooks.length > 0;
    });
    if (!mexeu) continue;
    if (restantes.length) user.hooks[evento] = restantes;
    else delete user.hooks[evento];
  }
}

fs.writeFileSync(userPath, JSON.stringify(user, null, 2) + '\n');
if (novas.length) console.log(`  acrescentado: ${novas.join(', ')}`);
if (legados) console.log(`  removido: hook antigo do dotcontext (${legados}) — o instalador de antes da 0.7.0 tinha gravado no seu settings.json`);
if (!novas.length && !legados) console.log('  já estava tudo lá — nada mudou');
