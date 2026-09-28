#!/usr/bin/env bash
# Lint do texto que o modelo lê: plugin/skills/*/SKILL.md, plugin/skills/*/references/*.md,
# plugin/templates/CLAUDE*.md e plugin/templates/subagentes.md. CHANGELOG, docs/ e testes
# ficam fora: lá frase de tempo e caminho antigo são o assunto, não instrução.
#
# Uma auditoria achou à mão caminho citado que não existe, frase que só faz sentido para
# quem conhece a versão anterior ("voltaram a aparecer") e arquivo de instrução instalado
# onde o Claude Code o lê em toda sessão. Este teste é o gate para esses erros não voltarem:
#
#   R1  caminho do kit entre crases (ou em bloco cercado) que não existe. `skills/`,
#       `references/`, `hooks/`, `templates/`, `agents/`, `plugin/…`, `<skill>/…` e
#       `${CLAUDE_PLUGIN_ROOT}/…` resolvem pela pasta da skill e por `plugin/`.
#       `~/.claude/…` é conferido contra o que o plugin/scripts/kit-setup.sh instala num
#       HOME descartável; skill, hook, agente e comando do kit vêm pelo plugin, então
#       `~/.claude/skills/<skill-do-kit>/…` reprova. Placeholder (`<…>`) e glob não contam.
#   R2  skill com `disable-model-invocation: true` citada como chamável ("chame a skill X",
#       `Skill(X)`, "pela tool Skill") fora da forma `/x` ou `/kit-vamoo:x`.
#   R3  frase relativa a versão ou tempo ("voltou a", "não existe mais", "agora é",
#       "desde a 0.x", "antes era"…). Ela envelhece no dia seguinte ao merge.
#   R4  arquivo de instrução no lugar errado, pelo destino real: roda o kit-setup.sh num
#       HOME descartável e reprova ~/.claude/agents.md em qualquer caixa (o Mac não
#       diferencia, e o Claude Code lê como AGENTS.md em toda sessão), ~/AGENTS.md,
#       ~/CLAUDE.md e um ~/.claude/CLAUDE.md que não seja o plugin/templates/CLAUDE-global.md.
#
# `scripts/…` e `docs/…` soltos são ambíguos: o texto das skills cita o `scripts/db-query.sh`
# e o `docs/security-audit/` DO PROJETO do mentorado. Por isso eles só reprovam quando a
# skill tem a própria pasta `scripts/`/`docs/` ou quando a pasta-mãe existe no plugin abaixo
# do primeiro nível (`scripts/templates/x`).
# atalho: `scripts/x.sh` solto de um script do plugin renomeado passa calado; revisitar se um
# desses escapar para o main (o `${CLAUDE_PLUGIN_ROOT}/scripts/x.sh` é conferido sempre).
#
# Exceção que sobra vai em tests/lint-instrucoes.allow, uma por linha:
#   <regra> :: <arquivo> :: <trecho literal da linha> :: <motivo>
# Entrada que não casa com nada reprova: allowlist sem gate apodrece e vira buraco.
#
# Uso: bash tests/test-lint-instrucoes.sh [raiz-do-repo] [allowlist]
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
KIT="${1:-$RAIZ}"
ALLOW="${2:-$RAIZ/tests/lint-instrucoes.allow}"
[ -d "$KIT/plugin/skills" ] || { echo "plugin não encontrado em $KIT"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 ausente"; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lint-instrucoes.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

MOTOR="$TMP/motor.py"
cat > "$MOTOR" <<'PY'
import filecmp, glob, os, re, shutil, subprocess, sys, tempfile

repo = os.path.abspath(sys.argv[1])
root = os.path.join(repo, "plugin")
allow_path = sys.argv[2] if len(sys.argv) > 2 else ""
home_real = os.path.realpath(os.path.expanduser("~"))

ALVOS = ("skills/*/SKILL.md", "skills/*/references/*.md", "templates/CLAUDE*.md", "templates/subagentes.md")
PREF_KIT = ("skills/", "references/", "hooks/", "templates/", "agents/", "commands/", "workflows/")
PREF_AMBIGUO = ("scripts/", "docs/")
# ~/.claude/… que o kit não instala mas é da máquina ou do próprio Claude Code: não reprova.
DA_MAQUINA = ("CLAUDE.md", "CLAUDE.kit.md", "settings.json", "settings.local.json", ".keep-local",
              "projects", "backup-agents-md", "plans", "todos", "statsig", "ide")
DO_PLUGIN = ("skills/", "hooks/", "agents/", "commands/")
PLUGIN_ROOT = re.compile(r"^\$\{?CLAUDE_PLUGIN_ROOT\}?/")
R3 = re.compile(r"voltou a|voltaram a|não existe mais|agora (é|usa|mede|exige|faz)"
                r"|desde (a )?0\.[0-9]+|a partir da 0\.[0-9]+|(antes|antigamente) (era|fazia)", re.I)
VERBO = r"(chame|chama|chamar|acione|aciona|acionar|use|usa|usar|invoque|invoca|invocar|carregue|carrega|carregar|dispare|dispara|disparar)"

achados = []  # (regra, arquivo relativo ao repo, linha, texto da linha, mensagem)

def existe(rel):
    return os.path.exists(os.path.join(root, rel.rstrip("/")))

def pasta_skill(rel):
    p = rel.split("/")
    return "/".join(p[:2]) if p[0] == "skills" and len(p) > 2 else None

alvos = []
for pat in ALVOS:
    alvos += sorted(glob.glob(os.path.join(root, pat)))

skills = {os.path.basename(os.path.dirname(f)) for f in glob.glob(os.path.join(root, "skills/*/SKILL.md"))}
so_slash = set()
for nome in skills:
    txt = open(os.path.join(root, "skills", nome, "SKILL.md"), encoding="utf-8").read()
    fm = txt.split("---", 2)[1] if txt.startswith("---") else ""
    if re.search(r"^disable-model-invocation:\s*true\s*$", fm, re.M):
        so_slash.add(nome)

# Um kit-setup.sh num HOME descartável serve à R1 (o que existe em ~/.claude) e à R4.
setup = os.path.join(root, "scripts", "kit-setup.sh")
home = None
setup_rc = None
if os.path.isfile(setup):
    home = tempfile.mkdtemp(prefix="lint-home.")
    if os.path.realpath(home) == home_real or not os.path.realpath(home).startswith(os.path.realpath(tempfile.gettempdir())):
        sys.exit("GUARDA: HOME do kit-setup fora do temporário — abortando")
    env = dict(os.environ, HOME=home)
    env.pop("CLAUDE_CONFIG_DIR", None)
    try:
        setup_rc = subprocess.run(["bash", setup], env=env, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, timeout=300).returncode
    except subprocess.TimeoutExpired:
        shutil.rmtree(home, ignore_errors=True)
        sys.exit("kit-setup.sh passou de 300s no HOME descartável")
instalado = os.path.join(home, ".claude") if home else None

def r1_home(t, tok):
    if t == "" or t.split("/")[0].rstrip("/") in DA_MAQUINA or t.startswith("backup-kit-"):
        return None
    if t.startswith(DO_PLUGIN):
        partes = t.split("/")
        if partes[0] == "skills" and (len(partes) < 2 or partes[1] not in skills):
            return None  # ~/.claude/skills/ genérico: as skills da própria pessoa
        return tok + " não existe: " + partes[0] + " do kit vem pelo plugin (${CLAUDE_PLUGIN_ROOT}/" + t + ")"
    if instalado is None:
        return None
    if os.path.exists(os.path.join(instalado, t.rstrip("/"))):
        return None
    if t.startswith(("scripts/", "workflows/")) or ("/" not in t and t.lower().endswith(".md")):
        return "o kit-setup.sh não instala " + tok
    return None

def r1_token(tok, sd):
    if tok.startswith("~/.claude/"):
        return r1_home(tok[len("~/.claude/"):], tok)
    if tok.startswith("plugin/"):
        return None if existe(tok[len("plugin/"):]) else "caminho do kit que não existe: " + tok
    cand = [tok] + ([sd + "/" + tok] if sd else [])
    if tok.startswith(PREF_KIT):
        return None if any(existe(c) for c in cand) else "caminho do kit que não existe: " + tok
    primeiro = tok.split("/")[0]
    if "/" in tok and primeiro in skills:
        return None if existe("skills/" + tok) else "caminho do kit que não existe: " + tok
    if tok.startswith(PREF_AMBIGUO):
        if any(existe(c) for c in cand):
            return None
        pai = os.path.dirname(tok.rstrip("/"))
        if (sd and existe(sd + "/" + primeiro)) or (pai != primeiro and existe(pai)):
            return "caminho do kit que não existe: " + tok
    return None

for f in alvos:
    rel = os.path.relpath(f, root)
    rel_repo = "plugin/" + rel
    sd = pasta_skill(rel)
    cerca = False
    for n, linha in enumerate(open(f, encoding="utf-8"), 1):
        texto = linha.rstrip("\n")
        if R3.search(texto):
            achados.append(("R3", rel_repo, n, texto, "frase relativa a versão ou tempo: " + R3.search(texto).group(0)))
        for nome in so_slash:
            q = re.escape(nome)
            if (re.search(VERBO + r"\s+(a\s+)?skill\s+`?" + q + r"\b", texto, re.I)
                    or re.search(r"Skill\(\s*[\"']?" + q + r"\b", texto)
                    or (re.search(r"(tool|ferramenta)\s+Skill\b", texto)
                        and re.search(r"(?<![/\w:-])`?" + q + r"\b", texto))):
                achados.append(("R2", rel_repo, n, texto, f"skill só-slash citada como chamável: {nome} (use `/{nome}`)"))
        if texto.lstrip().startswith("```"):
            cerca = not cerca
            continue
        trechos = [texto] if cerca else re.findall(r"`([^`]+)`", texto)
        for tr in trechos:
            for tok in tr.split():
                tok = tok.strip("\"'(),;:")
                tok = PLUGIN_ROOT.sub("plugin/", tok)
                tok = re.sub(r":[\d,-]+$", "", tok).rstrip(".")
                if not tok or re.search(r"[<>*?\[\]{}$…]", tok):
                    continue
                msg = r1_token(tok, sd)
                if msg:
                    achados.append(("R1", rel_repo, n, texto, msg))

def regra4():
    if home is None:
        return
    s = "plugin/scripts/kit-setup.sh"
    if setup_rc != 0:
        achados.append(("R4", s, 0, "", f"o kit-setup.sh saiu {setup_rc}: destino não conferido"))
    cd = instalado
    for nome in (os.listdir(cd) if os.path.isdir(cd) else []):
        if nome.lower() == "agents.md":
            achados.append(("R4", s, 0, "", f"instala ~/.claude/{nome}, que o Claude Code lê como AGENTS.md em toda sessão"))
    for nome in os.listdir(home):
        if nome.lower() in ("agents.md", "claude.md"):
            achados.append(("R4", s, 0, "", f"instala ~/{nome}"))
    destino = os.path.join(cd, "CLAUDE.md")
    tpl = os.path.join(root, "templates", "CLAUDE-global.md")
    if not os.path.isfile(destino):
        achados.append(("R4", s, 0, "", "não instala ~/.claude/CLAUDE.md"))
    elif not os.path.isfile(tpl) or not filecmp.cmp(destino, tpl, shallow=False):
        achados.append(("R4", s, 0, "", "~/.claude/CLAUDE.md não é o plugin/templates/CLAUDE-global.md"))

try:
    regra4()
finally:
    if home:
        shutil.rmtree(home, ignore_errors=True)

entradas = []
if allow_path and os.path.isfile(allow_path):
    for n, linha in enumerate(open(allow_path, encoding="utf-8"), 1):
        linha = linha.rstrip("\n")
        if not linha.strip() or linha.lstrip().startswith("#"):
            continue
        campos = [c.strip() for c in linha.split(" :: ")]
        if len(campos) != 4 or not all(campos):
            print(f"ALLOW {os.path.basename(allow_path)}:{n}: linha fora do formato <regra> :: <arquivo> :: <trecho> :: <motivo>")
            entradas.append(None)
            continue
        entradas.append((n, campos, [0]))

falhas = sum(1 for e in entradas if e is None)
for regra, arq, n, texto, msg in achados:
    coberto = False
    for e in entradas:
        if e and e[1][0] == regra and e[1][1] == arq and e[1][2] in texto:
            e[2][0] += 1
            coberto = True
    if not coberto:
        print(f"{regra} {arq}:{n}: {msg}")
        falhas += 1
for e in entradas:
    if e and e[2][0] == 0:
        print(f"ALLOW {os.path.basename(allow_path)}:{e[0]}: entrada órfã, não casa com nada: {' :: '.join(e[1][:3])}")
        falhas += 1
sys.exit(1 if falhas else 0)
PY

lint() { python3 "$MOTOR" "$@"; }

falhas=0
ok()    { printf '  ok    %s\n' "$1"; }
falha() { printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); }

