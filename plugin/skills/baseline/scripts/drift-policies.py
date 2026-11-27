#!/usr/bin/env python3
"""baseline · drift-policies — policy viva × última definição dela nas migrations.

Por que existe: num pentest de 11/2026 a matriz local, montada pelas migrations, não reproduziu
uma leitura que o pentest mediu em produção. O banco tinha policy que o repositório não
explicava: o dashboard muda policy sem migration, e a versão em schema_migrations bate mesmo
assim (02-banco.md, "Drift entre migrations e banco").

Não conecta em banco. A lista viva vem de um TSV que você gera com a URL só de leitura:

    psql "$SUPABASE_DB_URL_RO" -XAt -F $'\\t' -c "select schemaname, tablename, policyname, cmd, permissive, roles::text, coalesce(qual,''), coalesce(with_check,'') from pg_policies where schemaname = 'public'" > /tmp/vivas.tsv

    drift-policies.py --vivas /tmp/vivas.tsv [--root DIR] [pasta-de-migration ...]

Sem pasta, usa as que o raizes.sh (ao lado deste script) achar. Lê as migrations em ordem de
nome e aplica CREATE POLICY, ALTER POLICY (RENAME, TO, USING, WITH CHECK), DROP POLICY e
DROP TABLE: vale a última definição.

Saída, uma linha por divergência (TSV): tipo, tabela, policy, detalhe.
  VIVA_SEM_REPO     no banco e em nenhuma migration: aplicada à mão. É o achado principal
  REPO_SEM_VIVA     na migration e não no banco: migration não aplicada ou policy apagada à mão
  COMANDO_DIFERE    FOR select/insert/update/delete/all diferente
  PAPEL_DIFERE      TO diferente
  TIPO_DIFERE       PERMISSIVE × RESTRICTIVE
  EXPRESSAO_DIFERE  USING ou WITH CHECK diferente depois de normalizar (sem espaço, parênteses,
                    aspas e casts ::tipo, que o Postgres acrescenta ao guardar). Confira à mão:
                    o deparse pode reescrever o que é igual
Exit: 0 bate · 1 divergiu · 2 não mediu (sem --vivas, TSV vazio, sem pasta de migration).
"""
import os
import re
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))


def nao_medido(msg):
    print(f"NÃO MEDIDO: {msg}")
    sys.exit(2)


def sem_comentario(sql):
    """Tira comentário; string, identificador entre aspas e dollar-quote ficam."""
    out, i, n = [], 0, len(sql)
    while i < n:
        c = sql[i]
        if sql.startswith("--", i):
            j = sql.find("\n", i); i = n if j < 0 else j
        elif sql.startswith("/*", i):
            j = sql.find("*/", i + 2); i = n if j < 0 else j + 2
        elif c in "'\"":
            j = i + 1
            while j < n and not (sql[j] == c and not (j + 1 < n and sql[j + 1] == c)):
                j += 2 if sql[j] == c else 1
            out.append(sql[i:j + 1]); i = j + 1
        elif c == "$" and re.match(r"\$([A-Za-z_]\w*)?\$", sql[i:]):
            tag = re.match(r"\$([A-Za-z_]\w*)?\$", sql[i:]).group(0)
            j = sql.find(tag, i + len(tag)); j = n if j < 0 else j + len(tag)
            out.append(sql[i:j]); i = j
        else:
            out.append(c); i += 1
    return "".join(out)


def topo(st):
    """Posições de cada caractere fora de parênteses, string e aspas (profundidade 0)."""
    prof, i, q, pos = 0, 0, None, []
    while i < len(st):
        c = st[i]
        if q:
            if c == q:
                q = None
        elif c in "'\"":
            q = c
        elif c == "(":
            prof += 1
        elif c == ")":
            prof -= 1
        elif prof == 0:
            pos.append(i)
        i += 1
    return set(pos)


def statements(sql):
    st, ini, prof, q, i = [], 0, 0, None, 0
    while i < len(sql):
        c = sql[i]
        if q:
            if c == q:
                q = None
        elif c in "'\"":
            q = c
        elif c == "$" and re.match(r"\$([A-Za-z_]\w*)?\$", sql[i:]):
            tag = re.match(r"\$([A-Za-z_]\w*)?\$", sql[i:]).group(0)
            j = sql.find(tag, i + len(tag)); i = len(sql) if j < 0 else j + len(tag); continue
        elif c == ";":
            st.append(" ".join(sql[ini:i].split())); ini = i + 1
        i += 1
    st.append(" ".join(sql[ini:].split()))
    return [s for s in st if s]


ID = r'("(?:[^"]|"")+"|[A-Za-z_][\w$]*)'
QID = r'((?:' + ID + r'\s*\.\s*)?' + ID + r')'


def ident(s):
    s = s.strip()
    return s[1:-1].replace('""', '"') if s.startswith('"') else s.lower()


def tabela(s):
    partes = [ident(p) for p in re.findall(ID, s)]
    return partes[-1]  # só public é comparado; o schema já veio filtrado no TSV


def clausula(st, chave):
    """Texto entre parênteses depois de USING / WITH CHECK no nível de topo."""
    livres = topo(st)
    for m in re.finditer(r"\b" + chave + r"\s*\(", st, re.I):
        if m.start() not in livres:
            continue
        ini, prof = m.end(), 1
        for j in range(ini, len(st)):
            if st[j] == "(":
                prof += 1
            elif st[j] == ")":
                prof -= 1
                if prof == 0:
                    return st[ini:j]
    return None


