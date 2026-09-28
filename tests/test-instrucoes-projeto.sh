#!/usr/bin/env bash
# O instrucoes-projeto.sh classifica o par CLAUDE.md/AGENTS.md da raiz e só grava o que
# não pede julgamento.
#
# O AGENTS.md da raiz é a fonte das regras do projeto e o CLAUDE.md é a ponte
# `@AGENTS.md`, mais o que for exclusivo do Claude Code. O risco do script mora no
# --apply. Com `CLAUDE.md -> AGENTS.md`, um `printf > CLAUDE.md` escreve através do link e
# troca a fonte inteira por `@AGENTS.md`, que importa a si mesmo. No disco padrão do Mac,
# `[ -e AGENTS.md ]` responde por um `agents.md`, e o --apply faria a ponte para o arquivo
# errado. Por isso cada classe que não pode gravar tem foto antes e depois (nome, alvo de
# link, cksum), e os dois casos de symlink provam que o conteúdo saiu com os mesmos bytes.
#
# Uso: bash tests/test-instrucoes-projeto.sh [caminho-do-script]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${1:-$RAIZ/plugin/scripts/instrucoes-projeto.sh}"
MODELO="$RAIZ/plugin/templates/AGENTS-projeto.md.exemplo"
[ -f "$SCRIPT" ] || { echo "script não encontrado: $SCRIPT"; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/instrucoes.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# Nenhum git acima do TMP entra na conta: a visão "via find" tem que ser a de um diretório
# solto, mesmo que o TMPDIR de quem roda esteja dentro de um repo.
export GIT_CEILING_DIRECTORIES="$TMP"

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
sim() { if "$@"; then echo ok; else echo fail; fi; }

roda() { bash "$SCRIPT" "$@" 2>&1; }
classe_de() { printf '%s\n' "$1" | sed -n 's/^classe: //p' | head -1; }
tem() { printf '%s\n' "$1" | grep -q -- "$2"; }            # tem <saída> <regex>
nao_tem() { ! tem "$1" "$2"; }
# na_secao <saída> <regex do cabeçalho> <regex do item>: o item aparece indentado debaixo
# daquele cabeçalho, antes da próxima linha que começa na coluna 0. As regex vão pelo
# ENVIRON: o `-v` do awk interpreta `\[` como escape de string e a regex vira classe.
na_secao() {
  printf '%s\n' "$1" | H="$2" I="$3" awk '
    $0 ~ ENVIRON["H"] { s = 1; next }
    s && /^[^ ]/ { s = 0 }
    s && $0 ~ ENVIRON["I"] { f = 1 }
    END { exit !f }'
}
# antes <saída> <regex A> <regex B>: A aparece numa linha anterior à de B.
antes() {
  printf '%s\n' "$1" | A="$2" B="$3" awk '
    !pa && $0 ~ ENVIRON["A"] { pa = NR }
    !pb && $0 ~ ENVIRON["B"] { pb = NR }
    END { exit !(pa && pb && pa < pb) }'
}
ponte_ok() { printf '@AGENTS.md\n' | cmp -s - "$1"; }
soma() { cksum < "$1"; }
nao_eh_link() { [ ! -L "$1" ]; }
mesmo() { [ "$1" = "$2" ]; }

# foto <dir>: nome, tipo, alvo de link e cksum de tudo, fora o .git.
foto() {
  ( cd "$1" && find . -path ./.git -prune -o -print | LC_ALL=C sort | while IFS= read -r f; do
      if [ -L "$f" ]; then printf 'L %s -> %s\n' "$f" "$(readlink "$f")"
      elif [ -d "$f" ]; then printf 'D %s\n' "$f"
      else printf 'F %s %s\n' "$f" "$(cksum < "$f")"; fi
    done )
}
# nomes_exatos <dir>: entradas da raiz com o nome guardado no disco (o `ls` do Mac não
# troca a caixa, o `[ -e ]` troca).
nomes_exatos() { ls -A "$1"; }

novo() { mkdir -p "$TMP/$1"; printf '%s\n' "$TMP/$1"; }

AG='# Projeto X

Regras do projeto para qualquer agente que abrir este repo.

## Comandos
- Rode `npm run check` antes de dizer que terminou.
- Migrations novas entram em supabase/migrations com timestamp.
- Nunca rode supabase db reset no banco compartilhado.
'
CY='# Projeto Y

- Rode `npm test` antes de abrir PR.
- O hook SessionStart roda o lint.
'

# ── fixtures ─────────────────────────────────────────────────────────────────
S1="$(novo so-import)";      printf '%s' "$AG" > "$S1/AGENTS.md"; printf '\n  @AGENTS.md  \n\n' > "$S1/CLAUDE.md"
S2="$(novo so-import-crlf)"; printf '%s' "$AG" > "$S2/AGENTS.md"; printf '@AGENTS.md\r\n' > "$S2/CLAUDE.md"
IC="$(novo import-conteudo)"; printf '%s' "$AG" > "$IC/AGENTS.md"
printf '@AGENTS.md\n\n## Comandos\n- O hook do kit (PreToolUse) bloqueia commit direto em main.\n' > "$IC/CLAUDE.md"
II="$(novo import-inline)";  printf '%s' "$AG" > "$II/AGENTS.md"
printf 'Leia @AGENTS.md antes de qualquer tarefa.\n' > "$II/CLAUDE.md"
BT="$(novo import-crase)";   printf '%s' "$AG" > "$BT/AGENTS.md"
printf 'O CLAUDE.md deve ser só `@AGENTS.md`, sem mais nada.\n' > "$BT/CLAUDE.md"
CD="$(novo copia-duplicada)"; printf '%s' "$AG" > "$CD/AGENTS.md"
cat > "$CD/CLAUDE.md" <<'EOF'
# Projeto X
@AGENTS.md

Regras do projeto para qualquer agente que abrir este repo.

## Comandos
- Rode `npm run check` antes de dizer que terminou.
- Migrations novas entram em supabase/migrations com timestamp.
- Nunca rode supabase db reset no banco compartilhado.
- Use a skill ship (.claude/skills/ship/SKILL.md) para abrir o PR.
EOF
SA="$(novo so-agents)";      printf '%s' "$AG" > "$SA/AGENTS.md"
SC="$(novo so-claude)";      printf '%s' "$CY" > "$SC/CLAUDE.md"
# CLAUDE.md que importa um AGENTS.md que não existe: mover a linha do import criaria um
# AGENTS.md que importa a si mesmo.
SCI="$(novo so-claude-import)"; printf '@AGENTS.md\n\n- Regra solta do projeto que ficou sem fonte.\n' > "$SCI/CLAUDE.md"
SCO="$(novo so-claude-so-import)"; printf '@AGENTS.md\n' > "$SCO/CLAUDE.md"
LRO="$(novo link-agents-circular)"; printf '@AGENTS.md\n' > "$LRO/CLAUDE.md"; ln -s CLAUDE.md "$LRO/AGENTS.md"
DVE="$(novo divergentes-claude-vazio)"; printf '%s' "$AG" > "$DVE/AGENTS.md"; printf '\n\n' > "$DVE/CLAUDE.md"
DV="$(novo divergentes)";    printf '%s' "$AG" > "$DV/AGENTS.md"
cat > "$DV/CLAUDE.md" <<'EOF'
# Projeto X

- Rode `npm test` antes de abrir PR.
- O hook do projeto, no settings.json, bloqueia commit em main.
- Rode o comando `/handoff` no fim da sessão.
EOF
LF="$(novo link-claude)";    printf '%s' "$AG" > "$LF/AGENTS.md"; ln -s AGENTS.md "$LF/CLAUDE.md"
LR="$(novo link-agents)";    printf '%s' "$CY" > "$LR/CLAUDE.md"; ln -s CLAUDE.md "$LR/AGENTS.md"
LO="$(novo link-fora)";      mkdir -p "$LO/.context"; printf '%s' "$AG" > "$LO/.context/regras.md"
ln -s .context/regras.md "$LO/CLAUDE.md"
LQ="$(novo link-quebrado)";  printf '%s' "$AG" > "$LQ/AGENTS.md"; ln -s nao-existe.md "$LQ/CLAUDE.md"
LB="$(novo link-dois)";      mkdir -p "$LB/.context"; printf '%s' "$AG" > "$LB/.context/regras.md"
ln -s .context/regras.md "$LB/AGENTS.md"; ln -s AGENTS.md "$LB/CLAUDE.md"
# Frases que só parecem do Claude Code: rota web, hook do React, skill de gente.
HF="$(novo heuristica)";     printf '%s' "$AG" > "$HF/AGENTS.md"
cat > "$HF/CLAUDE.md" <<'EOF'
# Projeto H

- A tela de entrada fica em /login.
- Use React hooks nos componentes novos.
- O time tem skill em SQL e revisa as queries.
- A rota `/login` exige sessão.
- Rode o comando `/revisar` antes de abrir o PR.
- /handoff do Claude fecha a sessão.
- O hook PreToolUse bloqueia push direto em main.
- A skill de deploy mora em .claude/skills/deploy/SKILL.md.
EOF
# Import no meio da frase, sem AGENTS.md: movido como está, o AGENTS.md importaria a si mesmo.
SCM="$(novo so-claude-import-inline)"
cat > "$SCM/CLAUDE.md" <<'EOF'
# Projeto M

Veja @AGENTS.md para as regras gerais.
As regras comuns também estão em @./AGENTS.md.
- Rode `npm test` antes de abrir PR.
EOF
NH="$(novo nenhum)";         printf '# leia-me\n' > "$NH/README.md"
CX="$(novo caixa-agents)";   printf '%s' "$AG" > "$CX/agents.md"
CX2="$(novo caixa-claude)";  printf '%s' "$AG" > "$CX2/AGENTS.md"; printf 'conteudo proprio do projeto\n' > "$CX2/Claude.md"
LM="$(novo limite)";         head -c 32769 /dev/zero | tr '\0' 'a' > "$LM/AGENTS.md"; printf '@AGENTS.md\n' > "$LM/CLAUDE.md"
LN="$(novo no-limite)";      head -c 32768 /dev/zero | tr '\0' 'a' > "$LN/AGENTS.md"; printf '@AGENTS.md\n' > "$LN/CLAUDE.md"
NG="$(novo aninhado-git)"
printf '%s' "$AG" > "$NG/AGENTS.md"; printf '@AGENTS.md\n' > "$NG/CLAUDE.md"
mkdir -p "$NG/apps/web" "$NG/vendor/lib" "$NG/.claude/worktrees/wt" "$NG/packages/solo"
printf '%s' "$AG" > "$NG/apps/web/AGENTS.md"; printf '@AGENTS.md\n' > "$NG/apps/web/CLAUDE.md"
printf '%s' "$AG" > "$NG/vendor/lib/AGENTS.md"; printf 'x\n' > "$NG/vendor/lib/CLAUDE.md"
printf '%s' "$AG" > "$NG/.claude/worktrees/wt/AGENTS.md"; printf '@AGENTS.md\n' > "$NG/.claude/worktrees/wt/CLAUDE.md"
printf '%s' "$AG" > "$NG/packages/solo/AGENTS.md"
printf 'vendor/\n' > "$NG/.gitignore"
git -C "$NG" init -q
NF="$(novo aninhado-find)"
mkdir -p "$NF/docs" "$NF/node_modules/pkg" "$NF/.claude/worktrees/wt"
printf '%s' "$AG" > "$NF/docs/AGENTS.md"; printf '%s' "$CY" > "$NF/docs/CLAUDE.md"
printf '%s' "$AG" > "$NF/node_modules/pkg/AGENTS.md"; printf '%s' "$CY" > "$NF/node_modules/pkg/CLAUDE.md"
printf '%s' "$AG" > "$NF/.claude/worktrees/wt/AGENTS.md"; printf '@AGENTS.md\n' > "$NF/.claude/worktrees/wt/CLAUDE.md"

# ── --check: classe de cada fixture, e nenhuma gravação ────────────────────────
echo "== --check classifica e não grava =="
esperado() { # esperado <dir> <classe>
  local d="$1" c="$2" f0 f1 out rc
  f0="$(foto "$d")"; out="$(roda --check "$d")"; rc=$?; f1="$(foto "$d")"
  check "$(basename "$d"): classe $c (veio: $(classe_de "$out"))" "$(sim mesmo "$(classe_de "$out")" "$c")"
  check "$(basename "$d"): --check sai 0" "$(sim mesmo "$rc" 0)"
  check "$(basename "$d"): --check não grava nada" "$(sim mesmo "$f0" "$f1")"
}
esperado "$S1"  so-import
esperado "$S2"  so-import
esperado "$IC"  import+conteudo
esperado "$II"  import+conteudo
esperado "$BT"  divergentes
esperado "$CD"  import+conteudo
esperado "$SA"  so-agents
esperado "$SC"  so-claude
esperado "$SCI" so-claude
esperado "$SCO" so-claude
esperado "$LRO" symlink
esperado "$DVE" divergentes
esperado "$DV"  divergentes
esperado "$LF"  symlink
esperado "$LR"  symlink
esperado "$LO"  symlink
esperado "$LQ"  symlink
esperado "$LB"  symlink
esperado "$NH"  nenhum
esperado "$HF"  divergentes
esperado "$SCM" so-claude
esperado "$CX"  nenhum
esperado "$CX2" so-agents
esperado "$LM"  so-import
esperado "$NG"  so-import
esperado "$NF"  nenhum

echo "== o que a saída diz =="
out="$(roda "$SA")"
check "sem flag o modo é --check"                   "$(sim mesmo "$(classe_de "$out")" so-agents)"
check "imprime o tamanho do AGENTS.md em bytes"     "$(sim tem "$out" "^AGENTS.md: $(wc -c < "$SA/AGENTS.md" | tr -d ' ') B")"
check "diz que o CLAUDE.md está ausente"            "$(sim tem "$out" '^CLAUDE.md: ausente')"
check "tem ação proposta"                           "$(sim tem "$out" '^ação: ')"
out="$(roda "$S1")"
check "so-import: ação é nada a fazer"              "$(sim tem "$out" '^ação: nada a fazer')"
out="$(roda "$LF")"
check "symlink: mostra para onde o link aponta"     "$(sim tem "$out" '^CLAUDE.md: symlink -> AGENTS.md')"

out="$(roda "$CD")"
check "copia-duplicada: conta 4 linhas repetidas"   "$(sim tem "$out" '^copia-duplicada: 4 linhas')"
check "copia-duplicada: linha repetida sai do CLAUDE.md" \
  "$(sim na_secao "$out" '^proposta: sai do CLAUDE.md' 'Nunca rode supabase db reset')"
check "copia-duplicada: a skill fica no CLAUDE.md"  "$(sim na_secao "$out" '^proposta: fica no CLAUDE.md' '\[skill\] - Use a skill ship')"
out="$(roda "$IC")"
check "cabeçalho igual não é cópia colada"          "$(sim nao_tem "$out" '^copia-duplicada:')"
check "import+conteudo: o hook fica no CLAUDE.md"   "$(sim na_secao "$out" '^proposta: fica no CLAUDE.md' '\[hook\] - O hook do kit')"
out="$(roda "$II")"
check "import no meio da frase fica no CLAUDE.md"   "$(sim na_secao "$out" '^proposta: fica no CLAUDE.md' '\[import\] Leia @AGENTS.md')"
check "import no meio da frase não vai para o AGENTS.md" "$(sim nao_tem "$out" '^proposta: vai para o AGENTS.md')"
out="$(roda "$SCO")"
check "so-claude só com o import: diz que o AGENTS.md não existe" "$(sim tem "$out" '^ação: o CLAUDE.md só importa um AGENTS.md que não existe')"
out="$(roda "$SCI")"
check "so-claude com import: avisa que a linha do import não vai junto" "$(sim tem "$out" '^ação: --apply move .*sem a linha @AGENTS.md')"
out="$(roda "$DVE")"
check "CLAUDE.md vazio: a ação diz isso"            "$(sim tem "$out" '^ação: o CLAUDE.md está vazio')"

out="$(roda "$DV")"
check "divergentes: o hook fica no CLAUDE.md"       "$(sim na_secao "$out" '^proposta: fica no CLAUDE.md' '^  L4 .*\[hook\] - O hook do projeto')"
check "divergentes: o /comando fica no CLAUDE.md"   "$(sim na_secao "$out" '^proposta: fica no CLAUDE.md' '^  L5 .*\[/handoff\] - Rode o comando `/handoff`')"
check "divergentes: a regra comum vai para o AGENTS.md" \
  "$(sim na_secao "$out" '^proposta: vai para o AGENTS.md' '^  L3 .*- Rode `npm test`')"
check "divergentes: mostra o diff (linha que só o AGENTS.md tem)" "$(sim tem "$out" '^-- Rode `npm run check`')"
check "divergentes: mostra o diff (linha que só o CLAUDE.md tem)" "$(sim tem "$out" '^+- Rode `npm test`')"

out="$(roda "$HF")"
F_FICA='^proposta: fica no CLAUDE.md'; F_VAI='^proposta: vai para o AGENTS.md'
check "heurística: /login solto no meio da frase vai para o AGENTS.md"  "$(sim na_secao "$out" "$F_VAI" 'fica em /login')"
check "heurística: React hooks vai para o AGENTS.md"                   "$(sim na_secao "$out" "$F_VAI" 'Use React hooks')"
check "heurística: skill de gente vai para o AGENTS.md"                "$(sim na_secao "$out" "$F_VAI" 'skill em SQL')"
check "heurística: rota entre crases sem contexto vai para o AGENTS.md" "$(sim na_secao "$out" "$F_VAI" 'A rota `/login`')"
check "heurística: nenhum falso positivo fica no CLAUDE.md" \
  "$(sim nao_tem "$(printf '%s\n' "$out" | grep -E 'fica em /login|React hooks|skill em SQL|A rota `/login`' | grep '\[')" .)"
check "heurística: comando entre crases fica no CLAUDE.md"     "$(sim na_secao "$out" "$F_FICA" '\[/revisar\] - Rode o comando')"
check "heurística: /comando no começo da linha fica"           "$(sim na_secao "$out" "$F_FICA" '\[/handoff\] - /handoff do Claude')"
check "heurística: hook com evento fica no CLAUDE.md"          "$(sim na_secao "$out" "$F_FICA" '\[hook\] - O hook PreToolUse')"
check "heurística: skill com SKILL.md fica no CLAUDE.md"       "$(sim na_secao "$out" "$F_FICA" '\[skill\] - A skill de deploy')"
out="$(roda "$SCM")"
check "so-claude com import no meio da frase: avisa que o token não vai junto" "$(sim tem "$out" '^ação: --apply move .*sem o @AGENTS.md')"

out="$(roda "$SC")"
check "so-claude: aponta o que parece só do Claude" "$(sim tem "$out" '\[hook\] - O hook SessionStart')"

out="$(roda "$CX")"
check "caixa: acusa o agents.md minúsculo"          "$(sim tem "$out" '^caixa: agents.md')"
out="$(roda "$CX2")"
check "caixa: acusa o Claude.md"                    "$(sim tem "$out" '^caixa: Claude.md')"
out="$(roda "$S1")"
check "sem nome trocado, não fala de caixa"         "$(sim nao_tem "$out" '^caixa:')"

out="$(roda "$LM")"
check "AGENTS.md com 32769 B passa do limite do Codex" "$(sim tem "$out" '^limite-codex: AGENTS.md tem 32769 B')"
out="$(roda "$LN")"
check "AGENTS.md com 32768 B cabe"                  "$(sim nao_tem "$out" '^limite-codex:')"

out="$(roda "$NG")"
check "aninhados via git: só o par que o git vê"    "$(sim tem "$out" '^aninhados: 1 (via git)')"
check "aninhado: apps/web é so-import"              "$(sim tem "$out" '^aninhado: apps/web — so-import')"
check "aninhado: ignorado pelo .gitignore fica fora" "$(sim nao_tem "$out" 'vendor')"
check "aninhado: worktree fica fora"                "$(sim nao_tem "$out" 'worktrees/wt')"
check "aninhado: pasta com um arquivo só não é par" "$(sim nao_tem "$out" 'packages/solo')"
out="$(roda "$NF")"
check "aninhados via find fora do git"              "$(sim tem "$out" '^aninhados: 1 (via find)')"
check "aninhado: docs é divergentes"                "$(sim tem "$out" '^aninhado: docs — divergentes')"
check "aninhado: node_modules fica fora"            "$(sim nao_tem "$out" 'node_modules')"
check "aninhado: worktree fica fora (find)"         "$(sim nao_tem "$out" 'worktrees/wt')"

out="$( cd "$NG/apps/web" && bash "$SCRIPT" 2>&1 )"
check "sem <repo>, usa a raiz do git de onde roda"  "$(sim tem "$out" "^instrucoes-projeto: $NG\$")"

echo "== códigos de saída =="
roda --nada "$S1" >/dev/null;          check "opção desconhecida sai 2"   "$(sim mesmo "$?" 2)"
roda --check --apply "$S1" >/dev/null; check "--check com --apply sai 2"  "$(sim mesmo "$?" 2)"
roda "$S1" "$SA" >/dev/null;           check "dois repos sai 2"           "$(sim mesmo "$?" 2)"
roda "$TMP/nao-existe" >/dev/null;     check "repo que não existe sai 3"  "$(sim mesmo "$?" 3)"
roda --check "$TMP/nao-existe" >/dev/null; check "idem com --check"      "$(sim mesmo "$?" 3)"

# ── --apply nas três classes seguras ─────────────────────────────────────────
echo "== --apply: so-agents ganha a ponte =="
a0="$(soma "$SA/AGENTS.md")"
out="$(roda --apply "$SA")"; rc=$?
check "sai 0"                                        "$(sim mesmo "$rc" 0)"
check "CLAUDE.md é exatamente @AGENTS.md"            "$(sim ponte_ok "$SA/CLAUDE.md")"
check "AGENTS.md não mudou"                          "$(sim mesmo "$(soma "$SA/AGENTS.md")" "$a0")"
check "o diff aparece antes de gravar"               "$(sim antes "$out" '^\+@AGENTS\.md$' '^gravado: CLAUDE\.md')"
check "depois do --apply é so-import"                "$(sim mesmo "$(classe_de "$(roda "$SA")")" so-import)"
f0="$(foto "$SA")"; out="$(roda --apply "$SA")"; f1="$(foto "$SA")"
check "segundo --apply não grava nada"               "$(sim mesmo "$f0" "$f1")"
check "segundo --apply diz que não gravou"           "$(sim tem "$out" '^nada gravado')"

echo "== --apply: CLAUDE.md -> AGENTS.md vira arquivo, e o AGENTS.md sai intacto =="
a0="$(soma "$LF/AGENTS.md")"
out="$(roda --apply "$LF")"
check "CLAUDE.md deixou de ser link"                 "$(sim nao_eh_link "$LF/CLAUDE.md")"
check "CLAUDE.md é exatamente @AGENTS.md"            "$(sim ponte_ok "$LF/CLAUDE.md")"
check "AGENTS.md com os mesmos bytes"                "$(sim mesmo "$(soma "$LF/AGENTS.md")" "$a0")"
check "depois do --apply é so-import"                "$(sim mesmo "$(classe_de "$(roda "$LF")")" so-import)"

echo "== --apply: AGENTS.md -> CLAUDE.md vira o arquivo com o conteúdo =="
c0="$(soma "$LR/CLAUDE.md")"
out="$(roda --apply "$LR")"
check "AGENTS.md deixou de ser link"                 "$(sim nao_eh_link "$LR/AGENTS.md")"
check "AGENTS.md tem o conteúdo do CLAUDE.md"        "$(sim mesmo "$(soma "$LR/AGENTS.md")" "$c0")"
check "CLAUDE.md é exatamente @AGENTS.md"            "$(sim ponte_ok "$LR/CLAUDE.md")"
check "depois do --apply é so-import"                "$(sim mesmo "$(classe_de "$(roda "$LR")")" so-import)"

echo "== --apply: so-claude move o conteúdo =="
c0="$(soma "$SC/CLAUDE.md")"
out="$(roda --apply "$SC")"
check "AGENTS.md tem o conteúdo antigo do CLAUDE.md" "$(sim mesmo "$(soma "$SC/AGENTS.md")" "$c0")"
check "CLAUDE.md é exatamente @AGENTS.md"            "$(sim ponte_ok "$SC/CLAUDE.md")"
check "o diff do AGENTS.md aparece antes de gravar"  "$(sim antes "$out" '^\+# Projeto Y' '^gravado: AGENTS\.md')"
check "depois do --apply é so-import"                "$(sim mesmo "$(classe_de "$(roda "$SC")")" so-import)"

echo "== --apply: so-claude com import move o resto, sem a linha do import =="
out="$(roda --apply "$SCI")"
check "AGENTS.md tem a regra"                        "$(sim grep -q '^- Regra solta do projeto' "$SCI/AGENTS.md")"
check "AGENTS.md não importa a si mesmo"             "$(sim nao_tem "$(cat "$SCI/AGENTS.md")" '@AGENTS\.md')"
check "CLAUDE.md é exatamente @AGENTS.md"            "$(sim ponte_ok "$SCI/CLAUDE.md")"
check "depois do --apply é so-import"                "$(sim mesmo "$(classe_de "$(roda "$SCI")")" so-import)"

echo "== --apply: so-claude com import no meio da frase tira o token =="
out="$(roda --apply "$SCM")"
check "AGENTS.md tem a regra"                        "$(sim grep -q '^- Rode `npm test`' "$SCM/AGENTS.md")"
check "AGENTS.md sem @AGENTS.md (grep vazio)"        "$(sim mesmo "$(grep '@AGENTS.md' "$SCM/AGENTS.md")" "")"
check "AGENTS.md sem @./AGENTS.md"                   "$(sim mesmo "$(grep '@\./AGENTS\.md' "$SCM/AGENTS.md")" "")"
check "a frase fica, sem o token"                    "$(sim grep -q '^Veja para as regras gerais\.$' "$SCM/AGENTS.md")"
check "CLAUDE.md é exatamente @AGENTS.md"            "$(sim ponte_ok "$SCM/CLAUDE.md")"
check "depois do --apply é so-import"                "$(sim mesmo "$(classe_de "$(roda "$SCM")")" so-import)"

# ── --apply nas outras classes: nada muda ───────────────────────────────────
echo "== --apply não grava onde é preciso julgar =="
for d in "$S1" "$S2" "$IC" "$II" "$BT" "$CD" "$DV" "$DVE" "$SCO" "$LRO" "$LO" "$LQ" "$LB" "$NH" "$HF" "$CX" "$CX2" "$LM" "$NG" "$NF"; do
  f0="$(foto "$d")"; out="$(roda --apply "$d")"; rc=$?; f1="$(foto "$d")"
  check "$(basename "$d"): --apply sai 0 e não grava nada" "$(sim mesmo "$rc|$f0" "0|$f1")"
  check "$(basename "$d"): --apply diz que não gravou"     "$(sim tem "$out" '^nada gravado')"
done
check "caixa: não nasceu AGENTS.md ao lado do agents.md"  "$(sim nao_tem "$(nomes_exatos "$CX")" '^AGENTS.md$')"
check "caixa: não nasceu CLAUDE.md ao lado do Claude.md"  "$(sim nao_tem "$(nomes_exatos "$CX2")" '^CLAUDE.md$')"

# ── o que é do kit ───────────────────────────────────────────────────────────
echo "== o modelo de AGENTS.md é o do plugin =="
check "o modelo existe no plugin"                    "$(sim test -f "$MODELO")"
out="$(roda "$NH")"
check "nenhum: a ação aponta o modelo do plugin"     "$(sim tem "$out" "^ação: .*$MODELO")"
check "nenhum: não fala de bootstrap"                "$(sim nao_tem "$out" 'bootstrap')"
out="$(roda "$SCO")"
check "so-claude só com o import: aponta o modelo do plugin" "$(sim tem "$out" "$MODELO")"

echo "== --apply sem CLAUDE.md não faz barulho =="
SA2="$(novo so-agents-ruido)"; printf '%s' "$AG" > "$SA2/AGENTS.md"
err="$(bash "$SCRIPT" --apply "$SA2" 2>&1 >/dev/null)"
check "stderr vazio no --apply de so-agents (veio: ${err:-nada})" "$(sim mesmo "$err" "")"
check "e o CLAUDE.md nasceu a ponte"                 "$(sim ponte_ok "$SA2/CLAUDE.md")"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
