#!/usr/bin/env node
// Statusline do Claude Code. Cross-platform (Mac + Windows/Git Bash). Dois modos:
//
//   painel (padrão)  até 7 linhas:
//     ⚠ banner de diretório perigoso (só quando aplicável)
//     👤quem Opus 5.5 (1M ctx) [xhigh] (branch +449 -63 ✗) projeto  🔀 #12 OPEN ✓  ◆ agent
//     Input:244.2k | Output:1.9k | Cache:242.7k | ⚡54 t/s
//     Sessão:2h27m | API:34m | Custo:$17.42 | $0.12/min
//     ctx ━━━━━╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ | 244.2k/24% | 755.8k/76% rest.
//     (sem context_window no payload, a linha vira `ses`, lida do transcript, com a mesma régua)
//     5h  ━━━━╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ | 19%        | 4h14m rest.
//     7d  ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ | 4%         | 3d03h rest.
//   curto            uma linha: diretório, branch, dirty, ahead/behind, gh e PR, ctx, t/s.
//
// O modo é configuração, não quem a pessoa é: $CLAUDE_STATUSLINE_MODO (por terminal) ou a
// primeira linha de ~/.claude/statusline-modo, que o setup grava. Sem nenhum dos dois, painel.
// O 👤 de quem está no teclado e o carimbo da sessão em ~/.claude/session-owners.jsonl só
// existem com $CLAUDE_WHO, ~/.claude/whoami ou ~/.claude/.team-manifest: é harness
// compartilhado por mais de uma pessoa, e sem isso o painel não grava nada além dos
// marcadores de sessão.
//
// O estado do GitHub é caro (rede): cada modo tem o seu cache com TTL, e quando ele vence este
// mesmo script se re-invoca em background para atualizá-lo. A barra pinta o último valor.
'use strict';
const { execSync, execFileSync, spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const HOME = os.homedir();
const CLAUDE = path.join(HOME, '.claude');

// ── compartilhado pelos dois modos ──

// Os últimos ~256 KB do transcript, que passa de 100 MB em sessão longa; "" se não der.
const lerRabo = (tp) => {
  if (!tp) return '';
  try {
    const fd = fs.openSync(tp, 'r');
    try {
      const size = fs.fstatSync(fd).size;
      const len = Math.min(size, 256 * 1024);
      const buf = Buffer.allocUnsafe(len);
      fs.readSync(fd, buf, 0, len, size - len);
      return buf.toString('utf8');
    } finally { fs.closeSync(fd); }
  } catch { return ''; }
};

// Contexto do último turno lido do transcript, como o hook session-size-guard mede: input +
// cache_read + cache_creation do último usage de assistente fora de sidechain. Com o advisor,
// o usage de cima soma as iterações; vale a última "message" ou "fallback_message". Usage
// zerado (<synthetic>) não é turno, e compact_boundary depois do último usage zera até o
// próximo. Contar linhas do transcript mandava /compact depois do /compact: o transcript só
// cresce. Só alimenta a `ses`, o fallback da `ctx` quando o payload não traz context_window.
const ctxDoTranscript = (rabo) => {
  const n = (v) => Number(v) || 0;
  let ctx = 0;
  for (const linha of rabo.split('\n')) {
    if (!linha.startsWith('{')) continue;
    let e;
    try { e = JSON.parse(linha); } catch { continue; }
    if (!e || typeof e !== 'object' || e.isSidechain === true) continue;
    if (e.type === 'system' && e.subtype === 'compact_boundary') { ctx = 0; continue; }
    if (e.type !== 'assistant') continue;
    let u = e.message && e.message.usage;
    if (!u || typeof u !== 'object') continue;
    if (Array.isArray(u.iterations)) {
      const it = u.iterations.filter((i) => i && (i.type === 'message' || i.type === 'fallback_message'));
      if (it.length) u = it[it.length - 1];
    }
    const t = n(u.input_tokens) + n(u.cache_read_input_tokens) + n(u.cache_creation_input_tokens);
    if (t > 0) ctx = t;
  }
  return ctx;
};

// Tokens/s de saída da ÚLTIMA chamada de API. O transcript não guarda duração por request;
// a conta é output_tokens ÷ (última linha da resposta − último evento `user` antes dela).
// Inclui o TTFT e o processamento do prompt: é a velocidade que o olho vê, não a do servidor.
// Cada resposta ocupa várias linhas com o mesmo message.id e o mesmo usage (uma por bloco), e
// com ferramenta rodando durante o streaming os tool_result se intercalam com essas linhas —
// por isso o fim é a ÚLTIMA linha do id, e o início é o `user` anterior à PRIMEIRA.
const tpsDoTranscript = (rabo) => {
  let ultimoUser = null, atual = null;
  for (const linha of rabo.split('\n')) {
    if (!linha.startsWith('{"')) continue;
    let e;
    try { e = JSON.parse(linha); } catch { continue; }
    if (e.isSidechain || !e.timestamp) continue;
    if (e.type === 'user') { ultimoUser = e.timestamp; continue; }
    const id = e.type === 'assistant' && e.message && e.message.id;
    if (!id) continue;
    const out = (e.message.usage && e.message.usage.output_tokens) || 0;
    if (atual && atual.id === id) { atual.fim = e.timestamp; if (out) atual.out = out; }
    else if (out > 0) atual = { id, out, inicio: ultimoUser, fim: e.timestamp };
  }
  if (!atual || !atual.inicio) return null;
  const fim = Date.parse(atual.fim);
  const ms = fim - Date.parse(atual.inicio);
  // <0,5s é resposta curta demais pra medir; parado há 5 min, o número já é velho
  if (!(ms > 500) || Date.now() - fim > 300_000) return null;
  return atual.out / (ms / 1000);
};

// Troca de modelo no meio da sessão. Com switchModelsOnFlag, mensagem sinalizada pelos
// safeguards troca o modelo (saindo do 5.5: claude-opus-4-8 em cyber, claude-opus-5 em bio)
// e o model.id do payload muda sem ninguém notar — no time, 2 sessões seguiram 36 e 18
// mensagens no 4.8. Um /model também acende, e tudo bem: quem trocou vê e segue. A marca
// guarda o primeiro model.id da sessão; devolve "de→para" quando mudou, "" quando não.
// "claude-opus-5-5[1m]" → "opus-5-5": o [1m] é a janela, não o modelo, e sozinho não é troca.
const curtoModelo = (m) => m.replace(/\[1m\]$/i, '').replace(/-\d{8}$/, '').replace(/^claude-/, '');
const trocaDeModelo = (dir, prefixo, sid, id) => {
  try {
    if (!id || !/^[\w-]+$/.test(sid)) return '';
    const marca = path.join(dir, prefixo + sid);
    let primeiro = '';
    try { primeiro = fs.readFileSync(marca, 'utf8').trim(); } catch {}
    if (!primeiro) {
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(marca, id);
      primeiro = id;
    }
    return curtoModelo(primeiro) !== curtoModelo(id) ? curtoModelo(primeiro) + '→' + curtoModelo(id) : '';
  } catch { return ''; }
};

const lerModo = () => {
  const env = (process.env.CLAUDE_STATUSLINE_MODO || '').trim();
  if (env === 'curto' || env === 'painel') return env;
  try {
    const f = fs.readFileSync(path.join(CLAUDE, 'statusline-modo'), 'utf8').split('\n')[0].trim();
    if (f === 'curto' || f === 'painel') return f;
  } catch {}
  return 'painel';
};

// ═════════════════════════ MODO CURTO ═════════════════════════
// O estado do GitHub (gh conectado + PR aberto) fica em cache no tmpdir, por diretório.
const CURTO_TTL_MS = 90_000; // PR/auth: revalida a cada 90s
const CURTO_LOCK_MS = 15_000; // evita tempestade de refreshs enquanto um está em curso

const refreshCurto = () => {
  const cwd = process.env.CLAUDE_SL_CWD || process.cwd();
  const branch = process.env.CLAUDE_SL_BRANCH || '';
  const cacheFile = process.env.CLAUDE_SL_CACHE;
  const lockFile = cacheFile + '.lock';
  const out = { ts: Date.now(), branch, auth: false, pr: null };
  // execFileSync (argv separado), NÃO execSync com string: `branch` vem do git e nome de
  // branch aceita metacaractere de shell — `x$(touch${IFS}/tmp/x)` é ref válida no git e
  // executava aqui. Dar checkout numa branch vinda de PR de terceiro bastava pra rodar
  // comando arbitrário na máquina de quem instalou o kit.
  const gh = (args) => execFileSync('gh', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 8000 }).trim();
  try {
    execFileSync('gh', ['auth', 'status'], { encoding: 'utf8', stdio: 'ignore', timeout: 8000 });
    out.auth = true;
    if (branch && branch !== 'main' && branch !== 'master') {
      // número do PR aberto pra essa branch (vazio = sem PR)
      const n = gh(['pr', 'list', '--head', branch, '--state', 'open', '--json', 'number', '--jq', '.[0].number // empty']);
      out.pr = n ? String(n).trim() : 'none';
    }
  } catch { /* não autenticado / gh ausente → auth:false */ }
  try { fs.writeFileSync(cacheFile, JSON.stringify(out)); } catch {}
  try { fs.unlinkSync(lockFile); } catch {}
};

