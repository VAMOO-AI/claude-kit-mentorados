<!-- secscan: lido na Fase 0.5, antes de qualquer grep -->

## Fase 0.5 — Scanners reais (rode primeiro)

```bash
mkdir -p secscan-reports
# AUSENTE é só binário que não existe. Scanner que roda e sai ≠ 0 falhou ou achou algo.
if ! command -v semgrep >/dev/null; then echo "semgrep AUSENTE → confiança menor. Instalar: pipx install semgrep==1.181.0"
else
  out=$(semgrep scan --config p/owasp-top-ten --metrics=off --sarif --output secscan-reports/secscan.sarif . 2>&1); rc=$?
  # No sucesso o resumo (regras, arquivos, achados) está no fim do $out: vai junto do OK.
  if [ "$rc" -eq 0 ]; then echo "semgrep OK → achados em secscan-reports/secscan.sarif"; printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -15
  else echo "semgrep FALHOU (exit $rc) → não medido; última linha: $(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -1)"; fi
fi
# gitleaks em dois modos, sempre --redact (valor de segredo não chega à conversa): o
# histórico (`detect`) e a árvore de trabalho (`dir`), porque o `detect` não lê o que
# ainda não foi commitado. Legenda do exit: 0 limpo · 1 achou segredo · outro falhou.
if ! command -v gitleaks >/dev/null; then echo "gitleaks AUSENTE"
else
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    out=$(gitleaks detect --no-banner --redact -v 2>&1); rc=$?
    printf '%s\n' "$out"
    case "$out" in
      *"not a git repository"*) echo "gitleaks histórico não medido (sem git)" ;;
      *) echo "gitleaks histórico exit $rc (0 limpo · 1 achou segredo · outro falhou)" ;;
    esac
  else echo "gitleaks histórico não medido (sem git): fora de repositório ele sai 0 sem ler nada"; fi
  # `dir` existe desde a 8.19; antes dela o equivalente é `detect --no-git`.
  if gitleaks --help 2>&1 | grep -q '^ *dir '; then gitleaks dir --no-banner --redact -v .
  else gitleaks detect --no-git --source . --no-banner --redact -v; fi
  echo "gitleaks árvore exit $? (0 limpo · 1 achou segredo · outro falhou)"
fi
if ! command -v osv-scanner >/dev/null; then echo "osv-scanner AUSENTE (opcional)"
else osv-scanner scan --format json .; echo "osv-scanner exit $? (0 limpo · 1 achou vulnerabilidade · 128 sem lockfile = não medido · outro falhou)"; fi
if ! command -v trivy >/dev/null; then echo "trivy AUSENTE (opcional: IaC/Docker/misconfig)"
else trivy fs --scanners misconfig,vuln --quiet .; echo "trivy exit $? (0 rodou, achados na saída acima · outro falhou)"; fi
```
Anote quais rodaram, quais faltaram e quais falharam no disclaimer do relatório. Scanner
que falhou não é scanner ausente: instalar de novo não resolve, e a causa (rede, ruleset,
a última linha do erro) vai para o relatório.

Ruleset **fixo**, nunca `--config auto`: o `auto` faz login no registry da Semgrep e manda a
URL do projeto junto, o que não se faz em repositório de cliente. Semgrep é o que mais agrega —
mas saiba o que ele corrobora de fato. **Medido em 31/08/2026** num app React + Supabase:
o ruleset OWASP rodou 255 regras sobre 2.198 arquivos e devolveu 27 findings, **100% em
`.github/` e `.npmrc`**, zero em `src/`, zero em `supabase/functions/`. Num diretório com
quatro vulnerabilidades de código plantadas de propósito: 2 findings, ambos no `ci.yml`,
nenhuma das quatro. Consequência: neste stack **todo achado de C1 (injeção) é
`heuristic`** por construção, e a linha C1 do checklist diz isso — em vez de deixar o
leitor supor que o silêncio do semgrep é ausência de problema.
