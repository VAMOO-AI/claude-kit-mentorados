#!/usr/bin/env python3
"""Gera o PDF da auditoria de seguranca a partir de um findings.json.

Sem dependencia externa: stdlib + um navegador Chromium ja instalado.
HTML -> servidor HTTP local efemero -> Chrome headless --print-to-pdf.

O servidor existe por um motivo unico: o rodape nativo do Chrome (o unico que
sabe numerar "3/12") imprime a URL do documento. Servindo por HTTP o rodape
mostra o nome do relatorio; abrindo file:// ele mostraria o caminho absoluto da
maquina de quem gerou -- vazamento gratuito num PDF que vai pro cliente.

  python3 gerar-relatorio.py findings.json --out docs/security-audit/relatorio.pdf
  python3 gerar-relatorio.py findings.json --out ... --html-only   # so o HTML
  python3 gerar-relatorio.py findings.json --verificar --raiz .    # confere contra o repo

O --verificar cobra o que o schema promete em prosa e ninguem confere sozinho:
arquivo existe, linhas cabem nele, trecho foi copiado (nao reescrito de memoria),
corroborado tem fonte, falso positivo tem motivo, lead a validar tem bloqueio e
plano, issue cita achado que existe. Sem --raiz ele confere so' o JSON e avisa
que o codigo NAO foi conferido.
"""

import argparse
import functools
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

SEV = {
    "critica": ("Crítica", "#B91C1C"),
    "alta":    ("Alta",    "#EA580C"),
    "media":   ("Média",   "#D97706"),
    "baixa":   ("Baixa",   "#2563EB"),
    "informativa": ("Informativa", "#64748B"),
}
ORDEM_SEV = ["critica", "alta", "media", "baixa", "informativa"]
VERDE = "#059669"

# --------------------------------------------------------------------------- evidencia
# O nivel de evidencia e' a distancia entre "o padrao casou" e "eu abri o arquivo
# e o caminho e' explorave". Sem esse eixo, o PDF trata um grep e uma leitura com
# o mesmo peso, e a issue volta como "nao reproduz".
EVIDENCIA = {
    "padrao":      ("Padrão casou", "#94A3B8"),
    "lido":        ("Lido",         "#2563EB"),
    "corroborado": ("Corroborado",  "#059669"),
}
ORDEM_EVID = ["corroborado", "lido", "padrao"]
CONF_BASE = {"padrao": 0.45, "lido": 0.70, "corroborado": 0.90}
# Teto por nivel: confianca declarada nunca ultrapassa o que a evidencia sustenta.
# "O grep casou" com confianca 0,95 e' exatamente o erro que o teto existe para
# impedir -- inclusive quando quem declarou foi um modelo.
CONF_TETO = {"padrao": 0.60, "lido": 0.85, "corroborado": 1.00}
CONF_PISO = 0.10

STATUS_NAO_ACIONAVEL = {"corrigido", "falso_positivo", "risco_aceito", "aceito_por_design",
                        "a_validar"}
STATUS_ROTULO = {
    "aberto": "Aberto",
    "corrigido": "Corrigido",
    "falso_positivo": "Falso positivo",
    "risco_aceito": "Risco aceito",
    "aceito_por_design": "Aceito por design",
    "a_validar": "A validar",
}
# Tirar um achado do veredito e' decisao, e decisao sem justificativa escrita e'
# a mesma discussao voltando na auditoria seguinte.
STATUS_COM_MOTIVO = {"falso_positivo", "risco_aceito", "aceito_por_design"}

# 'a_validar' e' hipotese bloqueada por fato que o codigo nao mostra (header do
# proxy, config do provedor, policy do deploy). Nao recebe severidade no calculo:
# a 'severidade' declarada e' potencial, e so' serve para impedir que uma critica
# pendente saia LIBERADO.
CONDICAO_TIPO = {
    "autenticacao": "Nível de autenticação",
    "papel": "Papel ou permissão",
    "interacao": "Interação do usuário",
    "configuracao": "Configuração do sistema",
    "rede": "Rota ou rede",
    "dependencia": "Dependência externa",
    "estado": "Estado do dado",
    "tempo": "Janela de tempo",
}
CAMINHO_TIPO = {"entrada": "Entrada", "propagacao": "Propagação", "sink": "Sink"}

# --------------------------------------------------------------------------- compliance
# Rastreabilidade: cada achado aponta para quais controles de framework ele viola.
# Etiqueta sobre o achado ja' provado -- nao muda severidade nem veredito. Mapa e
# justificativa de cada controle em references/compliance-map.md. Controle que nao
# casa com o formato da norma vigente aborta o gerador, com ou sem --verificar:
# control ID inventado ou de versao aposentada nao vai para PDF de cliente.
COMPLIANCE_FRAMEWORKS = {
    "OWASP":     "OWASP Top 10:2025",
    "OWASP-API": "OWASP API Security Top 10:2023",
    "OWASP-LLM": "OWASP Top 10 for LLM Applications 2025",
    "ISO27001":  "ISO/IEC 27001:2022 (Anexo A)",
    "NIST-CSF":  "NIST CSF 2.0",
    "SOC2":      "SOC 2 (Trust Services Criteria)",
    "PCI-DSS":   "PCI DSS v4.0.1",
    "LGPD":      "LGPD (Lei 13.709/2018)",
}
ORDEM_FRAMEWORK = list(COMPLIANCE_FRAMEWORKS.keys())
# Formato de controle por framework, na versao vigente. Fecha o intervalo onde a
# norma fecha (ISO para em A.8.34, CSF 2.0 tem 22 categorias, LGPD tem 65 artigos).
COMPLIANCE_FORMATO = {
    "OWASP":     re.compile(r"A(0[1-9]|10):2025"),
    "OWASP-API": re.compile(r"API([1-9]|10):2023"),
    "OWASP-LLM": re.compile(r"LLM(0[1-9]|10):2025"),
    "ISO27001":  re.compile(r"A\.(5\.([1-9]|[12]\d|3[0-7])|6\.[1-8]|7\.([1-9]|1[0-4])"
                            r"|8\.([1-9]|[12]\d|3[0-4]))"),
    "NIST-CSF":  re.compile(r"(GV\.(OC|RM|RR|PO|OV|SC)|ID\.(AM|RA|IM)|PR\.(AA|AT|DS|PS|IR)"
                            r"|DE\.(CM|AE)|RS\.(MA|AN|CO|MI)|RC\.(RP|CO))(-\d{2})?"),
    "SOC2":      re.compile(r"CC(1\.[1-5]|2\.[1-3]|3\.[1-4]|4\.[12]|5\.[1-3]|6\.[1-8]"
                            r"|7\.[1-5]|8\.1|9\.[12])|A1\.[1-3]|C1\.[12]|PI1\.[1-5]"
                            r"|P[1-8]\.[1-7]"),
    "PCI-DSS":   re.compile(r"([1-9]|1[0-2])(\.\d{1,2}){0,3}"),
    "LGPD":      re.compile(r"Art\.([1-9]|[1-5]\d|6[0-5])"),
}
# Default por categoria: todo achado herda estes controles quando nao declara
# 'compliance' proprio. Subtipos (SSRF, chave de assinatura, deputado confuso) e
# dado pessoal (LGPD) entram por override no achado -- tabela no compliance-map.md.
COMPLIANCE_CATEGORIA = {
    "A1": ["OWASP:A01:2025", "OWASP-API:API1:2023", "ISO27001:A.8.3",
           "NIST-CSF:PR.AA", "SOC2:CC6.1", "PCI-DSS:7.2"],
    "A2": ["OWASP:A01:2025", "OWASP-API:API5:2023", "ISO27001:A.8.2",
           "NIST-CSF:PR.AA", "SOC2:CC6.3", "PCI-DSS:7.2"],
    "A3": ["OWASP:A01:2025", "OWASP-API:API1:2023", "ISO27001:A.8.3",
           "NIST-CSF:PR.AA", "SOC2:CC6.1", "PCI-DSS:7.2"],
    "A4": ["OWASP:A07:2025", "ISO27001:A.5.17", "NIST-CSF:PR.AA",
           "SOC2:CC6.1", "PCI-DSS:8.6.2"],
    "A5": ["OWASP:A05:2025", "ISO27001:A.8.28", "NIST-CSF:PR.PS", "PCI-DSS:6.2.4"],
    "A6": ["OWASP-LLM:LLM01:2025", "OWASP-LLM:LLM06:2025", "OWASP:A01:2025",
           "ISO27001:A.8.2", "NIST-CSF:PR.AA", "SOC2:CC6.3"],
}

