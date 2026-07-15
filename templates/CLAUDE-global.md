# <SEU NOME> — Diretivas Globais

> Este arquivo fica em `~/.claude/CLAUDE.md` e vale para TODOS os seus projetos.
> Edite os trechos `<entre-colchetes>` com os seus dados. Apague o que não usar.

## Quem sou
<Uma a três linhas: o que você faz, sua stack principal, como prefere ser respondido.>
Exemplo: "Estudante de dev fullstack (HTML/CSS/JS, aprendendo React + Supabase).
Responda em PT-BR, direto, e explique o porquê quando o assunto for novo pra mim."

## Roteamento de skills (a situação → a skill que carrega o processo)
Uma **skill** é um passo-a-passo que o Claude carrega só quando precisa, em vez
de deixar tudo escrito aqui (o que gastaria contexto toda sessão). A regra:
este arquivo guarda **o princípio**; o **como-fazer detalhado** mora na skill.
Quando a situação abaixo aparecer, o Claude deve carregar a skill antes de agir:

| Situação | Skill |
|---|---|
| Implementação GRANDE (vários sistemas / schema / algo irreversível) que vale fechar o plano antes de codar | `grilling` — o Claude aciona ao detectar; você dispara na mão com `/grill-me` |
| Plano vago **e** o projeto tem pasta `.context/` | `grill-with-docs` (interroga ancorado na doc do projeto) |
| Feature nova / corrigir bug | TDD: escreva o teste que FALHA primeiro (regra abaixo) |
| Bug / comportamento estranho | investigue a causa raiz e reproduza o bug antes de corrigir |
| Antes de dizer "pronto" | `verify` + `verificacao` |
| "deploy" / "manda pra prod" | `ship` |
| Dúvida de doc / API / versão de lib | `find-docs` |
| Mexer em vários arquivos independentes ao mesmo tempo | `orquestracao` |
| Vários terminais no mesmo projeto / worktree | `worktrees` |
| Checar segurança do código (scan local) | `secscan` |

## Modos de operação (detecte e ajuste)
- **EXECUTE** (default): tarefa pequena, fix, ajuste mecânico. Output curto, direto ao código. Se eu disser "sim/faz/manda" → executa, não repete o plano.
- **EXPLAIN** (quando eu falar "explica" / "modo aprendizado"): o PORQUÊ antes do COMO, comentários didáticos, link pra documentação oficial, 1-2 alternativas com tradeoffs.
- **MENTOR** (quando eu falar "modo aula"): passo a passo, sem atalhos, raciocínio antes do código, sem jargão não-explicado, código simples > código elegante.

## Proteção de escopo (OBRIGATÓRIO)
- Só modifique o que foi explicitamente pedido e combinado.
- Fora do escopo? PEÇA AUTORIZAÇÃO antes de tocar.
- Instrução vaga → pergunte (uma pergunta objetiva). Não assuma. (Implementação grande e ainda em aberto → `grilling`.)
- "sim", "faz", "manda" → execute. Não repita o plano.
- Antes de mudança arriscada: ofereça um checkpoint ("quer que eu salve o estado antes?").
- **Operações destrutivas exigem confirmação explícita** a cada vez (mesmo que a sessão já tenha autorizado algo parecido): apagar/sobrescrever arquivo existente, `DROP`/`ALTER TABLE`, `git push --force`, `reset --hard`, deletar branch compartilhada, mexer em credenciais. Autorizar uma não autoriza a próxima.

## Alvo confirmado antes de implementar (Target Lock)
Antes de mexer em vários arquivos: confirme o alvo exato (qual rota / tabela / função) e uma frase de comportamento por arquivo. Liste os arquivos que vai tocar e espere meu "go". Ambiguidade real → pergunte.
Exceção: fix em 1 arquivo que eu já apontei, typo, edição local óbvia.

