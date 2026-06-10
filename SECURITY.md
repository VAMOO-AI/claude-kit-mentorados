# Segurança

## Reportando uma vulnerabilidade

Achou um problema de segurança no kit (secret vazado, dependência vulnerável,
comando perigoso num script ou skill)? **Não abra issue pública.**

- Reporte via [GitHub Security Advisory](https://github.com/VAMOO-AI/claude-kit-mentorados/security/advisories/new) (privado), ou
- Me chame direto (mentorados têm meu contato).

Respondo em até 7 dias. Correção sai como patch + nota no CHANGELOG.

## O que o kit faz (e não faz) com seus dados

- O instalador só escreve em `~/.claude/` e faz backup do que sobrescreve em
  `~/.claude/backup-kit-<data>/`.
- Nenhum script do kit envia dados pra fora da sua máquina. As skills que falam
  com APIs (TickTick, Pipedrive, n8n, NotebookLM) só funcionam com credenciais
  **suas**, configuradas por você, fora do git.
- A skill `notebooklm` guarda cookies/auth do Google em `data/` dentro da
  própria skill — pasta coberta por `.gitignore`, nunca commitada.

## Regras que o próprio kit ensina (valem pra ele também)

- `.env` / `.env.local` nunca vão pro git; `.env.example` documenta as chaves.
- Vazou chave? Rotacione na hora — não adianta só apagar o commit.
- Dependências das skills são checadas com `osv-scanner` no CI do repositório.
