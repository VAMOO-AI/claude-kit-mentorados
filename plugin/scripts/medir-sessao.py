#!/usr/bin/env python3
"""Mede o que uma sessão do Claude Code carregou antes do seu primeiro prompt.

Lê o transcript da sessão (~/.claude/projects/<projeto>/<id>.jsonl) e mostra, por
sessão: de onde ela abriu (app desktop, terminal, SDK), a versão do Claude Code, o
diretório, quantos tokens o primeiro request já custou e quantas ferramentas MCP
chegaram, por servidor. É o número que a skill harness-check pede antes de cortar
qualquer coisa: "a sessão nasce cara" vira MEDIDO em vez de palpite.

Por que desktop e terminal nascem diferentes: o app desktop recebe os conectores da
sua conta do claude.ai mesmo com `"disableClaudeAiConnectors": true` (essa opção só
corta o carregamento automático do CLI). No kit do time, em 14/09/2026, mesma conta e
mesmo diretório: 296 tools/17 servidores no desktop contra 56/3 no terminal, e de
+22k a +32k tokens no primeiro request.

Uso:
  python3 medir-sessao.py                       # a última sessão, de qualquer superfície
  python3 medir-sessao.py --ultimas 5           # as 5 mais recentes
  python3 medir-sessao.py --cwd ~/projetos/app  # só sessões abertas nesse diretório
  python3 medir-sessao.py --comparar            # desktop x terminal lado a lado
  python3 medir-sessao.py <arquivo.jsonl | id-da-sessao>

Colunas: nascimento = tokens do primeiro request (MEDIDO, do `usage` que a API devolve);
tools = ferramentas MCP anunciadas à sessão; "?" quando o transcript não registra a
lista (o terminal nem sempre registra) — aí a fonte é o /context, não este script.
Só lê arquivos; não manda nada para lugar nenhum. Só biblioteca padrão do Python.
"""
import argparse
import collections
import glob
import json
import os
import re
import sys

BASE = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
PROJETOS = os.path.join(BASE, "projects")
TOOL_RE = re.compile(r'"(mcp__[A-Za-z0-9_.-]+__[A-Za-z0-9_.-]+)"')
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-", re.I)


def sessoes():
    return sorted(glob.glob(os.path.join(PROJETOS, "*", "*.jsonl")), key=os.path.getmtime, reverse=True)


def ler(caminho):
    """Varre o transcript uma vez: cabeçalho, 1º request e tools MCP anunciadas."""
    info = {"caminho": caminho, "entrypoint": None, "cwd": None, "versao": None,
            "nascimento": None, "tools": set(), "registrou_tools": False, "turnos": 0}
    with open(caminho, errors="ignore") as f:
        for linha in f:
            if info["entrypoint"] is None and '"entrypoint"' in linha:
                try:
                    d = json.loads(linha)
                except ValueError:
                    continue
                info["entrypoint"] = d.get("entrypoint")
                info["cwd"] = d.get("cwd")
                info["versao"] = d.get("version")
                continue
            if "deferred_tools" in linha:
                info["registrou_tools"] = True
            if "deferred_tools" in linha or "mcp_instructions" in linha:
                info["tools"] |= set(TOOL_RE.findall(linha))
            if '"assistant"' in linha:
                try:
                    d = json.loads(linha)
                except ValueError:
                    continue
                if d.get("type") != "assistant" or d.get("isSidechain"):
                    continue
                info["turnos"] += 1
                if info["nascimento"] is None:
                    u = (d.get("message") or {}).get("usage") or {}
                    if u:
                        info["nascimento"] = (u.get("input_tokens", 0)
                                              + u.get("cache_creation_input_tokens", 0)
                                              + u.get("cache_read_input_tokens", 0))
    return info


def servidores(tools):
    return collections.Counter(t.split("__")[1] for t in tools)


