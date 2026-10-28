<!-- secscan: lido na Fase 6, antes de escrever o relatório -->

## Fase 6 — Relatório

Escreva em `secscan-reports/<YYYY-MM-DD>-secscan.md`. Peça pro usuário adicionar `secscan-reports/`
no `.gitignore` (não edite o `.gitignore` você mesmo). Se o semgrep rodou, o `secscan.sarif` já está nessa pasta (Fase 0.5).

Ordem literal do documento: **Resumo → Disclaimer → 1. CHECKLIST → 2. ANOTAÇÕES →
3. SUGESTÕES DE CORREÇÃO → Ferramentas executadas → Handoff.** Só os três blocos
numerados são obrigatórios em forma; o resto fica em volta, sem numeração.

### As 7 categorias (taxonomia fixa)

Sempre as sete, sempre nesta ordem. A última coluna é quem produz o achado —
nenhuma categoria tem sonda própria fora das fases acima.

| Categoria | Prova mínima (o que precisa ter rodado pra linha sair limpa) | Vem de |
|---|---|---|
| **C1** injeção de código | SAST com ruleset de injeção (`semgrep`) + os sete grupos do bloco C1 (SQL, shell, HTML fora do framework, caminho, template, SSRF, log e filtro). O semgrep não corrobora código de app neste stack (Fase 0.5): todo achado sai `heuristic`, e a linha diz isso | F0.5 + F3 |
| **C2** autenticação e controle de acesso | Toda rota/handler público checa identidade antes de ler ou mutar; tabela sem RLS ou com policy `using (true)`; toda function que dispensa o gateway valida o chamador (bloco abaixo) | F2 + F3 |
| **C3** exposição de dados sensíveis | Segredo no versionamento **e** no bundle publicado (`grep` de `sbp_`/`eyJhbGciOi`/`sk-ant-` no `dist/` depois do build); `service_role`/secret atrás de prefixo público; endpoint devolvendo a linha inteira; view sem `security_invoker` lendo tabela protegida; duas policies PERMISSIVE do mesmo comando para o mesmo papel (somam com OR) | F1 + F2 + F3 |
| **C4** validação de entrada | Fase 2.5 inteira: o gap de boundary sem schema impresso, valor de dinheiro/permissão/identidade, limite de entrada, mass assignment | F2.5 |
| **C5** bibliotecas externas | Audit nativo do lockfile do projeto (`npm`/`pnpm`/`bun`/`poetry`…), ou `osv-scanner`; pacote alucinado; o CI roda algum audit? (`grep -rn audit .github/workflows/ package.json`: vazio é finding de processo) | F4 |
| **C6** configurações inseguras | Default inseguro versionado: debug ligado, TLS desligado, CORS `*`, URL de auth com curinga (`site_url` em `http://` no `supabase/config.toml`), endpoint/credencial hardcoded, URL de webhook ou tópico de push com o token no caminho | F1 + F3 + F5 |
| **C7** criptografia e armazenamento | Bloco C7 inteiro: hash, aleatoriedade, slug, comparação, cripto simétrica, TLS, JWT, armazenamento, gestão de chave | F5 |

Uma sonda de C2 que vale para todo projeto Supabase com functions: function fora do
`supabase/config.toml` herda o padrão (`verify_jwt = true`) no próximo deploy, e quem a
chamava sem JWT passa a tomar 401 no gateway, sem erro em lugar nenhum. E toda function com
`verify_jwt = false` precisa provar o chamador no próprio código (segredo em header, HMAC do
payload ou validação de token).

```bash
# O `test -f` não é decoração: sem ele, num repo sem config.toml o comm lista TODAS as
# functions e sai 0, e a skill reporta "N desprotegidas" num repo que só não tem o arquivo.
if [ -f supabase/config.toml ]; then
  comm -23 <(ls supabase/functions | grep -v '^_shared' | sort) \
           <(grep -o '^\[functions\.[^]]*\]' supabase/config.toml | sed 's/\[functions\.//;s/\]//' | sort)
else
  echo "sem supabase/config.toml → esta sonda de C2 é 'não aplicável (sem config.toml)', NUNCA 'todas desprotegidas'"
fi
```

