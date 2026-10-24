#!/usr/bin/env python3
"""Resolve a página de compartilhamento de vídeo para a URL direta do arquivo.

Suporta CleanShot (cleanshot.com/share/...), Loom, e qualquer página que exponha
og:video / <video src>. URLs que já apontam para um arquivo passam direto.

Uso: resolve-url.py <url>   -> imprime a URL direta em stdout
"""
import html
import json
import re
import sys
import urllib.request

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
FILE_EXT = (".mp4", ".mov", ".webm", ".m4v", ".mkv", ".m3u8")


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def unescape_all(page):
    """CleanShot serializa o state do Inertia com escapes em duas camadas."""
    out = html.unescape(page)
    return out.replace("\\u0022", '"').replace("\\u0026", "&")


def find(page, pattern):
    m = re.search(pattern, page)
    return m.group(1).replace("\\", "") if m else None


def resolve(url):
    if url.startswith(("/", "file://")) or url.lower().endswith(FILE_EXT):
        return url

    page = unescape_all(fetch(url))

    for pattern in (
        r'"download_url"\s*:\s*"([^"]+)"',      # CleanShot
        r'"video_url"\s*:\s*"([^"]+)"',
        r'"url"\s*:\s*"(https?:[^"]+\.mp4[^"]*)"',
        r'<meta[^>]+property="og:video(?::secure_url)?"[^>]+content="([^"]+)"',
        r'<video[^>]+src="([^"]+)"',
        r'<source[^>]+src="([^"]+)"',
    ):
        hit = find(page, pattern)
        if hit and hit.startswith("http") and ".mp4" in hit or (hit and hit.lower().endswith(FILE_EXT)):
            return hit

    raise SystemExit(f"não achei URL de vídeo em {url}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("uso: resolve-url.py <url>")
    print(resolve(sys.argv[1]))