# kit <nome>: repo mínimo com plugin/, uma skill `base` e um kit-setup.sh que instala o
# template; a fixture põe o que precisar em cima.
kit() {
  local k="$TMP/$1" p="$TMP/$1/plugin"
  mkdir -p "$p/skills/base/references" "$p/scripts" "$p/templates"
  printf -- '---\nname: base\ndescription: skill de fixture\n---\n\nVeja `references/ok.md`.\n' > "$p/skills/base/SKILL.md"
  echo "# ok" > "$p/skills/base/references/ok.md"
  echo "# comum" > "$p/templates/CLAUDE-global.md"
  : > "$p/scripts/ok.sh"
  instalador "$k" ''
  printf '%s' "$k"
}
instalador() { # instalador <kit> <corpo extra>: kit-setup.sh de fixture
  cat > "$1/plugin/scripts/kit-setup.sh" <<SH
#!/usr/bin/env bash
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
mkdir -p "\$HOME/.claude/scripts"
cp "\$R/templates/CLAUDE-global.md" "\$HOME/.claude/CLAUDE.md"
cp "\$R/scripts/ok.sh" "\$HOME/.claude/scripts/ok.sh"
$2
SH
}
dispara()    { local s; s="$(lint "$2" "${3:-}")" && falha "$1 (não disparou)" || { printf '%s\n' "$s" | grep -q "^$4 " && ok "$1" || falha "$1 (disparou outra coisa: $s)"; }; }
nao_dispara() { local s; s="$(lint "$2" "${3:-}")" && ok "$1" || falha "$1 (disparou: $s)"; }