def opcoes(resto, p):
    livres = topo(resto)
    def kw(regex):
        for m in re.finditer(regex, resto, re.I):
            if m.start() in livres:
                return m
    m = kw(r"\bas\s+(permissive|restrictive)\b")
    if m:
        p["tipo"] = m.group(1).upper()
    m = kw(r"\bfor\s+(all|select|insert|update|delete)\b")
    if m:
        p["cmd"] = m.group(1).upper()
    m = kw(r"\bto\s+(.+?)(?=\s+(?:using|with\s+check)\b|$)")
    if m:
        p["papeis"] = ",".join(sorted(ident(x) for x in m.group(1).split(",")))
    u, w = clausula(resto, "using"), clausula(resto, r"with\s+check")
    if u is not None:
        p["using"] = u
    if w is not None:
        p["check"] = w


def aplica(sql, pol):
    for st in statements(sem_comentario(sql)):
        m = re.match(r"create\s+policy\s+" + ID + r"\s+on\s+" + QID + r"(.*)$", st, re.I)
        if m:
            p = {"tipo": "PERMISSIVE", "cmd": "ALL", "papeis": "public", "using": "", "check": ""}
            opcoes(m.group(5), p)
            pol[(tabela(m.group(2)), ident(m.group(1)))] = p
            continue
        m = re.match(r"alter\s+policy\s+" + ID + r"\s+on\s+" + QID + r"\s+rename\s+to\s+" + ID, st, re.I)
        if m:
            k = (tabela(m.group(2)), ident(m.group(1)))
            if k in pol:
                pol[(k[0], ident(m.group(5)))] = pol.pop(k)
            continue
        m = re.match(r"alter\s+policy\s+" + ID + r"\s+on\s+" + QID + r"(.*)$", st, re.I)
        if m:
            k = (tabela(m.group(2)), ident(m.group(1)))
            if k in pol:
                opcoes(m.group(5), pol[k])
            continue
        m = re.match(r"drop\s+policy\s+(?:if\s+exists\s+)?" + ID + r"\s+on\s+" + QID, st, re.I)
        if m:
            pol.pop((tabela(m.group(2)), ident(m.group(1))), None); continue
        m = re.match(r"drop\s+table\s+(?:if\s+exists\s+)?(.+?)(?:\s+(?:cascade|restrict))?$", st, re.I)
        if m:
            for t in m.group(1).split(","):
                alvo = tabela(t)
                for k in [k for k in pol if k[0] == alvo]:
                    del pol[k]


def normaliza(expr):
    e = expr.lower()
    e = re.sub(r"::\s*\"?[a-z_][\w .]*\"?(\[\])?", "", e)
    return re.sub(r"[\s()\"]", "", e)


def main(argv):
    vivas, root, pastas = None, ".", []
    it = iter(argv)
    for a in it:
        if a == "--vivas":
            vivas = next(it, None)
        elif a == "--root":
            root = next(it, ".")
        elif a in ("-h", "--help"):
            print(__doc__); return 0
        elif a.startswith("-"):
            print(f"argumento desconhecido: {a}", file=sys.stderr); return 2
        else:
            pastas.append(a)
    if not vivas or not os.path.isfile(vivas):
        nao_medido("passe --vivas <arquivo.tsv> gerado do pg_policies (o comando está no cabeçalho)")
    os.chdir(root)
    if not pastas:
        out = subprocess.run(["bash", os.path.join(AQUI, "raizes.sh"), "--root", "."],
                             capture_output=True, text=True).stdout
        pastas = [l.split("\t")[1] for l in out.splitlines() if l.startswith("MIGRATIONS\t")]
    if not pastas:
        nao_medido("nenhuma pasta de migration (migrations/, sql/ ou schemas/ com .sql)")

    repo = {}
    for p in pastas:
        for f in sorted(x for x in os.listdir(p) if x.endswith(".sql")):
            with open(os.path.join(p, f), encoding="utf-8", errors="replace") as fh:
                aplica(fh.read(), repo)

    vivo = {}
    with open(vivas, encoding="utf-8", errors="replace") as fh:
        for linha in fh:
            c = linha.rstrip("\n").split("\t")
            if len(c) < 8 or c[0] != "public":
                continue
            papeis = ",".join(sorted(x.strip().strip('"') for x in c[5].strip("{}").split(",") if x.strip()))
            vivo[(c[1], c[2])] = {"cmd": c[3].upper(), "tipo": c[4].upper(), "papeis": papeis or "public",
                                  "using": c[6], "check": c[7]}
    if not vivo:
        nao_medido(f"{vivas} sem nenhuma policy de public (o psql falhou? o filtro de schema está certo?)")

    saida = []
    for k in sorted(set(vivo) | set(repo)):
        v, r = vivo.get(k), repo.get(k)
        if r is None:
            saida.append(("VIVA_SEM_REPO", *k, f"{v['cmd']} to {v['papeis']} using ({v['using']})"))
            continue
        if v is None:
            saida.append(("REPO_SEM_VIVA", *k, f"{r['cmd']} to {r['papeis']}"))
            continue
        for campo, tipo in (("cmd", "COMANDO_DIFERE"), ("papeis", "PAPEL_DIFERE"), ("tipo", "TIPO_DIFERE")):
            if v[campo] != r[campo]:
                saida.append((tipo, *k, f"banco {v[campo]} × repo {r[campo]}"))
        for campo in ("using", "check"):
            if normaliza(v[campo]) != normaliza(r[campo]):
                saida.append(("EXPRESSAO_DIFERE", *k, f"{campo}: banco ({v[campo]}) × repo ({r[campo]})"))
    for s in saida:
        print("\t".join(s))
    print(f"{'divergiu' if saida else 'ok'}: {len(vivo)} policy(s) no banco, {len(repo)} nas migrations de "
          f"{', '.join(pastas)}, {len(saida)} divergência(s)", file=sys.stderr)
    return 1 if saida else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
