#!/usr/bin/env python3
"""Gera imagem pela API de imagens da OpenAI e devolve um JPEG pronto para a web.

Uso:
    python3 gerar-imagem.py --prompt-file p.txt --out hero.jpg
    python3 gerar-imagem.py --prompt "..." --out foto.jpg --size 1024x1024 --largura 1600
    python3 gerar-imagem.py --listar-modelos

A chave é procurada nesta ordem, e o script SEMPRE imprime de onde ela veio:
    1. $OPENAI_API_KEY
    2. ~/.codex/.env.tokens
    3. .env / .env.local do diretório atual
    4. --env-file <caminho>
Chave que vem de fora do diretório atual aparece com aviso: o custo cai na conta
daquele projeto. Isso é de propósito — descobrir na fatura é pior.

O modelo NÃO é fixo. O default abaixo era o melhor em setembro/2026; rode
--listar-modelos antes de assumir que ainda é.
"""
import argparse, base64, json, os, pathlib, re, subprocess, sys, tempfile, time, urllib.error, urllib.request

MODELO_PADRAO = "gpt-image-2.5-sunburst"
API = "https://api.openai.com/v1"


def _da_linha(texto):
    m = re.match(r'\s*(?:export\s+)?OPENAI_API_KEY\s*=\s*["\']?([^"\'\s]+)', texto)
    return m.group(1) if m else None


def _do_arquivo(caminho):
    p = pathlib.Path(caminho).expanduser()
    if not p.is_file():
        return None
    try:
        for linha in p.read_text(encoding="utf-8", errors="replace").splitlines():
            chave = _da_linha(linha)
            if chave:
                return chave
    except OSError:
        return None
    return None


def carregar_chave(env_file=None):
    if os.environ.get("OPENAI_API_KEY"):
        return os.environ["OPENAI_API_KEY"], "$OPENAI_API_KEY"
    candidatos = []
    if env_file:
        candidatos.append(env_file)
    candidatos += ["~/.codex/.env.tokens", ".env", ".env.local"]
    for c in candidatos:
        chave = _do_arquivo(c)
        if chave:
            return chave, str(pathlib.Path(c).expanduser())
    sys.exit(
        "Nenhuma OPENAI_API_KEY encontrada.\n"
        "Procurei em: $OPENAI_API_KEY, ~/.codex/.env.tokens, ./.env, ./.env.local\n"
        "Coloque a chave da SUA conta em ~/.codex/.env.tokens (fora de qualquer repo)\n"
        "ou aponte outra com --env-file."
    )


def pedir(caminho, chave, payload=None, timeout=300):
    dados = json.dumps(payload).encode() if payload else None
    req = urllib.request.Request(
        f"{API}/{caminho}", data=dados,
        headers={"Authorization": f"Bearer {chave}", "Content-Type": "application/json"},
    )
    try:
        return json.load(urllib.request.urlopen(req, timeout=timeout))
    except urllib.error.HTTPError as e:
        sys.exit(f"API respondeu {e.code}: {e.read()[:400].decode(errors='replace')}")


def para_jpeg(png_bytes, destino, largura):
    """PNG -> JPEG redimensionado. ffmpeg desta máquina não tem encoder webp."""
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp.write(png_bytes)
        origem = tmp.name
    try:
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-i", origem,
             "-vf", f"scale={largura}:-2", "-q:v", "4", destino],
            check=True,
        )
    except FileNotFoundError:
        pathlib.Path(destino).with_suffix(".png").write_bytes(png_bytes)
        print("ffmpeg ausente: salvei o PNG original, sem redimensionar.")
        return
    finally:
        os.unlink(origem)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--prompt")
    ap.add_argument("--prompt-file")
    ap.add_argument("--out", default="imagem.jpg")
    ap.add_argument("--model", default=MODELO_PADRAO)
    ap.add_argument("--size", default="1536x1024", help="1536x1024 (3:2), 1024x1536 (2:3), 1024x1024")
    ap.add_argument("--largura", type=int, default=1400, help="largura final do JPEG")
    ap.add_argument("--env-file")
    ap.add_argument("--listar-modelos", action="store_true")
    a = ap.parse_args()

    chave, origem = carregar_chave(a.env_file)
    fora = not str(origem).startswith("$") and not str(pathlib.Path(origem).expanduser()).startswith(os.getcwd())
    print(f"chave: {origem}" + ("  ⚠️  fora do diretório atual — o custo cai nessa conta" if fora else ""))

    if a.listar_modelos:
        ids = sorted(m["id"] for m in pedir("models", chave, timeout=60)["data"])
        print("\n".join(i for i in ids if "image" in i or "dall" in i))
        return

    prompt = a.prompt or (pathlib.Path(a.prompt_file).read_text(encoding="utf-8") if a.prompt_file else None)
    if not prompt:
        sys.exit("Faltou --prompt ou --prompt-file. Escreva o prompt com a skill diretor-imagem.")

    t = time.time()
    d = pedir("images/generations", chave, {"model": a.model, "prompt": prompt, "size": a.size, "n": 1})
    item = d["data"][0]
    bruto = base64.b64decode(item["b64_json"]) if item.get("b64_json") else urllib.request.urlopen(item["url"]).read()
    para_jpeg(bruto, a.out, a.largura)
    kb = pathlib.Path(a.out).stat().st_size // 1024 if pathlib.Path(a.out).exists() else 0
    print(f"{a.out}  {kb}KB  ({a.model}, {a.size}, {time.time() - t:.0f}s)")


if __name__ == "__main__":
    main()
