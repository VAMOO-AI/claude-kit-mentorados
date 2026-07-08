#!/usr/bin/env node
// Lê o JSON que o Claude Code manda pro hook (via stdin) e imprime UM campo,
// endereçado por caminho com pontos. Ex.: hookjson.js tool_input.command
// Substitui o `jq` nos hooks — como o node já é pré-requisito do kit, isso
// remove o jq da lista de dependências. Falha em silêncio (campo ausente → vazio).
'use strict';
let raw = '';
process.stdin.on('data', (d) => { raw += d; });
process.stdin.on('end', () => {
  let obj;
  try { obj = JSON.parse(raw); } catch { return; }
  const path = (process.argv[2] || '').split('.').filter(Boolean);
  for (const key of path) {
    if (obj == null) return;
    obj = obj[key];
  }
  if (obj != null) process.stdout.write(String(obj));
});
