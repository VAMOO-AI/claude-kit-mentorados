---
name: baseline
description: >-
  Postura de ambiente e segurança de app web (Vite/Next + Supabase + Vercel +
  n8n) em 8 pilares — bundle, RLS, auth, rate limit, cache, observabilidade,
  segredos, perímetro. Dois modos: CONSTRUIR (projeto novo nasce apto) e AUDITAR (app em
  produção está apto?). Use em "está pronto pra prod", "auditar produção",
  "hardening", "app novo do zero", "baseline". O gate do /ship já roda o
  collect.sh sozinho — aqui mora o método e o julgamento dos achados.
---

> Derivada de `claude-config-team/skills/vamoo-baseline`. Ao divergir de propósito, diga aqui o quê e por quê.

# baseline — Ambiente e Segurança

> Origem: escrito a partir da auditoria de um app real em produção (React + Vite
> + Supabase + Vercel). Quatro dos sete pilares aqui — sourcemap, rate limit de
> endpoint próprio, cache headers e error tracking — costumam só ser lembrados
> depois do primeiro incidente. Esta skill existe para inverter essa ordem.

Um padrão, dois modos. **A skill é o método; o contrato é o dado.** O método é
genérico e mora aqui. O contrato mora no repo auditado, em
`.context/docs/baseline.md`, e é ele que diz o que vale *neste* projeto — mesmo
modelo que o `/ship` já usa ao ler `.context/docs/deploy.md`.

## Fronteira — o que esta skill NÃO é

| Skill | Responde | Não confunda |
|---|---|---|
| **`baseline`** (esta) | "A plataforma está apta a produção? O inventário bate com o contrato?" | postura de ambiente |
| `secscan` | "Existe `service_role` em `src/`? Esse `eval` é explorável?" | scanner de código (SAST/SCA/CWE) |
| `verificacao` | "Já posso dizer que está pronto?" | prova de que funciona |


No pilar de código, **chame `secscan`** — não refaça SAST aqui.
Para fan-out por área com juiz adversarial, use `~/.claude/workflows/audit-multidim.js`.

---

## As quatro invariantes (nunca quebre)

1. **Dado indisponível nunca é evidência de risco.** Todo check resolve em
   `conforme`, `nao_conforme` ou `nao_medido` **com o motivo**. Nunca
   "provavelmente ok", nunca silêncio.
2. **Medição ausente nunca é veredito limpo.** Run que não mediu nada sai com
   exit≠0. Um relatório vazio parece aprovação e é o pior resultado possível.
3. **Cobertura é declarada.** "Nenhum achado" significa "nenhum entre o que foi
   medido". A tabela de cobertura é obrigatória no report — sem ela o report não
   está pronto.
4. **Leitura de código responde "existe?", não "funciona?".** Achado que afirma
   *comportamento* exige prova de execução. (15/08/2026: três itens foram
   fechados como "auditado e PRONTO" por grep; a gravação do cliente mostrou os
   três quebrados.)

---

## Modo CONSTRUIR

App novo, feature nova, ou primeira ida ao ar. Pode escrever código.

1. **Existe `.context/docs/baseline.md`?**
   Não → gere a partir de `references/contrato-template.md` e preencha o que der
   sem perguntar (stack, superfícies, runners). O que depende de decisão
   (retenção, quem é dono da rotação) fica marcado `PENDENTE:` — não invente.
2. **Leia só o pilar que a tarefa toca.** Tocou build/CSP → `01`. Tocou migration
   → `02`. Tocou rota/papel → `03`. Tocou edge/webhook ou login → `04`. Tocou
   query/lista → `05`. Tocou tratamento de erro → `06`. Tocou env/chave → `07`.
   Subiu host, painel ou domínio novo → `08`.
   Carregar os oito de uma vez é desperdício de contexto.
3. **Aplique o Contrato do pilar** usando o bloco "Como implementar" como ponto
   de partida, adaptado ao stack real do projeto — não cole cego.
4. **Prove.** Rode o comando do bloco "Como provar" e cole o output. Sem output,
   o item fica `nao_medido`, não `conforme`.
5. **Registre.** Atualize a tabela de estado do contrato. Se decidiu
   conscientemente ficar fora do padrão, isso é uma **exceção aceita** e vai na
   tabela com motivo, dono e data de revisão — não fica implícito.

### A regra que evita a maior parte do retrabalho

**Ordem importa em dois pares.** Ligar `dropConsole`/`drop_debugger` antes de
existir error tracking apaga o único rastro que você teria em produção. E criar
tabela antes da policy deixa uma janela em que ela nasce aberta ou deny-all
silencioso. Nos dois casos: a segunda peça entra **no mesmo PR** que a primeira.

