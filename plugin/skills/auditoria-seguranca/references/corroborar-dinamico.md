# auditoria-seguranca — corroborar com requisição, sem escrever no cliente

Lido quando um achado já está `lido` e você quer subir para `corroborado`. Vem depois da
leitura das categorias e antes da Fase 5. A regra que manda aqui é a de ferro: **ler pode,
escrever nunca** no ambiente do cliente.

## Quando usar

- O achado está `lido`: você abriu o caminho inteiro e ele fecha. Falta uma fonte fora da sua
  leitura. Achado `padrao` volta para a leitura primeiro; requisição não substitui abrir o arquivo.
- O que vai em `fonte` é **a requisição nomeada**: método, rota, papel de quem pediu, o que voltou.
  Nunca o token, a key nem o corpo com dado do cliente. Exemplo:
  `"fonte": "GET /api/pedidos/{id} como usuário A (tenant 1): próprio 200 812 B; vítima (tenant 2) 200 790 B com o id dela no corpo; id inexistente 404"`.
- Token não entra na conversa. Quem audita gera o token no terminal dele e o deixa num arquivo
  fora do repo (`chmod 600`, `$HOME/.matriz-auditoria.conf`, formato `NOME=valor`). Os comandos
  abaixo leem dali sem ecoar. Você nunca pede para colar. Extensão `.conf`, não `.env`: o guard de
  segredo do kit pergunta antes de vários comandos que citam `*.env`, e o fluxo pararia nele.
- Não houve requisição limpa? O achado continua `lido`, ou vira `a_validar` com o
  `plano_validacao` desta página. Inconclusivo não sobe evidência.

## IDOR diferencial (só leitura)

Uma requisição sozinha não prova IDOR: 200 pode ser o handler devolvendo vazio, a página de
erro com status errado, ou o próprio dado de quem pediu. A prova é a **diferença** entre três
requisições iguais, mudando só o id, todas com a sessão do mesmo ator:

| # | id | papel |
|---|---|---|
| 1 | o do próprio ator | controle positivo: mostra a forma de uma resposta que tem dado |
| 2 | o da vítima (outro tenant ou outro usuário) | o teste |
| 3 | um inexistente do mesmo formato (UUID novo, número fora da faixa) | controle negativo: mostra a forma de "não tem nada aqui" |

```bash
# O token do ator vem do arquivo, sem passar pela conversa. BASE e os três ids vêm da leitura
# do código e dos dados de teste, nunca de um registro real escolhido a esmo.
# Mesmo formato que o script aceita: `export ` e aspas opcionais.
ATOR_JWT="$(awk '{ sub(/^[ \t]+/, ""); sub(/^export[ \t]+/, "") }
  index($0, "MATRIZ_JWT_A=") == 1 { v = substr($0, 14); gsub(/^["\047]|["\047]\r?$/, "", v); print v }' \
  "$HOME/.matriz-auditoria.conf")"
hash12() { python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest()[:12])' "$1"; }
ler() { # ler <rótulo> <url> <id> — imprime status, bytes e se o corpo cita o id; o corpo fica no disco
  # Sem token, a requisição sairia anônima e o resultado pareceria válido: aborta.
  [ -n "$ATOR_JWT" ] || { echo "ATOR_JWT vazio: confira MATRIZ_JWT_A no .conf; nada foi pedido" >&2; return 1; }
  local f; f="$(mktemp)"
  printf 'header = "Authorization: Bearer %s"\n' "$ATOR_JWT" |
    curl -q -sS --noproxy '*' --max-redirs 0 -K - --max-time 20 -o "$f" \
      -w "$1 http=%{http_code} bytes=%{size_download}" --url "$2"
  printf ' cita_id=%s sha=%s\n' "$(grep -c -- "$3" "$f")" "$(hash12 "$f")"
  rm -f "$f"
}
ler proprio     "$BASE/api/pedidos/$ID_PROPRIO"     "$ID_PROPRIO"
ler vitima      "$BASE/api/pedidos/$ID_VITIMA"      "$ID_VITIMA"
ler inexistente "$BASE/api/pedidos/$ID_INEXISTENTE" "$ID_INEXISTENTE"
```

