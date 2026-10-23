#!/usr/bin/env node
//
// Mescla o settings.json do kit no da pessoa. Extraído do kit-setup.sh em 0.8.1
// para poder ser testado sozinho (tests/test-merge-settings.sh) — antes o merge
// vivia num heredoc dentro do instalador e só dava pra exercitar rodando o
// instalador inteiro contra o ~/.claude de verdade.
//
//   node merge-settings.js <kit.json> <meu.json> [--overlay <arquivo>]... [--skills-dir <dir>]... [--estrito]
//
// Regras, em uma linha cada:
//   • chave que você já tem ganha da do kit — o kit só preenche o que falta;
//   • allow, deny e ask são UNIÃO: o kit acrescenta e nunca tira o que é seu — a
//     exceção são os allows de execução arbitrária que o próprio kit gravou até a
//     0.55.0 (ALLOWS_LEGADOS), casados pelo texto exato;
//   • defaultMode: Manual ("default"), ausente ou acceptEdits vira o do kit (auto),
//     salvo os marcadores kit-vamoo/manter-modo-manual e kit-vamoo/manter-accept-edits;
//     bypass, plan e dontAsk ficam;
//   • extraKnownMarketplaces é mesclado POR marketplace: a fonte que você já
//     tem nunca é trocada, e o kit só acrescenta o `autoUpdate` que falta;
//   • env e enabledPlugins são UNIÃO, e o seu valor vence o empate: o kit acrescenta a
//     variável ou o plugin novo e nunca troca o que você já tem;
//   • skillOverrides: o kit governa as chaves DELE; as suas ficam, e com --skills-dir a
//     de skill que não existe em nenhum desses diretórios cai, com aviso;
//   • modelSettings: o kit governa só as chaves dele dentro dos modelos que ele define;
//   • hooks são seus: o kit acrescenta, por evento, o comando que você ainda não tem, e o
//     único que sai é o dispatch do dotcontext que o instalador antigo gravou (mais os que
//     o overlay listar em hooksRemovidos).
//
// --overlay <arquivo> (F6 do núcleo único), repetível e aplicado em ordem: JSON com chaves de
// topo que substituem as do kit antes do merge (na mesma chave, a última camada vence); `hooks`
// se SOMA aos do kit, por evento. O `$merge` das camadas se soma: listas concatenam, mapas se
// juntam e o valor simples da última vale. A meta-chave `$merge` traz as
// regras de quem distribui o overlay e nunca é gravada no settings.json:
//   allowsRevogados {texto exato: substituto|null}, envDoKit {VAR: valor exato} e
//   chavesDoKit {chave: valor exato} — o que aquele kit gravou e tirou, e sai da máquina só
//   com o valor exato — e hooksRemovidos [trecho do comando]. E o que muda o padrão:
//   chavesGovernadas [chave] — chave escalar que o kit governa: volta ao valor do kit, em vez
//   de "a sua ganha" (não confundir com chavesDoKit, que só tira um valor antigo);
//   removerHooksAlheios true — hook da pessoa que não está no kit sai, com aviso nomeando
//   cada um (o backup é de quem chama o merge); scriptsEntregues [nome.sh] — script que o kit
//   instala por outro caminho, para o aviso não anunciar como perdido o que continua lá;
//   modoDaPessoa true — o defaultMode que a pessoa já tem fica, qualquer que seja (o do kit
//   só entra onde não há modo). chavesGovernadas vale para chave escalar e para objeto sem
//   regra própria (statusLine); env, hooks, permissions e as outras com regra seguem a delas.
//
// --estrito: settings.json inválido sai com rc 1 em vez de 0 (o arquivo continua intacto). O
// padrão é 0 porque o kit-setup.sh roda com `set -e`.
// Nenhum valor da casa mora aqui: quem tem histórico próprio o declara no overlay dele.
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
const USO = 'uso: merge-settings.js <kit.json> <meu.json> [--overlay <arquivo>]... [--skills-dir <dir>]... [--estrito]';
const posicionais = [];
const overlayPaths = [];
let estrito = false;
const skillDirs = [];
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a === '--estrito') { estrito = true; continue; }
  if (a === '--overlay' || a === '--skills-dir') {
    const v = process.argv[++i];
    if (!v) { console.error(USO); process.exit(2); }
    if (a === '--overlay') overlayPaths.push(v); else skillDirs.push(v);
  } else posicionais.push(a);
}
const [kitPath, userPath] = posicionais;
if (!kitPath || !userPath || posicionais.length > 2) {
  console.error(USO);
  process.exit(2);
}
const kit = JSON.parse(fs.readFileSync(kitPath, 'utf8'));
const objeto = (v) => !!v && typeof v === 'object' && !Array.isArray(v);

