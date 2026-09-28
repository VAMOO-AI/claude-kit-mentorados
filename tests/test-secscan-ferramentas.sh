#!/usr/bin/env bash
# A Fase 0.5 da skill secscan diz "AUSENTE" só quando o scanner não está instalado.
#
# O bloco era `command -v X && X ... || echo "X AUSENTE"`: qualquer saída ≠ 0 do scanner
# caía no `||`. O semgrep sem rede (não baixa o ruleset p/owasp-top-ten) virava "AUSENTE",
# e a skill oferecia instalar o que já estava instalado. Pior no gitleaks e no osv-scanner,
# que saem com 1 justamente quando ACHAM algo: segredo encontrado virava "gitleaks
# AUSENTE", e a linha da tabela ia para `não medido (gitleaks ausente)`. O semgrep que
# falha mostra o exit e a última linha do erro: a causa vai para o relatório.
#
# Na Fase 4 era o mesmo tipo de silêncio: `ls … | head -1 || echo "SEM LOCKFILE"` nunca
# imprimia, porque o exit do pipe é o do `head`, que sai 0 mesmo sem nada para ler.
# Fora de repositório git o gitleaks imprime "not a git repository" e sai 0, que a legenda
# lia como limpo: sem git, o histórico é "não medido (sem git)" — pela ausência do repo ou
# pela mensagem. E o `gitleaks detect` só lê o histórico: segredo ainda não commitado
# passava, então a árvore de trabalho entra com `gitleaks dir` (ou `detect --no-git` nas
# versões sem `dir`), sempre com --redact.
#
# O teste roda os blocos do SKILL.md, sem cópia, com binários falsos (ou nenhum) no PATH.
# O caso de ponta a ponta usa o gitleaks de verdade quando ele está instalado.
#
# Uso: bash tests/test-secscan-ferramentas.sh [caminho-do-SKILL.md]
set -uo pipefail
SKILL="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/secscan/SKILL.md}"
[ -f "$SKILL" ] || { echo "SKILL.md não encontrado: $SKILL"; exit 2; }

falhas=0
TMP=$(mktemp -d "${TMPDIR:-/tmp}/secscan-ferr.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
tem()     { case "$2" in *"$1"*) ok "$3" ;; *) falha "$3 (não achei '$1' em: $2)" ;; esac; }
nao_tem() { case "$2" in *"$1"*) falha "$3 (achei '$1' em: $2)" ;; *) ok "$3" ;; esac; }

bloco() { # bloco <regex-do-título> → o primeiro ```bash depois do título
  awk -v t="$1" '$0 ~ t {a=1} a && /^```bash/{b=1; next} b && /^```/{exit} b' "$SKILL"
}
bloco '^## Fase 0\.5' > "$TMP/fase05.sh"
[ -s "$TMP/fase05.sh" ] || { echo "bloco bash da Fase 0.5 não encontrado em $SKILL"; exit 2; }

falso() { # falso <caso> <binário> <exit> [linha-de-stderr]: imprime os args e sai com <exit>
  mkdir -p "$TMP/$1/bin"
  {
    printf '#!/bin/sh\n'
    printf 'if [ "$1" = "--help" ]; then echo "  dir         scan directories or files for secrets"; exit 0; fi\n'
    printf 'echo "%s falso rodou: $*"; echo "$*" >> "%s/args.log"\n' "$2" "$TMP/$1"
    [ -n "${4:-}" ] && printf 'echo "%s" >&2\n' "$4"
    printf 'exit %s\n' "$3"
  } > "$TMP/$1/bin/$2"
  chmod +x "$TMP/$1/bin/$2"
}
roda() { # roda <caso> → saída do bloco, rodado dentro de um projeto vazio
  mkdir -p "$TMP/$1/bin" "$TMP/$1/proj"
  (cd "$TMP/$1/proj" && PATH="$TMP/$1/bin:/usr/bin:/bin" bash "$TMP/fase05.sh" 2>&1)
}

echo "== nenhum scanner instalado: os três AUSENTE =="
out=$(roda nada)
tem "semgrep AUSENTE"     "$out" "semgrep ausente"
tem "gitleaks AUSENTE"    "$out" "gitleaks ausente"
tem "osv-scanner AUSENTE" "$out" "osv-scanner ausente"

