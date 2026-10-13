#!/usr/bin/env python3
"""Storyboard do Film: um quadro por cena do film.json, para aprovar antes de construir.

Não gera voz e não gasta crédito. Sem WAV, a duração de cada fala é estimada pelo texto.
O quadro usa o stills.mjs do projeto (o mesmo renderStill da galeria); --sem-stills só
escreve a página e a tabela, com miniatura vazia.

    PY="$("${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/py.sh")"
    "$PY" "${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/storyboard.py" <projeto> \
        [--composicao Reel|Master169] [--sem-stills]

Reel é o corte 9:16 (composição Reel916). Master169 é o 16:9.
Saída: <projeto>/out/storyboard/index.html e storyboard.md.
"""
from __future__ import annotations

import argparse
import html
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys

# Nome na linha de comando → (chave do film.json, composição do Remotion).
COMPOSICOES = {
    "Reel": ("reel", "Reel916"),
    "Reel916": ("reel", "Reel916"),
    "Master169": ("master", "Master169"),
}
FPS, BEAT, CPS = 30, 15, 14
PNG_VAZIO = b"\x89PNG\r\n\x1a\n"


def ler_json(caminho: Path):
    try:
        return json.loads(caminho.read_text(encoding="utf-8"))
    except json.JSONDecodeError as erro:
        raise SystemExit(f"!! {caminho.name} não é JSON válido: {erro}") from erro


def python_da_skill() -> str:
    """O python que o py.sh da skill escolhe. Sem numpy por perto, o que está rodando."""
    py_sh = Path(__file__).resolve().parent / "py.sh"
    try:
        resultado = subprocess.run(
            ["bash", str(py_sh)], check=True, capture_output=True, text=True,
            encoding="utf-8", errors="replace",
        )
    except (OSError, subprocess.CalledProcessError):
        return sys.executable
    linhas = [linha.strip() for linha in (resultado.stdout or "").splitlines() if linha.strip()]
    return linhas[-1] if linhas else sys.executable


def textos(valor):
    if isinstance(valor, str):
        return [valor.strip()] if valor.strip() else []
    if isinstance(valor, bool) or valor is None:
        return []
    if isinstance(valor, (int, float)):
        return [str(valor)]
    if isinstance(valor, dict):
        valor = list(valor.values())
    if isinstance(valor, list):
        return [item for parte in valor for item in textos(parte)]
    return []


def falas_de(projeto: Path) -> dict:
    vo = projeto / "vo.json"
    if not vo.is_file():
        return {}
    dados = ler_json(vo)
    linhas = dados.get("lines", []) if isinstance(dados, dict) else []
    return {linha["id"]: linha.get("text", "") for linha in linhas if isinstance(linha, dict) and linha.get("id")}


def estimar(cenas: list, falas: dict):
    """A mesma conta do build-timeline.py quando a fala ainda não tem WAV."""
    saida, corte = [], 0
    for cena in cenas:
        pre, gap, post = cena.get("pre", 6), cena.get("gap", 8), cena.get("post", 8)
        extra = cena.get("gaps") or []
        t, fins = pre, []
        for j, vid in enumerate(cena.get("vo") or []):
            n = math.ceil(len(falas.get(vid, "")) / CPS * FPS) or 30
            fins.append(t + n)
            t += n + gap + (extra[j] if j < len(extra) else 0)
        length = (fins[-1] + post) if fins else 0
        length = max(length, cena.get("min", 45))
        length = math.ceil(length / BEAT) * BEAT
        saida.append({"cut": corte, "len": length})
        corte += length
    return saida, FPS


def montar_cenas(film_cenas: list, tempos: list, fps: int, falas: dict) -> list:
    cenas = []
    for i, (cena, tempo) in enumerate(zip(film_cenas, tempos), 1):
        tela = list(dict.fromkeys(textos(cena.get("props", {}))))
        fala = " ".join(falas.get(v, "").strip() for v in (cena.get("vo") or []) if falas.get(v, "").strip())
        duracao = tempo["len"] / fps
        cenas.append({
            "numero": i,
            "tipo": str(cena.get("type") or "cena"),
            "duracao": duracao,
            "inicio": tempo["cut"] / fps,
            "fim": (tempo["cut"] + tempo["len"]) / fps,
            "tela": " · ".join(tela),
            "fala": fala,
            "png": f"cena-{i:02d}.png",
        })
    return cenas


def fmt_s(segundos: float) -> str:
    return f"{segundos:.1f}".replace(".", ",") + " s"


