# 07 · Segredos: inventário, exposição e rotação

Duas perguntas definem o pilar. **Quais segredos este projeto tem?** e **o que
acontece se um deles vazar hoje?** Um projeto que não responde a primeira não
consegue responder a segunda.

Aqui não se trata de "não ter segredo em lugar errado" — trata-se de *saber onde
cada um está*, inclusive os que estão em lugar errado por decisão consciente.

## Contrato

- [ ] **Inventário completo**: o quê, onde vive, quem tem acesso, qual o raio de
      dano, quando rotaciona.
- [ ] `.env*` fora do git; `.env.example` commitado só com nomes.
- [ ] **Secret scan cobre HEAD e histórico, não só o diff.** Gate que só olha o
      diff é estruturalmente cego para o que já está lá.
- [ ] Nenhum segredo em arquivo versionado — ou, se houver, **exceção aceita**
      registrada com dono e data de revisão.
- [ ] Segredo de servidor nunca sob prefixo público (ver pilar 01).
- [ ] **Runbook de rotação escrito** e testado ao menos uma vez.
- [ ] Chave com prazo tem data de expiração conhecida e anotada.
- [ ] Um token por escopo: token de cliente A não abre porta de cliente B.

## Como implementar

**O inventário.** Uma tabela no contrato do projeto, e ela é o entregável central
deste pilar:

| Segredo | Onde vive | Raio de dano | Rotação | Dono |
|---|---|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | Vercel env + n8n cred | **total** — ignora RLS | manual, dashboard | Ruan |
| `SUPABASE_ANON_KEY` | bundle (por design) | limitado pela RLS | com o projeto | Ruan |
| `APP_WEBHOOK_SECRET` | Vercel env + n8n cred | permite forjar webhook | manual | Ruan |
| `OPENAI_API_KEY` | Supabase function secrets | custo | painel OpenAI | Ruan |
| senha de ERP | 1Password | acesso ao ERP | via fornecedor | cliente |

"Raio de dano" é a coluna que decide a prioridade. `anon` no bundle é esperado;
`service_role` em qualquer lugar que não seja servidor é incidente.

**Scan que enxerga o que já está lá.** O gate de PR deve varrer o diff (rápido),
mas o inventário exige varrer HEAD e histórico:

```bash
gitleaks detect --no-banner --redact -v                    # histórico completo
gitleaks dir --no-banner --redact .                        # working tree
trufflehog git file://. --only-verified --no-update        # confirma se AINDA vive
```

`--only-verified` do trufflehog testa a credencial contra a API real. Isso elimina
falso-positivo por construção — e **faz chamada de rede com a credencial do
cliente**, então precisa estar autorizado no escopo do contrato.

Para repo com dívida conhecida, use baseline em vez de desligar o gate:

```bash
gitleaks detect --report-path baseline.json               # tira a foto de hoje
gitleaks detect --baseline-path baseline.json             # daqui pra frente, só o novo
```

Baseline é honesto: reconhece a dívida, não a esconde. Desligar o scan do
histórico "porque reprovaria todo PR" produz um gate que nunca vai encontrar o que
já está no repositório.

**Decodificar sem vazar.** Para provar o que uma chave encontrada é, sem trazer o
valor pro contexto:

```bash
# payload de um JWT (role e expiração), sem imprimir a chave
python3 - <<'PY'
import base64, json, re, pathlib
tok = re.search(r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+', pathlib.Path('arquivo.json').read_text()).group()
p = tok.split('.')[1]; p += '=' * (-len(p) % 4)
d = json.loads(base64.urlsafe_b64decode(p))
print({k: d.get(k) for k in ('role','iss','ref','exp')})
PY
```

No report vai o fingerprint (`sha256` dos 12 primeiros caracteres) e o payload —
nunca a chave.

**Runbook de rotação.** Rotação sem ordem escrita derruba produção; o objetivo é
que a nova chave já esteja aceita antes de a antiga morrer.

1. **Mapear consumidores** — todo lugar que usa a chave (env do host, credencial
   do n8n, secret do CI, máquina de dev).
2. **Emitir a nova** sem revogar a antiga (janela de convivência).
3. **Atualizar consumidores**, do menos crítico ao mais crítico.
4. **Verificar** cada um com uma chamada real — não com "deploy passou".
5. **Revogar a antiga** e confirmar que algo que deveria falhar falha.
6. **Registrar** data, motivo e quem executou no contrato.

Se o passo 2 não for possível (a plataforma revoga ao gerar), isso é uma janela de
indisponibilidade planejada: avise antes, faça fora do horário, tenha o rollback
pronto.

**Exceção aceita.** Quando o segredo fica onde não deveria por limitação real —
por exemplo, um nó que não aceita credencial e exige o valor inline — a decisão é
legítima e precisa virar registro:

```markdown
| EX-01 | service_role em `scripts/build-*.cjs` e `n8n_workflows/*.json` |
| Motivo | O Code node do n8n não aceita credencial; o valor precisa estar no JSON importado |
| Mitigação | Repo privado; CODEOWNERS em `/scripts/`; chave sem escopo reduzido disponível |
| Risco aceito | Leitura do repo = acesso total ao banco, ignorando RLS |
| Dono | Ruan · Aceito em 2026-08-22 · Revisar em 2026-11-22 |
```

Sem esse bloco, toda auditoria reabre o assunto e você paga de novo pela mesma
decisão. Com ele, a auditoria mostra "1 exceção vigente" e segue.

## Como provar

```bash
# .env fora do git
git ls-files | grep -E '(^|/)\.env' || echo 'OK: nenhum .env versionado'
git check-ignore .env .env.local && echo 'OK: ignorados'

# .env.example tem só nomes?
grep -nE '=.+' .env.example | grep -vE '=\s*$|=\s*(your|<|xxx|CHANGE)' | head

# JWT no HEAD — o que o gate de diff nunca vai ver
git grep -lE 'eyJ[A-Za-z0-9_-]{10,}\.eyJ' -- . ':!*.lock' ':!node_modules'

# a chave existe no ambiente? (contagem, nunca valor)
grep -c '^SUPABASE_SERVICE_ROLE_KEY=' .env.local 2>/dev/null

# o gate de CI varre só o diff?
grep -rn 'gitleaks\|trufflehog' .github/workflows/ | head
```

O terceiro comando é o que separa inventário de teatro. Se ele devolve arquivos e
o CI passa verde, o gate está medindo a coisa errada.

## Armadilhas

| Sintoma | Causa real |
|---|---|
| CI verde e segredo vivo no repositório | Scan só no diff. O que já está no HEAD é invisível por construção |
| "É só um UUID pra validar chamada" | Se está sob prefixo público, está no bundle — e não valida mais nada |
| Rotação derrubou a integração | Consumidor não mapeado (credencial do n8n, secret do CI). Passo 1 do runbook existe por isso |
| Chave "temporária" de 2 anos atrás | Sem data de expiração anotada, nada força revisão. `exp` do JWT resolve |
| `.env` some ao copiar projeto entre máquinas | Copiar por cloud sync leva o segredo pra fora. Use gerenciador de segredo |
| Sobrescreveu o arquivo de tokens e perdeu tudo | Escrita em arquivo de credencial é sempre chave a chave, nunca `cat >` |
| Token de um cliente funciona em outro | Token compartilhado entre escopos. Um por org, sempre |
| Segredo apareceu no log | Estava na query string, ou o log não redigia header. Header + redação no logger (pilar 06) |
