#!/usr/bin/env bash
# A matriz de RLS da auditoria-seguranca mede sem vazar token e sem escrever fora da máquina local.
#
# O `matriz-supabase.sh` é o caminho repetível para subir um achado de RLS de `lido` para
# `corroborado`: conta linhas por papel (anon, A, B, admin) com `Prefer: count=exact`. A saída
# vai para a conversa e para o campo `fonte` do findings.json, então quatro coisas não podem
# falhar, e este teste prova cada uma contra um PostgREST de mentira em 127.0.0.1:
#
#   1. a leitura sai certa por papel, e 401/403 aparece como "negado", não como zero;
#   2. nenhum JWT nem a anon key aparecem no stdout ou no stderr, nem no caminho de erro;
#   3. `--escrita` contra host que não é localhost/127.0.0.1/[::1] sai ≠ 0 SEM chamar o curl
#      (um curl falso no PATH grava cada chamada; o arquivo tem que ficar vazio), inclusive
#      nas formas que enganam um teste ingênuo de string (userinfo, subdomínio, caminho);
#   4. erro de conexão vira "não medido", nunca 0.
#
# O teste não aborta quando o script falta: roda todos os casos e conta as falhas, para que a
# execução antes do script mostre cada asserção caindo.
#
# Uso: bash tests/test-auditoria-matriz.sh [caminho-do-matriz-supabase.sh]
# shellcheck disable=SC2015  # `[ ] && ok || falha`: ok só imprime, não falha.
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${1:-$RAIZ/plugin/skills/auditoria-seguranca/scripts/matriz-supabase.sh}"

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/auditoria-matriz.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
MOCK_PID=""
trap '[ -n "$MOCK_PID" ] && { kill "$MOCK_PID" 2>/dev/null; wait "$MOCK_PID" 2>/dev/null; }; rm -rf "$TMP"' EXIT
ok()      { printf '  ok    %s\n' "$1"; }
falha()   { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
tem()     { case "$2" in *"$1"*) ok "$3" ;; *) falha "$3 (não achei '$1')" ;; esac; }
nao_tem() { case "$2" in *"$1"*) falha "$3 (achei '$1')" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] || echo "AVISO: script não encontrado ($SCRIPT); todos os casos vão falhar"

