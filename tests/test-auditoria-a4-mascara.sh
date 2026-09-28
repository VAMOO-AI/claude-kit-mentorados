#!/usr/bin/env bash
# A varredura de chaves expostas (A4 da auditoria-seguranca) não imprime o segredo nem roda build.
#
# O bloco da A4 é o que o modelo roda como está escrito, e a saída entra na conversa: vai para o
# transcript e costuma acabar colada no relatório e na issue. Antes o `grep -rEo` do
# bundle devolvia a chave inteira, e os greps de atribuição e de default em config devolviam a
# linha com o valor. Agora cada achado sai como arquivo:linha e a máscara (até 12 caracteres,
# só "…"; acima, no máximo os 4 primeiros + "…"; antes eram 6, e um default de 9 ficava a
# 3 de exposto); o JWT do bundle sai com o `role` do payload, que é o que separa a anon key da
# service_role. O bundle reconhece sk-proj-, sk-ant- e as chaves da Stripe, e os defaults cobrem os
# nomes de compose do v2 (compose.yaml, compose.yml, docker-compose*.yaml).
#
# A Fase 6 mandava copiar o trecho com `sed -n`, e para achado de segredo a linha trazia o
# valor para a conversa. O bloco "# trecho de achado de segredo" corta a linha no valor, e o
# teste prova que o resultado passa no --verificar do gerador contra o arquivo real.
#
# E o bloco rodava `npm run build` quando faltava `dist/`: script do repo auditado executando na
# máquina de quem audita, gravando fora de docs/security-audit/. Sem build no disco, o bloco não
# chama npm: o build vira pergunta, com o comando pronto e o que ele grava, e o bundle que ficou
# sem varrer aparece na `cobertura[]` da A4.
#
# Mesmo teste do kit do time, com o que só este kit tem: LC_ALL=C nos greps da A4 (o grep BSD
# cala a linha com byte inválido), o locale UTF-8 forçado no caso do byte, a varredura do
# gerador com cada prefixo da Fase 6 colado em %20 e em _, e a pergunta do build.
# O teste roda o bloco do SKILL.md, sem cópia, contra repos de mentira com segredos falsos
# montados na hora, e sem gitleaks no PATH (a linha dele já usa --redact).
#
# Uso: bash tests/test-auditoria-a4-mascara.sh [caminho-do-SKILL.md]
set -uo pipefail
SKILL="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/auditoria-seguranca/SKILL.md}"
[ -f "$SKILL" ] || { echo "SKILL.md não encontrado: $SKILL"; exit 2; }

falhas=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/a4-mascara.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou — abortando"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
ok()      { printf '  ok    %s\n' "$1"; }
falha()   { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
tem()     { case "$2" in *"$1"*) ok "$3" ;; *) falha "$3 (não achei '$1' em: $2)" ;; esac; }
nao_tem() { case "$2" in *"$1"*) falha "$3 (achei '$1')" ;; *) ok "$3" ;; esac; }

# O primeiro bloco ```bash depois do título da A4.
awk '/^## A4 /{a=1} a && /^```bash/{b=1; next} b && /^```/{exit} b' "$SKILL" > "$TMP/a4.sh"
[ -s "$TMP/a4.sh" ] || { echo "bloco bash da A4 não encontrado em $SKILL"; exit 2; }

# Segredos falsos montados aqui: literal de segredo no fonte faz scanner reprovar o próprio teste.
b64url() { printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '=\n'; }
SK="sk-FALSO$(printf 'a%.0s' $(seq 1 30))"
JWT="$(b64url '{"alg":"HS256","typ":"JWT"}').$(b64url '{"role":"service_role","iss":"supabase"}').$(printf 's%.0s' $(seq 1 30))"
CFG="valorFALSO$(printf '1%.0s' $(seq 1 10))"
DEF="padraoFALSO$(printf '2%.0s' $(seq 1 10))"

# Chaves com prefixo de fornecedor, montadas por concatenação: o prefixo inteiro num literal
# é o que a push protection do GitHub reconhece.
rep() { printf "$1%.0s" $(seq 1 "$2"); }
SKP="sk-""proj-FALSO$(rep b 30)"
SKL="sk_""live_FALSO$(rep c 24)"
SKT="sk_""test_FALSO$(rep d 24)"
RKL="rk_""live_FALSO$(rep e 24)"
SKA="sk-""ant-api03-FALSO$(rep f 40)"
# Política de máscara: até 12 caracteres o valor sai só como "…"; acima, no máximo 4 + "…".
# Os tamanhos de borda (6, 9, 12, 13) no default do compose e na atribuição de config.
# As variáveis têm dígito no nome (P6, P13): `[A-Z_]+` não casava ${S3_SECRET:-…} e o default sumia.
V6="seis66"; V9="nove99999"; V12="doze12121212"; V13="treze13131313"
C9="cnove9999"; C12="cdoze1212121"; C13="ctreze1313131"

R="$TMP/com-build"; mkdir -p "$R/dist" "$R/.next/static"
printf 'const a=1;\nconst k="%s";\nconst j="%s";\n' "$SK" "$JWT" > "$R/dist/app.js"
# binário com a chave dentro (o .asar do Electron): o grep BSD imprimia "Binary file … matches"
# no stdout, e o python do bloco quebrava levando junto os achados dos outros arquivos
printf 'ASAR\000\000\000cabecalho\nconst k="%s";\n' "$SK" > "$R/dist/app.asar"
printf 'var t="%s";\n' "$JWT" > "$R/.next/static/chunk.js"
printf 'const p="%s";\nconst s="%s";\nconst t="%s";\nconst r="%s";\nconst a="%s";\n' "$SKP" "$SKL" "$SKT" "$RKL" "$SKA" > "$R/dist/chaves.js"
printf 'nome: app\napi_key: "%s"\n' "$CFG" > "$R/config.yml"
printf 'nome: app\npassword: "%s"\nsecret: "%s"\ntoken: "%s"\n' "$C9" "$C12" "$C13" > "$R/tamanhos.yml"
printf 'services:\n  api:\n    environment:\n      JWT_SECRET: ${JWT_SECRET:-%s}\n' "$DEF" > "$R/docker-compose.yml"
# os nomes do Compose v2 e o override em .yaml
printf 'services:\n  db:\n    environment:\n      P6: ${P6:-%s}\n      P9: ${P9:-%s}\n      P12: ${P12:-%s}\n      P13: ${P13:-%s}\n' \
  "$V6" "$V9" "$V12" "$V13" > "$R/compose.yaml"
