#!/usr/bin/env bash
# release-trem.sh <versão> <pr>... — junta PRs de feature prontos num release só.
#
# PR de feature não sobe versão nem toca CHANGELOG ou novidades: deixa o texto no corpo, nas
# seções "## Para o CHANGELOG" e "## Para o novidades" (formato no CONTRIBUTING.md). Este
# script:
#   1. lê o corpo de cada PR (gh) e recusa PR fechado ou sem "## Para o CHANGELOG";
#   2. cria o worktree do branch release/<versão> a partir de origin/main;
#   3. dá merge de pull/<n>/head de cada PR, na ordem dada, e para no primeiro conflito
#      dizendo o PR e o arquivo;
#   4. sobe a versão nos cinco lugares (plugin.json, install.sh, kit-setup.sh, topo do
#      CHANGELOG e topo do plugin/novidades.txt), com o bloco do CHANGELOG agrupado por
#      seção (### Adicionado, ### Mudado...) e a linha das novidades juntando os PRs;
#   5. roda tests/test-versao-changelog.sh e tests/test-changelog-bloco.sh e faz o commit.
# Não faz push nem abre PR: imprime os comandos, e o corpo do PR fica num arquivo.
#
# Uso: bash scripts/release-trem.sh <x.y.z> <pr> [<pr>...] [--dir <pasta do worktree>]
# Ambiente: RELEASE_TREM_REPO (dono/repo para o gh; sem ele, o gh usa o do origin),
#           RELEASE_TREM_DATA (data do cabeçalho, AAAA-MM-DD), RELEASE_TREM_SLEEP (retry do gh).
set -uo pipefail

erro() { echo "release-trem: $*" >&2; exit 1; }
uso() { echo "uso: release-trem.sh <x.y.z> <pr> [<pr>...] [--dir <pasta>]" >&2; exit 2; }

V="${1:-}"; [ -n "$V" ] || uso; shift
case "$V" in *[!0-9.]*|.*|*.|*..*) uso ;; esac
[ "$(printf '%s' "$V" | tr -cd . | wc -c | tr -d ' ')" = 2 ] || uso
PRS=""; DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:-}"; [ -n "$DIR" ] || uso; shift 2 ;;
    *[!0-9]*|"") uso ;;
    *) PRS="$PRS $1"; shift ;;
  esac
done
[ -n "$PRS" ] || uso

TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || erro "rode dentro do clone do kit"
[ -f "$TOP/plugin/.claude-plugin/plugin.json" ] || erro "$TOP não é o repo do kit-vamoo (falta plugin/.claude-plugin/plugin.json)"
command -v gh >/dev/null 2>&1 || erro "precisa do gh"
command -v python3 >/dev/null 2>&1 || erro "precisa do python3"
BR="release/$V"
[ -n "$DIR" ] || DIR="$TOP/.claude/worktrees/release-$V"
[ -e "$DIR" ] && erro "$DIR já existe"
git -C "$TOP" show-ref --verify -q "refs/heads/$BR" && erro "o branch $BR já existe"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/release-trem.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

gh_r() { # gh com retry: a API às vezes devolve 502 no meio do trem
  local _
  for _ in 1 2 3; do
    if [ -n "${RELEASE_TREM_REPO:-}" ]; then gh "$@" --repo "$RELEASE_TREM_REPO" && return 0
    else gh "$@" && return 0; fi
    sleep "${RELEASE_TREM_SLEEP:-5}"
  done
  return 1
}

echo "== corpos dos PRs =="
for n in $PRS; do
  gh_r pr view "$n" --json number,title,body,state > "$TMP/pr-$n.json" 2>"$TMP/gh.err" \
    || erro "gh não leu o PR #$n: $(tail -1 "$TMP/gh.err")"
  # O corpo é dado: só o python lê, nada dele passa por eval de shell.
  python3 - "$TMP/pr-$n.json" "$n" <<'PY' || exit 1
import json, re, sys
d = json.load(open(sys.argv[1])); n = sys.argv[2]
if d.get("state") != "OPEN":
    sys.exit(f"release-trem: o PR #{n} está {d.get('state')}, não OPEN")
if not re.search(r"(?im)^##\s*Para o CHANGELOG\s*$", d.get("body") or ""):
    sys.exit(f"release-trem: o PR #{n} não tem a seção '## Para o CHANGELOG' no corpo (formato no CONTRIBUTING.md)")
print(f"  #{n} {d.get('title')}")
PY
done

