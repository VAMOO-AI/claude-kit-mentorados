#!/usr/bin/env python3
"""baseline · quem-entra — quem consegue virar membro, e o que "estar logado" já dá.

Estático e read-only: lê supabase/config.toml, as migrations e o código do app. Nunca chama
rede. Emite TSV no stdout, uma linha por fato, para o collect.sh (pilar 03), o secscan e a
auditoria-seguranca lerem:

  ACHADO<TAB>sev<TAB>check<TAB>arquivo:linha<TAB>titulo<TAB>detalhe
  COBERTURA<TAB>check<TAB>medido|nao_medido<TAB>motivo

Por que existe (pentests de 11/2026 em dois sistemas que rodavam secscan e baseline): o
achado principal nos dois foi o mesmo, e nenhuma skill o via inteiro.
  1. Cadastro do Supabase Auth aberto (painel ou config.toml), com auto-confirmação e
     senha curta. Nenhum check lia o bloco [auth] do config.toml, e sem config.toml a
     varredura ficava calada em vez de dizer "não medido".
  2. Autorização que confia em "estar autenticado": policy com auth.role() =
     'authenticated', <getter>() is not null, helper is_*() sem checar conta ativa.
  3. A linha que dá acesso nasce sozinha: trigger copia raw_user_meta_data->>'role'
     para o perfil, ou trigger de auto-provisão cria a ficha com papel padrão.
O RLS de cada tabela estava certo; o que falhava era o predicado ("autenticado =
funcionário") somado à porta aberta.

Estado efetivo: migration é append-only. A policy ou função que vale é a ÚLTIMA definição
(create/replace/drop, em ordem de nome de arquivo). Um grep cru acusa o que já foi corrigido
e perde o que foi recriado depois. O banco vivo continua sendo a autoridade (pg_policies,
pg_proc); este script é o melhor que dá sem ele, e diz isso na cobertura.

Uso: python3 -I quem-entra.py [--root DIR]
"""
import os
import re
import subprocess
import sys

# antes do chdir: o descobridor de pastas mora ao lado deste script
RAIZES_SH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "raizes.sh")

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

SAIDA = []


def limpa(s):
    return re.sub(r"[\t\r\n]+", " ", str(s)).strip()


def achado(sev, check, onde, titulo, detalhe):
    SAIDA.append("\t".join(["ACHADO", sev, check, limpa(onde), limpa(titulo), limpa(detalhe)]))


def cobertura(check, status, motivo=""):
    SAIDA.append("\t".join(["COBERTURA", check, status, limpa(motivo)]))


IGNORA_DIR = {"node_modules", ".git", ".next", "dist", "build", ".vercel", "coverage",
              "playwright-report", "test-results", ".turbo", "out"}


def arquivos(exts, base="."):
    for raiz, dirs, nomes in os.walk(base):
        dirs[:] = [d for d in dirs if d not in IGNORA_DIR and not d.startswith(".claude")]
        for n in nomes:
            if n.endswith(exts):
                yield os.path.normpath(os.path.join(raiz, n))


def le(p):
    try:
        with open(p, encoding="utf-8", errors="ignore") as f:
            return f.read()
    except OSError:
        return ""


def linha_de(texto, pos):
    return texto.count("\n", 0, pos) + 1


def sem_comentario_sql(t):
    # tira "-- ..." até o fim da linha, preservando o comprimento (as posições continuam valendo)
    return re.sub(r"--[^\n]*", lambda m: " " * len(m.group(0)), t)


