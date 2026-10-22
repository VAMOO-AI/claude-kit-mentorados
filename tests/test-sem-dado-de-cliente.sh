#!/usr/bin/env bash
# O kit é público: nada versionado aqui pode carregar dado de cliente da casa.
#
# As skills de WhatsApp e n8n vieram do kit do time, que nasceu de projetos de cliente:
# nome de empresa, nome de agente, telefone de verdade, host do servidor UAZAPI. Um grep na
# hora do porte deixou escapar nomes que só uma leitura linha a linha achou, e três nomes
# já estavam em comentários antigos. Este teste é o gate para nada disso entrar de novo.
#
# O que reprova, em todo arquivo de texto versionado (git ls-files):
#   - palavra cujo sha256 (minúsculas) está na lista abaixo. A lista é de HASHES de
#     propósito: em texto puro, o próprio teste publicaria a carteira de clientes. Para
#     incluir um nome: printf '%s' nome | shasum -a 256;
#   - telefone brasileiro com DDD real (55 + DDD 11–99 + 8 ou 9 dígitos, com ou sem
#     máscara). Exemplo usa DDD 00, que não chega em ninguém;
#   - host <algo>.uazapi.com que não seja placeholder (<...>), docs.uazapi.com ou
#     free.uazapi.com;
#   - project ref do Supabase (20 letras minúsculas) em `<ref>.supabase.co`,
#     `/projects/<ref>` ou no usuário do pooler `postgres.<ref>`. Exemplo usa placeholder (`<ref>`, `$SUPABASE_REF`);
#   - URL de capacidade, em que a própria URL é a senha: tópico ntfy com 12+ caracteres
#     (`ntfy.sh/<topico>` e prefixo curto passam), webhook do Discord ou do Slack com o
#     token no caminho, e `?token=`/`key=`/`secret=` com valor literal de 16+ caracteres
#     (`{{env:...}}`, `$VAR` e `<...>` passam). Até a 0.62 um tópico ntfy real passava aqui
#     (avaliação de 21/10/2026).
#
# Uso: bash tests/test-sem-dado-de-cliente.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
command -v python3 >/dev/null 2>&1 || { echo "python3 ausente"; exit 2; }

HASHES='
49e455c30a6f9273b4664699722a3ee616d285d80a45f54d485988f4eeb16871
2172fd481920ce9db75cf1d2f006597118d52f379ab6a3b47a196d5b50607d43
95a8f6568fa7ad6aba1bdcd6620a471a0aca7d4c447f508a94ae4aab2ed86bd3
8e0e7acb709b40a29195580da8c3a3da8495db78d704ad616f643243cf677c8f
3c417b7ea567c3115deebed7319de56c4d008e6990b0d45ed5cfa53d4c5d37fa
c9abd566c4b489808065a241c747ffab186254d1d9b85c9de91e4cf34547f8e5
1362ac7a8cefbcf4921a03ca100d82e5d029a7d9e824a477ebdd72d101b4428d
9bcca1aa25c88bd9b524195bccb4aae170f45eb8c9d9cccd5b2b30f2462d70ca
d233633d9524e84c71d6fe45eb3836f8919148e4a5fc2234cc9e6494ec0f11c2
6731a155a2f656580885f8fc6538b3b53df5f4e80328a3e8e3c59d24ac114680
b068c5093aed09a10a9732de95a450c094e59f0ac8afede78474b8c75eda95b3
2b2437a2b9ba96dece776fa2afc58a8ffbf1d5149fa7c3f3550781f7ca24109d
d2b5b064fd7f61cfd76491d9d7dbdf9537694b00358da0e23d540b7ca46e09f0
a4c3700a819851ce20ba602ed58e460c439730af68a7b74bc48298a444658bbf
5f00da6558739776862537b77b1e6e341d82a874324f598a82d7bfc18a20e30d
702053c25e604a89e6d70203b2e2b53ca124b17b3cb0b6acb66a3f2dc24521fe
a55ce4a84f567a262c142e8b4a10fb9e87c22b8b4e89e68162d5886da8148d5a
09982f15a0136d20544f6b2778d08fe85d03550bb25ee593c9394155e06a0b25
f59870fd84d3019ec3ae3a028b883c802aedd41d6ae0fd0e1d8d47f1dd7614e2
225e9c2aa7e4b8b585ce635156b1961af23d7c14edeaa1c687831320d92787c9
523cefbd8a33ea05ce2670dcbbc45611bb488e8823fba9d51ad49973bef2a0af
1da4d39e9ba385dbd9061d90986e9209327b66a2f161042c4eb1a53c770ffed6
02ae9df1dc51510fb2abdc74485f4dc777ac202a5f89a631321125cceb83246a
e34290628e9fbbc68ddd004201caa50d51b1c75c853a79f3744428b0a375a06f
'