## Verificação (PROIBIDO pular — casos detalhados na skill `verificacao`)
- Antes de dizer "pronto", rode o type-checker / linter do projeto (ex.: `npx tsc --noEmit`, `npx eslint .`). Sem ferramenta configurada → diga isso explicitamente.
- **Verify, don't claim**: NUNCA diga "passou / limpo / funciona" sem colar o output REAL do comando na mesma resposta, rodado agora nesta sessão. Não conseguiu rodar (sandbox/permissão) → diga "não executado" + liste os comandos que faltam.
- **"Pronto" é o caminho do usuário, não só o type-check.** Passar `tsc`/`eslint` não quer dizer "funciona". Antes de dizer pronto, **rode o app e faça o que o usuário faria**: clique o botão, envie o formulário, veja se salvou. Não deu pra rodar → diga "não testei na prática" + o passo manual que falta.
- **Mexeu na tela** (componente / página / CSS)? Abra o app e **olhe** (print/screenshot). Type-check não pega layout quebrado, blur, nem botão que não faz nada ao clicar.
- Fix em fluxo com ramos (if/else, texto vs áudio, feliz vs erro) → teste TODOS os ramos, não só um: consertar um pode quebrar o irmão. (Detalhes e exemplos em `verificacao`.)
- Depois de um fix: explique a causa raiz e como evitar esse tipo de bug de novo. Releia o que mudou antes de reportar.

## TDD (test-driven) para feature e bugfix
Mudando comportamento / feature nova / corrigindo bug: escreva o teste que FALHA primeiro, depois implemente até passar.
Bug: o teste captura a condição exata do bug (vermelho antes, verde depois).

## Secrets e variáveis de ambiente (REGRA DE OURO)
- `.env` / `.env.local` NUNCA vai pro git. Devem estar no `.gitignore`. Se vazou: troque todas as chaves na hora.
- `.env.example` SEMPRE commitado: lista as CHAVES sem os valores, documentando o que precisa pra rodar o projeto.
- Nunca mande secrets por WhatsApp/email/cloud. Pegue os valores direto no painel do serviço (Supabase, Vercel, etc.).
- Nunca cole uma chave secreta dentro de código nem no chat sem necessidade.

## Disciplina de trabalho
- Causa raiz: se 2 tentativas superficiais não resolveram, vá fundo (quem chama → o que é chamado → os dados → o banco). "Estamos em círculos" → pare, releia tudo de cima, repense do zero.
- Rename / refactor: faça um grep separado por chamadas, tipos, strings, imports e testes antes de apagar qualquer coisa. Nunca delete arquivo sem checar quem usa.
- Código apontado como referência: estude e copie o padrão exatamente.
- Trabalhe com dados reais. Sem o erro/print real, peça — não invente o output.
- Código humano, sem comentário robótico. Não over-engineer, não construa pra cenário imaginário.
- Quando fizer sentido, apresente 2 visões (perfeccionista vs pragmático) e me deixe decidir.

## Git / GitHub
- Conventional Commits: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`.
- Trabalhe em branch (`feat/nome`, `fix/nome`), nunca direto na `main`. O kit instala um hook que **bloqueia `git commit` na `main`/`master`** pra te proteger desse erro clássico. Se algum dia precisar mesmo commitar na main de propósito, rode o comando com `HOTFIX_MAIN=1` na frente.
- Antes de marcar como pronto: o type-checker e os testes passam (com output colado).
- `git add` só nos arquivos que você mexeu (nunca `git add -A`/`.`). **Vários terminais no mesmo projeto** (staging e branch são compartilhados) → skill `worktrees`.

## dotcontext (memória do projeto)
- O MCP `dotcontext` está ativo (instalado pelo kit). Em projeto novo, na 1ª sessão: peça **"init the context"**.
- Toda documentação nova vai em `./.context/docs/`. O `AGENTS.md` na raiz do projeto é o ponto de partida que Claude/Codex/Cursor leem.
- `.context/` é a fonte única de contexto — não duplique informação espalhada.

## Subagentes
Regras de como sub-agentes devem se comportar estão em `~/.claude/agents.md`. Resumo: subagentes são read-only por padrão (exploração), Edit/Write acontece na conversa principal, e ninguém afirma "passou" sem rodar. Pra disparar vários em paralelo (>5 arquivos independentes) → skill `orquestracao`.
