#!/usr/bin/env python3
"""familias-rpc.py: compara as funções SQL que escrevem na mesma tabela (A3 da auditoria-seguranca).

Num pentest de 11/2026, a checagem vertical (papel) segurou em todos os pontos, mas um usuário
comum conseguiu tomar registro de qualquer colega. Quatro funções escreviam na tabela de
cartões: editar, mover e descartar conferiam o dono, e a de transferir não conferia. Em outra
tabela, três funções de escrita não conferiam a carteira, enquanto a de apagar conferia. Os
dois furos eram uma checagem esquecida numa função, com a checagem certa logo ao lado.

O grep de handlers da A3 não vê esse caso, por três motivos:
  - a função Postgres exposta pelo PostgREST (/rest/v1/rpc/<nome>) é um handler sem rota no
    código do app;
  - um gateway genérico (/api/rpc/[nome]) conta como uma rota e esconde centenas de ações;
  - a checagem que falta só aparece quando se compara a função com as irmãs.

O script lê o estado efetivo das migrations (vale a última definição de cada função, depois
de create, replace e drop, em ordem de nome de arquivo). Agrupa as funções pela tabela em que
escrevem e acusa a função que não confere o chamador quando uma irmã confere.

"Confere o dono" quer dizer: a identidade do chamador (auth.uid(), auth.jwt(), request.jwt ou
uma variável tirada deles) aparece numa condição IF/WHEN ou num WHERE. Também vale chamar um
helper booleano passando um parâmetro da função, como pode_editar(p_id). O chamador só no SET
(`atualizado_por = auth.uid()`) não confere nada, apenas carimba quem fez.

A saída é candidato, não veredito: na auditoria entra como `padrao` (teto 0,60) até alguém
abrir a função. O banco vivo é a autoridade (pg_proc + has_function_privilege). Este script é
o melhor que dá sem ele, e diz isso na cobertura.

Saída em TSV, uma linha por registro:
  MATRIZ     tabela  função  arquivo:linha  dono=sim|nao  helpers=a,b  definer=sim|nao  exposto=sim|nao
  ACHADO     sev     check   arquivo:linha  título        detalhe
  COBERTURA  check   status  motivo

Uso: python3 -I familias-rpc.py [--root DIR]
"""
import os
import re
import sys

ROOT = "."
args = sys.argv[1:]
while args:
    a = args.pop(0)
    if a == "--root" and args:
        ROOT = args.pop(0)
    elif a in ("-h", "--help"):
        print(__doc__)
        sys.exit(0)
    else:
        print(f"argumento desconhecido: {a}", file=sys.stderr)
        sys.exit(2)
if not os.path.isdir(ROOT):
    print(f"root inválido: {ROOT}", file=sys.stderr)
    sys.exit(2)
os.chdir(ROOT)

DIRS = ["supabase/migrations", "migrations", "db/migrations", "database/migrations"]
CALLER = r"auth\s*\.\s*uid\s*\(\s*\)|auth\s*\.\s*jwt\s*\(\s*\)|current_setting\s*\(\s*'request\.jwt"
PREFIXO_HELPER = re.compile(
    r"^(is|eh|e|pode|can|has|tem|check|checa|verifica|assert|exige|require|garante|confere|sou|usuario_pode)_")
ELEVADO = re.compile(r"admin|gest[aã]o|gestor|gerente|manager|supervisor|superuser|staff|plataforma")
NAO_HELPER = {"has_table_privilege", "has_column_privilege", "has_function_privilege",
              "has_schema_privilege"}


def limpa(s):
    return re.sub(r"[\t\r\n]+", " ", str(s)).strip()


def sem_comentario(t):
    t = re.sub(r"--[^\n]*", lambda m: " " * len(m.group(0)), t)
    return re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), t, flags=re.S)


def arquivos():
    vistos = []
    for d in DIRS:
        if os.path.isdir(d):
            for raiz, _, nomes in os.walk(d):
                for n in nomes:
                    # concatenado de migrations não é definição efetiva: leria tudo duas vezes
                    if n.endswith(".sql") and not re.search(r"apply[_-]?all|dump|bundle", n, re.I):
                        vistos.append(os.path.join(raiz, n))
    return sorted(vistos, key=lambda p: (os.path.dirname(p), os.path.basename(p)))


def nome_curto(qual):
    qual = qual.replace('"', "").strip().lower()
    if "." in qual:
        esquema, nome = qual.split(".", 1)
    else:
        esquema, nome = "public", qual
    return esquema, nome