echo "== semgrep instalado que falha (sem rede para baixar o ruleset) =="
falso semfalha semgrep 2 "Failed to download configuration p/owasp-top-ten"
out=$(roda semfalha)
tem "scan --config p/owasp-top-ten" "$(cat "$TMP/semfalha/args.log" 2>/dev/null)" "o semgrep rodou"
nao_tem "semgrep AUSENTE"  "$out" "…e não sai como ausente"
tem "semgrep FALHOU"       "$out" "…sai como falhou"
tem "exit 2"               "$out" "…com o código de saída"
tem "última linha: Failed to download configuration p/owasp-top-ten" "$out" "…e a última linha do erro"

echo "== semgrep que roda bem, com o SARIF em secscan-reports/ =="
falso semok semgrep 0
out=$(roda semok)
nao_tem "semgrep AUSENTE"  "$out" "semgrep ok não sai como ausente"
nao_tem "semgrep FALHOU"   "$out" "…nem como falhou"
args=$(cat "$TMP/semok/args.log" 2>/dev/null)
tem "--output secscan-reports/secscan.sarif" "$args" "o SARIF vai para secscan-reports/, pelos argumentos do semgrep"
tem "--metrics=off"        "$args" "…com --metrics=off"
[ -d "$TMP/semok/proj/secscan-reports" ] && ok "…e o diretório existe" || falha "…o diretório secscan-reports/ não foi criado"

echo "== gitleaks que acha segredo (sai 1) =="
falso gl1 gitleaks 1
mkdir -p "$TMP/gl1/proj"; git -C "$TMP/gl1/proj" init -q
out=$(roda gl1)
nao_tem "gitleaks AUSENTE"      "$out" "segredo encontrado não vira gitleaks ausente"
tem "gitleaks histórico exit 1" "$out" "…o histórico diz o código, que a legenda lê como achado"
tem "gitleaks árvore exit 1"    "$out" "…e a árvore de trabalho também"
tem "1 achou"                   "$out" "…com a legenda impressa"

echo "== gitleaks varre a árvore de trabalho, sempre com --redact =="
tem "gitleaks falso rodou: dir" "$out" "a árvore de trabalho entra com gitleaks dir"
linhas=$(printf '%s\n' "$out" | grep -c 'gitleaks falso rodou')
redact=$(printf '%s\n' "$out" | grep 'gitleaks falso rodou' | grep -c -- '--redact')
[ "$linhas" -ge 2 ] && [ "$linhas" = "$redact" ] \
  && ok "as $linhas chamadas do gitleaks levam --redact" \
  || falha "chamadas do gitleaks: $linhas, com --redact: $redact"

echo "== gitleaks antigo, sem o subcomando dir: a árvore cai para detect --no-git =="
mkdir -p "$TMP/glvelho/bin"
cat > "$TMP/glvelho/bin/gitleaks" <<SH
#!/bin/sh
if [ "\$1" = "--help" ]; then echo "  detect      detect secrets in code"; exit 0; fi
echo "gitleaks falso rodou: \$*"; exit 0
SH
chmod +x "$TMP/glvelho/bin/gitleaks"
mkdir -p "$TMP/glvelho/proj"; git -C "$TMP/glvelho/proj" init -q
out=$(roda glvelho)
tem "rodou: detect --no-git"   "$out" "sem dir: a árvore roda com detect --no-git"
nao_tem "rodou: dir"           "$out" "…e não chama um subcomando que não existe"

echo "== gitleaks fora de repositório git =="
falso glsemgit gitleaks 0
out=$(roda glsemgit)
tem "gitleaks histórico não medido (sem git)" "$out" "sem git: o histórico sai 'não medido (sem git)'"
nao_tem "gitleaks histórico exit 0"           "$out" "…e não vira 'exit 0', que a legenda lê como limpo"
tem "gitleaks árvore exit 0"                  "$out" "…a árvore de trabalho continua medida sem git"

