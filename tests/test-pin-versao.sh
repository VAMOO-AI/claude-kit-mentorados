#!/usr/bin/env bash
# Nada sem versão no que o kit distribui: o que está em plugin/ e skills/ não manda baixar e
# rodar a última versão de pacote de terceiro, nem sobe MCP sozinho.
#
# O que reprova, nos arquivos versionados de plugin/ e skills/ (o que existir dos dois):
#   - latest: `@latest` em qualquer linha (npx, npm, go install…);
#   - runner-sem-versao: `npx` com pacote sem `@versão`, e os outros runners que baixam e
#     rodam: `bunx`, `pnpm dlx`, `yarn dlx`, `uvx`, `uv tool run`, `pipx run`. Sem terminal
#     interativo (o Bash do agente) o `npx` assume `--yes`, então `-y` não muda nada; só o
#     binário do projeto (`tsc`, `eslint`, `vitest`…) passa sem versão, e só sem `-y`;
#   - instalador-sem-versao: instalação global sem versão (`npm install -g`, `npm i -g`,
#     `pnpm add -g`, `bun add -g`, `yarn global add`, `uv tool install`, `pipx install`) e
#     `pip install` de pacote sem `==`;
#   - mcp: `.mcp.json` versionado, ou `.json` com a chave `mcpServers` (o plugin.json aceita
#     o bloco inline). É MCP que sobe sozinho em toda sessão de quem instala.
# Versão é `@x` ou `==x` com algum dígito: `@12` passa, `@next` não. Regra de permissão
# (`Bash(…)`, `PowerShell(…)`) também: é padrão de casamento do allow/deny, não comando.
#
# Exceção vai em tests/pin-versao.allow, `<arquivo>:<linha> :: <motivo>`. Entrada sem achado
# na linha reprova: o trecho mudou de linha ou saiu, e a lista não acumula entulho. Histórico
# que cresce pelo topo (cada versão empurra as linhas) entra inteiro, `<arquivo> :: <motivo>`,
# e reprova do mesmo jeito quando o arquivo não tem mais achado.
#
# Origem da ideia: afonsoft/skills (MIT); reimplementado. Lá uma skill proíbe `npx` sem
# versão no texto e o `.mcp.json` do mesmo repo sobe `@latest`.
#
# Uso: bash tests/test-pin-versao.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
command -v python3 >/dev/null 2>&1 || { echo "python3 ausente"; exit 2; }
git -C "$RAIZ" rev-parse --show-toplevel >/dev/null 2>&1 || { echo "não é um repo git: $RAIZ"; exit 2; }

