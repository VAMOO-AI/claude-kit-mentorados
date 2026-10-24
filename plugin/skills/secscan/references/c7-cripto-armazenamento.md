# C7 — Criptografia e armazenamento

> Referência da skill `secscan`, Fase 5. Leia ao avaliar C7.

Varredura no repo inteiro com `git grep`: ele lê **só arquivo rastreado**, o que já corta
`node_modules/`, `dist/` e cópias em `.claude/worktrees/` (sem isso cada achado aparece 2×).
Em compensação ele vê tudo que está rastreado, inclusive `.context/docs/`: exemplo de
comando em markdown é a principal fonte de falso positivo desta seção. Sem git:
`grep -rn --exclude-dir={node_modules,.git,dist,.claude}`. `git grep -E` é POSIX ERE: `\s`
não existe, escreva ` *`. Em toda a categoria o discriminante é o **destino**, nunca a
primitiva: `md5()` num fingerprint e `Math.random()` numa key de React não são finding.

**Hash de senha: hash rápido onde tinha que ter KDF.**

```bash
git grep -niE "createHash\(|hashlib\.(md5|sha1|sha256)|(md5|sha1|sha256) *\(|password_hash|senha_hash" -- src supabase scripts
git grep -lE "bcrypt|argon2|scrypt|pbkdf2|PBKDF2" -- package.json bun.lock requirements.txt go.sum Cargo.lock 2>/dev/null
```

- sha1/md5 todo mundo reconhece; **sha256 puro é o que passa batido**: não está quebrado,
  está *rápido*, e uma GPU faz bilhões de tentativas por segundo. Senha precisa de KDF
  lento, com salt por linha e custo ajustável: bcrypt, argon2id, scrypt ou PBKDF2 com
  iterações declaradas. Antes de escrever "não usa KDF", rode o segundo comando: pode estar
  em outra camada. Coluna `password_hash` em `public.*` é auth reimplementada, e aí é finding.

**Aleatoriedade: PRNG comum gerando coisa que autoriza.**

```bash
git grep -nE "Math\.random\(\)|\brandom\.random\(|\brand\(\)|uuid_generate_v1|uuidv1" -- src supabase scripts n8n
git grep -nE "crypto\.(randomUUID|getRandomValues)|randomBytes|secrets\.token_|gen_random_uuid|gen_random_bytes" -- src supabase
```

- Token de sessão, código de reset, convite, chave de API e slug público precisam de gerador
  criptográfico. `Math.random()` tem estado previsível; UUID v1 carrega MAC e horário, é
  *identificador*, não segredo. Só conta o que vira credencial, URL não listada ou
  identificador persistido.
- **Slug público**: a URL não listada é a única barreira, e só é segura enquanto for
  imprevisível. Confira quem *gera* o identificador, não quem o lê, e leia o CHECK que limita
  o formato: é ele que define a entropia real.

**Comparação de segredo sem tempo constante.**
`git grep -nE "(===|!==) *([A-Z][A-Z_]*(SECRET|_KEY)|expectedKey|expected|serviceRoleKey|cronSecret)" -- supabase/functions src | grep -v "__tests__\|\.test\."`

- `===` sobre HMAC, bearer ou chave de API para no primeiro byte diferente e vaza o prefixo
  pelo tempo de resposta. O certo: `crypto.subtle.verify`, `crypto.timingSafeEqual`,
  `hmac.compare_digest`. Severidade honesta: **LOW**, porque sobre HTTP o sinal se afoga no
  jitter de rede.

**Cripto simétrica: modo, IV e origem da chave.**
`git grep -niE "createCipher\(|aes-[0-9]+-ecb|MODE_ECB|createCipheriv\([^,]+, *[^,]+, *(''|\"\"|null|Buffer\.alloc)|pgp_sym_encrypt|encrypt\("`

- ECB (mesmo bloco de texto → mesmo cifrado, o padrão vaza), `createCipher` legado (deriva
  chave e IV de senha com MD5, sem salt), IV fixo ou reusado, chave no código, chave
  derivada de senha sem KDF.

**TLS desligado.**
`git grep -nE "NODE_TLS_REJECT_UNAUTHORIZED|rejectUnauthorized *: *false|verify *= *False|InsecureSkipVerify|curl .* -k( |$)|--insecure|sslmode=(disable|no-verify)"`

