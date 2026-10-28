# skills-projeto — Opcional: teste a skill sob pressão

Lido antes de montar um cenário de pressão para uma skill. É nota, não gate (ver SKILL.md).

Skill de disciplina ("sempre rode o teste antes de dizer pronto") costuma ser
ignorada justamente quando dá trabalho obedecer. O `skill-pressure-test.sh` do
plugin mede isso só nas skills do próprio kit: ele procura a skill em
`${CLAUDE_PLUGIN_ROOT}/skills` e recusa (exit 2) a que não está lá. Para uma
skill do seu projeto, faça o mesmo à mão: um cenário com escolha forçada
(A/B/C), rodado com `claude -p` sem a skill e depois com a SKILL.md em
`--append-system-prompt-file`; se a escolha certa só aparece com a skill, ela
segura alguma coisa. O método completo está no repositório do kit, fora do
plugin instalado:
https://github.com/VAMOO-AI/claude-kit-mentorados/blob/main/docs/testar-skills-sob-pressao.md