const renderCurto = (input) => {
  const C = { cyan: '\x1b[36m', blue: '\x1b[34m', green: '\x1b[32m', yellow: '\x1b[33m', orange: '\x1b[38;5;208m', red: '\x1b[31m', bold: '\x1b[1m', dim: '\x1b[90m', reset: '\x1b[0m' };
  const cwd = (input.workspace && input.workspace.current_dir) || process.cwd();
  const currentDir = path.basename(cwd) || cwd;

  const git = (args) => {
    try { return execSync('git --no-optional-locks ' + args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); }
    catch { return ''; }
  };

  // branch + dirty
  const branch = git('branch --show-current');
  let gitSeg = '';
  let aheadBehind = '';
  if (branch) {
    const dirty = git('status --porcelain') ? '✗' : '';
    gitSeg = ` ${C.blue}git:(${branch})${dirty}${C.reset}`;
    // ahead/behind vs upstream — "behind<TAB>ahead"
    const lr = git('rev-list --left-right --count @{upstream}...HEAD');
    if (lr) {
      const parts = lr.split(/\s+/);
      const behind = parseInt(parts[0], 10) || 0;
      const ahead = parseInt(parts[1], 10) || 0;
      let ab = '';
      if (ahead) ab += `${C.green}↑${ahead}${C.reset}`;
      if (behind) ab += `${C.yellow}↓${behind}${C.reset}`;
      if (ab) aheadBehind = ' ' + ab;
    }
  }

  // GitHub (cacheado): gh conectado? + PR aberto?
  let ghSeg = '';
  if (branch) {
    const key = crypto.createHash('md5').update(cwd).digest('hex').slice(0, 10);
    const cacheFile = path.join(os.tmpdir(), `claude-sl-gh-${key}.json`);
    const lockFile = cacheFile + '.lock';
    let cache = null;
    try { cache = JSON.parse(fs.readFileSync(cacheFile, 'utf8')); } catch {}
    const now = Date.now();
    const fresh = cache && cache.branch === branch && (now - cache.ts < CURTO_TTL_MS);

    if (!fresh) {
      // dispara refresh em background, com trava anti-tempestade
      let locked = false;
      try { locked = (now - fs.statSync(lockFile).mtimeMs) < CURTO_LOCK_MS; } catch {}
      if (!locked) {
        try {
          fs.writeFileSync(lockFile, '');
          const child = spawn(process.execPath, [__filename], {
            detached: true, stdio: 'ignore', windowsHide: true, // windowsHide: sem flash de console no Windows
            env: { ...process.env, CLAUDE_SL_REFRESH: '1', CLAUDE_SL_CWD: cwd, CLAUDE_SL_BRANCH: branch, CLAUDE_SL_CACHE: cacheFile },
          });
          child.unref();
        } catch {}
      }
    }
    // pinta o último valor conhecido (mesmo que velho); vazio no 1º uso até o refresh escrever
    if (cache) {
      ghSeg += cache.auth ? ` ${C.green}gh✓${C.reset}` : ` ${C.red}gh✗${C.reset}`;
      if (cache.auth && branch !== 'main' && branch !== 'master') {
        if (cache.pr && cache.pr !== 'none') ghSeg += ` ${C.green}PR#${cache.pr}${C.reset}`;
        else if (cache.pr === 'none') ghSeg += ` ${C.dim}no-PR${C.reset}`;
      }
    }
  }

  // Contexto em número ABSOLUTO, não em % da janela. Numa janela de 1M, 500k de contexto
  // pinta "50%" e parece saudável, quando é meio milhão de tokens relidos a cada comando.
  // Uma linha só de contexto: a `ctx:`, do payload do harness; a `ses:`, do transcript, só
  // quando o payload não traz context_window. Régua: verde, amarelo em 150k, vermelho com
  // /compact em 300k.
  const temPayload = !!input.context_window;
  const segCtx = (rotulo, tok) => {
    const col = tok < 150_000 ? C.green : tok < 300_000 ? C.yellow : C.red;
    const dica = tok >= 300_000 ? ' /compact' : '';
    return ` ${C.dim}·${C.reset} ${col}${rotulo}:${Math.floor(tok / 1000)}k${dica}${C.reset}`;
  };
  let ctxSeg = '';
  const usage = (temPayload && input.context_window.current_usage) || {};
  const totalInput = (usage.input_tokens || 0) + (usage.cache_creation_input_tokens || 0) + (usage.cache_read_input_tokens || 0);
  if (totalInput > 0) ctxSeg = segCtx('ctx', totalInput);

  const rabo = lerRabo(input.transcript_path);
  if (!temPayload) {
    const ctx = ctxDoTranscript(rabo);
    if (ctx > 0) ctxSeg = segCtx('ses', ctx);
  }

  let tpsSeg = '';
  const tps = rabo ? tpsDoTranscript(rabo) : null;
  if (tps) {
    const col = tps >= 40 ? C.green : tps >= 20 ? C.yellow : C.orange;
    tpsSeg = ` ${C.dim}·${C.reset} ${col}⚡${Math.round(tps)} t/s${C.reset}`;
  }

  // A linha não tem segmento de modelo: aparece só o desvio. O primeiro model.id fica no
  // tmpdir, como o cache do gh — some sozinho, e sessão retomada depois de reboot só perde o aviso.
  const troca = trocaDeModelo(os.tmpdir(), 'claude-sl-model-', String(input.session_id || ''), String((input.model && input.model.id) || ''));
  const modeloSeg = troca ? ` ${C.bold}${C.red}⚠ modelo trocou: ${troca}${C.reset}` : '';

  process.stdout.write(`${C.cyan}${currentDir}${C.reset}${modeloSeg}${gitSeg}${aheadBehind}${ghSeg}${ctxSeg}${tpsSeg}`);
};