confere_repo() { # <raiz> <allowlist>
git -C "$1" ls-files -z -- plugin skills | python3 -I -c '
import json, os, re, sys

raiz, allow_path = sys.argv[1], sys.argv[2]
arquivos = [a for a in sys.stdin.buffer.read().decode().split("\0") if a]
if not arquivos:
    print("nada versionado em plugin/ nem skills/: o gate não teria o que varrer")
    sys.exit(2)

LATEST = re.compile(r"@latest\b")
PERMISSAO = re.compile(r"\b(?:Bash|PowerShell)\([^)]*\)")
# Fronteira de comando: crase de código inline, ;, &&, ||, |, $( e parênteses.
SEP = re.compile(r"&&|\|\||\$\(|[;|()`]")
PLACEHOLDER = re.compile(r"[<>{}$…]|\.\.\.")
ASPAS = "\"\x27,"
# (palavras do comando, família da versão, regra, binário do projeto passa sem -y, exige -g)
COMANDOS = [
    (("npx",), "npm", "runner-sem-versao", True, False),
    (("bunx",), "npm", "runner-sem-versao", True, False),
    (("pnpm", "dlx"), "npm", "runner-sem-versao", True, False),
    (("yarn", "dlx"), "npm", "runner-sem-versao", True, False),
    (("uvx",), "py", "runner-sem-versao", False, False),
    (("uv", "tool", "run"), "py", "runner-sem-versao", False, False),
    (("pipx", "run"), "py", "runner-sem-versao", False, False),
    (("npm", "install"), "npm", "instalador-sem-versao", False, True),
    (("npm", "i"), "npm", "instalador-sem-versao", False, True),
    (("pnpm", "add"), "npm", "instalador-sem-versao", False, True),
    (("bun", "add"), "npm", "instalador-sem-versao", False, True),
    (("bun", "install"), "npm", "instalador-sem-versao", False, True),
    (("yarn", "global", "add"), "npm", "instalador-sem-versao", False, False),
    (("uv", "tool", "install"), "py", "instalador-sem-versao", False, False),
    (("pipx", "install"), "py", "instalador-sem-versao", False, False),
    (("pip", "install"), "py", "instalador-sem-versao", False, False),
    (("pip3", "install"), "py", "instalador-sem-versao", False, False),
]
FLAG_PACOTE = {"-p", "--package", "--spec", "--from"}  # o valor da flag é o pacote
FLAG_COM_VALOR = {"-c", "--call", "-w", "--workspace", "--prefix", "--registry", "-i",
                  "--index-url", "--extra-index-url", "--python", "--with", "-t", "--target"}
GLOBAL = {"-g", "--global", "--location=global"}
# Binário que o projeto já tem em node_modules/.bin: o runner usa o local, sem baixar.
# atalho: lista fixa, não lê o package.json do projeto; acrescentar o binário que aparecer.
BINARIO_DO_PROJETO = {"tsc", "tsx", "eslint", "prettier", "vitest", "jest", "playwright", "supabase",
                      "remotion", "next", "vite", "biome"}
DE_ARQUIVO = {"-r", "--requirement", "-e", "--editable"}  # pip instala do arquivo ou caminho

def tem_versao(spec, familia):
    if familia == "py" and re.search(r"(?:==|~=)\s*\d", spec):
        return True
    nome = spec[1:] if spec.startswith("@") else spec  # @escopo/pacote@versão
    return "@" in nome and bool(re.search(r"\d", nome.rsplit("@", 1)[1]))

def fora(spec):  # placeholder, caminho, URL ou flag: não é pacote de registry
    return (not spec or PLACEHOLDER.search(spec) or ":" in spec
            or spec.startswith((".", "/", "~", "-")))

def pacote(ts, j):
    """O primeiro pacote depois do comando, e as flags vistas antes dele."""
    flags = set()
    while j < len(ts):
        t = ts[j]
        chave = t.split("=", 1)[0]
        if t in FLAG_PACOTE:
            return (ts[j + 1] if j + 1 < len(ts) else None), flags
        if chave in FLAG_PACOTE and "=" in t:
            return t.split("=", 1)[1], flags
        if t in FLAG_COM_VALOR:
            j += 2
            continue
        if t.startswith("-"):
            flags.add(t)
            j += 1
            continue
        return t, flags
    return None, flags

def regras_da_linha(l):
    regras = set()
    l = PERMISSAO.sub(" ", l)
    if LATEST.search(l):
        regras.add("latest")
    for seg in SEP.split(l):
        ts = [t.strip(ASPAS) for t in seg.split()]
        for i in range(len(ts)):
            for palavras, familia, regra, local_passa, exige_g in COMANDOS:
                k = len(palavras)
                if ts[i].rsplit("/", 1)[-1] != palavras[0] or tuple(ts[i + 1:i + k]) != palavras[1:]:
                    continue
                # atalho: só o primeiro pacote do comando é conferido, então `pip install a b`
                # passa com o `b` solto; revisitar se o kit passar a instalar vários de uma vez.
                spec, flags = pacote(ts, i + k)
                if local_passa and spec in BINARIO_DO_PROJETO and not flags & {"-y", "--yes"}:
                    continue
                if exige_g and not GLOBAL & set(ts[i + k:]):
                    continue
                if familia == "py" and flags & DE_ARQUIVO:
                    continue
                if spec is None or fora(spec) or tem_versao(spec, familia):
                    continue
                regras.add(regra)
    return regras

def tem_chave(dado, chave):
    if isinstance(dado, dict):
        return chave in dado or any(tem_chave(v, chave) for v in dado.values())
    if isinstance(dado, list):
        return any(tem_chave(v, chave) for v in dado)
    return False

achados = {}  # (arquivo, linha) -> (regras, trecho)
for a in arquivos:
    p = os.path.join(raiz, a)
    if not os.path.isfile(p):
        continue
    bruto = open(p, "rb").read()
    if b"\0" in bruto:
        continue  # binário
    texto = bruto.decode("utf-8", errors="replace")
    linhas = texto.split("\n")
    for n, l in enumerate(linhas, 1):
        r = regras_da_linha(l)
        if r:
            achados[(a, n)] = (r, l.strip())
    if a.endswith(".json"):
        mcp = os.path.basename(a) == ".mcp.json"
        if not mcp:
            try:
                mcp = tem_chave(json.loads(texto), "mcpServers")
            except ValueError:
                pass  # JSON inválido é do test-docs-consistencia.sh
        if mcp:
            n = next((i for i, l in enumerate(linhas, 1) if "mcpServers" in l), 1)
            r, trecho = achados.get((a, n), (set(), linhas[n - 1].strip()))
            achados[(a, n)] = (r | {"mcp"}, trecho)

permitidos, inteiros, falhas = {}, {}, []
nome_allow = os.path.relpath(allow_path, raiz)
if os.path.isfile(allow_path):
    for k, l in enumerate(open(allow_path, encoding="utf-8"), 1):
        l = l.strip()
        if not l or l.startswith("#"):
            continue
        local, sep, motivo = l.partition(" :: ")
        local = local.strip()
        if not sep or not motivo.strip() or not local:
            falhas.append(f"{nome_allow}:{k}: entrada fora do formato <arquivo>[:<linha>] :: <motivo>: {l}")
            continue
        m = re.fullmatch(r"(.+):(\d+)", local)
        if m:
            permitidos[(m.group(1), int(m.group(2)))] = k
        else:
            inteiros[local] = k

for (a, n), (r, trecho) in sorted(achados.items()):
    if (a, n) not in permitidos and a not in inteiros:
        rs = ", ".join(sorted(r))
        falhas.append(f"{a}:{n}: [{rs}] {trecho[:140]}")
for (a, n), k in sorted(permitidos.items()):
    if (a, n) not in achados:
        falhas.append(f"{nome_allow}:{k}: entrada órfã {a}:{n}: a linha não tem achado. "
                      "Se o trecho só mudou de linha, atualize o número; se saiu, tire a entrada")
com_achado = {a for a, _ in achados}
for a, k in sorted(inteiros.items()):
    if a not in com_achado:
        falhas.append(f"{nome_allow}:{k}: entrada órfã {a}: o arquivo inteiro não tem achado. "
                      "Tire a entrada")

for f in falhas:
    print(f"  FALHA {f}")
pastas = " e ".join(sorted({a.split("/", 1)[0] + "/" for a in arquivos}))
print()
if falhas:
    print(f"{len(falhas)} falha(s) em {len(arquivos)} arquivos de {pastas}")
    sys.exit(1)
print(f"tudo verde ({len(arquivos)} arquivos de {pastas}, {len(achados)} achado(s), "
      "todos na allowlist com motivo)")
' "$1" "$2"
}

