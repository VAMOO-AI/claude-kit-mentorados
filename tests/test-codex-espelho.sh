#!/usr/bin/env bash
# O plugin/scripts/codex-espelho.sh (SessionStart, F5 do núcleo único, #241).
#
# O Codex roda os guards de ~/.codex/hooks, que são CÓPIAS (nada aponta para o cache versionado
# do plugin). O espelho leva a versão do plugin para o guard que já está lá, nunca cria guard
# novo, leva o hookjson.js para ~/.codex/scripts e só trabalha quando a versão muda. E o guard
# espelhado barra no payload do Codex (comando em array e tool_input.workdir).
#
# Skills (I9 do plano): em ~/.codex/skills e ~/.agents/skills, o link pendurado para
# ~/.claude/skills/<x> vira cópia de plugin/skills/<x> com o marcador .kit-vamoo-espelho; a
# cópia marcada é atualizada; pasta sem marcador é da pessoa; link vivo fica; nada é criado.
#
# O script roda no mesmo bash que roda a suíte ("$BASH"): `/bin/bash tests/test-codex-espelho.sh`
# exercita o espelho no bash 3.2 do macOS.
#
# Uso: bash tests/test-codex-espelho.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
ESP="$RAIZ/plugin/scripts/codex-espelho.sh"
command -v node >/dev/null 2>&1 || { echo "node é pré-requisito do kit"; exit 2; }
falhas=0
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
X="$TMP/codex"; DADOS="$TMP/dados"; mkdir -p "$X/hooks"
printf '#!/bin/bash\n# versao antiga\nexit 0\n' > "$X/hooks/check-careful.sh"
printf '#!/bin/bash\n# versao antiga\nexit 0\n' > "$X/hooks/rtk-codex.sh"
roda() { HOME="$TMP/home" CODEX_HOME="$X" CLAUDE_PLUGIN_DATA="$DADOS" "$BASH" "$ESP" 2>&1; }

echo "== guard que já está lá é atualizado; o que não está não é criado =="
out=$(roda)
cmp -s "$RAIZ/plugin/hooks/check-careful.sh" "$X/hooks/check-careful.sh" && ok "check-careful = versão do plugin" || falha "check-careful não foi atualizado"
cmp -s "$RAIZ/plugin/hooks/rtk-codex.sh" "$X/hooks/rtk-codex.sh" && ok "rtk-codex = versão do plugin" || falha "rtk-codex não foi atualizado"
[ -x "$X/hooks/check-careful.sh" ] && ok "executável" || falha "sem +x"
[ -e "$X/hooks/block-main-commit.sh" ] && falha "criou guard que não estava lá" || ok "guard ausente não é criado"
cmp -s "$RAIZ/plugin/scripts/hookjson.js" "$X/scripts/hookjson.js" && ok "hookjson.js em ~/.codex/scripts" || falha "hookjson.js não foi copiado"
case "$out" in *"2 guard(s)"*) ok "avisa quantos atualizou" ;; *) falha "aviso: $out" ;; esac
VER=$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' "$RAIZ/plugin/.claude-plugin/plugin.json" | head -1)
[ "$(cat "$DADOS/codex-espelho.versao" 2>/dev/null)" = "$VER" ] && ok "versão espelhada gravada ($VER)" || falha "versão espelhada não gravada"

echo
echo "== mesma versão: não mexe e não fala =="
printf '#!/bin/bash\n# mexido na mão\nexit 0\n' > "$X/hooks/check-careful.sh"
out=$(roda)
[ -z "$out" ] && ok "silêncio" || falha "falou: $out"
grep -q 'mexido na mão' "$X/hooks/check-careful.sh" && ok "não reescreve com a versão já espelhada" || falha "reescreveu sem a versão mudar"

echo
echo "== versão nova: atualiza de novo =="
printf '0.0.1\n' > "$DADOS/codex-espelho.versao"
roda >/dev/null
cmp -s "$RAIZ/plugin/hooks/check-careful.sh" "$X/hooks/check-careful.sh" && ok "versão mudou: atualiza" || falha "não atualizou com a versão nova"

