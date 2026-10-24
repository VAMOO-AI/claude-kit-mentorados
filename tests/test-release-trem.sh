#!/usr/bin/env bash
# O scripts/release-trem.sh junta os PRs, sobe a versão nos cinco lugares e não faz push?
#
# Sem rede: o origin é um repo bare de mentira, com refs/pull/<n>/head como no GitHub, e o gh
# é um stub que devolve o corpo de cada PR de um JSON. Os gates de versão que o script roda
# são os de verdade (tests/test-versao-changelog.sh e tests/test-changelog-bloco.sh), copiados
# para o repo de mentira.
#
# Casos: três PRs (seções ### repetidas entre eles, um só com bullets, um que marca setup e
# um gh que falha na 1ª chamada), conflito no segundo PR, PR sem "## Para o CHANGELOG",
# PR fechado e versão que não sobe.
#
# Uso: bash tests/test-release-trem.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
S="$RAIZ/scripts/release-trem.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/release-trem-teste.XXXXXX")"; trap 'rm -rf "$T"' EXIT
falhas=0
check() { if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"; else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi; }
[ -f "$S" ] || { echo "  FALHA $S não existe"; exit 1; }

export GIT_AUTHOR_NAME=teste GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=teste GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --file "$T/gitconfig" init.defaultBranch main
export RELEASE_TREM_SLEEP=0 RELEASE_TREM_DATA=2026-10-24

# gh de mentira: `gh pr view <n> --json ...` imprime $FIX/pr-<n>.json. Com $FIX/falha-<n>,
# a primeira chamada sai 1 (prova o retry) e apaga o marcador.
FIX="$T/fix"; mkdir -p "$T/bin" "$FIX"; export FIX
cat > "$T/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "gh $*" >> "$FIX/gh.log"
[ "$1 $2" = "pr view" ] || { echo "stub: só pr view" >&2; exit 9; }
[ -f "$FIX/falha-$3" ] && { rm -f "$FIX/falha-$3"; echo "HTTP 502" >&2; exit 1; }
cat "$FIX/pr-$3.json"
GH
chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH"

# pr <n> <estado> <título> <corpo>: grava o JSON que o gh devolve.
pr() { python3 -c 'import json,sys;json.dump({"number":int(sys.argv[1]),"state":sys.argv[2],"title":sys.argv[3],"body":sys.argv[4]},open(sys.argv[5],"w"))' "$1" "$2" "$3" "$4" "$FIX/pr-$1.json"; }

# Repo de mentira na 0.2.0, com os cinco lugares da versão e os gates de verdade.
novo_repo() { # novo_repo <pasta>  → <pasta>/origin.git (bare) e <pasta>/clone
  b="$1"; mkdir -p "$b/semente"; git init -q "$b/semente"; s="$b/semente"
  mkdir -p "$s/plugin/.claude-plugin" "$s/plugin/scripts" "$s/tests" "$s/.github/scripts"
  printf '{\n  "name": "kit-vamoo",\n  "version": "0.2.0"\n}\n' > "$s/plugin/.claude-plugin/plugin.json"
  printf '#!/usr/bin/env bash\nKIT_VERSION="0.2.0"\n' > "$s/install.sh"
  printf '#!/usr/bin/env bash\nKIT_VERSION="0.2.0"\n' > "$s/plugin/scripts/kit-setup.sh"
  printf '# Changelog\n\nAbertura.\n\n## [0.2.0] — 2026-10-01\n\n### Mudado\n\n- antes\n\n## [0.1.0]\n\n### Adicionado\n\n- início\n' > "$s/CHANGELOG.md"
  printf '# comentário\n# formato <versão>|<resumo>[|setup]\n0.2.0|antes\n0.1.0|início\n' > "$s/plugin/novidades.txt"
  printf 'a\nb\nc\n' > "$s/x.txt"
  cp "$RAIZ/tests/test-versao-changelog.sh" "$RAIZ/tests/test-changelog-bloco.sh" "$s/tests/"
  cp "$RAIZ/.github/scripts/changelog-bloco.sh" "$s/.github/scripts/"
  git -C "$s" add -A; git -C "$s" commit -q -m base
  git clone -q --bare "$s" "$b/origin.git"
  git clone -q "$b/origin.git" "$b/clone"
}
# ramo_pr <pasta> <n> <arquivo> <conteúdo>: commit a partir da main publicado em refs/pull/<n>/head.
ramo_pr() {
  c="$1/clone"; git -C "$c" checkout -q -b "f$2" origin/main
  printf '%s\n' "$4" > "$c/$3"; git -C "$c" add "$3"; git -C "$c" commit -q -m "feat $2"
  git -C "$c" push -q origin "HEAD:refs/pull/$2/head"; git -C "$c" checkout -q main
}

echo "== três PRs no trem =="
R="$T/a"; novo_repo "$R"
ramo_pr "$R" 11 onze.txt onze; ramo_pr "$R" 12 doze.txt doze; ramo_pr "$R" 13 treze.txt treze
pr 11 OPEN "feat: onze" "$(printf 'Resumo.\n\n## Para o CHANGELOG\n### Adicionado\n- **onze**: novo.\n\n### Corrigido\n- onze conserta.\n\n## Para o novidades\nAgora tem o onze.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n')"
pr 12 OPEN "feat: doze" "$(printf '## Para o CHANGELOG\n- doze muda | com barra.\n\n## Para o novidades\no doze | mudou\nsetup\n')"
pr 13 OPEN "feat: treze" "$(printf '## Para o CHANGELOG\n### Adicionado\n- treze também.\n\n## Teste\nnão é changelog\n')"
: > "$FIX/falha-11"
main_antes="$(git -C "$R/origin.git" rev-parse main)"
out="$(cd "$R/clone" && bash "$S" 0.3.0 11 12 13 2>&1)"; rc=$?
W="$R/clone/.claude/worktrees/release-0.3.0"
check "sai 0 (rc=$rc)" "$([ "$rc" = 0 ] && echo ok || { printf '%s\n' "$out" | tail -15 >&2; echo fail; })"
check "o gh falhou na 1ª chamada do #11 e o retry seguiu" "$([ "$(grep -c 'pr view 11' "$FIX/gh.log")" = 2 ] && echo ok || echo fail)"
check "o branch release/0.3.0 nasce de origin/main" "$(git -C "$R/clone" merge-base --is-ancestor "$main_antes" release/0.3.0 2>/dev/null && echo ok || echo fail)"
check "os três PRs entraram por merge" "$(for n in 11 12 13; do git -C "$R/clone" merge-base --is-ancestor "$(git -C "$R/origin.git" rev-parse "refs/pull/$n/head")" release/0.3.0 || exit 1; done && echo ok || echo fail)"
check "a versão é 0.3.0 nos cinco lugares (test-versao-changelog real)" "$(bash "$W/tests/test-versao-changelog.sh" "$W" >/dev/null 2>&1 && grep -q '"version": "0.3.0"' "$W/plugin/.claude-plugin/plugin.json" && echo ok || echo fail)"
bloco="$(bash "$W/.github/scripts/changelog-bloco.sh" 0.3.0 "$W/CHANGELOG.md")"
check "o bloco da 0.3.0 começa em '### '" "$(printf '%s\n' "$bloco" | head -1 | grep -q '^### ' && echo ok || echo fail)"
check "um '### Adicionado' só, com o onze e o treze" "$([ "$(printf '%s\n' "$bloco" | grep -c '^### Adicionado')" = 1 ] && printf '%s\n' "$bloco" | grep -q 'onze\*\*: novo' && printf '%s\n' "$bloco" | grep -q 'treze também' && echo ok || echo fail)"
check "PR só com bullets cai em '### Mudado'" "$(printf '%s\n' "$bloco" | awk '/^### Mudado/{m=1;next} /^### /{m=0} m' | grep -q 'doze muda' && echo ok || echo fail)"
check "'### Corrigido' veio do #11" "$(printf '%s\n' "$bloco" | awk '/^### Corrigido/{m=1;next} /^### /{m=0} m' | grep -q 'onze conserta' && echo ok || echo fail)"
check "nada de fora da seção (rodapé, '## Teste', novidades) entra no CHANGELOG" "$(printf '%s\n' "$bloco" | grep -q 'Generated\|não é changelog\|Agora tem' && echo fail || echo ok)"
check "o cabeçalho tem a data e fica acima da 0.2.0" "$(grep '^## \[' "$W/CHANGELOG.md" | head -2 | tr '\n' ' ' | grep -q '^## \[0.3.0\] — 2026-10-24 ## \[0.2.0\]' && echo ok || echo fail)"
topo="$(grep -v '^#' "$W/plugin/novidades.txt" | head -1)"
check "novidades: 0.3.0 no topo, PRs juntos, '|' do texto trocado e setup no 3º campo" "$([ "$topo" = '0.3.0|Agora tem o onze; o doze / mudou|setup' ] && echo ok || { echo "        veio: $topo" >&2; echo fail; })"
check "nada foi enviado ao origin (main igual e sem branch release)" "$([ "$(git -C "$R/origin.git" rev-parse main)" = "$main_antes" ] && ! git -C "$R/origin.git" show-ref -q --verify refs/heads/release/0.3.0 && echo ok || echo fail)"
check "o worktree ficou limpo, com o bump commitado" "$([ -z "$(git -C "$W" status --porcelain)" ] && git -C "$W" log -1 --format=%s | grep -q '^chore(release): 0.3.0 (#11 #12 #13)' && echo ok || echo fail)"
corpo="$(git -C "$W" rev-parse --git-dir)/release-trem-0.3.0.md"
check "o corpo do PR lista os PRs e os 'gh pr close'" "$(grep -q '#12 (feat: doze)' "$corpo" && grep -q 'gh pr close 13' "$corpo" && echo ok || echo fail)"
check "a saída diz que nada foi enviado e mostra o push" "$(printf '%s\n' "$out" | grep -q 'Nada foi enviado' && printf '%s\n' "$out" | grep -q 'push -u origin release/0.3.0' && echo ok || echo fail)"

echo "== conflito no segundo PR =="
R="$T/b"; novo_repo "$R"
ramo_pr "$R" 21 x.txt "$(printf 'a\nVINTE E UM\nc')"; ramo_pr "$R" 22 x.txt "$(printf 'a\nVINTE E DOIS\nc')"
pr 21 OPEN "feat: 21" "$(printf '## Para o CHANGELOG\n- 21\n\n## Para o novidades\n21\n')"
pr 22 OPEN "feat: 22" "$(printf '## Para o CHANGELOG\n- 22\n\n## Para o novidades\n22\n')"
out="$(cd "$R/clone" && bash "$S" 0.3.0 21 22 2>&1)"; rc=$?
W="$R/clone/.claude/worktrees/release-0.3.0"
check "para com exit 3" "$([ "$rc" = 3 ] && echo ok || echo fail)"
check "diz o PR e o arquivo do conflito" "$(printf '%s\n' "$out" | grep -q 'conflito ao juntar o #22' && printf '%s\n' "$out" | grep -q '^  x.txt' && echo ok || echo fail)"
check "o merge foi abortado e a versão não subiu" "$([ ! -f "$(git -C "$W" rev-parse --git-dir)/MERGE_HEAD" ] && grep -q '"0.2.0"' "$W/plugin/.claude-plugin/plugin.json" && echo ok || echo fail)"

echo "== recusas antes de criar qualquer coisa =="
R="$T/c"; novo_repo "$R"
ramo_pr "$R" 31 trinta.txt 31
pr 31 OPEN "feat: 31" "$(printf 'Só resumo, sem seção.\n\n## Para o novidades\n31\n')"
out="$(cd "$R/clone" && bash "$S" 0.3.0 31 2>&1)"; rc=$?
check "PR sem '## Para o CHANGELOG': sai 1 e diz qual" "$([ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q "#31 não tem a seção '## Para o CHANGELOG'" && echo ok || echo fail)"
check "e não cria worktree nem branch" "$([ ! -e "$R/clone/.claude/worktrees/release-0.3.0" ] && ! git -C "$R/clone" show-ref -q --verify refs/heads/release/0.3.0 && echo ok || echo fail)"
pr 31 CLOSED "feat: 31" "$(printf '## Para o CHANGELOG\n- 31\n')"
out="$(cd "$R/clone" && bash "$S" 0.3.0 31 2>&1)"; rc=$?
check "PR fechado é recusado" "$([ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '#31 está CLOSED' && echo ok || echo fail)"
pr 31 OPEN "feat: 31" "$(printf '## Para o CHANGELOG\n- 31\n\n## Para o novidades\n31\n')"
out="$(cd "$R/clone" && bash "$S" 0.2.0 31 2>&1)"; rc=$?
check "versão que não passa da main (0.2.0) é recusada" "$([ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'maior que a da main (0.2.0)' && echo ok || echo fail)"
out="$(cd "$R/clone" && bash "$S" 0.3 31 2>&1)"; rc=$?
check "versão fora de x.y.z sai 2" "$([ "$rc" = 2 ] && echo ok || echo fail)"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
