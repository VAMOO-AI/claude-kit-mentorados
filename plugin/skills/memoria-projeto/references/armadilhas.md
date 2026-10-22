# Armadilhas da memória versionada

| Sintoma | Causa real |
|---|---|
| "Liguei, mas continua só na minha máquina" | Ligar não commita. O symlink põe no clone, o commit põe no repositório (§4 da skill) |
| Máquina nova sem nada da memória | O symlink é por máquina. Rode a §3 em cada computador que você usar |
| Slug calculado à mão não acha a memória (erra todo worktree) | O Claude Code troca **todo caractere fora de `[a-zA-Z0-9]`** por `-`: barra, espaço, ponto, `+`; caminho de worktree tem `.claude`. Use o comando da §1 |
| Sessão em worktree "não achou" o que registrou | A memória automática é por repositório e compartilhada entre os worktrees ([doc](https://code.claude.com/docs/en/memory.md#auto-memory)): a sessão do worktree grava pelo link do clone principal, no `.context/memoria/` dele. Procure lá (`git -C <clone-principal> status --short .context/memoria/`) e publique pela §4 da SKILL.md |
| `--adotar` recusou e o projeto é meu mesmo | O gate não pergunta de quem é o repo. Limpar o arquivo é mais barato que trocar credencial depois |
| Memória sumiu depois de dar `git pull` | Não estava commitada. Commite antes de sincronizar, sempre |
| Dois ou três PRs abertos com a mesma memória | Cada sessão publicou sem olhar se já havia PR de memória aberto. Confira com o `gh pr list` da §4 antes de abrir outro |
