# skills-projeto — O que faz uma skill rotear de verdade

Lido ao criar, consertar ou julgar uma skill (passo 1 de Enxugar e o checklist antes de commitar).

O Claude Code escolhe a skill pelo `name` do frontmatter e decide pela
`description`. Três coisas, e todas já falharam em projeto real:

- **`name` igual ao nome da pasta**, minúsculo e com hífen. Pasta
  `refactoring` com `name: Refactoring` **não dispara nunca** — e continua
  cobrando a description em toda request. Em 04/09/2026 um projeto tinha dez
  assim, todas saídas do mesmo scaffold.
- **`description` que diz QUANDO usar**, com as palavras que você realmente
  digita. "Ajuda com testes" não roteia; "use ao escrever teste novo, ao
  investigar teste instável, ou quando o CI fica vermelho só no CI" roteia.
- **Corpo com conteúdo.** Os mesmos dez SKILL.md tinham 99–135 bytes e o corpo
  vazio: cobravam a description e não ensinavam nada. Skill sem corpo é uma
  linha do AGENTS.md do projeto que se disfarçou de skill.
