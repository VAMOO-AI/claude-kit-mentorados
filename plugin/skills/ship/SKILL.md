---
name: ship
description: >-
  Pipeline de release com portões de verificação. Use quando o usuário disser
  "ship", "/ship", "deploy", "manda pra prod", ou pedir pra fechar uma feature
  com commit + PR. Roda o fluxo completo com gates duros: typecheck, lint,
  testes, conventional-commit, push, PR via gh; passos de deploy dependem do que
  o projeto tem. Criada contra as falhas recorrentes: dizer "passou" sem output
  fresco, commitar do diretório errado, deployar o que não devia.
---

> Derivada de `claude-config-team/skills/ship`. Ao divergir de propósito, diga aqui o quê e por quê.

# /ship — Pipeline de Release

Rode os passos **na ordem**, sequencialmente. **Nunca pule um portão de verificação.**
Cole o output real do comando antes de qualquer afirmação de sucesso — nunca diga
"passou", "limpo" ou "pronto" sem mostrar o output na mesma mensagem.

## 0. Pré-voo (OBRIGATÓRIO)

```bash
pwd                            # confirma a raiz do projeto
git status                     # confirma working tree limpo-ish
git branch --show-current      # confirma a branch
git rev-parse --show-toplevel  # raiz absoluta do repo
```

Se `pwd` não for a raiz do projeto, **PARE** e pergunte. Não faça `cd` pra um caminho chutado.

Nunca deploye/commite de `main`/`master` se o trabalho devia estar em feature branch.

Detecte o que o projeto realmente tem (decide quais passos rodam):

```bash
test -f tsconfig.json && echo "TEM_TS"
test -f package.json && grep -E '"(lint|test|build)"' package.json || true
```

## 1. Verificar (OBRIGATÓRIO — cole o output)

Rode cada comando e cole o output real. Se algum falhar, **PARE e corrija a causa raiz** —
não "deploye mesmo assim".

```bash
npx tsc --noEmit                  # se TEM_TS
npx eslint . --quiet              # se eslint configurado
npm test --silent || npm run test # se existe script de teste
```

Se um comando não está configurado, diga explicitamente: "sem config de eslint — pulado".
Nunca afirme que um gate passou se ele não rodou.

## 2. Preparar e revisar

```bash
git status
git diff --stat
git diff           # revise o que está REALMENTE indo no commit
```

**Adicione arquivos por nome.** Não use `git add -A` nem `git add .` — risco de commitar
`.env`, secrets ou arquivos locais soltos.

## 3. Commit (conventional)

Formate a mensagem como `<tipo>(<escopo>): <assunto>` — siga o estilo do repo
(`git log --oneline -10` pra confirmar). Use HEREDOC pra mensagens multi-linha.

Tipos: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `perf`.

Nunca use `--amend` depois de hook falhar (o commit falho não aconteceu — amend reescreveria
o commit *anterior*). Corrija, re-stage, crie um commit novo.

## 4. Push e abrir PR

```bash
git push -u origin "$(git branch --show-current)"
gh pr create --title "..." --body "$(cat <<'EOF'
## Resumo
- ...

## Plano de teste
- [x] tsc --noEmit
- [x] eslint
- [x] npm test
- [ ] smoke test manual no preview

EOF
)"
```

Capture a URL do PR.

**Esperando o CI sem torrar contexto:** rode a espera como comando de background
(`run_in_background`), nunca como monitor de stream:

```bash
gh pr checks <n> --watch --fail-fast > /tmp/ci-<n>.log 2>&1
```

`--watch` **redesenha a tabela inteira** a cada poucos segundos. Num monitor de
eventos, cada redesenho acorda a sessão e faz reler a conversa toda — dezenas de
despertares sem uma linha de informação nova. Em background você recebe **uma**
notificação, no fim, e `--fail-fast` aborta no primeiro check obrigatório vermelho.

### O verde é de um SHA — e `--admin` não é um atalho para ele

"CI verde basta" quer dizer verde **do commit que vai para a main**, não do anterior.
Empurrou qualquer coisa depois do último `gh pr checks`? O gate reabre, mesmo que o diff novo
seja um comentário: a garantia é sobre o SHA que rodou, não sobre a sua leitura do diff.

E `gh pr merge --admin` não substitui a espera — ele existe para check obrigatório quebrado ou
inexistente, com autorização de quem manda no repositório, não para pular fila de runner.

Isto está escrito porque falhou de verdade. Num cenário de pressão medido em 05/09/2026 (o
único diff do commit era um comentário, a fila do runner era de 40 minutos, o cliente estava
numa tela compartilhada), o agente **sem** esta skill mergeou em 2 de 2 execuções, e **com**
ela ainda errava 1 em 3, argumentando:

> "O diff é um comentário — não altera nenhum caminho de execução, então o verde do commit
> anterior continua válido para o código que vai para a main."

> "`--admin` com registro explícito do motivo preserva 'self-merge livre' sem fingir que o
> pipeline rodou, e mantém rollback trivial."

As duas soam responsáveis e erram pelo mesmo motivo: trocam a evidência (um run verde naquele
SHA) por uma inferência sobre o diff. Comentário mal fechado quebra parser; `//` dentro de
string muda comportamento; e o CI roda lint e formatação, que reprovam arquivo por causa de
comentário. Se o diff bastasse como prova, o CI não precisaria existir.

**Quando a espera é cara de verdade**, diga o tempo real a quem pediu e devolva a decisão. Uma
janela com cliente é decisão de negócio dele — não uma leitura técnica que você faz sozinho
sob pressão.

## 5. Deploy (condicional — adapte ao SEU projeto)

A maioria dos setups faz deploy automático quando o PR é mergeado (Vercel, Netlify,
Railway, etc. via integração com o GitHub). Nesse caso, **você não roda nada aqui** —
só confirma que o PR vai pro ambiente certo.

Se o seu projeto exige um comando de deploy manual:

- **Confirme `pwd` de novo antes de qualquer comando de deploy.** Diretório errado é destrutivo.
- **Diff toca `supabase/migrations/` (ou qualquer DDL)?** Passe pela checklist "Migration que não derruba produção" da skill `baseline` (`references/02-banco.md`) antes de aplicar: NOT NULL só depois do backfill, índice em tabela viva com CONCURRENTLY, DROP/RENAME só depois do deploy que parou de usar. Migration que reprova num item não sobe inteira; vira duas ou três.
- **Migração de banco contra produção é destrutiva** — pergunte ao usuário antes de aplicar.
- Rode o comando de deploy do seu projeto só depois dos gates passarem.

> Preencha aqui o comando de deploy do seu stack quando souber qual é. Enquanto não
> houver, este passo é "deploy automático no merge — nada a rodar".

## 6. Relatório final

```
PR:      <url>
Preview: <url de preview, se houver>
Gates:
  - tsc:    pass | fail | skipped
  - eslint: pass | fail | skipped
  - tests:  pass | fail | skipped
```

## Regras duras

- **Verify, don't claim.** Todo "pass" tem output colado na mesma mensagem.
- **Sem `--no-verify`** pra pular hooks, a menos que o usuário peça explicitamente.
- **Nunca force-push em main/master.**
- **Um commit por mudança lógica.** Não junte refactor + feature no mesmo commit.
- **Diretório errado é destrutivo** — confirme `pwd` antes de qualquer deploy. Sempre.
