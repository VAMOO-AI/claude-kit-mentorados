#!/usr/bin/env bash
# A Fase 0.5 da skill secscan diz "AUSENTE" só quando o scanner não está instalado.
#
# O bloco era `command -v X && X ... || echo "X AUSENTE"`: qualquer saída ≠ 0 do scanner
# caía no `||`. O semgrep sem rede (não baixa o ruleset p/owasp-top-ten) virava "AUSENTE",
# e a skill oferecia instalar o que já estava instalado. Pior no gitleaks e no osv-scanner,
# que saem com 1 justamente quando ACHAM algo: segredo encontrado virava "gitleaks
# AUSENTE", e a linha da tabela ia para `não medido (gitleaks ausente)`.
#
# Na Fase 4 era o mesmo tipo de silêncio: `ls … | head -1 || echo "SEM LOCKFILE"` nunca
# imprimia, porque o exit do pipe é o do `head`, que sai 0 mesmo sem nada para ler. Projeto
# sem lockfile seguia sem o aviso, e a C5 podia sair limpa sem ter lido uma dependência.
# E fora de repositório git o gitleaks imprime "not a git repository" e sai 0, que a legenda
# lia como limpo: sem git, a linha é "não medido (sem git)".
#
# O teste roda os blocos do SKILL.md, sem cópia, com binários falsos (ou nenhum) no PATH.
#
# Uso: bash tests/test-secscan-ferramentas.sh [caminho-do-SKILL.md]
set -uo pipefail
SKILL="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin/skills/secscan/SKILL.md}"
[ -f "$SKILL" ] || { echo "SKILL.md não encontrado: $SKILL"; exit 2; }

falhas=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
tem()     { case "$2" in *"$1"*) ok "$3" ;; *) falha "$3 (não achei '$1' em: $2)" ;; esac; }
nao_tem() { case "$2" in *"$1"*) falha "$3 (achei '$1' em: $2)" ;; *) ok "$3" ;; esac; }

# O primeiro bloco ```bash depois do título da Fase 0.5.
awk '/^## Fase 0\.5/{a=1} a && /^```bash/{b=1; next} b && /^```/{exit} b' "$SKILL" > "$TMP/fase05.sh"
[ -s "$TMP/fase05.sh" ] || { echo "bloco bash da Fase 0.5 não encontrado em $SKILL"; exit 2; }

falso() { # falso <caso> <binário> <exit>: scanner que imprime uma linha e sai com <exit>
  mkdir -p "$TMP/$1/bin"
  printf '#!/bin/sh\necho "%s falso rodou"\nexit %s\n' "$2" "$3" > "$TMP/$1/bin/$2"
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
falso semfalha semgrep 2
out=$(roda semfalha)
tem "semgrep falso rodou"  "$out" "o semgrep rodou"
nao_tem "semgrep AUSENTE"  "$out" "…e não sai como ausente"
tem "semgrep FALHOU"       "$out" "…sai como falhou"
tem "exit 2"               "$out" "…com o código de saída"

echo "== semgrep que roda bem =="
falso semok semgrep 0
out=$(roda semok)
nao_tem "semgrep AUSENTE"  "$out" "semgrep ok não sai como ausente"
nao_tem "semgrep FALHOU"   "$out" "…nem como falhou"

echo "== gitleaks que acha segredo (sai 1) =="
falso gl1 gitleaks 1
mkdir -p "$TMP/gl1/proj"; git -C "$TMP/gl1/proj" init -q
out=$(roda gl1)
nao_tem "gitleaks AUSENTE" "$out" "segredo encontrado não vira gitleaks ausente"
tem "gitleaks exit 1"      "$out" "…a saída diz o código, que a legenda lê como achado"

echo "== gitleaks fora de repositório git (imprime 'not a git repository' e sai 0) =="
mkdir -p "$TMP/glsemgit/bin"
printf '#!/bin/sh\necho "fatal: not a git repository"\nexit 0\n' > "$TMP/glsemgit/bin/gitleaks"
chmod +x "$TMP/glsemgit/bin/gitleaks"
out=$(roda glsemgit)
tem "gitleaks não medido (sem git)" "$out" "sem git: sai 'não medido (sem git)'"
nao_tem "gitleaks exit 0"           "$out" "…e não vira 'exit 0', que a legenda lê como limpo"

echo "== gitleaks dentro de repositório git que sai 0 =="
falso glgit gitleaks 0
mkdir -p "$TMP/glgit/proj"; git -C "$TMP/glgit/proj" init -q
out=$(roda glgit)
tem "gitleaks exit 0"               "$out" "com git: o exit 0 continua sendo lido"
nao_tem "sem git"                   "$out" "…e não diz sem git"

echo "== osv-scanner que acha vulnerabilidade (sai 1) =="
falso osv1 osv-scanner 1
out=$(roda osv1)
nao_tem "osv-scanner AUSENTE" "$out" "vulnerabilidade encontrada não vira osv-scanner ausente"
tem "osv-scanner exit 1"      "$out" "…a saída diz o código"

echo "== Fase 4: projeto sem lockfile diz SEM LOCKFILE =="
awk '/^## Fase 4/{a=1} a && /^```bash/{b=1; next} b && /^```/{exit} b' "$SKILL" > "$TMP/fase4.sh"
[ -s "$TMP/fase4.sh" ] || { echo "bloco bash da Fase 4 não encontrado em $SKILL"; exit 2; }
# PATH só com ls e head: sem npm nem pnpm, o bloco ainda tem de dizer o que falta.
mkdir -p "$TMP/binmin"
for c in ls head; do ln -s "$(command -v "$c")" "$TMP/binmin/$c"; done
fase4() { (cd "$1" && PATH="$TMP/binmin" "$BASH" "$TMP/fase4.sh" 2>&1); }
mkdir -p "$TMP/f4-vazio" "$TMP/f4-lock"
out=$(fase4 "$TMP/f4-vazio")
tem "SEM LOCKFILE"           "$out" "sem lockfile: a Fase 4 diz SEM LOCKFILE"
printf '{}\n' > "$TMP/f4-lock/package-lock.json"
out=$(fase4 "$TMP/f4-lock")
tem "package-lock.json"      "$out" "com package-lock.json: diz qual lockfile achou"
nao_tem "SEM LOCKFILE"       "$out" "…e não diz SEM LOCKFILE"
for lf in yarn.lock bun.lockb npm-shrinkwrap.json; do
  mkdir -p "$TMP/f4-$lf"; : > "$TMP/f4-$lf/$lf"
  out=$(fase4 "$TMP/f4-$lf")
  tem "lockfile: $lf"        "$out" "com $lf: diz qual lockfile achou"
  nao_tem "SEM LOCKFILE"     "$out" "…e não diz SEM LOCKFILE"
done

echo "== a regra de estado da Fase 1 conhece o scanner que falhou =="
grep -q 'não medido (<ferramenta> falhou' "$SKILL" \
  && ok "o estado 'não medido (<ferramenta> falhou…)' está no texto" \
  || falha "a Fase 1 só conhece 'ausente': o semgrep que falhou vira ausente na tabela"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