// ═════════════════════════ MODO PAINEL ═════════════════════════
const PR_CACHE = path.join(CLAUDE, 'statusline-pr-cache.json');
const PR_TTL_MS = 120_000; // 2 min: cache fresco não refaz o gh
const GIT_TIMEOUT = 800;
const BAR_W = 20;
const WHO_FILE = path.join(CLAUDE, 'whoami');
const OWNERS_LOG = path.join(CLAUDE, 'session-owners.jsonl');
const OWNER_MARKS = path.join(CLAUDE, '.cache', 'session-owner');
const MODEL_MARKS = path.join(CLAUDE, '.cache', 'session-model');

const C = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  red: '\x1b[91m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  cyan: '\x1b[36m',
  white: '\x1b[97m',
  magenta: '\x1b[35m',
  blue: '\x1b[94m',
  orange: '\x1b[38;5;208m',
};

const sh = (cmd, cwd) => {
  try {
    return execSync(cmd, { cwd, encoding: 'utf8', timeout: GIT_TIMEOUT, stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
};
const readPrCache = () => {
  try {
    return JSON.parse(fs.readFileSync(PR_CACHE, 'utf8'));
  } catch {
    return {};
  }
};
// repo "owner/name" a partir do remote origin
const repoSlug = (cwd) => {
  const url = sh('git config --get remote.origin.url', cwd);
  if (!url) return '';
  const m = url.match(/[:/]([^/:]+\/[^/]+?)(?:\.git)?$/);
  return m ? m[1] : '';
};

const refreshPainel = (cwd) => {
  const branch = sh('git branch --show-current', cwd);
  const slug = repoSlug(cwd);
  if (!branch || !slug) return;
  const key = slug + '#' + branch;
  const cache = readPrCache();
  const entry = { ts: Date.now(), pr: null };
  try {
    // execFileSync (argv separado), NÃO execSync: o nome de branch aceita metacaractere de
    // shell (ver o refresh do modo curto).
    const raw = execFileSync(
      'gh',
      ['pr', 'view', branch, '--json', 'number,state,reviewDecision,statusCheckRollup'],
      { cwd, encoding: 'utf8', timeout: 6000, stdio: ['ignore', 'pipe', 'ignore'] },
    ).trim();
    if (raw) {
      const d = JSON.parse(raw);
      let passed = 0, failed = 0, pending = 0;
      for (const c of d.statusCheckRollup || []) {
        const st = (c.conclusion || c.status || '').toUpperCase();
        if (['SUCCESS', 'NEUTRAL', 'SKIPPED'].includes(st)) passed++;
        else if (['FAILURE', 'ERROR', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED'].includes(st)) failed++;
        else pending++;
      }
      entry.pr = { number: d.number, state: d.state, review: d.reviewDecision || null, passed, failed, pending };
    }
  } catch {
    entry.pr = null; // sem PR pra essa branch — negative cache evita re-hammer
  }
  cache[key] = entry;
  try {
    fs.writeFileSync(PR_CACHE, JSON.stringify(cache));
  } catch {}
};

// ---------- quem está no teclado ----------
// Harness de mais de uma pessoa no mesmo login: a sessão diz de quem ela é. Cascata, do mais
// específico pro mais genérico: $CLAUDE_WHO (por terminal: duas pessoas na MESMA máquina),
// ~/.claude/whoami (por máquina) e, só com o .team-manifest, o hostname. Sem nenhum deles a
// máquina é de uma pessoa só: sem 👤 e sem carimbo.
const trunc0 = (x) => (x.length > 14 ? x.slice(0, 13) + '…' : x);
const host = () => os.hostname().replace(/\.local$/i, '').split('.')[0];
const lerQuem = () => {
  const env = (process.env.CLAUDE_WHO || '').trim();
  if (env) return trunc0(env);
  try {
    const f = fs.readFileSync(WHO_FILE, 'utf8').split('\n')[0].trim();
    if (f) return trunc0(f);
  } catch {}
  if (fs.existsSync(path.join(CLAUDE, '.team-manifest'))) return trunc0(host());
  return '';
};

// Carimba sessão→pessoa UMA vez (o marcador em .cache evita reescrever a cada render). É isso
// que deixa um relatório de uso dizer, depois, de quem era cada sessão.
const stampOwner = (who, sid, transcript, cwd) => {
  if (!who || !sid || !/^[\w-]+$/.test(sid)) return;
  try {
    const mark = path.join(OWNER_MARKS, sid);
    // o marcador guarda o nome: se a identidade mudar no meio (criou o whoami, exportou
    // CLAUDE_WHO), recarimba em vez de congelar o fallback de hostname
    if (fs.existsSync(mark) && fs.readFileSync(mark, 'utf8').trim() === who) return;
    fs.mkdirSync(OWNER_MARKS, { recursive: true });
    fs.appendFileSync(
      OWNERS_LOG,
      JSON.stringify({
        ts: new Date().toISOString(),
        who,
        host: host(),
        user: os.userInfo().username,
        session: sid,
        transcript: transcript || null,
        cwd,
      }) + '\n',
    );
    fs.writeFileSync(mark, who);
  } catch {}
};

// ---------- helpers de formatação ----------
const fmtK = (n) => {
  // 999_950+: (n/1000).toFixed(1) arredondaria pra "1000.0k" — já cai no branch de M
  if (n >= 999_950) return (n / 1_000_000).toFixed(1).replace(/\.0$/, '') + 'M';
  if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
  return String(Math.floor(n));
};
const fmtDur = (ms) => {
  const m = Math.floor(ms / 60000);
  if (m >= 60) return Math.floor(m / 60) + 'h' + String(m % 60).padStart(2, '0') + 'm';
  if (m > 0) return m + 'm';
  return Math.floor(ms / 1000) + 's';
};
const fmtCost = (usd) => '$' + (usd || 0).toFixed(2);
const trunc = (s, max = 24) => (s.length > max ? s.slice(0, max - 1) + '…' : s);
// largura visível aproximada (strip ANSI; emojis usados aqui têm length 2 ≈ 2 células)
const visW = (s) => s.replace(/\x1b\[[0-9;]*m/g, '').length;
// Nível do ctx pelo que é relido a cada request, em tokens, e não pela fração da janela:
// numa de 1M, 55% são 550k relidos a cada passo. Os limiares absolutos são os do modo curto.
// A % continua de teto onde a janela acaba antes: numa de 200k (Haiku) 300k nem cabe, e o
// auto-compact dispara antes. Vale o que acender primeiro.
const CTX_AMARELO = 150_000;
const CTX_VERMELHO = 300_000;
const CTX_CORES = [C.green, C.yellow, C.orange, C.bold + C.red];
const ctxLevel = (tokens, pct) =>
  tokens >= CTX_VERMELHO || pct >= 80 ? 3 : pct >= 70 ? 2 : tokens >= CTX_AMARELO || pct >= 55 ? 1 : 0;
const usageColor = (pct) => (pct >= 90 ? C.bold + C.red : pct >= 75 ? C.orange : pct >= 50 ? C.yellow : C.white);
const effortColor = (l) =>
  l === 'max' ? C.bold + C.red : l === 'xhigh' ? C.orange : l === 'high' ? C.yellow : l === 'medium' ? C.white : C.dim;
// epoch (segundos) -> "4h14m" / "3d03h" / "12m" ("0m" se já passou)
const fmtReset = (epochSec) => {
  if (!epochSec) return '';
  const diff = epochSec * 1000 - Date.now();
  if (diff <= 0) return '0m';
  const m = Math.floor(diff / 60000);
  if (m >= 1440) return Math.floor(m / 1440) + 'd' + String(Math.floor((m % 1440) / 60)).padStart(2, '0') + 'h';
  if (m >= 60) return Math.floor(m / 60) + 'h' + String(m % 60).padStart(2, '0') + 'm';
  return m + 'm';
};

const renderPainel = (d) => {
  const cwd = (d.workspace && d.workspace.current_dir) || d.cwd || process.cwd();
  const projectDir = path.basename((d.workspace && d.workspace.project_dir) || cwd);
  const SEP = C.dim + ' | ' + C.reset;
  const who = lerQuem();
  stampOwner(who, d.session_id, d.transcript_path, cwd);

  // ---------- linha 1: 👤 modelo (ctx) [effort·sem-thinking·fast] ⚠troca (branch +add -rem ✗) projeto PR agent ----------
  const model = (d.model && (d.model.display_name || d.model.id)) || 'Claude';
  const modelId = (d.model && d.model.id) || '';
  const cw = d.context_window || {};
  const ctxSize = cw.context_window_size || 200000;
  const ctxNote = ctxSize !== 200000 ? ' ' + C.dim + '(' + fmtK(ctxSize) + ' ctx)' + C.reset : '';
  const modelPart = C.bold + C.white + model + C.reset + ctxNote;
  // cor estável derivada do nome: a mesma pessoa pinta sempre igual, pessoas diferentes destoam
  const whoPart = who
    ? [C.cyan, C.magenta, C.green, C.yellow, C.blue, C.orange][[...who].reduce((a, ch) => (a + ch.charCodeAt(0)) % 6, 0)] +
      '👤' + who + C.reset
    : '';

  const tags = [];
  if (d.effort && d.effort.level) tags.push(effortColor(d.effort.level) + d.effort.level + C.reset);
  // `thinking.enabled` é o toggle "Thinking mode", não o que o modelo faz: no Opus 5.5 e no
  // Fable 5 o CLI nem manda o thinking desligado (rejects_disabled_thinking, 2.1.280), e uma tag
  // "thinking" ficaria sempre acesa sem dizer nada. Só o desvio aparece: toggle desligado num
  // modelo que obedece a ele.
  // atalho: lista fixa de quem ignora o toggle; revisar quando sair modelo novo (o CLI trata todo modelo fora da lista antiga como "não desliga")
  if (d.thinking && d.thinking.enabled === false && !/opus-5-5|fable-5/.test(modelId)) tags.push(C.dim + 'sem-thinking' + C.reset);
  if (d.fast_mode === true) tags.push(C.yellow + 'fast' + C.reset);
  const tagPart = tags.length
    ? C.dim + '[' + C.reset + tags.join(C.dim + '·' + C.reset) + C.dim + ']' + C.reset
    : '';
  const troca = trocaDeModelo(MODEL_MARKS, '', String(d.session_id || ''), modelId);
  const switchPart = troca ? C.bold + C.red + '⚠ modelo trocou: ' + troca + C.reset : '';

  // -- git / worktree: (branch +adicionadas -removidas ✗) com linhas da SESSÃO --
  const wt = d.worktree;
  const branch = sh('git branch --show-current', cwd);
  const dirty = branch || (wt && wt.name) ? sh('git --no-optional-locks status --porcelain', cwd) : '';
  const dirtyMark = dirty ? ' ' + C.red + '✗' + C.reset : '';
  const linesAdd = (d.cost && d.cost.total_lines_added) || 0;
  const linesRem = (d.cost && d.cost.total_lines_removed) || 0;
  const linesInner =
    linesAdd || linesRem ? C.green + '+' + linesAdd + C.reset + ' ' + C.red + '-' + linesRem + C.reset : '';
  const linesPart = linesInner ? ' ' + linesInner : '';

  let gitPart = '';
  if (wt && wt.name) {
    const base = wt.original_branch
      ? ' ' + C.dim + '←' + C.reset + ' ' + C.white + trunc(wt.original_branch) + C.reset
      : '';
    gitPart =
      C.dim + '(' + C.reset + C.bold + C.blue + 'WT:' + trunc(wt.name) + C.reset +
      (wt.branch ? ' ' + C.magenta + trunc(wt.branch) + C.reset : '') + base + linesPart + dirtyMark +
      C.dim + ')' + C.reset;
  } else if (branch) {
    gitPart = C.dim + '(' + C.reset + C.magenta + trunc(branch) + C.reset + linesPart + dirtyMark + C.dim + ')' + C.reset;
  } else if (linesInner) {
    // fora de repo git as linhas da sessão ainda importam
    gitPart = C.dim + '(' + C.reset + linesInner + C.dim + ')' + C.reset;
  }

  // -- agente ativo (subagent) --
  const agentPart = d.agent && d.agent.name ? C.yellow + '◆ ' + d.agent.name + C.reset : '';

  // -- PR (do cache; refresh disparado em background) --
  let prPart = '';
  if (branch) {
    const slug = repoSlug(cwd);
    if (slug) {
      const cache = readPrCache();
      const entry = cache[slug + '#' + branch];
      const stale = !entry || Date.now() - (entry.ts || 0) > PR_TTL_MS;
      if (stale) {
        // marca o cache ANTES do spawn (preservando o pr antigo): sem isso, cada render
        // dos ~300ms dentro da janela do `gh` (até 6s) dispararia um refresh concorrente
        cache[slug + '#' + branch] = { ts: Date.now(), pr: (entry && entry.pr) || null };
        try {
          fs.writeFileSync(PR_CACHE, JSON.stringify(cache));
        } catch {}
        try {
          const child = spawn(process.execPath, [__filename, '--refresh-pr', cwd], {
            detached: true, stdio: 'ignore', windowsHide: true, // windowsHide: sem flash de console no Windows
          });
          child.unref();
        } catch {}
      }
      if (entry && entry.pr) {
        const p = entry.pr;
        const stateC = p.state === 'MERGED' ? C.magenta : p.state === 'CLOSED' ? C.red : C.green;
        const checks =
          p.failed > 0
            ? C.red + '✗' + p.failed + C.reset
            : p.pending > 0
              ? C.yellow + '•' + p.pending + C.reset
              : p.passed > 0
                ? C.green + '✓' + C.reset
                : '';
        prPart = '🔀 ' + stateC + '#' + p.number + ' ' + p.state + C.reset + (checks ? ' ' + checks : '');
      }
    }
  }

  // estourou o orçamento de ~100 células? derruba segmentos por prioridade: projeto, depois agent
  // (o aviso de troca de modelo nunca cai)
  const l1segs = (drop) =>
    [whoPart, modelPart, tagPart, switchPart, gitPart, drop < 1 && C.dim + projectDir + C.reset, prPart, drop < 2 && agentPart]
      .filter(Boolean)
      .join(' ');
  let line1 = l1segs(0);
  for (let drop = 1; drop <= 2 && visW(line1) > 100; drop++) line1 = l1segs(drop);

  // ---------- linha 2: Input | Output | Cache | t/s (última chamada de API) ----------
  const cu = cw.current_usage || {};
  const cacheRead = cu.cache_read_input_tokens || 0;
  const ctxTokens =
    cw.total_input_tokens != null ? cw.total_input_tokens : (cu.input_tokens || 0) + (cu.cache_creation_input_tokens || 0) + cacheRead;
  const rabo = lerRabo(d.transcript_path);
  const tps = rabo ? tpsDoTranscript(rabo) : null;
  const tpsPart = tps
    ? (tps >= 40 ? C.green : tps >= 20 ? C.yellow : C.orange) + '⚡' + Math.round(tps) + ' t/s' + C.reset
    : '';
  const line2 = d.context_window
    ? [
        C.dim + 'Input:' + C.reset + C.white + fmtK(ctxTokens) + C.reset,
        C.dim + 'Output:' + C.reset + C.white + fmtK(cu.output_tokens || 0) + C.reset,
        C.dim + 'Cache:' + C.reset + C.magenta + fmtK(cacheRead) + C.reset,
        tpsPart,
      ]
        .filter(Boolean)
        .join(SEP)
    : '';

  // ---------- linha 3: Sessão | API | Custo | $/min ----------
  const cost = (d.cost && d.cost.total_cost_usd) || 0;
  const durMs = (d.cost && d.cost.total_duration_ms) || 0;
  const apiMs = (d.cost && d.cost.total_api_duration_ms) || 0;
  const costC = cost >= 10 ? C.bold + C.red : cost >= 5 ? C.orange : cost >= 2 ? C.yellow : C.green;
  const burn = durMs > 60000 ? cost / (durMs / 60000) : 0; // ignora o primeiro ~1min (ruído)
  const burnC = burn >= 2 ? C.bold + C.red : burn >= 1 ? C.orange : burn >= 0.5 ? C.yellow : C.dim;
  const burnPart = burn > 0 ? burnC + (burn >= 1 ? '🔥 ' : '') + '$' + burn.toFixed(2) + '/min' + C.reset : '';
  const line3 = d.cost
    ? [
        C.dim + 'Sessão:' + C.reset + C.cyan + fmtDur(durMs) + C.reset,
        C.dim + 'API:' + C.reset + C.cyan + fmtDur(apiMs) + C.reset,
        C.dim + 'Custo:' + C.reset + costC + fmtCost(cost) + C.reset,
        burnPart,
      ]
        .filter(Boolean)
        .join(SEP)
    : '';

  // ---------- barras: ctx (ou ses) / 5h / 7d (colunas alinhadas) ----------
  // Uma linha só para o contexto: a `ctx`, do payload do harness. A `ses` (lida do transcript)
  // só entra quando o payload não traz context_window, com a mesma régua.
  const rows = [];
  // o recado segue o nível: em 1M o (/compact) chega com o vermelho dos 300k, não nos 80%
  const ctxWarn = (level) =>
    level === 3 ? ' ' + CTX_CORES[3] + '(/compact)' + C.reset : level === 2 ? ' ' + CTX_CORES[2] + '(iminente)' + C.reset : '';
  if (d.context_window) {
    const pct = Math.floor(cw.used_percentage != null ? cw.used_percentage : ctxSize ? (ctxTokens * 100) / ctxSize : 0);
    const remPct = Math.floor(cw.remaining_percentage != null ? cw.remaining_percentage : 100 - pct);
    const remaining = Math.max(0, ctxSize - ctxTokens);
    const level = ctxLevel(ctxTokens, pct);
    rows.push({
      label: 'ctx',
      pct,
      color: CTX_CORES[level],
      b: fmtK(ctxTokens) + '/' + pct + '%',
      c: fmtK(remaining) + '/' + remPct + '% rest.',
      warn: ctxWarn(level),
    });
  } else {
    // Sem payload a janela é desconhecida: só os limiares absolutos (a % entra como 0), e a
    // barra enche até os 300k do /compact, não até um tamanho de janela chutado.
    const sCtx = ctxDoTranscript(rabo);
    if (sCtx > 0) {
      const level = ctxLevel(sCtx, 0);
      rows.push({
        label: 'ses',
        pct: Math.min(100, Math.round((sCtx * 100) / CTX_VERMELHO)),
        color: CTX_CORES[level],
        b: fmtK(sCtx) + ' tok',
        c: '',
        warn: ctxWarn(level),
      });
    }
  }
  const rl = d.rate_limits || {};
  for (const [label, w] of [['5h', rl.five_hour], ['7d', rl.seven_day]]) {
    if (!w || w.used_percentage == null) continue;
    const p = Math.floor(w.used_percentage);
    const reset = fmtReset(w.resets_at);
    rows.push({ label, pct: p, color: usageColor(p), b: p + '%', c: reset ? reset + ' rest.' : '', warn: '' });
  }
  const bW = rows.length ? Math.max(...rows.map((r) => r.b.length)) : 0;
  const barLines = rows.map((r) => {
    const f = Math.round((Math.min(100, Math.max(0, r.pct)) * BAR_W) / 100);
    const bar = r.color + '━'.repeat(f) + C.reset + C.dim + '╌'.repeat(BAR_W - f) + C.reset;
    return (
      C.dim + r.label.padEnd(4) + C.reset + bar + SEP +
      r.color + r.b.padEnd(bW) + C.reset +
      (r.c ? SEP + C.dim + r.c + C.reset : '') + r.warn
    );
  });

  // ---------- banner de diretório perigoso ----------
  // Sessão fora de projeto é engano: busca e Explore varrem a home inteira, e o
  // ~/.claude/settings.local.json vira o settings local dela. Também cobre "/" e ~/.claude
  // (mexer no harness).
  const realCwd = path.resolve(cwd);
  let danger = '';
  if (realCwd === HOME) danger = '⚠ SESSÃO NA HOME — fora de projeto, a busca varre a home inteira. Saia p/ um projeto.';
  else if (realCwd === '/') danger = '⚠ SESSÃO EM / (raiz do disco).';
  else if (realCwd === CLAUDE) danger = '⚠ SESSÃO EM ~/.claude — mexendo no harness.';
  const bannerPart = danger ? C.bold + C.red + danger + C.reset : '';

  process.stdout.write([bannerPart, line1, line2, line3, ...barLines].filter(Boolean).join('\n'));
};

// ═════════════════════════ entrada ═════════════════════════
if (process.env.CLAUDE_SL_REFRESH === '1') {
  refreshCurto();
} else if (process.argv[2] === '--refresh-pr') {
  refreshPainel(process.argv[3] || process.cwd());
} else {
  let input = {};
  try { input = JSON.parse(fs.readFileSync(0, 'utf8') || '{}'); } catch {}
  if (!input || typeof input !== 'object') input = {};
  try {
    if (lerModo() === 'curto') renderCurto(input);
    else renderPainel(input);
  } catch {
    process.stdout.write('[statusline]');
  }
}
