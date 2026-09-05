#!/usr/bin/env node
// Statusline do Claude Code — mostra diretório, branch, dirty, ahead/behind,
// conexão com GitHub e PR aberto pra branch atual. Cross-platform (Mac + Windows/Git Bash).
//
// O estado local (branch/dirty/ahead-behind) é lido na hora (barato).
// O estado do GitHub (gh conectado + PR aberto) é CARO (chamada de rede), então é
// cacheado em arquivo com TTL. Quando o cache vence, este mesmo script se re-invoca
// em BACKGROUND (modo refresh) pra atualizar o cache sem travar a barra — a barra
// sempre pinta o último valor conhecido na hora.
'use strict';
const { execSync, execFileSync, spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const CACHE_TTL_MS = 90_000; // PR/auth: revalida a cada 90s
const LOCK_TTL_MS = 15_000;  // evita tempestade de refreshs enquanto um está em curso

// ── Modo REFRESH (rodando em background): atualiza o cache do GitHub e sai ──
if (process.env.CLAUDE_SL_REFRESH === '1') {
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
  process.exit(0);
}

// ── Modo NORMAL: pinta a barra ──
let input = {};
try { input = JSON.parse(fs.readFileSync(0, 'utf8') || '{}'); } catch {}

const C = { cyan: '\x1b[36m', blue: '\x1b[34m', green: '\x1b[32m', yellow: '\x1b[33m', red: '\x1b[31m', dim: '\x1b[90m', reset: '\x1b[0m' };
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
let hasUpstream = false;
if (branch) {
  const dirty = git('status --porcelain') ? '✗' : '';
  gitSeg = ` ${C.blue}git:(${branch})${dirty}${C.reset}`;
  // ahead/behind vs upstream — "behind<TAB>ahead"
  const lr = git('rev-list --left-right --count @{upstream}...HEAD');
  if (lr) {
    hasUpstream = true;
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
  const fresh = cache && cache.branch === branch && (now - cache.ts < CACHE_TTL_MS);

  if (!fresh) {
    // dispara refresh em background, com trava anti-tempestade
    let locked = false;
    try { locked = (now - fs.statSync(lockFile).mtimeMs) < LOCK_TTL_MS; } catch {}
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

// Contexto em número ABSOLUTO, não em % da janela.
// Numa janela de 1M, 500k de contexto pinta "50%" e parece saudável — quando na
// verdade é meio milhão de tokens sendo relidos a cada comando. O que dói é o
// valor absoluto: é ele que multiplica por request numa sessão longa.
// Passou de 150k, considere /clear ou /compact.
let ctxSeg = '';
const usage = (input.context_window && input.context_window.current_usage) || {};
const totalInput = (usage.input_tokens || 0) + (usage.cache_creation_input_tokens || 0) + (usage.cache_read_input_tokens || 0);
if (totalInput > 0) {
  const col = totalInput < 150_000 ? C.green : totalInput < 300_000 ? C.yellow : C.red;
  ctxSeg = ` ${C.dim}·${C.reset} ${col}ctx:${Math.round(totalInput / 1000)}k${C.reset}`;
}

// Comprimento da SESSÃO em linhas de transcript — outra medida que o ctx. A janela
// compacta e volta a encher; o transcript só cresce, e é ele que dita o quanto é relido a
// cada comando: no time, as sessões com 100+ requests fizeram 96,6% do cache read de uma
// semana. O hook session-size-guard avisa uma vez por faixa e o aviso rola para fora da
// tela; aqui o número fica. Conta bytes \n em blocos, sem carregar o arquivo (transcript de
// sessão longa passa de 100 MB e isto roda a cada turno).
let sesSeg = '';
try {
  const tp = input.transcript_path;
  if (tp) {
    const fd = fs.openSync(tp, 'r');
    try {
      const buf = Buffer.allocUnsafe(1 << 16);
      let linhas = 0, n;
      while ((n = fs.readSync(fd, buf, 0, buf.length, null)) > 0) {
        for (let i = 0; i < n; i++) if (buf[i] === 10) linhas++;
      }
      if (linhas >= 600) {
        const col = linhas >= 2000 ? C.red : linhas >= 1200 ? C.yellow : C.dim;
        // 2.000+ é a faixa das maratonas: nem adianta compactar, o barato é sessão nova.
        const dica = linhas >= 2000 ? ' maratona' : linhas >= 1200 ? ' /compact' : ' /clear?';
        sesSeg = ` ${C.dim}·${C.reset} ${col}ses:${linhas >= 1000 ? (linhas / 1000).toFixed(1) + 'k' : linhas}${dica}${C.reset}`;
      }
    } finally { fs.closeSync(fd); }
  }
} catch { /* sem transcript, sem permissão: a barra não pode quebrar por isto */ }

process.stdout.write(`${C.cyan}${currentDir}${C.reset}${gitSeg}${aheadBehind}${ghSeg}${ctxSeg}${sesSeg}`);