---

## Modo AUDITAR

App em produção. **READ-ONLY é iron rule** — mesma regra do `secscan`.

> Nunca modifique, mova ou crie código/config no projeto auditado. Nunca faça DDL
> no banco (os lints rodam como `select`, sem criar schema `lint`). Nunca teste
> endpoint de terceiro. As únicas escritas permitidas são os artefatos da
> auditoria: `findings.json`, o report e o contrato.

Quatro fases. Aplicar correção é **fora** deste modo — vai pro modo CONSTRUIR,
com contexto de regressão.

| Fase | O que faz | Escreve |
|---|---|---|
| **1 Medir** | `doctor.sh` → `collect.sh`. Determinístico, zero julgamento | `findings.json` |
| **2 Julgar** | Severidade + confiança. Aplica exceções do contrato. Falso-positivo via `fp-check` | `report.md` |
| **3 Propor** | Correção concreta + comando de reconferência, por finding | nada |
| **4 Reconferir** | Roda o comando de reconferência e cola o output | nada |

```bash
SK="${CLAUDE_PLUGIN_ROOT}/skills/baseline"          # plugin: o Claude Code preenche ao carregar a skill
[ -d "$SK" ] || SK="$HOME/.claude/skills/baseline"   # instalação antiga pelo install.sh
OUT=/tmp/baseline-$(basename "$PWD")

bash $SK/scripts/doctor.sh  --out "$OUT"      # o que dá pra medir
bash $SK/scripts/collect.sh --out "$OUT"      # exit≠0 se não mediu nada
node   $SK/scripts/render.mjs "$OUT/findings.json" --out "$OUT/report.md"
```

`doctor.sh` sempre roda primeiro. Descobrir que falta `jq` no meio do collect é
caro; descobrir antes custa 200 ms.

### Fase 2 — julgar

O collect emite fatos, não vereditos. Você aplica, nesta ordem:

1. **Exceção aceita** no contrato e ainda dentro da validade → o finding sai do
   report principal e vai pra seção "Exceções aplicadas". Fora da validade → volta
   como finding, severidade original, com a nota de que a exceção venceu.
2. **Veredito anterior** em `.context/docs/security/vereditos.md` → não reabra
   falso-positivo já julgado. Registre novos ali, nunca com `nosemgrep` espalhado
   pelo código.
3. **Confiança**: `CONFIRMED` quando ferramenta real e heurística concordam;
   `heuristic` quando só o grep viu. (Modelo herdado do `secscan`.)
4. **Severidade**: `CRITICAL` (segredo vivo exposto, bypass de RLS, RCE) ·
   `HIGH` (falha de autorização, injeção, custo ilimitado) · `MEDIUM` (hardening
   ausente) · `LOW` (boa prática) · `INFO`.

Severidade responde à **exposição real**, não ao padrão. `service_role` num
script local de build ≠ `service_role` no bundle servido ao browser. Se a
diferença não estiver medida, o finding é `nao_medido`, não HIGH por precaução.

### Formato de finding

```
[SEVERIDADE] [CONFIANÇA] [pilar] caminho/arquivo.ts:123
O quê          — uma linha, factual
Por que dói    — o dano concreto, não a categoria abstrata
Como corrigir  — a mudança mínima que resolve
Reconferir     — $ comando que retorna vazio/0 quando estiver corrigido
Referência     — OWASP/CWE/doc do fornecedor
```

**Sem comando de reconferência o finding está incompleto.** "Corrigido" sem
comando é alegação, e alegação é exatamente o que a invariante 4 proíbe.

---

## Os oito pilares

Carregue **só o que a tarefa toca**. Cada arquivo tem a mesma estrutura:
Contrato · Como implementar · Como provar · Armadilhas.

| # | Pilar | Referência | Núcleo |
|---|---|---|---|
| 01 | Frontend / bundle | `references/01-frontend.md` | sourcemap, `VITE_`/`NEXT_PUBLIC_`, CSP + headers, orçamento de bundle |
| 02 | Banco / RLS | `references/02-banco.md` | RLS, policy, `SECURITY DEFINER`, view, grant, storage |
| 03 | Auth / permissão | `references/03-auth.md` | sessão, MFA, RBAC, gate de rota **e sua contrapartida** |
| 04 | Limites / abuso | `references/04-limites.md` | rate limit, quota de LLM, webhook secret, `verify_jwt` |
| 05 | Carga / cache | `references/05-carga.md` | paginação, cache em 3 camadas, índice, gargalo, balanceamento |
| 06 | Observabilidade | `references/06-observabilidade.md` | error tracking, log estruturado, alerta, auditoria |
| 07 | Segredos | `references/07-segredos.md` | inventário, scan de HEAD+histórico, rotação, exceções |
| 08 | Perímetro | `references/08-perimetro.md` | inventário de hosts, headers na borda, painel interno, versão exposta |

