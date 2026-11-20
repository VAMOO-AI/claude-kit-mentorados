# baseline — Fronteira com secscan, auditoria-seguranca e verificacao

Lido quando a dúvida é se o pedido é desta skill, do `secscan`, da auditoria ou da
`verificacao`. A tabela mora só aqui: a `auditoria-seguranca` aponta para este arquivo.

| Skill | Responde | Entrega | Não confunda |
|---|---|---|---|
| `baseline` | "A plataforma está apta a produção? O inventário bate com o contrato?" | contrato em `.context/docs/baseline.md` (ou o doc de contrato do seu projeto) | postura de ambiente |
| `baseline`, fase dinâmica | "O preview deixa pular o middleware? Reflete CORS? Aceita CSRF?" | linhas da fase no report, saída do ZAP em `$HOME/.cache`, **fora** do repo | requisição contra o app rodando (DAST); só preview/staging do próprio projeto ou cliente autorizado por escrito; nunca produção |
| `secscan` | "Existe `service_role` em `src/`? Esse `eval` é explorável?" | Markdown + SARIF em `secscan-reports/`, **fora** do git | scanner de código (SAST/SCA/CWE); nunca manda requisição |
| `/kit-vamoo:auditoria-seguranca` | "Quais das 6 falhas clássicas este código tem, e o que faço com isso?" | PDF + issues, **dentro** do repo | pacote para outra pessoa agir; só a pessoa chama |
| `verificacao` | "Já posso dizer que está pronto?" | veredito com o output real | prova de que funciona |
