# Mapa de compliance — categoria → controles

Cliente com time de segurança pergunta "isto viola qual controle?" antes de
perguntar "quão grave é?". Este mapa responde a primeira pergunta sem mexer na
segunda: o achado continua valendo pela fronteira cruzada e pelo
`arquivo:linha`; o controle é a etiqueta que o relatório põe em cima dele.

Cada linha abaixo diz **por que** o controle se aplica. Controle que você não
consegue justificar em uma frase não entra no achado.

## Normas e versões

O gerador só aceita o prefixo e o formato da versão em vigor, e aborta o
relatório no primeiro controle fora dele, com ou sem `--verificar`.

| Prefixo | Norma | Formato aceito |
|---|---|---|
| `OWASP` | OWASP Top 10:2025 | `A01:2025` … `A10:2025` |
| `OWASP-API` | OWASP API Security Top 10:2023 | `API1:2023` … `API10:2023` |
| `OWASP-LLM` | OWASP Top 10 for LLM Applications 2025 | `LLM01:2025` … `LLM10:2025` |
| `ISO27001` | ISO/IEC 27001:2022, Anexo A | `A.5.1`–`A.5.37`, `A.6.1`–`A.6.8`, `A.7.1`–`A.7.14`, `A.8.1`–`A.8.34` |
| `NIST-CSF` | NIST Cybersecurity Framework 2.0 | categoria (`PR.AA`) ou subcategoria (`PR.AA-05`) das 22 do CSF 2.0 |
| `SOC2` | Trust Services Criteria (AICPA) | `CC1.1`–`CC9.2`, `A1.x`, `C1.x`, `PI1.x`, `P1.x`–`P8.x` |
| `PCI-DSS` | PCI DSS v4.0.1 | requisito `1`–`12` com até 3 níveis (`8.6.2`) |
| `LGPD` | Lei 13.709/2018 | `Art.1`–`Art.65` |

**O OWASP Top 10 mudou em 2025**, e quem copia ID de memória erra. SSRF deixou
de ser categoria própria e entrou em A01 (Broken Access Control). A03 passou a
ser cadeia de suprimentos, e injeção desceu para A05. Credencial fixa no código
(CWE-798) fica em A07, e chave criptográfica fixa (CWE-321) em A04. ID com
`:2021` é recusado e o gerador diz para remapear por esta tabela.

## Default por categoria

Achado sem campo `compliance` herda a linha da sua categoria. É o caso comum;
não precisa escrever nada.

### A1 — isolamento de inquilino / dono no banco

`OWASP:A01:2025` · `OWASP-API:API1:2023` · `ISO27001:A.8.3` · `NIST-CSF:PR.AA` · `SOC2:CC6.1` · `PCI-DSS:7.2`

- **A01 / API1:** a linha de outro inquilino chega porque a consulta não amarra o
  dono. É controle de acesso por objeto, o que a OWASP chama de BOLA.
- **A.8.3:** restrição de acesso à informação. É o controle que a política de
  linha (RLS) ou o `where` por inquilino implementam.
- **PR.AA:** identidade e controle de acesso. A sessão existe, mas não decide
  nada.
- **CC6.1:** controle lógico de acesso sobre os ativos de informação.
- **PCI 7.2:** o acesso é concedido pelo que a função precisa, e aqui não é.

A1 e A3 têm os mesmos controles. A diferença está em **onde** a checagem
faltou (no banco ou na rota), não em qual controle ela viola.

### A2 — permissão decidida no navegador / escalonamento / lógica

`OWASP:A01:2025` · `OWASP-API:API5:2023` · `ISO27001:A.8.2` · `NIST-CSF:PR.AA` · `SOC2:CC6.3` · `PCI-DSS:7.2`

- **API5 (BFLA):** a função administrativa responde a quem não tem o papel. É
  o caso típico de "o botão sumiu, mas a rota continua aberta".
- **A.8.2:** direito de acesso privilegiado. Escalonar é justamente obter esse
  direito sem a concessão.
- **CC6.3:** acesso por papel e menor privilégio.

### A3 — IDOR / BOLA