def rotulo(servidor, tools):
    """Conector da conta chega só com UUID: mostra uma tool dele para dar nome à coisa."""
    if not UUID_RE.match(servidor):
        return servidor
    exemplo = next((t.split("__", 2)[2] for t in sorted(tools) if t.split("__")[1] == servidor), "?")
    return f"{servidor[:8]}({exemplo})"


def mostra(info, detalhe=True):
    srv = servidores(info["tools"])
    nasc = info["nascimento"]
    sem_lista = not info["tools"] and not info["registrou_tools"]
    n_tools = "?" if sem_lista else len(info["tools"])
    n_srv = "?" if sem_lista else len(srv)
    print(f'{os.path.basename(info["caminho"])[:8]}  {info["entrypoint"] or "?":15s} '
          f'{info["versao"] or "?":9s} nascimento={nasc if nasc is not None else "?":>7} '
          f'tools={n_tools:>4} servidores={n_srv:>3} turnos={info["turnos"]:>4}')
    print(f'          {info["cwd"]}')
    if detalhe and srv:
        topo = ", ".join(f"{rotulo(s, info['tools'])}:{n}" for s, n in srv.most_common(8))
        print(f"          {topo}")


def resolve(alvo):
    if os.path.isfile(alvo):
        return alvo
    achados = glob.glob(os.path.join(PROJETOS, "*", f"{alvo}*.jsonl"))
    if not achados:
        sys.exit(f"sessão não encontrada: {alvo}")
    return achados[0]


def main():
    p = argparse.ArgumentParser(
        prog="medir-sessao.py",
        description="Mostra o que uma sessão do Claude Code carregou antes do primeiro prompt: "
                    "superfície, versão, diretório, tokens do 1º request e tools MCP por servidor.")
    p.add_argument("alvo", nargs="?", help="caminho do .jsonl ou id (ou começo do id) da sessão")
    p.add_argument("--ultimas", type=int, default=1, metavar="N", help="mostra as N sessões mais recentes (padrão 1)")
    p.add_argument("--cwd", metavar="DIR", help="só sessões abertas nesse diretório (vale também com --comparar)")
    p.add_argument("--comparar", action="store_true",
                   help="a sessão mais recente de cada superfície (desktop, terminal, SDK), lado a lado")
    a = p.parse_args()

    if a.alvo:
        mostra(ler(resolve(a.alvo)))
        return

    todas = sessoes()
    if not todas:
        sys.exit(f"nenhuma sessão em {PROJETOS}")

    alvo_cwd = os.path.abspath(os.path.expanduser(a.cwd)) if a.cwd else None

    if a.comparar:
        por_ep = {}
        for caminho in todas[:400]:
            info = ler(caminho)
            ep = info["entrypoint"]
            if not ep or ep in por_ep or (alvo_cwd and info["cwd"] != alvo_cwd):
                continue
            por_ep[ep] = info
        if not por_ep:
            sys.exit("nenhuma sessão legível" + (f" em {alvo_cwd}" if alvo_cwd else ""))
        ordem = ["claude-desktop", "cli", "sdk-cli"]
        for ep in ordem + sorted(set(por_ep) - set(ordem)):
            if ep in por_ep:
                mostra(por_ep[ep])
        if len(por_ep) == 1:
            print("\nsó uma superfície encontrada: abra a outra (app ou terminal) no mesmo diretório e rode de novo.")
        if len({i["cwd"] for i in por_ep.values()}) > 1:
            print("\naviso: diretórios diferentes — o CLAUDE.md e o .context de cada projeto entram na conta. "
                  "Para comparar de verdade, use --cwd com um diretório aberto nas duas superfícies.")
        return

    mostrados = 0
    for caminho in todas:
        if mostrados >= a.ultimas:
            break
        info = ler(caminho)
        if alvo_cwd and info["cwd"] != alvo_cwd:
            continue
        mostra(info)
        mostrados += 1
    if mostrados == 0:
        sys.exit("nenhuma sessão bate com o filtro")


if __name__ == "__main__":
    main()