# ───────────────────────────── 1. config do Auth versionada
cfg = "supabase/config.toml"
signup_aberto = None      # True / False / None (não medido)
confirma_email = None
if os.path.isfile(cfg):
    secao = ""
    vals = {}
    for i, ln in enumerate(le(cfg).splitlines(), 1):
        s = ln.split("#", 1)[0].strip()
        m = re.match(r"^\[([^\]]+)\]$", s)
        if m:
            secao = m.group(1).strip()
            continue
        m = re.match(r"^([A-Za-z_]+)\s*=\s*(.+)$", s)
        if m:
            vals[(secao, m.group(1))] = (m.group(2).strip().strip('"'), i)
    es = vals.get(("auth", "enable_signup"))
    ees = vals.get(("auth.email", "enable_signup"))
    ec = vals.get(("auth.email", "enable_confirmations"))
    mpl = vals.get(("auth", "minimum_password_length"))
    pr = vals.get(("auth", "password_requirements"))
    signup_aberto = (es is None or es[0] == "true") and (ees is None or ees[0] == "true")
    confirma_email = ec is not None and ec[0] == "true"
    if signup_aberto:
        onde = f"{cfg}:{(es or ees or ('', 1))[1]}"
        achado("MEDIUM", "auth_signup_aberto", onde,
               "Cadastro público do Auth ligado na config versionada",
               "enable_signup = true em [auth] e [auth.email]: qualquer pessoa cria conta pela API "
               "(POST /auth/v1/signup com a chave anon), mesmo sem tela de cadastro no app. Esconder "
               "o botão não fecha a porta. O config.toml vale para o ambiente local; produção é o "
               "painel (Authentication > Sign In / Providers): confirme lá ou com sonda-auth-viva.sh.")
    if signup_aberto and not confirma_email:
        onde = f"{cfg}:{ec[1]}" if ec else cfg
        achado("MEDIUM", "auth_sem_confirmacao", onde,
               "Conta nova entra sem confirmar o e-mail",
               "enable_confirmations = false: o e-mail da conta é o que a pessoa digitou. "
               "Autorização por e-mail ou domínio (auth.jwt()->>'email', @empresa.com) vira "
               "declaração do próprio usuário. Confirme 'Confirm email' no painel.")
    if mpl is not None:
        try:
            n = int(mpl[0])
        except ValueError:
            n = None
        if n is not None and n < 8:
            achado("MEDIUM", "auth_senha_curta", f"{cfg}:{mpl[1]}",
                   f"Senha mínima de {n} caracteres no Auth",
                   "minimum_password_length abaixo de 8. A regra da tela não vale para quem chama "
                   "a API direto (signup, updateUser, admin). Alinhe o painel (Password Security) "
                   "com a regra do app e ligue a checagem de senha vazada.")
    if pr is not None and pr[0] == "":
        achado("LOW", "auth_senha_sem_requisito", f"{cfg}:{pr[1]}",
               "Senha sem requisito de composição no Auth",
               "password_requirements vazio. Se o app exige maiúscula, dígito ou símbolo, o "
               "backend precisa exigir igual: senha definida por script ou suporte não passa pela tela.")
    cobertura("auth_config", "medido",
              f"{cfg} lido; produção é o painel: confirme com sonda-auth-viva.sh ou a Management API")
else:
    cobertura("auth_config", "nao_medido",
              "sem supabase/config.toml: cadastro aberto, auto-confirmação e senha mínima moram só "
              "no painel. Rode sonda-auth-viva.sh (GET /auth/v1/settings) antes de dizer que a "
              "porta está fechada. Foi este silêncio que deixou passar um signup público com papel admin.")

# ───────────────────────────── 2. estado efetivo das migrations
PASTAS_SQL = [p for p in ("supabase/migrations", "migrations", "src/sql", "db/migrations",
                          "supabase/schemas") if os.path.isdir(p)]
# mais toda pasta migrations/, sql/ ou schemas/ com .sql que o raizes.sh achar no repo
# (src/db/migrations, <app>/supabase/migrations). Sem o script ou sem bash, fica a lista fixa.
try:
    _r = subprocess.run(["bash", RAIZES_SH, "--root", "."], capture_output=True, text=True, timeout=60)
    for _l in _r.stdout.splitlines():
        _c = _l.split("\t")
        if len(_c) >= 2 and _c[0] == "MIGRATIONS" and _c[1] not in PASTAS_SQL and os.path.isdir(_c[1]):
            PASTAS_SQL.append(_c[1])
except (OSError, subprocess.SubprocessError):
    pass
