#!/usr/bin/env python3
"""Galeria do que o template já tem: cenas do Film, transições e cenas do Reel, com a marca do projeto.

    python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/galeria.py --lista [projeto]   # só o texto, sem render
    python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/galeria.py <projeto>             # <projeto>/out/galeria/index.html
    python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/galeria.py <projeto> --pior-caso   # <projeto>/out/galeria-pior-caso/

Serve para escolher cena e transição antes de roteirizar. Tudo vem do código do projeto (ou do
template da skill, sem projeto): as cenas do mapa SCENES de src/film-scenes.tsx com o comentário de
props de cada uma, as transições do D do scripts/build-timeline.py e as cenas do src/timeline.json.
O Film sai em 9:16 (Reel916) com as props de exemplo do film.json (master) e, para cena que não está
nele, dos film.json prontos em presets/ (que a lista e a página também mostram) ou do EXEMPLOS abaixo
(cenas avulsas, sem preset); cada transição aparece a
um quarto da troca antes do corte. O film.json e o vo.json não mudam; o src/tl-reel.json é trocado durante o render e
devolvido no fim, mesmo se o render falhar.

--pior-caso é a bancada de texto: cada cena do presets/pior-caso.json (textos no limite documentado
e no limite + 1) num quadro já assentado, em 9:16 e em 16:9, e o Grande do Reel com cada palavra
da lista "grande" do arquivo, cada quadro com a guia segura do useL() em vermelho por cima. O
pior-caso.json não é preset de filme: fica fora da lista de presets e dos exemplos da galeria.
"""
import html
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

SK = Path(__file__).resolve().parents[1]
TEMPLATE = SK / "assets/template"
ESCALA = 0.4
PIOR = "pior-caso.json"
# Exemplo das cenas avulsas, que não estão em nenhum film.json pronto: a galeria só usa quando o
# film.json do projeto e os presets/ não trazem o type. Textos de exemplo, para trocar.
EXEMPLOS = {
    "ranking": {"type": "ranking", "min": 105, "read": ["Onde o tempo vai", "Reunião, 12 h"], "props": {"kicker": "Exemplo", "title": "Onde o tempo vai", "items": [
        {"label": "Reunião", "v": 12, "suffix": " h"}, {"label": "E-mail", "v": 9, "suffix": " h"},
        {"label": "Relatório", "v": 6, "suffix": " h"}, {"label": "Planilha", "v": 4, "suffix": " h"}]}},
    "versus": {"type": "versus", "min": 105, "read": ["Antes e depois", "40 min", "6 min"], "props": {"kicker": "Exemplo", "title": "Antes e depois", "low": True,
        "left": {"label": "Antes", "v": 40, "suffix": " min"}, "right": {"label": "Depois", "v": 6, "suffix": " min"}}},
    "map": {"type": "map", "min": 120, "read": ["De onde para onde", "São Paulo, Recife, Lisboa"], "props": {"kicker": "Exemplo", "title": "De onde para onde", "region": "Brazil", "route": [
        {"name": "São Paulo", "at": [-46.63, -23.55]}, {"name": "Recife", "at": [-34.88, -8.05]},
        {"name": "Lisboa", "at": [-9.14, 38.72]}]}},
    "morph": {"type": "morph", "min": 270, "props": {"kicker": "Um processo", "states": [
        {"label": "Ideia"}, {"label": "Roteiro"}, {"label": "Gravação"}, {"label": "Corte"},
        {"label": "Legenda"}, {"label": "Revisão"}, {"label": "Post"}, {"label": "Dados"}]}},
    "swap": {"type": "swap", "min": 120, "props": {"from": "Ideia solta", "to": "Plano pronto", "kicker": "Antes e depois"}},
}
RENDER = """import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import fs from "node:fs";
import path from "node:path";

const job = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const serveUrl = await bundle({ entryPoint: path.join(job.root, "src/index.tsx") });
const tl = (n) => JSON.parse(fs.readFileSync(path.join(job.root, `src/tl-${n}.json`), "utf8"));
const props = { Reel916: () => ({ tl: tl("reel"), audio: "x.wav", withAudio: false }),
  Master169: () => ({ tl: tl("master"), audio: "x.wav", withAudio: false }), Reel: () => ({ withAudio: false }) };
const comps = {};
for (const it of job.itens) {
  const inputProps = { ...props[it.comp](), ...(it.props ?? {}) };
  comps[it.comp] ??= await selectComposition({ serveUrl, id: it.comp, inputProps });
  // a composição em cache guarda as props da 1ª seleção: cada quadro leva as dele
  await renderStill({ composition: { ...comps[it.comp], props: inputProps }, serveUrl, output: path.join(job.saida, it.nome + ".png"),
    frame: it.frame, inputProps, scale: job.scale });
}
"""


