#!/usr/bin/env python3
"""Gate de migration para o CI do projeto: o que a RLS não segura, pego antes do merge.

Copie este arquivo e o raizes.sh da baseline para a mesma pasta do projeto (os dois juntos:
o CI não tem o plugin):

    cp "${CLAUDE_PLUGIN_ROOT}/templates/gate-migration/check-migration.py" scripts/
    cp "${CLAUDE_PLUGIN_ROOT}/skills/baseline/scripts/raizes.sh" scripts/

O que reprova, por arquivo de migration lido inteiro (statement em várias linhas conta igual):
  1. CREATE TABLE em public (ou sem schema, que cai em public) sem
     ALTER TABLE ... ENABLE ROW LEVEL SECURITY da mesma tabela no mesmo arquivo;
  2. CREATE FUNCTION/PROCEDURE ... SECURITY DEFINER sem SET search_path na própria
     definição ou num ALTER FUNCTION ... SET search_path do mesmo arquivo;
  3. CREATE VIEW / MATERIALIZED VIEW em public que roda como o dono (sem
     security_invoker, no WITH ou num ALTER VIEW ... SET) e não é revogada de anon no
     mesmo arquivo. View do dono não passa pela RLS. security_invoker não é o conserto
     automático: sem a policy equivalente nas tabelas, ele zera o dado de todo mundo;
  4. GRANT de INSERT, UPDATE, DELETE, TRUNCATE ou ALL para anon;
  5. só com --gates: SECURITY DEFINER que anon ou authenticated executam (não revogada de
     public, anon E authenticated no mesmo arquivo) e cujo corpo não chama nenhuma das
     funções de papel listadas. auth.uid() is null não é gate de papel. Sem --gates, o
     gate não sabe quais são as funções de papel do projeto e imprime "não medido".
Comentário e string não satisfazem regra nenhuma; o corpo de função ($$ ... $$) só conta
na regra 5. O set_config('search_path') dentro do corpo não fixa o search_path da chamada.

Exceção de propósito leva, no próprio arquivo, uma linha com o motivo (sem motivo não vale):
    -- gate-migration: sem-rls public.<tabela> <motivo>        regra 1
    -- gate-migration: anon public.<view> <motivo>             regra 3
    -- gate-migration: anon-escreve public.<objeto> <motivo>   regra 4
    -- gate-migration: definer public.<funcao> <motivo>        regra 5

Uso:
    check-migration.py                     # toda pasta de migration que o raizes.sh achar
    check-migration.py --desde origin/main # só as migrations ADICIONADAS desde o ref (legado não trava)
    check-migration.py a.sql b.sql         # só estes arquivos
    check-migration.py --gates eh_gestor,tem_papel   # liga a regra 5

No CI (GitHub Actions, checkout com fetch-depth: 0):
    - run: python3 scripts/check-migration.py --desde "origin/${{ github.base_ref }}"
      if: github.event_name == 'pull_request'

Exit: 0 passou · 1 reprovou · 2 não mediu (sem raizes.sh, sem pasta de migration, ref
inválido). Não medido nunca é verde.

Só lê arquivos e o git local. Sem rede, sem banco.
"""
import os
import re
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))


def nao_medido(msg):
    print(f"NÃO MEDIDO: {msg}")
    sys.exit(2)


def acha_raizes(explicito):
    for c in (explicito, os.path.join(AQUI, "raizes.sh"),
              os.path.join(os.environ.get("CLAUDE_PLUGIN_ROOT", ""), "skills/baseline/scripts/raizes.sh")):
        if c and os.path.isfile(c):
            return c
    return None


def pastas_de_migration(raizes):
    out = subprocess.run(["bash", raizes, "--root", "."], capture_output=True, text=True).stdout
    return [l.split("\t")[1] for l in out.splitlines() if l.startswith("MIGRATIONS\t")]


