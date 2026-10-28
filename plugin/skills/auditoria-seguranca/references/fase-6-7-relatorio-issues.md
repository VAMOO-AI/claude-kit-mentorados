# auditoria-seguranca — Fase 6 (findings.json e PDF) e Fase 7 (issues)

Lido antes de escrever o findings.json, gerar o PDF ou montar as issues, e antes de copiar o trecho de qualquer achado de segredo.

## Fase 6 — findings.json e o PDF

O relatório é gerado por script, não escrito à mão: os números do resumo e dos
gráficos saem dos mesmos dados da tabela, e não podem discordar.

```bash
mkdir -p docs/security-audit
cp "${CLAUDE_PLUGIN_ROOT}/skills/auditoria-seguranca/scripts/gerar-relatorio.py" docs/security-audit/
# escreva docs/security-audit/findings.json (schema em references/findings-schema.md)
python3 docs/security-audit/gerar-relatorio.py docs/security-audit/findings.json --verificar --raiz .
python3 docs/security-audit/gerar-relatorio.py docs/security-audit/findings.json \
  --out docs/security-audit/relatorio-auditoria-seguranca.pdf
```

O `--verificar` é a regra "trecho copiado, não reescrito de memória" virando
código: arquivo existe, linhas cabem nele, cada linha do trecho está lá,
`corroborado` tem `fonte`, `caminho` vai de entrada a sink, issue cita achado
que existe. Ele **falha alto** —
corrija o JSON, não o contorne. Rodou sem `--raiz`? A saída diz que o código não
foi conferido, e isso não é "pronto".

**Achado de segredo (A4) não copia a linha.** O `trecho` copiado com `sed -n` traz o valor
para a conversa, que é o vazamento que o achado denuncia. O achado leva `arquivo`, `linhas`
e o tipo (no título e no `por_que`), e o `trecho` é a linha cortada no valor, com a máscara
da A4 e a anotação no fim. O `--verificar` aceita porque o corte é pedaço da linha real e a
anotação `//` no fim é tolerada:

```bash
# trecho de achado de segredo: troque <linha> e <arquivo>. Linha sem segredo reconhecido
# não imprime nada e sai 1; aí o achado fica só com arquivo:linha e o tipo.
sed -n '<linha>p' <arquivo> | python3 -c '
import re, sys
l = open(0, encoding="utf-8", errors="replace").read().rstrip("\n")
pads = [r"(sk-(?:proj|ant|svcacct|admin)-[A-Za-z0-9_-]{16,}|[rs]k-[A-Za-z0-9_-]{16,}|[rs]k_(?:live|test)_[A-Za-z0-9]{16,}|eyJ[A-Za-z0-9._-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|SG\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{40,}|whsec_[A-Za-z0-9+/=]{16,})",
        r"(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|xapp-[A-Za-z0-9-]{10,}|glpat-[A-Za-z0-9_-]{20,}|sb[ps]_[A-Za-z0-9_-]{12,}|sb_secret_[A-Za-z0-9_-]{16,}|shpat_[A-Za-z0-9_-]{12,}|npm_[A-Za-z0-9]{36,}|hf_[A-Za-z0-9]{30,})",
        r"(-----BEGIN [A-Z ]*PRIVATE KEY-----)",
        r"[A-Za-z][A-Za-z0-9+.-]*://[^:/\s@]*:((?!\$\{|\$[A-Z_][A-Z0-9_]*@)[^\s@/{][^\s@/]*)@",
        r"\$\{[A-Za-z_][A-Za-z0-9_]*:?-([^}]+)\}",
        r"(?i)(?:api[_-]?key|secret|token|passw(?:or)?d|pwd|senha|private[_-]?key)[A-Za-z0-9_]*[\x27\"]?\s*[:=>]{1,2}\s*[\x27\"]([^\x27\"\n]{8,})[\x27\"]",
        r"(?i)(?:api[_-]?key|secret|token|passw(?:or)?d|pwd|senha|private[_-]?key)[A-Za-z0-9_]*[\x27\"]?\s*[:=>]{1,2}\s*[\x27\"]?([^\x27\"\s,;]{8,})"]
achados = sorted((g.start(1), g.group(1)) for p in pads for g in re.finditer(p, l))
if not achados: sys.exit("nenhum segredo reconhecido nesta linha: o trecho não sai")
i, v = achados[0]
print(l[max(0, i - 60):i] + ("" if len(v) <= 12 else v[:4]) + "  // valor mascarado")'
```