echo "== gitleaks que imprime 'not a git repository' e sai 0, dentro de um .git =="
mkdir -p "$TMP/glmsg/bin"
cat > "$TMP/glmsg/bin/gitleaks" <<'SH'
#!/bin/sh
if [ "$1" = "--help" ]; then echo "  dir         scan directories or files for secrets"; exit 0; fi
case "$1" in detect|git) echo "fatal: not a git repository (or any of the parent directories): .git" >&2 ;; esac
exit 0
SH
chmod +x "$TMP/glmsg/bin/gitleaks"
mkdir -p "$TMP/glmsg/proj"; git -C "$TMP/glmsg/proj" init -q
out=$(roda glmsg)
tem "gitleaks histórico não medido (sem git)" "$out" "a mensagem 'not a git repository' vira 'não medido (sem git)'"
nao_tem "gitleaks histórico exit 0"           "$out" "…e não vira limpo"

echo "== gitleaks dentro de repositório git que sai 0 =="
falso glgit gitleaks 0
mkdir -p "$TMP/glgit/proj"; git -C "$TMP/glgit/proj" init -q
out=$(roda glgit)
tem "gitleaks histórico exit 0" "$out" "com git: o exit 0 continua sendo lido"
nao_tem "sem git"               "$out" "…e não diz sem git"

echo "== osv-scanner que acha vulnerabilidade (sai 1) =="
falso osv1 osv-scanner 1
out=$(roda osv1)
nao_tem "osv-scanner AUSENTE" "$out" "vulnerabilidade encontrada não vira osv-scanner ausente"
tem "osv-scanner exit 1"      "$out" "…a saída diz o código"
tem "128 sem lockfile"        "$out" "…e a legenda conhece o 128"

echo "== gitleaks de verdade: segredo não commitado aparece, e o valor não =="
if command -v gitleaks >/dev/null; then
  mkdir -p "$TMP/real/bin" "$TMP/real/proj"; git -C "$TMP/real/proj" init -q
  ln -s "$(command -v gitleaks)" "$TMP/real/bin/gitleaks"   # só ele: semgrep/osv da máquina ficam fora
  token="ghp_$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36)"
  printf 'const k = "%s";\n' "$token" > "$TMP/real/proj/config.js"
  out=$(roda real)
  tem "gitleaks árvore exit 1" "$out" "o segredo não commitado é achado pela árvore de trabalho"
  nao_tem "$token"             "$out" "…e o valor não aparece em nenhum campo da saída"
else
  echo "  pulado: gitleaks não instalado nesta máquina"
fi

echo "== Fase 4: lockfile por teste explícito =="
bloco '^## Fase 4' > "$TMP/fase4.sh"
[ -s "$TMP/fase4.sh" ] || { echo "bloco bash da Fase 4 não encontrado em $SKILL"; exit 2; }
# PATH só com ls e head: sem npm nem pnpm, o bloco ainda tem de dizer o que falta.
mkdir -p "$TMP/binmin"
for c in ls head; do ln -s "$(command -v "$c")" "$TMP/binmin/$c"; done
fase4() { (cd "$1" && PATH="$TMP/binmin" "$BASH" "$TMP/fase4.sh" 2>&1); }
mkdir -p "$TMP/f4-vazio"
out=$(fase4 "$TMP/f4-vazio")
tem "SEM LOCKFILE"           "$out" "sem lockfile: a Fase 4 diz SEM LOCKFILE"
for lf in package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb; do
  mkdir -p "$TMP/f4-$lf"; : > "$TMP/f4-$lf/$lf"
  out=$(fase4 "$TMP/f4-$lf")
  tem "lockfile: $lf"        "$out" "com $lf: diz qual lockfile achou"
  nao_tem "SEM LOCKFILE"     "$out" "…e não diz SEM LOCKFILE"
done

echo "== nenhum scanner sobrou com '&& … || echo AUSENTE' no SKILL.md =="
restos=$(grep -nE 'command -v [a-z-]+ *&&.*\|\| *echo .*AUSENTE' "$SKILL")
[ -z "$restos" ] && ok "nenhuma cópia do padrão" || falha "padrão antigo ainda presente: $restos"

echo "== a regra de estado da tabela conhece o scanner que falhou =="
grep -q 'não medido (<ferramenta> falhou' "$SKILL" \
  && ok "o estado 'não medido (<ferramenta> falhou…)' está no texto" \
  || falha "a tabela só conhece 'ausente': o semgrep que falhou vira ausente na tabela"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