def arquivo(projeto, rel):
    p = (projeto / rel) if projeto else None
    return p if p and p.is_file() else TEMPLATE / rel


def ler_json(caminho):
    return json.loads(caminho.read_text(encoding="utf-8"))


def cenas_do_film(projeto):
    """{tipo: (componente, descrição)} na ordem do SCENES de film-scenes.tsx.

    O componente pode morar em outro src/*.tsx importado no film-scenes.tsx (scenes-app.tsx…):
    o comentário de props é procurado nele também."""
    tsx = arquivo(projeto, "src/film-scenes.tsx").read_text(encoding="utf-8")
    bloco = re.search(r"export const SCENES[^=]*=\s*\{(.*?)\};", tsx, re.S)
    if not bloco:
        raise SystemExit("!! não achei o mapa SCENES em src/film-scenes.tsx")
    linhas = tsx.splitlines()
    for mod in re.findall(r'^import [^;]*? from "\./([\w-]+)";', tsx, re.M):
        alvo = arquivo(projeto, f"src/{mod}.tsx")
        if alvo.is_file():
            linhas += [""] + alvo.read_text(encoding="utf-8").splitlines()
    cenas = {}
    for tipo, comp in re.findall(r"(\w+)\s*:\s*(\w+)", bloco.group(1)):
        desc = ""
        for i, linha in enumerate(linhas):
            if linha.startswith(f"export const {comp}:"):
                j = i - 1
                while j >= 0 and linhas[j].startswith("//"):
                    if linhas[j].startswith("// props:"):
                        desc = linhas[j][3:]
                        break
                    j -= 1
                break
        cenas[tipo] = (comp, desc)
    return cenas


def presets(projeto):
    """[(arquivo, sequência de types do master, sobre)] dos film.json prontos em presets/."""
    pasta = (projeto / "presets") if projeto and (projeto / "presets").is_dir() else TEMPLATE / "presets"
    out = []
    for f in sorted(pasta.glob("*.json")):
        if f.name == PIOR:
            continue
        d = ler_json(f)
        out.append((f.name, [c["type"] for c in d.get("master", [])], d.get("sobre", "")))
    return out


def transicoes(projeto):
    """Transições do D do build-timeline.py, sem o corte seco."""
    texto = arquivo(projeto, "scripts/build-timeline.py").read_text(encoding="utf-8")
    d = re.search(r"^D = \{(.*?)\}", texto, re.M | re.S)
    if not d:
        raise SystemExit("!! não achei o D das transições em scripts/build-timeline.py")
    return [t for t in re.findall(r'"(\w+)"\s*:', d.group(1)) if t != "cut"]


def cenas_do_reel(projeto):
    tl = ler_json(arquivo(projeto, "src/timeline.json"))
    sc = tl["scenes"]
    return [(s["id"], s["cut"], (sc[i + 1]["cut"] if i + 1 < len(sc) else tl["total"]) - s["cut"])
            for i, s in enumerate(sc)]


def marca(projeto):
    lib = arquivo(projeto, "src/lib.tsx").read_text(encoding="utf-8")
    m = re.search(r'export const BRAND\s*=\s*"([^"]*)"', lib)
    return m.group(1) if m else "Sua Marca"


