#!/usr/bin/env node
// Lê o JSON que o Claude Code manda pro hook (via stdin) e imprime os campos pedidos,
// endereçados por caminho com pontos.
//   hookjson.js tool_input.command
//   hookjson.js permission_mode cwd tool_input.command
// Vários campos numa chamada só porque o hook roda em TODO comando Bash: cada startup
// de node custa ~30ms na latência de quem está usando.
//
// FORMATO: um campo por linha, na ordem pedida — MENOS o último, que sai cru e pode
// conter quebras de linha (é onde vai `tool_input.command`, que carrega heredoc).
// Quem chama lê os escalares com `sed -n Np` e o último com `sed '1,Nd'`.
// Falha em silêncio (campo ausente → linha vazia).
//
// CODEX: o Codex manda o comando em array (["/bin/zsh","-lc","<cmd>"]) e a pasta em
// tool_input.workdir, sem o cwd do Claude Code. Sem normalizar, `tool_input.command` saía
// como "/bin/zsh,-lc,<cmd>" e `cwd` vazio, e o guard decidia sobre o texto errado (no
// time, medido em 15/10/2026: o block-main-commit deixava passar commit na main). Por isso
// `tool_input.command` em array devolve o script do -lc/-c, e `cwd` cai para
// tool_input.workdir e tool_input.cwd, na mesma ordem dos guards do time. Normalizar aqui
// vale para todo hook do plugin, e o payload continua lido uma vez só.
'use strict';
// Hook não pode vomitar stack trace: se quem lê fechar o pipe antes (`| head`), o
// EPIPE viraria ruído no terminal de quem está trabalhando.
process.stdout.on('error', () => {});
let raw = '';
process.stdin.on('data', (d) => { raw += d; });
process.stdin.on('end', () => {
  let root;
  try { root = JSON.parse(raw); } catch { return; }
  const paths = process.argv.slice(2);
  const pick = (p) => {
    let obj = root;
    for (const key of p.split('.').filter(Boolean)) {
      if (obj == null) return undefined;
      obj = obj[key];
    }
    return obj;
  };
  const get = (p) => {
    let v = pick(p);
    if (p === 'tool_input.command' && Array.isArray(v)) {
      v = v.length >= 3 && (v[1] === '-lc' || v[1] === '-c') ? v[2] : v.join(' ');
    }
    if (p === 'cwd') {
      v = ['tool_input.workdir', 'tool_input.cwd', 'cwd']
        .map(pick).find((x) => typeof x === 'string' && x.length > 0);
    }
    return v == null ? '' : String(v);
  };
  const head = paths.slice(0, -1).map((p) => get(p).replace(/\r?\n/g, ' '));
  const last = paths.length ? get(paths[paths.length - 1]) : '';
  process.stdout.write(head.map((h) => h + '\n').join('') + last);
});