echo "== R1 caminho citado que não existe =="
k="$(kit r1-sim)"
printf 'Os critérios estão em `references/criterios.md`.\n' >> "$k/plugin/skills/base/SKILL.md"
dispara "reference que não existe na pasta da skill" "$k" "" R1
k="$(kit r1-sim-home)"
printf 'Rode `bash ~/.claude/scripts/sumiu.sh`.\n' >> "$k/plugin/skills/base/SKILL.md"
dispara "~/.claude/scripts/ que o kit-setup.sh não instala" "$k" "" R1
k="$(kit r1-sim-agents)"
printf 'As regras ficam em `~/.claude/agents.md`.\n' > "$k/plugin/templates/subagentes.md"
dispara "~/.claude/agents.md, que o kit-setup.sh não instala" "$k" "" R1
k="$(kit r1-sim-skill-home)"
printf 'Rode `bash ~/.claude/skills/base/scripts/ok.sh`.\n' >> "$k/plugin/skills/base/SKILL.md"
dispara "~/.claude/skills/<skill do kit>: vem pelo plugin" "$k" "" R1
k="$(kit r1-sim-cerca)"
printf '```bash\nbash "${CLAUDE_PLUGIN_ROOT}/skills/base/scripts/sumiu.sh"\n```\n' >> "$k/plugin/skills/base/SKILL.md"
dispara "\${CLAUDE_PLUGIN_ROOT} em bloco cercado" "$k" "" R1
k="$(kit r1-sim-skill)"
printf 'Checklist em `base/references/sumiu.md`.\n' > "$k/plugin/templates/subagentes.md"
dispara "<skill>/references/ que não existe" "$k" "" R1
k="$(kit r1-nao)"
cat >> "$k/plugin/skills/base/SKILL.md" <<'MD'
Rode `bash ~/.claude/scripts/ok.sh`, leia `skills/base/references/ok.md` e `base/references/ok.md`.
Rode `bash "${CLAUDE_PLUGIN_ROOT}/scripts/ok.sh"` e `bash $CLAUDE_PLUGIN_ROOT/scripts/ok.sh`.
Placeholder `scripts/<nome>.sh`, glob `skills/*/SKILL.md`, linha `references/ok.md:12`.
O relatório vai para `docs/security-audit/` e o gate é `node scripts/run-pgtap.cjs` — do projeto.
O `~/.claude/CLAUDE.md` é seu, a memória fica em `~/.claude/projects/` e as suas skills em `~/.claude/skills/`.
MD
nao_dispara "caminho que existe, \${CLAUDE_PLUGIN_ROOT}, placeholder, glob e caminho de projeto" "$k"