Só `GET` (ou o verbo de leitura da rota). O corpo não vai para a conversa: status, tamanho, hash e
se cita o id bastam para decidir.

**O corpo decide, não o status.** Um critério só, nas três respostas:

- **É prova** quando valem juntas: o corpo do próprio traz dado dele (cita o id); o corpo da
  vítima traz dado dela (cita o id dela, e o hash difere do próprio e do inexistente); e o corpo
  do inexistente **não traz dado** (não cita o id). O inexistente pode vir 404, 403 ou até 200
  com corpo vazio ou genérico: o que importa é que não traz registro.
- **Não é prova:** o corpo da vítima sem dado dela (vazio, `[]`, `{}`, `null`, ou sem o id);
  o corpo da vítima igual ao do inexistente (mesmo tamanho e hash: é a página genérica); o corpo
  da vítima igual ao do próprio (o handler ignora o id e devolve o dado de quem pede, outro bug);
  ou o inexistente trazendo dado (a rota não filtra pelo id, e a comparação não vale).
- Status igual nas três não decide nada sozinho: 200, 200, 200 pode ser prova ou página
  genérica, e só o corpo separa uma da outra.

O que não fechar em nenhuma das duas listas é **Inconclusivo**: o achado fica `lido`, e a
anotação diz o que faltou.

Escrita (`PUT`, `PATCH`, `DELETE` com o id da vítima) não se testa no cliente. Se o achado é de
escrita, a leitura diferencial prova o alcance do id, e o efeito vai para a matriz local abaixo.

**Por que não, mesmo "só para provar".** Num pentest de 11/2026 a escrita em produção provou os
dois P1 e deixou rastro que nenhum papel do app apagava. Ficaram registros de teste que só o
mantenedor arquiva, registros órfãos que só admin remove e o `atualizado_por` da conta de teste
gravado nos registros reais, sem volta. O desfazer exigia ser dono, e a limpeza virou uma lista
de pedidos ao cliente. O efeito de escrita vai para o Supabase local, com os mesmos papéis.

## O ator que mede o horizontal: papel amplo, escopo vazio

A matriz anon × A × B mede inquilino contra inquilino. O furo horizontal (A3, família de ações)
precisa de um quarto ator: **C, com o mesmo papel do dono e nenhum vínculo**. C não tem carteira,
não tem registro atribuído e não está em setor nenhum. Para C, a checagem de vínculo é a única
barreira: o papel deixa passar, e se a função esqueceu o dono, C escreve. Conta de teste com
carteira cheia ou admin esconde exatamente esse caso, porque tudo que ela toca já é dela.

No seed local: crie C como A e B são criados, dê a ele o papel de escrita (o mesmo de A) e não o
ligue a nenhuma linha. Rode a família de funções que o `familias-rpc.py` listou como
`MATRIZ`, uma por verbo, contra o registro de A:

```bash
# Local apenas. C_JWT de usuario-c, ID_DE_A uma linha do seed que pertence a A.
# --max-redirs 0 e host local: a mesma trava da matriz.
rpc_local() { # rpc_local <função> <corpo json>; recusa host que não seja local
  case "$SB" in http://127.0.0.1:*|http://localhost:*|http://\[::1\]:*) ;;
    *) echo "host não local ($SB): recusado, nada foi enviado" >&2; return 2;; esac
  [ -n "$C_JWT" ] || { echo "C_JWT vazio: nada foi enviado" >&2; return 1; }
  printf '%s' "$2" |
    curl -q -sS --noproxy '*' --max-redirs 0 -o /dev/null -w "$1 http=%{http_code}\n" \
      -H "apikey: $ANON_LOCAL" -H "Authorization: Bearer $C_JWT" \
      -H 'Content-Type: application/json' --data-binary @- "$SB/rest/v1/rpc/$1"
}
for fn in cartao_editar cartao_transferir; do   # os nomes que o familias-rpc imprimiu
  rpc_local "$fn" "$(printf '{"p_id":"%s"}' "$ID_DE_A")"
done
```