// Linha e coluna do erro de JSON, para a pessoa achar a vírgula sem abrir o arquivo às cegas.
const ondeErro = (e, bruto) => {
  // Node < 22 só diz a posição; linha e coluna saem dela.
  // Arquivo que acaba no meio ("Unexpected end of JSON input") não traz posição: é o fim dele.
  const pos = /position (\d+)/.exec(e.message) || (/end of JSON input/.test(e.message) && [null, bruto.trimEnd().length]);
  // Sem posição (ex.: BOM no início), a mensagem do V8 cita o conteúdo do arquivo — corta.
  if (!pos) return e.message.replace(/,\s*".*" is not valid JSON$/s, '');
  const antes = bruto.slice(0, Number(pos[1])).split('\n');
  return `linha ${antes.length}, coluna ${antes[antes.length - 1].length + 1}`;
};

let user = {};
// Arquivo vazio não tem o que perder e vira {}; JSON inválido é mantido e o setup segue
// (rc 0: o kit-setup.sh roda com `set -e`). Com --estrito, quem chama recebe rc 1.
if (fs.existsSync(userPath)) {
  const bruto = fs.readFileSync(userPath, 'utf8');
  if (bruto.trim()) {
    try {
      user = JSON.parse(bruto);
    } catch (e) {
      console.log(`! settings.json existente (${userPath}) está com JSON inválido (${ondeErro(e, bruto)})— mantive o seu e não mesclei nada.`);
      process.exit(estrito ? 1 : 0);
    }
  }
}

// ── Overlay ────────────────────────────────────────────────────────────────────────────
// Overlay quebrado não derruba o merge: segue com o valor do kit, e o aviso diz o que está
// errado (linha e coluna, ou "vazio").
let regras = {};
// Soma o `$merge` de uma camada ao das anteriores: lista concatena, mapa junta, valor simples troca.
const somaRegras = (a, b) => {
  const r = { ...a };
  for (const [k, v] of Object.entries(b)) {
    if (Array.isArray(v) && Array.isArray(r[k])) r[k] = [...r[k], ...v];
    else if (objeto(v) && objeto(r[k])) r[k] = { ...r[k], ...v };
    else r[k] = v;
  }
  return r;
};
for (const overlayPath of overlayPaths) {
  let ov;
  let bruto = null;
  try { bruto = fs.readFileSync(overlayPath, 'utf8'); } catch (e) {
    console.log(`! overlay ${overlayPath} ilegível (${e.code || e.message}) — ignorado, valem as chaves do kit`);
  }
  if (bruto !== null) {
    try { ov = JSON.parse(bruto); } catch (e) {
      console.log(`! overlay ${overlayPath} com JSON inválido (${ondeErro(e, bruto)}) — ignorado, valem as chaves do kit`);
    }
  }
  if (ov !== undefined && !objeto(ov)) {
    console.log(`! overlay ${overlayPath} não é um objeto JSON — ignorado, valem as chaves do kit`);
  } else if (ov !== undefined && !Object.keys(ov).length) {
    console.log(`! overlay ${overlayPath} vazio — ignorado, valem as chaves do kit`);
  } else if (ov !== undefined) {
    if (objeto(ov.$merge)) regras = somaRegras(regras, ov.$merge);
    delete ov.$merge;
    for (const [k, v] of Object.entries(ov)) {
      if (k !== 'hooks') { kit[k] = v; continue; }
      if (!objeto(v)) { console.log('! overlay: `hooks` não é um objeto — ignorado'); continue; }
      // Somar, não trocar: um `hooks` no overlay que substituísse o do kit apagaria todos os
      // hooks do kit na máquina. Grupo cujos comandos já estão no evento não entra de novo.
      kit.hooks = objeto(kit.hooks) ? kit.hooks : {};
      for (const [evento, grupos] of Object.entries(v)) {
        if (!Array.isArray(grupos)) continue;
        const atuais = Array.isArray(kit.hooks[evento]) ? kit.hooks[evento] : (kit.hooks[evento] = []);
        const vistos = new Set(atuais.flatMap((g) => (g && Array.isArray(g.hooks) ? g.hooks : [])).map((h) => h && h.command));
        for (const g of grupos) {
          const cmds = (g && Array.isArray(g.hooks) ? g.hooks : []).map((h) => h && h.command);
          if (cmds.length && cmds.every((c) => vistos.has(c))) continue;
          atuais.push(g);
          cmds.forEach((c) => vistos.add(c));
        }
      }
    }
  }
}
const mapa = (v) => (objeto(v) ? v : {});
const allowsRevogadosOverlay = mapa(regras.allowsRevogados);
const envDoKit = mapa(regras.envDoKit);
const chavesDoKit = mapa(regras.chavesDoKit);
const lista = (v) => (Array.isArray(v) ? v.filter((t) => typeof t === 'string' && t) : []);
const hooksRemovidos = lista(regras.hooksRemovidos);
const chavesGovernadas = lista(regras.chavesGovernadas);
const scriptsEntregues = lista(regras.scriptsEntregues);
const removerHooksAlheios = regras.removerHooksAlheios === true;
const modoDaPessoa = regras.modoDaPessoa === true;

