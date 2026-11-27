# 08 · Domínio, e-mail e painel de hospedagem

Parte do pilar 08 (perímetro) que não passa pelo app: o que o DNS público diz do domínio, quem
pode mandar e-mail em nome dele, que CA pode emitir certificado para ele e quem cuida do painel
da hospedagem. O app pode estar todo certo e o domínio deixar qualquer um mandar e-mail como
`financeiro@<dominio>`, ou um `includeSubDomains` trancar o webmail no navegador por um ano.

Lido no AUDITAR, pilar 08, e no CONSTRUIR quando sobe domínio, caixa de e-mail ou painel novo.

## Contrato

- [ ] **Domínio que envia e-mail:** SPF lista só quem envia e termina em `-all`, com no máximo
      10 consultas de DNS (ver Como provar). DKIM assinando em **todo** remetente: caixa
      (Workspace, Microsoft 365), hospedagem e transacional. DMARC com `rua=` (para onde vão os
      relatórios), `sp=` para subdomínio e plano datado `p=none` → `quarantine` → `reject`.
- [ ] **Domínio que não envia** (o segundo domínio do painel, o domínio de campanha parado):
      `v=spf1 -all`, DMARC `p=reject` e MX nulo (`0 .`), para ninguém usar o nome dele.
- [ ] **CAA publicado com as CAs que emitem hoje** para cada host, mais `iodef`. Leia o emissor
      do certificado de cada host antes de publicar.
- [ ] **Sem registro `*` que ninguém usa.** Wildcard faz qualquer rótulo responder e deixa o
      inventário por resolução inútil.
- [ ] **HSTS `includeSubDomains` só com o inventário fechado** e TLS válido na 443 de todo
      subdomínio, painel e webmail inclusos (o header em si é do pilar 01).
- [ ] **Painel de hospedagem** (cPanel, WHM, webmail, Plesk, DirectAdmin) **tem dono
      declarado**. Em hospedagem compartilhada o dono do software é o provedor: o projeto
      responde por 2FA nas contas, pela versão conferida por ticket e por restringir as portas
      por IP onde o plano deixa. Onde não deixa, vira exceção aceita com `revisar_em`.

## Como implementar

**SPF:** um único registro TXT `v=spf1` por nome (dois registros invalidam os dois). Cada
remetente entra pelo `include:` que o próprio fornecedor documenta. Comece em `~all` só
enquanto o DMARC está em `p=none` e os relatórios ainda mostram remetente legítimo fora da
lista; com o `rua` limpo, troque para `-all`.

**DKIM:** a chave se gera no painel de cada remetente, que diz o seletor
(`<seletor>._domainkey.<dominio>`). Remetente sem DKIM só passa no DMARC pelo SPF, e o SPF
quebra em encaminhamento.

**DMARC:** `_dmarc.<dominio>` com `v=DMARC1; p=none; rua=mailto:<caixa-de-relatorio>; sp=none`
no primeiro dia, e no contrato a data de cada passo. `p=none` só monitora: falsificação passa.
O passo para `quarantine` e depois `reject` vem quando os relatórios só mostram remetentes
conhecidos alinhados.

**CAA:** um `issue` por CA que emite de fato (a borda da Vercel, do Cloudflare, o certificado
do painel da hospedagem podem ser CAs diferentes), `issuewild` se há certificado curinga, e
`iodef "mailto:<caixa>"`.

**Painel:** a versão do cPanel/WHM do servidor compartilhado se pergunta ao provedor, por
ticket, e o número do ticket vai para o contrato. 2FA se liga em cada conta do painel e do
webmail. Painel que o plano não deixa restringir por IP fica como exceção com `revisar_em`.

## Como provar

Só DNS público e handshake TLS, e **só nos nomes do próprio domínio**. O `cpanel.<dominio>`
costuma resolver para o servidor compartilhado do provedor, que é terceiro: nele vale o
handshake da 443 no nome do cliente, e nada mais. Varredura das portas do painel
(2082 a 2096) fica `não aplicável (servidor do provedor)`, e a versão vira pergunta por ticket.

```bash
dig +short TXT <dominio> | grep -i 'v=spf1'          # ~all ou ?all com DMARC p=none = falsificável
dig +short TXT _dmarc.<dominio>                      # p=none = só monitora; sem rua = ninguém lê
dig +short MX <dominio>                              # "0 ." = MX nulo (domínio que não recebe)
dig +short CAA <dominio>                             # vazio = qualquer CA emite
dig +short A nao-existe-$RANDOM.<dominio>            # qualquer resposta = wildcard
dig +short TXT <seletor>._domainkey.<dominio>        # o seletor sai do e-mail real (ver Armadilhas)
openssl s_client -connect <dominio>:443 -servername <dominio> </dev/null 2>/dev/null | openssl x509 -noout -issuer
for h in www mail webmail cpanel; do printf '%-8s ' "$h"; openssl s_client -connect "$h.<dominio>:443" -servername "$h.<dominio>" </dev/null 2>&1 | grep -m1 -E 'Verify return code|handshake failure|alert|connect:errno'; done
```

`Verify return code: 0 (ok)` em todo host da lista é a condição para `includeSubDomains`.
Código diferente de 0, `handshake failure` ou nome que não responde na 443 é o achado.

**Contar as 10 consultas do SPF.** O `dig` não soma. Cada `include:`, `a`, `mx`, `ptr`,
`exists:` e `redirect=` custa uma consulta, e os de dentro de cada `include` também contam:
abra cada um (`dig +short TXT <dominio-do-include>`) e some até o fim. Acima de 10 o SPF dá
`permerror`, e o DMARC trata como falha de SPF para todo e-mail.

## Armadilhas

| Sintoma | Causa real |
|---|---|
| "Não tem DKIM" porque `default._domainkey` não respondeu | Seletor não se enumera por DNS. A prova é o cabeçalho `DKIM-Signature: ... s=<seletor>; d=<dominio>` de um e-mail real de **cada** remetente, e o `dig` desse seletor. Seletor chutado sem resposta não prova ausência |
| Certificado parou de renovar depois do CAA | O CAA não listou a CA da borda (ou a do painel). Leia o emissor de cada host antes de publicar |
| Painel e webmail inacessíveis no navegador depois do HSTS | `includeSubDomains` com a 443 do `cpanel.`/`webmail.` falhando o handshake. O navegador recusa o host até o `max-age` vencer, e não há botão de "continuar mesmo assim" |
| Headers e WAF certos e o e-mail continua falsificável | A borda da Vercel e do Cloudflare cobre `www` e apex. MX, SPF e DMARC são DNS, e o host de e-mail está em outra máquina |
| Inventário de subdomínios com centenas de nomes que respondem | Registro `*` apontando para a borda: todo rótulo responde (`DEPLOYMENT_NOT_FOUND` na Vercel). Apague o wildcard que ninguém usa |
| SPF "certo" e e-mail legítimo caindo no spam | Mais de 10 consultas (`permerror`), dois registros `v=spf1` ou remetente novo fora do `include` |
| DMARC em `p=none` há um ano | Sem data no contrato, o passo para `quarantine` nunca vem. Cada passo tem data e dono |
