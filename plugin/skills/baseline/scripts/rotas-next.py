#!/usr/bin/env python3
"""baseline · rotas-next — o que cada route handler do Next expõe, rota por rota.

Estático e read-only, sem rede. Emite TSV para o collect.sh:

  ACHADO<TAB>pilar<TAB>sev<TAB>check<TAB>arquivo:linha<TAB>titulo<TAB>detalhe
  COBERTURA<TAB>pilar<TAB>check<TAB>medido|nao_medido<TAB>motivo

Por que existe: o pilar 04 media rate limit no projeto inteiro (um 429 em qualquer lugar e o
check saía "medido"). Num pentest de 11/2026, o login tinha limite e a busca do inbox, o lookup
de avatar por telefone e o link de roteiro por token não tinham. Também não havia check de
segredo de máquina compartilhado entre famílias de rota, nem de COOP/CORP, robots.txt ou
security.txt.

Checks:
  04 rate_limit_rota_publica   route handler sem sessão nem segredo, com parâmetro dinâmico,
                               busca ou POST, sem limitador no arquivo, nos imports locais
                               ou no middleware/proxy
  04 rate_limit_rota_sessao    route handler com sessão que faz busca livre ou consulta em lote
  04 segredo_compartilhado     uma env de segredo de máquina autenticando rotas de 2+ famílias
  01 headers_isolamento        COOP / CORP ausentes onde os headers são declarados
  08 robots_txt, security_txt  arquivo ou rota ausente

Uso: python3 -I rotas-next.py [--root DIR]
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

SAIDA = []


def limpa(s):
    return re.sub(r"[\t\r\n]+", " ", str(s)).strip()


def achado(pilar, sev, check, onde, titulo, detalhe):
    SAIDA.append("\t".join(["ACHADO", pilar, sev, check, limpa(onde), limpa(titulo), limpa(detalhe)]))


def cobertura(pilar, check, status, motivo=""):
    SAIDA.append("\t".join(["COBERTURA", pilar, check, status, limpa(motivo)]))


def le(p):
    try:
        with open(p, encoding="utf-8", errors="ignore") as f:
            return f.read()
    except OSError:
        return ""


IGNORA = {"node_modules", ".git", ".next", "dist", "build", ".vercel", "coverage", "out", ".turbo"}


def anda(base, filtro):
    for raiz, dirs, nomes in os.walk(base):
        dirs[:] = [d for d in dirs if d not in IGNORA and not d.startswith(".claude")]
        for n in nomes:
            if filtro(n):
                yield os.path.normpath(os.path.join(raiz, n))


APPS = [d for d in ("src/app", "app") if os.path.isdir(d)]
PAGES_API = [d for d in ("src/pages/api", "pages/api") if os.path.isdir(d)]

# limitador imposto pelo próprio código (o 429 de fornecedor tratado não conta)
RE_LIMITE = re.compile(r"rate_?limit_?take|rateLimitTake|checkRateLimit|new\s+Ratelimit|@upstash/ratelimit|"
                       r"rateLimit\s*\(|limitar\w*\s*\(|limiter\.|status:\s*429|status\s*=\s*429|"
                       r"['\"]Retry-After['\"]\s*:", re.I)
# a rota prova quem chama: sessão de usuário ou segredo de máquina
RE_SESSAO = re.compile(r"auth\.getUser|getClaims|getSession|getServerSession|requireSession|requireUser|"
                       r"\brequireAuth|\bassertAuth|\bcurrentUser\b|\bexigir\w*\(|\bauth\(\)|\bwithAuth\b", re.I)
# Prova de máquina = comparar algo da requisição com um segredo. "Bearer" e createHmac sozinhos
# não servem: aparecem quando a rota CHAMA um serviço (token do Google, assinatura de saída).
RE_MAQUINA = re.compile(r"timingSafeEqual|constantTimeEqual|safeCompare|verify\w*(Signature|Hmac|Secret|Token)|"
                        r"isCronAuthorized|isAuthorized\w*\(|CRON_SECRET|"
                        r"headers\.get\(\s*['\"](authorization|x-[\w-]+)['\"]\s*\)\s*[!=]==?", re.I)
RE_LE_REQUISICAO = re.compile(r"headers\.get\(|req\.headers|request\.headers|\(\s*(request|req)\s*[,)]", re.I)
RE_BUSCA = re.compile(r"searchParams\.get\(\s*['\"](q|query|search|busca|termo|term|phone|telefone|email|nome|name)['\"]",
                      re.I)
RE_LOTE = re.compile(r"\b(phones|telefones|ids|emails|numeros|items)\b\s*(\.slice|\.length|:\s*z\.array|\]\s*=)", re.I)
RE_FETCH_EXTERNO = re.compile(r"fetch\(\s*[`'\"]https?://|fetch\(\s*`\$\{", re.I)


def resolve_import(origem, spec):
    if spec.startswith("@/"):
        base = os.path.join("src", spec[2:]) if os.path.isdir("src") else spec[2:]
    elif spec.startswith("."):
        base = os.path.normpath(os.path.join(os.path.dirname(origem), spec))
    else:
        return None
    for c in (base + ".ts", base + ".tsx", base + ".js", base + ".mjs", os.path.join(base, "index.ts"),
              os.path.join(base, "index.js"), base):
        if os.path.isfile(c):
            return c
    return None


def imports_locais(p, texto):
    out = []
    for m in re.finditer(r"""(?:from|import\()\s*['"]([^'"]+)['"]""", texto):
        r = resolve_import(p, m.group(1))
        if r:
            out.append(r)
    return out


def com_imports(p, profundidade=2):
    """texto do arquivo + o dos módulos locais que ele importa (até 2 níveis)."""
    vistos, fila, textos = set(), [(p, 0)], []
    while fila:
        f, d = fila.pop()
        if f in vistos:
            continue
        vistos.add(f)
        t = le(f)
        textos.append(t)
        if d < profundidade:
            fila += [(i, d + 1) for i in imports_locais(f, t)]
    return "\n".join(textos), vistos


# ───────────────────────────── middleware / proxy cobre todo mundo?
mw = [f for f in ("middleware.ts", "middleware.js", "src/middleware.ts", "src/middleware.js",
                  "proxy.ts", "proxy.js", "src/proxy.ts", "src/proxy.js") if os.path.isfile(f)]
limite_global = None
sessao_mw = None
publicos_mw = []
for f in mw:
    t, _ = com_imports(f)
    if RE_LIMITE.search(t):
        limite_global = f
    if RE_SESSAO.search(t):
        sessao_mw = f
    # o que escapa da sessão do middleware: lista de prefixos públicos em string e a exclusão
    # do matcher por lookahead negativo ("/((?!_next|api/cron|api/r/).*)")
    for g in re.findall(r"\(\?!([^)]*)\)", t):
        publicos_mw += ["/" + x.strip().lstrip("/") for x in g.split("|") if len(x.strip()) >= 3]
    publicos_mw += re.findall(r"""['"](/[\w\-./\[\]]{2,})['"]""", t)
publicos_mw = sorted({x.rstrip("$") for x in publicos_mw if not x.startswith("/_next")})


def caminho_url(p):
    q = p.replace("\\", "/")
    for b in ("src/app/", "app/", "src/pages/", "pages/"):
        if q.startswith(b):
            q = q[len(b) - 1:]
            break
    q = re.sub(r"/\([^)]*\)", "", q)
    q = re.sub(r"/route\.(ts|js|mjs)$", "", q)
    q = re.sub(r"\.(ts|js)$", "", q)
    return q or "/"


def escapa_do_middleware(p):
    if not sessao_mw:
        return True
    u = caminho_url(p)
    return any(u == x or u.startswith(x.rstrip("/") + "/") or u.startswith(x) and x.endswith("/") for x in publicos_mw)

# ───────────────────────────── 04 · rate limit por route handler
rotas = []
for base in APPS:
    rotas += list(anda(base, lambda n: re.match(r"^route\.(ts|js|mjs)$", n) is not None))
for base in PAGES_API:
    rotas += list(anda(base, lambda n: n.endswith((".ts", ".js")) and not n.startswith("_")))

publicas, sessao_busca = [], []
for p in sorted(rotas):
    t = le(p)
    tudo, _ = com_imports(p)
    if RE_LIMITE.search(tudo) or limite_global:
        continue
    dinamico = re.search(r"\[[^\]/]+\]", p) is not None
    busca = RE_BUSCA.search(t) is not None
    lote = RE_LOTE.search(t) is not None
    escreve = re.search(r"export\s+(async\s+)?function\s+(POST|PUT|PATCH|DELETE)\b|export\s+const\s+(POST|PUT|PATCH|DELETE)\b", t) is not None
    externo = RE_FETCH_EXTERNO.search(tudo) is not None
    tem_sessao = RE_SESSAO.search(tudo) is not None or not escapa_do_middleware(p)
    tem_maquina = RE_MAQUINA.search(tudo) is not None and RE_LE_REQUISICAO.search(t) is not None
    motivo = [m for m, v in (("parâmetro dinâmico", dinamico), ("busca", busca), ("lote", lote),
                             ("escrita", escreve), ("chama serviço externo", externo)) if v]
    if not motivo:
        continue
    if not tem_sessao and not tem_maquina:
        publicas.append((p, motivo))
    elif tem_sessao and (busca or lote):
        sessao_busca.append((p, motivo))

if rotas:
    if publicas:
        ex = "; ".join(f"{p} ({', '.join(m)})" for p, m in publicas[:4])
        achado("04", "MEDIUM", "rate_limit_rota_publica", publicas[0][0],
               f"{len(publicas)} route handlers sem login nem segredo e sem rate limit",
               "Rota aberta com token no caminho, busca, escrita ou chamada a serviço pago responde a "
               "qualquer volume: valida token vazado por força bruta (404 × 403 vira oráculo), enumera "
               "e gasta a cota do fornecedor. O limite que existe em outra rota (login, edge function) "
               "não protege esta. Limite por IP na borda ou no handler, 429 com Retry-After. "
               f"Exemplos: {ex}")
    if sessao_busca:
        ex = "; ".join(f"{p} ({', '.join(m)})" for p, m in sessao_busca[:4])
        achado("04", "LOW", "rate_limit_rota_sessao", sessao_busca[0][0],
               f"{len(sessao_busca)} route handlers com sessão fazem busca ou consulta em lote sem rate limit",
               "Sessão válida não é volume razoável: uma conta (ou uma conta roubada) varre a base por "
               "busca curinga ou faz o servidor consultar o fornecedor em lote. Limite por usuário e "
               f"por janela. Exemplos: {ex}")
    cobertura("04", "rate_limit_rota", "medido",
              f"{len(rotas)} route handlers lidos com os imports locais"
              + (f"; sessão no {sessao_mw}, {len(publicos_mw)} prefixos públicos" if sessao_mw else "")
              + (f"; limitador global em {limite_global}" if limite_global else ""))
else:
    cobertura("04", "rate_limit_rota", "nao_medido", "sem route handler do Next (app/**/route.ts, pages/api)")

# ───────────────────────────── 04 · um segredo para várias famílias de rota
RE_ENV = re.compile(r"process\.env\.([A-Z][A-Z0-9_]*(?:SECRET|_KEY|TOKEN|SENHA|CHAVE)[A-Z0-9_]*)|"
                    r"process\.env\[\s*['\"]([A-Z][A-Z0-9_]*(?:SECRET|_KEY|TOKEN)[A-Z0-9_]*)['\"]\s*\]")
PUBLICAS_ENV = re.compile(r"^(NEXT_PUBLIC_|VITE_|PUBLIC_)|ANON_KEY|PUBLISHABLE|SUPABASE_URL")


def familia(p):
    partes = p.replace("\\", "/").split("/")
    if "api" in partes:
        i = partes.index("api")
        return "/".join(partes[i:i + 2])
    return os.path.dirname(p)


uso = {}
for p in rotas:
    _, arquivos = com_imports(p)
    for a in arquivos:
        ta = le(a)
        if not RE_MAQUINA.search(ta):
            continue  # env lida aqui é token de saída (chama um serviço), não prova de quem chama
        for m in RE_ENV.finditer(ta):
            nome = m.group(1) or m.group(2)
            if PUBLICAS_ENV.search(nome) or "SERVICE_ROLE" in nome:
                continue
            # mapa de chaves (uma por integração) já é a correção, não o problema
            if re.search(r"(CHAVES|KEYS|SECRETS|TOKENS)$", nome) or \
                    re.search(r"JSON\.parse\(\s*process\.env\.?\[?['\"]?" + nome, ta):
                continue
            uso.setdefault(nome, set()).add(p)
n_seg = 0
for nome, ps in sorted(uso.items()):
    fams = {familia(p) for p in ps}
    if len(ps) >= 4 and len(fams) >= 2:
        n_seg += 1
        achado("04", "LOW", "segredo_compartilhado", sorted(ps)[0],
               f"{nome} autentica {len(ps)} rotas em {len(fams)} famílias",
               "Um segredo de máquina para famílias diferentes (ingestão, webhook, automação) faz quem "
               "tem a chave de uma integração alcançar todas. Um segredo por família (ou por "
               "integração), com a lista de rotas que cada um abre. Famílias: "
               + ", ".join(sorted(fams)[:5]))
if rotas:
    cobertura("04", "segredo_compartilhado", "medido", f"{len(uso)} envs de segredo lidas nas rotas")

# ───────────────────────────── 01 · COOP / CORP onde os headers são declarados
fontes_h = [f for f in ("next.config.ts", "next.config.js", "next.config.mjs", "vercel.json", "public/_headers",
                        "netlify.toml") + tuple(mw) if os.path.isfile(f)]
if fontes_h:
    txt = "\n".join(le(f) for f in fontes_h)
    declara = re.search(r"x-frame-options|x-content-type-options|strict-transport-security|content-security-policy|"
                        r"referrer-policy|headers\s*\(", txt, re.I)
    if declara:
        falta = [h for h in ("Cross-Origin-Opener-Policy", "Cross-Origin-Resource-Policy")
                 if not re.search(h, txt, re.I)]
        if falta:
            achado("01", "LOW", "headers_isolamento", fontes_h[0],
                   f"Headers de isolamento ausentes: {', '.join(falta)}",
                   "Sem COOP, uma aba aberta por window.open de outro site mantém referência à sua "
                   "(tabnabbing, vazamento entre janelas); sem CORP, outro site embute seus recursos "
                   "autenticados. Valores comuns: Cross-Origin-Opener-Policy: same-origin (ou "
                   "same-origin-allow-popups se o login abre popup de OAuth) e "
                   "Cross-Origin-Resource-Policy: same-origin. Teste o login social antes de ligar.")
        if re.search(r"strict-transport-security", txt, re.I) and not re.search(r"preload", txt, re.I):
            achado("01", "INFO", "hsts_sem_preload", fontes_h[0], "HSTS declarado sem preload",
                   "Sem preload, a primeira visita ainda pode sair em HTTP. Só some preload depois de "
                   "garantir HTTPS em todos os subdomínios (includeSubDomains), e envie para hstspreload.org.")
        cobertura("01", "headers_isolamento", "medido", "lidos: " + ", ".join(fontes_h))
    else:
        cobertura("01", "headers_isolamento", "nao_medido",
                  "nenhum header declarado no repo: a borda pode injetar; confira com curl -sSI")
else:
    cobertura("01", "headers_isolamento", "nao_medido", "sem next.config/vercel.json/_headers")

# ───────────────────────────── 08 · robots.txt e security.txt
if APPS or os.path.isdir("public"):
    def existe(*cands):
        return next((c for c in cands if os.path.exists(c)), None)

    robots = existe("public/robots.txt", "src/app/robots.ts", "src/app/robots.js", "app/robots.ts", "app/robots.js",
                    "src/app/robots.txt", "app/robots.txt")
    sec = existe("public/.well-known/security.txt", "src/app/.well-known/security.txt",
                 "app/.well-known/security.txt", "public/security.txt")
    if not robots:
        achado("08", "LOW", "robots_txt", "public/robots.txt", "Sem robots.txt",
               "Sem o arquivo, o caminho cai na rota padrão (num app atrás de login, 307 para /login). "
               "App interno: Disallow: / para o crawler não indexar telas de login e links por token. "
               "Se o middleware roda em tudo, exclua /robots.txt do matcher, senão o arquivo nunca é servido.")
    if not sec:
        achado("08", "INFO", "security_txt", "public/.well-known/security.txt", "Sem /.well-known/security.txt",
               "RFC 9116: diz a quem achou uma falha para onde mandar (Contact:, Expires:). Sem ele, o "
               "relato vai para o suporte ou para lugar nenhum. Mesmo cuidado com o matcher do middleware.")
    cobertura("08", "robots_security_txt", "medido",
              f"robots: {robots or 'ausente'}; security.txt: {sec or 'ausente'}. Servido de verdade só o "
              "curl prova (o middleware pode redirecionar): sonda-auth-viva.sh")

print("\n".join(SAIDA))
