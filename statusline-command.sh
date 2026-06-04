#!/bin/bash
# Claude Code statusline — Node.js version (Windows/Git Bash compatible)
input=$(cat)

node -e "
const input = JSON.parse(process.argv[1]);
const path = require('path');

// Current directory
const cwd = input.workspace?.current_dir || '';
const currentDir = path.basename(cwd);

// Git branch + dirty status
let gitInfo = '';
try {
  const { execSync } = require('child_process');
  const branch = execSync('git --no-optional-locks branch --show-current 2>/dev/null', { cwd, encoding: 'utf8' }).trim();
  if (branch) {
    const porcelain = execSync('git --no-optional-locks status --porcelain 2>/dev/null', { cwd, encoding: 'utf8' }).trim();
    gitInfo = porcelain ? ' git:(' + branch + ')✗' : ' git:(' + branch + ')';
  }
} catch {}

// Context usage
let contextInfo = '';
let ctxColor = '';
const usage = input.context_window?.current_usage || {};
const inputTokens = usage.input_tokens || 0;
const cacheCreation = usage.cache_creation_input_tokens || 0;
const cacheRead = usage.cache_read_input_tokens || 0;
const windowSize = input.context_window?.context_window_size || 0;
const totalInput = inputTokens + cacheCreation + cacheRead;

if (totalInput > 0 && windowSize > 0) {
  const inputK = Math.round(totalInput / 1000);
  const windowK = Math.round(windowSize / 1000);
  const pct = Math.round((totalInput * 100) / windowSize);
  contextInfo = ' ctx:' + inputK + 'k/' + windowK + 'k (' + pct + '%)';
  if (pct < 50) ctxColor = '\x1b[32m';
  else if (pct < 80) ctxColor = '\x1b[33m';
  else ctxColor = '\x1b[31m';
}

let out = '\x1b[36m' + currentDir + '\x1b[0m';
if (gitInfo) out += '\x1b[34m' + gitInfo + '\x1b[0m';
if (contextInfo) out += ctxColor + contextInfo + '\x1b[0m';
process.stdout.write(out);
" "$input"