- Certificado não validado = interceptação silenciosa, e a variável de ambiente vale pro
  processo inteiro. O ` -k( |$)` evita casar `x-api-key` de exemplo de `curl` na doc.

**JWT: algoritmo, expiração e verificação.**
`git grep -nE "algorithm[s]? *: *\[?'?(none|HS256)|verify *: *false|ignoreExpiration|decode\(.*\{ *complete|jwt\.decode\("`

- `alg: none` aceita token sem assinatura; HS256 onde o emissor é externo deixa forjar com
  a chave pública como segredo; sem `exp` o token é eterno; `decode` no lugar de `verify` não
  valida nada. A `anon` do Supabase é pública por desenho; a `service_role` vazada vale até o
  `exp` dela e não expira sozinha, então o controle é rotação e ela nunca chegar ao
  navegador (Fase 1).

**Armazenamento: onde o segredo e o dado pessoal repousam.**

```bash
# segredo em coluna de texto
git grep -niE "(api_key|access_token|refresh_token|secret|password|webhook_url)[a-z_]* +(text|varchar|jsonb)" -- supabase/migrations
# credencial/dado pessoal no navegador e no log
git grep -nE "(localStorage|sessionStorage)\.setItem\(" -- src
git grep -nE "console\.(log|warn|error)\(.*(token|secret|senha|password|cpf|phone|email)" -- src supabase/functions | grep -v "__tests__"
# arquivo inteiro em base64 numa coluna
git grep -n "readAsDataURL\|toDataURL" -- src
```

```sql
-- estado real, com acesso ao banco: uma query por chamada
select jobname, command from cron.job where command ~ 'Bearer [A-Za-z0-9]{16,}';
select id, public from storage.buckets order by id;
```

- **Coluna em claro**: variável de plpgsql (`v_webhook_url TEXT;`), parâmetro de função e
  migration arquivada não contam; só coluna de tabela viva.
- **Cron**: comando de `cron.job` em texto claro é de onde se *recupera* um segredo perdido,
  ou seja, ler o banco é ler o segredo. A query tem que voltar vazia.
- **localStorage**: `access_token`, `refresh_token`, chave de serviço ou dado pessoal de
  cliente ali é legível por qualquer XSS e sobrevive ao logout.
- **Bucket público**: aqui o ângulo é o **conteúdo** do bucket; o flag e as policies são da
  Fase 2.
- **Arquivo em base64 numa coluna**: avatar de ~2 MB gravado como data URI numa tabela que
  outras queries embutem com `select('*')` e ORDER BY fez cada execução ordenar em disco,
  saturou o IO e derrubou o banco e o login junto. Base64 numa coluna envenena **toda**
  query que embute aquela tabela; o lugar do arquivo é o Storage, com teto de tamanho no
  upload.

**Gestão de chave: referência no lugar do valor.**
- Arquivo de env versionado ou fora do `.gitignore` guarda **ponteiro** ou **segredo vivo**?
  `find . -maxdepth 3 -name '.env*' -not -path './node_modules/*' | while read -r f; do git check-ignore -q "$f" || echo "NÃO IGNORADO: $f"; done`.
  `.env.example` cheio de placeholder não é finding: o discriminante é o valor ter cara de
  credencial.
- **Cópia viva esquecida**: `.env.bak`, `.env.old` dentro do projeto ficam fora do git e
  invisíveis pro gitleaks: `find . -maxdepth 2 -iname '.env*' \( -name '*bak*' -o -name '*old*' -o -name '*cop*' -o -name '*save*' \) 2>/dev/null`.
  Fora do projeto (Downloads, anexo de chat), aponte o lugar para a pessoa conferir à mão em
  vez de varrer a pasta pessoal.
- Rotação de segredo compartilhado: antes de rotacionar, liste quem mais consome a mesma
  credencial (outra function, outro repo, um cron no banco), senão a rotação derruba o
  consumidor esquecido.

C7 só sai como "nenhum problema identificado" se as varreduras de hash, aleatoriedade e
armazenamento rodaram de fato; sem elas o estado é **não medido**, não limpo.
