---
name: baseline
description: >-
  Postura de ambiente e segurança de app web (Vite/Next + Supabase + Vercel +
  n8n) em 7 pilares — bundle, RLS, auth, rate limit, cache, observabilidade,
  segredos. Dois modos: CONSTRUIR (projeto novo nasce apto) e AUDITAR (app em
  produção está apto?). Use em "está pronto pra prod", "auditar produção",
  "hardening", "app novo do zero", "baseline". O gate do /ship já roda o
  collect.sh sozinho — aqui mora o método e o julgamento dos achados.
---

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

No pilar de código, **chame `secscan`** — não refaça análise de código aqui.

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
   → `02`. Tocou rota/papel → `03`. Tocou edge/webhook → `04`. Tocou query/lista
   → `05`. Tocou tratamento de erro → `06`. Tocou env/chave → `07`.
   Carregar os sete de uma vez é desperdício de contexto.
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
SK=~/.claude/skills/baseline
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

## Os sete pilares

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

O contrato por projeto: `references/contrato-template.md`.

---

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