def roteiro(projeto, tipos, trans):
    """Uma cena de exemplo por tipo (props do master) e, entre elas, cada transição uma vez."""
    exemplos = {}
    fontes = [projeto / "film.json", TEMPLATE / "film.json"]
    fontes += sorted((projeto / "presets").glob("*.json")) + sorted((TEMPLATE / "presets").glob("*.json"))
    for fonte in [f for f in fontes if f.name != PIOR]:
        if fonte.is_file():
            for cena in ler_json(fonte).get("master", []):
                exemplos.setdefault(cena["type"], cena)
    for tipo, cena in EXEMPLOS.items():
        exemplos.setdefault(tipo, cena)
    base = [{k: v for k, v in exemplos[t].items() if k not in ("in", "cues", "mark")} for t in tipos if t in exemplos]
    if not base:
        raise SystemExit("!! nenhum exemplo de cena no film.json (master)")
    spec = [dict(c) for c in base]
    while len(spec) - 1 < len(trans):
        spec.append(dict(base[len(spec) % len(base)]))
    for i, cena in enumerate(spec[1:len(trans) + 1], 1):
        cena["in"] = trans[i - 1]
    return spec, [c["type"] for c in base]


def listar(projeto=None):
    print("Cenas do Film (film.json → type):")
    for tipo, (comp, desc) in cenas_do_film(projeto).items():
        print(f"  {tipo:<10} {comp:<10} {desc}")
    print("Transições (film.json → in; timeline.json → in):")
    print("  " + ", ".join(transicoes(projeto)) + "  (e cut, o corte seco)")
    print("Cenas do Reel (src/timeline.json → id, layout fixo em 1080×1920):")
    print("  " + ", ".join(i for i, _, _ in cenas_do_reel(projeto)))
    print("Presets do Film (cp presets/<arquivo> film.json e troque os textos):")
    for nome, tipos, sobre in presets(projeto):
        print(f"  {nome:<22} {' → '.join(tipos)}")
        if sobre:
            print(f"  {'':<22} {sobre}")


def pagina(nome, cenas, mostradas, trans, reel, pre):
    e = html.escape

    def fig(arq, titulo, texto):
        return (f'  <figure><img src="{e(arq)}.png" alt="{e(titulo)}"><figcaption><b>{e(titulo)}</b>'
                f'<br>{e(texto)}</figcaption></figure>')
    film = "\n".join(fig(f"cena-{t}", t, f"{cenas[t][0]}: {cenas[t][1]}") for t in mostradas)
    trs = "\n".join(fig(f"transicao-{t}", t, "durante a troca") for t in trans)
    rl = "\n".join(fig(f"reel-{i}", i, "Reel (música)") for i, _, _ in reel)
    pr = "\n".join(f"  <li><b>{e(n)}</b>: {e(' → '.join(t))}<br>{e(s)}</li>" for n, t, s in pre)
    return f"""<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Galeria motion-reel: {e(nome)}</title>
<style>
  body {{ margin: 0; padding: 24px 16px; font: 16px/1.4 system-ui, sans-serif; background: #f4f4f5; color: #18181b; }}
  h1 {{ font-size: 22px; margin: 0 0 4px; }} h2 {{ font-size: 18px; margin: 28px 0 12px; }}
  p {{ margin: 0 0 8px; color: #52525b; }}
  main {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 16px; }}
  figure {{ margin: 0; background: #fff; border-radius: 10px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,.12); }}
  img {{ display: block; width: 100%; aspect-ratio: 9 / 16; object-fit: cover; background: #000; }}
  figcaption {{ padding: 8px 10px 12px; font-size: 13px; color: #3f3f46; }}
  ul {{ margin: 0; padding-left: 20px; }} li {{ margin: 0 0 10px; color: #3f3f46; }}
</style>
</head>
<body>
<h1>Galeria motion-reel: {e(nome)}</h1>
<p>Um quadro de cada cena e de cada transição que o template já tem, com a marca do projeto. Os textos são os de exemplo.</p>
<h2>Presets do Film (cp presets/&lt;arquivo&gt; film.json)</h2>
<ul>
{pr}
</ul>
<h2>Cenas do Film (type no film.json)</h2>
<main>
{film}
</main>
<h2>Transições (in)</h2>
<main>
{trs}
</main>
<h2>Cenas do Reel (timeline.json)</h2>
<main>
{rl}
</main>
</body>
</html>
"""


def modulo_timeline(projeto):
    mod_spec = importlib.util.spec_from_file_location("motion_build_timeline", projeto / "scripts/build-timeline.py")
    bt = importlib.util.module_from_spec(mod_spec)
    mod_spec.loader.exec_module(bt)
    return bt


