---
name: ship
description: >-
  Pipeline de release com portões de verificação. Use quando o usuário disser
  "ship", "/ship", "deploy", "manda pra prod", ou pedir pra fechar uma feature
  com commit + PR.

  Roda o fluxo completo com gates duros: typecheck, lint, testes,
  conventional-commit, push, PR via gh. Passos de deploy são opcionais e
  dependem do que o projeto realmente tem.

  Criada pra evitar as falhas recorrentes: dizer "passou" sem colar output
  fresco, commitar de diretório errado, e deployar coisa que não devia.
---

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

## 5. Deploy (condicional — adapte ao SEU projeto)

A maioria dos setups faz deploy automático quando o PR é mergeado (Vercel, Netlify,
Railway, etc. via integração com o GitHub). Nesse caso, **você não roda nada aqui** —
só confirma que o PR vai pro ambiente certo.

Se o seu projeto exige um comando de deploy manual:

- **Confirme `pwd` de novo antes de qualquer comando de deploy.** Diretório errado é destrutivo.
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
