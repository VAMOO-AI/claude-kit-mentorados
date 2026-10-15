#!/usr/bin/env bash
# Prova de consistência da documentação versionada do kit.
#
# O que reprova:
#   - link relativo em Markdown (`[x](caminho)`, `![x](caminho)`, `[x]: caminho`) e
#     `href="…"`/`src="…"` dentro de .md que apontam para arquivo que não existe;
#   - âncora (`arquivo.md#secao` ou `#secao`) que não bate com nenhum título do alvo,
#     com o slug calculado como o GitHub calcula (minúsculas, acento mantido, pontuação
#     fora, cada espaço vira hífen, título repetido ganha -1, -2…) ou com um id/name
#     declarado em HTML;
#   - .json versionado que não parseia.
#
# Link e título dentro de bloco de código ou de `código inline` não contam. Link com
# esquema (https:, mailto:), caminho de instalação (~/…) ou placeholder ({{ }}, <<, $) fica
# de fora: não é arquivo deste repo.
#
# A lista sai de `git ls-files`, nunca de `find`: .claude/worktrees/ guarda cópias inteiras
# do repo, que dobrariam cada achado.
#
# ideia de soumatheusgomes/vibe-coding-toolkit (MIT), validate-docs.mjs; reimplementado.
#
# Uso: bash tests/test-docs-consistencia.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
command -v python3 >/dev/null 2>&1 || { echo "python3 ausente"; exit 2; }
git -C "$RAIZ" rev-parse --show-toplevel >/dev/null 2>&1 || { echo "não é um repo git: $RAIZ"; exit 2; }

confere_repo() { # <raiz>
git -C "$1" ls-files -z -- '*.md' '*.json' | python3 -I -c '
import json, os, re, sys, unicodedata
from urllib.parse import unquote

raiz = sys.argv[1]
arquivos = [a for a in sys.stdin.buffer.read().decode().split("\0") if a]
falhas = []
conferidos = {"links": 0, "ancoras": 0}

# Cerca de bloco (CommonMark): 3+ crases ou tis, até 3 espaços de recuo. Depois de crase
# a info string não pode ter crase: "```text ... ```" no começo da linha é código inline,
# não abre bloco (o GitHub renderiza assim, e o título seguinte segue virando âncora).
FENCE = re.compile(r"^ {0,3}(?:`{3,}[^`]*|~{3,}.*)$")
INLINE = re.compile(r"(`+)(?:(?!\1).)+?\1")
TITULO = re.compile(r"^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$")
LINK = re.compile(r"!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
REF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s+.*)?$")
ATTR = re.compile(r"""\b(?:href|src)\s*=\s*["\x27]([^"\x27]+)["\x27]""")
ID = re.compile(r"""\b(?:id|name)\s*=\s*["\x27]([^"\x27]+)["\x27]""")
ESQUEMA = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")

def linhas_fora_de_codigo(texto):
    dentro = False
    for n, l in enumerate(texto.split("\n"), 1):
        if FENCE.match(l):
            dentro = not dentro
            continue
        if not dentro:
            yield n, INLINE.sub("", l)

def texto_do_titulo(t):
    t = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", t)   # [x](y) → x
    t = re.sub(r"<[^>]+>", "", t)                        # tags HTML
    t = t.replace("`", "")
    t = re.sub(r"\*\*|__|\*", "", t)                     # ênfase
    return t

def slug(t):
    t = texto_do_titulo(t).strip().lower()
    out = []
    for c in t:
        cat = unicodedata.category(c)
        if c in " -_" or cat[0] in "LN" or cat[0] == "M":
            out.append(c)
    return "".join(out).replace(" ", "-")

cache = {}
def ancoras(rel):
    if rel in cache:
        return cache[rel]
    vistos, nomes = {}, set()
    try:
        texto = open(os.path.join(raiz, rel), encoding="utf-8").read()
    except OSError:
        cache[rel] = None
        return None
    dentro = False
    for l in texto.split("\n"):
        if FENCE.match(l):
            dentro = not dentro
            continue
        if dentro:
            continue
        for i in ID.findall(l):
            nomes.add(i.lower())
        m = TITULO.match(l)
        if not m:
            continue
        s = slug(m.group(2))
        if s in vistos:
            vistos[s] += 1
            nomes.add(f"{s}-{vistos[s]}")
        else:
            vistos[s] = 0
            nomes.add(s)
    cache[rel] = nomes
    return nomes

def confere(origem, n, alvo):
    alvo = alvo.strip()
    if not alvo or ESQUEMA.match(alvo) or alvo.startswith(("//", "~", "<")):
        return
    if any(p in alvo for p in ("{{", "<<", "$", "...", "…")):
        return
    conferidos["links"] += 1
    caminho, _, frag = alvo.partition("#")
    caminho = unquote(caminho.split("?")[0])
    if caminho:
        base = raiz if caminho.startswith("/") else os.path.join(raiz, os.path.dirname(origem))
        destino = os.path.normpath(os.path.join(base, caminho.lstrip("/")))
        if not os.path.relpath(destino, raiz).startswith(".."):
            if not os.path.exists(destino):
                falhas.append(f"{origem}:{n}: link para arquivo inexistente: {alvo}")
                return
        else:
            return
        rel = os.path.relpath(destino, raiz)
    else:
        rel = origem
    if frag and rel.endswith(".md") and os.path.isfile(os.path.join(raiz, rel)):
        nomes = ancoras(rel)
        conferidos["ancoras"] += 1
        if nomes is not None and unquote(frag).lower() not in nomes:
            falhas.append(f"{origem}:{n}: âncora #{frag} não existe em {rel}")

for a in arquivos:
    p = os.path.join(raiz, a)
    if not os.path.isfile(p):
        continue
    if a.endswith(".json"):
        try:
            json.load(open(p, encoding="utf-8"))
        except Exception as e:
            falhas.append(f"{a}: JSON inválido: {e}")
        continue
    texto = open(p, encoding="utf-8").read()
    for n, l in linhas_fora_de_codigo(texto):
        for alvo in LINK.findall(l):
            confere(a, n, alvo)
        m = REF.match(l)
        if m:
            confere(a, n, m.group(1))
        for alvo in ATTR.findall(l):
            confere(a, n, alvo)

for f in falhas:
    print(f"  FALHA {f}")
md = sum(1 for a in arquivos if a.endswith(".md"))
js = len(arquivos) - md
print()
if falhas:
    print(f"{len(falhas)} falha(s) em {md} .md e {js} .json")
    sys.exit(1)
nl, na = conferidos["links"], conferidos["ancoras"]
print(f"tudo verde ({md} .md, {js} .json, {nl} links, {na} âncoras)")
' "$1"
}