O que decide é o **estado depois**, não o status (função que engole o erro devolve 200). Releia a
linha como A (`responsavel`, `atualizado_por`) entre uma chamada e outra e rode `supabase db reset`
antes da próxima família. Em `fonte`: `"local, migrations do commit abc1234: C (papel X, carteira
vazia) chamou <função> no registro de A; responsavel passou de A para C"`.

## Matriz por personificação (só leitura, sem conta nova)

Com acesso SQL ao banco, o que um papel lê se mede sem token e sem criar usuário:
`baseline/scripts/matriz-rls.sql` personifica um usuário **existente** numa transação
`read only` e devolve, por tabela e view, quantas linhas existem e quantas o ator lê.

```bash
psql "$SUPABASE_DB_URL_RO" -X -v ator=<uuid> -f "${CLAUDE_PLUGIN_ROOT}/skills/baseline/scripts/matriz-rls.sql"
```

- A primeira tabela da saída é a prova de identidade. `identidade_ok = f` invalida a medição.
- "0 linhas" só vale com `existem > 0`. Tabela vazia sai "sem denominador".
- Rode para o papel mais restrito, um intermediário, o admin e **uma conta sem vínculo** (sem
  organização, sem carteira): é ela que pega helper que falha aberto e papel global em `OR`.
- Em `fonte`: "personificação de <papel>, transação read only, contagem por objeto". Nunca o id.
- Mede leitura. Escrita continua sendo fixture local, como a matriz abaixo.

## Matriz de RLS do Supabase

Papéis **anon, A, B** (e **admin**, se o app tiver) × **tabela** × **operação**. A e B são
usuários comuns de tenants diferentes; admin é o papel do app, não a `service_role`. A
`service_role` ignora RLS e não entra na matriz.

**Leitura** (pode rodar contra o projeto do cliente, com usuários de teste que o cliente
forneceu): `HEAD` com `Prefer: count=exact`, por papel; é o modo padrão do script, que não faz
`GET`. Só a contagem volta, pelo `Content-Range`; nenhuma linha entra no transcript.
`count=exact` faz o banco contar a tabela inteira a cada papel × tabela: em produção do cliente,
passe só as tabelas do achado, não a lista toda. Compare as contagens entre papéis:

- RLS negando SELECT devolve **0**, não erro. 0 para B numa tabela onde A vê 3 é o esperado.
- B vendo as mesmas 3 de A, ou anon vendo qualquer coisa numa tabela de tenant, é o achado.
- 401/403 é `negado`: a tabela nem está exposta para o papel, o que é outra informação.
- Erro de rede, status inesperado ou sem `Content-Range` é `nao_medido`. **Não é 0**; não cite.

**Escrita** (INSERT, UPDATE, DELETE) **só roda contra Supabase local** (`supabase start`, host
`localhost`, `127.0.0.1` ou `[::1]`), com usuários seed criados ali. **Nunca contra o projeto do
cliente.** O script recusa `--escrita` em qualquer outro host, e não existe flag que mude isso.

- Branch do Supabase não é alternativa: criar uma no projeto do cliente já é escrever na infra
  dele. O efeito de escrita que não der para provar localmente vira `status: a_validar`, com o
  `plano_validacao` para o dono rodar.
- A matriz local corrobora **as policies das migrations do repositório**, não a produção. A A1
  manda consultar o estado vivo; se o vivo diverge das migrations, a escrita local não prova o
  vivo. Diga isso em `fonte`: `"matriz local, migrations do commit abc1234"`.

### Rodar

O script lê tudo por variável de ambiente ou por um arquivo `NOME=valor` (`--env`). O argv só
leva tabela e flag, porque argv vai para o histórico do shell e para o `ps`:

```bash
# Arquivo fora do repo, chmod 600, montado por quem audita (nunca colado na conversa).
# A anon legada (JWT) e a sb_publishable_ servem; a publishable vai só no header apikey.
#   SUPABASE_URL=http://127.0.0.1:54321
#   SUPABASE_ANON_KEY=...
#   MATRIZ_JWT_A=...            MATRIZ_JWT_B=...           MATRIZ_JWT_ADMIN=...   (opcional)
#   MATRIZ_FILTRO=id=eq.<uuid de uma linha do seed>        (só escrita)
#   MATRIZ_CORPO_INSERT={"tenant_id":"<uuid do tenant B>","titulo":"teste"}   (só escrita)
#   MATRIZ_CORPO_UPDATE={"titulo":"alterado"}              (só escrita)
bash "${CLAUDE_PLUGIN_ROOT}/skills/auditoria-seguranca/scripts/matriz-supabase.sh" --env "$HOME/.matriz-auditoria.conf" pedidos perfis
bash "${CLAUDE_PLUGIN_ROOT}/skills/auditoria-seguranca/scripts/matriz-supabase.sh" --env "$HOME/.matriz-auditoria.conf" --escrita pedidos
```

Saída: uma linha por célula, pronta para citar, e a tabela no fim. Exit 0 tudo medido, 3 sobrou
célula não medida, 2 uso inválido ou escrita recusada.

```text
matriz-supabase op=SELECT papel=B tabela=pedidos resultado=3 http=200 url=http://127.0.0.1:54321/rest/v1/pedidos
matriz-supabase op=UPDATE papel=B tabela=pedidos resultado=1 http=204 url=http://127.0.0.1:54321/rest/v1/pedidos?id=eq.<uuid>
```

No modo escrita, sem `MATRIZ_FILTRO` o UPDATE e o DELETE não saem (pegariam a tabela inteira) e a
célula fica `nao_medido`. A ordem é anon, A, B, admin; um DELETE aceito muda o que o próximo papel
vê, então rode `supabase db reset` (local) entre medições que dependem do mesmo seed.

### Os dois usuários seed, localmente

Com o Supabase local de pé (`supabase start`; `supabase status` mostra a URL e a anon key locais),
crie A e B pelo próprio Auth local. A confirmação de e-mail vem desligada no local:

```bash
SB=http://127.0.0.1:54321
ANON_LOCAL='<anon key do supabase status>'
SENHA_SEED="$(openssl rand -hex 16)"   # senha só deste banco local; não reaproveite
for u in usuario-a usuario-b; do
  printf '{"email":"%s@exemplo.test","password":"%s"}' "$u" "$SENHA_SEED" |
    curl -sS -o /dev/null -w "$u signup http=%{http_code}\n" -H "apikey: $ANON_LOCAL" \
      -H 'Content-Type: application/json' --data-binary @- "$SB/auth/v1/signup"
done
jwt_de() {
  printf '{"email":"%s@exemplo.test","password":"%s"}' "$1" "$SENHA_SEED" |
    curl -sS -H "apikey: $ANON_LOCAL" -H 'Content-Type: application/json' --data-binary @- \
      "$SB/auth/v1/token?grant_type=password" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
}
umask 077
{ echo "SUPABASE_URL=$SB"; echo "SUPABASE_ANON_KEY=$ANON_LOCAL"
  echo "MATRIZ_JWT_A=$(jwt_de usuario-a)"; echo "MATRIZ_JWT_B=$(jwt_de usuario-b)"; } > "$HOME/.matriz-auditoria.conf"
```

Depois ligue cada usuário ao seu tenant com o mecanismo do próprio app (a tabela de membros, o
`tenant_id` no perfil, o claim que a policy lê), pelo seed do repositório ou por SQL no banco
local, e crie ao menos uma linha por tenant nas tabelas da matriz. Sem linha nos dois tenants, a
matriz só mostra zeros e não prova nada. O JWT local expira em uma hora; gere de novo se a
matriz começar a sair `negado` para todo mundo. Apague o `$HOME/.matriz-auditoria.conf` no fim.

## Scan ativo não é desta skill

ZAP, fuzzing e scan ativo são perímetro: ficam com a `/kit-vamoo:baseline`, que a pessoa chama.