// Env da máquina antes de qualquer mudança: o aviso do Remote Control fala do que ela tem.
const envOriginal = objeto(user.env) ? { ...user.env } : null;

const novas = [];
// Chaves dict com regra própria, abaixo. As outras seguem "a sua ganha": o kit só preenche.
const COM_REGRA = ['permissions', 'extraKnownMarketplaces', 'env', 'enabledPlugins', 'skillOverrides', 'modelSettings', 'hooks'];
for (const [k, v] of Object.entries(kit)) {
  if (COM_REGRA.includes(k) && objeto(v) && objeto(user[k])) continue;
  if (k === 'permissions' || k === 'extraKnownMarketplaces') continue;
  if (user[k] === undefined) { user[k] = v; novas.push(k); }
}

// env e enabledPlugins: união, o seu vence o empate. Enquanto o kit não define a chave, a
// sua sobrevive pela regra geral; no dia em que define, "o seu ganha no nível da chave"
// esconderia para sempre a variável ou o plugin novo de quem já tem a chave.
for (const k of ['env', 'enabledPlugins']) {
  if (!objeto(kit[k]) || !objeto(user[k])) continue;
  const acrescentar = Object.keys(kit[k]).filter((n) => !(n in user[k]));
  if (!acrescentar.length) continue;
  user[k] = { ...kit[k], ...user[k] };
  novas.push(`${k} (+${acrescentar.length})`);
}

// skillOverrides: o kit governa as chaves dele (é o kit dizendo como a skill dele carrega, e
// é o que deixa o kit mudar de ideia); a sua chave fica enquanto a skill existir. Só com
// --skills-dir o merge sabe onde procurar: skill de plugin mora no cache do plugin, fora de
// ~/.claude/skills, e descartar sem saber apagaria override legítimo.
if (objeto(kit.skillOverrides) && objeto(user.skillOverrides)) {
  const merged = { ...user.skillOverrides };
  const mudou = [];
  for (const [n, v] of Object.entries(kit.skillOverrides)) {
    if (merged[n] !== v) mudou.push(n);
    merged[n] = v;
  }
  const mortos = [];
  if (skillDirs.length) {
    for (const n of Object.keys(user.skillOverrides)) {
      if (n in kit.skillOverrides) continue;
      if (!skillDirs.some((d) => fs.existsSync(path.join(d, n)))) { mortos.push(n); delete merged[n]; }
    }
  }
  // Mesma ordem de chaves a cada passada, para a segunda não reescrever o arquivo.
  user.skillOverrides = merged;
  if (mudou.length) novas.push(`skillOverrides (${mudou.join(', ')})`);
  if (mortos.length) {
    console.log(`! ${mortos.length} override(s) de skill que não existe em nenhum dos diretórios de skill — descartado(s): ${mortos.sort().map((n) => `override morto: ${n}`).join(', ')}`);
  }
}