# literal depois da } interna, nome minúsculo, sem os dois-pontos, e as referências puras
printf '      L1: ${A:-${B}%s}\n      L2: ${A:-${B:-curto}%s}\n      L3: ${db_pass:-%s}\n      L4: ${PW-%s}\n      L5: ${A:-${B}}\n      L6: ${A:-${B:-${C}}}\n      L7: ${lower_pw-%s}\n' \
  "LiteralFALSO123" "LiteralFALSO456" "DefaultFALSOsenha1" "OutraFALSOsenha22" "SemDoisFALSOpontos" >> "$R/compose.yaml"
printf 'services:\n  w:\n    environment:\n      DB_PASSWORD: ${DB_PASSWORD:-senhaDoComposeYml1}\n' > "$R/compose.yml"
printf 'services:\n  w:\n    environment:\n      REDIS_PASSWORD: ${REDIS_PASSWORD:-senhaDoOverride22}\n' > "$R/docker-compose.override.yaml"

# Busca 4 alinhada à lista pads da Fase 6: um formato por linha, nos tamanhos que o pads exige.
# A linha 16 é classe CSS de bundle minificado: o sk-/rk- genérico mantém a fronteira do gerador.
NOVOS=(
  "sb_""secret_FALSO$(rep a 20)"   "chave:token do Supabase"
  "np""m_FALSO$(rep b 32)"         "chave:token do npm"
  "h""f_FALSO$(rep c 30)"          "chave:token do Hugging Face"
  "AI""zaFALSO$(rep g 30)"         "chave:chave de API do Google"
  "S""G.FALSO$(rep s 18).FALSO$(rep t 38)" "chave:chave SendGrid"
  "sk-""svcacct-FALSO$(rep d 20)"  "chave:chave de conta de serviço OpenAI"
  "sk-""admin-FALSO$(rep e 20)"    "chave:chave admin OpenAI"
  "sk-""FALSO_ab-$(rep f 16)"      "chave:chave sk-"
  "rk-""FALSO-cd_$(rep h 16)"      "chave:chave rk-"
  "AK""IAFALSO$(rep 7 11)"         "chave:chave AWS"
  "gh""p_FALSO$(rep Z 24)"         "chave:token do GitHub"
  "github""_pat_FALSO$(rep X 24)"  "chave:token do GitHub"
  "xo""xb-FALSO$(rep W 12)"        "chave:token do Slack"
  "gl""pat-FALSO$(rep U 20)"       "chave:token do GitLab"
  "wh""sec_FALSO$(rep T 20)"       "chave:chave de webhook Stripe"
)
: > "$R/dist/novos.js"
for ((i = 0; i < ${#NOVOS[@]}; i += 2)); do printf 'var k="%s";\n' "${NOVOS[i]}" >> "$R/dist/novos.js"; done
printf 'e.className="task-FALSOlistitemcheckboxwrap";\n' >> "$R/dist/novos.js"
printf 'k="-----BEGIN RSA PRIVATE KEY-----MIIFALSO%s"\n' "$(rep p 40)" >> "$R/dist/novos.js"

# Busca 3 alinhada à atribuição da Fase 6: pwd, chave com sufixo no nome, =>, aspas com espaço,
# chave JSON e valor sem aspas. As linhas 6 e 7 são default com literal, fora dos arquivos que a
# busca 2 varre: continuam achado. A linha 8 é referência pura e não sai.
CFG3=("abc(FALSOpwd123)" "wJalrFALSOawsawsaws" "setaFALSOphp1234" "chaveFALSOjson123" "frase FALSO com espaco"
      "tokeFALSOdefault1" "segrFALSOdefault2")
{
  printf 'pwd=%s\n' "${CFG3[0]}"
  printf 'AWS_SECRET_ACCESS_KEY=%s\n' "${CFG3[1]}"
  printf "'api_key' => '%s'\n" "${CFG3[2]}"
  printf '"secretKey": "%s"\n' "${CFG3[3]}"
  printf 'password = "%s"\n' "${CFG3[4]}"
  printf 'token: "${API_TOKEN:-%s}"\n' "${CFG3[5]}"
  printf 'SECRET_KEY=${SECRET_KEY:-%s}\n' "${CFG3[6]}"
  printf 'DB_PASSWORD=${OUTRA_SENHA_DO_AMBIENTE}\n'
} > "$R/cfg3.env"

saida=$(cd "$R" && PATH=/usr/bin:/bin bash "$TMP/a4.sh" 2>&1)

echo "== o segredo não sai inteiro =="
nao_tem "$SK"  "$saida" "chave sk- do bundle mascarada"
nao_tem "$JWT" "$saida" "JWT do bundle mascarado"
nao_tem "$CFG" "$saida" "valor do api_key em config mascarado"
nao_tem "$DEF" "$saida" "default do compose mascarado"
# sem o `}`: uma regressão que imprime o valor inteiro seguido de "…}" tem que reprovar aqui
nao_tem ":-$DEF" "$saida" "default do compose: nada do valor depois do :-"
for v in "$SKP" "$SKL" "$SKT" "$RKL" "$SKA"; do nao_tem "$v" "$saida" "chave ${v:0:3}… do bundle mascarada"; done

echo "== o achado continua achável: arquivo:linha, até 4 caracteres e o tipo =="
tem "dist/app.js:2:sk-F…"             "$saida" "bundle: dist/app.js:2 e sk-F…"
tem "dist/app.js:3:eyJh…"             "$saida" "bundle: dist/app.js:3 e eyJh…"
tem ".next/static/chunk.js:1:eyJh…"   "$saida" "bundle: .next/static/chunk.js:1 e eyJh…"
tem "dist/app.asar:2:sk-F…"           "$saida" "bundle: a chave dentro do binário vira achado"
nao_tem "Traceback"                   "$saida" "bundle: binário não quebra o bloco"
tem "role=service_role"               "$saida" "bundle: o JWT sai com o role do payload"
tem "config.yml:2:"                   "$saida" "config: config.yml:2"
tem "api_key: \"valo…"                "$saida" "config: 4 caracteres do valor de 20"
nao_tem "\"valorF"                    "$saida" "config: não sai o 5º caractere"
tem "docker-compose.yml:4:"           "$saida" "default: docker-compose.yml:4"
tem ":-padr…}"                        "$saida" "default: 4 caracteres do default de 21"

echo "== bundle: sk-proj-, sk-ant- e as chaves da Stripe viram achado, com o tipo certo =="
linha() { printf '%s\n' "$saida" | grep -F "$1" | head -1; }
tem "chave de projeto OpenAI"         "$(linha 'dist/chaves.js:1:sk-p…')" "sk-proj-: dist/chaves.js:1, 4 caracteres e o tipo"
tem "Stripe sk_""live_"               "$(linha 'dist/chaves.js:2:sk_l…')" "sk_live_: dist/chaves.js:2, 4 caracteres e o tipo"
tem "Stripe sk_""test_"               "$(linha 'dist/chaves.js:3:sk_t…')" "sk_test_: dist/chaves.js:3, 4 caracteres e o tipo"
tem "Stripe rk_""live_"               "$(linha 'dist/chaves.js:4:rk_l…')" "rk_live_: dist/chaves.js:4, 4 caracteres e o tipo"
# sk-ant-api03-…: o hífen depois de "ant" quebrava o sk-[A-Za-z0-9]{16,}, e a chave da
# Anthropic não virava achado, como a sk-proj- antes
tem "chave Anthropic"                "$(linha 'dist/chaves.js:5:sk-a…')" "sk-ant-: dist/chaves.js:5, 4 caracteres e o tipo"
for n in 2 3 4; do nao_tem "JWT" "$(linha "dist/chaves.js:$n:")" "chave da Stripe na linha $n não sai como JWT"; done

echo "== bundle: cada formato da lista pads vira achado, mascarado e com o tipo =="
# Antes a busca 4 conhecia só sk-proj-, sk-ant-, sk- sem _/-, Stripe, JWT e sbp_: o gerador
# redigia sb_secret_, npm_, hf_, AIza, SG., sk-svcacct-, rk- e os tokens de serviço, mas a
# varredura do bundle nem os achava.
sem_janela() { # sem_janela <valor> <saída> <rótulo>: nenhum pedaço de 8 caracteres do valor sai
  local k; for ((k = 0; k + 8 <= ${#1}; k++)); do
    case "$2" in *"${1:k:8}"*) falha "$3 (saiu '${1:k:8}')"; return ;; esac
  done; ok "$3"
}
n=1
for ((i = 0; i < ${#NOVOS[@]}; i += 2)); do
  v="${NOVOS[i]}"; tipo="${NOVOS[i+1]#chave:}"
  l=$(linha "dist/novos.js:$n:${v:0:4}…")
  tem "$tipo" "$l" "bundle linha $n: ${v:0:4}… com o tipo '$tipo'"
  nao_tem "JWT" "$l" "bundle linha $n: não sai como JWT"
  sem_janela "$v" "$saida" "bundle linha $n: nada do valor além de 4 caracteres"
  n=$((n+1))
done
nao_tem "dist/novos.js:$n:" "$saida" "bundle: classe CSS com 'sk-' no meio da palavra não é achado"
tem "dist/novos.js:$((n+1)):----…  bloco de chave privada" "$saida" "bundle: bloco de chave privada vira achado"

echo "== config: pwd, sufixo no nome, =>, aspas com espaço e valor sem aspas =="
# A busca 3 só via api_key/secret/token/password/passwd em minúsculas, colados no [:=] e com
# aspas: AWS_SECRET_ACCESS_KEY=, pwd=, 'api_key' => e o .env sem aspas passavam.
for c in 'cfg3.env:1:pwd=abc(…' 'cfg3.env:2:SECRET_ACCESS_KEY=wJal…' "cfg3.env:3:api_key' => 'seta…" \
         'cfg3.env:4:secretKey": "chav…' 'cfg3.env:5:password = "fras…' \
         'cfg3.env:6:token: "${AP…' 'cfg3.env:7:SECRET_KEY=${SE…'; do
  tem "$c" "$saida" "config: $c"
done
for v in "${CFG3[@]}"; do sem_janela "$v" "$saida" "config: '${v:0:4}…' não sai além de 4 caracteres"; done
nao_tem "cfg3.env:8:" "$saida" "config: referência \${…} no lugar do valor não é achado"

echo "== compose v2 e .yaml: o default de senha é achado, mascarado =="
# no começo da linha: "compose.yml:4:" também está dentro de "docker-compose.yml:4:"
comeca() { printf '%s\n' "$2" | grep -q "^$1" && ok "$3" || falha "$3 (nenhuma linha começa com '$1')"; }
comeca "compose\.yaml:4:"                 "$saida" "compose.yaml entra na varredura"
comeca "compose\.yml:4:"                  "$saida" "compose.yml entra na varredura"
comeca "docker-compose\.override\.yaml:4:" "$saida" "docker-compose*.yaml entra na varredura"
nao_tem "senhaDoComposeYml1"          "$saida" "compose.yml: default mascarado"
nao_tem "senhaDoOverride22"           "$saida" "override .yaml: default mascarado"

echo "== política de máscara: até 12 caracteres, nada do valor; acima, no máximo 4 =="
for v in "$V6" "$V9" "$V12" "$V13"; do nao_tem ":-$v" "$saida" "default de ${#v}: nada do valor depois do :-"; done
tem "compose.yaml:4:      P6: \${P6:-…}"       "$saida" "default de 6 sai só como …"
tem "compose.yaml:5:      P9: \${P9:-…}"       "$saida" "default de 9 sai só como …"
tem "compose.yaml:6:      P12: \${P12:-…}"     "$saida" "default de 12 sai só como …"
tem "compose.yaml:7:      P13: \${P13:-trez…}" "$saida" "default de 13 sai com 4 + …"
for v in "$C9" "$C12" "$C13"; do nao_tem "$v" "$saida" "config de ${#v}: valor mascarado"; done
tem "tamanhos.yml:2:password: \"…"    "$saida" "config de 9 sai só como …"
tem "tamanhos.yml:3:secret: \"…"      "$saida" "config de 12 sai só como …"
tem "tamanhos.yml:4:token: \"ctre…"   "$saida" "config de 13 sai com 4 + …"

echo "== default aninhado, minúsculo e sem dois-pontos: o literal sai mascarado =="
# O re.sub parava na primeira }: em ${A:-${B}Literal…} o literal saía cru. O grep só achava nome
# maiúsculo com ":-", e ${db_pass:-…} e ${PW-…} nem entravam na varredura.
nao_tem "FALSO"                                   "$saida" "nenhum resto de default literal"
tem 'compose.yaml:8:      L1: ${A:-${B}Lite…}'    "$saida" "literal depois da } interna: 4 + …"
tem 'compose.yaml:9:      L2: ${A:-${B:-…}Lite…}' "$saida" "literal depois de default interno: 4 + …"
tem 'compose.yaml:10:      L3: ${db_pass:-Defa…}' "$saida" "nome minúsculo entra na varredura"
tem 'compose.yaml:11:      L4: ${PW-Outr…}'       "$saida" "default sem dois-pontos entra na varredura"
tem 'compose.yaml:12:      L5: ${A:-${B}}'        "$saida" "referência pura fica intacta"
tem 'compose.yaml:13:      L6: ${A:-${B:-${C}}}'  "$saida" "referência aninhada fica intacta"
tem 'compose.yaml:14:      L7: ${lower_pw-SemD…}' "$saida" "nome minúsculo sem dois-pontos entra na varredura"

echo "== byte fora de UTF-8 na linha não derruba a varredura =="
# Um comentário em Latin-1 na mesma linha do default: o grep do Linux, sem -a, cala a linha
# com byte inválido, e o default dela nem chega à máscara. O sed do macOS em locale UTF-8
# aborta com "illegal byte sequence" e leva junto os achados seguintes. PYTHONIOENCODING
# fixa a leitura estrita do python em qualquer locale (o C.UTF-8 do CI a relaxa).
L="$TMP/latin1"; mkdir -p "$L/dist"
printf 'services:\n  a:\n    environment:\n      DB_PASSWORD: ${DB_PASSWORD:-senhaValida12345} # caf\351\n      Z: ${Z:-outroDefaultDepois1}\n' > "$L/compose.yaml"
printf 'password: "valor\351ruim12345"\ntoken: "tokenDepoisDoByte99" # caf\351\nsecret: "segredoDepoisDoByte"\n' > "$L/cfg.yml"
printf '/* caf\351 */ const k="%s";\n' "$SK" > "$L/dist/app.js"
# O locale UTF-8 que a máquina tem: sem ele a glibc cai para C e o cenário passa até no código antigo.
U=$(locale -a 2>/dev/null | grep -iE '^(en_US|C)\.utf-?8$' | head -1)
sl=$(cd "$L" && LC_ALL="${U:-en_US.UTF-8}" PYTHONIOENCODING=utf-8:strict PATH=/usr/bin:/bin bash "$TMP/a4.sh" 2>&1)
nao_tem "Traceback"                   "$sl" "byte fora de UTF-8: sem Traceback"
nao_tem "illegal byte sequence"       "$sl" "byte fora de UTF-8: o sed não aborta"
tem "compose.yaml:4:"                 "$sl" "byte fora de UTF-8: a linha do byte continua achada"
tem "compose.yaml:5:"                 "$sl" "byte fora de UTF-8: o default seguinte não some"
tem "cfg.yml:1:"                      "$sl" "byte fora de UTF-8 dentro do valor: a config continua achada"
nao_tem "ruim12345"                   "$sl" "byte fora de UTF-8 dentro do valor: o valor continua mascarado"
tem "cfg.yml:2:"                      "$sl" "byte fora de UTF-8: a config com byte continua achada"
tem "cfg.yml:3:"                      "$sl" "byte fora de UTF-8: a config seguinte não some"
tem "dist/app.js:1:sk-F…"             "$sl" "byte fora de UTF-8: a chave do bundle continua achada"
nao_tem "senhaValida12345"            "$sl" "byte fora de UTF-8: o default continua mascarado"
nao_tem "tokenDepoisDoByte99"         "$sl" "byte fora de UTF-8: a config continua mascarada"
nao_tem "$SK"                         "$sl" "byte fora de UTF-8: a chave do bundle continua mascarada"

echo "== Fase 0: o ls de infra lista os nomes do Compose v2 =="
awk '/^## Fase 0 /{a=1} a && /^```bash/{b=1; next} b && /^```/{exit} b' "$SKILL" > "$TMP/fase0.sh"
f0=$(cd "$R" && PATH=/usr/bin:/bin bash "$TMP/fase0.sh" 2>&1)
tem "compose.yaml"                    "$f0" "Fase 0 lista compose.yaml"
tem "docker-compose.override.yaml"    "$f0" "Fase 0 lista docker-compose*.yaml"

echo "== Fase 6: o trecho de achado de segredo sai cortado no valor e passa no --verificar =="
# O bloco da Fase 6 marcado "# trecho de achado de segredo", com <linha> e <arquivo> trocados.
awk '/^## Fase 6 /{a=1} a && /^```bash/{b=1; buf=""; next} b && /^```/{if (buf ~ /# trecho de achado de segredo/) {printf "%s", buf; exit} b=0; next} b {buf = buf $0 "\n"}' \
  "$SKILL" > "$TMP/fase6.sh"
trecho() { # trecho <arquivo> <linha> — roda o bloco da Fase 6; deixa a saída em $T6 e o exit em $X6
  sed -e "s|<arquivo>|$1|g" -e "s|<linha>|$2|g" "$TMP/fase6.sh" > "$TMP/fase6-run.sh"
  T6=$(cd "$R" && PYTHONIOENCODING=utf-8:strict PATH=/usr/bin:/bin bash "$TMP/fase6-run.sh" 2>/dev/null); X6=$?
}
if [ ! -s "$TMP/fase6.sh" ]; then
  falha "bloco '# trecho de achado de segredo' não encontrado na Fase 6"
else
  trecho config.yml 2
  nao_tem "$CFG" "$T6" "config.yml:2: o valor não sai"
  tem "api_key: \"valo  // valor mascarado" "$T6" "config.yml:2: cortado nos 4 caracteres, com a anotação"
  trecho tamanhos.yml 3
  nao_tem "$C12" "$T6" "valor de 12: não sai"
  tem "secret: \"  // valor mascarado" "$T6" "valor de 12: nenhum caractere"
  trecho dist/chaves.js 1
  nao_tem "$SKP" "$T6" "sk-proj-: não sai"
  tem "sk-p  // valor mascarado" "$T6" "sk-proj-: 4 caracteres"
  trecho dist/chaves.js 5
  nao_tem "$SKA" "$T6" "sk-ant-: não sai"
  tem "sk-a  // valor mascarado" "$T6" "sk-ant-: 4 caracteres"
  trecho docker-compose.yml 4
  nao_tem ":-$DEF" "$T6" "default: nada do valor depois do :-"
  cp "$L/compose.yaml" "$R/latin1.yaml"
  trecho latin1.yaml 4
  [ "$X6" -eq 0 ] && ok "byte fora de UTF-8 na linha: o trecho sai (exit $X6)" || falha "byte fora de UTF-8 derrubou o bloco da Fase 6 (exit $X6)"
  nao_tem "senhaValida12345" "$T6" "byte fora de UTF-8: o valor não sai no trecho"
  trecho config.yml 1
  [ "$X6" -ne 0 ] && [ -z "$T6" ] && ok "linha sem segredo reconhecido: não imprime nada e sai ≠ 0" \
    || falha "linha sem segredo reconhecido saiu $X6 com: $T6"

  # o trecho mascarado passa no --verificar do gerador, contra o arquivo de verdade
  GER="$(dirname "$SKILL")/scripts/gerar-relatorio.py"
  EXE="$(dirname "$SKILL")/references/exemplo-findings.json"
  trecho config.yml 2
  T6="$T6" python3 - "$EXE" "$TMP/f6.json" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1]))
a = d["achados"][0]
a.update(categoria="A4", arquivo="config.yml", linhas="2", trecho=os.environ["T6"])
d["achados"] = [a]
d["issues"] = []
d["recomendacoes"] = []
json.dump(d, open(sys.argv[2], "w"), ensure_ascii=False)
PY
  v=$(python3 "$GER" "$TMP/f6.json" --verificar --raiz "$R" 2>&1); xv=$?
  [ "$xv" -eq 0 ] && ok "--verificar aceita o trecho mascarado" || falha "--verificar recusou o trecho mascarado: $v"

  echo "== Fase 6: a janela antes do valor não carrega outro segredo =="
  # Antes a lista da Fase 6 não reconhecia token do GitHub, do Slack nem a senha de URL:
  # o corte caía na chave seguinte, e o segredo dos 60 caracteres anteriores saía cru. As três
  # linhas são as da reprodução do revisor; as demais cobrem cada prefixo novo.
  GHP="gh""p_FALSO$(rep Z 32)"; GHO="gh""o_FALSO$(rep Y 32)"; GPAT="github""_pat_FALSO$(rep X 30)"
  XOX="xo""xb-FALSO$(rep W 26)"; XOP="xo""xp-FALSO$(rep V 26)"; GLP="gl""pat-FALSO$(rep U 20)"
  AKI="AK""IAFALSO$(rep 7 11)"; WHS="wh""sec_FALSO$(rep T 24)"; SEN="SenhaForte123"
  {
    printf 'const gh="%s", k="%s";\n' "$GHP" "$SKP"
    printf 'const a="%s"; const b="%s";\n' "$XOX" "$SKL"
    printf 'DATABASE_URL=postgres://u:%s@h/db API_KEY=%s\n' "$SEN" "$SKL"
    printf 'o="%s", k="%s";\n' "$GHO" "$SKL"
    printf 'p="%s", k="%s";\n' "$GPAT" "$SKL"
    printf 's="%s", k="%s";\n' "$XOP" "$SKL"
    printf 'g="%s", k="%s";\n' "$GLP" "$SKL"
    printf 'w="%s", k="%s";\n' "$AKI" "$SKL"
    printf 'h="%s", k="%s";\n' "$WHS" "$SKL"
    printf 'REDIS_URL=redis://:%s@cache:6379\n' "$SEN"
    printf 'DB=postgres://u:${DB_PASS}@h/db\n'
    printf 'u="postgres://u:$ecretFALSO9999@h/d";k="%s"\n' "$GHP"
    printf 'DB=postgres://u:$DB_PASS@h/db\n'
  } > "$R/janela.js"
  exato() { [ "$T6" = "$1" ] && ok "$2" || falha "$2 (saiu: $T6)"; }
  trecho janela.js 1; nao_tem "$GHP" "$T6" "linha 1: ghp_ não sai";  exato 'const gh="ghp_  // valor mascarado' "linha 1: corta no ghp_"
  trecho janela.js 2; nao_tem "$XOX" "$T6" "linha 2: xoxb- não sai"; exato 'const a="xoxb  // valor mascarado' "linha 2: corta no xoxb-"
  trecho janela.js 3; nao_tem "$SEN" "$T6" "linha 3: senha da URL não sai"
  exato 'DATABASE_URL=postgres://u:Senh  // valor mascarado' "linha 3: corta na senha da URL"
  n=4
  for v in "$GHO" "$GPAT" "$XOP" "$GLP" "$AKI" "$WHS"; do
    trecho janela.js $n
    nao_tem "$v" "$T6" "linha $n: ${v:0:4}… não sai"
    nao_tem "FALSO" "$T6" "linha $n: nada depois dos 4 caracteres"
    tem "=\"${v:0:4}  // valor mascarado" "$T6" "linha $n: corta em ${v:0:4}"
    n=$((n+1))
  done
  trecho janela.js 10; exato 'REDIS_URL=redis://:Senh  // valor mascarado' "URL sem usuário: corta na senha"
  trecho janela.js 11
  [ "$X6" -ne 0 ] && [ -z "$T6" ] && ok 'URL com ${VAR} no lugar da senha não é achado' \
    || falha "URL com \${VAR} virou achado: $T6"
  # senha de URL que começa com $: só $NOME de env (maiúsculas e _) e ${…} são referência
  trecho janela.js 12; nao_tem "FALSO" "$T6" 'URL com $ecret: nada da senha'
  exato 'u="postgres://u:$ecr  // valor mascarado' 'URL com $ecret: corta na senha'
  trecho janela.js 13
  [ "$X6" -ne 0 ] && [ -z "$T6" ] && ok 'URL com $NOME no lugar da senha não é achado' \
    || falha "URL com \$DB_PASS virou achado: $T6"
  trecho janela.js 3
  T6="$T6" python3 - "$EXE" "$TMP/f6b.json" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1]))
a = d["achados"][0]
a.update(categoria="A4", arquivo="janela.js", linhas="3", trecho=os.environ["T6"])
d["achados"] = [a]
d["issues"] = []
d["recomendacoes"] = []
json.dump(d, open(sys.argv[2], "w"), ensure_ascii=False)
PY
  v=$(python3 "$GER" "$TMP/f6b.json" --verificar --raiz "$R" 2>&1); xv=$?
  [ "$xv" -eq 0 ] && ok "--verificar aceita o corte na senha da URL" || falha "--verificar recusou o corte na URL: $v"

  # Até 60 caracteres antes do corte saíam crus: um token que o bloco não reconhecia, na mesma
  # linha e antes da chave reconhecida, ia inteiro para o trecho (e daí para o PDF e a issue).
  # As três linhas da revisão da 0.43.1, mais os outros prefixos de fornecedor.
  GHP="gh""p_FALSO$(rep Z 32)"; GHO="gh""o_FALSO$(rep Y 32)"; GPAT="github""_pat_FALSO$(rep X 40)"
  XOX="xo""xb-FALSO$(rep W 26)"; GLP="gl""pat-FALSO$(rep V 20)"; AWS="AK""IAFALSO$(rep Q 11)"
  WHS="wh""sec_FALSO$(rep U 28)"; SENHA="SenhaFalsa$(rep 9 6)"
  printf 'const gh="%s", k="%s";\n' "$GHP" "$SKP" > "$R/dist/revisao.js"
  printf 'const a="%s"; const b="%s";\n' "$XOX" "$SKL" >> "$R/dist/revisao.js"
  printf 'DATABASE_URL=postgres://u:%s@h/db API_KEY=%s\n' "$SENHA" "$SKL" >> "$R/dist/revisao.js"
  printf 'x = ["%s", "%s", "%s", "%s", "%s", "%s"]\n' "$GHO" "$GPAT" "$GLP" "$AWS" "$WHS" "$SKL" >> "$R/dist/revisao.js"
  verifica_trecho() { # <arquivo> <linha> — o trecho em $T6 passa no --verificar contra o arquivo real
    T6="$T6" python3 - "$EXE" "$TMP/f6.json" "$1" "$2" <<'PYF'
import json, os, sys
d = json.load(open(sys.argv[1]))
a = d["achados"][0]
a.update(categoria="A4", arquivo=sys.argv[3], linhas=sys.argv[4], trecho=os.environ["T6"])
d["achados"] = [a]
d["issues"] = []
d["recomendacoes"] = []
json.dump(d, open(sys.argv[2], "w"), ensure_ascii=False)
PYF
    python3 "$GER" "$TMP/f6.json" --verificar --raiz "$R" >/dev/null 2>&1
  }
  for n in 1 2 3 4; do
    trecho dist/revisao.js "$n"
    [ "$X6" -eq 0 ] && [ -n "$T6" ] || falha "revisao.js:$n: o bloco não achou segredo (exit $X6)"
    vazou=""
    for v in "$GHP" "$SKP" "$XOX" "$SKL" "$SENHA" "$GHO" "$GPAT" "$GLP" "$AWS" "$WHS"; do
      case "$T6" in *"$v"*) vazou="$vazou ${v:0:6}";; esac
    done
    [ -z "$vazou" ] && ok "revisao.js:$n: nenhum valor sai inteiro" || falha "revisao.js:$n: valor inteiro no trecho:$vazou ($T6)"
    verifica_trecho dist/revisao.js "$n" && ok "revisao.js:$n: o --verificar aceita o trecho" \
      || falha "revisao.js:$n: o --verificar recusou: $T6"
  done
  trecho dist/revisao.js 3
  tem "postgres://u:" "$T6" "senha em URL: o corte fica na senha, depois do usuário"
  nao_tem "SenhaF" "$T6" "senha em URL: não passa dos 4 primeiros"
  printf 'u = "postgres://u:${DB_PASSWORD}@h/db"\n' > "$R/ref-url.txt"
  trecho ref-url.txt 1
  [ "$X6" -ne 0 ] && ok "senha em URL que é \${VAR}: referência, não achado" || falha "\${VAR} na URL virou achado: $T6"

  # Todo prefixo que a Fase 6 reconhece sai redigido pelo gerador, também colado em %20 e em _
  # (o \b dos prefixos específicos deixava passar Bearer%20ghp_… e x_xoxs-…). Cada amostra
  # passa antes pelo bloco da Fase 6: amostra que ele não reconhece não prova nada aqui.
  B64='{"alg":"HS256"}'; JWT2="$(b64url "$B64").$(b64url '{"role":"anon"}').$(rep t 30)"
  AMOSTRAS=("sk-""proj-FALSO$(rep b 30)" "sk-""ant-api03-FALSO$(rep f 30)" "sk-FALSO$(rep a 30)"
    "sk_""live_FALSO$(rep c 24)" "rk_""test_FALSO$(rep e 24)" "$JWT2" "sb""p_$(rep 0 30)" "AK""IAFALSO$(rep Q 11)"
    "gh""p_FALSO$(rep Z 32)" "gh""o_FALSO$(rep Z 32)" "gh""u_FALSO$(rep Z 32)" "gh""s_FALSO$(rep Z 32)"
    "gh""r_FALSO$(rep Z 32)" "github""_pat_FALSO$(rep X 40)" "xo""xa-FALSO$(rep W 26)" "xo""xb-FALSO$(rep W 26)"
    "xo""xp-FALSO$(rep W 26)" "xo""xr-FALSO$(rep W 26)" "xo""xs-FALSO$(rep W 26)" "gl""pat-FALSO$(rep V 20)"
    "wh""sec_FALSO$(rep U 28)")
  : > "$R/prefixos.txt"
  for v in "${AMOSTRAS[@]}"; do printf 'k = "%s"\n' "$v" >> "$R/prefixos.txt"; done
  n=0; fora=""
  for v in "${AMOSTRAS[@]}"; do n=$((n+1)); trecho prefixos.txt "$n"; [ "$X6" -eq 0 ] || fora="$fora ${v:0:6}"; done
  [ -z "$fora" ] && ok "as ${#AMOSTRAS[@]} amostras são prefixos que a Fase 6 reconhece" || falha "a Fase 6 não reconhece:$fora"
  AMOSTRAS+=("postgres://u:SenhaFalsa$(rep 8 6)@h/db")
  # o sk- genérico fica com a fronteira (senão "task-list-…" vira chave): só no contexto puro.
  # Função, e não o laço dentro do $(…): no bash 3.2 do macOS o ")" do case fecha a substituição.
  amostras_txt() {
    local v
    for v in "${AMOSTRAS[@]}"; do
      printf 'a = "%s"\n' "$v"
      case "$v" in
        sk-FALSO*) ;;
        *) printf 'b = "Bearer%%20%s"\nc = x_%s\n' "$v" "$v" ;;
      esac
    done
  }
  AMOSTRAS_TXT="$(amostras_txt)" \
  python3 - "$EXE" "$TMP/pref.json" <<'PYP'