`OWASP:A01:2025` · `OWASP-API:API1:2023` · `ISO27001:A.8.3` · `NIST-CSF:PR.AA` · `SOC2:CC6.1` · `PCI-DSS:7.2`

Mesma justificativa da A1. O ID vem do cliente e a rota não confere se o
objeto é de quem pediu.

### A4 — chaves / segredos expostos

`OWASP:A07:2025` · `ISO27001:A.5.17` · `NIST-CSF:PR.AA` · `SOC2:CC6.1` · `PCI-DSS:8.6.2`

- **A07:** o Top 10:2025 mapeia credencial fixa no código (CWE-798) em Falhas
  de Autenticação. Chave que vaza vira login de outra pessoa.
- **A.5.17:** gestão de informação de autenticação. Segredo em bundle, repo ou
  log está fora dessa gestão.
- **PCI 8.6.2:** senha e segredo de conta de sistema ou aplicação não ficam em
  script, arquivo de configuração nem código-fonte. É o texto do requisito.

Chave de assinatura ou de criptografia pede o override abaixo, porque aí o
controle principal é outro.

### A5 — input sem tratamento (XSS / injeção)

`OWASP:A05:2025` · `ISO27001:A.8.28` · `NIST-CSF:PR.PS` · `PCI-DSS:6.2.4`

- **A05:** injeção, que inclui XSS na versão 2025.
- **A.8.28:** codificação segura, o controle que cobre validar a entrada e
  escapar a saída.
- **PR.PS:** segurança de plataforma. A prática de desenvolvimento seguro está
  na subcategoria PR.PS-06.
- **PCI 6.2.4:** técnicas de engenharia que previnem ataques comuns. O
  requisito cita injeção e XSS pelo nome.

**Sem SOC 2 de propósito.** O TSC não tem critério de codificação segura, e
forçar CC7.1 ou CC8.1 aqui seria etiqueta sem lastro.

### A6 — agente de IA com ferramentas

`OWASP-LLM:LLM01:2025` · `OWASP-LLM:LLM06:2025` · `OWASP:A01:2025` · `ISO27001:A.8.2` · `NIST-CSF:PR.AA` · `SOC2:CC6.3`

- **LLM01:** texto que o atacante controla chega ao prompt de um agente que age.
- **LLM06 (Excessive Agency):** a ferramenta alcança mais do que a tarefa
  precisa. Sem isso, a injeção só produziria texto.
- **A01 / A.8.2 / CC6.3:** a ação acontece com um privilégio que o usuário
  final não tem.

## Overrides por subtipo

Quando o achado é um destes recortes, declare `compliance` no achado. O campo
**substitui** o default, não soma. Por isso, repita o que do default ainda vale.