sqls = []
ignorados = []
for p in PASTAS_SQL:
    nomes = sorted(n for n in os.listdir(p) if n.endswith(".sql"))
    # Pasta de migration com prefixo numérico: arquivo fora do padrão (_apply_all.sql, seed,
    # rascunho) não é migration aplicada, e por ordenar DEPOIS dos números viraria a definição
    # "efetiva" de tudo que ele concatena.
    if any(re.match(r"^\d", n) for n in nomes):
        ignorados += [os.path.join(p, n) for n in nomes if not re.match(r"^\d", n)]
        nomes = [n for n in nomes if re.match(r"^\d", n)]
    sqls += [os.path.join(p, n) for n in nomes]

RE_NOME = r'((?:"?[\w]+"?\.)?"?[\w]+"?)'


def norm(nome):
    nome = nome.replace('"', "").lower()
    return nome.split(".", 1)[1] if nome.startswith(("public.", "auth.")) and "." in nome else nome


funcoes = {}     # nome -> dict(arq, linha, corpo)
policies = {}    # (tabela, nome) -> dict(arq, linha, texto, tabela, cmd, roles)
triggers = {}    # (tabela, nome) -> dict(arq, linha, tabela, funcao, evento)

for arq in sqls:
    bruto = le(arq)
    t = sem_comentario_sql(bruto)
    # Eventos na ordem do arquivo: "drop policy if exists x; create policy x" é o padrão
    # idempotente, e aplicar todos os create antes dos drop apagaria a policy recém-criada.
    ev = []
    for m in re.finditer(r"create\s+(?:or\s+replace\s+)?function\s+" + RE_NOME + r"\s*\(", t, re.I):
        d = re.search(r"\$(\w*)\$", t[m.end():])
        if not d:
            continue
        ini = m.end() + d.end()
        fim = t.find(d.group(0), ini)
        if fim < 0:
            continue
        ev.append((m.start(), "fn+", norm(m.group(1)),
                   {"arq": arq, "linha": linha_de(t, m.start()), "corpo": t[ini:fim], "cab": t[m.start():ini]}))
    for m in re.finditer(r"drop\s+function\s+(?:if\s+exists\s+)?" + RE_NOME, t, re.I):
        ev.append((m.start(), "fn-", norm(m.group(1)), None))
    # policies, inclusive dentro de execute format('create policy ... on %I ...') em laço
    for m in re.finditer(r'create\s+policy\s+(?:"([^"]+)"|(\w+))\s+on\s+((?:"?\w+"?\.)?%[IsL]|' + RE_NOME[1:-1] + r')(.*?);',
                         t, re.I | re.S):
        nome = (m.group(1) or m.group(2)).lower()
        tab = norm(m.group(3)) if "%" not in m.group(3) else "(laço)"
        texto = m.group(4)
        cmd = re.search(r"\bfor\s+(select|insert|update|delete|all)\b", texto, re.I)
        roles = re.search(r"\bto\s+([\w, ]+?)\s+(?:using|with)\b", texto, re.I)
        ev.append((m.start(), "pol+", (tab, nome),
                   {"arq": arq, "linha": linha_de(t, m.start()), "texto": texto, "tabela": tab,
                    "cmd": (cmd.group(1).lower() if cmd else "all"),
                    "roles": (roles.group(1).lower() if roles else "public")}))
    for m in re.finditer(r'drop\s+policy\s+(?:if\s+exists\s+)?(?:"([^"]+)"|(\w+))\s+on\s+((?:"?\w+"?\.)?%[IsL]|' + RE_NOME[1:-1] + r')',
                         t, re.I):
        tab = norm(m.group(3)) if "%" not in m.group(3) else "(laço)"
        ev.append((m.start(), "pol-", (tab, (m.group(1) or m.group(2)).lower()), None))
    for m in re.finditer(r"create\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+(\w+)\s+(.*?)\bon\s+"
                         + RE_NOME + r"(.*?)execute\s+(?:function|procedure)\s+" + RE_NOME, t, re.I | re.S):
        tab = norm(m.group(3))
        ev.append((m.start(), "tg+", (tab, m.group(1).lower()),
                   {"arq": arq, "linha": linha_de(t, m.start()), "tabela": tab,
                    "funcao": norm(m.group(5)), "evento": m.group(2).lower()}))
    for m in re.finditer(r"drop\s+trigger\s+(?:if\s+exists\s+)?(\w+)\s+on\s+" + RE_NOME, t, re.I):
        ev.append((m.start(), "tg-", (norm(m.group(2)), m.group(1).lower()), None))
    for _, tipo, chave, val in sorted(ev, key=lambda e: e[0]):
        alvo = {"fn": funcoes, "pol": policies, "tg": triggers}[tipo[:-1]]
        if tipo.endswith("+"):
            alvo[chave] = val
        else:
            alvo.pop(chave, None)