echo "== worktree $BR a partir de origin/main =="
git -C "$TOP" fetch -q origin main || erro "git fetch origin main falhou"
V_MAIN="$(git -C "$TOP" show origin/main:plugin/.claude-plugin/plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["version"])')"
python3 -c 'import sys;a,b=(tuple(map(int,x.split("."))) for x in sys.argv[1:]);sys.exit(0 if a>b else 1)' "$V" "$V_MAIN" \
  || erro "a versão $V tem que ser maior que a da main ($V_MAIN)"
git -C "$TOP" worktree add -q -b "$BR" "$DIR" origin/main || erro "git worktree add falhou"
echo "  $DIR (main em $V_MAIN)"

echo "== merge dos PRs =="
for n in $PRS; do
  git -C "$DIR" fetch -q origin "pull/$n/head" || erro "não achei pull/$n/head no origin"
  titulo="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["title"])' "$TMP/pr-$n.json")"
  if ! git -C "$DIR" merge -q --no-ff --no-edit -m "Merge #$n: $titulo" FETCH_HEAD >"$TMP/merge.log" 2>&1; then
    conflito="$(git -C "$DIR" diff --name-only --diff-filter=U)"
    git -C "$DIR" merge --abort 2>/dev/null
    [ -n "$conflito" ] || { cat "$TMP/merge.log" >&2; erro "o merge do #$n falhou sem conflito de arquivo"; }
    echo "release-trem: conflito ao juntar o #$n em:" >&2
    printf '%s\n' "$conflito" | sed 's/^/  /' >&2
    echo "  O worktree $DIR ficou com os PRs anteriores ao #$n. Resolva no branch do #$n (rebase na main) ou tire-o do trem." >&2
    exit 3
  fi
  echo "  #$n ok"
done

echo "== versão $V nos cinco lugares, CHANGELOG e novidades =="
python3 - "$DIR" "$V" "${RELEASE_TREM_DATA:-$(date +%F)}" "$TMP" $PRS <<'PY' || erro "montar CHANGELOG/novidades falhou"
import json, os, re, sys
raiz, v, data, tmp = sys.argv[1:5]
prs = sys.argv[5:]

def secao(corpo, nome):
    """Texto da seção '## <nome>' até o próximo '#'/'##', o rodapé '🤖' ou '---'."""
    linhas = corpo.replace("\r\n", "\n").split("\n")
    out, dentro = [], False
    for l in linhas:
        if re.match(r"(?i)^##\s*" + re.escape(nome) + r"\s*$", l.strip()):
            dentro = True; continue
        if dentro:
            if re.match(r"^#{1,2}\s", l) or l.startswith("🤖") or l.strip() == "---":
                break
            out.append(l)
    while out and not out[0].strip(): out.pop(0)
    while out and not out[-1].strip(): out.pop()
    return out

ORDEM = ["Adicionado", "Mudado", "Corrigido", "Removido", "Segurança"]
grupos, novidades, setup = {}, [], False
for n in prs:
    d = json.load(open(os.path.join(tmp, f"pr-{n}.json")))
    corpo = d.get("body") or ""
    atual, pedaco = "Mudado", {}
    for l in secao(corpo, "Para o CHANGELOG"):
        m = re.match(r"^###\s+(.+?)\s*$", l)
        if m:
            atual = m.group(1); continue
        pedaco.setdefault(atual, []).append(l)
    for s, ls in pedaco.items():
        while ls and not ls[0].strip(): ls.pop(0)
        while ls and not ls[-1].strip(): ls.pop()
        if ls: grupos.setdefault(s, []).append(ls)
    nov = secao(corpo, "Para o novidades")
    texto = []
    for l in nov:
        t = l.strip()
        if t.lower() in ("setup", "|setup"): setup = True; continue
        if t.lower().endswith("|setup"): setup = True; t = t[: -len("|setup")]
        if t: texto.append(t)
    if texto:
        novidades.append(" ".join(texto).replace("|", "/").rstrip(".; "))

if not grupos:
    sys.exit("release-trem: nenhum PR trouxe texto em '## Para o CHANGELOG'")
if not novidades:
    sys.exit("release-trem: nenhum PR trouxe '## Para o novidades'; o aviso do SessionStart ficaria sem a versão")

