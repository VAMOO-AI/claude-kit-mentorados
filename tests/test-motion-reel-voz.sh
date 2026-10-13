#!/usr/bin/env bash
# Narração grátis da motion-reel: o voz.py fala cada linha do vo.json com a voz do sistema
# (`say` no macOS, System.Speech pelo PowerShell no Windows) e grava public/vo/<id>.wav
# (48 kHz mono), no formato que o build-timeline.py já mede.
#
# Até a 0.49 o kit só ensinava o `say` em linhas soltas no narracao.md, sem a troca de
# pronúncia do blocks.json e sem caminho no Windows. Este teste prova o script sem depender
# do Mac nem do Windows: `say`, `powershell.exe` e `ffmpeg` são falsos no PATH (o ffmpeg falso
# grava um WAV válido de 1 s, porque o build-timeline abre o arquivo com `wave`).
#
#   1. sem --voz, usa a primeira voz pt-BR detectada (nenhum nome fixo); texto por arquivo,
#      nunca na linha de comando; aplica o `say` do blocks.json; WAV 48 kHz mono; timeline
#      sem duração estimada;
#   2. não sobrescreve gravação própria; id na linha de comando refaz só aquele;
#   3. sem voz pt-BR para e explica como baixar; --qualquer-voz segue com a padrão;
#   4. voz pedida que não existe e id que não está no vo.json recusam;
#   5. sem `say` nem PowerShell (Linux) para e aponta a gravação própria;
#   6. no Windows lista as vozes pelo PowerShell, escolhe a pt-BR e fala pelo manifesto UTF-8,
#      com a pronúncia trocada e sem texto de fala na linha de comando.
#
# Uso: bash tests/test-motion-reel-voz.sh [raiz-do-repo]
set -uo pipefail
RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SK="$RAIZ/plugin/skills/motion-reel"
VOZ="$SK/scripts/voz.py"
[ -f "$VOZ" ] || { echo "voz.py não encontrado em $VOZ"; exit 2; }
PY="$(command -v python3)" || { echo "python3 ausente"; exit 2; }

falhas=0
check() { # check <descrição> <ok|fail>
  if [ "$2" = ok ]; then printf '  ok    %s\n' "$1"
  else printf '  FALHA %s\n' "$1"; falhas=$((falhas+1)); fi
}
tem() { /usr/bin/grep -qF -- "$2" "$1" 2>/dev/null && echo ok || echo fail; }
naotem() { /usr/bin/grep -qF -- "$2" "$1" 2>/dev/null && echo fail || echo ok; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/motion-voz.XXXXXX")"
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp -d falhou"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
export LOG="$TMP/chamadas.log" TEXTOS="$TMP/textos.log" VOZES="$TMP/vozes.txt"

cat > "$BIN/say" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = -v ] && [ "${2:-}" = "?" ]; then cat "$VOZES"; exit 0; fi
printf 'say' >> "$LOG"; for a in "$@"; do printf ' [%s]' "$a" >> "$LOG"; done; echo >> "$LOG"
out=""; txt=""
while [ "$#" -gt 0 ]; do
  case "$1" in -o) out="$2"; shift ;; -f) txt="$2"; shift ;; esac; shift
