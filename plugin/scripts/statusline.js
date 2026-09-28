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
// Uma linha só de contexto: a `ctx:`, do payload do harness. A `ses:`, lida do transcript
// mais abaixo, só entra quando o payload não traz context_window — as duas juntas mandavam
// /compact em dobro. Mesma régua nas duas: verde, amarelo em 150k, vermelho com /compact em 300k.
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

// Os últimos 256 KB do transcript, que passa de 100 MB em sessão longa e é lido a cada turno.
// "" sem transcript ou sem permissão: a barra não pode quebrar por isto.
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
const rabo = lerRabo(input.transcript_path);

// Fallback da `ctx:` sem context_window no payload: o contexto do último turno no transcript,
// como o hook session-size-guard mede — input + cache_read + cache_creation do último usage
// de assistente fora de sidechain. Com o advisor, o usage de cima soma as iterações; vale a
// última "message" ou "fallback_message". Usage zerado (<synthetic>) não é turno, e
// compact_boundary depois do último usage zera até o próximo. Contar linhas do transcript
// mandava /compact depois do /compact: o transcript só cresce.
if (!temPayload) {
  const n = (v) => Number(v) || 0;
  let ctx = 0;
  for (const linha of rabo.split('\n')) {
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
  if (ctx > 0) ctxSeg = segCtx('ses', ctx);
}

// Tokens/s de saída da ÚLTIMA chamada de API. O transcript não guarda duração por request;
// a conta é output_tokens ÷ (última linha da resposta − último evento `user` antes dela).
// Inclui o TTFT e o processamento do prompt: é a velocidade que o olho vê, não a do servidor.
// Cada resposta ocupa várias linhas com o mesmo message.id e o mesmo usage (uma por bloco), e
// com ferramenta rodando durante o streaming os tool_result se intercalam com essas linhas —
// por isso o fim é a ÚLTIMA linha do id, e o início é o `user` anterior à PRIMEIRA.
let tpsSeg = '';
try {
  if (rabo) {
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
    if (atual && atual.inicio) {
      const fim = Date.parse(atual.fim);
      const ms = fim - Date.parse(atual.inicio);
      // <0,5s é resposta curta demais pra medir; parado há 5 min, o número já é velho
      if (ms > 500 && Date.now() - fim < 300_000) {
        const tps = atual.out / (ms / 1000);
        const col = tps >= 40 ? C.green : tps >= 20 ? C.yellow : C.orange;
        tpsSeg = ` ${C.dim}·${C.reset} ${col}⚡${Math.round(tps)} t/s${C.reset}`;
      }
    }
  }
} catch { /* transcript ausente ou ilegível: o segmento some, a barra fica */ }

// Troca de modelo no meio da sessão. Com switchModelsOnFlag, mensagem sinalizada pelos
// safeguards troca o modelo (saindo do 5.5: claude-opus-4-8 em cyber, claude-opus-5 em bio)
// e o model.id do payload muda sem ninguém notar — no time, 2 sessões seguiram 36 e 18
// mensagens no 4.8. A barra não tem segmento de modelo (é uma linha só): aparece só o desvio.
// Um /model também acende, e tudo bem: quem trocou vê e segue. O primeiro model.id fica no
// tmpdir, como o cache do gh — some sozinho, e sessão retomada depois de reboot só perde o aviso.
let modeloSeg = '';
try {
  const sid = String(input.session_id || '');
  const id = String((input.model && input.model.id) || '');
  if (id && /^[\w-]+$/.test(sid)) {
    const marca = path.join(os.tmpdir(), `claude-sl-model-${sid}`);
    let primeiro = '';
    try { primeiro = fs.readFileSync(marca, 'utf8').trim(); } catch {}
    if (!primeiro) { fs.writeFileSync(marca, id); primeiro = id; }
    // "claude-opus-5-5[1m]" → "opus-5-5": o [1m] é a janela, não o modelo, e sozinho não é troca
    const curto = (m) => m.replace(/\[1m\]$/i, '').replace(/-\d{8}$/, '').replace(/^claude-/, '');
    if (curto(primeiro) !== curto(id)) modeloSeg = ` ${C.bold}${C.red}⚠ modelo trocou: ${curto(primeiro)}→${curto(id)}${C.reset}`;
  }
} catch {}

process.stdout.write(`${C.cyan}${currentDir}${C.reset}${modeloSeg}${gitSeg}${aheadBehind}${ghSeg}${ctxSeg}${tpsSeg}`);
