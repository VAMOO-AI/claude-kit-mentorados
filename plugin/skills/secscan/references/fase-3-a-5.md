<!-- secscan: lido nas Fases 3, 4 e 5 (C1, webhooks, SCA, bump, vibe-coding, C7) -->

## Fase 3 — Next.js / React

- Rota de API / server action **sem checagem de auth** (`getUser`/sessão) antes de mutar/retornar dado.
- `service_role` ou secret importado num Client Component (vaza pro navegador).
- Endpoint retornando a linha inteira (hash de senha, campos internos) — falta filtrar colunas.
- Query de lista sem limite/paginação → DoS (e o teto de 1.000 linhas do Supabase cortando calado).
- CORS `Access-Control-Allow-Origin: *` em endpoint autenticado.

A validação de entrada (C4) tem fase própria, a 2.5.

### C1 — Injeção

Varredura do **repositório inteiro** em sete grupos: SQL dinâmico, command injection, XSS
(inclusive o HTML montado fora do framework: e-mail, PDF, bot), caminho e chave de Storage,
template e expressão (Code Node e `{{ }}` do n8n), SSRF, e injeção em log e em filtro
(`.or()` do supabase-js). Os comandos e o veredito de cada grupo estão em
[references/c1-injecao.md](c1-injecao.md): leia ao avaliar C1. O semgrep não
corrobora código de app neste stack, então **todo achado de C1 é `heuristic`**, e a linha C1
do checklist diz isso.

### Webhooks e n8n

- Nó Webhook **sem validação de header de auth ou segredo** na chamada que chega.
- Credencial escrita dentro de um Code Node em vez de ficar nas credenciais do n8n.
- Payload que chega usado sem validação (injeção em nó seguinte, SQL, shell). O schema é
  da Fase 2.5; aqui é a guarda de quem pode chamar.
- Tópico de push (ntfy) ou URL de webhook de chat com o token no caminho, em texto no git:
  a própria URL é a senha.

## Fase 4 — Dependências (SCA)

```bash
f=$(ls package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb 2>/dev/null | head -1)
[ -n "$f" ] && echo "lockfile: $f" \
  || echo "SEM LOCKFILE → C5 é 'não medido (lockfile ausente)', nunca 'nenhum problema identificado'"
test -f bun.lock && bun audit || true
test -f package-lock.json && npm audit || true
test -f pnpm-lock.yaml && pnpm audit || true
```
Com `yarn.lock` ou `bun.lockb`, o `npm audit` não serve: rode `yarn npm audit` (Yarn 2+) ou
`yarn audit` (Yarn 1), ou leia o `osv-scanner` da Fase 0.5, que entende `yarn.lock` (o
`bun.lockb` é binário e ele não lê: C5 fica `não medido` sem outro scanner).
O teste do lockfile é o resultado do `ls`, não o exit do pipe: o `head` sai 0 mesmo sem
nada para ler, e aí o aviso nunca saía. E ele não é decoração: os `|| true` são exatamente
o modo de falha que esta skill acusa nos outros — sem lockfile, tudo falha em silêncio e
C5 sairia limpa sem ter lido uma linha. `osv-scanner` tem o mesmo defeito: não lê `package.json` puro, roda, sai 0
e não mede nada (medido em 31/08/2026: zero achado, e as vulnerabilidades estavam lá).

Sinalize versão com CVE conhecido e **pacote alucinado** (importado mas não existe no registry — comum em código gerado por IA).
Pra achar o alucinado, `npm install --package-lock-only --ignore-scripts` falha com E404
nomeando o fantasma — rode numa **cópia** do `package.json` fora do repo (o comando escreve
lockfile, e você é read-only aqui). Efeito colateral que vai no relatório: essa mesma falha
impede gerar o lockfile, então um repo com dependência inventada deixa C5 cega também para
as CVEs reais. Reporte os dois fatos juntos. Complemento: liste os imports sem entrada no
lockfile e triague à mão (alias de caminho, módulo nativo e módulo virtual do bundler são
ruído).

### C5.2 — Subir versão é mudança de código (o PR de bump)