if ignorados:
    cobertura("sql_fora_do_padrao", "nao_medido",
              f"{len(ignorados)} .sql sem prefixo numérico ignorados como estado efetivo: {', '.join(ignorados[:3])}")
if not sqls:
    cobertura("predicados_rls", "nao_medido", "sem pasta de migration com .sql")
    cobertura("autoprovisao", "nao_medido", "sem pasta de migration com .sql")
else:
    cobertura("predicados_rls", "medido",
              f"{len(policies)} policies efetivas em {len(sqls)} arquivos ({', '.join(PASTAS_SQL)}); "
              "efetivo = última definição nas migrations. O banco vivo vence: confirme com pg_policies")

RE_META_PAPEL = re.compile(r"(raw_)?user_meta_?data[^;\n]{0,40}(role|papel|admin|tier|plan|plano|tenant|org|perfil|cargo|nivel)",
                           re.I)
RE_ATIVO = re.compile(r"\b(ativo|ativa|active|enabled|habilitad|status|aprovad|approved|deleted_at|banned|bloquead|desativad)", re.I)

# 2a. papel lido do metadata que o próprio usuário escreve (função/trigger efetiva)
meta_hits = []
for nome, f in funcoes.items():
    m = RE_META_PAPEL.search(f["corpo"])
    if m:
        meta_hits.append(nome)
        achado("HIGH", "papel_do_metadata", f"{f['arq']}:{f['linha']}",
               f"Função {nome}() decide papel a partir de user_metadata",
               "raw_user_meta_data é escrito pelo usuário: signUp({options:{data:{role:'admin'}}}) "
               "ou updateUser({data}). Trigger de cadastro que copia esse campo para a coluna de "
               "papel faz a conta nascer com o papel que ela mesma pediu. Fixe o papel mínimo no "
               "trigger (ou nasça inativo) e grave papel só pelo servidor (app_metadata ou tabela "
               "que o usuário não edita). Definição efetiva; confirme com pg_get_functiondef.")
for (tab, nome), p in policies.items():
    if re.search(r"user_meta_?data", p["texto"], re.I):
        achado("HIGH", "papel_do_metadata", f"{p['arq']}:{p['linha']}",
               f"Policy '{nome}' em {tab} lê user_metadata",
               "Policy que decide por metadata editável pelo usuário (lint 0015 do Supabase). Use "
               "app_metadata ou uma tabela de papéis.")
cobertura("papel_do_metadata_sql", "medido" if sqls else "nao_medido",
          f"{len(funcoes)} funções efetivas lidas" if sqls else "sem migrations")

# 2b. o que roda quando uma conta nasce, e com que papel
def chamadas(texto):
    return {norm(x) for x in re.findall(r"((?:\w+\.)?\w+)\s*\(", texto)} & set(funcoes)


# Toda função que uma policy chama, direto ou por dentro de outra função (concierge_pode_ler()
# chama papel_atual(), que lê perfis): a tabela que ela lê é tabela que libera acesso.
getters_usados = set()
fila = set()
for (tab, nome), p in policies.items():
    fila |= chamadas(p["texto"])
while fila:
    g = fila.pop()
    if g in getters_usados:
        continue
    getters_usados.add(g)
    fila |= chamadas(funcoes[g]["corpo"]) - getters_usados


def tabelas_lidas(corpo):
    return {norm(x) for x in re.findall(r"\bfrom\s+" + RE_NOME, corpo, re.I)}


