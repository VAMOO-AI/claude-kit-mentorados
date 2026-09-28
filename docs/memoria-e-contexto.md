# 🧩 Memória e contexto — como o Claude "lembra"

Este é o modelo mental que confunde até gente experiente. Entender isso aqui evita
90% das dúvidas sobre CLAUDE.md.

---

## Os dois CLAUDE.md NÃO competem — eles se somam

O Claude Code carrega CLAUDE.md de mais de um lugar, em camadas:

| Camada | Onde fica | Pra quê |
|---|---|---|
| **Global (user)** | `~/.claude/CLAUDE.md` | Como VOCÊ trabalha — vale em todo projeto (idioma, segurança, disciplina). |
| **Projeto** | `<projeto>/AGENTS.md`, que o `<projeto>/CLAUDE.md` importa com a linha `@AGENTS.md` | O que é AQUELE repo — stack, comandos, armadilhas. |
| **Local (opcional)** | `<projeto>/CLAUDE.local.md` | Suas notas pessoais do projeto (fica no `.gitignore`). |

**Por que `AGENTS.md` no projeto:** é o arquivo que Codex, Cursor e outros agentes também
leem. O `CLAUDE.md` do projeto fica com uma linha, `@AGENTS.md`, mais o que for exclusivo do
Claude — a regra mora num lugar só, sem cópia e sem symlink. Modelo pronto em
[`plugin/templates/AGENTS-projeto.md.exemplo`](../plugin/templates/AGENTS-projeto.md.exemplo).

**Como eles se combinam:** os arquivos são **concatenados** (somados), não disputados.
Quando há *conflito* na mesma regra, o **mais específico vence** — projeto ganha do
global. Exemplo: global diz "indentação 2 espaços", projeto diz "4 espaços" → no
projeto, vale 4.

> Por isso **não existe "ambiguidade" em ter global + projeto.** Existe composição com
> precedência clara. O global é a base; o projeto especializa. É o design oficial — não
> tente "consertar" movendo o global pra outro arquivo: aí ele para de ser carregado
> sozinho e você perde a automação.

**Quer ver o que está carregado agora?** Rode `/memory` dentro do Claude Code — ele
lista os arquivos ativos e a ordem. É a ferramenta de debug quando o Claude não segue
uma regra que você jurava estar ativa.

---

## O que vai onde (a regra que evita inchaço)

Cada coisa tem um lugar. Misturar incha o contexto e degrada tudo.

| Conteúdo | Vai pra... | Por quê |
|---|---|---|
| **Regra de comportamento** ("sempre X", "nunca Y") | `AGENTS.md` do projeto (vale em todo projeto? `~/.claude/CLAUDE.md`) | É carregado em toda sessão. Tem que ser curto e durável. |
| **Documentação de implementação** (como tal feature funciona, decisão de arquitetura) | `docs/` (ou `.context/docs/`) | É consultado sob demanda, não a cada sessão. |
| **Fato durável do projeto** (credencial está em X, esse cliente usa Y) | memória / `.context/` | Lembrado entre sessões, sem inflar o `AGENTS.md`. |

> **Anti-pattern comum:** "toda vez que termino uma feature, mando atualizar o
> AGENTS.md". NÃO. O AGENTS.md entra **inteiro** no contexto em **toda** sessão (o
> `CLAUDE.md` o importa) — changelog ali dentro é peso morto que você paga sempre.
> Changelog e doc de implementação vão pra `docs/`. **AGENTS.md cresce com regra, não
> com histórico.**

---

## O loop de feedback (a prática mais poderosa)

Quando o Claude faz algo que você não queria:

1. Corrija na hora: *"não faça isso — [o que fazer no lugar]"*.
2. Peça pra gravar no lugar certo: *"grava essa regra no AGENTS.md"* (regra deste
   projeto; se vale pra todo projeto, no `~/.claude/CLAUDE.md`) ou *"guarda isso na
   memória"* (se é um fato do projeto).

Assim, na próxima sessão, ele já começa sabendo — sem você repetir.

---

## Ao terminar uma feature

Bom hábito de fechamento:

> *"Atualiza a documentação em `docs/` e a memória se algo mudou. NÃO mexe no AGENTS.md
> a menos que tenha surgido uma regra nova."*

Isso mantém o contexto vivo entre sessões **sem** inflar o arquivo que pesa toda vez.

---

## Em uma frase

**Global + projeto se somam (não competem); regra do projeto vai no AGENTS.md (a de todo
projeto, no `~/.claude/CLAUDE.md`), implementação vai em `docs/`, fato vai na memória — e
`/memory` mostra o que está carregado.**
