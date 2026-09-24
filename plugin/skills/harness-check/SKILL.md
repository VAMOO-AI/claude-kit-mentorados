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

O total do preload você mede sem pedir nada, direto do transcript:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/medir-sessao.py" --ultimas 3
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/medir-sessao.py" --comparar --cwd "$PWD"   # app × terminal
```

Por sessão: superfície (app desktop, terminal, SDK), versão, diretório,
`nascimento` = tokens do primeiro request (MEDIDO) e ferramentas MCP por servidor
(MEDIDO quando o transcript registra a lista; `?` quando não registra — aí só o
`/context` responde). Não substitui o `/context`, que quebra o preload por fatia;
responde "quanto custa abrir uma sessão aqui" e "é o app ou o terminal que nasce
caro". Numa medição de 23/09/2026 (conta do autor, mesmo diretório), o app nascia
com ~74K tokens e 340 tools de 26 servidores, e o terminal com ~41K.

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
claude mcp get <nome>   # escopo e comando de um servidor específico
```

Cruze com o `/context` (linha *MCP tools*) e pergunte, um por um: usei este mês?
Não usou → desligue e reative quando precisar. Dois avisos:

- **A tabela de uso não é a configuração de boot.** MCP que aparece pouco pode
  estar configurado só num projeto e nem carregar aqui — não há o que remover.
- **Conector do claude.ai não sai por `claude mcp remove`** (esse comando só
  enxerga os locais). Pra desligar todos no CLI e manter no
  site: `"disableClaudeAiConnectors": true` no `settings.json`. No **app desktop**
  essa opção não vale: os conectores da conta chegam por outro caminho. Se o
  `medir-sessao.py --comparar` mostra o app muito acima do terminal, o corte é
  desconectar o que você não usa nas configurações da conta no claude.ai
  (Conectores), ou trabalhar pelo terminal.

Skill que você só chama na mão também pesa (a *descrição* de cada skill entra no
preload). Duas saídas: `disable-model-invocation: true` no frontmatter da skill,
ou `"skillOverrides": {"minha-skill": "user-invocable-only"}` no `settings.json`.
Nos dois casos o `/minha-skill` continua funcionando — ela só sai da listagem
que o modelo lê toda vez.

## Passo 4 — os hábitos que realmente movem a conta

Em ordem de impacto medido, não de esforço:

1. **Sessão-maratona.** É o item número um, com folga. Sessão nova no projeto
   ao trocar de assunto (não `/clear`, que apaga o histórico da sessão) e `/compact` por volta de 150K de contexto (o `ctx:` amarelo da
   barra) — em janela de 1M o auto-compact só age perto do teto, e aí custa
   100–200K tokens de uma vez.
2. **Modelo caro como padrão.** Reserve o tier de cima pro problema difícil, não
   pra ajuste de CSS. Confira também em `ccusage daily` se aparece modelo que
   você não escolheu (subagente e barra de status explicam quase tudo).
3. **Preload** — só depois dos dois acima, e só com o `/context` na mão.
4. **Screenshot.** Imagem fica na conversa e é relida em toda mensagem seguinte.
   Peça texto (`read_page`, `get_page_text`) quando o pixel não for a evidência,
   e mande QA visual repetitivo pra um subagente.
5. **Esforço alto fixo.** `effortLevel` alto no `settings.json` faz toda
   resposta pensar mais — no Opus 5.5, mais que no Opus 5 no mesmo nível.
   Padrão no dia a dia; alto só na tarefa que pede, escolhido antes da primeira
   mensagem da sessão: trocar `/effort` no meio faz a próxima mensagem reler a
   conversa inteira sem cache.

## Fechamento

Entregue uma tabela `PROBLEMA | SINAL | GANHO ESTIMADO POR SESSÃO | RISCO`, ordenada
por ganho, com o rótulo MEDIDO/ESTIMADO em cada número — e **não aplique nada sem o
usuário aprovar item a item**. Desligar MCP, cortar regra do CLAUDE.md e trocar
modelo mudam o comportamento do harness dele, não só o custo.

Se o ganho total ficar abaixo de ~5% da fatura, diga isso na cara: o dinheiro
está no passo 4, e mexer no resto é fazer faxina achando que é economia.

### O que entra na tabela

Uma auditoria que devolve trinta recomendações não é mais completa: é mais fácil de
ignorar. E ignorada ela custa o dobro, porque gastou contexto e não mudou nada.

- **Só entra o que muda a conta de forma perceptível.** Ordene pelo impacto medido,
  não pelo que é mais fácil de escrever; no empate, suba o que o usuário aplica hoje.
  Não existe um número fixo de linhas: quem decide é o impacto.
- **Passo medido e limpo não vira linha.** Nada de `MCP | nada a relatar`. Linha vazia
  que se repete ensina a pular a tabela inteira.
- **Passo que você não conseguiu medir vira linha, com `INDISPONÍVEL`.** O caso comum é
  o `/context` do passo 1, que o usuário não colou. Sem essa linha o silêncio parece
  aprovação: "não achei nada" e "não medi" são coisas diferentes, e só a segunda pede
  uma ação dele.
- **A coluna SINAL diz de onde saiu a recomendação.** Não "desligue o MCP `foo`", e sim
  "`foo`: 38 tools anunciadas no `medir-sessao.py` (MEDIDO), escopo user no
  `claude mcp get foo`, e você disse que não usou este mês". Não "enxugue o CLAUDE.md",
  e sim "`CLAUDE.md` com 8,4K chars, ~2,1K tokens (ESTIMADO), contra 52,7K de preload no
  `/context` (MEDIDO)". Sem o sinal a recomendação parece palpite, e o usuário não tem
  como conferir.
- **Recomendação sem comando ou arquivo que a sustente não entra.** Só valem as fontes
  desta skill: `/context`, `medir-sessao.py`, `ccusage`, `claude mcp list/get` e o
  arquivo que você abriu. Esta skill não conta chamadas por MCP; "você não usa" é o
  usuário quem responde, não um número que você inventa.
- **Feche dizendo o que ficou de fora**, numa linha: *"deixei de fora N achados menores
  (MCP e skills) — peça se quiser a lista"*. Ele decide se quer mais; você não decide
  por ele despejando tudo.