def renderizar(projeto, saida, montar):
    """Monta as timelines (montar(bt) → itens), renderiza os quadros num bundle só e devolve os
    src/tl-*.json do projeto como estavam, mesmo se o render falhar."""
    tls = [projeto / f"src/tl-{n}.json" for n in ("reel", "master")]
    salvos = {f: f.read_bytes() if f.is_file() else None for f in tls}
    saida.mkdir(parents=True, exist_ok=True)
    for velho in saida.glob("*.png"):
        velho.unlink()
    script, job = projeto / "out/galeria-render.mjs", projeto / "out/galeria-job.json"
    try:
        itens = montar(modulo_timeline(projeto))
        job.write_text(json.dumps({"root": str(projeto), "saida": str(saida), "scale": ESCALA, "itens": itens}),
                       encoding="utf-8")
        script.write_text(RENDER, encoding="utf-8")
        print(f"→ renderizando {len(itens)} quadros (o primeiro render pode baixar o Chrome do Remotion)")
        subprocess.run(["node", str(script), str(job)], cwd=projeto, check=True)
    except subprocess.CalledProcessError as erro:
        raise SystemExit(f"!! a galeria não renderizou: node saiu com {erro.returncode}")
    finally:
        script.unlink(missing_ok=True)
        job.unlink(missing_ok=True)
        for f, salvo in salvos.items():
            if salvo is None:
                f.unlink(missing_ok=True)
            else:
                f.write_bytes(salvo)
    return itens


def checar_projeto(projeto):
    for rel in ("film.json", "src/index.tsx", "scripts/build-timeline.py"):
        if not (projeto / rel).is_file():
            raise SystemExit(f"!! {projeto} não tem {rel}: crie o projeto com o new.sh da skill")


