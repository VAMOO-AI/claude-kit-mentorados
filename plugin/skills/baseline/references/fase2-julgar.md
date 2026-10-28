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
