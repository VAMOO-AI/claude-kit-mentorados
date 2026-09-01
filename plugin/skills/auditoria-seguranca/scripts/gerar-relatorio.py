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
"""

import argparse
import functools
import html
import json
import os
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


def montar_html(d):
    projeto = d.get("projeto", "projeto")
    titulo = f"Relatório de Auditoria de Segurança — {projeto}"
    achados = d.get("achados", [])
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
</style></head><body>""")

    # ---- capa
    p.append('<div class="capa"><div class="faixa"></div>')
    p.append(f"<h1>Relatório de Auditoria de Segurança</h1>")
    p.append(f'<div class="sub">{e(projeto)}</div>')
    p.append('<dl class="meta">')
    p.append(f"<dt>Data</dt><dd>{e(d.get('data',''))}</dd>")
    escopo = d.get("escopo", [])
    p.append("<dt>Escopo auditado</dt><dd>" +
             (e(", ".join(escopo)) if isinstance(escopo, list) else e(escopo)) + "</dd>")
    stack = d.get("stack", {})
    if stack:
        linhas = "".join(f"<div><b>{e(k)}:</b> {e(v)}</div>" for k, v in stack.items())
        p.append(f"<dt>Stack detectada</dt><dd>{linhas}</dd>")
    if d.get("nota_metodologica"):
        p.append(f"<dt>Nota metodológica</dt><dd>{e(d['nota_metodologica'])}</dd>")
    p.append("</dl></div>")

    # ---- resumo executivo
    p.append("<h2>Resumo executivo</h2>")
    if d.get("resumo"):
        p.append(f"<p>{e(d['resumo'])}</p>")
    p.append('<div class="painel"><div>' + donut(contagem) + "</div><div>" +
             (legenda(contagem) or '<p class="vazio">Nenhum achado registrado.</p>') +
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

    # ---- tabela de achados
    p.append('<h2 class="quebra">Achados</h2>')
    if not achados_ord:
        p.append('<p class="vazio">Nenhum achado.</p>')
    else:
        p.append("<table><tr><th style='width:74px'>Severidade</th><th style='width:215px'>Arquivo:linha</th>"
                 "<th>Descrição</th></tr>")
        for a in achados_ord:
            p.append(f"<tr><td>{chip(a.get('severidade'))}</td>"
                     f"<td class='arq'>{local_html(a)}</td>"
                     f"<td><b>{e(a.get('id',''))}</b> — {e(a.get('titulo',''))}</td></tr>")
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
                p.append(f'<div class="cab">{chip(a.get("severidade"))}'
                         f'<span class="id">{e(a.get("id",""))}</span>'
                         f'<b>{e(a.get("titulo",""))}</b></div>')
                p.append(f'<div class="campo arq"><b>Local:</b> <code>{local_html(a)}</code></div>')
                p.append(bloco_codigo(a.get("trecho")))
                if a.get("por_que"):
                    p.append(f'<div class="campo"><b>Por que é explorável:</b> {e(a["por_que"])}</div>')
                if a.get("impacto"):
                    p.append(f'<div class="campo"><b>Impacto:</b> {e(a["impacto"])}</div>')
                if a.get("condicoes"):
                    p.append(f'<div class="campo"><b>Condições de explorabilidade:</b> {e(a["condicoes"])}</div>')
                if a.get("correcao"):
                    p.append(f'<div class="campo"><b>Correção sugerida:</b> {e(a["correcao"])}</div>')
                p.append("</div>")

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
        corpo = montar_corpo_issue(iss, achados)
        p.append(f'<div class="issue">--- ISSUE {i} ---\n{e(corpo)}\n--- FIM ISSUE {i} ---</div>')

    p.append("</body></html>")
    return "\n".join(p)


def montar_corpo_issue(iss, achados):
    """Monta o markdown da issue. Aceita corpo pronto ou monta dos achados citados."""
    if iss.get("markdown"):
        return iss["markdown"].strip()
    idx = {a.get("id"): a for a in achados}
    refs = [idx[i] for i in iss.get("achados", []) if i in idx]
    sev = iss.get("severidade") or (refs[0].get("severidade") if refs else "media")
    linhas = [f"**Título:** [Segurança] {iss.get('titulo','')}",
              f"**Labels:** `security`, `{sev}`", "", "## Problema", "",
              iss.get("problema", ""), "", "## Evidência", ""]
    for a in refs:
        local = a.get("arquivo", "")
        if a.get("linhas"):
            local += f":{a['linhas']}"
        linhas.append(f"- `{local}` — {a.get('titulo','')}")
        if a.get("trecho"):
            linhas += ["", "```", a["trecho"].strip(), "```", ""]
    linhas += ["", "## Impacto", "", iss.get("impacto", ""), "",
               "## Correção sugerida", "", iss.get("correcao", ""), "",
               "## Critérios de aceite", ""]
    for c in iss.get("criterios_aceite", []):
        linhas.append(f"- [ ] {c}")
    return "\n".join(linhas)


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
    ap.add_argument("--out", required=True, help="caminho do PDF de saida")
    ap.add_argument("--html-only", action="store_true", help="so escreve o HTML")
    args = ap.parse_args()

    dados = json.loads(Path(args.findings).read_text(encoding="utf-8"))
    for campo in ("projeto", "data", "categorias"):
        if campo not in dados:
            raise SystemExit(f"findings.json sem o campo obrigatorio: {campo}")

    out = Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    html_txt = montar_html(dados)
    html_path = out.with_suffix(".html")
    html_path.write_text(html_txt, encoding="utf-8")
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