def tabelas_inseridas(corpo):
    return {norm(x) for x in re.findall(r"\binsert\s+into\s+" + RE_NOME, corpo, re.I)}


tabelas_de_acesso = set()
for g in getters_usados:
    if g in funcoes:
        tabelas_de_acesso |= tabelas_lidas(funcoes[g]["corpo"])

for (tab, nome), tg in triggers.items():
    f = funcoes.get(tg["funcao"])
    if not f or "insert" not in tg["evento"]:
        continue
    inseridas = tabelas_inseridas(f["corpo"])
    padrao = re.findall(r"(?:coalesce\s*\([^;]{0,200}?,\s*|else\s+)'(\w+)'", f["corpo"], re.I)
    if tab == "users" and inseridas:
        nasce_inativa = re.search(r"\b(ativo|active|enabled|aprovad|approved)\b", f["corpo"], re.I) \
            and re.search(r"\bfalse\b", f["corpo"], re.I)
        sev = "MEDIUM" if (padrao and tg["funcao"] not in meta_hits and not nasce_inativa) else "INFO"
        achado(sev, "autoprovisao_cadastro", f"{f['arq']}:{f['linha']}",
               f"Conta nova em auth.users cria linha em {', '.join(sorted(inseridas))} via {tg['funcao']}()",
               "Toda conta criada pelo signup passa por aqui. Valores padrão encontrados: "
               f"{', '.join(sorted(set(padrao))) or 'nenhum literal'}. Se o padrão é um papel com "
               "acesso, ou a linha nasce ativa, o cadastro aberto vira membro sem convite. Padrão "
               "seguro: papel mínimo e ativo = false até alguém liberar.")
    cruz = inseridas & tabelas_de_acesso
    if cruz and tab != "users":
        achado("MEDIUM", "autoprovisao_acesso", f"{f['arq']}:{f['linha']}",
               f"Trigger {nome} em {tab} cria a linha que libera leitura ({', '.join(sorted(cruz))})",
               "Uma policy autoriza por '<getter>() is not null', e o getter lê uma tabela que este "
               "trigger preenche sozinho (papel padrão: "
               f"{', '.join(sorted(set(padrao))) or 'n/d'}). A prova de vínculo passa a ser a "
               "existência de uma linha que o sistema cria, não um convite. Exija vínculo de verdade "
               "(ficha de equipe, convite aceito) e marque a origem das linhas automáticas.")
cobertura("autoprovisao", "medido" if sqls else "nao_medido",
          f"{len(triggers)} triggers efetivos" if sqls else "sem migrations")

# 2c. predicado "autenticado = membro"
PRED = [
    (r"auth\.role\s*\(\s*\)\s*=\s*'authenticated'", "auth.role() = 'authenticated'"),
    (r"auth\.uid\s*\(\s*\)\s*(?:\)\s*)?is\s+not\s+null", "auth.uid() is not null"),
    (r"\b(\w+)\s*\(\s*\)\s*(?:\)\s*)?is\s+not\s+null", "<getter>() is not null"),
]
n_pred = 0
for (tab, nome), p in sorted(policies.items(), key=lambda kv: (kv[1]["arq"], kv[1]["linha"])):
    txt = p["texto"]
    alvo = None
    for rx, rot in PRED:
        m = re.search(rx, txt, re.I)
        if m:
            if rot == "<getter>() is not null" and m.group(1).lower() in ("uid", "auth"):
                continue
            alvo = rot if rot != "<getter>() is not null" else f"{m.group(1)}() is not null"
            break
    if not alvo and re.search(r"\busing\s*\(\s*true\s*\)", txt, re.I) and "authenticated" in p["roles"]:
        alvo = "to authenticated using (true)"
    if not alvo:
        continue
    n_pred += 1
    escreve = p["cmd"] in ("insert", "update", "delete", "all")
    if signup_aberto is not False and escreve:
        sev = "HIGH"
    elif alvo == "to authenticated using (true)" and not escreve:
        sev = "LOW"  # leitura de catálogo por qualquer sessão: anote, o juízo é do dono
    else:
        sev = "MEDIUM"
    porta = {True: "o cadastro está aberto na config versionada",
             False: "o cadastro está fechado na config versionada (confirme no painel)",
             None: "o estado do cadastro não foi medido (sem config.toml)"}[signup_aberto]
    achado(sev, "autenticado_e_membro", f"{p['arq']}:{p['linha']}",
           f"Policy '{nome}' em {p['tabela']} ({p['cmd']}) aceita '{alvo}'",
           f"O predicado responde 'tem sessão' ou 'tem uma linha', não 'é da equipe'. Com cadastro "
           f"aberto, qualquer conta nova passa; e {porta}. Prove vínculo (perfil ativo e aprovado, "
           "ficha de equipe, liberação do módulo) em vez de existência. Definição efetiva nas "
           "migrations; o banco vivo vence.")