VEREDITO = {
    "BLOQUEADO": ("Bloqueado", "#B91C1C"),
    "REVISAR":   ("Revisar",   "#D97706"),
    "LIBERADO":  ("Liberado",  "#059669"),
}

FERRAMENTA_ESTADO = {
    "executado":     ("Executado",     VERDE),
    "nao_aplicavel": ("Não aplicável", "#64748B"),
    "nao_instalado": ("Não instalado", "#B91C1C"),
    "falhou":        ("Falhou",        "#B91C1C"),
}
# Ferramenta que nao rodou deixa superficie sem medida: ausencia de achado ali nao
# e' evidencia de nada, e o PDF precisa dizer isso em vez de deixar o leitor supor.
ESTADO_SEM_MEDIDA = {"nao_instalado", "falhou"}

# --------------------------------------------------------------------------- redacao
# O relatorio copia trecho literal do codigo e a categoria A4 e' sobre segredo
# exposto: sem isto, o PDF entregue ao cliente vira o vazamento que ele denuncia.
PADROES_SEGREDO = [
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----",
                re.S), "[CHAVE PRIVADA REDIGIDA]"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}"),
     "[JWT REDIGIDO]"),
    (re.compile(r"\b(?:sk|rk)-[A-Za-z0-9_-]{16,}"), "[CHAVE REDIGIDA]"),
    (re.compile(r"\b(?:sbp|sbs|ghp|gho|ghu|ghs|ghr|glpat|xoxb|xoxp|xapp|shpat)[-_]"
                r"[A-Za-z0-9_-]{12,}"), "[TOKEN REDIGIDO]"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "[CHAVE AWS REDIGIDA]"),
]
# O prefixo opcional cobre POSTGRES_PASSWORD, DB_PASSWORD, JWT_SECRET e afins:
# sem ele o \b encosta no _ do meio do nome e a chave escapa da redacao.
_CHAVE = (r"(?:[A-Za-z0-9]+[_-])?"
          r"(?:api[_-]?key|secret|token|passwd|password|senha|private[_-]?key)")
# Atribuicao com literal entre aspas: alta precisao, redige sempre.
_ATRIB_ASPAS = re.compile(r"(?i)\b(" + _CHAVE + r"[\"']?\s*[:=>]{1,2}\s*)([\"'])([^\"'\n]{8,})\2")
# Mesma atribuicao sem aspas. A classe do valor exclui ., (, $ e { de proposito:
# req.body.password e ${VAR:-default} sao codigo e referencia, nao segredo -- e o
# default publico do compose e' justamente a evidencia que precisa aparecer.
_ATRIB_NUA = re.compile(
    r"(?i)\b(" + _CHAVE + r"\s*[:=]\s*)([A-Za-z0-9_@#!%^&*+=/~-]{8,})(?=\s|$|[,;])")


def redigir_segredos(texto):
    """Mascara segredo em trecho de codigo. Devolve (texto, quantidade_mascarada)."""
    if not texto:
        return texto, 0
    total = 0
    for padrao, marca in PADROES_SEGREDO:
        texto, n = padrao.subn(marca, texto)
        total += n
    texto, n = _ATRIB_ASPAS.subn(r"\1\2[SEGREDO REDIGIDO]\2", texto)
    total += n
    texto, n = _ATRIB_NUA.subn(r"\1[SEGREDO REDIGIDO]", texto)
    total += n
    return texto, total

CHROMES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
]


def achar_chrome():
    for nome in ("google-chrome", "chromium", "chromium-browser", "brave-browser",
                 "microsoft-edge", "google-chrome-stable"):
        p = shutil.which(nome)
        if p:
            return p
    for p in CHROMES:
        if os.path.exists(p):
            return p
    return None


def e(txt):
    return html.escape(str(txt if txt is not None else ""))


def num(valor):
    """Numero com virgula decimal, que e' como o leitor do relatorio escreve."""
    return f"{valor:.2f}".replace(".", ",")


# --------------------------------------------------------------------------- evidencia

def nivel_evidencia(a):
    """Nivel declarado, com 'padrao' como default deliberado.

    Quem nao declarou nao confirmou: o default conservador forca a declaracao em
    vez de presumir leitura que ninguem fez.
    """
    nivel = str(a.get("evidencia", "padrao")).strip().lower()
    return nivel if nivel in EVIDENCIA else "padrao"


def confianca(a):
    """Confianca efetiva do achado, limitada pelo teto do nivel de evidencia."""
    nivel = nivel_evidencia(a)
    bruta = a.get("confianca")
    if bruta is None:
        return CONF_BASE[nivel]
    try:
        bruta = float(bruta)
    except (TypeError, ValueError):
        return CONF_BASE[nivel]
    return round(max(CONF_PISO, min(CONF_TETO[nivel], bruta)), 2)


def status_achado(a):
    st = str(a.get("status", "aberto")).strip().lower()
    return st if st in STATUS_ROTULO else "aberto"


def acionavel(a):
    return status_achado(a) not in STATUS_NAO_ACIONAVEL


def framework_de(controle):
    """Prefixo de framework de um control ID ('OWASP:A01:2025' -> 'OWASP')."""
    return str(controle).split(":", 1)[0].strip()


def erros_compliance(a):
    """Problemas do campo 'compliance' de um achado: nao-lista, framework fora da
    lista ou controle fora do formato da norma vigente. Lista vazia = ok."""
    ident = a.get("id", "?")
    comp = a.get("compliance")
    if comp is None:
        return []
    if not isinstance(comp, list):
        return [f"achado {ident}: 'compliance' deve ser lista de \"FRAMEWORK:CONTROLE\", "
                f"veio {type(comp).__name__}"]
    erros = []
    for c in comp:
        fw, _, ctrl = str(c).partition(":")
        fw, ctrl = fw.strip(), ctrl.strip()
        if fw not in COMPLIANCE_FRAMEWORKS:
            erros.append(f"achado {ident}: controle {c!r} com framework desconhecido "
                         f"— use {', '.join(COMPLIANCE_FRAMEWORKS)}")
        elif not COMPLIANCE_FORMATO[fw].fullmatch(ctrl):
            dica = (" — o OWASP Top 10 vigente e' o 2025; remapeie pelo compliance-map.md"
                    if fw == "OWASP" and ctrl.endswith(":2021") else "")
            erros.append(f"achado {ident}: controle {c!r} nao existe em "
                         f"{COMPLIANCE_FRAMEWORKS[fw]}{dica}")
    return erros


def compliance_do_achado(a):
    """Controles do achado: os declarados em 'compliance', senao o default da
    categoria. Lista vazia quando nem um nem outro existe (categoria fora do mapa)."""
    decl = a.get("compliance")
    if isinstance(decl, list) and decl:
        return [str(c).strip() for c in decl if str(c).strip()]
    return list(COMPLIANCE_CATEGORIA.get(str(a.get("categoria", "")).strip().upper(), []))