# Tokens falsos montados na hora: literal com cara de JWT no fonte reprova os scanners do repo.
b64url() { printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '=\n'; }
jwt() { printf '%s.%s.%s' "$(b64url '{"alg":"HS256","typ":"JWT"}')" "$(b64url "{\"role\":\"$1\",\"sub\":\"$2\"}")" "FALSO$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')assinatura$RANDOM"; }
ANON="$(jwt anon anonimo)"
JA="$(jwt authenticated usuarioa)"
JB="$(jwt authenticated usuariob)"
JADM="$(jwt authenticated administrador)"

# O PostgREST de mentira: Content-Range diferente por JWT, 401 para o anon na tabela "segredo",
# 200 sem Content-Range na tabela "semrange". Grava método, caminho e se a apikey chegou.
cat > "$TMP/cfg.py" <<EOF
TOKENS = {"$ANON": "anon", "$JA": "A", "$JB": "B", "$JADM": "admin"}
EOF
cat > "$TMP/mock.py" <<'EOF'
import http.server, sys, os, importlib.util
spec = importlib.util.spec_from_file_location("cfg", sys.argv[1]); cfg = importlib.util.module_from_spec(spec); spec.loader.exec_module(cfg)
LOG = sys.argv[3]
CONTAGEM = {"pedidos": {"anon": 0, "A": 3, "B": 2, "admin": 5}, "perfis": {"anon": 7, "A": 7, "B": 7, "admin": 7}}
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _papel(self):
        auth = self.headers.get("Authorization", "")
        return cfg.TOKENS.get(auth[7:] if auth.startswith("Bearer ") else "", "?")
    def _registra(self):
        with open(LOG, "a") as f:
            f.write("%s %s apikey=%s papel=%s\n" % (self.command, self.path, "sim" if self.headers.get("apikey") in cfg.TOKENS else "nao", self._papel()))
    def _responde(self, codigo, faixa=None, corpo=b""):
        self.send_response(codigo)
        if faixa is not None: self.send_header("Content-Range", faixa)
        self.send_header("Content-Length", str(len(corpo))); self.end_headers()
        if self.command != "HEAD": self.wfile.write(corpo)
    def _tabela(self): return self.path.split("?")[0].rsplit("/", 1)[-1]
    def do_HEAD(self):
        self._registra(); t, p = self._tabela(), self._papel()
        if t == "segredo": return self._responde(401 if p == "anon" else 200, None if p == "anon" else "*/1")
        if t == "semrange": return self._responde(200)
        n = CONTAGEM.get(t, {}).get(p)
        if n is None: return self._responde(404)
        self._responde(200, ("0-%d/%d" % (n - 1, n)) if n else "*/0")
    do_GET = do_HEAD
    def _escrita(self):
        self._registra(); p = self._papel()
        n = int(self.headers.get("Content-Length") or 0)
        if n: self.rfile.read(n)
        if p == "anon": return self._responde(401)
        if self.command == "POST": return self._responde(201, "*/1")
        self._responde(204, "*/%d" % (1 if p == "A" else 0))
    do_POST = do_PATCH = do_DELETE = _escrita
s = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(sys.argv[2] + ".tmp", "w") as f: f.write(str(s.server_address[1]))
os.rename(sys.argv[2] + ".tmp", sys.argv[2])
s.serve_forever()
EOF
python3 -I "$TMP/mock.py" "$TMP/cfg.py" "$TMP/porta" "$TMP/reqs.log" &
MOCK_PID=$!
for _ in $(seq 1 50); do [ -s "$TMP/porta" ] && break; sleep 0.1; done
[ -s "$TMP/porta" ] || { echo "mock não subiu"; exit 2; }
PORTA="$(cat "$TMP/porta")"
URL="http://127.0.0.1:$PORTA"

# Porta fechada: abre, pega o número e fecha. Ninguém escuta lá.
FECHADA="$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"

roda() { # roda <url> [args...] — ambiente só com o que o script deve ler
  local u="$1"; shift
  # EXTRA_ENV é uma lista VAR=valor, quebrada por espaço de propósito.
  # shellcheck disable=SC2086
  env -i PATH="${PATH_TESTE:-$PATH}" HOME="$TMP" TMPDIR="$TMP" \
    SUPABASE_URL="$u" SUPABASE_ANON_KEY="$ANON" MATRIZ_JWT_A="$JA" MATRIZ_JWT_B="$JB" MATRIZ_JWT_ADMIN="$JADM" \
    ${EXTRA_ENV:-} bash "$SCRIPT" "$@" 2>&1
}
sem_token() { # sem_token <saida> <rótulo>
  local s="$1" vazou=""
  for t in "$ANON" "$JA" "$JB" "$JADM"; do case "$s" in *"$t"*) vazou=1 ;; esac; done
  # nem o miolo da assinatura (pega token cortado ou embrulhado)
  case "$s" in *assinatura*) vazou=1 ;; esac
  [ -z "$vazou" ] && ok "$2: nenhum token na saída" || falha "$2: token apareceu na saída"
}