import json, os, sys
d = json.load(open(sys.argv[1]))
d["achados"][0]["trecho"] = os.environ["AMOSTRAS_TXT"]
d["issues"][0]["achados"] = [d["achados"][0]["id"]]
d["issues"][1]["markdown"] = "```\n" + os.environ["AMOSTRAS_TXT"] + "\n```"
json.dump(d, open(sys.argv[2], "w"))
PYP
  python3 "$GER" "$TMP/pref.json" --out "$TMP/pref.pdf" --html-only >/dev/null 2>&1 || falha "gerador falhou com as amostras"
  [ "$(grep -c 'Bearer%20' "$TMP/pref.json")" -ge 1 ] && [ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["achados"][0]["trecho"].splitlines()))' "$TMP/pref.json")" -ge 60 ] \
    && ok "as amostras entram no trecho nos três contextos" || falha "as amostras não chegaram ao trecho do gerador"
  vazou=""
  for v in "${AMOSTRAS[@]}"; do
    s="${v#postgres://u:}"; s="${s%@h/db}"
    grep -qF "$s" "$TMP/pref.html" && vazou="$vazou ${v:0:6}"
  done
  [ -z "$vazou" ] && ok "gerador: todo prefixo da Fase 6 sai redigido, puro, depois de %20 e depois de _ (sk- genérico só puro)" \
    || falha "gerador deixou passar inteiro:$vazou"

  echo "== Fase 6: paridade reversa — o que o gerador redige, a Fase 6 reconhece e corta antes =="
  # O 12d do test-auditoria-relatorio prova Fase 6 → gerador. Este é o inverso: formato que só o
  # gerador conhecia (rk-, sb_secret_, sbs_, xapp-, shpat_, sk-svcacct-, pwd=, AWS_SECRET_ACCESS_KEY=,
  # ${db_pass:-…}, ${PW-…}, $ecret na URL, o literal depois da } interna) saía cru nos 60
  # caracteres antes do corte. As regex do gerador têm lookahead, lookbehind e função, e não dá
  # para tirar amostra delas como o 12d tira da lista pads: o conjunto é fixo e está abaixo. A
  # guarda é automática: cada padrão do gerador (cada alternativa das listas de prefixo, o default
  # e as duas atribuições) tem de casar pelo menos uma amostra, e padrão novo sem amostra reprova.
  # Cada amostra roda sozinha no bloco da Fase 6, que tem de reconhecê-la (exit 0) e cortar antes
  # do valor: nenhum pedaço de 8 caracteres dele no que sai.
  rev=$(PYTHONIOENCODING=utf-8:strict python3 - "$TMP/fase6.sh" "$GER" "$TMP" <<'PY'
import importlib.util, os, re, subprocess, sys
fase6, ger, tmp = sys.argv[1:4]
spec = importlib.util.spec_from_file_location("g", ger); g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
F = "FALSO"
def tok(prefixo, n, c="Q"): return prefixo + F + c * n
AMOSTRAS = []   # (linha, valor que não pode sair)
def am(linha, v): AMOSTRAS.append((linha, v))
for pre, n in (("sk_" "live_", 20), ("sk_" "test_", 20), ("rk_" "live_", 20), ("rk_" "test_", 20),
               ("sk-" "proj-", 20), ("sk-" "ant-", 20), ("sk-" "svcacct-", 20), ("sk-" "admin-", 20),
               ("wh" "sec_", 20), ("gh" "p_", 24), ("gh" "o_", 24), ("github" "_pat_", 24),
               ("xo" "xb-", 12), ("xa" "pp-", 12), ("gl" "pat-", 20), ("sb" "p_", 12), ("sb" "s_", 12),
               ("sb_" "secret_", 20), ("sh" "pat_", 12), ("np" "m_", 31), ("h" "f_", 30)):
    v = tok(pre, n)
    am(f'x = "Bearer%20{v}";', v)
for pre in ("sk-", "rk-"):
    v = tok(pre, 16); am(f'k = "{v}";', v)
v = "AI" "za" + F + "g" * 30; am(f'g = "x_{v}";', v)
v = "S" "G." + F + "s" * 18 + "." + F + "t" * 38; am(f'm = "{v}";', v)   # 23: a fixture do revisor
v = "AK" "IA" + F + "7" * 11; am(f"aws = {v}", v)
v = "eyJ" + F + "jwtjwt" + "x" * 20; am(f'h = "Bearer%20{v}";', v)
v = "MII" + F + "p" * 40
am(f'k = "-----BEGIN RSA PRIVATE KEY-----{v}-----END RSA PRIVATE KEY-----"', v)
v = "Senha" + F + "9999"; am(f'DB = "postgres://u:{v}@h/d"', v)
v = "$ecret" + F + "9999"; am(f'u = "postgres://u:{v}@h/d"', v)
v = "Redis" + F + "9999"; am(f"R=redis://:{v}@cache:6379", v)
v = "Default" + F + "senha1"; am(f"x: ${{DB_PASSWORD:-{v}}}", v)
v = "Default" + F + "senha2"; am(f"x=${{db_pass:-{v}}}", v)
v = "Outra" + F + "senha3"; am(f"y=${{PW-{v}}}", v)
v = "SemDois" + F + "pontos"; am(f"z=${{lower_pw-{v}}}", v)   # a L17 da fixture do revisor
v = "Literal" + F + "123"; am(f"L1: ${{A:-${{B}}{v}}}", v)
v = "Literal" + F + "456"; am(f"L2: ${{A:-${{B:-curto}}{v}}}", v)
v = "frase " + F + " com espaco"; am(f'password = "{v}"', v)
v = "chave" + F + "json123"; am(f'"secretKey": "{v}"', v)
v = "seta" + F + "php1234"; am(f"'api_key' => '{v}'", v)
v = "minha." + F + ".senha"; am(f"DB_PASSWORD={v}", v)
v = "abc(" + F + "123)"; am(f"pwd={v}", v)
v = "wJalr" + F + "awsawsaws"; am(f"AWS_SECRET_ACCESS_KEY={v}", v)
v = "senha" + F + "12345"; am(f"senha: {v}", v)

falhas = []
def alternativas(p):
    if not p.startswith("(?:") or not p.endswith(")"): return [p]
    corpo, partes, prof, cls, atual = p[3:-1], [], 0, False, ""
    for i, c in enumerate(corpo):
        esc = i > 0 and corpo[i - 1] == "\\"
        if c == "[" and not esc: cls = True
        elif c == "]" and not esc: cls = False
        elif not cls and not esc and c == "(": prof += 1
        elif not cls and not esc and c == ")": prof -= 1
        if c == "|" and prof == 0 and not cls: partes.append(atual); atual = ""
        else: atual += c
    return partes + [atual]
unidades = [a for p, _ in g.PADROES_SEGREDO for a in alternativas(p.pattern)]
# o default do compose pode morar fora da lista (casamento de chaves aninhadas)
unidades += [getattr(g, n).pattern for n in ("_DEFAULT", "_ATRIB_ASPAS", "_ATRIB_NUA") if hasattr(g, n)]
for u in unidades:
    if not any(re.search(u, l) for l, _ in AMOSTRAS):
        falhas.append(f"padrão do gerador sem amostra na paridade reversa: {u[:70]}")

bloco = open(fase6, encoding="utf-8").read()
arq = os.path.join(tmp, "reversa.txt")
with open(arq, "w", encoding="utf-8") as f:
    f.write("\n".join(l for l, _ in AMOSTRAS) + "\n")
env = dict(os.environ, PATH="/usr/bin:/bin")
for n, (linha, v) in enumerate(AMOSTRAS, 1):
    red, _ = g.redigir_segredos(linha)
    if v in red:
        falhas.append(f"amostra que o gerador não redige (conserte a amostra): {linha[:40]}"); continue
    sc = bloco.replace("<arquivo>", arq).replace("<linha>", str(n))
    r = subprocess.run(["bash", "-c", sc], capture_output=True, text=True, env=env)
    pedacos = [v[k:k + 8] for k in range(len(v) - 7)]
    if r.returncode != 0:
        falhas.append(f"a Fase 6 não reconhece: {linha.replace(v, v[:4] + '…')}")
    elif any(p in r.stdout for p in pedacos):
        falhas.append(f"a Fase 6 corta depois do valor: {r.stdout.strip().replace(F, '*****')[:90]}")
for f in falhas:
    print("  FALHA paridade reversa:", f)
if not falhas:
    print(f"  ok    paridade reversa: {len(AMOSTRAS)} amostras cobrem {len(unidades)} padrões do gerador, "
          "e a Fase 6 corta antes de cada valor")
PY
)
  echo "$rev"
  case "$rev" in *"ok    paridade reversa"*) ;; *) falhas=$((falhas + 1)) ;; esac