def cobertura_compliance(achados):
    """Agrega controles -> ids de achado acionavel, agrupado por framework.

    Devolve OrderedDict {framework: {controle: [ids]}} na ordem de ORDEM_FRAMEWORK,
    controles ordenados. So conta achado acionavel: falso positivo e risco aceito
    nao 'violam' controle."""
    from collections import OrderedDict
    bruto = {}
    for a in achados:
        if not acionavel(a):
            continue
        aid = a.get("id", "?")
        for c in compliance_do_achado(a):
            bruto.setdefault(c, [])
            if aid not in bruto[c]:
                bruto[c].append(aid)
    por_fw = OrderedDict()
    for fw in ORDEM_FRAMEWORK:
        controles = {c: ids for c, ids in bruto.items() if framework_de(c) == fw}
        if controles:
            por_fw[fw] = OrderedDict(sorted(controles.items()))
    return por_fw


def calcular_veredito(achados):
    """Veredito deterministico da auditoria. Devolve (chave, motivo).

    Regra, na ordem: critica com confianca >= 0,50 bloqueia; alta corroborada ou
    com confianca >= 0,70 bloqueia; critica ainda nao confirmada, alta restante e
    media pedem revisao. Achado nao acionavel (corrigido, falso positivo, risco
    aceito) nao pesa.

    Severidade sozinha nao decide: 'alta' que so' bateu num grep vai para revisao,
    nao para bloqueio. E' o que separa o veredito de uma contagem de chips. O
    inverso tambem vale: critica sem confirmacao nunca sai LIBERADO -- confianca
    baixa e' motivo para ir confirmar, nao para dar o assunto por encerrado.
    """
    gate, motivo = "LIBERADO", "Nenhum achado acionável acima do limiar de política."
    for a in achados:
        if status_achado(a) == "a_validar":
            # Hipotese, nao achado: nao bloqueia. Mas critica potencial pendente
            # nunca deixa o veredito sair LIBERADO -- o bloqueio e' para resolver.
            if a.get("severidade") == "critica" and gate == "LIBERADO":
                gate, motivo = "REVISAR", (f"{a.get('id', '?')}: crítica potencial a validar — "
                                           f"resolva o bloqueio antes de liberar.")
            continue
        if not acionavel(a):
            continue
        sev = a.get("severidade", "informativa")
        nivel, cf = nivel_evidencia(a), confianca(a)
        rotulo = f"{a.get('id', '?')} ({SEV.get(sev, ('?',))[0].lower()}, confiança {num(cf)})"
        if sev == "critica":
            if cf >= 0.50:
                return "BLOQUEADO", f"{rotulo}: crítica com confiança suficiente."
            if gate == "LIBERADO":
                gate, motivo = "REVISAR", f"{rotulo}: crítica ainda não confirmada — confirme antes de liberar."
        elif sev == "alta":
            if nivel == "corroborado":
                return "BLOQUEADO", f"{rotulo}: alta corroborada por segunda fonte."
            if cf >= 0.70:
                return "BLOQUEADO", f"{rotulo}: alta com confiança ≥ 0,70."
            if gate == "LIBERADO":
                gate, motivo = "REVISAR", f"{rotulo}: alta ainda não confirmada por leitura."
        elif sev == "media" and gate == "LIBERADO":
            gate, motivo = "REVISAR", f"{rotulo}: média aberta."
    return gate, motivo


def trecho_redigido(a):
    """Trecho do achado ja' mascarado. 'redacao': false desliga, para o caso em que
    o valor literal E' a evidencia (default publico versionado, por exemplo)."""
    trecho = a.get("trecho")
    if not trecho or a.get("redacao") is False:
        return trecho, 0
    return redigir_segredos(trecho)


# --------------------------------------------------------------------------- SVG

def donut(contagem, raio=78, espessura=30):
    """Rosca por severidade. Sem lib: um circle por fatia com stroke-dasharray."""
    total = sum(contagem.values())
    cx = cy = raio + espessura / 2 + 2
    circ = 2 * 3.14159265 * raio
    if total == 0:
        return (f'<svg viewBox="0 0 {cx*2} {cy*2}" width="200" height="200">'
                f'<circle cx="{cx}" cy="{cy}" r="{raio}" fill="none" stroke="#E2E8F0" '
                f'stroke-width="{espessura}"/>'
                f'<text x="{cx}" y="{cy+6}" text-anchor="middle" font-size="20" '
                f'fill="#0F172A">0</text></svg>')
    partes, offset = [], 0.0
    for chave in ORDEM_SEV:
        n = contagem.get(chave, 0)
        if not n:
            continue
        frac = n / total
        dash = circ * frac
        partes.append(
            f'<circle cx="{cx}" cy="{cy}" r="{raio}" fill="none" stroke="{SEV[chave][1]}" '
            f'stroke-width="{espessura}" stroke-dasharray="{dash:.2f} {circ - dash:.2f}" '
            f'stroke-dashoffset="{-offset:.2f}" transform="rotate(-90 {cx} {cy})"/>')
        offset += dash
    return (f'<svg viewBox="0 0 {cx*2} {cy*2}" width="200" height="200">' + "".join(partes) +
            f'<text x="{cx}" y="{cy-2}" text-anchor="middle" font-size="34" font-weight="700" '
            f'fill="#0F172A">{total}</text>'
            f'<text x="{cx}" y="{cy+20}" text-anchor="middle" font-size="12" '
            f'fill="#64748B">achados</text></svg>')


def barras(por_categoria, cats):
    """Barras horizontais por categoria, empilhadas por severidade."""
    if not por_categoria:
        return '<p class="vazio">Sem achados para plotar.</p>'
    largura, alt_barra, gap, pad_esq = 500, 26, 14, 168
    maximo = max(sum(v.values()) for v in por_categoria.values()) or 1
    altura = len(por_categoria) * (alt_barra + gap) + 22
    linhas = []
    for i, (cat, sevs) in enumerate(por_categoria.items()):
        y = i * (alt_barra + gap)
        rotulo = cats.get(cat, cat)
        if len(rotulo) > 27:
            rotulo = rotulo[:26] + "…"
        linhas.append(f'<text x="0" y="{y+18}" font-size="10.5" fill="#334155">{e(rotulo)}</text>')
        x = pad_esq
        for chave in ORDEM_SEV:
            n = sevs.get(chave, 0)
            if not n:
                continue
            w = (largura - pad_esq) * n / maximo
            linhas.append(f'<rect x="{x:.1f}" y="{y}" width="{w:.1f}" height="{alt_barra}" '
                          f'fill="{SEV[chave][1]}" rx="2"/>')
            if w > 16:
                linhas.append(f'<text x="{x+w/2:.1f}" y="{y+17}" text-anchor="middle" '
                              f'font-size="11" fill="#fff" font-weight="600">{n}</text>')
            x += w + 1.5
        total = sum(sevs.values())
        linhas.append(f'<text x="{x+6:.1f}" y="{y+18}" font-size="11" fill="#64748B">{total}</text>')
    return (f'<svg viewBox="0 0 {largura+30} {altura}" width="100%" '
            f'style="max-width:{largura+30}px">' + "".join(linhas) + "</svg>")


def legenda(contagem):
    itens = []
    for chave in ORDEM_SEV:
        n = contagem.get(chave, 0)
        if not n:
            continue
        itens.append(f'<li><span class="ponto" style="background:{SEV[chave][1]}"></span>'
                     f'{SEV[chave][0]} <b>{n}</b></li>')
    return '<ul class="legenda">' + "".join(itens) + "</ul>" if itens else ""


# --------------------------------------------------------------------------- HTML

def chip(sev):
    rotulo, cor = SEV.get(sev, ("?", "#64748B"))
    return f'<span class="chip" style="background:{cor}">{rotulo}</span>'


def chip_evidencia(a):
    nivel = nivel_evidencia(a)
    rotulo, cor = EVIDENCIA[nivel]
    return (f'<span class="chip chip-ev" style="border-color:{cor};color:{cor}">'
            f'{rotulo}</span>')


