# baseline — Fase 2: julgar e formato de finding

Lido na fase 2 do Modo AUDITAR, antes de julgar o `findings.json` e de escrever qualquer finding.

### Fase 2 — julgar

O collect emite fatos, não vereditos. Você aplica, nesta ordem:

1. **Exceção aceita** no contrato e ainda dentro da validade → o finding sai do
   report principal e vai pra seção "Exceções aplicadas". Fora da validade → volta
   como finding, severidade original, com a nota de que a exceção venceu.
2. **Veredito anterior** em `.context/docs/security/vereditos.md` → falso-positivo
   já julgado não reabre enquanto o trecho julgado for o mesmo (abra o
   `arquivo:linha`); mudou o código, julgue de novo. Registre novos ali no formato
   do `secscan` (fingerprint · veredito · por quê · quem · quando), nunca com
   `nosemgrep` espalhado pelo código.
3. **Confiança**: `CONFIRMED` quando ferramenta real e heurística concordam;
   `heuristic` quando só o grep viu. (Modelo herdado do `secscan`.)
4. **Severidade**: `CRITICAL` (segredo vivo exposto, bypass de RLS, RCE) ·
   `HIGH` (falha de autorização, injeção, custo ilimitado) · `MEDIUM` (hardening
   ausente) · `LOW` (boa prática) · `INFO`.

Severidade responde à **exposição real**, não ao padrão. `service_role` num
script local de build ≠ `service_role` no bundle servido ao browser. Se a
diferença não estiver medida, o finding é `nao_medido`, não HIGH por precaução.

5. **Juiz** em todo `CRITICAL` e `HIGH`, `heuristic` incluso. O contrato
   (as três provas de `refutado`, a lista do que não refuta, rebaixar em vez
   de apagar) é o da `auditoria-seguranca`, em
   [fase-5-veredito.md](../../auditoria-seguranca/references/fase-5-veredito.md),
   pergunta 3; leia lá, não aqui. O que muda por causa do formato da baseline:

   - **Antes do dispatch, você escreve `muda_severidade_se`** para o finding:
     as condições que, se verdadeiras, mudam a nota ("se a tabela não tem
     `GRANT` para `anon`, cai para MEDIUM"). Na baseline quem achou é o
     collect mais você, e o collect não escreve isso.
   - **O prompt do juiz leva** pilar, título, `arquivo:linha`, `O quê`,
     `Por que dói`, `Reconferir` e o `muda_severidade_se`, mais a ordem de
     refutar. **Pede pelo nome** os três campos que o `revisor` só devolve
     quando pedidos: `veredito` (`mantido`/`refutado`) com o motivo,
     `contraevidencia` (a evidência mais forte contra o finding e por que não
     o derruba) e `severidade_nova` com a condição que a sustenta, quando
     discorda só da nota. Não manda sua confiança nem os outros findings.
   - **`mantido` sem `contraevidencia` não foi julgado**: despache de novo.
     O texto vai para a linha `Contra` do finding.
   - **`refutado` vira veredito em `.context/docs/security/vereditos.md`**
     (passo 2), e o "por quê" carrega a prova que o juiz deu: o controle com
     `arquivo:linha`, o caminho que não fecha com `arquivo:linha`, ou a
     consulta ao estado vivo com o resultado (pilar 02: policy, `GRANT`,
     trigger). Refutado sem uma das três volta como mantido. `heuristic`
     baixa a confiança, não refuta: o grep ter visto sozinho não é prova de
     que o caminho não fecha.
   - **Veredito por controle reabre quando o controle muda.** O passo 2 reabre
     se o trecho do finding mudou; com refutação por controle, abra também o
     `arquivo:linha` do controle. Middleware removido não pode deixar um
     falso-positivo congelado.
   - **Rebaixado não vai para `vereditos.md`.** Fica no report com a
     severidade nova, o motivo nomeando a condição de `muda_severidade_se`
     que se confirmou e o mesmo comando de `Reconferir`: o finding continua
     de pé, só pesa menos.

### Formato de finding

```
[SEVERIDADE] [CONFIANÇA] [pilar] caminho/arquivo.ts:123
O quê          — uma linha, factual
Por que dói    — o dano concreto, não a categoria abstrata
Como corrigir  — a mudança mínima que resolve
Reconferir     — $ comando que retorna vazio/0 quando estiver corrigido
Contra         — a contraevidencia do juiz e por que não derruba (CRITICAL/HIGH)
Referência     — OWASP/CWE/doc do fornecedor
```

`Contra` só existe em `CRITICAL`/`HIGH` julgado (passo 5). Esta fase escreve o
report à mão; o `render.mjs` roda na fase Medir, antes do juiz, e não lê nem
escreve essa linha.

**Sem comando de reconferência o finding está incompleto.** "Corrigido" sem
comando é alegação, e alegação é exatamente o que a invariante 4 proíbe.