echo "== R2 skill só-slash citada como chamável =="
k="$(kit r2-sim)"
mkdir -p "$k/plugin/skills/manual"
printf -- '---\nname: manual\ndescription: x\ndisable-model-invocation: true\n---\n' > "$k/plugin/skills/manual/SKILL.md"
printf 'Plano grande? Chame a skill `manual` antes de codar.\n' >> "$k/plugin/skills/base/SKILL.md"
dispara "\"chame a skill manual\"" "$k" "" R2
k="$(kit r2-sim-tool)"
mkdir -p "$k/plugin/skills/manual"
printf -- '---\nname: manual\ndescription: x\ndisable-model-invocation: true\n---\n' > "$k/plugin/skills/manual/SKILL.md"
printf 'Acione `manual` pela tool Skill.\n' >> "$k/plugin/skills/base/SKILL.md"
dispara "\"pela tool Skill\"" "$k" "" R2
k="$(kit r2-nao)"
mkdir -p "$k/plugin/skills/manual" "$k/plugin/skills/livre"
printf -- '---\nname: manual\ndescription: x\ndisable-model-invocation: true\n---\n' > "$k/plugin/skills/manual/SKILL.md"
printf -- '---\nname: livre\ndescription: x\n---\n' > "$k/plugin/skills/livre/SKILL.md"
printf 'Chame por `/manual` ou `/kit-vamoo:manual` pela tool Skill. Use a skill `livre` quando precisar.\n' >> "$k/plugin/skills/base/SKILL.md"
nao_dispara "forma /x, /kit-vamoo:x e skill que o modelo pode chamar" "$k"