A Fase 4 olha o que **está** instalado. Esta parte olha a mudança que **troca** o
instalado: o PR mais fácil de aprovar sem ler, e o que meses depois vira "não mudei nada
e quebrou". A pergunta da triagem é uma só: **o que passou a rodar aqui que ninguém
escreveu?** Entra quando o escopo é uma branch/PR, ou quando o histórico recente mexeu
nas dependências:

```bash
git diff --stat origin/main...HEAD -- package.json package-lock.json pnpm-lock.yaml bun.lock
git log --oneline -5 -- package.json
git ls-files package-lock.json pnpm-lock.yaml bun.lock   # vazio com lockfile no disco = lockfile fora do git
```

- **Um pacote por PR** (ou um grupo pequeno e relacionado). Bump em lote quebra o build e
  esconde qual dos 14 pacotes quebrou, e o revert leva os 13 inocentes junto.
- **O que decide é o changelog, não o número.** Semver é promessa do mantenedor, não
  garantia: patch carrega mudança de comportamento com frequência. Em major, o PR diz
  **o que quebra** — "subiu de 4 para 5" não é descrição.
- **Testes verdes ANTES e DEPOIS**, com output colado. "Instalou" não é verificação. Se
  quase nenhum teste passa pelo que a dependência faz, **essa lacuna é o achado**: o
  teste vem antes do bump, senão o verde não prova nada.
- **O lockfile é o que de fato sobe.** Revise o diff dele, não só o do `package.json`;
  commite sempre; nunca edite à mão. Um bump direto arrasta dezenas de dependências
  indiretas, e é ali que mora o pacote que ninguém escolheu. `^4.2.0` no `package.json`
  aceita qualquer 4.x: sem lockfile no git, cada `npm install` pode montar outra árvore.
  No CI, a instalação tem que ser a que respeita o lockfile (`npm ci`,
  `pnpm install --frozen-lockfile`, `bun install --frozen-lockfile`); `npm install` no CI
  resolve as faixas de novo e testa uma árvore que ninguém revisou.
- **Dependência nova pede procedência**, não só versão: existe no registro (pacote
  alucinado é a Fase 4), quem mantém, quando foi o último commit, licença, quanto pesa no
  bundle. E a pergunta anterior a todas: **o que já está no projeto resolve isso?** Toda
  dependência é passivo.
- **`postinstall` é execução de código na sua máquina e no CI.** Em pacote novo ou em
  major, olhe os scripts de instalação antes de rodar; `--ignore-scripts` na primeira
  instalação é barato.

Reporte como achado de **C5** quando a mudança de dependência não tiver changelog lido,
testes verdes dos dois lados, lockfile revisado e commitado, ou quando o CI instalar com
`npm install`. Não é detalhe: é a via de supply chain que a Fase 4 não vê, porque na hora
do scan a versão nova já está instalada. No modo pedagógico, o caso contado passo a passo
está em [`docs/seguranca.md`](https://github.com/VAMOO-AI/claude-kit-mentorados/blob/main/docs/seguranca.md#atualizar-dependência-também-é-mudança-de-código).

## Fase 5 — Heurísticas de "vibe-coding"

Padrões que IA costuma gerar. Grep no projeto:
- Auth de mentira: `if (true)`, `next()` sem guard, `SKIP_AUTH`, `DEBUG` bypass.
- `eval` / `new Function` com input do usuário (`child_process.exec` é a C1.2).
- Comentário dizendo "seguro/production-ready" sem nenhum controle real atrás.

### C7 — Criptografia e armazenamento

Hash de senha sem KDF (sha256 puro é o que passa batido), gerador comum criando token ou
slug, comparação de segredo sem tempo constante, cripto simétrica com ECB ou IV fixo, TLS
desligado, JWT sem verificação, segredo e dado pessoal em repouso (coluna em claro, cron,
localStorage, arquivo em base64 numa coluna) e gestão de chave. Os comandos (`git grep`, só
arquivo rastreado) e os hits que não são finding estão em
[references/c7-cripto-armazenamento.md](c7-cripto-armazenamento.md): leia ao
avaliar C7. O discriminante é o **destino** do valor, nunca a primitiva. C7 só sai como
"nenhum problema identificado" se as varreduras de hash, aleatoriedade e armazenamento
rodaram de fato.