confere() { # <raiz> — imprime um achado por linha; sai 1 se achou algo
  git -C "$1" ls-files -z | HASHES="$HASHES" python3 -I -c '
import hashlib, os, re, sys
raiz = sys.argv[1]
proibidos = {h.strip() for h in os.environ["HASHES"].split() if h.strip()}
eu = "tests/test-sem-dado-de-cliente.sh"
BIN = (".zip", ".png", ".jpg", ".jpeg", ".gif", ".wav", ".mp3", ".mp4", ".ttf", ".woff", ".woff2", ".ico", ".pdf")
PALAVRA = re.compile(r"[a-z0-9]+")
TEL = re.compile(r"(?<![0-9])\+?55[ -]?\(?(?:1[1-9]|[2-9][0-9])\)?[ -]?9?[0-9]{4}[ -]?[0-9]{4}(?![0-9])")
HOST = re.compile(r"(?<![<\w-])([a-z0-9-]+)\.uazapi\.com", re.I)
CAP = re.compile(r"ntfy\.sh/[A-Za-z0-9_-]{12,}|discord(?:app)?\.com/api/webhooks/[0-9]{6,}/[A-Za-z0-9_-]{20,}|hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]{10,}|[?&](?:token|key|apikey|api_key|secret)=[A-Za-z0-9_-]{16,}", re.I)
SUPA = re.compile(r"(?<![a-z0-9])[a-z]{20}\.supabase\.(?:co|in)\b|/projects/[a-z]{20}(?![a-z0-9])|\bpostgres\.[a-z]{20}(?![a-z0-9])")
achados = []
for rel in sys.stdin.buffer.read().decode().split("\0"):
    if not rel or rel == eu or rel.lower().endswith(BIN):
        continue
    p = os.path.join(raiz, rel)
    if not os.path.isfile(p):
        continue
    try:
        texto = open(p, encoding="utf-8").read()
    except (UnicodeDecodeError, OSError):
        continue
    for n, linha in enumerate(texto.split("\n"), 1):
        baixa = linha.lower()
        for w in set(PALAVRA.findall(baixa)):
            if hashlib.sha256(w.encode()).hexdigest() in proibidos:
                achados.append(f"{rel}:{n}: nome de cliente (palavra #{hashlib.sha256(w.encode()).hexdigest()[:8]})")
        for m in TEL.finditer(linha):
            achados.append(f"{rel}:{n}: telefone com DDD real: {m.group(0)}")
        for m in SUPA.finditer(linha):
            achados.append(f"{rel}:{n}: project ref do Supabase: {m.group(0)}")
        for m in CAP.finditer(linha):
            achados.append(f"{rel}:{n}: URL de capacidade (a URL é a senha): {m.group(0)[:24]}…")
        for m in HOST.finditer(linha):
            if m.group(1).lower() not in ("docs", "free"):
                achados.append(f"{rel}:{n}: host UAZAPI que não é exemplo: {m.group(0)}")
for a in achados:
    print("  FALHA " + a)
sys.exit(1 if achados else 0)
' "$1"
}