def mascara(sql):
    """Devolve (mascarado, so_corpo), os dois do tamanho de sql e com as quebras de linha no
    lugar. No mascarado, comentário, string e dollar-quote viram espaço, e identificador entre
    aspas volta sem as aspas ("public"."x" é nome). No so_corpo, só o que está dentro de
    dollar-quote sobrevive, sem os comentários de dentro dele."""
    out, corpo, i, n = [], [], 0, len(sql)
    branco = lambda s: re.sub(r"[^\n]", " ", s)
    while i < n:
        c = sql[i]
        if sql.startswith("--", i) or sql.startswith("/*", i):
            j = (sql.find("\n", i) if c == "-" else sql.find("*/", i + 2))
            j = n if j < 0 else (j if c == "-" else j + 2)
            out.append(branco(sql[i:j])); corpo.append(branco(sql[i:j])); i = j
        elif c == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'" and j + 1 < n and sql[j + 1] == "'":
                    j += 2; continue
                if sql[j] == "'":
                    break
                j += 1
            out.append(branco(sql[i:j + 1])); corpo.append(branco(sql[i:j + 1])); i = j + 1
        elif c == '"':
            j = sql.find('"', i + 1)
            j = n - 1 if j < 0 else j
            out.append(" " + sql[i + 1:j].lower() + " "); corpo.append(branco(sql[i:j + 1])); i = j + 1
        elif c == "$" and re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$", sql[i:]):
            tag = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$", sql[i:]).group(0)
            j = sql.find(tag, i + len(tag))
            j = n if j < 0 else j + len(tag)
            dentro = re.sub(r"--[^\n]*", lambda m: branco(m.group(0)), sql[i:j])
            out.append(branco(sql[i:j])); corpo.append(dentro); i = j
        else:
            out.append(c); corpo.append(" " if c != "\n" else c); i += 1
    return "".join(out), "".join(corpo)


def statements(mascarado):
    """Parte no ';' de topo e devolve (linha_inicial, texto_normalizado, inicio, fim)."""
    res, ini = [], 0
    for m in re.finditer(r";|$", mascarado):
        bloco = mascarado[ini:m.start()]
        if bloco.strip():
            pre = len(bloco) - len(bloco.lstrip())
            linha = mascarado.count("\n", 0, ini + pre) + 1
            res.append((linha, " ".join(bloco.split()).lower(), ini, m.start()))
        ini = m.end()
        if m.start() == len(mascarado):
            break
    return res


NOME = r"((?:[a-z_][a-z0-9_$]*\s*\.\s*)?[a-z_][a-z0-9_$]*)"
RE_CREATE = re.compile(r"^create\s+(?:(?:global|local)\s+)?(temp\s+|temporary\s+)?(?:unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?" + NOME)
RE_ENABLE = re.compile(r"^alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?" + NOME + r"\s+.*\benable\s+row\s+level\s+security\b")
RE_FUNC = re.compile(r"^create\s+(?:or\s+replace\s+)?(?:function|procedure)\s+" + NOME)
RE_ALTER_FN = re.compile(r"^alter\s+(?:function|procedure)\s+" + NOME + r".*\bset\s+search_path\b")
RE_VIEW = re.compile(r"^create\s+(?:or\s+replace\s+)?(?:(?:temp|temporary)\s+()|(?:recursive\s+)?)(materialized\s+)?view\s+(?:if\s+not\s+exists\s+)?" + NOME)
RE_ALTER_VIEW_INV = re.compile(r"^alter\s+view\s+(?:if\s+exists\s+)?" + NOME + r"\s+set\s*\(.*\bsecurity_invoker\s*(?:=\s*)?(?:true|on|1)\b")
RE_REVOKE = re.compile(r"^revoke\s+(?:grant\s+option\s+for\s+)?(.*?)\s+on\s+(.*?)\s+from\s+(.*?)(?:\s+(?:cascade|restrict|granted\s+by\s+.*))?$")
RE_GRANT = re.compile(r"^grant\s+(.*?)\s+on\s+(.*?)\s+to\s+(.*?)(?:\s+with\s+grant\s+option)?(?:\s+granted\s+by\s+.*)?$")
RE_MARCA = re.compile(r"--\s*gate-migration:\s*(sem-rls|anon-escreve|anon|definer)\s+(\S+)[ \t]*(.*)$", re.M | re.I)
ESCRITA = re.compile(r"\b(insert|update|delete|truncate|all)\b")


