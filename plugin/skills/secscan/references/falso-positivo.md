<!-- secscan: lido antes de escrever qualquer finding -->

## Falso positivo — o que a calibração ensinou

Medido em 31/08/2026, rodando esta skill num app real: **5 dos 14 achados HIGH+ eram
reais — 36% de precisão**, contra uma meta de 70%. Um relatório onde dois em cada três
alertas graves são ruído deixa de ser lido — e aí o achado real passa junto. Regras que
saíram dessa rodada:

- **Grep localiza; leitura decide.** Nenhum comando desta skill emite veredito. Ele aponta
  o arquivo; você abre a linha, segue de onde o valor vem e só então escreve o finding.
  Finding sem `arquivo:linha` que você mesmo leu não existe.
- **Anotação de exemplo apodrece.** Todo `arquivo:linha` que veio de relatório anterior,
  de memória ou de exemplo nesta skill foi medido num repo, numa data. Na calibração, a
  skill mandava reportar um fallback `Math.random()` de token de convite que já tinha
  virado `crypto.randomUUID()` — repetir a anotação era **fabricar finding**. Antes de
  citar, abra o arquivo: se o código mudou, a anotação é ruído, não atalho.
- **Não conte o mesmo hit duas vezes.** Greps de bullets vizinhos se sobrepõem (na
  calibração, "29 mass assignment" eram 20 + 9 coerções `Number()` que o bullet seguinte
  contava de novo). Some as contagens do Resumo só depois de triar.
- **O discriminante é o destino do valor, nunca a primitiva.** `md5()` num fingerprint e
  `Math.random()` numa key de lista React não são finding; `Math.random()` gerando token de
  reset é. Diga no finding por que aquele uso é explorável, não que a função existe.
- **Falso positivo julgado mora num arquivo, não no código.** `nosemgrep` e
  `eslint-disable` espalham a decisão pelo diff e não dizem quem decidiu nem quando. O dono
  do projeto registra em `.context/docs/security/vereditos.md` (fingerprint · veredito ·
  por quê · quem · quando — a skill `baseline` lê a mesma tabela). Antes de reportar,
  consulte: achado já julgado não volta como novo. O veredito vence quando o código ao
  redor muda — por isso o "por quê" é obrigatório.

**Precedentes.** [references/checklist-incidentes.md](checklist-incidentes.md)
traz 27 checks de C2, C3, C5 e C6 que nasceram de incidente real, cada um com como achar a
ferramenta equivalente no repo auditado: consulte durante as Fases 2 a 5, ou quando um
finding precisar de precedente.

**Calibração da casa.** Se existir `~/.claude/docs/secscan-casa.md` (ou
`.context/docs/security/calibracao.md` no projeto), leia durante as Fases 2 a 5: ele traz
os incidentes datados e as contagens medidas num repo de verdade, com o comando de cada
check naquele stack. É calibração de um repo, não resposta: rode o comando no repo auditado
e cole a saída de agora.