### 1. CHECKLIST (obrigatório, sempre impresso)

Tabela de **exatamente 7 linhas**, `Categoria | Estado | Base` — inclusive quando
está tudo limpo. Os estados são **quatro**:

- **`N achado(s)`** — encontrou; os findings vão pro bloco 2.
- **`nenhum problema identificado`** — procurou e não achou. Só sai assim se
  **todas** as provas mínimas daquela linha rodaram.
- **`não medido (<ferramenta> ausente)`** — nomeie o binário que faltou
  (`semgrep`, `gitleaks`, `osv-scanner`). Instalado e falhou (a Fase 0.5 imprime
  `FALHOU` ou um exit fora da legenda) é **`não medido (<ferramenta> falhou: exit N)`**,
  nunca `ausente`. **Ferramenta presente com input ausente
  também é não medido**, e é o caso que mais engana: `osv-scanner` instalado num projeto
  sem lockfile roda, sai 0 e não lê nada; o histórico do `gitleaks` fora de repositório git
  também (a árvore de trabalho continua medida pelo `gitleaks dir`). Escreva
  o motivo real — `não medido (lockfile ausente)`, `não medido (sem git)` —, nunca "nenhum problema identificado" com a ferramenta na coluna Base.
- **`não aplicável (<motivo>)`** — a precondição da Fase 0 não existe (projeto sem
  banco não tem RLS; site estático não tem rota de API).

Regras duras:

- **É proibido omitir uma linha.** Categoria não investigada é `não medido`, nunca
  limpa — silêncio virando aprovação é o modo de falha desta skill.
- Prova parcial (a heurística rodou, o scanner não) continua `nenhum problema
  identificado`, mas a coluna **Base** carrega o qualificador
  *(parcial: semgrep ausente)*. O qualificador mora na Base, nunca vira um quinto estado.
- **Prova parcial COM achado é `N achado(s)`, e o qualificador continua obrigatório.** Parte
  das sondas da linha não rodou (sem `config.toml`, sem acesso ao banco) e as que rodaram
  acharam coisa. `não medido` apagaria achado real; `N achados` sozinho esconde que metade
  da prova não rodou. Escreva `2 achados` no Estado e `(parcial: sem acesso ao banco — a
  consulta de policies não rodou)` na Base. Nunca escolha entre o achado e o buraco:
  reporte os dois.
- **Base** lista o que de fato rodou naquela linha — o comando. Base vazia obriga
  `não medido`.

Exemplo do formato (3 das 7 linhas; **as outras 4 também são impressas**):

| Categoria | Estado | Base |
|---|---|---|
| C2 autenticação e controle de acesso | **2 achados** | grep de `create policy` em `supabase/migrations` · leitura das rotas de API |
| C6 configurações inseguras | nenhum problema identificado | grep de TLS/CORS/debug *(parcial: semgrep ausente)* |
| C5 bibliotecas externas | não medido (osv-scanner ausente) | — |

### 2. ANOTAÇÕES

Só as categorias com achado. Um bloco por finding:

- `Severidade · Confiança (CONFIRMED ou heuristic) · C<n> <categoria> · arquivo:linha`
- **Trecho** — 3 a 8 linhas do código real, com a linha do problema marcada.
  **Nunca cole o valor de um segredo**: só o nome da variável e o prefixo
  (`SUPABASE_SERVICE_ROLE_KEY = eyJhbGciOi…`), no relatório e no chat.
- **O conceito** — explique a ideia de segurança em linguagem simples, sem jargão não-definido (ex: "RLS é o porteiro que decide quais linhas cada usuário pode ver; sem ele, qualquer um lê tudo"). Uma analogia vale três definições.
- **Por que aconteceu** — o padrão que gera esse bug em código de iniciante/IA, pra reconhecer da próxima.
- **Por que é explorável** — o caminho concreto do atacante até o dado, não a definição da classe.
- **Doc oficial** — link via `find-docs`.

### 3. SUGESTÕES DE CORREÇÃO

Uma por finding, nomeando arquivo, linha e a mudança. **NÃO aplique** — quem
aplica é o dono do projeto, e é aplicando que se aprende.