def qualifica(nome):
    nome = re.sub(r"\s+", "", nome)
    return nome if "." in nome else "public." + nome


def papeis(txt):
    return {p.strip() for p in re.split(r",", txt.replace("group ", ""))}


def objetos(alvo):
    """Nomes de objeto de um 'on ...' de GRANT/REVOKE; tira o tipo e a assinatura."""
    alvo = re.sub(r"^(table|function|procedure|routine|sequence)\s+", "", alvo)
    alvo = re.sub(r"\([^)]*\)", "", alvo)
    return {qualifica(a) for a in alvo.split(",") if a.strip() and not a.strip().startswith("all ")}


def julga(caminho, gates):
    try:
        with open(caminho, encoding="utf-8", errors="replace") as f:
            bruto = f.read()
    except OSError as e:
        return [f"{caminho}: não li ({e})"], 0
    marcas = {}
    for m in RE_MARCA.finditer(bruto):
        if m.group(3).strip():
            marcas.setdefault(m.group(1).lower(), set()).add(qualifica(m.group(2).lower()))
    marcada = lambda tipo, obj: obj in marcas.get(tipo, set())
    mascarado, so_corpo = mascara(bruto)
    tabelas, com_rls, funcoes, fn_com_sp = [], set(), [], set()
    views, view_inv, revogado, erros = [], set(), {}, []
    for linha, st, ini, fim in statements(mascarado):
        m = RE_CREATE.match(st)
        if m:
            if not m.group(1):  # temp não é tabela da API
                tabelas.append((linha, qualifica(m.group(2))))
            continue
        m = RE_ENABLE.match(st)
        if m:
            com_rls.add(qualifica(m.group(1))); continue
        m = RE_VIEW.match(st)
        if m:
            if m.group(1) is None:  # temp view fica de fora
                v = qualifica(m.group(3))
                inv = bool(re.search(r"\bwith\s*\(.*\bsecurity_invoker\s*(?:=\s*)?(?:true|on|1)\b", st.split(" as ")[0]))
                views.append((linha, v, bool(m.group(2)), inv))
            continue
        m = RE_ALTER_VIEW_INV.match(st)
        if m:
            view_inv.add(qualifica(m.group(1))); continue
        m = RE_FUNC.match(st)
        if m:
            if re.search(r"\bsecurity\s+definer\b", st):
                funcoes.append((linha, qualifica(m.group(1)), bool(re.search(r"\bset\s+search_path\b", st)),
                                so_corpo[ini:fim]))
            continue
        m = RE_ALTER_FN.match(st)
        if m:
            fn_com_sp.add(qualifica(m.group(1))); continue
        m = RE_REVOKE.match(st)
        if m:
            for o in objetos(m.group(2)):
                revogado.setdefault(o, set()).update(papeis(m.group(3)))
            continue
        m = RE_GRANT.match(st)
        if m and "anon" in papeis(m.group(3)) and ESCRITA.search(m.group(1)):
            objs = objetos(m.group(2)) or {m.group(2)}
            if not any(marcada("anon-escreve", o) for o in objs):
                erros.append(f"{caminho}:{linha}: GRANT de escrita ({m.group(1)}) para anon em {', '.join(sorted(objs))}: o navegador escreve sem login")

    for linha, t in tabelas:
        if t.startswith("public.") and t not in com_rls and not marcada("sem-rls", t):
            erros.append(f"{caminho}:{linha}: CREATE TABLE {t} sem ALTER TABLE {t} ENABLE ROW LEVEL SECURITY no mesmo arquivo")
    for linha, v, mat, inv in views:
        if not v.startswith("public.") or inv or v in view_inv or "anon" in revogado.get(v, set()) or marcada("anon", v):
            continue
        tipo = "materialized view" if mat else "view"
        erros.append(f"{caminho}:{linha}: {tipo} {v} roda como o dono (não passa pela RLS) e anon não foi revogado: "
                     f"revoke all on {v} from anon, ou marque o motivo (security_invoker só com a policy equivalente nas tabelas)")
    sem_medir = 0
    for linha, fn, tem_sp, corpo in funcoes:
        if not tem_sp and fn not in fn_com_sp:
            erros.append(f"{caminho}:{linha}: função {fn} SECURITY DEFINER sem SET search_path (fixe search_path = '' e qualifique os nomes)")
        if {"public", "anon", "authenticated"} <= revogado.get(fn, set()) or marcada("definer", fn):
            continue
        if not gates:
            sem_medir += 1; continue
        if not any(re.search(r"\b" + re.escape(g) + r"\s*\(", corpo, re.I) for g in gates):
            erros.append(f"{caminho}:{linha}: função {fn} SECURITY DEFINER executável pelo navegador e o corpo não chama "
                         f"nenhum gate de papel ({', '.join(gates)}): revogue de public, anon e authenticated, chame o gate ou marque o motivo")
    return erros, sem_medir