cobertura("autenticado_e_membro", "medido" if sqls else "nao_medido",
          f"{n_pred} policies com predicado de existência" if sqls else "sem migrations")

# 2d. helper de papel que ignora conta desativada
n_help = 0
for nome, f in funcoes.items():
    if not re.match(r"^(is_|eh_|e_|sou_|tem_|has_|can_|pode_|meu_|my_|current_|papel|role|user_role)", nome):
        continue
    corpo = f["corpo"]
    if "auth.uid" not in corpo.lower():
        continue
    if not tabelas_lidas(corpo):
        continue
    if RE_ATIVO.search(corpo):
        continue
    n_help += 1
    achado("MEDIUM", "papel_sem_conta_ativa", f"{f['arq']}:{f['linha']}",
           f"Helper {nome}() não confere se a conta está ativa",
           "Desativar a pessoa não tira o poder enquanto o JWT valer (cerca de 1 h), e conta "
           "auto-cadastrada que ainda não foi aprovada passa igual. Some 'and ativo' (ou o "
           "equivalente) em todo helper de papel, não só no de admin.")
cobertura("papel_sem_conta_ativa", "medido" if sqls else "nao_medido", f"{n_help} helpers sem ativo")

# 2e. identidade por e-mail do JWT
for nome, f in funcoes.items():
    if re.search(r"auth\.jwt\s*\(\s*\)\s*->>?\s*'email'|auth\.email\s*\(\s*\)", f["corpo"], re.I) \
            and "email_confirmed_at" not in f["corpo"].lower():
        sev = "MEDIUM" if confirma_email is not True else "LOW"
        achado(sev, "identidade_por_email", f"{f['arq']}:{f['linha']}",
               f"{nome}() identifica a pessoa pelo e-mail do JWT sem exigir e-mail confirmado",
               "Com auto-confirmação ligada, o e-mail do JWT é o que a pessoa digitou no cadastro: "
               "nome.sobrenome@suaempresa.com vira 'da casa'. Exija auth.users.email_confirmed_at "
               "is not null com confirmação de verdade ligada; o claim email_verified do "
               "user_metadata não prova nada (o usuário escreve).")

# ───────────────────────────── 3. código do app
CODIGO = tuple([".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"])
fontes = [p for p in arquivos(CODIGO) if not re.search(r"(\.test\.|\.spec\.|__tests__|/e2e/|\.d\.ts$)", p)]
cobertura("codigo_app", "medido" if fontes else "nao_medido", f"{len(fontes)} arquivos de código")


def eh_comentario(ln):
    return re.match(r"^\s*(//|\*|/\*)", ln) is not None


# 3a. papel decidido pelo metadata no app
for p in fontes:
    for i, ln in enumerate(le(p).splitlines(), 1):
        if eh_comentario(ln):
            continue
        if RE_META_PAPEL.search(ln) or re.search(
                r"\{[^}]*(role|papel|admin|plan|plano|tier|tenant|org)[^}]*\}\s*=[^;]*user_meta_?data", ln, re.I):
            if re.search(r"(signUp|createUser|inviteUserByEmail|updateUser)", ln) or re.search(r"user_meta_?data\s*:", ln):
                continue  # quem ESCREVE é o servidor; o risco é ler e decidir
            achado("HIGH", "papel_do_metadata_app", f"{p}:{i}",
                   "O app decide papel ou acesso a partir de user_metadata",
                   "user_metadata é do usuário. Leia o papel de app_metadata ou de uma tabela que só o "
                   "servidor grava.")