def selo_status(a):
    st = status_achado(a)
    if st == "aberto":
        return ""
    return f'<span class="selo">{e(STATUS_ROTULO[st])}</span>'


def bloco_veredito(chave, motivo, suprimidos=0):
    rotulo, cor = VEREDITO[chave]
    extra = ""
    if suprimidos:
        plural = "s" if suprimidos > 1 else ""
        extra = (f'<div class="vd-extra">{suprimidos} achado{plural} não acionável'
                 f'{plural} (corrigido, falso positivo ou risco aceito) fora do cálculo.</div>')
    return (f'<div class="veredito" style="border-color:{cor}">'
            f'<div class="vd-sel" style="background:{cor}">{rotulo}</div>'
            f'<div class="vd-txt"><b>Veredito da auditoria</b>'
            f'<div>{e(motivo)}</div>{extra}</div></div>')


def local_html(a):
    """arquivo:linha com o intervalo indivisivel — quebrar "88-96" em duas linhas
    torna a referencia inutil para quem vai abrir o arquivo."""
    arq = e(a.get("arquivo", ""))
    if not a.get("linhas"):
        return arq
    return f'{arq}<span style="white-space:nowrap">:{e(a["linhas"])}</span>'


def bloco_codigo(trecho):
    if not trecho:
        return ""
    return f'<pre class="codigo">{e(trecho)}</pre>'


def bloco_caminho(caminho):
    """Entrada -> propagacao -> sink, cada passo com arquivo:linha.

    Um achado que nao comeca numa entrada de menor confianca e nao termina no
    sink e' um trecho suspeito, nao um caminho explorave -- e e' o caminho que
    quem corrige precisa refazer."""
    itens = []
    for passo in caminho or []:
        tipo = CAMINHO_TIPO.get(str(passo.get("tipo", "")).lower(), passo.get("tipo", "?"))
        local = e(passo.get("arquivo", ""))
        if passo.get("linha"):
            local += f'<span style="white-space:nowrap">:{e(passo["linha"])}</span>'
        itens.append(f'<li><b>{e(tipo)}</b> <code class="arq">{local}</code>'
                     f' — {e(passo.get("descricao", ""))}</li>')
    if not itens:
        return ""
    return '<div class="campo"><b>Caminho:</b><ol class="caminho">' + "".join(itens) + "</ol></div>"


def condicoes_html(cond):
    """Aceita texto livre (formato antigo) ou lista de {tipo, descricao}."""
    if not cond:
        return ""
    if isinstance(cond, str):
        return e(cond)
    partes = []
    for c in cond:
        if isinstance(c, str):
            partes.append(e(c))
            continue
        tipo = CONDICAO_TIPO.get(str(c.get("tipo", "")).lower(), c.get("tipo", ""))
        partes.append((f"<b>{e(tipo)}:</b> " if tipo else "") + e(c.get("descricao", "")))
    return "; ".join(partes)


def bloco_a_validar(a):
    plano = a.get("plano_validacao") or {}
    p = ['<div class="achado">']
    sev = a.get("severidade")
    p.append(f'<div class="cab">{chip(sev) if sev else ""}'
             f'<span class="id">{e(a.get("id", ""))}</span>'
             f'<b>{e(a.get("titulo", ""))}</b><span class="selo">A validar</span></div>')
    if sev:
        p.append('<div class="campo" style="color:#64748B;font-size:9pt">Severidade '
                 'potencial: só vale depois que o bloqueio for resolvido.</div>')
    p.append(f'<div class="campo arq"><b>Local:</b> <code>{local_html(a)}</code></div>')
    p.append(bloco_caminho(a.get("caminho")))
    if a.get("trecho"):
        texto, _ = trecho_redigido(a)
        p.append(bloco_codigo(texto))
    if a.get("por_que"):
        p.append(f'<div class="campo"><b>Hipótese:</b> {e(a["por_que"])}</div>')
    p.append(f'<div class="campo"><b>O que falta saber:</b> {e(a.get("bloqueio", ""))}</div>')
    if plano.get("local"):
        p.append(f'<div class="campo"><b>Como resolver localmente:</b> {e(plano["local"])}</div>')
    if plano.get("dono"):
        p.append(f'<div class="campo"><b>O que o dono do deploy confere:</b> {e(plano["dono"])}</div>')
    p.append("</div>")
    return "".join(p)