O contrato por projeto: `references/contrato-template.md`.

---

## Adotar num repo pela primeira vez

Uma sessão por repo. O primeiro custa mais porque você calibra o julgamento; os
seguintes são rápidos porque o método já está no lugar.

```bash
cd <repo>
SK="${CLAUDE_PLUGIN_ROOT}/skills/baseline"; [ -d "$SK" ] || SK="$HOME/.claude/skills/baseline"   # plugin, ou instalação antiga
OUT=/tmp/baseline-$(basename "$PWD")

bash $SK/scripts/doctor.sh  --out "$OUT"    # 1. o que dá pra medir aqui
bash $SK/scripts/collect.sh --out "$OUT"    # 2. mede (exit 3 = não mediu nada)
bash $SK/scripts/splinter.sh                # 3. banco, se houver acesso
node   $SK/scripts/render.mjs "$OUT/findings.json" --out "$OUT/report.md" --tools "$OUT/tools.json"
```

**4. Escreva o contrato** em `.context/docs/baseline.md`, de
`references/contrato-template.md`. É aqui que está o trabalho de verdade — os
scripts só medem. Preencha nesta ordem:

1. **Superfícies e ambientes.** Se não há staging, escreva isso: muda como tudo
   no repo é feito, e quem chega depois precisa saber.
2. **Estado por pilar**, com a prova ao lado. O que não mediu fica `nao_medido`.
3. **Inventário de segredos** — a coluna que decide prioridade é *raio de dano*.
4. **Gates de UI e contrapartidas.** Para cada gate, meça se o banco também nega
   (ver `03-auth.md`); marque `real` ou `cosmético`. Cosmético não é acusação, é
   informação — o risco é não saber qual dos seus gates é.
5. **Exceções aceitas**, com dono e data de revisão. Decisão consciente de ficar
   fora do padrão pertence aqui; sem isso, a próxima auditoria reabre o assunto e
   você paga de novo pela mesma decisão.
6. **Backlog por custo × risco**, não por pilar.

**5. Julgue o report contra o contrato** (fase 2) e **6. reconfira** rodando os
comandos de reconferência dos itens que fechou.

### O que esperar do primeiro run

- **Falso positivo é normal e é informação.** Detector que acusa depois do bug
  corrigido treina a ignorar o gate — corrija o detector, não o sintoma. Se for
  específico do projeto, registre em `.context/docs/security/vereditos.md`.
- **Achado que some quando você corrige** é o único que prova que o gate funciona.
  Por isso a fase 4 existe.
- **O que o script mede vence o que o repo sugere.** Grep em migration responde
  "o que foi escrito"; o banco responde "o que está valendo". Já divergiu por
  mais do dobro num projeto real.

### Ordem sugerida de adoção

Por exposição, não por afinidade: cliente em produção primeiro, protótipo por
último. Um repo por sessão — o contrato do primeiro serve de modelo para os
outros, e emendar dois na mesma sessão só encarece o contexto.

## Regras duras

- **Read-only no modo AUDITAR.** Localize, nunca conserte. A correção sai numa
  sessão com contexto de regressão.
- **Verify, don't claim.** Todo "conforme"/"passou"/"limpo" precisa do output real
  colado na mesma mensagem. Não rodou → escreva `não executado` e o comando que
  faltou.
- **Zero findings ≠ seguro.** O report diz isso explicitamente, sempre.
- **Semgrep sempre com `--metrics=off` e ruleset fixo.** `--config auto` faz login
  no registry e envia a URL do projeto. **Proibido em repo de cliente.**
- **Nunca traga o valor de um segredo pro contexto.** Para provar que existe:
  `grep -c '^KEY=' .env.local`. Fingerprint no report, nunca o valor.
- **Nunca faça DDL no banco auditado.** Nem `create schema lint`, nem tabela
  temporária. Os lints do splinter rodam como `select` puro.
- **Exceção aceita é artefato, não silêncio.** Se a decisão foi ficar fora do
  padrão, ela vai no contrato com motivo, dono e data — senão a próxima auditoria
  reabre o assunto e você paga de novo pela mesma decisão.
- **Um item medido por ferramenta vale mais que dez inferidos.** Se `doctor.sh`
  disse que a ferramenta falta, o pilar dela é `nao_medido` — não preencha com
  heurística e chame de cobertura.