ordem = [s for s in ORDEM if s in grupos] + [s for s in grupos if s not in ORDEM]
bloco = [f"## [{v}] — {data}", ""]
for s in ordem:
    bloco += [f"### {s}", ""]
    corpo = []
    for ls in grupos[s]:
        if corpo:
            lista = corpo[-1].lstrip().startswith(("- ", "* ")) and ls[0].startswith(("- ", "* "))
            if not lista: corpo.append("")
        corpo += ls
    bloco += corpo + [""]

cl = os.path.join(raiz, "CHANGELOG.md")
linhas = open(cl, encoding="utf-8").read().split("\n")
i = next((k for k, l in enumerate(linhas) if l.startswith("## [")), None)
if i is None: sys.exit("release-trem: CHANGELOG.md sem nenhum '## [' para inserir acima")
open(cl, "w", encoding="utf-8").write("\n".join(linhas[:i] + bloco + linhas[i:]))

nv = os.path.join(raiz, "plugin/novidades.txt")
linhas = open(nv, encoding="utf-8").read().split("\n")
i = next((k for k, l in enumerate(linhas) if l.strip() and not l.lstrip().startswith("#")), len(linhas))
linha = f"{v}|" + "; ".join(novidades) + ("|setup" if setup else "")
open(nv, "w", encoding="utf-8").write("\n".join(linhas[:i] + [linha] + linhas[i:]))

pj = os.path.join(raiz, "plugin/.claude-plugin/plugin.json")
s = open(pj, encoding="utf-8").read()
s2 = re.sub(r'("version"\s*:\s*")[^"]*(")', lambda m: m.group(1) + v + m.group(2), s, count=1)
if s2 == s: sys.exit("release-trem: não achei o version no plugin.json")
open(pj, "w", encoding="utf-8").write(s2)
for f in ("install.sh", "plugin/scripts/kit-setup.sh"):
    p = os.path.join(raiz, f)
    s = open(p, encoding="utf-8").read()
    s2 = re.sub(r'(?m)^KIT_VERSION="[^"]*"', f'KIT_VERSION="{v}"', s, count=1)
    if s2 == s: sys.exit(f"release-trem: não achei KIT_VERSION em {f}")
    open(p, "w", encoding="utf-8").write(s2)
print("  novidades: " + linha)
PY

echo "== gates de versão =="
for t in test-versao-changelog test-changelog-bloco; do
  [ -f "$DIR/tests/$t.sh" ] || { echo "  (sem tests/$t.sh neste repo)"; continue; }
  if [ "$t" = test-versao-changelog ]; then bash "$DIR/tests/$t.sh" "$DIR" > "$TMP/$t.log" 2>&1
  else bash "$DIR/tests/$t.sh" > "$TMP/$t.log" 2>&1; fi \
    || { cat "$TMP/$t.log" >&2; erro "tests/$t.sh reprovou no release; o worktree ficou em $DIR sem commit"; }
  echo "  ok $t"
done

lista="$(for n in $PRS; do printf '#%s ' "$n"; done | sed 's/ $//')"
git -C "$DIR" add plugin/.claude-plugin/plugin.json install.sh plugin/scripts/kit-setup.sh CHANGELOG.md plugin/novidades.txt
git -C "$DIR" commit -q -m "chore(release): $V ($lista)" || erro "commit do bump falhou"

CORPO="$(git -C "$DIR" rev-parse --git-dir)/release-trem-$V.md"
python3 - "$TMP" "$V" "$CORPO" $PRS <<'PY'
import json, os, sys
tmp, v, saida = sys.argv[1:4]; prs = sys.argv[4:]
l = [f"Release que junta {len(prs)} PR(s) já revisados num ciclo de CI só (scripts/release-trem.sh).", "", "**PRs incluídos:**"]
for n in prs:
    d = json.load(open(os.path.join(tmp, f"pr-{n}.json")))
    l.append(f"- #{n} ({d['title']})")
l += ["", f"Versão {v} nos 5 lugares, com o CHANGELOG e o novidades montados do corpo de cada PR.", "",
      "Depois do merge, feche os PRs incluídos (o squash do release não os fecha):", "```"]
l += [f"gh pr close {n} --comment 'Entrou no release {v}.'" for n in prs]
l += ["```", ""]
open(saida, "w", encoding="utf-8").write("\n".join(l))
PY

echo
echo "release/$V pronto em $DIR (commit $(git -C "$DIR" rev-parse --short HEAD)). Nada foi enviado."
echo "Revise o CHANGELOG e a linha das novidades, e então:"
echo "  git -C $DIR push -u origin $BR"
echo "  gh pr create --draft --head $BR --title 'release: $V' --body-file $CORPO"
