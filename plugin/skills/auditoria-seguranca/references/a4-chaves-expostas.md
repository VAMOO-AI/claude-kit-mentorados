# auditoria-seguranca — A4, chaves expostas

Lido antes de rodar qualquer busca de segredo (A4).

## A4 — Chaves expostas

Quatro superfícies, e a quarta é a que quase ninguém varre. O que o comando imprime
entra na conversa, e dali no relatório e na issue: por isso nenhuma busca mostra o valor
inteiro. Sai `arquivo:linha`, o nome (a chave, a variável) e o tipo do token em rótulo
separado. Do valor, só um prefixo: até 12 caracteres sai só `…` (`${DB_PASS:-…}`), porque
qualquer pedaço de um valor curto é boa parte dele; acima disso, os 4 primeiros + `…`. Para
julgar um achado, abra o `arquivo:linha`.

```bash
command -v gitleaks && gitleaks detect --no-banner --redact -v   # HEAD + histórico, valor redigido
# LC_ALL=C e -a em todo grep: com byte fora de UTF-8 na linha (comentário em Latin-1), o grep
# do Linux e o do macOS calam a linha, e o default dela some. O python conta caractere, não byte.
# 2. default de segredo: os nomes de compose do v1 e do v2, helm, CI e scripts
#    ${VAR:-valor}, ${var:-valor} e ${var-valor}; todo literal do corpo sai mascarado, também o
#    que vem depois de uma referência interna (${A:-${B}literal}); ${A:-${B}} fica intacto
LC_ALL=C grep -arnE '\$\{[A-Za-z_][A-Za-z0-9_]*:?-[^}]+\}' docker-compose*.yml docker-compose*.yaml \
  compose.yml compose.yaml helm/ .github/ scripts/ 2>/dev/null | python3 -c '
import re
m = lambda v: "…" if len(v) <= 12 else v[:4] + "…"
REF = r"\$[A-Z_][A-Z0-9_]*(?![A-Za-z0-9_])"
lit = lambda g: g[0] if g[1] or not re.search(r"[A-Za-z0-9]", g[0]) else m(g[0])
def dflt(l):
    s = []
    def ph(g):
        s.append(g[0] if g[1] is None else "${" + g[1] + re.sub(r"(\0\d+\0|" + REF + r")|(?:(?!" + REF + r")[^\0])+", lit, g[2]) + "}")
        return "\0%d\0" % (len(s) - 1)
    while True:
        n = re.sub(r"\$\{(?:([A-Za-z_][A-Za-z0-9_]*:?-)([^{}]*)|[^{}]*)\}", ph, l)
        if n == l: break
        l = n
    volta = lambda t: re.sub(r"\0(\d+)\0", lambda g: volta(s[int(g[1])]), t)
    return volta(l)
for l in open(0, encoding="utf-8", errors="replace"): print(dflt(l.rstrip("\n")))'
# 3. atribuição com literal em config: a mesma chave da Fase 6 (pwd, sufixo no nome como em
#    AWS_SECRET_ACCESS_KEY, => e aspas opcionais); valor que é referência (${…}, process.) não
#    sai, mas o default com literal (${X:-valor}) sai: a busca 2 não varre config.yml nem .env
LC_ALL=C grep -arnoiE "(api[_-]?key|secret|token|passw(or)?d|pwd|senha|private[_-]?key)[A-Za-z0-9_]*['\"]?[[:space:]]*[:=>]{1,2}[[:space:]]*(['\"][^'\"]{8,}|[^'\"[:space:],;]{8,})" \
  --include='*.yml' --include='*.yaml' --include='*.env*' --include='*.md' . | LC_ALL=C grep -av node_modules \
  | python3 -c '
import re
m = lambda v: "…" if len(v) <= 12 else v[:4] + "…"
ref = ("$", "{", "(", "req.", "process.", "this.", "env.", "os.environ")
for l in open(0, encoding="utf-8", errors="replace"):
    g = re.match(r"(.*?:\d+:[^:=>]*[:=>]{1,2}\s*[\x27\"]?)(.*)$", l.rstrip("\n"))
    if g and (not g[2].startswith(ref) or re.match(r"\$\{[A-Za-z_][A-Za-z0-9_]*:?-", g[2])): print(g[1] + m(g[2]))'
# 4. o bundle já buildado (o segredo que "só existe no servidor" e foi pro browser): os
#    formatos da lista pads da Fase 6. O JWT sai com o `role` do payload, e só o de header
#    eyJhbGciOi (eyJ puro pega todo JSON em base64, como o source map inline); o sk-/rk-
#    genérico tem \b, senão "risk-…" de classe CSS vira chave. O -a lê binário (.asar) como
#    texto. Sem build no disco, não rode um: ver abaixo.
LC_ALL=C grep -arnoE "(sk-(proj|ant|svcacct|admin)-[A-Za-z0-9_-]{16,}|\b[rs]k-[A-Za-z0-9_-]{16,}|[rs]k_(live|test)_[A-Za-z0-9]{16,}|eyJhbGciOi[A-Za-z0-9._-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|SG\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{40,}|whsec_[A-Za-z0-9+/=]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|xapp-[A-Za-z0-9-]{10,}|glpat-[A-Za-z0-9_-]{20,}|sb_secret_[A-Za-z0-9_-]{16,}|sb[ps]_[A-Za-z0-9_-]{12,}|shpat_[A-Za-z0-9_-]{12,}|npm_[A-Za-z0-9]{36,}|hf_[A-Za-z0-9]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)" \
  dist/ .next/static/ 2>/dev/null | python3 -c '
import base64, json
m = lambda v: "…" if len(v) <= 12 else v[:4] + "…"
T = (("sk-proj-", "chave de projeto OpenAI"), ("sk-svcacct-", "chave de conta de serviço OpenAI"),
     ("sk-admin-", "chave admin OpenAI"), ("sk-ant-", "chave Anthropic"), ("sk-", "chave sk-"),
     ("rk-", "chave rk-"), ("whsec_", "chave de webhook Stripe"), ("AKIA", "chave AWS"),
     ("AIza", "chave de API do Google"), ("SG.", "chave SendGrid"), ("gh", "token do GitHub"),
     ("github_pat_", "token do GitHub"), ("xox", "token do Slack"), ("xapp-", "token do Slack"), ("glpat-", "token do GitLab"),
     ("sb", "token do Supabase"), ("shpat_", "token do Shopify"), ("npm_", "token do npm"),
     ("hf_", "token do Hugging Face"), ("-----", "bloco de chave privada"))
for l in open(0, encoding="utf-8", errors="replace"):
    if l.count(":") < 2: continue
    arq, lin, v = l.rstrip("\n").rsplit(":", 2)
    if v[:3] in ("sk_", "rk_"): tipo = "chave Stripe " + v[:v.find("_", 3) + 1]
    elif not v.startswith("eyJ"): tipo = next((t for p, t in T if v.startswith(p)), "formato da lista pads")
    else:
        p = (v.split(".") + [""])[1]
        try: tipo = "JWT role=" + str(json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))["role"])
        except Exception: tipo = "JWT role=?"
    print(arq + ":" + lin + ":" + m(v) + "  " + tipo)' | sort | uniq -c
```