def montar_html(d, redacoes=None):
    projeto = d.get("projeto", "projeto")
    titulo = f"Relatório de Auditoria de Segurança — {projeto}"
    todos = d.get("achados", [])
    # Lead a validar nao e' achado: sai da rosca, das barras e da tabela, e ganha
    # secao propria. Mistura-lo com os confirmados e' contar hipotese como falha.
    a_validar = [a for a in todos if status_achado(a) == "a_validar"]
    achados = [a for a in todos if status_achado(a) != "a_validar"]
    # lista de um elemento para servir de contador compartilhado com as issues
    redacoes = redacoes if redacoes is not None else [0]
    cats = {c["id"]: c.get("nome", c["id"]) for c in d.get("categorias", [])}

    contagem = {}
    # semeado na ordem declarada das categorias: sem isto a barra sai na ordem em
    # que o primeiro achado de cada categoria aparece, e discorda do resto do PDF.
    por_categoria = {c["id"]: {} for c in d.get("categorias", [])}
    for a in achados:
        s = a.get("severidade", "informativa")
        contagem[s] = contagem.get(s, 0) + 1
        cat = a.get("categoria", "?")
        por_categoria.setdefault(cat, {})
        por_categoria[cat][s] = por_categoria[cat].get(s, 0) + 1

    ordem = {k: i for i, k in enumerate(ORDEM_SEV)}
    achados_ord = sorted(achados, key=lambda a: (ordem.get(a.get("severidade"), 9),
                                                 a.get("categoria", ""), a.get("arquivo", "")))

    gate, motivo_gate = calcular_veredito(todos)
    suprimidos = sum(1 for a in achados if not acionavel(a))
    ferramentas = d.get("ferramentas", [])
    sem_medida = [f for f in ferramentas
                  if str(f.get("estado", "")).strip().lower() in ESTADO_SEM_MEDIDA]

    p = []
    p.append(f"""<!DOCTYPE html><html lang="pt-BR"><head><meta charset="utf-8">
<title>{e(titulo)}</title><style>
@page {{ size: A4; margin: 2cm 1.8cm; }}
* {{ box-sizing: border-box; }}
body {{ font-family: -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
       color: #0F172A; font-size: 10.5pt; line-height: 1.5; margin: 0; }}
h1 {{ font-size: 22pt; margin: 0 0 6px; letter-spacing: -.4px; }}
h2 {{ font-size: 15pt; margin: 26px 0 10px; padding-bottom: 6px;
     border-bottom: 2px solid #0F172A; letter-spacing: -.2px; }}
h3 {{ font-size: 11.5pt; margin: 18px 0 6px; color: #1E293B; }}
p, li {{ margin: 6px 0; }}
.quebra {{ page-break-before: always; }}
.evitar-quebra {{ page-break-inside: avoid; }}
.capa {{ page-break-after: always; padding-top: 3.2cm; }}
.capa .faixa {{ height: 8px; background: linear-gradient(90deg,#B91C1C,#EA580C,#D97706,#2563EB);
               margin-bottom: 28px; }}
.capa .sub {{ color: #475569; font-size: 12pt; margin-top: 10px; }}
.meta {{ margin-top: 34px; border-top: 1px solid #CBD5E1; padding-top: 14px; }}
.meta dt {{ font-weight: 700; font-size: 9.5pt; text-transform: uppercase;
           letter-spacing: .5px; color: #64748B; margin-top: 12px; }}
.meta dd {{ margin: 3px 0 0; }}
.painel {{ display: flex; gap: 26px; align-items: center; flex-wrap: wrap; }}
.legenda {{ list-style: none; padding: 0; margin: 0; }}
.legenda li {{ font-size: 10pt; margin: 4px 0; }}
.ponto {{ display: inline-block; width: 10px; height: 10px; border-radius: 50%;
         margin-right: 7px; vertical-align: middle; }}
table {{ width: 100%; border-collapse: collapse; margin: 10px 0 18px; font-size: 9.5pt; }}
th {{ text-align: left; background: #F1F5F9; padding: 7px 8px; border-bottom: 2px solid #CBD5E1;
     font-size: 9pt; text-transform: uppercase; letter-spacing: .4px; color: #475569; }}
td {{ padding: 7px 8px; border-bottom: 1px solid #E2E8F0; vertical-align: top; }}
td.arq {{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 8.8pt;
         word-break: normal; overflow-wrap: anywhere; }}
.chip {{ color: #fff; font-size: 8.5pt; font-weight: 700; padding: 2px 8px; border-radius: 10px;
        display: inline-block; white-space: nowrap; }}
.chip-ev {{ background: #fff; border: 1px solid #94A3B8; font-weight: 600; font-size: 8pt; }}
.selo {{ background: #E2E8F0; color: #334155; font-size: 8pt; font-weight: 700; padding: 2px 7px;
        border-radius: 4px; text-transform: uppercase; letter-spacing: .3px; }}
.veredito {{ display: flex; gap: 14px; align-items: center; border: 2px solid #64748B;
            border-radius: 7px; padding: 12px 14px; margin: 12px 0 18px; page-break-inside: avoid; }}
.vd-sel {{ color: #fff; font-weight: 700; font-size: 13pt; letter-spacing: .5px; padding: 8px 16px;
          border-radius: 5px; white-space: nowrap; text-transform: uppercase; }}
.vd-txt {{ font-size: 9.8pt; }}
.vd-txt b {{ font-size: 10.5pt; }}
.vd-extra {{ color: #64748B; font-size: 9pt; margin-top: 3px; }}
.aviso {{ border-left: 4px solid #B91C1C; background: #FEF2F2; padding: 9px 13px; margin: 8px 0;
         border-radius: 0 4px 4px 0; font-size: 9.8pt; }}
.conf {{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 9pt; }}
.codigo {{ background: #0F172A; color: #E2E8F0; padding: 9px 11px; border-radius: 5px;
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 8.5pt;
          line-height: 1.45; overflow-wrap: break-word; white-space: pre-wrap; margin: 7px 0; }}
.forte {{ border-left: 4px solid {VERDE}; background: #ECFDF5; padding: 9px 13px; margin: 8px 0;
         border-radius: 0 4px 4px 0; }}
.fraco {{ border-left: 4px solid #B91C1C; background: #FEF2F2; padding: 9px 13px; margin: 8px 0;
         border-radius: 0 4px 4px 0; }}
.achado {{ page-break-inside: avoid; border: 1px solid #E2E8F0; border-radius: 6px;
          padding: 12px 14px; margin: 12px 0; }}
.achado .cab {{ display: flex; gap: 10px; align-items: baseline; margin-bottom: 4px; }}
.achado .cab .id {{ font-weight: 700; color: #64748B; font-size: 9pt; }}
.achado .campo {{ margin: 6px 0; font-size: 9.8pt; }}
.achado .campo b {{ color: #475569; }}
.issue {{ background: #F8FAFC; border: 1px dashed #94A3B8; border-radius: 5px; padding: 10px 13px;
         margin: 12px 0; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
         font-size: 8.6pt; white-space: pre-wrap; word-wrap: break-word; page-break-inside: avoid; }}
.vazio {{ color: #64748B; font-style: italic; }}
.nota {{ background: #F8FAFC; border: 1px solid #E2E8F0; padding: 10px 13px; border-radius: 5px;
        font-size: 9.8pt; }}
.prio {{ font-weight: 700; color: #0F172A; }}
.caminho {{ margin: 4px 0 0; padding-left: 18px; font-size: 9.4pt; }}
.caminho li {{ margin: 2px 0; }}
.hard {{ border-left: 4px solid #64748B; background: #F8FAFC; padding: 9px 13px; margin: 8px 0;
        border-radius: 0 4px 4px 0; }}
</style></head><body>""")

    # ---- capa
    p.append('<div class="capa"><div class="faixa"></div>')
    p.append(f"<h1>Relatório de Auditoria de Segurança</h1>")
    p.append(f'<div class="sub">{e(projeto)}</div>')
    p.append('<dl class="meta">')
    p.append(f"<dt>Data</dt><dd>{e(d.get('data',''))}</dd>")
    p.append(f"<dt>Veredito</dt><dd><b style=\"color:{VEREDITO[gate][1]}\">"
             f"{VEREDITO[gate][0]}</b> — {e(motivo_gate)}</dd>")
    escopo = d.get("escopo", [])
    p.append("<dt>Escopo auditado</dt><dd>" +
             (e(", ".join(escopo)) if isinstance(escopo, list) else e(escopo)) + "</dd>")
    stack = d.get("stack", {})
    if stack:
        linhas = "".join(f"<div><b>{e(k)}:</b> {e(v)}</div>" for k, v in stack.items())
        p.append(f"<dt>Stack detectada</dt><dd>{linhas}</dd>")
    if d.get("nota_metodologica"):
        p.append(f"<dt>Nota metodológica</dt><dd>{e(d['nota_metodologica'])}</dd>")
    anterior = d.get("auditoria_anterior")
    if anterior:
        partes = [x for x in (anterior.get("data"), anterior.get("arquivo"), anterior.get("nota")) if x]
        p.append(f"<dt>Auditoria anterior</dt><dd>{e(' · '.join(partes))}</dd>")
    else:
        p.append("<dt>Auditoria anterior</dt><dd>Nenhuma: esta é a primeira auditoria registrada "
                 "no repositório. Uma rodada não esgota o alvo.</dd>")
    p.append("</dl></div>")

    # ---- resumo executivo
    p.append("<h2>Resumo executivo</h2>")
    p.append(bloco_veredito(gate, motivo_gate, suprimidos))
    if d.get("resumo"):
        p.append(f"<p>{e(d['resumo'])}</p>")
    p.append('<div class="painel"><div>' + donut(contagem) + "</div><div>" +
             (legenda(contagem) or '<p class="vazio">Nenhum achado registrado.</p>') +
             (f'<p style="color:#64748B;font-size:9.5pt">+ {len(a_validar)} hipótese(s) a validar, '
              f'sem severidade, fora da contagem.</p>' if a_validar else "") +
             "</div></div>")
    p.append("<h3>Achados por categoria</h3>")
    p.append(barras(por_categoria, cats))

    # ---- cobertura
    cobertura = d.get("cobertura", [])
    if cobertura:
        p.append("<h3>Cobertura da auditoria</h3>")
        p.append("<table><tr><th>Categoria</th><th>Estado</th><th>Como foi medido</th></tr>")
        for c in cobertura:
            p.append(f"<tr><td>{e(cats.get(c.get('categoria'), c.get('categoria')))}</td>"
                     f"<td>{e(c.get('estado',''))}</td><td>{e(c.get('medido',''))}</td></tr>")
        p.append("</table>")

    # ---- ferramentas
    if ferramentas:
        p.append("<h3>Ferramentas da auditoria</h3>")
        p.append("<table><tr><th style='width:118px'>Ferramenta</th><th style='width:76px'>Versão</th>"
                 "<th style='width:96px'>Estado</th><th>Escopo / observação</th></tr>")
        for f in ferramentas:
            estado = str(f.get("estado", "")).strip().lower()
            rot, cor = FERRAMENTA_ESTADO.get(estado, (f.get("estado", "?"), "#64748B"))
            detalhe = " · ".join(x for x in (f.get("escopo"), f.get("nota")) if x)
            p.append(f"<tr><td><b>{e(f.get('nome',''))}</b></td>"
                     f"<td class='arq'>{e(f.get('versao','—'))}</td>"
                     f"<td style='color:{cor};font-weight:700'>{e(rot)}</td>"
                     f"<td>{e(detalhe)}</td></tr>")
        p.append("</table>")
        if sem_medida:
            nomes = ", ".join(str(f.get("nome", "?")) for f in sem_medida)
            p.append(f'<div class="aviso"><b>Superfície não medida:</b> {e(nomes)} não '
                     f'chegou a rodar. Ausência de achado nessas superfícies não é '
                     f'evidência de ausência de falha — rode e reavalie antes de tratar '
                     f'este relatório como completo.</div>')

    # ---- fortes e fracos
    p.append('<h2 class="quebra">Pontos fortes</h2>')
    fortes = d.get("pontos_fortes", [])
    if not fortes:
        p.append('<p class="vazio">Nenhum controle verificado como correto foi registrado.</p>')
    for f in fortes:
        p.append(f'<div class="forte evitar-quebra"><b>{e(f.get("titulo") or cats.get(f.get("categoria"), ""))}</b>'
                 f'<div>{e(f.get("descricao",""))}</div>'
                 + (f'<div class="arq" style="color:#475569;font-size:9pt">Evidência: '
                    f'<code>{e(f.get("evidencia"))}</code></div>' if f.get("evidencia") else "")
                 + "</div>")

    p.append("<h2>Pontos fracos</h2>")
    fracos = d.get("pontos_fracos", [])
    if not fracos:
        p.append('<p class="vazio">Nenhum risco central registrado.</p>')
    for f in fracos:
        p.append(f'<div class="fraco evitar-quebra"><b>{e(f.get("titulo",""))}</b>'
                 f'<div>{e(f.get("descricao",""))}</div></div>')

    # ---- hardening: camada B ausente com a camada A funcionando. Nao e' achado,
    # nao pesa no veredito, mas some do relatorio se nao tiver lugar proprio.
    hardening = d.get("hardening", [])
    if hardening:
        p.append("<h2>Notas de hardening</h2>")
        p.append('<div class="nota">Melhorias de defesa em profundidade sem violação de fronteira '
                 'alcançável hoje. Não entram no veredito nem viram issue de segurança.</div>')
        for h in hardening:
            if isinstance(h, str):
                p.append(f'<div class="hard evitar-quebra">{e(h)}</div>')
                continue
            p.append(f'<div class="hard evitar-quebra"><b>{e(h.get("titulo",""))}</b>'
                     f'<div>{e(h.get("descricao",""))}</div>'
                     + (f'<div class="arq" style="color:#475569;font-size:9pt">'
                        f'<code>{e(h.get("arquivo"))}</code></div>' if h.get("arquivo") else "")
                     + "</div>")

    # ---- tabela de achados
    p.append('<h2 class="quebra">Achados</h2>')
    if not achados_ord:
        p.append('<p class="vazio">Nenhum achado.</p>')
    else:
        p.append('<div class="nota">O nível de evidência diz como o achado foi obtido: '
                 '<b>padrão casou</b> é busca automática ainda não confirmada, '
                 '<b>lido</b> é o arquivo aberto e o caminho conferido, e '
                 '<b>corroborado</b> exige uma segunda fonte independente (outra ferramenta '
                 'ou reprodução real). A confiança é limitada pelo nível: um padrão que casou '
                 'não passa de 0,60 por mais convincente que pareça.</div>')
        p.append("<table><tr><th style='width:74px'>Severidade</th>"
                 "<th style='width:88px'>Evidência</th><th style='width:52px'>Conf.</th>"
                 "<th style='width:168px'>Arquivo:linha</th><th>Descrição</th></tr>")
        for a in achados_ord:
            p.append(f"<tr><td>{chip(a.get('severidade'))}</td>"
                     f"<td>{chip_evidencia(a)}</td>"
                     f"<td class='conf'>{num(confianca(a))}</td>"
                     f"<td class='arq'>{local_html(a)}</td>"
                     f"<td><b>{e(a.get('id',''))}</b> — {e(a.get('titulo',''))} "
                     f"{selo_status(a)}</td></tr>")
        p.append("</table>")

        # ---- detalhe por categoria
        for c in d.get("categorias", []):
            do_cat = [a for a in achados_ord if a.get("categoria") == c["id"]]
            p.append(f'<h3>{e(c["id"])} · {e(c.get("nome",""))}</h3>')
            if c.get("aplicavel") is False:
                p.append(f'<div class="nota">Categoria não aplicável a esta stack. '
                         f'{e(c.get("nota",""))}</div>')
                continue
            if c.get("nota"):
                p.append(f'<div class="nota">{e(c["nota"])}</div>')
            if not do_cat:
                p.append('<p class="vazio">Nenhum achado nesta categoria.</p>')
            for a in do_cat:
                p.append('<div class="achado">')
                desde = (f'<span class="id">desde {e(a["desde"])}</span>'
                         if a.get("desde") else "")
                p.append(f'<div class="cab">{chip(a.get("severidade"))}'
                         f'{chip_evidencia(a)}'
                         f'<span class="id">{e(a.get("id",""))}</span>'
                         f'<b>{e(a.get("titulo",""))}</b>{selo_status(a)}{desde}</div>')
                if status_achado(a) != "aberto" and a.get("motivo"):
                    p.append(f'<div class="campo"><b>Motivo do status:</b> {e(a["motivo"])}</div>')
                fonte = a.get("fonte")
                p.append(f'<div class="campo"><b>Evidência:</b> '
                         f'{e(EVIDENCIA[nivel_evidencia(a)][0].lower())} · confiança '
                         f'<span class="conf">{num(confianca(a))}</span>'
                         + (f' · {e(fonte)}' if fonte else "") + '</div>')
                p.append(f'<div class="campo arq"><b>Local:</b> <code>{local_html(a)}</code></div>')
                p.append(bloco_caminho(a.get("caminho")))
                texto, n_red = trecho_redigido(a)
                redacoes[0] += n_red
                p.append(bloco_codigo(texto))
                if n_red:
                    p.append('<div class="campo" style="color:#64748B;font-size:9pt">'
                             'Segredo mascarado no trecho acima.</div>')
                if a.get("por_que"):
                    p.append(f'<div class="campo"><b>Por que é explorável:</b> {e(a["por_que"])}</div>')
                if a.get("impacto"):
                    p.append(f'<div class="campo"><b>Impacto:</b> {e(a["impacto"])}</div>')
                if a.get("condicoes"):
                    p.append(f'<div class="campo"><b>Condições de explorabilidade:</b> '
                             f'{condicoes_html(a["condicoes"])}</div>')
                if a.get("correcao"):
                    p.append(f'<div class="campo"><b>Correção sugerida:</b> {e(a["correcao"])}</div>')
                p.append("</div>")

    # ---- a validar
    p.append('<h2 class="quebra">A validar</h2>')
    if not a_validar:
        p.append('<p class="vazio">Nenhuma hipótese ficou bloqueada por fato fora do código.</p>')
    else:
        p.append('<div class="nota">Hipóteses com caminho real no código cuja confirmação depende '
                 'de um fato que o repositório não mostra (configuração do provedor, header do '
                 'proxy, policy do deploy). Não têm severidade e não são falhas confirmadas: '
                 'cada uma diz exatamente o que falta saber e como resolver. Nenhuma é '
                 'instrução para testar contra produção.</div>')
        for a in a_validar:
            p.append(bloco_a_validar(a))

    # ---- rastreabilidade de compliance: etiqueta os achados provados nos
    # controles de framework. Nao muda severidade nem veredito; so responde
    # "qual controle isto viola". Achado a_validar/nao acionavel nao entra.
    cobertura = cobertura_compliance(achados)
    p.append('<h2 class="quebra">Rastreabilidade de compliance</h2>')
    if not cobertura:
        p.append('<p class="vazio">Nenhum achado acionável para mapear a controles '
                 'de framework.</p>')
    else:
        p.append('<div class="nota">Cada achado confirmado é etiquetado nos controles '
                 'que ele viola. Isto é rastreabilidade técnica sobre achados já provados '
                 '— não sobe nem desce a severidade, e não substitui auditoria de '
                 'certificação (ISO/SOC 2 exigem evidência de processo que esta análise '
                 'estática não mede). Controle sem achado nesta lista não significa '
                 'conformidade: significa que esta auditoria não encontrou violação ali.</div>')
        p.append("<table><tr><th style='width:34%'>Framework</th><th>Controle</th>"
                 "<th style='width:130px'>Achados</th></tr>")
        for fw, controles in cobertura.items():
            linhas_fw = list(controles.items())
            for j, (ctrl, ids) in enumerate(linhas_fw):
                nome_fw = (f"{e(COMPLIANCE_FRAMEWORKS[fw])}" if j == 0 else "")
                ctrl_txt = ctrl.split(":", 1)[1] if ":" in ctrl else ctrl
                p.append(f"<tr><td>{nome_fw}</td>"
                         f"<td class='arq'>{e(ctrl_txt)}</td>"
                         f"<td class='arq'>{e(', '.join(ids))}</td></tr>")
        p.append("</table>")

    # ---- recomendacoes
    p.append('<h2 class="quebra">Recomendações priorizadas</h2>')
    recs = d.get("recomendacoes", [])
    if not recs:
        p.append('<p class="vazio">Nenhuma recomendação registrada.</p>')
    else:
        p.append("<table><tr><th style='width:52px'>Prio</th><th>Ação</th>"
                 "<th style='width:120px'>Achados</th></tr>")
        for r in recs:
            p.append(f"<tr><td class='prio'>{e(r.get('prioridade',''))}</td>"
                     f"<td>{e(r.get('texto',''))}</td>"
                     f"<td class='arq'>{e(', '.join(r.get('achados', [])))}</td></tr>")
        p.append("</table>")

    # ---- issues
    p.append('<h2 class="quebra">Issues para o GitHub</h2>')
    issues = d.get("issues", [])
    if not issues:
        p.append('<p class="vazio">Nenhuma issue gerada.</p>')
    for i, iss in enumerate(issues, 1):
        corpo = montar_corpo_issue(iss, todos, redacoes)
        p.append(f'<div class="issue">--- ISSUE {i} ---\n{e(corpo)}\n--- FIM ISSUE {i} ---</div>')

    p.append("</body></html>")
    return "\n".join(p)