# 3b. HMAC sem janela de tempo nem nonce (assinatura vale para sempre)
for p in fontes:
    t = le(p)
    if "createHmac" not in t and "crypto.subtle.sign" not in t:
        continue
    if not re.search(r"timingSafeEqual|verify|assinatura|signature", t, re.I):
        continue
    if re.search(r"timestamp|nonce|Date\.now\(\)|x-[\w-]*(time|ts)\b|toleran|janela|max_?age|expir", t, re.I):
        continue
    m = re.search(r"createHmac|crypto\.subtle\.sign", t)
    achado("MEDIUM", "hmac_sem_janela", f"{p}:{linha_de(t, m.start())}",
           "Assinatura HMAC sem timestamp nem nonce",
           "Quem captura uma requisição assinada a reenvia para sempre (replay): PATCH reaplica, "
           "ingestão duplica. Assine timestamp + corpo, recuse fora de uma janela (ex.: 300 s) e "
           "guarde o nonce. Header que decide autoria ou escopo (id do workflow, tenant) entra na "
           "assinatura. Um segredo por família de rota, não um para todas.")

# 3c. segredo de máquina na query string
for p in fontes:
    for i, ln in enumerate(le(p).splitlines(), 1):
        if eh_comentario(ln):
            continue
        m = re.search(r"searchParams\.get\(\s*['\"](secret|chave|key|api_?key|apikey|senha|password|signature|sig|token)['\"]", ln, re.I) \
            or re.search(r"\bquery\.(secret|chave|api_?key|apikey|senha|password|signature)\b", ln, re.I)
        if m:
            achado("LOW", "segredo_na_query", f"{p}:{i}",
                   f"Credencial aceita pela query string (?{m.group(1)}=)",
                   "Query string fica em log de proxy, de CDN, no histórico e no Referer. Aceite o "
                   "segredo só em header (Authorization ou x-*-secret) e compare em tempo constante.")

# 3d. guard de rota que responde 200: redirect()/notFound() abaixo de um loading.tsx
apps = [d for d in ("app", "src/app") if os.path.isdir(d)]
n_guard = 0
guardas = []
for base in apps:
    for p in arquivos(("page.tsx", "page.jsx", "page.js", "page.ts"), base):
        t = le(p)
        m = re.search(r"^(?!\s*(//|\*)).*\b(redirect|notFound|forbidden|unauthorized)\s*\(", t, re.M)
        if not m:
            continue
        d = os.path.dirname(p)
        loading = None
        while True:
            for ext in ("tsx", "jsx", "js"):
                c = os.path.join(d, f"loading.{ext}")
                if os.path.isfile(c):
                    loading = c
                    break
            if loading or os.path.normpath(d) == os.path.normpath(base):
                break
            d = os.path.dirname(d)
        if loading:
            n_guard += 1
            guardas.append((f"{p}:{linha_de(t, m.start())}", loading))
if guardas:
    onde, loading = guardas[0]
    achado("LOW", "guard_depois_do_stream", onde,
           f"{len(guardas)} páginas com redirect()/notFound() abaixo de um loading (200 com meta-refresh)",
           f"{loading} cria um Suspense acima da página: o shell sai com status 200 antes "
           "do redirect()/notFound(), que vira <meta http-equiv=refresh>. Não vaza dado, mas "
           "monitor e scanner leem 'rota saudável', e um notFound() não devolve 404. Se o redirect "
           "é guard de acesso, decida no middleware/proxy ou num layout sem loading acima; prove "
           "com curl -s -o /dev/null -w '%{http_code}' sem sessão (esperado 307/404). Exemplos: "
           + ", ".join(g[0] for g in guardas[:3]))
cobertura("guard_depois_do_stream", "medido" if apps else "nao_medido",
          f"{n_guard} páginas com guard abaixo de loading" if apps else "sem app/ do Next")