# Antes do repo de verdade, um repo de mentira com um erro de cada tipo: gate que não
# reprova o erro plantado aprovaria qualquer coisa.
FIX=$(mktemp -d); trap 'rm -rf "$FIX"' EXIT
git -C "$FIX" init -q
mkdir -p "$FIX/skills/a" "$FIX/plugin/.claude-plugin" "$FIX/docs" "$FIX/tests"
cat > "$FIX/skills/a/SKILL.md" <<'MD'
# Skill de mentira
Rode `npx -y QUEBRADO-npx-y daily` para medir.
npx --yes @escopo/QUEBRADO-escopo
npm install -g QUEBRADO-global && npm install ok-local-do-projeto
Instale com `uv tool install QUEBRADO-uv` (ou `pipx install ok-pipx==1.4`).
~/.venvs/x/bin/pip install QUEBRADO-pip; pip install -r requirements.txt
`bunx QUEBRADO-bunx` `uvx ok-uvx@0.6.0` `bunx <ferramenta>`
go install example.com/QUEBRADO-latest@latest
`npx -y ok-pinado@1.2.3` `npx -y ok-major@12` `npx tsc --noEmit` `npx eslint . --fix`
Sem terminal o npx assume yes: `DO_NOT_TRACK=1 npx QUEBRADO-sem-y find x`
npm i -g ok-global@0.5.13; npm install --global @escopo/ok-escopo@2.0.0
`pip install`, `python -m pip install -e .` e `pnpm add ok-local` não instalam nada solto
A opção `mcpServers` do Agent SDK é prosa, não config.
Linha liberada: `npx -y ALLOW-ok@latest daily`
MD
echo '{"mcpServers": {"x": {"command": "npx"}}}' > "$FIX/plugin/.mcp.json"
printf '{\n  "name": "x",\n  "mcpServers": {"y": {"command": "z"}}\n}\n' > "$FIX/plugin/.claude-plugin/plugin.json"
echo '{"name": "ok", "scripts": {"start": "npx remotion studio"}}' > "$FIX/skills/a/package.json"
mkdir -p "$FIX/plugin/templates"
printf '{"permissions": {"allow": ["PowerShell(bunx tsc *)"],\n  "deny": ["Bash(bunx *supabase* db push *)", "Bash(npx -y supabase@latest db push*)"]}}\n' \
  > "$FIX/plugin/templates/settings.json"
