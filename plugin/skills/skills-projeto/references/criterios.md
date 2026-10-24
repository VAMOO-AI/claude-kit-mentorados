# Critérios — os casos que a tabela do scan não decide sozinha

O `skills-projeto-scan.sh` acusa o que está **objetivamente** quebrado: `name` ≠ pasta,
corpo vazio (casca), skill sem description, total acima do teto. Ele não sabe se a skill é
boa, se duplica outra, nem de onde veio. Estes são os casos em que a decisão é sua.

## Deletar

**`name` ≠ pasta.** O Claude Code escolhe a skill pelo `name` do frontmatter; pasta com
nome diferente é description paga e gatilho morto. Se a skill tinha conteúdo bom, conserte
o `name` **e** confira o corpo antes de manter: nas dez cascas de 04/09/2026 os dois
defeitos vieram juntos.

**Corpo vazio.** Zero linha com texto depois do frontmatter. Se alguém garante que ia
escrever, o compromisso vira issue no repositório do projeto, não arquivo em
`.claude/skills`.

**Duplica skill global ou de plugin.** Compare o corpo antes de apagar. Se a versão local
é melhor, ela sobe para onde as outras moram (o seu kit, o seu plugin) e a local sai no
mesmo commit. Manter as duas garante divergência silenciosa: a de fora é atualizada e a
local não.

**O modelo acerta sem ela.** Rode o cenário de pressão da skill sem a SKILL.md (ver
"Opcional: teste a skill sob pressão" na SKILL.md). Se a escolha certa já aparece assim,
a skill não está segurando nada, ou o cenário é fraco. As duas leituras terminam em "não
mantenha como está".

**Skill fora do git.** Não é motivo por si só, é agravante. Confira com
`git ls-files .claude/skills`: o que não aparece some no próximo clone, então já é
local-de-uma-máquina, e mantê-la só engorda o contexto de quem a tem.

## Mover para `.context/docs/`

O teste é o gatilho, não o tamanho: **existe frase do tipo "use quando…"?**

- Tem gatilho claro e procedimento → skill.
- Só tem conteúdo ("o schema é assim", "os endpoints são estes", "decidimos X porque Y")
  → `.context/docs/` (ou a pasta de docs do repositório, sem `.context/`). Preload zero, e o texto continua
  achável por busca.

Corpo curto é sinal, não sentença: procedimento de verdade em 12 linhas existe. O que não
existe é procedimento de verdade em 3.

Ao mover, leve o texto inteiro e apague a pasta da skill no mesmo commit. Pasta com um
`SKILL.md` de uma linha apontando para o doc é o pior dos dois mundos: paga description
para dizer "está lá".

## Manter

Passou nos dois acima e o total continua dentro do teto (8 skills / 2.000 chars, ver o
`skills-projeto-scan.sh`).

Se o total estoura com todas as skills íntegras, o problema é escopo, e há duas saídas
honestas:

1. **Promover** o que não é específico deste projeto para um kit ou plugin seu: serve a
   todos os projetos e é mantido em um lugar só.
2. **Dividir o repositório**: catálogo local grande costuma ser sintoma de monorepo que
   deveria ser dois.

O que **não** é saída: pôr tudo como só-slash (`disable-model-invocation: true`) para o
número cair. Zera o custo e zera o roteamento junto, e você fica com dez comandos de barra
que ninguém lembra de digitar.

## Lacuna — o que conta como dor

"Fiz na mão umas três vezes" é literal: **três ocorrências datadas**, não três hipóteses.
E o procedimento precisa estar estável: se o passo a passo ainda muda a cada vez, escrever
a skill agora congela a versão errada.

Ordem das portas, sem pular:

1. Já existe skill global ou de plugin? `ls ~/.claude/skills` e o menu `/` da sessão.
   Pode existir e estar como só-slash, o que não a faz sumir.
2. Existe no ecossistema? `npx skills@1.7.4 find <termo>`. Instalar traz update próprio;
   escrever traz manutenção.
3. Escrever. Nasce com `name` = pasta, corpo que ensina algo, description abaixo de 500
   chars e, se for skill de disciplina, um cenário que **erra** sem a skill. Cenário que
   acerta sem ela não prova nada.

## Skill que está no git de um cliente

Deletar é commit no repositório do cliente, com a mesma régua de qualquer mudança:
branch, mensagem explicando o porquê, PR. Não apague direto na main "porque é só uma pasta
de config".

Se a skill foi escrita por outra pessoa, a linha do scan entra no PR como evidência, não
como opinião. `name: Refactoring` numa pasta `refactoring` é fato verificável, e a
conversa termina rápido.

## Procedência

O scan não diz de onde a skill veio. Pergunte à pasta:

- `LICENSE` na pasta da skill → código de terceiro copiado para dentro. Prefira instalar
  pelo gerenciador (`npx skills@1.7.4 add`) ou como plugin, que trazem update, a manter
  uma cópia que ninguém atualiza.
- Nenhum sinal → ache o autor no histórico: `git log --diff-filter=A -- .claude/skills/<pasta>`.

Em qualquer caso, **leia o SKILL.md inteiro antes de instalar ou manter**: a interpolação
de comando no corpo executa shell quando a skill carrega, fora de toda a cadeia de
permissão.
