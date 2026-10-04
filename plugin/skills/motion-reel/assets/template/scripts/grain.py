#!/usr/bin/env python3
"""Gera public/grain.png: tile 512×512 de ruído cinza (seed fixa) para o grão de película do Film.

PNG escrito à mão (zlib + struct): só precisa do numpy, que a trilha já exige.
"""
import pathlib, struct, zlib
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
S = 512


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def main():
    rng = np.random.default_rng(7)
    g = np.clip(rng.normal(128, 48, (S, S)), 0, 255).astype(np.uint8)
    raw = b"".join(b"\x00" + row.tobytes() for row in g)  # filtro 0 por linha
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 0, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    dst = ROOT / "public/grain.png"
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(png)
    print(f"{dst.name}: {S}×{S}, {len(png) // 1024} KB")


if __name__ == "__main__":
    main()
