#!/usr/bin/env python3
"""Gate de migration para o CI do projeto: tabela em public sem RLS e SECURITY DEFINER sem search_path.

Copie este arquivo e o raizes.sh da baseline para a mesma pasta do projeto (os dois juntos:
o CI não tem o plugin):

    cp "${CLAUDE_PLUGIN_ROOT}/templates/gate-migration/check-migration.py" scripts/
    cp "${CLAUDE_PLUGIN_ROOT}/skills/baseline/scripts/raizes.sh" scripts/

O que reprova, por arquivo de migration lido inteiro (statement em várias linhas conta igual):
  - CREATE TABLE em public (ou sem schema, que cai em public) sem
    ALTER TABLE ... ENABLE ROW LEVEL SECURITY da mesma tabela no mesmo arquivo;
  - CREATE FUNCTION/PROCEDURE ... SECURITY DEFINER sem SET search_path na própria
    definição ou num ALTER FUNCTION ... SET search_path do mesmo arquivo.
Comentário, string e corpo de função ($$ ... $$) não satisfazem regra nenhuma: o
set_config('search_path') dentro do corpo não fixa o search_path da chamada.

Tabela que fica sem RLS de propósito leva, no próprio arquivo, a linha
    -- gate-migration: sem-rls public.<tabela> <motivo>
Sem motivo, a marcação não vale.

Uso:
    check-migration.py                     # toda pasta de migration que o raizes.sh achar
    check-migration.py --desde origin/main # só as migrations ADICIONADAS desde o ref (legado não trava)
    check-migration.py a.sql b.sql         # só estes arquivos

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
    """Troca comentário, string, identificador entre aspas e dollar-quote por espaço (mantém as
    quebras de linha, para o número da linha bater) e devolve o texto mascarado. Identificador
    entre aspas volta sem as aspas, porque "public"."x" é nome, não conteúdo."""
    out, i, n = [], 0, len(sql)
    branco = lambda s: re.sub(r"[^\n]", " ", s)
    while i < n:
        c = sql[i]
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            j = n if j < 0 else j
            out.append(branco(sql[i:j])); i = j
        elif sql.startswith("/*", i):
            j = sql.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(branco(sql[i:j])); i = j
        elif c == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'" and j + 1 < n and sql[j + 1] == "'":
                    j += 2; continue
                if sql[j] == "'":
                    break
                j += 1
            out.append(branco(sql[i:j + 1])); i = j + 1
        elif c == '"':
            j = sql.find('"', i + 1)
            j = n - 1 if j < 0 else j
            out.append(" " + sql[i + 1:j].lower() + " "); i = j + 1
        elif c == "$":
            m = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$", sql[i:])
            if m:
                tag = m.group(0)
                j = sql.find(tag, i + len(tag))
                j = n if j < 0 else j + len(tag)
                out.append(" $corpo$" + branco(sql[i:j])); i = j
            else:
                out.append(c); i += 1
        else:
            out.append(c); i += 1
    return "".join(out)


def statements(mascarado):
    """Parte no ';' de topo (o mascarado não tem ';' dentro de string nem de corpo) e devolve
    (linha_inicial, texto_normalizado)."""
    res, ini = [], 0
    for m in re.finditer(r";|$", mascarado):
        bloco = mascarado[ini:m.start()]
        if bloco.strip():
            pre = len(bloco) - len(bloco.lstrip())
            linha = mascarado.count("\n", 0, ini + pre) + 1
            res.append((linha, " ".join(bloco.split()).lower()))
        ini = m.end()
        if m.start() == len(mascarado):
            break
    return res


NOME = r"((?:[a-z_][a-z0-9_$]*\s*\.\s*)?[a-z_][a-z0-9_$]*)"
RE_CREATE = re.compile(r"^create\s+(?:(?:global|local)\s+)?(temp\s+|temporary\s+)?(?:unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?" + NOME)
RE_ENABLE = re.compile(r"^alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?" + NOME + r"\s+.*\benable\s+row\s+level\s+security\b")
RE_FUNC = re.compile(r"^create\s+(?:or\s+replace\s+)?(?:function|procedure)\s+" + NOME)
RE_ALTER_FN = re.compile(r"^alter\s+(?:function|procedure)\s+" + NOME + r".*\bset\s+search_path\b")
RE_MARCA = re.compile(r"--\s*gate-migration:\s*sem-rls\s+(\S+)[ \t]*(.*)$", re.M | re.I)


def qualifica(nome):
    nome = re.sub(r"\s+", "", nome)
    return nome if "." in nome else "public." + nome


def julga(caminho):
    try:
        with open(caminho, encoding="utf-8", errors="replace") as f:
            bruto = f.read()
    except OSError as e:
        return [f"{caminho}: não li ({e})"]
    marcadas = {qualifica(m.group(1).lower()) for m in RE_MARCA.finditer(bruto) if m.group(2).strip()}
    sts = statements(mascara(bruto))
    tabelas, com_rls, funcoes, fn_com_sp = [], set(), [], set()
    for linha, st in sts:
        m = RE_CREATE.match(st)
        if m:
            if not m.group(1):  # temp não é tabela da API
                tabelas.append((linha, qualifica(m.group(2))))
            continue
        m = RE_ENABLE.match(st)
        if m:
            com_rls.add(qualifica(m.group(1))); continue
        m = RE_FUNC.match(st)
        if m:
            fora_do_corpo = st.replace("$corpo$", " ")
            if re.search(r"\bsecurity\s+definer\b", fora_do_corpo):
                funcoes.append((linha, qualifica(m.group(1)), bool(re.search(r"\bset\s+search_path\b", fora_do_corpo))))
            continue
        m = RE_ALTER_FN.match(st)
        if m:
            fn_com_sp.add(qualifica(m.group(1)))
    erros = []
    for linha, t in tabelas:
        if t.startswith("public.") and t not in com_rls and t not in marcadas:
            erros.append(f"{caminho}:{linha}: CREATE TABLE {t} sem ALTER TABLE {t} ENABLE ROW LEVEL SECURITY no mesmo arquivo")
    for linha, fn, tem_sp in funcoes:
        if not tem_sp and fn not in fn_com_sp:
            erros.append(f"{caminho}:{linha}: função {fn} SECURITY DEFINER sem SET search_path (fixe search_path = '' e qualifique os nomes)")
    return erros


def main(argv):
    raizes_arg, desde, arquivos = None, None, []
    it = iter(argv)
    for a in it:
        if a == "--raizes":
            raizes_arg = next(it, None)
        elif a == "--desde":
            desde = next(it, None)
            if not desde:
                nao_medido("--desde sem ref")
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

    erros = [e for a in arquivos for e in julga(a)]
    for e in erros:
        print(f"REPROVA {e}")
    print(f"{'reprovou' if erros else 'ok'}: {len(arquivos)} arquivo(s) lido(s), {len(erros)} problema(s)")
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