def md_celula(texto: str) -> str:
    if not texto:
        return "—"
    return " ".join(texto.split()).replace("|", "\\|")


def pagina(composicao: str, comp: str, cenas: list) -> str:
    e = html.escape
    proporcao = "16 / 9" if comp == "Master169" else "9 / 16"
    total = fmt_s(sum(c["duracao"] for c in cenas))
    rotulo = "16:9" if comp == "Master169" else "corte 9:16"
    cards = []
    for c in cenas:
        cards.append(
            f'<article>\n'
            f'  <img src="{e(c["png"])}" alt="Cena {c["numero"]:02d}, {e(c["tipo"])}">\n'
            f'  <h2>Cena {c["numero"]:02d}</h2>\n'
            f'  <p>Tipo: {e(c["tipo"])}</p>\n'
            f'  <p>Duração estimada: {e(fmt_s(c["duracao"]))}</p>\n'
            f'  <p>Texto na tela: {e(c["tela"] or "—")}</p>\n'
            f'  <p>Fala: {e(c["fala"] or "—")}</p>\n'
            f'</article>'
        )
    miolo = "\n".join(cards)
    return f"""<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Storyboard {e(composicao)}</title>
<style>
  body {{ margin: 0; padding: 24px 16px 48px; font: 16px/1.45 system-ui, sans-serif; background: #f4f4f5; color: #18181b; }}
  h1 {{ font-size: 22px; margin: 0 0 4px; }}
  p.nota {{ margin: 0 0 20px; color: #52525b; max-width: 42rem; }}
  main {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; }}
  article {{ background: #fff; border-radius: 10px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,.12); }}
  img {{ display: block; width: 100%; aspect-ratio: {proporcao}; object-fit: cover; background: #e4e4e7; }}
  h2 {{ font-size: 16px; margin: 12px 12px 4px; }}
  article p {{ margin: 0 12px 8px; font-size: 14px; color: #3f3f46; }}
  article p:last-child {{ margin-bottom: 14px; }}
</style>
</head>
<body>
<h1>Storyboard {e(composicao)}</h1>
<p class="nota">{e(rotulo)}, composição {e(comp)}. {len(cenas)} cenas, duração estimada {e(total)}. Não gera voz. Voz paga e o render final só entram depois da aprovação desta página, cena a cena.</p>
<main>
{miolo}
</main>
</body>
</html>
"""


def tabela(composicao: str, comp: str, cenas: list) -> str:
    rotulo = "16:9" if comp == "Master169" else "corte 9:16"
    total = fmt_s(sum(c["duracao"] for c in cenas))
    linhas = [
        (
            f"| {c['numero']:02d} | {md_celula(c['tipo'])} | {fmt_s(c['duracao'])} "
            f"| {md_celula(c['tela'])} | {md_celula(c['fala'])} | |"
        )
        for c in cenas
    ]
    corpo = "\n".join(linhas)
    return f"""# Storyboard

Aprove ou ajuste cada cena nesta tabela. Este passo não gera voz. Voz paga e o render final só entram depois desta aprovação.

- Composição: {composicao} ({rotulo}, {comp})
- Cenas: {len(cenas)}
- Duração estimada total: {total}

| Cena | Tipo | Duração estimada | Texto na tela | Fala | Ajuste |
| --- | --- | --- | --- | --- | --- |
{corpo}
"""


def timeline(projeto: Path, formato: str, cenas: list, falas: dict):
    script = projeto / "scripts/build-timeline.py"
    if not script.is_file():
        raise SystemExit("!! o projeto não tem scripts/build-timeline.py: crie com o new.sh da skill")
    env = {**os.environ, "PYTHONUTF8": "1"}
    try:
        subprocess.run([python_da_skill(), str(script), formato], cwd=projeto, check=True, env=env)
    except subprocess.CalledProcessError as erro:
        raise SystemExit(f"!! a timeline do roteiro não saiu (build-timeline.py terminou com {erro.returncode})") from erro
    caminho = projeto / f"src/tl-{formato}.json"
    if not caminho.is_file():
        raise SystemExit(f"!! o build-timeline.py não gravou src/tl-{formato}.json")
    tl = ler_json(caminho)
    tempos = tl.get("scenes") or []
    if len(tempos) != len(cenas):
        raise SystemExit(
            f"!! o film.json tem {len(cenas)} cenas em {formato!r} e a timeline tem {len(tempos)}"
        )
    return tempos, tl.get("fps", FPS)


