# 08 · Perímetro e superfície exposta

Os sete pilares anteriores olham para dentro do app. Este olha de fora: **o que
responde na internet com o nome da empresa, e o que cada um desses hosts entrega
antes de qualquer login.**

O furo típico não está no app auditado — está no `n8n`, no Metabase, no Portainer
e no Evolution que subiram "pra testar", num subdomínio do domínio principal, sem
WAF, sem os headers e com a versão estampada na tela de login. O app passa na
auditoria e a empresa cai pelo painel do lado.

## Contrato

- [ ] **Existe inventário de hosts públicos** — todo subdomínio que responde, com
      dono, propósito e se é interno ou de cliente. Sem a lista, nada aqui é
      auditável.
- [ ] **Todo host público está atrás da borda** (CDN/WAF), não com o IP de origem
      no DNS. Origem alcançável direto = WAF decorativo.
- [ ] **Os 6 headers valem para todos os hosts**, não só para o app na Vercel. A
      configuração do pilar `01` cobre a Vercel; Traefik/Nginx/Cloudflare
      precisam da versão deles.
- [ ] **Painel de infraestrutura não fica em `login.<dominio-principal>`.**
      Serviço interno (n8n, Metabase, Portainer, Evolution, Grafana) mora em
      **outro domínio** e, quando o acesso é só do time, atrás de VPN ou de
      allowlist de IP.
- [ ] **Versão e tecnologia não são publicadas.** `X-Powered-By`, `Server` com
      versão, banner de login com número de release, `/version`, `/actuator`,
      `/_next/static` com sourcemap.
- [ ] **Endpoint de saúde detalhado exige autenticação.** `/health` responde
      vivo/morto para qualquer um; o que lista versão de dependência, host de
      banco, fila e estado de pool é dado de reconhecimento.
- [ ] **Repositório privado por padrão**, e a visibilidade é conferida — não
      lembrada. Repo público é decisão, com dono e data.
- [ ] **Autenticação tem limite de tentativa na borda** (ver pilar `04`, seção de
      força bruta).

## Como implementar

**Esconder não é proteger — mas reduz o alvo.** Mover o n8n para um segundo
domínio tira o painel do scan que enumera subdomínio do domínio principal. Isso
compra tempo, não segurança: o que **tranca** é VPN, allowlist de IP ou mTLS. Use
os dois, e nunca registre o primeiro como se fosse o segundo.

**Headers na borda (Cloudflare, Transform Rule / Response Header):** os mesmos
seis do pilar `01`. É o caminho para cobrir de uma vez host que não passa pela
Vercel.

**Serviço em VPS própria (n8n, Metabase, Portainer):** se o proxy for Traefik ou
Nginx, os mesmos seis headers precisam ser configurados **lá também** — a
configuração da Vercel não alcança esse host. E o painel de infraestrutura não
deveria estar na internet aberta: allowlist de IP ou uma rede privada (Tailscale,
Cloudflare Zero Trust) é o que tranca. Senha é o segundo fator, não o primeiro.

## Como provar

```bash
# 1. inventário: o que existe com este nome (fonte pública, sem tocar nos hosts)
curl -s "https://crt.sh/?q=%25.<dominio>&output=json" | python3 -c \
  'import json,sys;print("\n".join(sorted({n for r in json.load(sys.stdin) for n in r["name_value"].split(chr(10))})))'

# 2. cada host: headers, banner e versão (rode a lista inteira, não um host)
for h in app.<dominio> n8n.<outro-dominio> painel.<dominio>; do
  echo "== $h"; curl -sSI "https://$h" \
    | grep -iE 'strict-transport|content-security-policy|x-frame|x-content-type|referrer-policy|permissions-policy|server:|x-powered-by'
done

# 3. a origem está alcançável por fora da borda? (cabeçalho da CDN ausente = passou direto)
curl -sSI https://<host> | grep -iE 'cf-ray|x-vercel-id|server: cloudflare' || echo 'SEM borda na frente'

# 4. saúde detalhada aberta?
for p in /health /healthz /readyz /status /version /actuator/health /debug/vars; do
  printf '%-22s %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' https://<host>$p)"
done

# 5. visibilidade dos repos da org (o que está público é decisão, não acidente)
gh repo list <org> --json name,visibility --limit 200 | python3 -c \
  'import json,sys;[print(r["visibility"],r["name"]) for r in json.load(sys.stdin) if r["visibility"]!="PRIVATE"]'
```

`200` em `/version` ou em `/actuator/health` é achado. `403`/`404` é o esperado
para quem vem de fora.

## Armadilhas

| Sintoma | Causa real |
|---|---|
| "Está atrás do Cloudflare" e o ataque chegou mesmo assim | O IP de origem responde direto. Proxy só protege o que passa por ele — feche a origem por firewall |
| Headers certos no app e ausentes no painel | A configuração vive no `vercel.json`, e o painel não passa pela Vercel. Header é por host |
| Subdomínio esquecido de um projeto morto | Ninguém dá baixa em DNS. Entrada órfã ainda aponta para um host que sobe desatualizado — e para takeover se o serviço foi deletado |
| Painel "protegido por senha" invadido | Painel de infra na internet aberta é questão de tempo. Senha é o segundo fator, VPN é o primeiro |
| Auditoria de header passou e o scanner acusou | Testou `https://dominio` e o host real era `www.` (ou o inverso). Rode a lista, não um |
| Versão escondida e mesmo assim exploraram | Esconder banner atrasa scanner automatizado; não substitui atualizar. É redução de ruído, não patch |