echo
echo "== versão nova com o guard já igual (o update.sh do time chegou antes): não reescreve =="
printf '0.0.2\n' > "$DADOS/codex-espelho.versao"
ino_antes=$(ls -i "$X/hooks/check-careful.sh" | awk '{print $1}')
out=$(roda)
ino_depois=$(ls -i "$X/hooks/check-careful.sh" | awk '{print $1}')
[ "$ino_antes" = "$ino_depois" ] && ok "mesmo arquivo, sem cópia nova" || falha "reescreveu guard idêntico"
case "$out" in *"guard(s)"*) falha "contou guard idêntico: $out" ;; *) ok "não conta guard idêntico" ;; esac

echo
echo "== o guard espelhado barra no payload do Codex =="
r=$(printf '%s' '{"tool_input":{"command":["/bin/zsh","-lc","git push --force origin main"],"workdir":"/tmp"},"permission_mode":"default"}' \
    | HOME="$TMP/home" bash "$X/hooks/check-careful.sh" 2>/dev/null)
case "$r" in *'"permissionDecision":"ask"'*) ok "push --force na main em array: ask" ;; *) falha "check-careful espelhado não perguntou: $r" ;; esac

echo
echo "== sem ~/.codex/hooks: nada =="
rm -rf "$X/hooks"; out=$(roda)
[ -z "$out" ] && [ ! -d "$X/hooks" ] && ok "sem pasta de hooks, não cria nada" || falha "mexeu sem ~/.codex/hooks"

echo
echo "== skills: ~/.codex/skills e ~/.agents/skills (sem ~/.codex/hooks) =="
H2="$TMP/hs"; X2="$TMP/codex2"; D2="$TMP/dados2"
CS="$X2/skills"; AS="$H2/.agents/skills"
mkdir -p "$CS" "$AS" "$H2/.claude/skills" "$H2/minhas/handoff"
ln -s "$H2/.claude/skills/git-sync" "$CS/git-sync"                 # pendurado, com par no plugin
ln -s "$H2/.claude/skills/git-sync/" "$AS/git-sync"                # idem, com barra no fim
mkdir -p "$AS/grilling"; printf 'velho\n' > "$AS/grilling/SKILL.md"; printf 'sobra\n' > "$AS/grilling/antigo.md"
printf '0.0.1\n' > "$AS/grilling/.kit-vamoo-espelho"              # espelhada antes
mkdir -p "$AS/ship"; printf 'meu\n' > "$AS/ship/SKILL.md"          # pasta da pessoa
ln -s "$H2/minhas/handoff" "$AS/handoff"                           # link vivo
ln -s "$H2/.claude/skills/so-meu" "$AS/so-meu"                     # pendurado, sem par no plugin
ln -s "/lugar/nenhum/find-docs" "$CS/find-docs"                    # pendurado para outro lugar
antes_cs=$(ls -A "$CS" | LC_ALL=C sort); antes_as=$(ls -A "$AS" | LC_ALL=C sort)
roda2() { HOME="$H2" CODEX_HOME="$X2" CLAUDE_PLUGIN_DATA="$D2" "$BASH" "$ESP" 2>&1; }
igual_plugin() { diff -r -x .kit-vamoo-espelho "$RAIZ/plugin/skills/$1" "$2" >/dev/null 2>&1; }
out=$(roda2)
for d in "$CS/git-sync" "$AS/git-sync"; do
  { [ ! -L "$d" ] && [ -d "$d" ]; } && ok "link pendurado vira pasta: ${d#$TMP/}" || falha "não virou pasta: ${d#$TMP/}"
  igual_plugin git-sync "$d" && ok "conteúdo = plugin/skills/git-sync" || falha "conteúdo difere: ${d#$TMP/}"
  [ "$(cat "$d/.kit-vamoo-espelho" 2>/dev/null)" = "$VER" ] && ok "marcador com a versão" || falha "sem marcador: ${d#$TMP/}"
  [ -z "$(find "$d" -type l 2>/dev/null)" ] && ok "cópia sem symlink" || falha "cópia tem symlink"