printf '0.2.0|linha nova empurra as de baixo\n0.1.0|o MCP vem de npx -y ALLOW-historico@latest\n' > "$FIX/plugin/novidades.txt"
echo '# Sem achado nenhum' > "$FIX/skills/a/sem-achado.md"
echo 'npx -y ok-fora-do-escopo@latest' > "$FIX/docs/fora.md"
n_allow=$(grep -n 'ALLOW-ok' "$FIX/skills/a/SKILL.md" | cut -d: -f1)
cat > "$FIX/tests/pin-versao.allow" <<ALLOW
# comentário e linha vazia não contam

skills/a/SKILL.md:$n_allow :: caso liberado do autoteste
skills/a/SKILL.md:1 :: QUEBRADO-orfa: o título não tem achado
plugin/novidades.txt :: histórico que cresce pelo topo entra inteiro
skills/a/sem-achado.md :: QUEBRADO-orfa-inteira: arquivo sem achado
ALLOW
git -C "$FIX" add -A
saida=$(confere_repo "$FIX" "$FIX/tests/pin-versao.allow"); rc=$?
falhas_fix=0
espera() { # <padrão> <descrição>
  if printf '%s' "$saida" | grep >/dev/null -F -- "$1"; then printf '  ok    %s\n' "$2"
  else printf '  FALHA %s (não achei %s)\n' "$2" "$1"; falhas_fix=$((falhas_fix+1)); fi
}
echo "== o gate reprova o erro plantado =="
[ "$rc" = 1 ] && printf '  ok    sai 1\n' || { printf '  FALHA rc=%s\n' "$rc"; falhas_fix=$((falhas_fix+1)); }
espera '[runner-sem-versao] Rode `npx -y QUEBRADO-npx-y' "npx -y sem versão"
espera 'QUEBRADO-escopo' "npx --yes com @escopo/pacote sem versão"
espera 'QUEBRADO-sem-y' "npx sem -y e sem versão (binário do projeto passa)"
espera '[instalador-sem-versao] npm install -g QUEBRADO-global' "npm install -g sem versão (o local passa)"
espera 'QUEBRADO-uv' "uv tool install sem versão (o pipx com == passa)"
espera 'QUEBRADO-pip' "pip install sem == pelo caminho do venv (o -r passa)"
espera 'QUEBRADO-bunx' "bunx sem versão (uvx com @ e placeholder passam)"
espera '[latest] go install example.com/QUEBRADO-latest@latest' "@latest fora de npx"
espera 'plugin/.mcp.json:1: [mcp]' ".mcp.json versionado"
espera 'plugin/.claude-plugin/plugin.json:3: [mcp]' "mcpServers no plugin.json, na linha da chave"
espera 'entrada órfã skills/a/SKILL.md:1' "entrada órfã da allowlist"
espera 'entrada órfã skills/a/sem-achado.md: o arquivo inteiro' "entrada órfã de arquivo inteiro"
n=$(printf '%s' "$saida" | grep -c 'FALHA')
[ "$n" = 12 ] && printf '  ok    exatamente 12 achados (pinado, binário do projeto, local, prosa, permissão, fora do escopo e liberado não acusam)\n' \
  || { printf '  FALHA %s achados, esperava 12:\n%s\n' "$n" "$saida"; falhas_fix=$((falhas_fix+1)); }
[ "$falhas_fix" -eq 0 ] || { echo; echo "$falhas_fix falha(s) no autoteste"; exit 1; }

echo
echo "== o repo =="
confere_repo "$RAIZ" "$RAIZ/tests/pin-versao.allow"
