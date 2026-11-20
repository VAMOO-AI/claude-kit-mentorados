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

## O corpo: cada frase muda o que o agente faria sem ela

Vale para SKILL.md, `AGENTS.md`, `CLAUDE.md` e doc que um ponteiro abre. Adaptado de
[mattpocock/skills](https://github.com/mattpocock/skills) (`writing-for-agents`, MIT).

- **Frase que o modelo já obedece é no-op: sai inteira.** "Seja cuidadoso", "escreva código
  limpo", "leia o arquivo antes de editar" pagam contexto para dizer nada. O teste é contra o
  comportamento padrão do modelo, e se resolve rodando a skill, não discutindo. Não apare
  palavras de uma frase no-op: apague a frase.
- **Diga o alvo, não a proibição.** "Não use travessão" põe o travessão no contexto e o torna
  mais provável. Escreva o que fazer ("use vírgula ou ponto"). Proibição sozinha só para
  guardrail duro que não tem forma positiva, e mesmo assim junto do alvo.
- **Uma palavra-âncora no lugar da frase repetida.** Ideia explicada em três lugares vira um
  termo que o modelo já conhece, repetido como termo: um loop *vermelho* (o comando falha neste
  bug ou não falha) no lugar de "um teste em que você confia e que pega o problema". A palavra
  forte também vence o padrão onde a fraca não vence: *implacável* muda o comportamento,
  *detalhado* não.
- **O ambiente é a fonte; a doc não copia.** Script do `package.json`, config, árvore de pastas
  e `--help` o agente acha num comando. Copiar para a skill cria cache que envelhece. Escreva o
  que nenhum comando revela: a convenção não escrita, o porquê de uma escolha, a pegadinha.
- **Cada passo termina num critério que dá para checar.** "Entender o problema" deixa o agente
  pular para o fim; "um comando já rodado que falha com o sintoma relatado" não deixa. O
  critério forte é checável e exaustivo ("todo modelo alterado listado").
- **Detalhe que só um ramo usa vai para `references/`**, atrás de um ponteiro que diz quando
  ler. O que todo ramo precisa fica no SKILL.md. Um significado mora num lugar só.