def montar_corpo_issue(iss, achados, redacoes=None):
    """Monta o markdown da issue. Aceita corpo pronto ou monta dos achados citados.

    A issue vai para o GitHub, que e' mais publico que o PDF: o trecho sai daqui
    pela mesma redacao, e o nivel de evidencia acompanha para quem for corrigir
    saber se o achado foi lido ou so' sugerido por um padrao.
    """
    redacoes = redacoes if redacoes is not None else [0]
    if iss.get("markdown"):
        # Corpo escrito a mao tambem passa pela mascara: e' o mesmo GitHub, e quem
        # escreve markdown custom e' justamente quem colou o trecho na unha.
        texto, n_red = redigir_segredos(iss["markdown"].strip())
        redacoes[0] += n_red
        return texto
    idx = {a.get("id"): a for a in achados}
    refs = [idx[i] for i in iss.get("achados", []) if i in idx]
    sev = iss.get("severidade") or (refs[0].get("severidade") if refs else "media")
    ctrls = []
    for a in refs:
        for c in compliance_do_achado(a):
            if c not in ctrls:
                ctrls.append(c)
    linhas = [f"**Título:** [Segurança] {iss.get('titulo','')}",
              f"**Labels:** `security`, `{sev}`"]
    if ctrls:
        linhas.append(f"**Compliance:** {', '.join('`' + c + '`' for c in ctrls)}")
    linhas += ["", "## Problema", "", iss.get("problema", ""), "", "## Evidência", ""]
    for a in refs:
        local = a.get("arquivo", "")
        if a.get("linhas"):
            local += f":{a['linhas']}"
        nivel = EVIDENCIA[nivel_evidencia(a)][0].lower()
        linhas.append(f"- `{local}` — {a.get('titulo','')} "
                      f"({nivel}, confiança {num(confianca(a))})")
        texto, n_red = trecho_redigido(a)
        if texto:
            linhas += ["", "```", texto.strip(), "```", ""]
            redacoes[0] += n_red
    linhas += ["", "## Impacto", "", iss.get("impacto", ""), "",
               "## Correção sugerida", "", iss.get("correcao", ""), "",
               "## Critérios de aceite", ""]
    for c in iss.get("criterios_aceite", []):
        linhas.append(f"- [ ] {c}")
    return "\n".join(linhas)