def main(argv):
    raizes_arg, desde, arquivos, gates = None, None, [], []
    it = iter(argv)
    for a in it:
        if a == "--raizes":
            raizes_arg = next(it, None)
        elif a == "--desde":
            desde = next(it, None)
            if not desde:
                nao_medido("--desde sem ref")
        elif a == "--gates":
            gates = [g.strip().split(".")[-1] for g in (next(it, None) or "").split(",") if g.strip()]
        elif a in ("-h", "--help"):
            print(__doc__); return 0
        elif a.startswith("-"):
            print(f"argumento desconhecido: {a}", file=sys.stderr); return 2
        else:
            arquivos.append(a)

    if not arquivos:
        raizes = acha_raizes(raizes_arg)
        if not raizes:
            nao_medido("raizes.sh não está ao lado deste script (copie os dois) nem em --raizes")
        pastas = pastas_de_migration(raizes)
        if not pastas:
            nao_medido("nenhuma pasta de migration achada pelo raizes.sh (migrations/, sql/ ou schemas/ com .sql)")
        if desde:
            r = subprocess.run(["git", "-c", "core.quotePath=false", "diff", "--relative", "--name-only", "--diff-filter=A",
                                f"{desde}...HEAD", "--", *pastas], capture_output=True, text=True)
            if r.returncode != 0:
                nao_medido(f"git diff contra {desde} falhou: {r.stderr.strip()}")
            novos = [l for l in r.stdout.splitlines() if l.endswith(".sql")]
            arquivos = [l for l in novos if os.path.dirname(l) in pastas]
            if not arquivos:
                print(f"ok: nenhuma migration nova desde {desde} em {', '.join(pastas)}")
                return 0
        else:
            for p in pastas:
                arquivos += sorted(os.path.join(p, f) for f in os.listdir(p) if f.endswith(".sql"))
            arquivos = [a[2:] if a.startswith("./") else a for a in arquivos]

    erros, sem_medir = [], 0
    for a in arquivos:
        e, s = julga(a, gates)
        erros += e; sem_medir += s
    for e in erros:
        print(f"REPROVA {e}")
    if sem_medir:
        print(f"corpo de SECURITY DEFINER: não medido em {sem_medir} função(ões) (passe --gates com as funções de papel do projeto)")
    print(f"{'reprovou' if erros else 'ok'}: {len(arquivos)} arquivo(s) lido(s), {len(erros)} problema(s)")
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