// modelSettings: é onde o /effort salva o padrão de cada modelo. O kit manda nas chaves dele
// dentro dos modelos que ele define; o modelo que o kit não cita, e a chave que só a máquina
// tem num modelo do kit (um maxEffortLevel), ficam.
if (objeto(kit.modelSettings) && objeto(user.modelSettings)) {
  const mudou = [];
  for (const [m, v] of Object.entries(kit.modelSettings)) {
    const atual = user.modelSettings[m];
    const novo = objeto(v) && objeto(atual) ? { ...atual, ...v } : v;
    if (JSON.stringify(novo) !== JSON.stringify(atual)) mudou.push(m);
    user.modelSettings[m] = novo;
  }
  if (mudou.length) novas.push(`modelSettings (${mudou.join(', ')})`);
}

// hooks: o kit acrescenta, por evento, o comando que a pessoa ainda não tem; nada dela sai.
if (objeto(kit.hooks) && objeto(user.hooks)) {
  let n = 0;
  for (const [evento, grupos] of Object.entries(kit.hooks)) {
    if (!Array.isArray(grupos)) continue;
    if (user.hooks[evento] !== undefined && !Array.isArray(user.hooks[evento])) continue;
    const atuais = user.hooks[evento] || [];
    const vistos = new Set(atuais.flatMap((g) => (g && Array.isArray(g.hooks) ? g.hooks : [])).map((h) => h && h.command));
    for (const g of grupos) {
      if (!g || !Array.isArray(g.hooks)) continue;
      const faltam = g.hooks.filter((h) => h && !vistos.has(h.command));
      if (!faltam.length) continue;
      atuais.push({ ...g, hooks: faltam });
      faltam.forEach((h) => vistos.add(h.command));
      n += faltam.length;
    }
    if (atuais.length) user.hooks[evento] = atuais;
  }
  if (n) novas.push(`hooks (+${n})`);
}

// chavesGovernadas: a chave escalar que o overlay declara governada volta ao valor do kit.
// Chave com regra própria (env, hooks, permissions…) segue a regra dela e não entra aqui; objeto
// sem regra (statusLine) é governado inteiro.
for (const k of chavesGovernadas) {
  if (!(k in kit) || COM_REGRA.includes(k)) continue;
  if (JSON.stringify(user[k]) === JSON.stringify(kit[k])) continue;
  const antes = user[k];
  user[k] = kit[k];
  if (antes !== undefined) novas.push(`${k} (${JSON.stringify(antes)} → ${JSON.stringify(kit[k])}, governada pelo kit)`);
}

