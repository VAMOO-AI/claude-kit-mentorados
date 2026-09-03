---
name: harness-check
description: >-
  Descobre PARA ONDE seu token está indo e o que dá pra cortar sem perder nada.
  Mede o que a sessão já carrega antes do seu primeiro prompt (CLAUDE.md, skills,
  MCPs) e o gasto durante o uso, com rótulo de MEDIDO vs ESTIMADO. Use em
  "estourei o limite", "por que gastei tanto token", "a sessão nasce cara",
  "vale desligar esse MCP?", "meu CLAUDE.md está grande demais?", "harness-check".
  Não é o secscan (segurança) nem o baseline (produção).
---

# Harness Check — para onde vai o seu token

O erro clássico de quem tenta economizar é cortar o que dá pra ver: o CLAUDE.md.
Quase sempre ele é a menor parte. Esta skill manda **medir antes de cortar**, e
separa o que você tem como medir do que é chute.

## Regra de ouro: rotule todo número

- **MEDIDO** — saiu de um comando ou de um relatório nesta sessão.
- **ESTIMADO** — `chars ÷ 4`, extrapolação, regra de bolso.
- **INDISPONÍVEL** — você não tem acesso. Diga isso; não chute por baixo só pra
  a tabela ficar completa.

Número sem rótulo não entra no relatório. Auditoria de token engana justamente
aí: a maior fatia do contexto inicial são schemas de ferramenta, que você **não**
consegue medir arquivo por arquivo — só o `/context` entrega.

## Passo 1 — o que a sessão carrega antes do primeiro prompt

Peça ao usuário: **rode `/context` e cole o output**. Comando built-in do CLI não
se invoca por `Bash` — peça, não simule, não estime no lugar dele.

O `/context` devolve, em tokens e em % da janela: system prompt, system tools,
MCP tools, memory files (CLAUDE.md e afins), custom agents, mensagens,
autocompact buffer e espaço livre. Esse é o **preload**: ele é relido em toda
request da sessão, então cada token ali é multiplicado por quantas vezes você
apertar Enter.

Leia o output com esta pergunta: **quanto do preload é arquivo meu?** Numa
medição de 03/09/2026 (conta do autor do kit, harness carregado) o preload era
**52,7K tokens** (MEDIDO) e só ~5K — **10%** — vinha de arquivo editável
(ESTIMADO por `chars÷4`: CLAUDE.md 2,1K, descrições das skills visíveis 1,7K,
memória 0,9K). Os outros 90% eram system prompt, schemas de ferramenta e MCP —
INDISPONÍVEL sem o `/context`. Enxugar o CLAUDE.md ali economizaria ~2% do
preload, ou seja, nada — e é exatamente o corte que todo mundo tenta primeiro.

## Passo 2 — o gasto durante o uso

```bash
npx -y ccusage@latest daily      # custo por dia e por modelo
npx -y ccusage@latest session    # custo por sessão — ache as caras
```

Olhe **cache read**: numa sessão longa ele costuma ser a maior linha da conta,
porque cada tool call relê tudo que veio antes. Uma sessão de 400 requests não
custa 4× uma de 100: custa muito mais, porque o contexto que se relê cresce a
cada turno.

Compare o custo médio das sessões curtas com o das longas. Se as longas dominam
a fatura (o normal), o problema **não** é o seu CLAUDE.md — é o passo 4.

## Passo 3 — MCP que você não usa

Todo servidor MCP ligado injeta o schema de cada ferramenta dele no preload,
usando você ou não. É a única parte grande do preload que está na sua mão.

```bash
claude mcp list
jq '.mcpServers, (.projects | to_entries[] | select(.value.mcpServers))' ~/.claude.json
```

Cruze com o `/context` (linha *MCP tools*) e pergunte, um por um: usei este mês?
Não usou → desligue e reative quando precisar. Dois avisos:

- **A tabela de uso não é a configuração de boot.** MCP que aparece pouco pode
  estar configurado só num projeto e nem carregar aqui — não há o que remover.
- **Conector do claude.ai não sai por `claude mcp remove`** (esse comando só
  enxerga os locais do `~/.claude.json`). Pra desligar todos no CLI e manter no
  site: `"disableClaudeAiConnectors": true` no `settings.json`.

Skill que você só chama na mão também pesa (a *descrição* de cada skill entra no
preload). Duas saídas: `disable-model-invocation: true` no frontmatter da skill,
ou `"skillOverrides": {"minha-skill": "user-invocable-only"}` no `settings.json`.
Nos dois casos o `/minha-skill` continua funcionando — ela só sai da listagem
que o modelo lê toda vez.

## Passo 4 — os hábitos que realmente movem a conta

Em ordem de impacto medido, não de esforço:

1. **Sessão-maratona.** É o item número um, com folga. `/clear` ao trocar de
   assunto e `/compact` por volta de 60% do contexto — o auto-compact só age
   tarde, e aí custa 100–200K tokens de uma vez.
2. **Modelo caro como padrão.** Reserve o tier de cima pro problema difícil, não
   pra ajuste de CSS. Confira também em `ccusage daily` se aparece modelo que
   você não escolheu (subagente e barra de status explicam quase tudo).
3. **Preload** — só depois dos dois acima, e só com o `/context` na mão.
4. **Screenshot.** Imagem fica na conversa e é relida em toda mensagem seguinte.
   Peça texto (`read_page`, `get_page_text`) quando o pixel não for a evidência,
   e mande QA visual repetitivo pra um subagente.

## Fechamento

Entregue uma tabela `PROBLEMA | GANHO ESTIMADO POR SESSÃO | RISCO`, ordenada por
ganho, com o rótulo MEDIDO/ESTIMADO em cada número — e **não aplique nada sem o
usuário aprovar item a item**. Desligar MCP, cortar regra do CLAUDE.md e trocar
modelo mudam o comportamento do harness dele, não só o custo.

Se o ganho total ficar abaixo de ~5% da fatura, diga isso na cara: o dinheiro
está no passo 4, e mexer no resto é fazer faxina achando que é economia.