JWT com `role=anon` no bundle é a anon key, pública por design; `role=service_role` é o
banco inteiro por cima da RLS.

**Sem build no disco, o build é pergunta, não passo da auditoria.** `npm run build`
executa o script de build do repo auditado, que esta auditoria trata como código não
confiável, e grava `dist/` (ou `.next/`) fora de `docs/security-audit/`. Pergunte com o
comando pronto e o que ele faz: *"Não há build no disco, então o bundle ficou sem varrer.
Posso rodar `npm run build` aqui? Ele executa o script de build do repo e grava `dist/` na
pasta do projeto; sem `node_modules/`, precisa antes de `npm ci`, que baixa as dependências
e roda os scripts de instalação delas."* Sem o ok, a alternativa read-only é ler os `.js`
que o domínio serve (ler produção pode). Sem nenhum dos dois, a `cobertura[]` diz que o
bundle ficou de fora:
`{ "categoria": "A4", "estado": "parcial", "medido": "bundle não varrido: sem build no disco e sem ok para o build" }`.

**Default público é achado, mesmo com a variável sobrescrita em produção hoje.**
`${JWT_SECRET:-supersecret}` é um segredo real esperando um deploy distraído. O
achado só fecha com **validação de startup** que aborta o boot com o valor
conhecido — a ausência dessa validação é parte do achado, não uma sugestão
extra.

Agrupe os defaults num achado por tema (todos os segredos do compose viram uma
issue só) para não gerar spam.