def corpo_de(resto):
    m = re.search(r"\bas\s+(\$[a-z_0-9]*\$)(.*?)\1", resto, re.I | re.S)
    if m:
        return m.group(2), resto[:m.start()] + resto[m.end():m.end() + 400]
    m = re.search(r"\bbegin\s+atomic\b(.*?)\bend\s*;", resto, re.I | re.S)
    if m:
        return m.group(1), resto[:m.start()]
    m = re.search(r"\bas\s+'(.*?)'\s*(;|language)", resto, re.I | re.S)
    if m:
        return m.group(1), resto[:m.start()] + resto[m.end():m.end() + 400]
    return "", resto[:600]


def params_de(assinatura):
    nomes = []
    for p in assinatura.split(","):
        toks = re.findall(r"[a-z_][a-z0-9_]*", p.lower())
        toks = [t for t in toks if t not in ("in", "out", "inout", "variadic")]
        if len(toks) >= 2:
            nomes.append(toks[0])
    return nomes


def analisa(corpo, params, booleanas, helper_dono):
    b = sem_comentario(corpo).lower()
    escreve = set()
    for m in re.finditer(r"\b(?:update(?:\s+only)?|insert\s+into|delete\s+from|merge\s+into)\s+"
                         r"((?:\"?[a-z_0-9]+\"?\.)?\"?[a-z_][a-z_0-9]*\"?)", b):
        esq, tab = nome_curto(m.group(1))
        if esq == "public" and tab not in ("set",):
            escreve.add(tab)
    # variáveis que guardam a identidade do chamador
    tokens = [CALLER]
    # declare v_eu uuid := auth.uid();  (tipo de uma palavra, com [] opcional)
    for m in re.finditer(r"\b([a-z_][a-z0-9_]*)\s+[a-z_][a-z0-9_.]*(?:\s*\[\])?\s*(?::=|=|\bdefault\b)\s*(?:" + CALLER + ")", b):
        tokens.append(r"\b" + re.escape(m.group(1)) + r"\b")
    for m in re.finditer(r"\b([a-z_][a-z0-9_]*)\s*:=\s*(?:\(?\s*select\s+)?(?:" + CALLER + ")", b):
        tokens.append(r"\b" + re.escape(m.group(1)) + r"\b")
    for m in re.finditer(r"select\s+(?:" + CALLER + r")[^;]*?\binto\s+([a-z_][a-z0-9_]*)", b):
        tokens.append(r"\b" + re.escape(m.group(1)) + r"\b")
    chamador = re.compile("|".join(tokens))
    condicoes = [m.group(1) for m in re.finditer(r"\b(?:if|elsif|when)\b(.*?)\bthen\b", b, re.S)]
    condicoes += [m.group(1) for m in re.finditer(
        r"\bwhere\b(.*?)(?=;|\breturning\b|\border\s+by\b|\bgroup\s+by\b|\blimit\b|\bthen\b|\bon\s+conflict\b|$)",
        b, re.S)]
    dono = any(chamador.search(c) for c in condicoes)
    helpers = set()
    for m in re.finditer(r"\b([a-z_][a-z0-9_]*)\s*\(([^()]*)\)", b):
        nome = m.group(1).split(".")[-1]
        if nome in NAO_HELPER:
            continue
        if nome in booleanas or PREFIXO_HELPER.match(nome):
            helpers.add(nome)
            argumentos = re.findall(r"[a-z_][a-z0-9_]*", m.group(2))
            # helper por objeto, pode_editar(p_id): só conta se ele mesmo olha o chamador.
            # perfil_ativo(p_para) valida o destino e não diz nada sobre quem chamou
            if nome in helper_dono and any(a in params for a in argumentos):
                dono = True
    cita_chamador = bool(re.search(CALLER, b)) or len(tokens) > 1
    return escreve, dono, helpers, cita_chamador


SAIDA = []
FUNCS = {}          # nome -> dict
expor_padrao = True
lidos = arquivos()

if not lidos:
    SAIDA.append("\t".join(["COBERTURA", "familias_rpc", "nao_medido",
                            "nenhuma migration .sql em " + ", ".join(DIRS) +
                            ": sem banco, a família de funções não foi comparada"]))
    print("\n".join(SAIDA))
    sys.exit(0)

RE_CRIA = re.compile(r"\bcreate\s+(or\s+replace\s+)?function\s+((?:\"?[a-z_0-9]+\"?\.)?\"?[a-z_][a-z_0-9]*\"?)\s*\(", re.I)
RE_DROP = re.compile(r"\bdrop\s+function\s+(?:if\s+exists\s+)?((?:\"?[a-z_0-9]+\"?\.)?\"?[a-z_][a-z_0-9]*\"?)", re.I)
RE_PRIV = re.compile(r"\b(grant|revoke)\s+(?:all(?:\s+privileges)?|execute)\s+on\s+"
                     r"(?:function\s+((?:\"?[a-z_0-9]+\"?\.)?\"?[a-z_][a-z_0-9]*\"?)|all\s+functions\s+in\s+schema\s+public)"
                     r"[^;]*?\b(?:to|from)\b([^;]*);", re.I | re.S)