def galeria(projeto):
    projeto = projeto.resolve()
    checar_projeto(projeto)
    cenas, trans, reel = cenas_do_film(projeto), transicoes(projeto), cenas_do_reel(projeto)
    spec, mostradas = roteiro(projeto, list(cenas), trans)
    saida = projeto / "out/galeria"

    def montar(bt):
        bt.build("reel", spec, {}, bt.texts())
        tl = ler_json(projeto / "src/tl-reel.json")
        itens = []
        for i, s in enumerate(tl["scenes"]):
            if i < len(mostradas):
                itens.append({"comp": "Reel916", "nome": f"cena-{s['type']}",
                              "frame": min(tl["total"] - 1, s["cut"] + int(0.7 * s["len"]))})
            if i and s["in"] in trans:
                # no cut exato a troca cobre a tela (panel, iris): 1/4 antes mostra as duas cenas se cruzando
                itens.append({"comp": "Reel916", "nome": f"transicao-{s['in']}", "frame": s["cut"] - s["d"] // 4})
        return itens + [{"comp": "Reel", "nome": f"reel-{i}", "frame": cut + span // 2} for i, cut, span in reel]

    renderizar(projeto, saida, montar)
    (saida / "index.html").write_text(pagina(marca(projeto), cenas, mostradas, trans, reel, presets(projeto)), encoding="utf-8")
    return saida


# Guia segura (esquerda, direita, topo, base) em px do formato: a do useL() no Film e a do qa.sh no Reel.
GUIA = {"Reel916": (1080, 1920, 90, 180, 200, 340), "Master169": (1920, 1080, 120, 120, 96, 96),
        "Reel": (1080, 1920, 90, 180, 180, 320)}


def pagina_pior(nome, itens):
    e = html.escape

    def fig(it):
        w, h, l, r, t, b = GUIA[it["comp"]]
        guia = f"left:{l / w:.2%};right:{r / w:.2%};top:{t / h:.2%};bottom:{b / h:.2%}"
        return (f'  <figure class="{"h" if w > h else "v"}"><div class="q"><img src="{e(it["nome"])}.png" alt="{e(it["nome"])}">'
                f'<i style="{guia}"></i></div><figcaption><b>{e(it["titulo"])}</b><br>{e(it["comp"])}</figcaption></figure>')
    return f"""<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pior caso motion-reel: {e(nome)}</title>
<style>
  body {{ margin: 0; padding: 24px 16px; font: 16px/1.4 system-ui, sans-serif; background: #f4f4f5; color: #18181b; }}
  h1 {{ font-size: 22px; margin: 0 0 4px; }} p {{ margin: 0 0 16px; color: #52525b; }}
  main {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 16px; }}
  figure {{ margin: 0; background: #fff; border-radius: 10px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,.12); }}
  figure.h {{ grid-column: span 2; }}
  .q {{ position: relative; }} img {{ display: block; width: 100%; background: #000; }}
  .q i {{ position: absolute; border: 2px solid rgba(239,68,68,.9); pointer-events: none; }}
  figcaption {{ padding: 8px 10px 12px; font-size: 13px; color: #3f3f46; }}
</style>
</head>
<body>
<h1>Pior caso motion-reel: {e(nome)}</h1>
<p>Textos no limite documentado e no limite + 1 (presets/{PIOR}), num quadro já assentado. A linha vermelha é a guia segura: texto fora dela, ou cortado na borda, reprova.</p>
<main>
{chr(10).join(fig(it) for it in itens)}
</main>
</body>
</html>
"""


def pior_caso(projeto):
    """Bancada de texto: cada cena do pior-caso.json em 9:16 e 16:9 e o Grande do Reel com cada palavra."""
    projeto = projeto.resolve()
    checar_projeto(projeto)
    fonte = arquivo(projeto, f"presets/{PIOR}")
    if not fonte.is_file():
        raise SystemExit(f"!! sem presets/{PIOR} no projeto nem na skill")
    film = ler_json(fonte)
    saida = projeto / "out/galeria-pior-caso"
    sc = ler_json(arquivo(projeto, "src/timeline.json"))["scenes"]
    # Grande assentado: 2 quadros antes de a transição de saída começar (o whip borra a palavra)
    grande = next(((s, sc[i + 1] if i + 1 < len(sc) else None) for i, s in enumerate(sc) if s["id"] == "grande"), None)

    def montar(bt):
        itens = []
        for nome, comp in (("reel", "Reel916"), ("master", "Master169")):
            bt.build(nome, film[nome], film, bt.texts())
            tl = ler_json(projeto / f"src/tl-{nome}.json")
            for i, s in enumerate(tl["scenes"]):
                # quadro já assentado: 10 antes do fim da cena (o corte seco do "current" não cruza)
                fim = tl["scenes"][i + 1]["cut"] if i + 1 < len(tl["scenes"]) else tl["total"]
                rot = (s["props"].get("kicker") or "").strip()
                itens.append({"comp": comp, "nome": f"pior-{nome}-{i:02d}-{s['type']}", "frame": fim - 10,
                              "titulo": f"{s['type']}" + (f": {rot}" if rot else "")})
        if grande:
            s, prox = grande
            quadro = prox["cut"] - prox.get("d", 0) // 2 - 2 if prox else s["cut"] + 30
            for k, palavra in enumerate(film.get("grande", [])):
                itens.append({"comp": "Reel", "nome": f"pior-grande-{k}", "frame": quadro,
                              "props": {"props": {"grande": {"word": palavra}}},
                              "titulo": f"Grande: {palavra} ({len(palavra)} letras)"})
        return itens

    itens = renderizar(projeto, saida, montar)
    (saida / "index.html").write_text(pagina_pior(marca(projeto), itens), encoding="utf-8")
    return saida


def main():
    # Terminal do Windows em cp1252: "→" e "×" da listagem não podem derrubar o script.
    for fluxo in (sys.stdout, sys.stderr):
        fluxo.reconfigure(encoding="utf-8", errors="replace")
    args = sys.argv[1:]
    if args and args[0] == "--lista":
        listar(Path(args[1]).resolve() if len(args) > 1 else None)
        return
    pior = "--pior-caso" in args
    args = [a for a in args if a != "--pior-caso"]
    if len(args) != 1 or args[0].startswith("-"):
        raise SystemExit("uso: galeria.py <projeto> [--pior-caso]  |  galeria.py --lista [projeto]")
    pasta = (pior_caso if pior else galeria)(Path(args[0]))
    print(f"galeria: {pasta / 'index.html'}")


if __name__ == "__main__":
    main()
