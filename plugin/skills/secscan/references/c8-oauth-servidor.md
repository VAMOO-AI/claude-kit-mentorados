<!-- secscan: lido na Fase 3 quando o app EMITE token OAuth (tem /authorize e /token próprios) -->

## App que é servidor OAuth (Fase 3)

Vale quando o próprio app emite código e token: servidor MCP com registro dinâmico de cliente,
"Entrar com <app>" para parceiros, API com `/authorize` e `/token` próprios. Login **com** um
provedor (Google, Supabase Auth) é cliente OAuth, e fica no `c2-nextjs-auth.md`.

O nome do arquivo não cria categoria: os achados daqui entram na C2 (autenticação e controle
de acesso) e, quando o problema é o segredo em si (código previsível, token guardado em
claro), na C7. Severidade pelo dano: código ou refresh reaproveitável por outro cliente é
`HIGH`; o resto, `MEDIUM` a `HIGH` conforme o que o token alcança.

Localize primeiro:

```bash
grep -rniE "(/authorize|/token|/register|/revoke)['\"/]|grant_type|code_verifier|code_challenge|refresh_token|redirect_uri" \
  --include='*.ts' --include='*.tsx' --include='*.js' --include='*.py' --include='*.sql' . \
  | grep -vE 'node_modules|\.next/|dist/' | head -80
```

Cada item abaixo diz o que conferir no código, e a fonte. "MUST" e "SHOULD" são do texto da
RFC; onde o kit pede mais que a RFC, o item diz.

### Código de autorização

- **Uso único, atômico.** Segundo uso do mesmo `code` é negado, e o servidor deveria revogar
  os tokens já emitidos com ele (RFC 6749 §4.1.2: MUST negar, SHOULD revogar "when possible").
  No código, a troca é um `UPDATE ... SET usado_em = now() WHERE code = $1 AND usado_em IS NULL
  RETURNING ...` (ou `DELETE ... RETURNING`) e só emite token se voltou linha. Ler, conferir e
  marcar em três passos deixa duas requisições simultâneas trocarem o mesmo código (o padrão
  da corrida está no `c4-concorrencia.md`).
- **Vida curta.** O código expira logo depois de emitido; a RFC recomenda no máximo 10 minutos
  (RFC 6749 §4.1.2). Procure o TTL e a comparação com `now()` na troca, não só na emissão.
- **Amarrado ao cliente e ao `redirect_uri`.** O código vale só para o `client_id` e o
  `redirect_uri` que o pediram (RFC 6749 §4.1.2). A troca confere os dois contra o que foi
  gravado com o código.

### PKCE

- **Obrigatório para cliente público** (RFC 9700 §2.1.1: "Public clients MUST use PKCE", e o
  servidor MUST suportar). Para cliente confidencial, RECOMMENDED. Servidor de MCP com DCR
  recebe cliente público: exija em todo fluxo.
- **Só `S256`** é política do kit, mais forte que a RFC: a RFC 9700 §2.1.1 diz SHOULD usar
  método que não expõe o verifier, e hoje o único é `S256`. Dois pontos fazem dela regra:
  sem `code_challenge_method` o padrão é `plain` (RFC 7636 §4.3), então requisição sem o
  método é recusada, não aceita como `plain`; e `plain` aceito deixa quem lê a URL de
  autorização trocar o código.
- **Sem downgrade.** `code_verifier` na troca de um código que nasceu sem `code_challenge` é
  recusado (RFC 9700 §4.8.2, MUST). Procure o ramo `if (code_challenge)` que pula a checagem.
- **O desafio é por transação.** `code_challenge` constante, ou reaproveitado, não protege
  (RFC 9700 §2.1.1: MUST ser específico da transação).

### `redirect_uri`

- **Igualdade exata de string** contra o valor registrado, com uma exceção: a porta em
  redirect de loopback de app nativo (RFC 9700 §2.1, MUST). `startsWith`, `includes`, regex,
  comparação só de host ou normalização antes de comparar são o achado.
- **Sem `http`** fora do loopback de app nativo (RFC 9700 §2.6, MUST NOT).
- **Loopback aceita qualquer porta** na requisição (RFC 8252 §7.3, MUST), e só a porta: o
  resto da URI é comparado exato. O literal de IP (`http://127.0.0.1:{porta}/...`) é o
  recomendado; `localhost` é NOT RECOMMENDED (RFC 8252 §8.3).

### Registro dinâmico de cliente (DCR)