`api_key: "sk-proj-…"` na linha 2 vira `api_key: "sk-p  // valor mascarado`. O corte fica
no primeiro valor da linha, com até 60 caracteres antes dele: num bundle minificado, a
linha inteira é o arquivo. Por isso a lista cobre tudo o que o gerador do relatório redige, e o
teste de paridade do kit reprova nos dois sentidos: chaves OpenAI (inclusive `sk-svcacct-` e
`sk-admin-`), Anthropic, Stripe, AWS, Google (`AIza`), SendGrid (`SG.`), JWT, tokens do GitHub,
Slack, GitLab, Supabase (`sbp_`, `sbs_`, `sb_secret_`), Shopify, npm (`npm_`) e Hugging Face
(`hf_`), `whsec_`, bloco de chave privada, a senha de `scheme://user:senha@`, o default
`${var:-valor}` ou `${var-valor}` e a atribuição a chave de senha ou segredo, com ou sem aspas.
Na senha de URL, só `${…}` e `$NOME` de env (maiúsculas e `_`) são referência: `$ecret` é senha.
O que ela reconhece nunca fica antes do corte, e a janela impressa sai sem segredo conhecido. Se
a lista não reconhecer um formato, ele pode sair cru nos 60 caracteres. Leia a janela antes de
colar.

O PDF imprime **"Rastreabilidade de compliance"** sozinho: cada achado acionável
é etiquetado nos controles de OWASP 2025/API/LLM/ISO/NIST/SOC2/PCI que viola,
herdando o default da sua categoria. É etiqueta sobre o achado já provado — não
muda severidade nem veredito, e não substitui certificação. Declare
`compliance` no achado quando o subtipo pede precisão (SSRF, chave de
assinatura, deputado confuso) ou o dado alcançado é pessoal (`LGPD:Art.46`).
Controle fora do formato da norma vigente aborta a geração mesmo sem
`--verificar`. Mapa, formatos e justificativas em `references/compliance-map.md`.

Sem dependência: stdlib + Chrome/Chromium já instalado (HTML → servidor HTTP
efêmero → `--print-to-pdf`). O servidor não é firula: o rodapé nativo do Chrome
é o único que sabe numerar `3/12`, e ele imprime a URL do documento — abrindo
`file://` o PDF entregue ao cliente carregaria o caminho absoluto da sua máquina.

**Verifique o PDF antes de entregar** (a regra de screenshot vale: no máximo
duas páginas rasterizadas, e só porque aqui o pixel é a evidência):

```bash
pdfinfo docs/security-audit/relatorio-auditoria-seguranca.pdf | head -3
pdftoppm -png -r 68 -f 2 -l 2 docs/security-audit/relatorio-auditoria-seguranca.pdf /tmp/pg
```

Olhe a página do resumo: rótulo de barra cortado, rosca sem legenda e tabela
transbordando são defeitos de entrega, não detalhe.

## Fase 7 — Issues

Cada achado acionável vira uma issue completa (`[Segurança] <falha>`, labels
`security` + severidade, problema, evidência com `arquivo:linha`, impacto,
correção, critérios de aceite verificáveis). O gerador já emite tudo entre
`--- ISSUE n ---` e `--- FIM ISSUE n ---` a partir do `findings.json`.

Lead `a_validar` **não** vira issue de segurança: vira a pergunta ao dono do
deploy, com o `plano_validacao.dono` como corpo. Nota de `hardening[]` vira
issue comum, sem label `security`, se o time quiser — o gerador não a emite.

Critério de aceite bom é executável: *"requisição com id de outro tenant devolve
404"* vale; *"corrigir o IDOR"* não vale. E quando o achado for bug de
comportamento, o critério inclui **o teste falhando no commit anterior ao fix** —
verde sozinho não prova regressão nenhuma.