- **Proibido genérico**: "sanitize a entrada", "valide o input", "revise as
  permissões". Isso não é correção, é o nome do problema repetido.
- **Obrigatório específico**: "valide `body` com o schema que já existe em
  `lib/schemas.ts` antes da linha 42", "troque o `escapeHtml` local de
  `Comentario.tsx:97` pelo import de `src/lib/sanitize.ts`", "selecione colunas
  explícitas no lugar de `select('*')` em `useUsuarios.ts:20`".
- **Passo a passo numerado**, o fix correto mais simples em vez do elegante.
- **Como prevenir a categoria** — o que passa a ser rodado sempre pra essa classe
  não voltar.
- **Gate que trava a regressão**, quando existir: o comando que **falha hoje e
  passa depois do fix**. Não existe gate → diga isso e aponte onde ele entraria
  (um step do CI), sem criá-lo — a skill é read-only.

Em volta dos três blocos: **Resumo** com as contagens `CRITICAL N · HIGH N ·
MEDIUM N · LOW N · INFO N` · **Disclaimer** "Zero findings ≠ seguro" (só significa que este
scan, com estas ferramentas, neste escopo, não achou nada) · **Ferramentas
executadas** — semgrep/gitleaks/audit/osv/trivy/consulta ao banco: rodou ou não rodou e por quê. As
linhas `não medido` do checklist têm que bater com essa lista.

Severidade: `CRITICAL` (secret vazado, RLS bypass, RCE) · `HIGH` (falha de autorização, injeção) · `MEDIUM` (falta hardening) · `LOW` (boa prática) · `INFO` (registro, sem risco hoje).

**Handoff:** imprima o caminho do relatório. Diga que é esse arquivo que um agente deve ler antes de planejar qualquer fix — não infira o fix só pelo resumo do chat.

### O que se corta do relatório (e o que é proibido cortar)

A saída desta skill é **artefato de handoff**: o arquivo que outro agente lê antes de
corrigir, e achado que não está escrito nele some quando a sessão acaba. Cortar conselho
custa atenção; cortar achado esconde vulnerabilidade. Por isso o arquivo leva tudo, e o
corte, quando existe, é só no chat. A lição vale além desta skill: **regra editorial boa
num lugar vira defeito no outro quando muda o que a saída é.**

**Proibido no arquivo do relatório:**

- **Limitar a 1–2 achados por categoria.** Se C2 tem 16 rotas sem checagem de identidade,
  são 16 no relatório. Imprimir 2 e calar 14 é o mesmo *silêncio virando aprovação* que a
  regra dura do checklist proíbe — pior, com cara de relatório completo.
- **Pular categoria vazia.** Colide com *É proibido omitir uma linha*. Aqui a linha vazia
  **é** informação: diz que a sonda rodou e não achou, e é ela que separa `nenhum problema
  identificado` de `não medido`. As 7 linhas saem sempre.

**No terminal o corte é de atenção, nunca de registro.** No chat: o checklist inteiro
(7 linhas), todos os `CRITICAL` e `HIGH` — se são nove, saem nove —, e dos `MEDIUM`/`LOW`
só o que muda a ordem de correção, agrupado por classe; feche com `cortei N achados
menores — os N estão completos em <caminho>`. O excedente já está escrito no arquivo: a
linha de corte é um ponteiro, não uma promessa.

**Agrupar não é cortar, e é o que de fato desinfla.** Vinte hits da mesma classe viram
**um** bloco com a contagem e 2–3 representantes `arquivo:linha`, não vinte blocos quase
iguais. A contagem continua completa; o que sai é a repetição.

E o motivo de o cap ser a ferramenta errada aqui está medido logo acima: **36% de
precisão**. O que infla relatório de scanner não é excesso de achado verdadeiro, é falso
positivo. Teto de contagem sobre uma lista majoritariamente ruidosa não devolve sinal —
sorteia qual dos achados reais sobrevive. Quem desinfla é triagem: abrir o `arquivo:linha`
antes de citar, e olhar o destino do valor, não a primitiva.
