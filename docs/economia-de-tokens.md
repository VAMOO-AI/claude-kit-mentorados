# 💸 Economia de tokens — por que seu limite acaba (e como fazer render)

Você paga o plano, usa o Claude por umas horas e… "limite atingido". A reação
comum é culpar o tamanho do projeto ou achar que o Claude "lê demais". Numa
análise real que fizemos (uma semana inteira de sessões, 2 bilhões de tokens
processados), a causa não era nada disso — e os números surpreendem.

---

## O modelo mental: o Claude relê a conversa INTEIRA toda hora

Isso é a coisa mais importante deste doc:

> **A cada mensagem sua — e a cada comando/arquivo que o Claude executa — ele
> relê a conversa inteira desde o início da sessão.**

O Claude não tem "memória de trabalho" separada: o contexto É a conversa. Se a
sessão acumulou 200 mil tokens (código lido, prints, respostas), cada passinho
novo reprocessa esses 200 mil. Um pedido seu que dispara 15 comandos = a
conversa inteira relida 15 vezes.

É por isso que **sessão longa custa juros compostos**: a 50ª mensagem numa
sessão cheia custa muitas vezes mais que a 5ª numa sessão limpa — pra fazer a
mesma coisa.

Na análise real: **90% de todo o consumo** veio de sessões com mais de 100
requests. E o detalhe: o usuário tinha mandado só ~30 mensagens em cada uma.
Não foi excesso de uso — foi a conversa acumulando peso.

---

## Os 4 hábitos que mais economizam (custo zero)

1. **Sessão nova por tarefa.** Terminou o bug do login? Vai mexer no layout?
   Fecha e abre outra (`/clear` ou novo terminal). Seu `CLAUDE.md` e o
   `.context/` do dotcontext recuperam o contexto necessário — barato.

2. **`/clear` ao trocar de assunto.** Tudo que ficou pra trás na conversa
   (aquele arquivo de 800 linhas lido há uma hora) continua sendo relido a
   cada passo. `/clear` zera a conta.

3. **`/compact` quando a barra de contexto passar de ~60%.** Ele resume a
   conversa e libera espaço. Fazer cedo é mais barato e resume melhor do que
   esperar o compact automático estourar no talo.

4. **Não "continue amanhã" na mesma sessão.** Retomar uma sessão pesada paga
   o preço dela inteira de novo. Amanhã, sessão nova + "continua o X" — o
   CLAUDE.md do projeto lembra o resto.

---

## Modelo certo pra tarefa certa

Modelos top custam **2× ou mais** por token que o tier abaixo — e no plano,
consomem seu limite na mesma proporção. Regra prática:

| Tarefa | Modelo |
|---|---|
| Dia a dia: fix, feature pequena, dúvida | **Sonnet** (dá conta e sobra limite) |
| Problema difícil, refactor grande, sessão longa autônoma | Opus |
| O problema impossível da semana | Tier acima do Opus, pontualmente (`/model`) |

E cuidado com a **janela de 1M de contexto** (`[1m]`): parece upgrade, mas ela
também desativa na prática a compactação automática — a sessão incha sem
limite e cada mensagem fica caríssima. Use só quando realmente precisa de um
contexto gigante de uma vez.

## Imagens pesam (e ficam)

Print de tela é ótimo pra mostrar um bug — mas cada imagem vira parte da
conversa e é reprocessada a cada mensagem até a sessão acabar. Prefira colar o
texto do erro quando der, e evite sequências longas de screenshots na mesma
sessão (é mais um motivo pro `/clear` entre tarefas).

## O que quase nunca é o problema

Na análise real, as suspeitas populares deram zero: a ferramenta de busca
(Grep) teve **0 chamadas na semana**, e leitura de arquivos era só ~8% do
custo. Antes de instalar indexador de código, compressor de output ou qualquer
ferramenta milagrosa: **meça primeiro** (abaixo). O problema quase sempre é
higiene de sessão, não ferramenta que falta.

---

## Como medir o seu consumo

- **`/usage`** dentro do Claude Code — mostra quanto do limite do plano você
  já usou.
- **`npx -y ccusage@latest daily`** no terminal — lê o histórico local das
  suas sessões e mostra consumo por dia e por modelo. Rode uma vez por semana;
  se um dia explodiu, você vai ver na hora qual foi.

Extra pra quem quer enxugar mais: MCPs e skills instalados entram no contexto
de **toda** sessão mesmo sem uso. Remova MCP que você não usa
(`claude mcp remove nome`) e esconda skills que você só chama por atalho
(`"skillOverrides": {"nome-da-skill": "user-invocable-only"}` no
`~/.claude/settings.json` — o `/nome-da-skill` continua funcionando).
