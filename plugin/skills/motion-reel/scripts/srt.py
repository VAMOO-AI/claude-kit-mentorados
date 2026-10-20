#!/usr/bin/env python3
"""Legenda SRT do Film: o texto do vo.json (grafia da tela) no tempo em que a voz toca.

    python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/srt.py <projeto> <master|reel> <saida.srt>

Cada fala começa em (cut + beats[i]) / fps da cena no src/tl-<formato>.json, o mesmo ponto em que o
track_cinema.py põe a voz, e dura o WAV dela (public/vo/<id>.wav). Fala sem WAV deixa a legenda sem
tempo de verdade: o script recusa (exit 1) em vez de entregar tempo estimado. Filme sem voz nenhuma
sai com exit 3 e sem arquivo (não há o que legendar).
"""
import json
from pathlib import Path
import sys
import wave


def carimbo(seg):
    ms = max(0, round(seg * 1000))
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def legendas(projeto, formato):
    tl = json.loads((projeto / f"src/tl-{formato}.json").read_text(encoding="utf-8"))
    vo = projeto / "vo.json"
    textos = {l["id"]: l["text"] for l in json.loads(vo.read_text(encoding="utf-8"))["lines"]} if vo.is_file() else {}
    fps, saida, faltas = tl["fps"], [], []
    for cena in tl["scenes"]:
        for i, vid in enumerate(cena.get("vo", [])):
            wav = projeto / f"public/vo/{vid}.wav"
            if not wav.is_file():
                faltas.append(vid)
                continue
            with wave.open(str(wav)) as w:
                dur = w.getnframes() / w.getframerate()
            ini = (cena["cut"] + cena["beats"][i]) / fps
            saida.append((ini, ini + dur, textos.get(vid, "").strip()))
    return saida, faltas


def main():
    if len(sys.argv) != 4:
        raise SystemExit("uso: srt.py <projeto> <master|reel> <saida.srt>")
    projeto, formato, destino = Path(sys.argv[1]).resolve(), sys.argv[2], Path(sys.argv[3])
    falas, faltas = legendas(projeto, formato)
    if faltas:
        print(f"!! sem legenda: fala sem WAV ({' '.join(faltas)}), o tempo seria estimado. Gere a voz e rode de novo.")
        sys.exit(1)
    if not falas:
        print("sem legenda: o filme não tem fala")
        sys.exit(3)
    blocos = [f"{n}\n{carimbo(a)} --> {carimbo(b)}\n{t}\n" for n, (a, b, t) in enumerate(falas, 1) if t]
    destino.write_text("\n".join(blocos), encoding="utf-8")
    print(f"legenda: {destino} ({len(blocos)} falas)")


if __name__ == "__main__":
    main()
