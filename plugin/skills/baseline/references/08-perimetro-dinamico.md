<!-- baseline: lido na fase dinâmica opcional do pilar 08, só quando a pessoa pede teste contra o app rodando -->

# 08 · Perímetro: fase dinâmica (requisição contra o app rodando)

O resto da baseline lê código, config e banco; o pilar 08 faz `curl -sSI` passivo nos hosts.
Esta fase **manda requisição** ao app: o scan passivo do ZAP e seis sondas pontuais. É opcional
e só roda quando a pessoa pede ("testa o preview", "roda o ZAP", "DAST"). O `collect.sh` não a
chama.

> Ponto de partida das sondas: as seções "Sinal rápido" das skills `hunt-*` de
> `elementalsouls/Claude-BugHunter` (MIT), destiladas em chave defensiva. A parte estática das
> mesmas classes está no secscan (`skills/secscan/references/c2-nextjs-auth.md`).

## Política de alvo (antes de qualquer requisição)

| Tipo de alvo | Pode | Condição |
|---|---|---|
| `preview` | ZAP + as seis sondas | Deploy de preview da Vercel **do próprio projeto** (o time de quem audita), listado no contrato |
| `staging` | ZAP + as seis sondas | Ambiente de staging **do próprio projeto**, listado no contrato |
| `cliente-autorizado` | ZAP sem formulário + sondas só de leitura (tabela abaixo) | Autorização por escrito do cliente registrada no `.context` do projeto, com o host no escopo e a data dentro da janela |
| produção (própria ou de cliente) | nada desta fase | O `curl -sSI` passivo do `08-perimetro.md` continua valendo; o resto, não |
| qualquer outro host | nada | Pare e diga à pessoa que o alvo está fora da política |

**Em ambiente de cliente nada escreve:** só `GET`, `HEAD` e `OPTIONS`, sem sessão autenticada.
Sonda que precisa de `POST` ou faz o servidor buscar URL é `não aplicável (alvo de cliente)`. O
ZAP roda com o corte de formulário da seção dele, provado pelo log de um servidor de teste.

### O porteiro: o alvo está no contrato?

O contrato (`.context/docs/baseline.md`) tem a seção `## Alvos dinâmicos`, uma linha por host ou
padrão (`*` vale um trecho de nome de host). O comando abaixo diz o tipo do alvo; `FORA` encerra a
fase.

