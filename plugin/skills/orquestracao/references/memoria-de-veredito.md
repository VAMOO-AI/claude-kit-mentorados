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
mesmo julgamento e chega a conclusões diferentes conforme o agente. Registre o motivo, não
só o "não é problema".

O veredito expira em dois casos, e nos dois o achado volta para ser julgado:

- **Código ao redor mudou** → o fingerprint deixa de valer.
- **O controle caiu.** Quando o "por quê" se apoia num middleware, guard, policy ou trigger,
  quem escreve o veredito cita o `arquivo:linha` desse controle. Quem consulta a tabela abre
  esse arquivo antes de aceitar o veredito: controle removido, ou que não cobre mais o
  caminho do achado → o achado volta. Confira o controle, não o número da linha. Sem essa
  checagem, o falso-positivo fica congelado com o código do achado intacto.
