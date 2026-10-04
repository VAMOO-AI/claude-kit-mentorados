#!/usr/bin/env python3
"""vo.json + blocks.json → out/vo-blocks/<bloco>.txt: o texto exato a mandar para o TTS.

Um bloco = várias falas numa geração só (a voz fica coerente entre elas). Cada fala recebe as
tags de direção de blocks.json["tags"][id] na frente (ex.: "[softly] [slowly]"), as trocas de
pronúncia de blocks.json["say"] (ex.: "Claude" → "Cláudi", só no áudio: a tela continua
"Claude") e um "[long pause]" no fim, que vira o silêncio onde o split-vo.py corta.
Imprime a contagem de caracteres por bloco: no ElevenLabs o custo é ~1 crédito por caractere,
tags incluídas.
Uso: blocks-text.py [bloco ...]
"""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    B = json.loads((ROOT / "blocks.json").read_text())
    L = {l["id"]: l["text"] for l in json.loads((ROOT / "vo.json").read_text())["lines"]}
    say, tags = B.get("say", {}), B.get("tags", {})
    out = ROOT / "out/vo-blocks"; out.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[1:])
    total = 0
    for b, ids in B["blocks"].items():
        if only and b not in only:
            continue
        falas = []
        for k, i in enumerate(ids):
            t = L[i]
            for de, para in say.items():
                t = re.sub(rf"\b{re.escape(de)}\b", para, t)
            t = f"{tags[i]} {t}" if i in tags else t
            falas.append(t + (" [long pause]" if k < len(ids) - 1 else ""))
        txt = "\n\n".join(falas) + "\n"
        (out / f"{b}.txt").write_text(txt)
        total += len(txt)
        print(f"{b}: {len(ids)} falas, {len(txt)} caracteres → out/vo-blocks/{b}.txt")
    print(f"total: {total} caracteres · voz {B.get('voice_id')} · modelo {B.get('model')}")


if __name__ == "__main__":
    main()