RE_DEFAULT = re.compile(r"alter\s+default\s+privileges[^;]*?\b(grant|revoke)\s+(?:all|execute)\s+on\s+functions"
                        r"[^;]*?\b(?:to|from)\b([^;]*);", re.I | re.S)
PAPEIS_BROWSER = re.compile(r"\b(anon|authenticated|public)\b", re.I)

# primeiro passe: quem devolve boolean é candidato a helper de checagem, e o que cita o
# chamador no corpo pode servir de checagem de dono
booleanas = set()
helper_dono = set()
textos = {}
for arq in lidos:
    try:
        with open(arq, encoding="utf-8", errors="replace") as f:
            textos[arq] = sem_comentario(f.read())
    except OSError:
        continue
    for m in RE_CRIA.finditer(textos[arq]):
        trecho = textos[arq][m.end():m.end() + 800]
        if re.search(r"\)\s*returns\s+(boolean|bool)\b", trecho, re.I):
            nome_b = nome_curto(m.group(2))[1]
            booleanas.add(nome_b)
            prox = RE_CRIA.search(textos[arq], m.end())
            corpo_b, _ = corpo_de(textos[arq][m.end():prox.start() if prox else len(textos[arq])])
            if re.search(CALLER, corpo_b, re.I):
                helper_dono.add(nome_b)
            else:
                helper_dono.discard(nome_b)

for arq in lidos:
    t = textos.get(arq, "")
    eventos = []
    for m in RE_CRIA.finditer(t):
        eventos.append((m.start(), "cria", m))
    for m in RE_DROP.finditer(t):
        eventos.append((m.start(), "drop", m))
    for m in RE_PRIV.finditer(t):
        eventos.append((m.start(), "priv", m))
    for m in RE_DEFAULT.finditer(t):
        eventos.append((m.start(), "default", m))
    eventos.sort(key=lambda e: e[0])
    for pos, tipo, m in eventos:
        if tipo == "cria":
            esq, nome = nome_curto(m.group(2))
            if esq != "public":
                continue
            # assinatura até o parêntese que fecha
            prof, i = 1, m.end()
            while i < len(t) and prof:
                prof += {"(": 1, ")": -1}.get(t[i], 0)
                i += 1
            assinatura = t[m.end():i - 1]
            proximo = RE_CRIA.search(t, i)
            resto = t[i:proximo.start() if proximo else len(t)]
            corpo, cabeca = corpo_de(resto)
            definer = bool(re.search(r"\bsecurity\s+definer\b", cabeca, re.I))
            if not corpo:
                continue
            params = params_de(assinatura)
            escreve, dono, helpers, cita = analisa(corpo, params, booleanas, helper_dono)
            anterior = FUNCS.get(nome)
            exposto = anterior["exposto"] if anterior else expor_padrao
            FUNCS[nome] = {"onde": f"{arq}:{t.count(chr(10), 0, pos) + 1}", "escreve": escreve,
                           "dono": dono, "helpers": helpers, "cita": cita,
                           "definer": definer, "exposto": exposto}
        elif tipo == "drop":
            FUNCS.pop(nome_curto(m.group(1))[1], None)
        elif tipo == "priv":
            if not PAPEIS_BROWSER.search(m.group(3)):
                continue
            valor = m.group(1).lower() == "grant"
            if m.group(2):
                f = FUNCS.get(nome_curto(m.group(2))[1])
                if f:
                    f["exposto"] = valor
            else:
                for f in FUNCS.values():
                    f["exposto"] = valor
        elif tipo == "default":
            if PAPEIS_BROWSER.search(m.group(2)):
                expor_padrao = m.group(1).lower() == "grant"

familias = {}
for nome, f in FUNCS.items():
    for tab in f["escreve"]:
        familias.setdefault(tab, []).append(nome)

sn = lambda v: "sim" if v else "nao"
gestao_nome = lambda n: any(ELEVADO.search(h) for h in FUNCS[n]["helpers"])
for tab in sorted(familias):
    for nome in sorted(familias[tab]):
        f = FUNCS[nome]
        SAIDA.append("\t".join(["MATRIZ", tab, nome, f["onde"], "dono=" + sn(f["dono"]),
                                "helpers=" + (",".join(sorted(f["helpers"])) or "-"),
                                "definer=" + sn(f["definer"]), "exposto=" + sn(f["exposto"])]))