echo "== R3 frase relativa a versão ou tempo =="
k="$(kit r3-sim)"
printf '`gh -q` voltaram a aparecer em sessões reais na 2.1.277 e na 2.1.278\n' >> "$k/plugin/skills/base/SKILL.md"
dispara "\"voltaram a\"" "$k" "" R3
k="$(kit r3-sim-versao)"
printf 'O hook bloqueia desde a 0.40 e a statusline agora mede tokens.\n' > "$k/plugin/templates/CLAUDE-global.md"
instalador "$k" ''
dispara "\"desde a 0.x\" e \"agora mede\"" "$k" "" R3
k="$(kit r3-nao)"
printf 'Medido na 2.1.259 (03/09/2026). A statusline mede tokens reais do último turno.\n' >> "$k/plugin/skills/base/SKILL.md"
nao_dispara "versão e data como fato datado" "$k"

echo "== R4 arquivo de instrução no lugar errado =="
k="$(kit r4-sim-agents)"; instalador "$k" 'echo regras > "$HOME/.claude/Agents.md"'
dispara "~/.claude/Agents.md (caixa mista)" "$k" "" R4
k="$(kit r4-sim-home)"; instalador "$k" 'echo regras > "$HOME/CLAUDE.md"'
dispara "~/CLAUDE.md" "$k" "" R4
k="$(kit r4-sim-tpl)"; instalador "$k" 'echo outro > "$HOME/.claude/CLAUDE.md"'
dispara "~/.claude/CLAUDE.md que não é o CLAUDE-global.md" "$k" "" R4
k="$(kit r4-sim-exit)"; instalador "$k" 'exit 3'
dispara "kit-setup.sh que sai com erro" "$k" "" R4
k="$(kit r4-nao)"; instalador "$k" 'echo "# sub" > "$HOME/.claude/subagentes.md"'
nao_dispara "CLAUDE.md do template e subagentes.md em ~/.claude" "$k"

echo "== allowlist =="
k="$(kit allow)"
printf 'O intervalo voltou a caber.\n' >> "$k/plugin/skills/base/SKILL.md"
printf '# comentário\nR3 :: plugin/skills/base/SKILL.md :: intervalo voltou a caber :: estado do host, não versão do kit\n' > "$TMP/lista-ok"
nao_dispara "entrada com motivo suprime o achado" "$k" "$TMP/lista-ok"
printf 'R3 :: plugin/skills/base/SKILL.md :: frase que sumiu :: motivo\n' > "$TMP/lista-orfa"
k="$(kit allow-orfa)"
dispara "entrada órfã reprova" "$k" "$TMP/lista-orfa" ALLOW
printf 'R3 :: plugin/skills/base/SKILL.md :: voltou a caber\n' > "$TMP/lista-sem-motivo"
dispara "entrada sem motivo reprova" "$k" "$TMP/lista-sem-motivo" ALLOW

echo "== $KIT =="
[ -f "$KIT/plugin/scripts/kit-setup.sh" ] || falha "sem plugin/scripts/kit-setup.sh: a R4 não teria o que rodar"
if s="$(lint "$KIT" "$ALLOW")"; then
  ok "nenhum achado fora da allowlist ($(grep -cE '^R[0-9] :: ' "$ALLOW" 2>/dev/null) exceções com motivo)"
else
  falha "o texto que o modelo lê tem achados"
  printf '%s\n' "$s" | sed 's/^/        → /'
fi

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
