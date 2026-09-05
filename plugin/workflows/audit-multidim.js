export const meta = {
  name: 'audit-multidim',
  description: 'Auditoria multi-área reutilizável: fan-out de auditores read-only por área → juiz adversarial por finding → critic de cobertura. 100% parametrizado via args.',
  phases: [
    { title: 'Auditoria', detail: 'um auditor read-only por área' },
    { title: 'Verificação', detail: 'juiz adversarial por finding' },
    { title: 'Cobertura', detail: 'critic de completude' },
  ],
}

// args: { alvo, contexto, regras?, areas: [{ key, files, foco? }], maxFindings? }
// (sem Date/aleatório aqui — runner é determinístico; datas entram via args)
const A = args || {}
if (!A.alvo || !Array.isArray(A.areas) || !A.areas.length) {
  throw new Error('args obrigatórios: { alvo, areas: [{key, files, foco}] }')
}
const MAX = A.maxFindings || 8

const COMMON = `Você é auditor especialista. Alvo: ${A.alvo}\n${A.contexto || ''}\n\nREGRAS DURAS:\n- READ-ONLY: não edite, não crie, não delete nada; use Read/Grep/Glob/Bash(ls, head, wc) só pra inspecionar.\n- NUNCA leia .env*/credenciais (deny ativo). Existência de key: no máximo grep -c count-only.\n- Cada finding = mudança CONCRETA com o texto exato pronto pra aplicar. Nada de conselho genérico.\n- Qualidade > quantidade: máximo ${MAX} findings; zero é resposta válida.\n- Responda em PT-BR.\n${A.regras || ''}`

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      maxItems: MAX,
      items: {
        type: 'object',
        required: ['file', 'issue', 'proposal', 'impact'],
        properties: {
          file: { type: 'string', description: 'path absoluto do arquivo alvo' },
          issue: { type: 'string', description: 'o problema em 1-2 frases' },
          proposal: { type: 'string', description: 'a mudança exata, texto pronto pra aplicar' },
          impact: { enum: ['ALTA', 'MEDIA', 'BAIXA'] },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['verdict', 'reason'],
  properties: {
    verdict: { enum: ['APROVAR', 'REJEITAR', 'PENDENTE_RUAN'] },
    reason: { type: 'string', description: '1-2 frases' },
    proposalRefinada: { type: 'string', description: 'só se APROVAR com ajuste' },
  },
}

const CRITIC_SCHEMA = {
  type: 'object',
  required: ['gaps'],
  properties: {
    gaps: {
      type: 'array',
      maxItems: 5,
      items: {
        type: 'object',
        required: ['area', 'oQueFaltou'],
        properties: { area: { type: 'string' }, oQueFaltou: { type: 'string' } },
      },
    },
  },
}

phase('Auditoria')
const porArea = await pipeline(
  A.areas,
  (a) => agent(`${COMMON}\n\nSUA ÁREA: ${a.key}\nARQUIVOS: ${a.files}\nFOCO: ${a.foco || 'problemas concretos que mudam comportamento na prática'}\n\nEntregue os findings no formato estruturado: {findings: [{file, issue, proposal, impact}]} (máximo ${MAX}).`,
    { label: 'audit:' + a.key, phase: 'Auditoria', schema: FINDINGS_SCHEMA }
  ).then((res) => {
    const fs = (res && res.findings) || []
    if (!fs.length) return []
    return parallel(fs.map((f) => () =>
      agent(`Você é juiz ADVERSARIAL de uma proposta de melhoria. Tente REFUTÁ-LA antes de aprovar.\n\nAlvo: ${A.alvo}\n${A.regras || ''}\n\nFINDING (área ${a.key}):\n- file: ${f.file}\n- issue: ${f.issue}\n- proposal: ${f.proposal}\n\nChecagens: (1) factualidade — abra o arquivo e confirme que o problema existe HOJE; (2) a proposta aplica sem quebrar nada; (3) não viola nenhuma regra dura. Na dúvida sobre factualidade, REJEITAR. Responda {verdict, reason, proposalRefinada?}.`,
        { label: 'judge:' + a.key, phase: 'Verificação', schema: VERDICT_SCHEMA }
      ).then((v) => v
        ? { area: a.key, ...f, verdict: v.verdict, verdictReason: v.reason, proposalRefinada: v.proposalRefinada }
        : { area: a.key, ...f, verdict: 'SEM_VEREDITO' })
    )).then((arr) => arr.filter(Boolean))
  })
)

const all = (porArea || []).filter(Boolean).flat()
log(all.length + ' findings julgados')

phase('Cobertura')
const critic = await agent(`${COMMON}\n\nVocê é o CRITIC DE COMPLETUDE. Áreas auditadas: ${A.areas.map((x) => x.key).join(', ')}.\nFindings que sobreviveram (issue apenas):\n${all.map((f) => '[' + f.area + '/' + f.verdict + '] ' + f.issue).join('\n') || '(nenhum)'}\n\nO que FALTOU? Confirme cada gap inspecionando os arquivos ANTES de reportar (gap especulativo = não reporte). Máximo 5. Responda {gaps: [{area, oQueFaltou}]}.`,
  { phase: 'Cobertura', schema: CRITIC_SCHEMA }
)

return {
  aprovados: all.filter((f) => f.verdict === 'APROVAR'),
  pendentes: all.filter((f) => f.verdict === 'PENDENTE_RUAN'),
  rejeitados: all.filter((f) => f.verdict === 'REJEITAR' || f.verdict === 'SEM_VEREDITO').map((f) => ({ area: f.area, issue: f.issue, motivo: f.verdictReason })),
  gaps: (critic && critic.gaps) || [],
}