acusadas = set()
for tab in sorted(familias):
    membros = familias[tab]
    if len(membros) < 2:
        continue
    com_dono = [n for n in membros if FUNCS[n]["dono"]]
    com_guarda = [n for n in membros if FUNCS[n]["dono"] or FUNCS[n]["helpers"]]
    # helper com nome de papel elevado (admin, gestão): função que só passa por ele é ação de
    # gestão e não precisa conferir dono. Só pelo nome: juntar os helpers das irmãs corretas
    # tornaria "elevado" o filtro de papel amplo que elas também chamam (pode_escrever)
    gestao = lambda n: any(ELEVADO.search(h) for h in FUNCS[n]["helpers"])
    for nome in sorted(membros):
        f = FUNCS[nome]
        if not f["exposto"] or (nome, tab) in acusadas:
            continue
        if not f["dono"] and not f["helpers"] and com_guarda:
            irmas = ", ".join(sorted(com_guarda))
            SAIDA.append("\t".join(["ACHADO", "HIGH", "familia_sem_checagem", f["onde"],
                                    limpa(f"{nome} escreve em {tab} sem checagem nenhuma, e as irmãs checam"),
                                    limpa(f"As irmãs que escrevem em {tab} conferem o chamador ou chamam helper "
                                          f"({irmas}); {nome} não faz nenhum dos dois. Exposta ao papel do browser "
                                          f"(definer={sn(f['definer'])}). Abra a função e copie a checagem da irmã.")]))
            acusadas.add((nome, tab))
        elif not f["dono"] and com_dono and not gestao(nome):
            irmas = ", ".join(sorted(com_dono))
            verbo = "confere" if len(com_dono) == 1 else "conferem"
            SAIDA.append("\t".join(["ACHADO", "HIGH", "familia_sem_dono", f["onde"],
                                    limpa(f"{nome} escreve em {tab} sem conferir dono, e as irmãs conferem"),
                                    limpa(f"{irmas} {verbo} o chamador contra o registro; {nome} só checa "
                                          f"papel ({', '.join(sorted(f['helpers'])) or 'nada'}). É o furo horizontal: "
                                          "mesmo papel, registro de outra pessoa. Verbo que muda o dono "
                                          "(transferir, atribuir, assumir) e upsert são os suspeitos de sempre.")]))
            acusadas.add((nome, tab))

for tab in sorted(familias):
    membros = familias[tab]
    expostos = [n for n in membros if FUNCS[n]["exposto"]]
    if len(membros) < 2 or any(FUNCS[n]["dono"] for n in membros) or not expostos \
            or all(FUNCS[n]["helpers"] and gestao_nome(n) for n in expostos) \
            or any((n, tab) in acusadas for n in membros):
        continue
    SAIDA.append("\t".join(["ACHADO", "LOW", "familia_toda_sem_dono", FUNCS[expostos[0]]["onde"],
                            limpa(f"Nenhuma das {len(membros)} funções que escrevem em {tab} confere dono ou escopo"),
                            limpa(f"{', '.join(sorted(membros))} só checam papel ou nada. Pode estar certo (tabela "
                                  "de gestão, ou o escopo é de todo o papel), ou o vínculo (carteira, setor) é "
                                  "conferido por funções que escrevem em outra tabela. Este script compara só "
                                  "dentro da mesma tabela: monte a matriz à mão com as funções que recebem o "
                                  "mesmo identificador (p_cliente, p_crm) e veja se alguma confere o vínculo.")]))

for nome, f in sorted(FUNCS.items()):
    if f["exposto"] and f["definer"] and f["escreve"] and not f["cita"] and not f["helpers"] \
            and not any((nome, t) in acusadas for t in f["escreve"]):
        SAIDA.append("\t".join(["ACHADO", "MEDIUM", "definer_escreve_sem_chamador", f["onde"],
                                limpa(f"{nome} é security definer, escreve e não olha quem chamou"),
                                limpa(f"Escreve em {', '.join(sorted(f['escreve']))} por cima da RLS e não cita "
                                      "auth.uid()/auth.jwt() nem helper. Exposta ao papel do browser: confirme "
                                      "com has_function_privilege ou revogue o EXECUTE.")]))

escrevem = [n for n, f in FUNCS.items() if f["escreve"]]
SAIDA.append("\t".join(["COBERTURA", "familias_rpc", "medido_migrations",
                        f"{len(lidos)} migrations, {len(FUNCS)} funções efetivas em public, "
                        f"{len(escrevem)} escrevem, {sum(1 for n in escrevem if FUNCS[n]['exposto'])} expostas, "
                        f"{sum(1 for m in familias.values() if len(m) > 1)} famílias com 2+ funções. Estado "
                        "efetivo = última definição nas migrations; o banco vivo vence (pg_proc e "
                        "has_function_privilege). Overload com o mesmo nome conta como uma função só"]))
print("\n".join(SAIDA))