# --------------------------------------------------------------------------- verificacao

def _normalizar(s):
    return re.sub(r"\s+", " ", s).strip()


_ANOTACAO = re.compile(r"\s+(//|#)[^\"']*$")   # anotacao do auditor no fim da linha


def _intervalo(linhas):
    m = re.fullmatch(r"\s*(\d+)\s*(?:-\s*(\d+))?\s*", str(linhas))
    if not m:
        return None
    return int(m.group(1)), int(m.group(2) or m.group(1))


def verificar_local(raiz, rotulo, arquivo, linhas, trecho):
    """Arquivo existe, linhas cabem nele e cada linha do trecho esta' la'.

    A comparacao ignora espacos e aceita anotacao do auditor no fim da linha
    ("// sem organizationId"); o que ela nao aceita e' codigo reescrito de
    memoria, que e' o que a issue devolvida como "nao reproduz" costuma ter.
    """
    if not arquivo:
        return [f"{rotulo}: sem 'arquivo'"]
    caminho = Path(raiz, arquivo)
    if not caminho.is_file():
        return [f"{rotulo}: arquivo não existe em {raiz}: {arquivo}"]
    conteudo = caminho.read_text(encoding="utf-8", errors="replace").splitlines()
    ini = fim = None
    if linhas is not None and str(linhas).strip():
        faixa = _intervalo(linhas)
        if not faixa:
            return [f"{rotulo}: 'linhas' {linhas!r} não é N nem N-M"]
        ini, fim = faixa
        if ini < 1 or ini > fim or fim > len(conteudo):
            return [f"{rotulo}: linhas {linhas} fora de {arquivo} ({len(conteudo)} linhas)"]
    if not trecho:
        return []
    alvo = " ".join(_normalizar(l) for l in (conteudo[ini - 1:fim] if ini else conteudo))
    for linha in str(trecho).splitlines():
        candidatos = {_normalizar(linha), _normalizar(_ANOTACAO.sub("", linha))}
        candidatos.discard("")
        if candidatos and not any(c in alvo for c in candidatos):
            return [f"{rotulo}: linha do trecho não está em {arquivo}"
                    f"{':' + str(linhas) if linhas else ''}: {linha.strip()[:70]!r}"]
    return []