echo "== 1. leitura: papel × tabela × contagem =="
: > "$TMP/reqs.log"
saida="$(roda "$URL" pedidos perfis segredo semrange)"; rc=$?
[ "$rc" -eq 3 ] && ok "sai 3 quando sobra célula não medida (semrange)" || falha "exit esperado 3, veio $rc"
tem "op=SELECT papel=anon tabela=pedidos resultado=0 http=200" "$saida" "anon vê 0 em pedidos"
tem "op=SELECT papel=A tabela=pedidos resultado=3 http=200" "$saida" "A vê 3 em pedidos"
tem "op=SELECT papel=B tabela=pedidos resultado=2 http=200" "$saida" "B vê 2 em pedidos"
tem "op=SELECT papel=admin tabela=pedidos resultado=5 http=200" "$saida" "admin vê 5 em pedidos"
tem "op=SELECT papel=A tabela=perfis resultado=7 http=200" "$saida" "A vê 7 em perfis"
tem "op=SELECT papel=anon tabela=segredo resultado=negado http=401" "$saida" "401 vira negado, não 0"
tem "op=SELECT papel=A tabela=semrange resultado=nao_medido" "$saida" "200 sem Content-Range vira não medido"
tem "url=$URL/rest/v1/pedidos" "$saida" "linha da célula traz a URL, pronta para fonte"
tem "papel" "$saida" "imprime o cabeçalho da tabela legível"
sem_token "$saida" "leitura"
reqs="$(cat "$TMP/reqs.log" 2>/dev/null)"
nao_tem "POST" "$reqs" "leitura não faz POST"; nao_tem "PATCH" "$reqs" "leitura não faz PATCH"; nao_tem "DELETE" "$reqs" "leitura não faz DELETE"
nao_tem "apikey=nao" "$reqs" "toda requisição leva a apikey"
case "$reqs" in *"HEAD /rest/v1/pedidos"*|*"GET /rest/v1/pedidos"*) ok "leu pedidos pelo /rest/v1" ;; *) falha "não leu /rest/v1/pedidos" ;; esac

echo "== 2. sem tabela ou sem variável: recusa sem rede =="
saida="$(roda "$URL")"; rc=$?
[ "$rc" -ne 0 ] && ok "sem tabela sai ≠ 0" || falha "sem tabela saiu 0"
saida="$(env -i PATH="$PATH" HOME="$TMP" SUPABASE_URL="$URL" bash "$SCRIPT" pedidos 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "sem SUPABASE_ANON_KEY sai ≠ 0" || falha "sem anon key saiu 0"
saida="$(roda "$URL" "$JA" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "token passado como argumento é recusado" || falha "aceitou token como argumento"
sem_token "$saida" "argumento recusado (o script não ecoa o argv suspeito)"

echo "== 3. --escrita contra host não local: recusa sem chamar o curl =="
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<EOF
#!/bin/sh
echo "chamado \$*" >> "$TMP/curl-falso.log"
exit 7
EOF
chmod +x "$TMP/bin/curl"
for alvo in "https://abcdefghij.supabase.co" "http://localhost.exemplo.test" "http://127.0.0.1@exemplo.test" \
            "http://exemplo.test/localhost" "http://127.0.0.1.exemplo.test:54321" "http://exemplo.test#@127.0.0.1"; do
  : > "$TMP/curl-falso.log"
  saida="$(PATH_TESTE="$TMP/bin:$PATH" roda "$alvo" --escrita pedidos)"; rc=$?
  [ "$rc" -ne 0 ] && ok "recusa $alvo (exit $rc)" || falha "aceitou --escrita em $alvo"
  [ ! -s "$TMP/curl-falso.log" ] && ok "nenhuma requisição para $alvo" || falha "curl foi chamado para $alvo"
  sem_token "$saida" "recusa de $alvo"
done
: > "$TMP/curl-falso.log"
saida="$(PATH_TESTE="$TMP/bin:$PATH" roda "https://abcdefghij.supabase.co" pedidos --escrita --forcar)"; rc=$?
[ "$rc" -ne 0 ] && [ ! -s "$TMP/curl-falso.log" ] && ok "não existe escotilha por flag" || falha "alguma flag liberou escrita remota"