- **`redirect_uris` é obrigatório** para fluxo com redirecionamento (RFC 7591 §5, MUST), e
  cada valor é de uma das formas que a RFC lista: site com TLS (`https://`), `http` no
  `localhost`, ou esquema próprio do app (`meuapp://`).
- **Allowlist de esquema** no registro, não blocklist: `https`, `http` só com host de
  loopback, e os esquemas próprios que o produto aceita. Esquema fora da lista recusa o
  registro. Validar só no `/authorize` deixa o cliente registrado com URI que nunca devia ter
  entrado.
- **Esquema próprio em notação de domínio reverso** (`com.exemplo.app:/callback`): o servidor
  SHOULD exigir, e, no mínimo, esquema próprio sem ponto SHOULD ser recusado (RFC 8252 §8.4).
  Esquema curto (`meuapp://`) colide com o de outro app instalado, que recebe o código.
- **Exibido ao usuário com cuidado.** `client_name`, `logo_uri` e `client_uri` vêm de quem
  registrou. A RFC 7591 §5 pede (SHOULD) conferir que `logo_uri`, `tos_uri`, `client_uri` e
  `policy_uri` têm o mesmo host e esquema dos `redirect_uris`.

### Refresh token

- **Amarrado ao cliente.** O servidor mantém e confere o vínculo entre o refresh e o cliente
  para quem foi emitido (RFC 6749 §10.4, MUST). Na troca, `client_id` da requisição contra o
  gravado com o token; refresh de um cliente usado por outro é `HIGH`.
- **Cliente público: sender-constrained ou rotação** (RFC 9700 §2.2.2, MUST). Na rotação,
  cada uso emite um refresh novo e invalida o anterior, mas guarda a relação entre eles.
  Quando um refresh **já invalidado** é apresentado de novo, o servidor revoga o refresh ativo
  daquele grant (RFC 9700 §2.2.2). Confira que o código distingue "não existe" de "existiu e
  foi rotacionado", porque só o segundo dispara a revogação.
- **Escopo preso ao consentido.** O refresh não amplia escopo nem resource server além do que
  o dono consentiu (RFC 9700 §2.2.2, MUST).

### Access token

- **Audiência conferida a cada requisição.** O resource server verifica, em toda requisição,
  se o token foi emitido para ele, e recusa se não (RFC 9700 §2.3, MUST). Token emitido para
  um recurso e aceito por outro é o achado.
- **Vínculo revalidado a cada requisição** é regra de autorização do app, não da RFC: membro
  removido da organização, ou papel rebaixado, não pode seguir usando o token até expirar.
  O handler carrega o principal e confere vínculo e papel no banco, como a C2 pede para
  qualquer rota.

### Fluxos que não se oferecem

- **Implicit** (`response_type=token`, ou qualquer resposta que põe access token na URL de
  retorno): o cliente SHOULD NOT usar (RFC 9700 §2.1.2). Servidor que ainda o aceita expõe o
  token na URL e no histórico, sem PKCE e sem como amarrar o token ao cliente. Procure
  `response_type` aceitando `token` no `/authorize`.
- **Senha do usuário direto no `/token`** (`grant_type=password`): MUST NOT ser usado
  (RFC 9700 §2.4). Ensina o usuário a digitar a senha fora do servidor de autorização e não
  funciona com 2FA. Servidor que aceita esse `grant_type` é o achado.

### Clickjacking no `/authorize`

- **O servidor de autorização MUST impedir clickjacking** (RFC 9700 §4.16), e SHOULD usar CSP
  nível 2 ou maior: `frame-ancestors` com a lista de origens permitidas (ou `'none'`), mais
  `X-Frame-Options` para navegador antigo. A CSP vale no `/authorize` e também nas páginas de
  login, consentimento e erro do fluxo.

```bash
curl -sSI "https://<host-de-preview>/authorize" | grep -iE 'content-security-policy|x-frame-options'
```

Só `curl -sSI` em preview do próprio projeto. Troca de código, reuso de refresh e registro
com URI maliciosa mandam requisição de escrita: são da fase dinâmica da baseline
(`skills/baseline/references/08-perimetro-dinamico.md`), nunca daqui.

Fontes: RFC 6749 (§4.1.2, §10.4), RFC 7636 (§4.3), RFC 7591 (§5), RFC 8252 (§7.3, §8.3,
§8.4) e RFC 9700 (§2.1, §2.1.1, §2.1.2, §2.2.2, §2.3, §2.4, §2.6, §4.8.2, §4.16), lidas no
rfc-editor.org em 27/11/2026.
