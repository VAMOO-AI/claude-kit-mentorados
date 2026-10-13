#!/usr/bin/env python3
"""Galeria do que o template já tem: cenas do Film, transições e cenas do Reel, com a marca do projeto.

    python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/galeria.py --lista [projeto]   # só o texto, sem render
    python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/galeria.py <projeto>             # <projeto>/out/galeria/index.html

Serve para escolher cena e transição antes de roteirizar. Tudo vem do código do projeto (ou do
template da skill, sem projeto): as cenas do mapa SCENES de src/film-scenes.tsx com o comentário de
props de cada uma, as transições do D do scripts/build-timeline.py e as cenas do src/timeline.json.
O Film sai em 9:16 (Reel916) com as props de exemplo do film.json (master); cada transição aparece a
um quarto da troca antes do corte. O film.json e o vo.json não mudam; o src/tl-reel.json é trocado durante o render e
devolvido no fim, mesmo se o render falhar.
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
RENDER = """import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import fs from "node:fs";
import path from "node:path";

const job = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const serveUrl = await bundle({ entryPoint: path.join(job.root, "src/index.tsx") });
const tl = JSON.parse(fs.readFileSync(path.join(job.root, "src/tl-reel.json"), "utf8"));
const props = { Reel916: { tl, audio: "x.wav", withAudio: false }, Reel: { withAudio: false } };
const comps = {};
for (const it of job.itens) {
  const inputProps = props[it.comp];
  comps[it.comp] ??= await selectComposition({ serveUrl, id: it.comp, inputProps });
  await renderStill({ composition: comps[it.comp], serveUrl, output: path.join(job.saida, it.nome + ".png"),
    frame: it.frame, inputProps, scale: job.scale });
}
"""


def arquivo(projeto, rel):
    p = (projeto / rel) if projeto else None
    return p if p and p.is_file() else TEMPLATE / rel


def ler_json(caminho):
    return json.loads(caminho.read_text(encoding="utf-8"))


def cenas_do_film(projeto):
    """{tipo: (componente, descrição)} na ordem do SCENES de film-scenes.tsx."""
    tsx = arquivo(projeto, "src/film-scenes.tsx").read_text(encoding="utf-8")
    bloco = re.search(r"export const SCENES[^=]*=\s*\{(.*?)\};", tsx, re.S)
    if not bloco:
        raise SystemExit("!! não achei o mapa SCENES em src/film-scenes.tsx")
    linhas = tsx.splitlines()
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
    for fonte in (projeto / "film.json", TEMPLATE / "film.json"):
        if fonte.is_file():
            for cena in ler_json(fonte).get("master", []):
                exemplos.setdefault(cena["type"], cena)
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


def pagina(nome, cenas, mostradas, trans, reel):
    e = html.escape

    def fig(arq, titulo, texto):
        return (f'  <figure><img src="{e(arq)}.png" alt="{e(titulo)}"><figcaption><b>{e(titulo)}</b>'
                f'<br>{e(texto)}</figcaption></figure>')
    film = "\n".join(fig(f"cena-{t}", t, f"{cenas[t][0]}: {cenas[t][1]}") for t in mostradas)
    trs = "\n".join(fig(f"transicao-{t}", t, "durante a troca") for t in trans)
    rl = "\n".join(fig(f"reel-{i}", i, "Reel (música)") for i, _, _ in reel)
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
</style>
</head>
<body>
<h1>Galeria motion-reel: {e(nome)}</h1>
<p>Um quadro de cada cena e de cada transição que o template já tem, com a marca do projeto. Os textos são os de exemplo.</p>
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


def galeria(projeto):
    projeto = projeto.resolve()
    for rel in ("film.json", "src/index.tsx", "scripts/build-timeline.py"):
        if not (projeto / rel).is_file():
            raise SystemExit(f"!! {projeto} não tem {rel}: crie o projeto com o new.sh da skill")
    cenas, trans, reel = cenas_do_film(projeto), transicoes(projeto), cenas_do_reel(projeto)
    spec, mostradas = roteiro(projeto, list(cenas), trans)
    tl_reel = projeto / "src/tl-reel.json"
    salvo = tl_reel.read_bytes() if tl_reel.is_file() else None
    saida = projeto / "out/galeria"
    saida.mkdir(parents=True, exist_ok=True)
    for velho in saida.glob("*.png"):
        velho.unlink()
    script, job = projeto / "out/galeria-render.mjs", projeto / "out/galeria-job.json"
    try:
        mod_spec = importlib.util.spec_from_file_location("motion_build_timeline", projeto / "scripts/build-timeline.py")
        bt = importlib.util.module_from_spec(mod_spec)
        mod_spec.loader.exec_module(bt)
        bt.build("reel", spec, {}, bt.texts())
        tl = ler_json(tl_reel)
        itens = []
        for i, s in enumerate(tl["scenes"]):
            if i < len(mostradas):
                itens.append({"comp": "Reel916", "nome": f"cena-{s['type']}",
                              "frame": min(tl["total"] - 1, s["cut"] + int(0.7 * s["len"]))})
            if i and s["in"] in trans:
                # no cut exato a troca cobre a tela (panel, iris): 1/4 antes mostra as duas cenas se cruzando
                itens.append({"comp": "Reel916", "nome": f"transicao-{s['in']}", "frame": s["cut"] - s["d"] // 4})
        itens += [{"comp": "Reel", "nome": f"reel-{i}", "frame": cut + span // 2} for i, cut, span in reel]
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
        if salvo is None:
            tl_reel.unlink(missing_ok=True)
        else:
            tl_reel.write_bytes(salvo)
    (saida / "index.html").write_text(pagina(marca(projeto), cenas, mostradas, trans, reel), encoding="utf-8")
    return saida


def main():
    args = sys.argv[1:]
    if args and args[0] == "--lista":
        listar(Path(args[1]).resolve() if len(args) > 1 else None)
        return
    if len(args) != 1 or args[0].startswith("-"):
        raise SystemExit("uso: galeria.py <projeto>  |  galeria.py --lista [projeto]")
    pasta = galeria(Path(args[0]))
    print(f"galeria: {pasta / 'index.html'}")


if __name__ == "__main__":
    main()
