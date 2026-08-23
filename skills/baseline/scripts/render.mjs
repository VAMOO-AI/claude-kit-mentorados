#!/usr/bin/env node
// baseline · render — findings.json -> report.md
//
// A tabela de cobertura é obrigatória (invariante 3): "nenhum achado" só
// significa "nenhum entre o que foi medido". Um report sem cobertura declarada
// é indistinguível de um sistema seguro, e não é a mesma coisa.
//
//   render.mjs <findings.json> [--out report.md] [--tools tools.json]

import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'

const argv = process.argv.slice(2)
const input = argv.find((a) => !a.startsWith('--'))
const flag = (n) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : undefined }

if (!input) {
  console.error('uso: render.mjs <findings.json> [--out report.md] [--tools tools.json]')
  process.exit(2)
}

const data = JSON.parse(readFileSync(input, 'utf8'))
const outPath = flag('--out') ?? join(dirname(input), 'report.md')
const toolsPath = flag('--tools') ?? join(dirname(input), 'tools.json')
const tools = existsSync(toolsPath) ? JSON.parse(readFileSync(toolsPath, 'utf8')).tools ?? [] : []

const ORDER = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO']
const PILARES = {
  '01': 'Frontend e bundle', '02': 'Banco e RLS', '03': 'Auth e permissão',
  '04': 'Limites e abuso', '05': 'Carga e cache', '06': 'Observabilidade',
  '07': 'Segredos',
}

const findings = (data.findings ?? []).slice().sort(
  (a, b) => ORDER.indexOf(a.severity) - ORDER.indexOf(b.severity) || a.pilar.localeCompare(b.pilar),
)
const coverage = data.coverage ?? []
const m = data.meta ?? {}
const count = (s) => findings.filter((f) => f.severity === s).length
const naoMedidos = coverage.filter((c) => c.status !== 'medido')
const esc = (s) => String(s ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ')

const L = []
L.push(`# Baseline — ${m.project ?? 'projeto'}`, '')
L.push(
  `**Gerado:** ${m.generated_at ?? '?'} · **Base:** \`${m.branch ?? '?'}\` @ \`${m.git_sha ?? '?'}\`` +
  ` · **Modo:** ${m.mode ?? 'completo'}`, '')
L.push(`> Método: skill \`baseline\`. Este relatório é a fase **Medir**.`)
L.push(`> Severidade e exceções aceitas são aplicadas na fase **Julgar**, com o`)
L.push(`> contrato do projeto (\`.context/docs/baseline.md\`) em mãos.`, '')

// ── Resumo
L.push('## Resumo', '')
L.push(ORDER.map((s) => `${s} ${count(s)}`).join(' · '), '')
L.push(
  `${coverage.length} checks · **${coverage.length - naoMedidos.length} medidos** · ` +
  `${naoMedidos.length} não medidos`, '')
L.push('**Zero findings não significa seguro.** Significa: nada encontrado entre o')
L.push('que foi medido, pelas ferramentas disponíveis, no escopo declarado abaixo.', '')

// ── Cobertura (invariante 3 — obrigatória)
L.push('## Cobertura', '')
L.push('| Pilar | Check | Estado | Ferramenta | Observação |')
L.push('|---|---|---|---|---|')
for (const c of coverage) {
  const badge = c.status === 'medido' ? 'medido' : '**não medido**'
  L.push(`| ${c.pilar} | ${esc(c.check)} | ${badge} | ${esc(c.tool)} | ${esc(c.reason)} |`)
}
L.push('')
if (naoMedidos.length) {
  L.push('**Dado indisponível não é evidência de risco — nem de ausência dele.** Os')
  L.push(`${naoMedidos.length} checks acima não foram medidos; o veredito deles é desconhecido,`)
  L.push('não "conforme".', '')
}

// ── Ferramentas
if (tools.length) {
  const ausentes = tools.filter((t) => t.state !== 'ok')
  L.push('## Ferramentas', '')
  L.push(tools.filter((t) => t.state === 'ok').map((t) => `\`${t.name}\``).join(' · ') || '_nenhuma_', '')
  if (ausentes.length) {
    L.push('Ausentes — a confiança do relatório é menor por causa disso:', '')
    L.push('| Ferramenta | Para que serviria | Instalar |')
    L.push('|---|---|---|')
    for (const t of ausentes) L.push(`| ${t.name} | ${esc(t.purpose)} | \`${esc(t.install)}\` |`)
    L.push('')
  }
}

// ── Findings
L.push('## Findings', '')
if (!findings.length) {
  L.push('Nenhum finding entre os checks medidos. Ver Cobertura acima antes de ler')
  L.push('isto como aprovação.', '')
} else {
  let sev = null
  for (const f of findings) {
    if (f.severity !== sev) { sev = f.severity; L.push(`### ${sev}`, '') }
    L.push(`#### [${f.pilar} · ${PILARES[f.pilar] ?? ''}] ${f.title}`, '')
    L.push(`\`${f.file || '—'}\` · confiança: **${f.confidence}**`, '')
    L.push(f.detail || '', '')
    if (f.recheck) L.push('Reconferir:', '', '```bash', f.recheck, '```', '')
    if (f.ref) L.push(`_Referência: ${f.ref}_`, '')
  }
}

// ── Como usar
L.push('## Próximo passo', '')
L.push('1. **Julgar** — cruze cada finding com as exceções aceitas do contrato.')
L.push('   Exceção vigente sai do report; exceção vencida volta com a severidade original.')
L.push('2. **Propor** — a correção mínima, por finding.')
L.push('3. **Reconferir** — rode o comando de reconferência e cole o output. Sem')
L.push('   isso, "corrigido" é alegação.', '')
L.push('Achado marcado `heuristic` foi visto só por padrão de texto e pode ser falso')
L.push('positivo — verifique antes de agir. Achado sobre *comportamento* exige prova')
L.push('de execução: ler o código responde "existe?", não "funciona?".', '')

writeFileSync(outPath, L.join('\n'))
console.log(
  `${outPath} · ${findings.length} findings ` +
  `(${count('CRITICAL')} critical, ${count('HIGH')} high) · ` +
  `${coverage.length - naoMedidos.length}/${coverage.length} checks medidos`)
