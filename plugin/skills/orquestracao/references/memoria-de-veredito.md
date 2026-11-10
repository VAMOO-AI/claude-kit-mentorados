# orquestracao — memória de veredito

Lido antes de silenciar um achado ou reabrir um finding (auditoria, revisor de PR, fan-out que produz achado).

## Memória de veredito (falso-positivo não se resolve no código)

Silenciar o achado onde ele aparece (`nosemgrep`, `eslint-disable`, exceção no scanner)
espalha a decisão pelo código, some no diff e não diz quem decidiu nem quando. O veredito vai
num arquivo, `.context/docs/security/vereditos.md`. O modelo da tabela (fingerprint ·
veredito · por quê · quem · quando) mora em `secscan/references/falso-positivo.md`: leia lá
antes de criar o arquivo.

Antes de reabrir um finding, consulte a tabela; depois de julgar um novo, escreva nela. Vale
para auditoria, revisor de PR e todo fan-out que produz achado: sem isso, cada rodada paga o
mesmo julgamento e chega a conclusões diferentes conforme o agente. Código ao redor mudou →
o fingerprint deixa de valer e o achado volta. Registre o motivo, não só o "não é problema".
