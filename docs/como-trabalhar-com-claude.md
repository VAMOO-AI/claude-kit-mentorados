# 🧠 Como trabalhar com o Claude (sem se queimar)

A ferramenta é poderosa, mas quem dirige é você. Este guia é sobre *como pensar*
junto com o Claude — vale mais que qualquer configuração.

---

## 1. O Claude faz o que você pede — então peça bem

Pedido ruim gera resultado ruim. Compare:

| ❌ Vago | ✅ Específico |
|---|---|
| "arruma esse código" | "esse botão não envia o formulário. O erro no console é `X`. Acha a causa e corrige." |
| "faz um site" | "uma landing page com um formulário de email que salva no Supabase. Stack: Next.js." |
| "tá lento" | "essa lista demora ~5s pra carregar 200 itens. Investiga o porquê antes de mudar." |

**Regra de ouro:** dê o **contexto** (o que é), o **objetivo** (o que quer) e o
**sinal real** (o erro, o print, o comportamento). Sem o erro real, o Claude
*adivinha* — e adivinhar é a fonte nº1 de retrabalho.

---

## 2. Use os modos certos (estão no seu CLAUDE.md)

- **Normal / executar:** "faz", "manda", "corrige isso". O Claude vai direto ao ponto.
- **"explica" / "modo aprendizado":** ele ensina o *porquê* antes do *como*, com
  alternativas. Use quando o assunto é novo pra você.
- **"modo aula":** passo a passo, sem atalhos, sem jargão. Use pra aprender de verdade.

Trocar de modo é só falar. Não precisa de comando.

---

## 3. Não confie cego — verifique

O Claude pode errar com confiança. Defesas simples:

- **Peça o teste rodando.** "Rodou? Cola o output." Seu CLAUDE.md já obriga isso,
  mas cobre se ele esquecer.
- **Leia o diff antes de aceitar.** Se você não entendeu a mudança, pergunte:
  "explica o que isso faz" antes de seguir.
- **Documentação:** com a skill `find-docs` instalada, peça "confere na doc oficial
  do `<lib>`". Isso evita API inventada/desatualizada.

> Regra prática: se a resposta parece boa demais e você não checou nada, você ainda
> não terminou.

---

## 4. Escopo pequeno, passos curtos

- Uma tarefa por vez. "Faz tudo" vira bagunça difícil de revisar.
- Antes de mudança grande, peça o plano: "me mostra o que vai mudar antes de fazer."
- Commits pequenos e frequentes. Deu ruim? Você volta um passo, não o projeto inteiro.

---

## 5. Memória do projeto (dot-context)

Em projeto novo, na 1ª conversa: peça **"init the context"**. O Claude cria a pasta
`.context/` e passa a lembrar das decisões do projeto entre sessões. Documentação
nova vai pra `.context/docs/`. Isso evita explicar tudo de novo toda vez.

> 📌 Quer entender como o Claude "lembra" das coisas (global vs projeto, o que vai no
> CLAUDE.md vs em `docs/`)? Leia [`memoria-e-contexto.md`](memoria-e-contexto.md). É o
> que mais confunde — vale 5 minutos.

---

## 6. Quando travar

- "Estamos em círculos" → fale isso. O Claude deve parar, reler tudo do zero e
  repensar, em vez de insistir no mesmo erro.
- Duas tentativas falharam? Peça pra ele ir fundo: "investiga a causa raiz, do
  começo, não chuta mais."
- Não entendeu a explicação? "explica de novo, mais simples, como se eu nunca
  tivesse visto isso."

---

## Anti-patterns (o que NÃO fazer)

- ❌ Aceitar código que você não entende só porque "rodou".
- ❌ Colar secret/senha/API key no chat ou no código.
- ❌ Pedir 10 coisas numa mensagem só.
- ❌ Deixar o Claude mexer direto na branch `main`.
- ❌ Reportar "deu erro" sem colar o erro.

---

## Em uma frase

**Você é o piloto. O Claude é um copiloto rápido e às vezes confiante demais —
dê contexto, verifique, e mantenha os passos pequenos.**
