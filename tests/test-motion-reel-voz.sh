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
#   1. sem --voz, prefere a Luciana entre as pt-BR detectadas; texto por arquivo,
#      nunca na linha de comando; aplica o `say` do blocks.json; WAV 48 kHz mono; timeline
#      sem duração estimada;
#   2. não sobrescreve gravação própria; id na linha de comando refaz só aquele;
#   3. sem voz pt-BR para e explica como baixar; --qualquer-voz segue com a padrão;
#   4. voz pedida que não existe e id que não está no vo.json recusam;
#   5. sem `say` nem PowerShell (Linux) para e aponta a gravação própria;
#   6. no Windows lista as vozes pelo PowerShell, escolhe a pt-BR e fala pelo manifesto UTF-8,
#      com a pronúncia trocada e sem texto de fala na linha de comando;
#   7. com o terminal em cp1252 (Windows), o aviso do build-timeline ("duração") não derruba o
#      voz.py com UnicodeDecodeError: ele recusa com a mensagem de fala sem WAV;
#   8. escolha da voz: Luciana quando instalada; senão a primeira pt-BR que não é voz de
#      novidade (Eddy, Flo, Grandma...); senão a primeira pt-BR;
#   9. --taxa vale nos dois: say -r no macOS e Rate do System.Speech no Windows
#      (round(10·log3(taxa/182)), de −10 a 10). Fora de 90–300 recusa;
#   10. pronúncia casa termo com ponto ou cerquilha (.env, C#, node.js), não só palavra.
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
cat > "$BIN/ffprobe" <<'SH'
#!/usr/bin/env bash
printf '1.0\n'
SH
chmod +x "$BIN/say" "$BIN/ffmpeg" "$BIN/ffprobe"

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
check "prefere a Luciana entre as pt-BR" "$(tem "$LOG" '[-v] [Luciana]')"
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
    log.write("rate=%s\n" % m["rate"])
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
sys.argv = ["voz.py", *sys.argv[2:]]
voz.main()
EOF
P6="$TMP/p6 ção"; projeto "$P6"; : > "$LOG"; : > "$TEXTOS"
PATH="$BIN:$PATH" "$PY" "$TMP/windows.py" "$VOZ" "$P6" > "$TMP/6.log" 2>&1; rc=$?
check "sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/6.log"
n_wav="$(ls "$P6/public/vo/"*.wav 2>/dev/null | wc -l | tr -d ' ')"
check "um WAV por fala ($n_wav de $n_vo)" "$([ "$n_wav" = "$n_vo" ] && echo ok || echo fail)"
check "escolhe a voz pt-BR do Windows" "$(tem "$TEXTOS" 'voz=Microsoft Maria Desktop')"
check "taxa padrão vira Rate 0" "$(tem "$TEXTOS" 'rate=0')"
check "não avisa que --taxa só vale no macOS" "$(naotem "$TMP/6.log" 'só vale no macOS')"
check "o say do blocks.json troca Claude por Cláudi no áudio" "$(tem "$TEXTOS" 'O Cláudi confere tudo.')"
check "o script vai codificado (-EncodedCommand)" "$(tem "$LOG" '[-EncodedCommand]')"
check "nenhum texto de fala na linha de comando" "$(naotem "$LOG" 'Segunda, nove da manhã')"
check "não chama o say" "$(/usr/bin/grep -q '^say' "$LOG" && echo fail || echo ok)"
check "ffmpeg converte para mono 48 kHz" "$(tem "$LOG" '[-ar] [48000]')"
check "timeline sem duração estimada" "$(naotem "$TMP/6.log" 'duração estimada')"

echo "7. terminal em cp1252 (Windows)"
# Só a fala a1 ganha WAV: o build-timeline avisa "duração estimada" das outras. Com
# PYTHONIOENCODING=cp1252 herdado, o filho escrevia o aviso em cp1252 e a leitura em UTF-8
# estrito estourava fora do try.
P7="$TMP/p7"; projeto "$P7"; printf '%s\n' "$VOZES_PT" > "$VOZES"
PYTHONIOENCODING=cp1252 PATH="$BIN:$PATH" "$PY" "$VOZ" "$P7" a1 > "$TMP/7.log" 2>&1; rc=$?
check "recusa com erro (veio $rc)" "$([ "$rc" = 1 ] && echo ok || echo fail)"
check "sem traceback de encoding" "$(/usr/bin/grep -q 'Traceback\|UnicodeDecodeError\|UnicodeEncodeError' "$TMP/7.log" && echo fail || echo ok)"
check "diz que sobrou fala sem WAV" "$(tem "$TMP/7.log" 'fala sem WAV')"

echo "8. escolha da voz"
cat > "$TMP/escolha.py" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("voz", sys.argv[1])
voz = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voz)
pt = lambda *nomes: [(n, "pt-BR") for n in nomes]
casos = {
    "luciana": (pt("Eddy (Português (Brasil))", "Flo (Português (Brasil))", "Luciana"), "Luciana"),
    "novidade": (pt("Eddy (Português (Brasil))", "Grandma (Português (Brasil))", "Reed (Português (Brasil))",
                    "Fernanda (Português (Brasil))"), "Fernanda (Português (Brasil))"),
    "windows": ([("Microsoft Zira Desktop", "en-US")] + pt("Microsoft Maria Desktop"), "Microsoft Maria Desktop"),
    "so-novidade": (pt("Rocko (Português (Brasil))", "Sandy (Português (Brasil))"), "Rocko (Português (Brasil))"),
}
for nome, (lista, esperado) in casos.items():
    veio = voz.escolher_voz(lista)
    print(nome, "ok" if veio == esperado else f"fail (veio {veio})")
