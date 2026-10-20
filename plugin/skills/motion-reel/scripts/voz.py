#!/usr/bin/env python3
"""Narração grátis do Film: um WAV de 48 kHz mono por fala do vo.json, na voz do sistema.

    python3 ${CLAUDE_PLUGIN_ROOT}/skills/motion-reel/scripts/voz.py <projeto> [id ...] [--voz NOME]
                                                    [--taxa 182] [--refazer] [--qualquer-voz]

macOS: `say`. Windows: System.Speech pelo PowerShell 5.1. Voz: a Luciana quando instalada; senão a
primeira em português do Brasil que não é voz de novidade (Eddy, Flo...); outra com --voz.
O texto vai por arquivo UTF-8, nunca pela linha de comando, e passa antes pelo `say` do blocks.json
(troca de pronúncia, só no áudio).
Saída em <projeto>/public/vo/<id>.wav, sem silêncio nas pontas, que é o que o build-timeline.py mede.
Cache por hash em public/vo/.voz.json: cada WAV gerado guarda o hash da entrada (texto depois da
pronúncia, voz, taxa) e o do próprio arquivo. Fala editada, troca nova no `say` ou taxa nova geram de
novo só o que mudou. WAV sem entrada no manifesto, ou trocado depois de gerado, é gravação da pessoa e
fica como está, mesmo com --refazer; só o id na linha de comando o substitui.
No fim roda o build-timeline.py e recusa se sobrar fala sem voz.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

WINDOWS = os.name == "nt"
TAXA = 182
MANIFESTO = ".voz.json"
PREFERIDA = "Luciana"
# Vozes de novidade/Eloquence do macOS: existem em pt-BR e vêm antes da Luciana na ordem alfabética.
NOVIDADE = {"Eddy", "Flo", "Grandma", "Grandpa", "Reed", "Rocko", "Sandy", "Shelley"}
SAY_VOZ = re.compile(r"^(.*?\S)\s+([a-z]{2,3}_[A-Za-z0-9]+)\s+#")
# Corta o silêncio do começo e do fim da fala: a cena anima em cima do início medido.
APARA = ("silenceremove=start_periods=1:start_threshold=-50dB,areverse,"
         "silenceremove=start_periods=1:start_threshold=-50dB,areverse")

# Só ASCII: vai como -EncodedCommand. Sem MOTION_VOZ_MANIFESTO lista as vozes; com ele, fala cada linha num WAV.
PS_SCRIPT = r"""
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Speech
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
if (-not $env:MOTION_VOZ_MANIFESTO) {
  foreach ($v in $s.GetInstalledVoices()) {
    if ($v.Enabled) { [Console]::Out.WriteLine($v.VoiceInfo.Name + "`t" + $v.VoiceInfo.Culture.Name) }
  }
  exit 0
}
$m = [System.IO.File]::ReadAllText($env:MOTION_VOZ_MANIFESTO, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
if ($m.voz) { $s.SelectVoice($m.voz) }
foreach ($f in $m.falas) {
  $s.SetOutputToWaveFile($f.saida)
  $s.Speak($f.texto)
  $s.SetOutputToNull()
}
$s.Dispose()
"""

SEM_VOZ_MAC = (
    "!! este Mac não tem voz em português do Brasil instalada.\n"
    "Para baixar: Ajustes do Sistema > Acessibilidade > Conteúdo Falado > Voz do Sistema > Gerenciar Vozes,"
    " escolha Português (Brasil) e baixe uma voz. Depois rode de novo.\n"
    "Outra saída grátis: gravar a própria voz (references/narracao.md)."
)
SEM_VOZ_WINDOWS = (
    "!! o Windows não tem voz em português do Brasil instalada.\n"
    "Para instalar: Configurações > Hora e idioma > Fala > Adicionar vozes, escolha Português (Brasil)"
    " e espere baixar. Depois rode de novo.\n"
    "Outra saída grátis: gravar a própria voz (references/narracao.md)."
)
SEM_MOTOR = (
    "!! sem voz do sistema aqui: a narração grátis usa o `say` do macOS ou o PowerShell do Windows.\n"
    "Fora deles, a saída grátis é gravar a própria voz e cortar com o split-vo.py (references/narracao.md)."
)


def rodar(args, **kw):
    return subprocess.run(args, check=True, capture_output=True, **kw)


def powershell(env=None):
    script = base64.b64encode(PS_SCRIPT.encode("utf-16-le")).decode("ascii")
    return rodar(["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                  "-EncodedCommand", script], env={**os.environ, **(env or {})})


def vozes():
    """[(nome, idioma)] das vozes instaladas, com o idioma no formato pt-BR."""
    if WINDOWS:
        linhas = powershell().stdout.decode("utf-8", "replace").splitlines()
        return [tuple(l.strip().split("\t", 1)) for l in linhas if "\t" in l]
    saida = rodar(["say", "-v", "?"]).stdout.decode("utf-8", "replace")
    return [(m.group(1), m.group(2).replace("_", "-")) for m in map(SAY_VOZ.match, saida.splitlines()) if m]


def escolher_voz(lista, pedida=None, qualquer=False):
    if pedida:
        for nome, _ in lista:
            if nome.lower() == pedida.lower():
                return nome
        raise SystemExit(f"!! voz '{pedida}' não encontrada. Vozes instaladas: " + ", ".join(n for n, _ in lista))
    pt = [nome for nome, idioma in lista if idioma.lower() == "pt-br"]
    if PREFERIDA in pt:
        return PREFERIDA
    normais = [nome for nome in pt if nome.split(" (")[0] not in NOVIDADE]
    if pt:
        return (normais or pt)[0]
    if qualquer:
        print("aviso: sem voz pt-BR; usando a voz padrão do sistema (serve para testar, não para publicar).")
        return None
    raise SystemExit(SEM_VOZ_WINDOWS if WINDOWS else SEM_VOZ_MAC)


def pronuncia(texto, trocas):
    for de, para in trocas.items():
        texto = re.sub(rf"\b{re.escape(de)}\b", para, texto)
    return texto


def sha(dados):
    return hashlib.sha256(dados).hexdigest()


def entrada(texto, voz, taxa):
    """Hash do que define o áudio: mudou um dos três, o WAV gerado ficou velho."""
    return sha(json.dumps([texto, voz, taxa], ensure_ascii=False).encode("utf-8"))


def ler_manifesto(destino):
    try:
        falas = json.loads((destino / MANIFESTO).read_text(encoding="utf-8")).get("falas", {})
    except (OSError, ValueError, AttributeError):
        return {}
    return falas if isinstance(falas, dict) else {}


def gravar_manifesto(destino, falas):
    arq = destino / MANIFESTO
    temp = arq.with_name(arq.name + ".tmp")
    temp.write_text(json.dumps({"versao": 1, "falas": falas}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    os.replace(temp, arq)


def da_pessoa(wav, registro):
    """WAV que o voz.py não gerou (sem entrada) ou que mudou depois de gerado."""
    return wav.is_file() and (not registro or registro.get("wav") != sha(wav.read_bytes()))


def gerar(projeto, ids=(), voz=None, taxa=None, refazer=False, qualquer_voz=False):
    """Grava public/vo/<id>.wav das falas pendentes. Devolve os ids gerados."""
    falas = json.loads((projeto / "vo.json").read_text(encoding="utf-8"))["lines"]
    blocos = projeto / "blocks.json"
    trocas = json.loads(blocos.read_text(encoding="utf-8")).get("say", {}) if blocos.is_file() else {}
    conhecidos = {f["id"] for f in falas}
    fora = [i for i in ids if i not in conhecidos]
    if fora:
        raise SystemExit(f"!! id fora do vo.json: {', '.join(fora)}")
    destino = projeto / "public/vo"
    manifesto = ler_manifesto(destino)
    wav = {f["id"]: destino / f"{f['id']}.wav" for f in falas}
    pessoa = [f["id"] for f in falas if f["id"] not in ids and da_pessoa(wav[f["id"]], manifesto.get(f["id"]))]
    if pessoa:
        print(f"{len(pessoa)} fala(s) com WAV fora do manifesto (gravação sua, ou gerada antes do cache): "
              f"ficam como estão: {' '.join(pessoa)}. Para gerar de novo pela voz do sistema, passe os ids.")
    candidatas = [f for f in falas if (f["id"] in ids if ids else f["id"] not in pessoa)]
    if not candidatas:
        print("nenhuma fala para gerar")
        return []
    if not shutil.which("powershell.exe" if WINDOWS else "say"):
        raise SystemExit(SEM_MOTOR)
    nome = escolher_voz(vozes(), voz, qualquer_voz)
    if WINDOWS and taxa:
        print("aviso: --taxa só vale no macOS; no Windows a voz fala no ritmo dela.")
    taxa = None if WINDOWS else (taxa or TAXA)  # no Windows a taxa não muda o áudio: fica fora do hash
    hashes = {f["id"]: entrada(pronuncia(f["text"], trocas), nome, taxa) for f in candidatas}
    pendentes = [f for f in candidatas if ids or refazer or not wav[f["id"]].is_file()
                 or manifesto.get(f["id"], {}).get("entrada") != hashes[f["id"]]]
    if not pendentes:
        print("todas as falas geradas estão em dia com o texto, a voz e a taxa (--refazer gera de novo)")
        return []
    print(f"voz: {nome or 'padrão do sistema'}" + ("" if WINDOWS else f", taxa {taxa}"))
    destino.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        brutos = {}
        if WINDOWS:
            for f in pendentes:
                brutos[f["id"]] = temp / f"{f['id']}.wav"
            pedido = temp / "falas.json"
            pedido.write_text(json.dumps({"voz": nome, "falas": [
                {"texto": pronuncia(f["text"], trocas), "saida": str(brutos[f["id"]])} for f in pendentes]}),
                encoding="utf-8")
            powershell({"MOTION_VOZ_MANIFESTO": str(pedido)})
        else:
            for f in pendentes:
                texto, brutos[f["id"]] = temp / f"{f['id']}.txt", temp / f"{f['id']}.aiff"
                texto.write_text(pronuncia(f["text"], trocas), encoding="utf-8")
                rodar(["say", *(["-v", nome] if nome else []), "-r", str(taxa), "-f", str(texto),
                       "-o", str(brutos[f["id"]])])
        for f in pendentes:
            rodar(["ffmpeg", "-v", "error", "-y", "-i", str(brutos[f["id"]]), "-af", APARA, "-ac", "1",
                   "-ar", "48000", str(wav[f["id"]])])
            manifesto[f["id"]] = {"entrada": hashes[f["id"]], "wav": sha(wav[f["id"]].read_bytes())}
            gravar_manifesto(destino, manifesto)
            print(f"  {f['id']}: public/vo/{f['id']}.wav")
    return [f["id"] for f in pendentes]


def main():
    # Terminal do Windows em cp1252: acento e seta não podem derrubar o script na hora de imprimir.
    for fluxo in (sys.stdout, sys.stderr):
        fluxo.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description="Narração grátis (voz do sistema) para o Film da motion-reel.")
    parser.add_argument("projeto", type=Path)
    parser.add_argument("ids", nargs="*", help="só estas falas, geradas de novo mesmo que já tenham WAV")
    parser.add_argument("--voz", help="nome de uma voz instalada (padrão: Luciana, ou a primeira pt-BR que não é voz de novidade)")
    parser.add_argument("--taxa", type=int, help=f"palavras por minuto do say, só macOS (padrão: {TAXA})")
    parser.add_argument("--refazer", action="store_true", help="gera de novo todas as falas")
    parser.add_argument("--qualquer-voz", action="store_true", help="sem voz pt-BR, usa a voz padrão do sistema")
    args = parser.parse_args()
    projeto = args.projeto.resolve()
    if not (projeto / "vo.json").is_file():
        raise SystemExit(f"!! {projeto / 'vo.json'} não existe: crie o projeto com o new.sh da skill")
    try:
        gerar(projeto, args.ids, args.voz, args.taxa, args.refazer, args.qualquer_voz)
    except FileNotFoundError as erro:
        raise SystemExit(f"!! programa não encontrado: {erro.filename}")
    except subprocess.CalledProcessError as erro:
        detalhe = (erro.stderr or b"").decode("utf-8", "replace").strip()
        raise SystemExit(f"!! {Path(erro.cmd[0]).name} falhou: {detalhe or erro}")
    # O build-timeline mede cada WAV: sem aviso de duração estimada, toda fala tem voz.
    # O filho herda o encoding do terminal (cp1252 no Windows): força UTF-8 para ler o aviso com acento.
    timeline = subprocess.run([sys.executable, str(projeto / "scripts/build-timeline.py")], cwd=projeto,
                              capture_output=True, text=True, encoding="utf-8", errors="replace",
                              env={**os.environ, "PYTHONUTF8": "1", "PYTHONIOENCODING": "utf-8"})
    print(timeline.stdout.rstrip())
    if timeline.returncode:
        raise SystemExit(timeline.stderr.strip() or "!! build-timeline.py falhou")
    if "duração estimada" in timeline.stdout:
        raise SystemExit("!! ainda há fala sem WAV: confira os ids do vo.json e do film.json")


if __name__ == "__main__":
    main()
