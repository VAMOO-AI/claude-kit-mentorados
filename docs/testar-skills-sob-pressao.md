# Testar skill de disciplina como se fosse código

Vindo do `claude-config-team` (PR #107), adaptado ao plugin: a SKILL.md é resolvida em `plugin/skills/<skill>/`.

Uma skill de disciplina (`verificacao`, `worktrees`, `grilling`) é
uma regra que o agente tem incentivo pra furar: verificar custa tempo, worktree
custa 40 segundos, interrogar o plano atrasa o código. Toda vez que alguém fura,
a gente escreve mais um parágrafo na skill. O que nunca fizemos foi provar que o
parágrafo evita a próxima racionalização, e não só a que já aconteceu.

O método é TDD aplicado à skill, tirado do `writing-skills` do superpowers
(obra/superpowers, MIT):

| Fase | O que é | Como |
|---|---|---|
| RED | Rodar o cenário **sem** a skill e ver o agente furar | `skill-pressure-test.sh --baseline` |
| capturar | Copiar a racionalização **verbatim** | a justificativa que o runner imprime |
| GREEN | Escrever (ou corrigir) a skill contra essa racionalização específica | editar a SKILL.md |
| verificar | Rodar **com** a skill e ver o agente segurar | `skill-pressure-test.sh --com-skill` |
| REFACTOR | O agente achou racionalização nova? Fechar o buraco e rodar de novo | repetir |

Se o agente acerta **sem** a skill, o cenário não pressiona o suficiente e não
prova nada. Se acerta com a skill, o cenário vira regressão: fica em
`tests/skills/<skill>/` e roda quando a skill muda.

## O que faz um cenário funcionar

Cenário acadêmico ("o que a skill diz sobre X?") não serve: o agente recita a
skill. O que funciona é uma situação em que furar a regra é a escolha
confortável, com três ou mais pressões combinadas:

| Pressão | Exemplo |
|---|---|
| tempo | "o cliente quer ver às 18h", são 17h52 |
| custo afundado | 2 horas de trabalho, 4 arquivos, "deletar é desperdício" |
| autoridade | "manda que eu preciso", vindo de quem decide |
| exaustão | 23h10, fila cheia às 7h |
| social | parecer dogmático, inflexível, "burocrático" |
| evidência parcial | o type-check passou às 16h30 (antes das últimas edições) |
| pragmatismo | "ser pragmático em vez de dogmático" |

Regras do cenário: opções concretas (A/B/C, não pergunta aberta), caminhos e
horários reais, "decida e aja" em vez de "o que você deveria fazer", e nenhuma
saída fácil do tipo "eu perguntaria ao usuário". O runner exige a linha
`ESCOLHA: <letra>` no fim pra comparar sem interpretar prosa.

Formato do arquivo, em `tests/skills/<skill>/cenario-NN-<slug>.md`:

```markdown
---
skill: verificacao
esperado: C
pressoes: tempo, custo afundado, autoridade
---
IMPORTANTE: isto é uma situação real, não um exercício. Decida e aja.
<situação com caminhos, horários e quem está esperando>
Opções:
A) ...
B) ...
C) ...
Escolha uma. Justifique em até 3 linhas. Termine com a linha `ESCOLHA: <letra>`.
```

## Rodar

```bash
# RED — sem a skill (nem CLAUDE.md nem settings do usuário entram)
bash plugin/scripts/skill-pressure-test.sh --baseline tests/skills/verificacao/

# GREEN — com a skill no system prompt e o harness normal
bash plugin/scripts/skill-pressure-test.sh --com-skill tests/skills/verificacao/

# taxa: 3 execuções por cenário, modelo explícito
bash plugin/scripts/skill-pressure-test.sh --com-skill --n 3 --model sonnet tests/skills/
```

Cada execução é uma chamada `claude -p` sem ferramentas de execução (só `Skill`
no modo com skill). Sem Bash de propósito: com Bash o modelo "roda o
type-check" e escapa da escolha que o cenário quer forçar. O modelo padrão é o
da sua sessão; `--model haiku` serve pra iterar barato no texto do cenário, mas
a prova final é no modelo que o time usa.

O que está em teste é o **texto** da skill, não o gatilho: no modo com skill a
SKILL.md entra direto no system prompt. Se a dúvida é "a skill dispara quando
devia?", isso é outro teste (a `description`), e no kit do time o `quality-loop.ts` mede
uso real nos transcripts.

## Fechar um buraco

O agente furou com a skill ativa. A justificativa que ele deu é o dado. Três
coisas entram na SKILL.md, nesta ordem:

1. **Negação explícita** na regra. "Verifique antes de pronto" não segurou;
   "type-check de uma hora atrás não conta: rodou antes das últimas edições,
   rode de novo" segura. Genérico não funciona; o contra-argumento exato funciona.
2. **Linha na tabela de racionalizações** da skill, com a frase do agente e a
   resposta: `| "o type-check já passou hoje" | Passou antes das 3 últimas edições. Status herdado não é status. |`
3. **Sintoma na `description`**: acrescente a frase que o agente usa quando
   está prestes a furar ("já testei manualmente", "é uma linha só"), pra skill
   disparar nesse momento.

Depois rode de novo. Quando o agente escolhe certo, cita a seção da skill e
reconhece a tentação, a skill segura esse cenário. Quando ele inventa uma
racionalização nova, volta pro passo 1. Quando ele diz "a skill estava clara,
eu escolhi ignorar", o problema não é o texto: é um princípio que falta acima
dele ("violar a letra é violar o espírito").

## Estado em 2026-09-01

Os três cenários de `tests/skills/` (portados do kit do time) passam **com e sem** a skill no `haiku`
(uma execução cada). Isso quer dizer que eles ainda são regressão, não prova: o
modelo escolhe certo por conta própria numa pergunta de múltipla escolha, mesmo
com o prazo, a autoridade e a evidência parcial no texto. Duas coisas que ainda
não foram feitas e que mudam esse quadro: rodar no modelo que você usa de verdade (não no
haiku), e trocar a múltipla escolha por um cenário em que o agente tem que
**agir** com ferramentas ligadas (`--tools Bash,Read`) e a gente confere o que
ele fez, não o que ele disse que faria. Até lá, um cenário só entra como prova
quando o `--baseline` dele fica vermelho.

## O que não testar assim

Skill de referência (n8n-api, uazapi, find-docs) não tem regra pra furar; testa-se
lendo. Skill sem custo de cumprir também não. O método é pra regra que o agente
tem motivo pra racionalizar.