# 3e. cota/limite contado em tabela que o próprio usuário grava
insert_aberto = {}
for (tab, nome), p in policies.items():
    if p["cmd"] in ("insert", "all") and ("authenticated" in p["roles"] or p["roles"] == "public"):
        insert_aberto.setdefault(tab, p)
for p in fontes:
    t = le(p)
    if not re.search(r"count\s*:\s*['\"]exact['\"]", t):
        continue
    if not re.search(r"LIMITE|LIMIT_|_LIMIT\b|quota|cota|MAX_|limite_?diario|daily", t, re.I):
        continue
    for m in re.finditer(r"\.from\(\s*['\"](\w+)['\"]\s*\)", t):
        trecho = t[m.start():m.start() + 400]
        if not re.search(r"count\s*:\s*['\"]exact['\"]", trecho):
            continue
        if not re.search(r"\.(gte|gt)\(\s*['\"]\w*(criad|created|data|hora|em|at)\w*['\"]", trecho):
            continue  # teto de estoque (máx. de fotos) não é cota por janela
        tab = m.group(1).lower()
        if tab in insert_aberto:
            pol = insert_aberto[tab]
            achado("MEDIUM", "cota_em_tabela_do_usuario", f"{p}:{linha_de(t, m.start())}",
                   f"Limite contado em '{tab}', que o próprio usuário grava pela API",
                   f"A policy de insert '{pol['arq']}:{pol['linha']}' deixa a sessão inserir em {tab}. "
                   "O freio mede quantas linhas existem, não quantas chamadas o servidor atendeu: "
                   "inserir direto pelo PostgREST esgota ou falseia a cota. Conte numa tabela que só "
                   "o servidor escreve, com consumo atômico (security definer + for update).")

# 3f. cookie de sessão longo ou no domínio-mãe
for p in fontes:
    t = le(p)
    if not re.search(r"cookie", t, re.I):
        continue
    for m in re.finditer(r"maxAge\s*:\s*([\d_ *]+)", t):
        try:
            seg = eval(m.group(1).replace("_", ""), {"__builtins__": {}})  # só dígitos, _ e *
        except Exception:
            continue
        if isinstance(seg, (int, float)) and seg > 90 * 86400:
            achado("LOW", "cookie_longo", f"{p}:{linha_de(t, m.start())}",
                   f"Cookie com validade de {int(seg // 86400)} dias",
                   "Sessão que sobrevive meses aumenta a janela de um cookie roubado. 30 a 90 dias "
                   "bastam; o refresh renova a cada uso.")
    for m in re.finditer(r"domain\s*:\s*['\"]\.[\w.-]+['\"]", t):
        achado("INFO", "cookie_dominio_mae", f"{p}:{linha_de(t, m.start())}",
               "Cookie de sessão no domínio-mãe",
               "Todo subdomínio, inclusive legado ou de terceiro, recebe o cookie. Mantenha a lista "
               "de subdomínios vivos curta, ou use cookie host-only com troca explícita.")

# 3g. escrita que não confere se alguma linha mudou (RLS nega com 204)
cegas = []
for p in fontes:
    t = le(p)
    for m in re.finditer(r"\.(update|delete|upsert)\(", t):
        if not re.search(r"\.from\(", t[max(0, m.start() - 300):m.start()]):
            continue
        fim = t.find(";", m.end())
        cadeia = t[m.end():fim if fim > 0 else m.end() + 400]
        if re.search(r"\.select\(|count\s*:|\.single\(|\.maybeSingle\(", cadeia):
            continue
        cegas.append(f"{p}:{linha_de(t, m.start())}")
if cegas:
    achado("LOW", "escrita_sem_conferir", cegas[0],
           f"{len(cegas)} escritas pelo PostgREST não conferem se alguma linha mudou",
           "Escrita negada pela RLS não é erro: o PostgREST responde 204 (ou 200 com []) e o código "
           "segue como se tivesse gravado. Peça a linha de volta (.select()) ou { count: 'exact' } "
           "e trate zero como 'sem permissão'. Exemplos: " + ", ".join(cegas[:3]))
cobertura("escrita_sem_conferir", "medido" if fontes else "nao_medido", f"{len(cegas)} escritas cegas")

print("\n".join(SAIDA))