| Subtipo (categoria) | `compliance` | Por quê |
|---|---|---|
| SSRF, URL controlada alcança rede interna (A3) | `OWASP:A01:2025` · `OWASP-API:API7:2023` · `ISO27001:A.8.22` · `NIST-CSF:PR.IR` | O Top 10:2025 pôs SSRF em A01. Se o metadata endpoint responde, a segregação de rede (A.8.22) falhou. |
| Campo sensível gravável pelo cliente, mass assignment (A2) | `OWASP:A01:2025` · `OWASP-API:API3:2023` · `ISO27001:A.8.3` · `SOC2:CC6.1` | Autorização por **propriedade**, não por objeto: o registro é seu, mas o campo `role` não. |
| Bypass de autenticação ou sessão (A2) | `OWASP:A07:2025` · `OWASP-API:API2:2023` · `ISO27001:A.8.5` · `NIST-CSF:PR.AA` · `SOC2:CC6.1` · `PCI-DSS:8.3` | Não é permissão errada, é identidade não provada. A.8.5 é autenticação segura, e PCI 8.3 exige autenticação forte. |
| Erro que libera o acesso, fail-open (A2) | `OWASP:A10:2025` · `OWASP:A01:2025` · `ISO27001:A.8.28` | A10:2025 trata a exceção mal tratada. Aqui o `catch` devolve "autorizado". |
| Segredo com default público em compose/CI (A4) | `OWASP:A02:2025` · `OWASP:A07:2025` · `ISO27001:A.8.9` · `PCI-DSS:2.2.2` | Configuração insegura por padrão (A02, A.8.9). O default publicado vira credencial conhecida (A07). PCI 2.2.2 manda trocar o default de fábrica. |
| Chave de assinatura ou criptografia exposta, JWT secret (A4) | `OWASP:A04:2025` · `OWASP:A07:2025` · `ISO27001:A.8.24` · `NIST-CSF:PR.DS` | Chave fixa é CWE-321, em A04. Quem tem a chave forja token (A07). A.8.24 cobra a gestão da chave. Sem PCI: o 3.6 protege a chave que cifra dado de cartão armazenado, não a de assinar sessão. |
| Saída do modelo em sink de render ou execução (A6) | `OWASP-LLM:LLM05:2025` · `OWASP:A05:2025` · `ISO27001:A.8.28` | A resposta do modelo vira HTML, SQL ou shell sem tratamento, e aí é injeção com um passo a mais. |
| Deputado confuso, tool com credencial ampla (A6) | `OWASP-LLM:LLM06:2025` · `OWASP:A01:2025` · `OWASP-API:API5:2023` · `ISO27001:A.8.2` | O agente executa com a credencial do serviço uma função que o usuário não poderia chamar. |
| Modelo devolve dado ou system prompt que não devia (A6) | `OWASP-LLM:LLM02:2025` · `OWASP-LLM:LLM07:2025` · `ISO27001:A.8.12` | Vazamento pela saída do modelo; A.8.12 é prevenção de vazamento de dados. |
| Trilha de auditoria ausente ou apagável (transversal) | `OWASP:A09:2025` · `ISO27001:A.8.15` · `NIST-CSF:DE.CM` · `SOC2:CC7.2` · `PCI-DSS:10.2` | Sem log não se prova quem fez. Use só quando a ausência da trilha é o próprio achado. |
| Dependência com CVE alcançável pelo caminho do atacante (transversal) | `OWASP:A03:2025` · `ISO27001:A.8.8` · `NIST-CSF:ID.RA` · `PCI-DSS:6.3.3` | Cadeia de suprimentos. Vale só com o caminho provado até a função vulnerável; CVE na árvore sem alcance é `hardening[]`. |

## LGPD: só quando o dado alcançado é pessoal

A LGPD não entra em default nenhum, porque a categoria não diz se o dado é
pessoal: um IDOR em tabela de configuração não tem titular. Quando o caminho
provado chega a dado pessoal (nome, CPF, e-mail, telefone, endereço, dado de
saúde), declare o override. Repita os controles que valem e acrescente:

- **`LGPD:Art.46`:** o controlador e o operador devem adotar medidas de
  segurança aptas a proteger o dado contra acesso não autorizado. Serve para
  qualquer achado acionável que alcança dado pessoal.
- **`LGPD:Art.49`:** o sistema que trata o dado deve ser estruturado para
  atender os requisitos de segurança. Use quando a falha é de desenho (não há
  isolamento de inquilino nenhum), não um esquecimento pontual.

`Art.48` (comunicar o incidente à ANPD) não entra no achado: é um dever que
nasce depois de um incidente, não um controle que o código viola. Se o achado
sugere exploração real, isso vai para a conversa com o cliente, não para a
etiqueta.

```json
{ "id": "F2", "categoria": "A3", "severidade": "critica",
  "titulo": "Qualquer usuário lê o prontuário de outra clínica",
  "compliance": ["OWASP:A01:2025", "OWASP-API:API1:2023", "ISO27001:A.8.3",
                 "LGPD:Art.46"] }
```

## O que o mapa não faz

- **Não muda o veredito.** Nenhum controle sobe ou desce severidade ou gate.
  Um `hardening[]` sem vítima não vira controle violado só porque o assunto
  lembra uma linha da ISO.
- **Não certifica.** ISO 27001 e SOC 2 medem processo, política e evidência
  organizacional, e esta auditoria só lê código. O PDF diz isso na seção.
- **Não prova conformidade pelo silêncio.** Controle sem achado significa que
  esta auditoria não encontrou violação ali, não que ele está atendido.