done
igual_plugin grilling "$AS/grilling" && ok "cópia marcada atualizada" || falha "cópia marcada não atualizou"
[ ! -e "$AS/grilling/antigo.md" ] && ok "arquivo velho da cópia marcada sai" || falha "sobrou arquivo velho"
[ "$(cat "$AS/grilling/.kit-vamoo-espelho" 2>/dev/null)" = "$VER" ] && ok "marcador da cópia atualizado" || falha "marcador velho"
[ "$(cat "$AS/ship/SKILL.md")" = meu ] && [ ! -e "$AS/ship/.kit-vamoo-espelho" ] && ok "pasta da pessoa intacta" || falha "mexeu na pasta da pessoa"
[ -L "$AS/handoff" ] && [ "$(readlink "$AS/handoff")" = "$H2/minhas/handoff" ] && ok "link vivo fica" || falha "mexeu no link vivo"
[ -L "$AS/so-meu" ] && ok "link sem par no plugin fica" || falha "mexeu no link sem par"
[ -L "$CS/find-docs" ] && [ "$(readlink "$CS/find-docs")" = "/lugar/nenhum/find-docs" ] && ok "link para outro lugar fica" || falha "mexeu em link de outro lugar"
[ "$(ls -A "$CS" | LC_ALL=C sort)" = "$antes_cs" ] && [ "$(ls -A "$AS" | LC_ALL=C sort)" = "$antes_as" ] && ok "nenhuma entrada nova" || falha "criou ou apagou entrada"
[ ! -e "$X2/hooks" ] && ok "não cria ~/.codex/hooks" || falha "criou ~/.codex/hooks"
case "$out" in *"skill(s)"*) ok "avisa as skills espelhadas" ;; *) falha "sem aviso de skill: $out" ;; esac
case "$out" in *ship*) ok "avisa a pasta da pessoa" ;; *) falha "não avisou a pasta da pessoa: $out" ;; esac
[ "$(printf '%s\n' "$out" | grep -c .)" -le 2 ] && ok "no máximo uma linha por assunto" || falha "falou demais: $out"
out=$(roda2)
[ -z "$out" ] && ok "mesma versão: silêncio (aviso uma vez por versão)" || falha "falou de novo: $out"

echo
echo "== sem ~/.codex nem ~/.agents: não grava nada =="
H3="$TMP/h3"; mkdir -p "$H3"
HOME="$H3" CODEX_HOME="$H3/.codex" "$BASH" "$ESP" >/dev/null 2>&1
[ -z "$(find "$H3" -mindepth 1 -print)" ] && ok "HOME intacto" || falha "escreveu no HOME: $(find "$H3" -mindepth 1 | head -3)"

echo
echo "== máquina do time (.team-manifest): o comando do hooks.json roda o espelho =="
H4="$TMP/h4"; mkdir -p "$H4/.claude" "$H4/.agents/skills"
echo "skill/vamoo-verificacao" > "$H4/.claude/.team-manifest"
ln -s "$H4/.claude/skills/git-sync" "$H4/.agents/skills/git-sync"
cmd=$(node -e '
  const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  for (const g of (j.hooks.SessionStart || [])) for (const h of g.hooks || [])
    if ((h.command || "").includes("codex-espelho.sh")) { console.log(h.command); process.exit(0); }
' "$RAIZ/plugin/hooks/hooks.json")
( unset KIT_VAMOO_HOOKS; HOME="$H4" CODEX_HOME="$H4/.codex" CLAUDE_PLUGIN_ROOT="$RAIZ/plugin" CLAUDE_PLUGIN_DATA="$TMP/dados4" \
    "$BASH" -c "$cmd" >/dev/null 2>&1 </dev/null )
{ [ ! -L "$H4/.agents/skills/git-sync" ] && [ -f "$H4/.agents/skills/git-sync/.kit-vamoo-espelho" ]; } \
  && ok "espelho rodou com o .team-manifest" || falha "a guarda de convidado calou o espelho"

echo
echo "== nenhum caminho com versão =="
grep -q 'codex-espelho.sh' "$RAIZ/plugin/hooks/hooks.json" && ok "registrado no SessionStart" || falha "fora do hooks.json"
grep -nE 'cache/[^"]*/[0-9]+\.[0-9]+\.[0-9]+' "$ESP" "$RAIZ/plugin/scripts/codex-optimize.sh" >/dev/null && falha "caminho com número de versão" || ok "nenhum caminho do cache versionado"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