# Autoteste: um repo com um erro plantado de cada tipo. Gate que não reprova o erro
# plantado aprovaria qualquer coisa. "clientefantasma" está na lista só para isto.
FIX=$(mktemp -d); trap 'rm -rf "$FIX"' EXIT
git -C "$FIX" init -q
cat > "$FIX/a.md" <<'MD'
Agente do ClienteFantasma em produção.
Ligue para 5511900000000 ou +55 (21) 90000-0000 (fictícios, mas com DDD real).
Servidor: https://minhaempresa.uazapi.com/send/text
Banco: https://abcdefghijklmnopqrst.supabase.co/rest/v1
Pooler: user postgres.tsrqponmlkjihgfedcba
Exemplo que passa: https://<ref>.supabase.co, /v1/projects/$SUPABASE_REF/database/query
Exemplos que passam: 5500999990001, 550099990001, <sua-instancia>.uazapi.com, docs.uazapi.com
Passam: ntfy.sh/<topico>, ntfy.sh/alertas-, /webhook/agente?token={{env:TOKEN_WEBHOOK}}, ?token=$TOKEN
MD
# As URLs de capacidade falsas são montadas aqui, em pedaços: escritas inteiras neste
# arquivo, o gitleaks do CI as acusaria como segredo de verdade.
x="xxxxxxxx"
{
  printf 'Alerta: https://%s/%s\n' "ntfy.sh" "meutopico${x}"
  printf 'Discord: https://%s/%s/%s\n' "discord.com/api""/webhooks" "123456789012" "${x}${x}${x}"
  printf 'Slack: https://%s/%s/%s/%s\n' "hooks.slack.com/""services" "T0000AAAA" "B0000BBBB" "${x}${x}"
  printf 'Webhook: https://n8n.exemplo.com/webhook/agente?%s=%s\n' "token" "${x}${x}${x}"
} >> "$FIX/a.md"
git -C "$FIX" add -A
saida=$(confere "$FIX"); rc=$?
falhas=0
espera() { if printf '%s' "$saida" | grep >/dev/null -F -- "$1"; then printf '  ok    %s\n' "$2"; else printf '  FALHA %s\n' "$2"; falhas=$((falhas+1)); fi; }
echo "== o gate reprova o erro plantado =="
[ "$rc" = 1 ] && printf '  ok    sai 1\n' || { printf '  FALHA rc=%s\n' "$rc"; falhas=$((falhas+1)); }
espera 'nome de cliente' "nome de cliente pelo hash, em qualquer caixa"
espera '5511900000000' "telefone sem máscara"
espera '+55 (21) 90000-0000' "telefone com máscara"
espera 'minhaempresa.uazapi.com' "host UAZAPI de verdade"
espera 'abcdefghijklmnopqrst.supabase.co' "project ref do Supabase na URL"
espera 'postgres.tsrqponmlkjihgfedcba' "project ref no usuário do pooler"
espera 'ntfy.sh/meutopicoxxx' "tópico ntfy de verdade"
espera 'discord.com/api/webhook' "webhook do Discord com token"
espera 'hooks.slack.com/services' "webhook do Slack com token"
espera '?token=xxxxxxxx' "token literal na query"
n=$(printf '%s\n' "$saida" | grep -c 'FALHA')
[ "$n" = 10 ] && printf '  ok    exatamente 10 achados (DDD 00, placeholders, docs e env passam)\n' \
  || { printf '  FALHA %s achados, esperava 10:\n%s\n' "$n" "$saida"; falhas=$((falhas+1)); }
[ "$falhas" -eq 0 ] || { echo; echo "$falhas falha(s) no autoteste"; exit 1; }

echo
echo "== o repo =="
if confere "$RAIZ"; then echo "tudo verde"; else echo; echo "dado de cliente no repo (acima)"; exit 1; fi
