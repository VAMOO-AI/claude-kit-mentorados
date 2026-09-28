#!/usr/bin/env bash
# UserPromptSubmit: avisa VOCÊ quando o contexto da sessão passa de tamanhos que pesam — uma
# vez por faixa, não a cada prompt.
#
# Cada tool call relê a conversa inteira, então o total de tokens relidos cresce com o
# QUADRADO do comprimento da sessão. Medido no time em 22/08/2026: sessões com 100+
# requests concentraram 97,8% do cache read da semana. O aviso precisa chegar antes, não
# depois.
#
# Cada linha sai com o prefixo `@usuario `: o pre-prompt.sh manda essas linhas para a sua
# tela (systemMessage), fora do contexto do modelo. Dentro do contexto o aviso virava
# contagem regressiva — medido no time em 22/09/2026: depois dele, 13,8% das respostas
# falavam em /clear ou /compact, contra 2,7% nas demais.
#
# A medida é o contexto real do último turno, não o comprimento do transcript: o transcript
# só cresce, inclusive depois do /compact, e o aviso que manda rodar /compact seguia
# repetindo depois dele. Faixas: 150K e 300K, as mesmas cores do `ctx` na barra de status,
# e dali em diante a cada +100K (400K, 500K, …). Avisar uma vez só não segurava: no time, de
# 19 a 26/09/2026, 14 de 14 sessões que passaram do aviso do topo seguiram, em média +358
# requests, e no app desktop não há barra de status para frear depois.
#
# Lê o payload e o transcript via node (sem depender de jq). Falha-aberta: erro => exit 0.
command -v node >/dev/null 2>&1 || exit 0

# Só os últimos 256 KB do transcript, que passa de 100 MB em sessão longa, e isto roda a
# cada prompt. Contexto = input + cache_read + cache_creation do último usage de assistente.
# Com o advisor, o usage de cima soma as iterações e dá o dobro do contexto: vale a última
# iteração "message" ou "fallback_message" (a do modelo de fallback), nunca "advisor_message"
# ou "compaction". Usage zerado (<synthetic>: limite atingido, login vencido) não é turno.
# Compact depois do último usage deixa o número velho: silêncio até o próximo turno. A
# linha partida no começo da janela não passa no JSON.parse e fica de fora.
out=$(node -e '
  const fs = require("fs");
  let raw = "";
  process.stdin.on("data", (d) => { raw += d; }).on("end", () => {
    let p; try { p = JSON.parse(raw); } catch { return; }
    const sid = String((p && p.session_id) || ""), tp = String((p && p.transcript_path) || "");
    if (!sid || !tp) return;
    let tail = "";
    try {
      const fd = fs.openSync(tp, "r");
      try {
        const size = fs.fstatSync(fd).size, len = Math.min(size, 262144);
        const buf = Buffer.alloc(len);
        fs.readSync(fd, buf, 0, len, size - len);
        tail = buf.toString("utf8");
      } finally { fs.closeSync(fd); }
    } catch { return; }
    const n = (v) => Number(v) || 0;
    let ctx = 0;
    for (const l of tail.split("\n")) {
      let e; try { e = JSON.parse(l); } catch { continue; }
      if (!e || typeof e !== "object" || e.isSidechain === true) continue;
      if (e.type === "system" && e.subtype === "compact_boundary") { ctx = 0; continue; }
      if (e.type !== "assistant") continue;
      let u = e.message && e.message.usage;
      if (!u || typeof u !== "object") continue;
      if (Array.isArray(u.iterations)) {
        const it = u.iterations.filter((i) => i && (i.type === "message" || i.type === "fallback_message"));
        if (it.length) u = it[it.length - 1];
      }
      const t = n(u.input_tokens) + n(u.cache_read_input_tokens) + n(u.cache_creation_input_tokens);
      if (t > 0) ctx = t;
    }
    if (ctx > 0) process.stdout.write(sid + "\n" + ctx);
  });
' 2>/dev/null) || exit 0
sid=${out%%$'\n'*}
ctx=${out#*$'\n'}
# O session_id vira nome de arquivo: barra ou ponto no começo sairiam da pasta de estado.
case "$sid" in ''|*/*|.*) exit 0 ;; esac
case "$ctx" in ''|*[!0-9]*) exit 0 ;; esac

if   [ "$ctx" -ge 300000 ]; then faixa=$(( ctx / 100000 * 100 ))
elif [ "$ctx" -ge 150000 ]; then faixa=150
else faixa=0
fi

# A faixa avisada, em K, muda nos dois sentidos: sobe com o aviso e desce com o /compact,
# para o aviso voltar só quando o contexto crescer de novo até a faixa seguinte. Um salto de
# várias faixas dá um aviso só. Grava antes de avisar: estado que não grava ou não se lê de
# volta cala o aviso, que sem ele voltaria a cada prompt.
s="$HOME/.claude/.cache/session-size-faixa/$sid"
[ -e "$s" ] && [ ! -r "$s" ] && exit 0
prev=""; { read -r prev < "$s"; } 2>/dev/null
case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
[ "$faixa" -eq "$prev" ] && exit 0
mkdir -p "${s%/*}" 2>/dev/null
{ printf '%s' "$faixa" > "$s"; } 2>/dev/null || exit 0
[ "$faixa" -lt "$prev" ] && exit 0

k=$(( ctx / 1000 ))
if   [ "$faixa" -ge 400 ]; then echo "@usuario 🚨 session-size: ~${k}K tokens relidos a cada passo do Claude. É a faixa das sessões-maratona. Abra uma sessão nova no projeto, ou rode /compact."
elif [ "$faixa" -ge 300 ]; then echo "@usuario ⚠️ session-size: ~${k}K tokens relidos a cada passo do Claude. Rode /compact agora, ou abra uma sessão nova no projeto se o assunto mudou."
else                            echo "@usuario 📊 session-size: ~${k}K tokens de contexto relidos a cada passo do Claude. Se a tarefa atual acabou, abra uma sessão nova no projeto para o próximo assunto."
fi
exit 0