def verificar(dados, raiz=None):
    """Confere o que o schema promete em prosa. Devolve a lista de problemas.

    Com raiz, confere tambem arquivo/linhas/trecho contra o codigo. Sem raiz,
    devolve o aviso como primeiro item de 'avisos' -- o codigo NAO foi conferido
    e o relatorio precisa saber disso.
    """
    erros, ids = [], {}
    for a in dados.get("achados", []):
        ident = a.get("id", "?")
        if ident in ids:
            erros.append(f"achado {ident}: id repetido")
        ids[ident] = a
        st = status_achado(a)
        if nivel_evidencia(a) == "corroborado" and not str(a.get("fonte", "")).strip():
            erros.append(f"achado {ident}: corroborado sem 'fonte' nomeada — segunda fonte que "
                         f"não se nomeia é autodeclaração")
        if st in STATUS_COM_MOTIVO and not str(a.get("motivo", "")).strip():
            erros.append(f"achado {ident}: status {st} sem 'motivo'")
        if st == "a_validar":
            plano = a.get("plano_validacao") or {}
            if not str(a.get("bloqueio", "")).strip():
                erros.append(f"achado {ident}: a_validar sem 'bloqueio' (o fato exato que falta)")
            if not (isinstance(plano, dict) and (plano.get("local") or plano.get("dono"))):
                erros.append(f"achado {ident}: a_validar sem plano_validacao.local nem .dono")
        erros.extend(erros_compliance(a))
        caminho = a.get("caminho") or []
        if caminho:
            tipos = [str(x.get("tipo", "")).lower() for x in caminho]
            if tipos[0] != "entrada":
                erros.append(f"achado {ident}: caminho não começa em 'entrada'")
            if tipos[-1] != "sink":
                erros.append(f"achado {ident}: caminho não termina em 'sink'")
            if any(t != "propagacao" for t in tipos[1:-1]):
                erros.append(f"achado {ident}: passo intermediário do caminho não é 'propagacao'")
        if raiz:
            erros += verificar_local(raiz, f"achado {ident}", a.get("arquivo"), a.get("linhas"),
                                     a.get("trecho"))
            for i, passo in enumerate(caminho):
                erros += verificar_local(raiz, f"achado {ident} caminho[{i}]",
                                         passo.get("arquivo"), passo.get("linha"), None)
    for iss in dados.get("issues", []):
        for ref in iss.get("achados", []):
            if ref not in ids:
                erros.append(f"issue {iss.get('titulo', '?')!r}: cita achado inexistente {ref}")
    for r in dados.get("recomendacoes", []):
        for ref in r.get("achados", []):
            if ref not in ids:
                erros.append(f"recomendação {r.get('prioridade', '?')}: cita achado inexistente {ref}")
    return erros


# --------------------------------------------------------------------------- PDF

def servir_e_imprimir(html_txt, saida_pdf, chrome):
    """Serve o HTML por HTTP efemero e imprime. O nome do arquivo servido vira o
    rodape do PDF (o Chrome imprime a URL), por isso ele e' legivel, nao um hash."""
    tmp = tempfile.mkdtemp(prefix="auditoria-")
    nome = "Relatorio-de-Auditoria-de-Seguranca.html"
    Path(tmp, nome).write_text(html_txt, encoding="utf-8")

    class Silencioso(SimpleHTTPRequestHandler):
        def log_message(self, *a, **k):
            pass

    handler = functools.partial(Silencioso, directory=tmp)
    srv = HTTPServer(("127.0.0.1", 0), handler)
    porta = srv.server_address[1]
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    try:
        cmd = [chrome, "--headless", "--disable-gpu", "--no-sandbox",
               "--virtual-time-budget=6000",
               f"--print-to-pdf={saida_pdf}", f"http://localhost:{porta}/{nome}"]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        if not os.path.exists(saida_pdf):
            print(r.stderr[-2000:], file=sys.stderr)
            raise SystemExit("Chrome nao gerou o PDF (saida acima).")
    finally:
        srv.shutdown()
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(description="Gera o PDF da auditoria de seguranca.")
    ap.add_argument("findings", help="caminho do findings.json")
    ap.add_argument("--out", help="caminho do PDF de saida")
    ap.add_argument("--html-only", action="store_true", help="so escreve o HTML")
    ap.add_argument("--verificar", action="store_true",
                    help="confere referencias cruzadas e, com --raiz, arquivo/linhas/trecho "
                         "contra o codigo; falha alto")
    ap.add_argument("--raiz", help="raiz do repositorio auditado, para o --verificar")
    args = ap.parse_args()
    if not args.out and not args.verificar:
        ap.error("--out e' obrigatorio (ou rode so' com --verificar)")

    dados = json.loads(Path(args.findings).read_text(encoding="utf-8"))
    for campo in ("projeto", "data", "categorias"):
        if campo not in dados:
            raise SystemExit(f"findings.json sem o campo obrigatorio: {campo}")

    # Valor invalido em evidencia/status seria rebaixado em silencio para o default
    # e mudaria o veredito sem ninguem notar. Falha alto.
    for a in dados.get("achados", []):
        ident = a.get("id", "?")
        ev = a.get("evidencia")
        if ev is not None and str(ev).strip().lower() not in EVIDENCIA:
            raise SystemExit(f"achado {ident}: evidencia invalida {ev!r} "
                             f"(use: {', '.join(EVIDENCIA)})")
        st = a.get("status")
        if st is not None and str(st).strip().lower() not in STATUS_ROTULO:
            raise SystemExit(f"achado {ident}: status invalido {st!r} "
                             f"(use: {', '.join(STATUS_ROTULO)})")
        # Sem isso a secao "A validar" sai vazia e o falso positivo vira opiniao.
        st = status_achado(a)
        if st == "a_validar" and not str(a.get("bloqueio", "")).strip():
            raise SystemExit(f"achado {ident}: a_validar exige 'bloqueio' (o fato exato que falta)")
        if st in STATUS_COM_MOTIVO and not str(a.get("motivo", "")).strip():
            raise SystemExit(f"achado {ident}: status {st} exige 'motivo'")
        # Sem isso o PDF sai com control ID inventado etiquetado num achado provado;
        # o --verificar e' opcional, esta checagem nao pode ser.
        comp_erros = erros_compliance(a)
        if comp_erros:
            raise SystemExit("\n".join(comp_erros))

    if args.verificar:
        raiz = Path(args.raiz).resolve() if args.raiz else None
        if raiz and not raiz.is_dir():
            raise SystemExit(f"--raiz nao e' um diretorio: {raiz}")
        problemas = verificar(dados, raiz)
        for x in problemas:
            print(f"VERIFICAR: {x}", file=sys.stderr)
        if problemas:
            raise SystemExit(f"{len(problemas)} problema(s) no findings.json - corrija antes de gerar.")
        if raiz:
            print(f"Verificacao: ok - arquivo, linhas e trecho conferidos contra {raiz}.")
        else:
            print("Verificacao: referencias ok. Codigo NAO conferido (passe --raiz <repo>).")
        if not args.out:
            return

    out = Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    redacoes = [0]
    html_txt = montar_html(dados, redacoes)
    html_path = out.with_suffix(".html")
    html_path.write_text(html_txt, encoding="utf-8")

    gate, motivo = calcular_veredito(dados.get("achados", []))
    print(f"Veredito: {gate} — {motivo}")
    pendentes = sum(1 for a in dados.get("achados", []) if status_achado(a) == "a_validar")
    if pendentes:
        print(f"A validar: {pendentes} hipotese(s) bloqueada(s) por fato fora do codigo.")
    if redacoes[0]:
        print(f"Redacao: {redacoes[0]} segredo(s) mascarado(s) no relatorio.")
    sem_medida = [f.get("nome", "?") for f in dados.get("ferramentas", [])
                  if str(f.get("estado", "")).strip().lower() in ESTADO_SEM_MEDIDA]
    if sem_medida:
        print(f"ATENCAO: superficie nao medida - {', '.join(sem_medida)} nao rodou.")
    print(f"HTML: {html_path}")
    if args.html_only:
        return

    chrome = achar_chrome()
    if not chrome:
        raise SystemExit("Nenhum Chromium encontrado. Instale o Chrome ou rode com --html-only "
                         "e converta com a ferramenta que voce tiver.")
    servir_e_imprimir(html_txt, str(out), chrome)
    print(f"PDF:  {out}")

    if shutil.which("pdfinfo"):
        info = subprocess.run(["pdfinfo", str(out)], capture_output=True, text=True).stdout
        for linha in info.splitlines():
            if linha.startswith(("Pages:", "Page size:")):
                print(linha)
    else:
        print("pdfinfo ausente - numero de paginas NAO verificado.")


if __name__ == "__main__":
    main()