# Antes do repo de verdade, um repo de mentira com um erro de cada tipo: gate que não
# reprova o erro plantado aprovaria qualquer coisa.
FIX=$(mktemp -d); trap 'rm -rf "$FIX"' EXIT
git -C "$FIX" init -q
mkdir -p "$FIX/docs"
cat > "$FIX/docs/alvo.md" <<'MD'
# Título com Acentuação e `código`
## Seção
## Seção
<a id="ancora-html"></a>
```
## dentro-de-codigo
```
```text inline``` no começo da linha não abre bloco
## Depois do inline
MD
cat > "$FIX/README.md" <<'MD'
[ok](docs/alvo.md) [ok](docs/alvo.md#título-com-acentuação-e-código)
[ok](docs/alvo.md#seção-1) [ok](docs/alvo.md#ancora-html) [ok](https://example.com/x)
[ok](#leia) ![ok](docs/alvo.md) [ok](docs/alvo.md#depois-do-inline) [ok]: docs/alvo.md
# Leia
[QUEBRADO-arquivo](docs/nao-existe.md)
[QUEBRADO-ancora](docs/alvo.md#secao-sem-acento)
[QUEBRADO-dup](docs/alvo.md#seção-2)
[QUEBRADO-codigo](docs/alvo.md#dentro-de-codigo)
<img src="docs/QUEBRADO-src.png">
`[ignorado](nao-existe-inline.md)`
```
[ignorado](nao-existe-fence.md)
```
MD
echo '{"quebrado": }' > "$FIX/QUEBRADO.json"
git -C "$FIX" add -A
saida=$(confere_repo "$FIX"); rc=$?
falhas_fix=0
espera() { # <padrão> <descrição>
  if printf '%s' "$saida" | grep -qF -- "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não achei %s)\n' "$2" "$1"; falhas_fix=$((falhas_fix+1)); fi
}
echo "== o gate reprova o erro plantado =="
[ "$rc" = 1 ] && printf '  ok    sai 1\n' || { printf '  FALHA rc=%s\n' "$rc"; falhas_fix=$((falhas_fix+1)); }
espera 'docs/nao-existe.md' "arquivo inexistente"
espera '#secao-sem-acento' "âncora sem o acento do título"
espera '#seção-2' "terceira ocorrência que não existe (só -1)"
espera '#dentro-de-codigo' "título dentro de bloco de código não vira âncora"
espera 'QUEBRADO-src.png' "src= dentro de .md"
espera 'QUEBRADO.json' "JSON inválido"
n=$(printf '%s' "$saida" | grep -c 'FALHA')
[ "$n" = 6 ] && printf '  ok    exatamente 6 achados (os links ok e os de código não acusam)\n' \
  || { printf '  FALHA %s achados, esperava 6:\n%s\n' "$n" "$saida"; falhas_fix=$((falhas_fix+1)); }
[ "$falhas_fix" -eq 0 ] || { echo; echo "$falhas_fix falha(s) no autoteste"; exit 1; }

echo
echo "== o repo =="
confere_repo "$RAIZ"