echo "== 4. --escrita contra 127.0.0.1: mede INSERT/UPDATE/DELETE =="
: > "$TMP/reqs.log"
saida="$(EXTRA_ENV="MATRIZ_FILTRO=id=eq.1 MATRIZ_CORPO_INSERT={\"x\":1} MATRIZ_CORPO_UPDATE={\"x\":2}" roda "$URL" --escrita pedidos)"; rc=$?
[ "$rc" -eq 0 ] && ok "escrita local sai 0" || falha "escrita local saiu $rc"
tem "op=INSERT papel=anon tabela=pedidos resultado=negado http=401" "$saida" "anon não insere"
tem "op=INSERT papel=A tabela=pedidos resultado=aceito http=201" "$saida" "A insere"
tem "op=UPDATE papel=A tabela=pedidos resultado=1 http=204" "$saida" "A atualiza 1 linha"
tem "op=UPDATE papel=B tabela=pedidos resultado=0 http=204" "$saida" "B atualiza 0 linhas"
tem "op=DELETE papel=B tabela=pedidos resultado=0 http=204" "$saida" "B apaga 0 linhas"
tem "op=SELECT papel=A tabela=pedidos resultado=3" "$saida" "modo escrita também mede a leitura"
sem_token "$saida" "escrita local"
reqs="$(cat "$TMP/reqs.log" 2>/dev/null)"
tem "DELETE /rest/v1/pedidos?id=eq.1" "$reqs" "DELETE vai com o filtro da variável"
tem "PATCH /rest/v1/pedidos?id=eq.1" "$reqs" "PATCH vai com o filtro da variável"
: > "$TMP/reqs.log"
saida="$(roda "$URL" --escrita pedidos)"; rc=$?
tem "op=UPDATE papel=A tabela=pedidos resultado=nao_medido" "$saida" "sem filtro/corpo, a escrita vira não medido"
reqs="$(cat "$TMP/reqs.log" 2>/dev/null)"
nao_tem "DELETE" "$reqs" "sem MATRIZ_FILTRO não sai DELETE sem filtro (apagaria a tabela)"

echo "== 5. erro de conexão vira não medido =="
saida="$(roda "http://127.0.0.1:$FECHADA" pedidos)"; rc=$?
[ "$rc" -eq 3 ] && ok "porta fechada sai 3" || falha "porta fechada: exit esperado 3, veio $rc"
tem "op=SELECT papel=A tabela=pedidos resultado=nao_medido" "$saida" "rede caída é não medido"
nao_tem "resultado=0 " "$saida" "rede caída nunca vira 0"
sem_token "$saida" "erro de conexão"

echo "== 6. --env <arquivo>: o segredo vem do arquivo, o argv só leva o caminho =="
{
  echo "# comentário ignorado"
  echo "SUPABASE_URL=$URL"
  echo "SUPABASE_ANON_KEY=\"$ANON\""
  echo "export MATRIZ_JWT_A='$JA'"
  echo "MATRIZ_JWT_B=$JB"
  echo "PATH=/nao/existe"
  echo "touch $TMP/injetado"
} > "$TMP/matriz.env"
saida="$(env -i PATH="$PATH" HOME="$TMP" TMPDIR="$TMP" bash "$SCRIPT" --env "$TMP/matriz.env" pedidos 2>&1)"; rc=$?
tem "op=SELECT papel=A tabela=pedidos resultado=3 http=200" "$saida" "A medido com o JWT do arquivo (aspas simples e export aceitos)"
tem "op=SELECT papel=B tabela=pedidos resultado=2 http=200" "$saida" "B medido com o JWT do arquivo"
tem "op=SELECT papel=anon tabela=pedidos resultado=0 http=200" "$saida" "anon key do arquivo (aspas duplas aceitas)"
[ ! -e "$TMP/injetado" ] && ok "o arquivo é lido, não executado" || falha "o arquivo foi executado como shell"
sem_token "$saida" "--env"
saida="$(env -i PATH="$PATH" HOME="$TMP" bash "$SCRIPT" --env "$TMP/nao-existe.env" pedidos 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "--env com arquivo ausente sai 2" || falha "--env ausente: exit esperado 2, veio $rc"

echo
if [ "$falhas" -eq 0 ]; then echo "PASSOU"; exit 0; fi
echo "FALHOU ($falhas)"; exit 1