done
[ -n "$txt" ] && { cat "$txt" >> "$TEXTOS"; echo >> "$TEXTOS"; }
printf 'FORM' > "$out"
SH
cat > "$BIN/ffmpeg" <<'SH'
#!/usr/bin/env bash
printf 'ffmpeg' >> "$LOG"; for a in "$@"; do printf ' [%s]' "$a" >> "$LOG"; done; echo >> "$LOG"
for a in "$@"; do out="$a"; done
python3 -c 'import sys, wave
w = wave.open(sys.argv[1], "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000)
w.writeframes(b"\0\0" * 48000); w.close()' "$out"
SH
chmod +x "$BIN/say" "$BIN/ffmpeg"

VOZES_PT='Albert              en_US    # Hello! My name is Albert.
Fernanda (Português (Brasil)) pt_BR    # Olá, meu nome é Fernanda.
Luciana             pt_BR    # Olá, meu nome é Luciana.
Samantha            en_US    # Hello! My name is Samantha.'

projeto() { # projeto <pasta>: copia o que o voz.py e o build-timeline leem do template
  local P="$1"
  mkdir -p "$P/scripts" "$P/src"
  cp "$SK/assets/template/film.json" "$SK/assets/template/blocks.json" "$P/"
  cp "$SK/assets/template/scripts/build-timeline.py" "$P/scripts/"
  "$PY" - "$SK/assets/template/vo.json" "$P/vo.json" <<'PY'
import json, sys
vo = json.load(open(sys.argv[1], encoding="utf-8"))
for l in vo["lines"]:
    if l["id"] == "t1":
        l["text"] = "O Claude confere tudo."
json.dump(vo, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
}
roda() { # roda <log> <args...>
  local out="$1"; shift
  PATH="$BIN:$PATH" "$PY" "$VOZ" "$@" > "$out" 2>&1
}

echo "1. voz pt-BR padrão, texto por arquivo, pronúncia, WAV e timeline"
P="$TMP/pasta com espaço ção/motion"; projeto "$P"
printf '%s\n' "$VOZES_PT" > "$VOZES"; : > "$LOG"; : > "$TEXTOS"
roda "$TMP/1.log" "$P"; rc=$?
check "sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/1.log"
n_vo="$("$PY" -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["lines"]))' "$P/vo.json")"
n_wav="$(ls "$P/public/vo/"*.wav 2>/dev/null | wc -l | tr -d ' ')"
check "um WAV por fala ($n_wav de $n_vo)" "$([ "$n_wav" = "$n_vo" ] && echo ok || echo fail)"
check "a primeira voz pt-BR detectada, com espaço e parênteses no nome" "$(tem "$LOG" '[-v] [Fernanda (Português (Brasil))]')"
check "velocidade padrão (-r 182)" "$(tem "$LOG" '[-r] [182]')"
check "texto vai por arquivo (-f)" "$(tem "$LOG" '[-f]')"
check "nenhum texto de fala na linha de comando" "$(naotem "$LOG" 'Segunda, nove da manhã')"
check "o say do blocks.json troca Claude por Cláudi no áudio" "$(tem "$TEXTOS" 'O Cláudi confere tudo.')"
check "o vo.json continua com a grafia da tela" "$(tem "$P/vo.json" 'O Claude confere tudo.')"
check "ffmpeg converte para mono 48 kHz" "$(tem "$LOG" '[-ac] [1]')"
check "ffmpeg converte para 48 kHz" "$(tem "$LOG" '[-ar] [48000]')"
check "timeline do master gerada" "$([ -s "$P/src/tl-master.json" ] && echo ok || echo fail)"
check "timeline sem duração estimada" "$(naotem "$TMP/1.log" 'duração estimada')"
check "nenhum .aiff sobra em public/vo" "$(ls "$P/public/vo/"*.aiff >/dev/null 2>&1 && echo fail || echo ok)"

echo "2. gravação própria fica; id na linha de comando refaz só ele"
# gravação da pessoa: WAV válido de 2 s (o build-timeline mede), reconhecida pelo hash
"$PY" -c 'import sys, wave
w = wave.open(sys.argv[1], "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000)
w.writeframes(b"\1\0" * 96000); w.close()' "$P/public/vo/a1.wav"
hash_a1() { "$PY" -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$P/public/vo/a1.wav"; }
H1="$(hash_a1)"; : > "$LOG"
roda "$TMP/2a.log" "$P"; rc=$?
check "sem fala pendente sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "não chama o say" "$(naotem "$LOG" 'say')"
check "a gravação da pessoa continua" "$([ "$(hash_a1)" = "$H1" ] && echo ok || echo fail)"
: > "$LOG"
roda "$TMP/2b.log" "$P" a2; rc=$?
check "id pedido sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "fala só o id pedido" "$([ "$(/usr/bin/grep -c '^say' "$LOG")" = 1 ] && echo ok || echo fail)"
check "a gravação de outro id segue intacta" "$([ "$(hash_a1)" = "$H1" ] && echo ok || echo fail)"

echo "3. sem voz pt-BR"
P3="$TMP/p3"; projeto "$P3"
printf 'Albert              en_US    # Hello!\n' > "$VOZES"; : > "$LOG"
roda "$TMP/3a.log" "$P3"; rc=$?
check "para com erro (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
check "explica onde baixar a voz" "$(tem "$TMP/3a.log" 'Conteúdo Falado')"
check "não grava WAV" "$([ -e "$P3/public/vo/a1.wav" ] && echo fail || echo ok)"
roda "$TMP/3b.log" "$P3" --qualquer-voz; rc=$?
check "--qualquer-voz segue (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
check "--qualquer-voz chama o say sem -v" "$(/usr/bin/grep '^say' "$LOG" | /usr/bin/grep -qF '[-v]' && echo fail || echo ok)"

echo "4. pedidos que não existem"
printf '%s\n' "$VOZES_PT" > "$VOZES"
roda "$TMP/4a.log" "$P3" --refazer --voz Inexistente; rc=$?
check "voz inexistente recusa (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
check "a recusa lista as vozes instaladas" "$(tem "$TMP/4a.log" 'Luciana')"
roda "$TMP/4b.log" "$P3" zz9; rc=$?
check "id fora do vo.json recusa (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
check "a recusa cita o id" "$(tem "$TMP/4b.log" 'zz9')"

echo "5. sem say (fora do Mac)"
SEM="$TMP/semsay"; mkdir -p "$SEM"; ln -s "$BIN/ffmpeg" "$SEM/ffmpeg"; ln -s "$PY" "$SEM/python3"
PATH="$SEM" "$PY" "$VOZ" "$P3" --refazer > "$TMP/5.log" 2>&1; rc=$?
check "para com erro (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
check "aponta a gravação própria" "$(tem "$TMP/5.log" 'gravar')"

echo "6. Windows: System.Speech pelo PowerShell"
# O ramo do Windows roda aqui com WINDOWS forçado e um powershell.exe falso: sem
# MOTION_VOZ_MANIFESTO ele lista as vozes (nome<TAB>cultura); com ele, lê o manifesto e grava
# um arquivo por fala, anotando a voz e o texto.
cat > "$BIN/powershell.exe" <<'SH'
#!/usr/bin/env bash
printf 'powershell' >> "$LOG"; for a in "$@"; do printf ' [%s]' "$a" >> "$LOG"; done; echo >> "$LOG"
if [ -z "${MOTION_VOZ_MANIFESTO:-}" ]; then
  printf 'Microsoft Zira Desktop\ten-US\nMicrosoft Maria Desktop\tpt-BR\n'; exit 0
fi
python3 -c 'import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
with open(sys.argv[2], "a", encoding="utf-8") as log:
    log.write("voz=%s\n" % m["voz"])
    for f in m["falas"]:
        log.write(f["texto"] + "\n")
        open(f["saida"], "wb").write(b"RIFF")' "$MOTION_VOZ_MANIFESTO" "$TEXTOS"
SH
chmod +x "$BIN/powershell.exe"
cat > "$TMP/windows.py" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("voz", sys.argv[1])
voz = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voz)
voz.WINDOWS = True
sys.argv = ["voz.py", sys.argv[2]]
voz.main()
EOF
P6="$TMP/p6 ção"; projeto "$P6"; : > "$LOG"; : > "$TEXTOS"
PATH="$BIN:$PATH" "$PY" "$TMP/windows.py" "$VOZ" "$P6" > "$TMP/6.log" 2>&1; rc=$?
check "sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/6.log"
n_wav="$(ls "$P6/public/vo/"*.wav 2>/dev/null | wc -l | tr -d ' ')"
check "um WAV por fala ($n_wav de $n_vo)" "$([ "$n_wav" = "$n_vo" ] && echo ok || echo fail)"
check "escolhe a voz pt-BR do Windows" "$(tem "$TEXTOS" 'voz=Microsoft Maria Desktop')"
check "o say do blocks.json troca Claude por Cláudi no áudio" "$(tem "$TEXTOS" 'O Cláudi confere tudo.')"
check "o script vai codificado (-EncodedCommand)" "$(tem "$LOG" '[-EncodedCommand]')"
check "nenhum texto de fala na linha de comando" "$(naotem "$LOG" 'Segunda, nove da manhã')"
check "não chama o say" "$(/usr/bin/grep -q '^say' "$LOG" && echo fail || echo ok)"
check "ffmpeg converte para mono 48 kHz" "$(tem "$LOG" '[-ar] [48000]')"
check "timeline sem duração estimada" "$(naotem "$TMP/6.log" 'duração estimada')"

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