```bash
ALVO="https://<projeto>-git-<branch>-<time>.vercel.app"
HOST="${ALVO#*://}"; HOST="${HOST%%/*}"
awk -F'|' -v h="$HOST" '
  /^## Alvos dinâmicos/ { f = 1; next } /^## / { f = 0 }
  f && NF > 3 {
    p = $2; t = $3; gsub(/^[ \t`]+|[ \t`]+$/, "", p); gsub(/^[ \t`]+|[ \t`]+$/, "", t)
    if (p == "" || p ~ /^-+$/ || p ~ /^Host/) next
    re = p; gsub(/\./, "\\.", re); gsub(/\*/, "[a-z0-9-]*", re)
    if (h ~ ("^" re "$")) { print "tipo=" t; achou = 1; exit }
  }
  END { if (!achou) print "tipo=FORA" }' .context/docs/baseline.md
```

Depois do tipo, a prova de que o alvo é do próprio projeto ou está autorizado:

- **`preview`:** `.vercel.app` prova que é Vercel, não de quem é. A URL vem do PR do próprio repo
  (`gh pr checks <n>`, o link do deploy) ou passa em `vercel inspect "$ALVO" --scope <time>` (sai
  ≠ 0 quando o deploy não é do time).
- **`staging`:** o host está na tabela de superfícies do contrato com o mesmo dono.
- **`cliente-autorizado`:** existe `.context/docs/security/autorizacao-dast.md` com quem autorizou
  (cargo), onde está o documento assinado ou o e-mail, os hosts no escopo e a janela
  (`inicio: YYYY-MM-DD`, `fim: YYYY-MM-DD`). Host fora da lista ou data fora da janela: pare.
  Acordo verbal não vale, vale o que está no `.context`.

### O preview responde, ou é a tela de login da Vercel?

Preview com Deployment Protection devolve `401` ou redireciona para `vercel.com`. O ZAP varre
essa tela, sai `0` e o relatório parece limpo: é o falso limpo mais provável desta fase.

O bypass é o segredo de "Protection Bypass for Automation" do projeto, enviado no header
`x-vercel-protection-bypass`. Ele não entra na conversa nem na linha de comando: quem audita grava
num arquivo fora do repo (`$HOME/.dast-alvo.conf`, `chmod 600`, `NOME=valor`, chaves
`VERCEL_BYPASS` e, só para preview/staging, `SESSAO_COOKIE` de um usuário de teste) e os comandos
leem de lá. O check abaixo pede a raiz sem e com o bypass:

```bash
ALVO="https://<alvo-do-porteiro>"
le_conf() { awk -v k="$1=" '{ sub(/^[ \t]+/, ""); sub(/^export[ \t]+/, "") }
  index($0, k) == 1 { v = substr($0, length(k) + 1); gsub(/^["\047]|["\047]\r?$/, "", v); print v }' \
  "$HOME/.dast-alvo.conf" 2>/dev/null; }
CAB="$(mktemp)"; chmod 600 "$CAB"; B="$(le_conf VERCEL_BYPASS)"
[ -n "$B" ] && printf 'header = "x-vercel-protection-bypass: %s"\n' "$B" > "$CAB"
curl -q -sS -o /dev/null --max-redirs 0 --max-time 20 \
  -w 'sem bypass: http=%{http_code} destino=%{redirect_url}\n' "$ALVO/"
[ -s "$CAB" ] && curl -q -sS -o /dev/null --max-redirs 0 --max-time 20 -K "$CAB" \
  -w 'com bypass: http=%{http_code} destino=%{redirect_url}\n' "$ALVO/"
rm -f "$CAB"
```

`401`, ou destino em `vercel.com`, sem bypass e sem `VERCEL_BYPASS`: **todas as linhas** ficam
`não medido (preview protegido)`. Com bypass, a linha "com bypass" tem que dar `2xx`; segredo
errado ou vencido cai no SSO de novo, e todas as linhas ficam `não medido (bypass recusado)`.

## ZAP baseline (scan passivo)

O `zap-baseline.py` roda o spider por um tempo, espera o scan passivo e não lança ataque. O
spider, porém, segue link por `GET` e, sem configuração, **envia formulário, inclusive `POST`**:
`spider.processform` e `spider.postform` nascem `true` (`SpiderParam.java` do
`zaproxy/zap-extensions`). As duas chaves do `-z` desligam isso **só com `--autooff`**: sem ele, o
script monta um plano do Automation Framework cujo job `spider` ignora o `-config`. Provado em
20/11/2026 com a 2.17.0 contra um servidor de teste com um `<form method="post">` na raiz:

| Opções | O que chegou no servidor |
|---|---|
| nenhuma | 6 `GET` + `POST /excluir` |
| só `-z` com as duas chaves | 6 `GET` + `POST /excluir` |
| só `--autooff` | 6 `GET` + `POST /excluir` |
| `--autooff` + `-z` | 6 `GET`, nenhum `POST` |

Os dois juntos são obrigatórios em qualquer alvo, e nenhuma sessão vai junto. Trocou a imagem,
refaça a prova antes da primeira rodada em cliente.

```bash
ALVO="https://<alvo-do-porteiro>"
HOST="${ALVO#*://}"; HOST="${HOST%%/*}"
rodar_zap() {
le_conf() { awk -v k="$1=" '{ sub(/^[ \t]+/, ""); sub(/^export[ \t]+/, "") }
  index($0, k) == 1 { v = substr($0, length(k) + 1); gsub(/^["\047]|["\047]\r?$/, "", v); print v }' \
  "$HOME/.dast-alvo.conf" 2>/dev/null; }
OUT="$HOME/.cache/baseline-$(basename "$PWD")/dinamico"; mkdir -p "$OUT"
IMG="ghcr.io/zaproxy/zaproxy:2.17.0@sha256:9624669db72f54d86c4b46a7064518bd9bf79d8c61a4c31befa9923489f328af"
AUTH=()
ZAP_AUTH_HEADER_VALUE="$(le_conf VERCEL_BYPASS)"; export ZAP_AUTH_HEADER_VALUE
[ -n "$ZAP_AUTH_HEADER_VALUE" ] && AUTH=(-e ZAP_AUTH_HEADER=x-vercel-protection-bypass
  -e ZAP_AUTH_HEADER_VALUE -e "ZAP_AUTH_HEADER_SITE=${HOST%%:*}")
docker run --rm -v "$OUT:/zap/wrk:rw" "${AUTH[@]}" \
  "$IMG" zap-baseline.py -t "$ALVO" -m 1 -T 10 -J zap.json -w zap.md --autooff \
  -z "-config spider.processform=false -config spider.postform=false"
echo "exit=$?"
}
rodar_zap
```

- **Imagem por digest, nunca `stable` nem `latest`.** Para atualizar: pegue o digest da tag de
  versão nova no `ghcr.io` e troque a tag e o digest juntos.
- **Saída em `$HOME/.cache`, fora do repo.** O relatório traz trecho de resposta do alvo. E o
  Colima só monta `$HOME` no container: com o `-v` apontando para `/tmp`, o ZAP recebe um
  diretório vazio do root e falha com `AccessDeniedException` ao gravar o relatório.
- `-e NOME` sem valor repassa a variável do shell: o segredo não aparece no `ps` nem no histórico.
  Sem `VERCEL_BYPASS`, nenhuma das três variáveis vai para o container. O `ZAP_AUTH_HEADER_SITE`
  vai sem a porta: com `host:porta` o ZAP não casa o site e manda as requisições sem o header
  (visto no log do servidor de teste).
- **Saída:** `0` sem alerta, `1` pelo menos um FAIL, `2` só WARN, `3` erro. Com o padrão, todo
  alerta é WARN.

**"Saiu 0" só vale como limpo se o ZAP viu o alvo.** Antes de escrever o estado, rode o leitor
abaixo. Ele lê o relatório JSON do ZAP (`site`, `@name`, `alerts`, `riskcode`), conferido contra
o relatório da rodada de prova.

```bash
python3 -I - "$OUT/zap.json" "$HOST" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); host = sys.argv[2]
sites = [s for s in d.get("site", []) if host in s.get("@name", "")]
if not sites:
    sys.exit(f"não medido: o relatório não tem o host {host}")
risco = {"3": "HIGH", "2": "MEDIUM", "1": "LOW", "0": "INFO"}
for s in sites:
    for a in s.get("alerts", []):
        print(risco.get(a.get("riskcode"), "?"), a.get("pluginid"), a.get("alert"), f"({a.get('count')} URLs)")
PY
```

Sem o host no JSON, o estado é `não medido (ZAP não alcançou o alvo)`. Alerta de header ausente
(CSP, HSTS, `X-Content-Type-Options`) é o mesmo achado do pilar 01: um finding só, com o
`Reconferir` de lá.

## Sondas pontuais

Cada sonda imprime status e tamanho; o corpo fica no disco e não vai para a conversa. Rode o
bloco inteiro de uma vez (o shell não guarda função de uma chamada para outra), com as rotas
lidas no código: rota que não existe deixa a sonda `não medido (sem rota)`, nunca limpa.

| Sonda | `preview`/`staging` | `cliente-autorizado` |
|---|---|---|
| 1 `x-middleware-subrequest` | sim | sim (`GET`) |
| 2 source map servido | sim | sim (`GET`) |
| 3 CORS refletido e `Origin: null` | sim | sim (`GET`) |
| 4 introspection do GraphQL | sim (`POST`) | só por `GET`; servidor que não aceita `GET`: `não aplicável (alvo de cliente)` |
| 5 CSRF com `Content-Type: text/plain` | sim, com usuário de teste | `não aplicável (alvo de cliente)` |
| 6 URL interna em fetch de preview | sim | `não aplicável (alvo de cliente)`: fazer o servidor buscar URL interna é ataque, não leitura |

```bash
ALVO="https://<alvo-do-porteiro>"; TIPO="preview"   # preview | staging | cliente-autorizado
ROTA_PROTEGIDA="/painel"          # protegida só pelo middleware/proxy (leia o matcher)
ROTA_API="/api/<rota-com-cookie>" # rota que lê a sessão
ROTA_GRAPHQL=""                   # vazio: tenta /graphql e /api/graphql
ROTA_MUTACAO=""                   # route handler que muda estado com cookie; vazio = não medido
CORPO_MUTACAO='{}'                # corpo válido da mutação, em dado de teste
ROTA_FETCH=""                     # ex.: /api/preview?url={URL}; vazio = não medido
le_conf() { awk -v k="$1=" '{ sub(/^[ \t]+/, ""); sub(/^export[ \t]+/, "") }
  index($0, k) == 1 { v = substr($0, length(k) + 1); gsub(/^["\047]|["\047]\r?$/, "", v); print v }' \
  "$HOME/.dast-alvo.conf" 2>/dev/null; }
CAB="$(mktemp)"; chmod 600 "$CAB"; B="$(le_conf VERCEL_BYPASS)"
[ -n "$B" ] && printf 'header = "x-vercel-protection-bypass: %s"\n' "$B" >> "$CAB"
C() { curl -q -sS --noproxy '*' --max-redirs 0 --max-time 20 -K "$CAB" "$@"; }
CORPO="$(mktemp)"

echo "== 1 x-middleware-subrequest"
sem="$(C -o /dev/null -w '%{http_code}' "$ALVO$ROTA_PROTEGIDA")"
for v in middleware src/middleware middleware:middleware:middleware:middleware:middleware \
         src/middleware:src/middleware:src/middleware:src/middleware:src/middleware; do
  echo "sem=$sem com[$v]=$(C -o /dev/null -w '%{http_code}' -H "x-middleware-subrequest: $v" "$ALVO$ROTA_PROTEGIDA")"
done

echo "== 2 source map"
C -o "$CORPO" "$ALVO/"
for js in $(grep -oE '/(_next/static|assets)/[^"'"'"' ?#]+\.js' "$CORPO" | sort -u | head -3); do
  r="$(C -o "$CORPO.map" -w '%{http_code} %{content_type}' "$ALVO$js.map")"
  echo "$js.map $r sources=$(grep -c '"sources"' "$CORPO.map")"
done

echo "== 3 CORS"
for o in https://exemplo-nao-confiavel.test null; do
  echo "Origin=$o: $(C -o /dev/null -D - -H "Origin: $o" "$ALVO$ROTA_API" \
    | grep -iE '^access-control-allow-(origin|credentials)' | tr -d '\r' | tr '\n' ' ')"
done

echo "== 4 GraphQL"
for g in ${ROTA_GRAPHQL:-/graphql /api/graphql}; do
  if [ "$TIPO" = cliente-autorizado ]; then
    r="$(C -o "$CORPO" -w '%{http_code}' "$ALVO$g?query=%7B__schema%7BqueryType%7Bname%7D%7D%7D")"
  else
    r="$(C -o "$CORPO" -w '%{http_code}' -H 'Content-Type: application/json' \
      --data '{"query":"{__schema{queryType{name}}}"}' "$ALVO$g")"
  fi
  echo "$g http=$r schema=$(grep -c '__schema' "$CORPO") sugestao=$(grep -ci 'did you mean' "$CORPO")"
done

if [ "$TIPO" != cliente-autorizado ]; then
  S="$(le_conf SESSAO_COOKIE)"
  echo "== 5 CSRF"
  if [ -n "$ROTA_MUTACAO" ] && [ -n "$S" ]; then
    printf 'header = "Cookie: %s"\n' "$S" >> "$CAB"
    echo "controle json+mesma-origem: $(C -o /dev/null -w '%{http_code}' -X POST -H "Origin: $ALVO" \
      -H 'Content-Type: application/json' --data "$CORPO_MUTACAO" "$ALVO$ROTA_MUTACAO")"
    echo "text/plain: $(C -o /dev/null -w '%{http_code}' -X POST -H "Origin: $ALVO" \
      -H 'Content-Type: text/plain' --data "$CORPO_MUTACAO" "$ALVO$ROTA_MUTACAO")"
    echo "origem de terceiro: $(C -o /dev/null -w '%{http_code}' -X POST -H 'Origin: https://exemplo-nao-confiavel.test' \
      -H 'Content-Type: application/json' --data "$CORPO_MUTACAO" "$ALVO$ROTA_MUTACAO")"
  else
    echo "não medido (sem ROTA_MUTACAO ou sem SESSAO_COOKIE de teste)"
  fi
  echo "== 6 URL interna"
  if [ -n "$ROTA_FETCH" ]; then
    for u in https://example.com/ http://169.254.169.254/latest/meta-data/ http://127.0.0.1/ \
             'http://[::1]/' http://0x7f000001/; do
      q="$(python3 -I -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$u")"
      echo "$u $(C -o /dev/null -w 'http=%{http_code} t=%{time_total}s' "$ALVO${ROTA_FETCH/\{URL\}/$q}")"
    done
  else
    echo "não medido (sem ROTA_FETCH)"
  fi
fi
rm -f "$CAB" "$CORPO" "$CORPO.map"
```

### Como ler cada sonda

1. **`x-middleware-subrequest`** (CVE-2025-29927, GHSA-f82v-jwr5-mffw). O valor que funciona muda
   com a versão: `middleware` (ou `src/middleware`) até a 13.1, e o nome repetido cinco vezes da
   13.2 em diante, por isso as quatro variantes. Achado `HIGH` quando `sem` é `3xx`, `401` ou `403`
   e alguma variante dá `200`. `sem=200` quer dizer que a rota não está protegida para quem chega
   sem sessão: `não medido (rota não é protegida pelo middleware)`, escolha outra rota.
2. **Source map.** App Router não tem `main.js`: o bloco pega chunks reais do HTML. Achado `MEDIUM`
   (pilar 01) só com `200` **e** `sources>=1`. SPA com fallback devolve o `index.html` com `200`
   para qualquer caminho: `200` sem `sources` não é achado. Nenhum chunk no HTML:
   `não medido (HTML sem chunk)`.
3. **CORS.** `access-control-allow-origin` igual à origem enviada (ou `null`) **com**
   `access-control-allow-credentials: true`: `HIGH`. Refletido sem credencial: `LOW`. `*` sem
   credencial é normal em rota pública, e no PostgREST do Supabase é o padrão (quem controla é a
   RLS): não é achado.
4. **GraphQL.** `schema>=1` é introspection aberta: `LOW` a `MEDIUM`, conforme o que o schema
   mostra. `sugestao>=1` com introspection fechada é `LOW`. As rotas dando `404`:
   `não aplicável (sem GraphQL)`. O `/graphql/v1` do Supabase mostra o schema conforme os grants:
   é assunto do pilar 02, não daqui.
5. **CSRF.** Só vale se o **controle** (JSON, mesma origem) deu `2xx`: sem isso o `4xx` dos outros
   pode ser só o corpo inválido, e o estado é `não medido (controle falhou)`. `text/plain` ou origem
   de terceiro com `2xx`: `MEDIUM`; `HIGH` em ação de conta. As três chamadas executam a mutação:
   use usuário e dado de teste, e uma rota de efeito reversível.
6. **URL interna.** Só vale se o **controle** (`https://example.com/`) deu `2xx`. URL interna com
   `2xx`: `HIGH`. `400`, `403` ou `422` rápido é a validação recusando, o esperado. `5xx` ou tempo
   perto do `--max-time` quer dizer que o servidor tentou buscar e só a rede impediu: `MEDIUM`
   (validação ausente).

## Estado no relatório

A tabela da fase dinâmica tem **sempre as sete linhas** (ZAP + as seis sondas), nos mesmos estados
do secscan:

| Estado | Quando | No `findings.json` |
|---|---|---|
| `N achado(s)` | a leitura acima fechou em achado | `nao_conforme` |
| `nenhum problema identificado` | a sonda rodou, o controle passou e nada fechou | `conforme` |
| `não medido (<motivo>)` | sem rota, preview protegido, controle falhou, ZAP sem o host, Docker ausente | `nao_medido` com o motivo |
| `não aplicável (<motivo>)` | alvo de cliente para as sondas 5 e 6, sem GraphQL | fora da contagem, com o motivo |

Cada achado sai no formato de finding da baseline (`fase2-julgar.md`), com pilar `08`, a sonda
como `Reconferir` e o `HIGH` passando pelo juiz. O que vai em evidência é a requisição nomeada
(método, rota, header, status), nunca o corpo nem o segredo.

## Depois: strix (documentado, não implementado)

O [strix](https://github.com/usestrix/strix) é o passo seguinte, com agente que explora o app. Ele
não entra no kit agora, por quatro motivos que valem para qualquer rodada manual:

- O modo white-box monta o diretório do código **gravável** e o agente edita os arquivos reais:
  rode só numa cópia descartável do repo, nunca no clone de trabalho.
- O código inteiro vai para o provedor de LLM configurado: só Anthropic, e só repo interno do
  próprio time, nunca código de cliente.
- A telemetria vem ligada: `STRIX_TELEMETRY=0` antes de rodar.
- O modo deep valida o achado atacando: mesma política desta página, só `preview`/`staging` do
  próprio projeto.

Instalação e execução ficam para quando ele entrar no kit, com versão fixa.