def renderizar(projeto: Path, comp: str, fracao: float, escala: float, n: int):
    if not (projeto / "scripts/stills.mjs").is_file():
        raise SystemExit("!! o projeto não tem scripts/stills.mjs: crie com o new.sh da skill")
    origem = projeto / f"out/stills-{comp}"
    shutil.rmtree(origem, ignore_errors=True)
    env = {**os.environ, "PYTHONUTF8": "1"}
    try:
        subprocess.run(
            ["node", "scripts/stills.mjs", comp, str(fracao), str(escala), *(str(i) for i in range(n))],
            cwd=projeto, check=True, env=env,
        )
        falha = None
    except (subprocess.CalledProcessError, OSError) as erro:
        falha = erro
    faltando = [str(i) for i in range(n) if not (origem / f"{i:03d}.png").is_file()]
    if faltando:
        motivo = f" ({falha})" if falha else ""
        raise SystemExit(f"!! os quadros das cenas {', '.join(faltando)} não saíram{motivo}")
    return origem, falha


def gravar(projeto: Path, composicao: str, sem_stills: bool, fracao: float, escala: float) -> Path:
    projeto = Path(projeto).resolve()
    if not (projeto / "film.json").is_file():
        raise SystemExit(f"!! {projeto} não tem film.json: crie o projeto com o new.sh da skill e escreva o roteiro")
    if composicao not in COMPOSICOES:
        raise SystemExit(f"!! composição {composicao!r}: use Reel ou Master169")
    formato, comp = COMPOSICOES[composicao]
    film = ler_json(projeto / "film.json")
    if not isinstance(film, dict):
        raise SystemExit("!! film.json não é um objeto")
    bloco = film.get(formato)
    if not isinstance(bloco, list) or not bloco:
        raise SystemExit(
            f"!! o film.json não tem cenas no formato {formato!r} ({composicao}). Use --composicao Reel ou Master169"
        )
    if not all(isinstance(cena, dict) for cena in bloco):
        raise SystemExit(f"!! as cenas de {formato!r} no film.json precisam ser objetos")
    falas = falas_de(projeto)
    if sem_stills and not (projeto / "scripts/build-timeline.py").is_file():
        tempos, fps = estimar(bloco, falas)
        aviso = None
        origem = None
    else:
        tempos, fps = timeline(projeto, formato, bloco, falas)
        if sem_stills:
            aviso, origem = None, None
        else:
            origem, aviso = renderizar(projeto, comp, fracao, escala, len(bloco))
    cenas = montar_cenas(bloco, tempos, fps, falas)
    pasta = projeto / "out/storyboard"
    pasta.mkdir(parents=True, exist_ok=True)
    for velho in pasta.glob("cena-*.png"):
        velho.unlink()
    for i, cena in enumerate(cenas):
        destino = pasta / cena["png"]
        if origem is None:
            destino.write_bytes(PNG_VAZIO)
        else:
            shutil.copyfile(origem / f"{i:03d}.png", destino)
    (pasta / "index.html").write_text(pagina(composicao, comp, cenas), encoding="utf-8")
    (pasta / "storyboard.md").write_text(tabela(composicao, comp, cenas), encoding="utf-8")
    if aviso:
        print(f"Aviso: quadros prontos, mas a folha de contato não saiu ({aviso})", file=sys.stderr)
    return pasta


def main(argv=None) -> int:
    os.environ["PYTHONUTF8"] = "1"
    for fluxo in (sys.stdout, sys.stderr):
        if hasattr(fluxo, "reconfigure"):
            fluxo.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("projeto", help="pasta do projeto Remotion (a que tem film.json)")
    parser.add_argument("--composicao", default="Reel", choices=tuple(COMPOSICOES),
                        help="Reel (corte 9:16, composição Reel916) ou Master169 (16:9)")
    parser.add_argument("--sem-stills", action="store_true",
                        help="não renderiza quadros; escreve a página e a tabela com miniatura vazia")
    parser.add_argument("--fracao", type=float, default=0.7, help="ponto da cena do quadro, de 0 a 1")
    parser.add_argument("--escala", type=float, default=0.4, help="escala do quadro")
    args = parser.parse_args(argv)
    if not 0 <= args.fracao <= 1:
        raise SystemExit(f"!! fração {args.fracao}: use um número de 0 a 1")
    if args.escala <= 0:
        raise SystemExit(f"!! escala {args.escala}: use um número maior que 0")
    pasta = gravar(Path(args.projeto), args.composicao, args.sem_stills, args.fracao, args.escala)
    print(f"→ storyboard: {pasta / 'index.html'} (sem voz)")
    print(pasta / "storyboard.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
