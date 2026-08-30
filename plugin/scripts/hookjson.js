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
  const get = (p) => {
    let obj = root;
    for (const key of p.split('.').filter(Boolean)) {
      if (obj == null) return '';
      obj = obj[key];
    }
    return obj == null ? '' : String(obj);
  };
  const head = paths.slice(0, -1).map((p) => get(p).replace(/\r?\n/g, ' '));
  const last = paths.length ? get(paths[paths.length - 1]) : '';
  process.stdout.write(head.map((h) => h + '\n').join('') + last);
});