fi
# Nenhum `sed -n` da skill copia linha para a conversa sem passar pela máscara.
sem=$(grep -n 'sed -n' "$SKILL" | grep -v '| python3' | grep -vi 'segredo')
[ -z "$sem" ] && ok "todo sed -n da skill passa pela máscara ou exclui segredo" \
  || falha "sed -n que copia linha sem máscara: $sem"

echo "== sem build no disco, o bloco não roda o build do repo auditado =="
# npm falso no PATH: se o bloco chamar npm, a marca aparece na pasta do repo
S="$TMP/sem-build"; mkdir -p "$S" "$TMP/bin"
printf '{"name":"alvo","scripts":{"build":"echo build"}}\n' > "$S/package.json"
printf '#!/bin/sh\ntouch "$PWD/NPM_RODOU"\n' > "$TMP/bin/npm"; chmod +x "$TMP/bin/npm"
(cd "$S" && PATH="$TMP/bin:/usr/bin:/bin" bash "$TMP/a4.sh" >/dev/null 2>&1)
[ ! -e "$S/NPM_RODOU" ] && ok "npm não foi chamado" \
  || falha "o bloco chamou npm no repo auditado (build executa script dele e grava fora de docs/security-audit/)"

echo "== sem build, a A4 pergunta com o comando pronto e declara a cobertura =="
secao=$(awk '/^## A4 /{a=1; next} a && /^## /{exit} a' "$SKILL")
tem 'Posso rodar `npm run build`'   "$secao" "o build é pergunta, com o comando pronto"
tem 'grava `dist/`'                  "$secao" "a pergunta diz o que o build grava"
tem '`npm ci`'                       "$secao" "sem node_modules, a pergunta cita o npm ci e o que ele roda"
tem '"categoria": "A4"'              "$secao" "o bundle sem varrer entra na cobertura[] da A4"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