EOF
"$PY" "$TMP/escolha.py" "$VOZ" > "$TMP/8.log" 2>&1
for k in "luciana:Luciana quando instalada, mesmo depois das vozes de novidade" \
         "novidade:sem Luciana, pula Eddy, Grandma e Reed" "windows:Windows: a pt-BR do sistema" \
         "so-novidade:só voz de novidade: a primeira pt-BR"; do
  check "${k#*:}" "$(/usr/bin/grep -qx "${k%%:*} ok" "$TMP/8.log" && echo ok || echo fail)"
done
/usr/bin/grep -v ' ok$' "$TMP/8.log" | sed 's/^/        /'

echo "9. --taxa (90–300) no say e no Rate do Windows"
printf '%s\n' "$VOZES_PT" > "$VOZES"; : > "$LOG"
roda "$TMP/9a.log" "$P" --refazer --taxa 220; rc=$?
check "taxa 220 sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/9a.log"
check "say recebe -r 220" "$(tem "$LOG" '[-r] [220]')"
check "a saída cita a taxa 220" "$(tem "$TMP/9a.log" 'taxa 220')"
roda "$TMP/9b.log" "$P" --refazer --taxa 89; rc=$?
check "abaixo de 90 recusa (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
check "a recusa cita a faixa" "$(tem "$TMP/9b.log" '90')"
roda "$TMP/9c.log" "$P" --refazer --taxa abc; rc=$?
check "taxa que não é número recusa (veio $rc)" "$([ "$rc" != 0 ] && echo ok || echo fail)"
: > "$TEXTOS"
PATH="$BIN:$PATH" "$PY" "$TMP/windows.py" "$VOZ" "$P6" --refazer --taxa 220 > "$TMP/9d.log" 2>&1; rc=$?
check "Windows com taxa 220 sai 0 (veio $rc)" "$([ "$rc" = 0 ] && echo ok || echo fail)"
[ "$rc" = 0 ] || sed 's/^/        /' "$TMP/9d.log"
rate220="$("$PY" -c 'import math; print(max(-10, min(10, round(10 * math.log(220 / 182, 3)))))')"
check "taxa 220 vira Rate $rate220 no manifesto" "$(tem "$TEXTOS" "rate=$rate220")"
check "a saída do Windows cita a taxa 220" "$(tem "$TMP/9d.log" 'taxa 220')"
check "não avisa que --taxa só vale no macOS" "$(naotem "$TMP/9d.log" 'só vale no macOS')"

echo "10. pronúncia com ponto e cerquilha"
cat > "$TMP/pronuncia.py" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("voz", sys.argv[1])
voz = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voz)
trocas = {".env": "ponto env", "C#": "cê sharp", "node.js": "node jota esse"}
sai = voz.pronuncia("Leia o .env, use C# e node.js agora.", trocas)
ok = ("ponto env" in sai and "cê sharp" in sai and "node jota esse" in sai
      and ".env" not in sai and "C#" not in sai and "node.js" not in sai)
print("troca", "ok" if ok else f"fail ({sai})")
parcial = voz.pronuncia("my.env e xnode.jsy e CC#.", trocas)
okp = (".env" in parcial and "node.js" in parcial and "C#" in parcial
       and "ponto env" not in parcial and "cê sharp" not in parcial)
print("parcial", "ok" if okp else f"fail ({parcial})")
import math
def esp(taxa):
    return max(-10, min(10, round(10 * math.log(taxa / 182, 3))))
casos = {182: esp(182), 220: esp(220), 90: esp(90), 300: esp(300), 1: -10, 100000: 10}
okt = all(voz.rate_windows(t) == e for t, e in casos.items())
print("rate", "ok" if okt else "fail " + " ".join(f"{t}->{voz.rate_windows(t)}" for t in casos))
try:
    voz.taxa_valida("89"); print("faixa", "fail (89 passou)")
except Exception:
    try:
        voz.taxa_valida("301"); print("faixa", "fail (301 passou)")
    except Exception:
        print("faixa", "ok" if voz.taxa_valida("90") == 90 and voz.taxa_valida("300") == 300 else "fail")
EOF
"$PY" "$TMP/pronuncia.py" "$VOZ" > "$TMP/10.log" 2>&1
for k in "troca:troca .env, C# e node.js" "parcial:não troca no meio de outra palavra" \
         "rate:Rate do Windows segue log3 e o teto -10..10" "faixa:taxa_valida fica em 90–300"; do
  check "${k#*:}" "$(/usr/bin/grep -qx "${k%%:*} ok" "$TMP/10.log" && echo ok || echo fail)"
done
/usr/bin/grep -v ' ok$' "$TMP/10.log" | sed 's/^/        /'

echo
if [ "$falhas" -eq 0 ]; then echo "tudo verde"; else echo "$falhas falha(s)"; exit 1; fi
