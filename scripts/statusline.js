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
const { execSync, spawn } = require('child_process');
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
  const gh = (args) => execSync('gh ' + args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 8000 }).trim();
  try {
    execSync('gh auth status', { encoding: 'utf8', stdio: 'ignore', timeout: 8000 });
    out.auth = true;
    if (branch && branch !== 'main' && branch !== 'master') {
      // número do PR aberto pra essa branch (vazio = sem PR)
      const n = gh(`pr list --head ${branch} --state open --json number --jq '.[0].number // empty'`);
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

// contexto (mesma lógica da statusline base)
let ctxSeg = '';
const usage = (input.context_window && input.context_window.current_usage) || {};
const windowSize = (input.context_window && input.context_window.context_window_size) || 0;
const totalInput = (usage.input_tokens || 0) + (usage.cache_creation_input_tokens || 0) + (usage.cache_read_input_tokens || 0);
if (totalInput > 0 && windowSize > 0) {
  const pct = Math.round((totalInput * 100) / windowSize);
  const col = pct < 50 ? C.green : pct < 80 ? C.yellow : C.red;
  ctxSeg = ` ${C.dim}·${C.reset} ${col}ctx:${Math.round(totalInput / 1000)}k/${Math.round(windowSize / 1000)}k (${pct}%)${C.reset}`;
}

process.stdout.write(`${C.cyan}${currentDir}${C.reset}${gitSeg}${aheadBehind}${ghSeg}${ctxSeg}`);