// O que o kit de quem distribui o overlay gravou e tirou: sai só com o valor exato.
const tiradosDoKit = [];
if (objeto(user.env)) {
  for (const [k, v] of Object.entries(envDoKit)) {
    if (user.env[k] !== undefined && String(user.env[k]).trim() === String(v)) {
      delete user.env[k];
      tiradosDoKit.push(`env.${k}`);
    }
  }
  if (tiradosDoKit.length && !Object.keys(user.env).length) delete user.env;
}
for (const [k, v] of Object.entries(chavesDoKit)) {
  if (k in kit || user[k] === undefined) continue;
  if (JSON.stringify(user[k]) === JSON.stringify(v)) { delete user[k]; tiradosDoKit.push(k); }
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

// Até a 0.55.0 o template liberava estes allows, e com eles o Claude roda código que
// ele mesmo pode ter acabado de escrever, sem pergunta: `awk 'BEGIN{system(...)}'`, um
// `.ts` novo pelo `npx tsx`, o `package.json` editado e chamado pelo `npm run`. O modo
// Auto descarta sozinho as regras de "run" de gerenciador de pacote, mas devolve todas
// quando a pessoa sai dele (Accept edits, Manual), e a doc não garante que `awk` e
// `npx tsx` entrem nessa lista. Como o allow é união, tirar do template não tirava de ninguém que já
// tinha rodado o setup: sai aqui o texto exato que o kit gravou. Quem escreveu a mesma
// regra por conta própria perde junto — não dá pra distinguir —, e a saída diz como
// liberar o comando exato no projeto.
// O overlay soma a lista dele (allowsRevogados), com o substituto quando houver.
const ALLOWS_LEGADOS = ['Bash(awk:*)', 'Bash(npx tsx:*)', 'Bash(npm run:*)', 'PowerShell(npm run *)', 'PowerShell(npx tsx *)',
  ...Object.keys(allowsRevogadosOverlay)];
const allowsTirados = Array.isArray(user.permissions.allow)
  ? user.permissions.allow.filter((p) => ALLOWS_LEGADOS.includes(p))
  : [];
if (allowsTirados.length) user.permissions.allow = user.permissions.allow.filter((p) => !ALLOWS_LEGADOS.includes(p));
if (Array.isArray(kitPerms.allow)) kitPerms.allow = kitPerms.allow.filter((p) => !ALLOWS_LEGADOS.includes(p));

const allowAntes = [...(user.permissions.allow || [])];
const askAntes = new Set(user.permissions.ask || []);
for (const lista of ['allow', 'deny', 'ask']) {
  const meus = user.permissions[lista] || [];
  const vistos = new Set(meus);
  const acrescentar = (kitPerms[lista] || []).filter((p) => !vistos.has(p));
  if (acrescentar.length) novas.push(`permissions.${lista} (+${acrescentar.length})`);
  if (meus.length || acrescentar.length) user.permissions[lista] = [...meus, ...acrescentar];
}

// Modo de permissão (0.48.0; `auto` desde a 0.56.0). Manual (`default`) ou modo ausente
// vira o do kit (`auto`, o padrão do próprio Claude Code desde a v2.1.283): o kit não
// quer mentorado aprovando edição por edição, e no Auto quem revisa o comando é o
// classificador, não um allow largo. Sem Auto disponível na conta ou no modelo, o
// Claude Code abre em Manual. `acceptEdits` também vira `auto` (0.56.1, decisão do Ruan
// de 19/10/2026): foi o modo que o kit impôs da 0.48.0 à 0.55.0, e na 0.56.0 ele só
// ganhava um aviso, então o Auto não chegava a quase ninguém. Quem quer ficar no Accept
// edits cria ~/.claude/kit-vamoo/manter-accept-edits. O manter-modo-manual também segura:
// a promessa dele é "o setup não troca mais o seu modo". `bypassPermissions`, `plan` e
// `dontAsk` ficam calados. Os marcadores saem de dirname(userPath) para o teste nunca
// tocar o ~/.claude de verdade.
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
const MARCADOR_ACCEPT = path.join(path.dirname(userPath), 'kit-vamoo', 'manter-accept-edits');
const MODOS_MANTIDOS = ['auto', 'bypassPermissions', 'plan', 'dontAsk', 'acceptEdits'];
const meuModo = user.permissions.defaultMode;
const modoKit = kitPerms.defaultMode;
if (modoDaPessoa && meuModo) {
  // O overlay declarou o modo como postura de quem senta na cadeira: o da pessoa fica.
} else if (modoKit && meuModo !== modoKit && (meuModo === undefined || meuModo === 'default')) {
  if (fs.existsSync(MARCADOR)) {
    console.log(`  modo de permissão: mantive o manual porque existe ${MARCADOR}`);
  } else {
    user.permissions.defaultMode = modoKit;
    novas.push(`permissions.defaultMode (${meuModo || 'sem modo'} → ${modoKit})`);
    console.log(`  modo de permissão: ${meuModo === 'default' ? 'Manual ("default")' : 'sem modo definido'} → "${modoKit}" (Auto: um classificador revisa cada comando no lugar do "Permitir"; o que é destrutivo continua pedindo). Se o Auto não estiver disponível na sua conta ou no modelo, o Claude Code abre em Manual.`);
    console.log(`  pra voltar ao manual de vez: crie o arquivo ${MARCADOR} e ponha permissions.defaultMode em "default" no settings.json (sem o arquivo, o próximo setup troca de novo).`);
  }
} else if (meuModo === 'acceptEdits' && modoKit === 'auto') {
  const segura = [MARCADOR_ACCEPT, MARCADOR].find((m) => fs.existsSync(m));
  if (segura) {
    console.log(`  modo de permissão: mantive o "acceptEdits" (Accept edits) porque existe ${segura}`);
  } else {
    user.permissions.defaultMode = modoKit;
    novas.push(`permissions.defaultMode (acceptEdits → ${modoKit})`);
    console.log(`  modo de permissão: Accept edits ("acceptEdits") → "${modoKit}" (Auto: um classificador revisa cada comando, em vez de liberar sem pergunta o que está no allow; o que é destrutivo continua pedindo). Se o Auto não estiver disponível na sua conta ou no modelo, o Claude Code abre em Manual.`);
    console.log(`  pra voltar ao Accept edits de vez: crie o arquivo ${MARCADOR_ACCEPT} e ponha permissions.defaultMode em "acceptEdits" no settings.json (sem o arquivo, o próximo setup troca de novo).`);
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
// Tira de user.hooks todo comando que contém um dos trechos; evento que fica vazio sai.
const tirarHooks = (trechos) => {
  let n = 0;
  if (!objeto(user.hooks) || !trechos.length) return 0;
  for (const [evento, grupos] of Object.entries(user.hooks)) {
    if (!Array.isArray(grupos)) continue;
    let mexeu = false;
    const restantes = grupos.filter((g) => {
      if (!g || !Array.isArray(g.hooks)) return true;
      const antes = g.hooks.length;
      g.hooks = g.hooks.filter((h) => !(h && typeof h.command === 'string' && trechos.some((t) => h.command.includes(t))));
      if (g.hooks.length === antes) return true;
      n += antes - g.hooks.length;
      mexeu = true;
      return g.hooks.length > 0;
    });
    if (!mexeu) continue;
    if (restantes.length) user.hooks[evento] = restantes;
    else delete user.hooks[evento];
  }
  return n;
};
const legados = tirarHooks([DISPATCH_LEGADO]);
const doOverlay = tirarHooks(hooksRemovidos);

// removerHooksAlheios: o kit governa os hooks — o da pessoa que não está no kit (com o overlay
// já somado) sai. O aviso nomeia só o que de fato some da máquina: hook que o kit reescreveu,
// virou script ou passou a ser chamado por um dispatcher continua existindo de outra forma, e
// aviso que grita falso-positivo ensina a pular a saída inteira.
const comandos = (h) => (objeto(h) ? Object.values(h) : []).filter(Array.isArray).flat()
  .flatMap((g) => (g && Array.isArray(g.hooks) ? g.hooks : [])).map((x) => x && x.command).filter((c) => typeof c === 'string');
let alheiosAvisados = [];
let alheios = 0;
if (removerHooksAlheios && objeto(user.hooks)) {
  const kitCmds = new Set(comandos(kit.hooks));
  const assinatura = (c) => {
    const m = /([\w-]+)\.sh\b/.exec(c);
    if (m) return 'sh:' + m[1];
    const f = ['dotcontext', 'rtk', 'eslint', 'prettier', 'afplay', 'osascript'].find((t) => c.includes(t));
    return f || 'raw:' + c.split(/\s+/).filter(Boolean).join(' ');
  };
  const kitSigs = new Set([...kitCmds].map(assinatura));
  const kitScripts = new Set([...kitCmds].flatMap((c) => [...c.matchAll(/([\w-]+)\.sh\b/g)].map((m) => m[1])));
  const kitDir = path.dirname(path.resolve(kitPath));
  const reembrulhado = (c) => {
    const sig = assinatura(c);
    if (kitSigs.has(sig)) return true;
    if ([...kitScripts].some((n) => c.includes(n))) return true;
    if (sig.startsWith('sh:')) {
      const nome = sig.slice(3) + '.sh';
      if (['hooks', 'scripts'].some((d) => fs.existsSync(path.join(kitDir, d, nome)))) return true;
      if (scriptsEntregues.some((s) => path.basename(s) === nome)) return true;
    }
    if (!sig.startsWith('sh:') && !sig.startsWith('raw:') && [...kitScripts].some((n) => n.includes(sig))) return true;
    const nucleo = c.trim().replace(/&+\s*$/, '').trim();
    return !!nucleo && [...kitCmds].some((k) => k.includes(nucleo));
  };
  const fora = [...new Set(comandos(user.hooks).filter((c) => !kitCmds.has(c)))];
  alheiosAvisados = fora.filter((c) => !reembrulhado(c)).sort();
  if (fora.length) {
    const tirar = new Set(fora);
    for (const [evento, grupos] of Object.entries(user.hooks)) {
      if (!Array.isArray(grupos)) continue;
      const restantes = grupos.filter((g) => {
        if (!g || !Array.isArray(g.hooks)) return true;
        const antes = g.hooks.length;
        g.hooks = g.hooks.filter((h) => !(h && typeof h.command === 'string' && tirar.has(h.command)));
        alheios += antes - g.hooks.length;
        return g.hooks.length > 0 || antes === 0;
      });
      if (restantes.length) user.hooks[evento] = restantes;
      else delete user.hooks[evento];
    }
  }
}
if (alheiosAvisados.length) {
  console.log(`! ${alheiosAvisados.length} hook(s) do seu settings.json não estão no kit e foram REMOVIDOS:`);
  for (const c of alheiosAvisados) console.log(`    ${c.slice(0, 110)}`);
  console.log('  A cópia integral fica no backup de quem chamou o merge. Hook que precisa sobreviver tem que estar no settings.json do kit ou no overlay.');
}

// Avisos sobre o env que fica: o merge não tira variável da pessoa, então explica o efeito.
// Regra de cada var copiada da CLI (2.1.280, testado com `claude remote-control`): as duas
// primeiras bloqueiam com qualquer valor não vazio, "0" incluso; as outras só com valor verdadeiro.
if (envOriginal) {
  const val = (k) => (envOriginal[k] === undefined || envOriginal[k] === null ? '' : String(envOriginal[k]));
  const presentes = [
    ...['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC', 'DISABLE_TELEMETRY'].filter((k) => val(k) !== ''),
    ...['DO_NOT_TRACK', 'DISABLE_GROWTHBOOK'].filter((k) => ['1', 'true', 'yes', 'on'].includes(val(k).trim().toLowerCase())),
  ];
  if (presentes.length) {
    console.log(`! ${presentes.join(', ')} no seu env: o Remote Control fica desligado enquanto existir (DISABLE_TELEMETRY bloqueia até com valor 0).`);
    console.log('  Para usar o Remote Control, apague a chave do ~/.claude/settings.json; para manter a telemetria desligada, não faça nada. Confira com: claude doctor');
  }
}
// Na CLI a env de budget vence o skillListingBudgetFraction do kit e fixa o budget da lista de
// skills em qualquer janela de contexto.
if (kit.skillListingBudgetFraction !== undefined && objeto(user.env) && user.env.SLASH_COMMAND_TOOL_CHAR_BUDGET !== undefined) {
  console.log(`! SLASH_COMMAND_TOOL_CHAR_BUDGET=${user.env.SLASH_COMMAND_TOOL_CHAR_BUDGET} no seu env: ela anula o skillListingBudgetFraction do kit e fixa o budget da lista de skills em qualquer janela.`);
  console.log('  Para o budget acompanhar a janela, apague SLASH_COMMAND_TOOL_CHAR_BUDGET do ~/.claude/settings.json.');
}

fs.writeFileSync(userPath, JSON.stringify(user, null, 2) + '\n');
if (novas.length) console.log(`  acrescentado: ${novas.join(', ')}`);
if (legados) console.log(`  removido: hook antigo do dotcontext (${legados}) — o instalador de antes da 0.7.0 tinha gravado no seu settings.json`);
if (doOverlay) console.log(`  removido: hook listado no overlay (${doOverlay})`);
// tiradosDoKit sai calado, como no kit do time: é o próprio kit desfazendo o que gravou.
if (allowsTirados.length) {
  console.log(`  removido do allow: ${allowsTirados.join(', ')} — rodam código arbitrário sem pergunta, ou o kit gravou e tirou.`);
  for (const r of allowsTirados) {
    if (!(r in allowsRevogadosOverlay)) continue;
    const novo = allowsRevogadosOverlay[r];
    console.log(`  allow do kit antigo saiu: ${r} (${novo ? `agora ${novo}` : 'sem substituto: o comando volta a pedir aprovação'})`);
  }
  console.log('  projeto que precisa libera o comando exato no próprio .claude/settings.json (ex.: "Bash(npm run build)").');
}
if (!novas.length && !legados && !doOverlay && !alheios && !tiradosDoKit.length && !allowsTirados.length) console.log('  já estava tudo lá — nada mudou');
