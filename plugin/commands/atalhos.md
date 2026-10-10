---
description: Lista os atalhos deliberados marcados no código (// atalho: <teto>; <quando revisitar>) e aponta os que não têm gatilho de revisão
allowed-tools:
  - 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/atalhos.sh" *)'
  - 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/atalhos.sh *)'
---

Rode e mostre a saída inteira:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/atalhos.sh" .
```

Depois, uma linha por atalho `[sem-gatilho]`: o `arquivo:linha` e o gatilho que faltou (`; <condição mensurável pra revisitar>`), proposto a partir do código ao redor, não genérico. Não altere nada sem eu mandar.
