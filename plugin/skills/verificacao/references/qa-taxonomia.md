# Taxonomia de QA — o formato do veredito

O subagent de QA visual devolve "veredito" e cada um inventa o seu. Este é o
formato. Um achado sem severidade e categoria não entra no relatório.

## Severidade

| Nível | Definição | Exemplo |
|---|---|---|
| **crítico** | Bloqueia um fluxo central, perde dado ou derruba a tela | Submit do form vira página de erro; dado apagado sem confirmação; login em loop |
| **alto** | Feature principal quebrada, sem contorno | Busca devolve resultado errado; upload falha calado; botão principal morto |
| **médio** | Funciona, mas com problema visível; tem contorno | Página em >5 s; validação faltando mas o submit vai; layout quebrado só no mobile |
| **baixo** | Cosmético | Typo, 1 px desalinhado, hover inconsistente |

Segurança e perda de dado sobem pra crítico mesmo quando o esforço de corrigir
é grande. Prioridade é impacto vezes risco, não facilidade.

## Categorias

1. **Visual** — sobreposição, texto cortado, scroll horizontal, imagem quebrada,
   z-index errado, fonte ou cor fora do sistema, animação que engasga, tema
   escuro.
2. **Funcional** — link 404 ou destino errado, botão que não faz nada, validação
   ausente ou burlável, redirect errado, estado que some no refresh ou no
   voltar, double-submit, busca sem resultado quando devia ter.
3. **UX** — navegação sem saída, falta de indicador de carregamento, interação
   >500 ms sem feedback, erro genérico ("algo deu errado") sem detalhe, ação
   destrutiva sem confirmação, padrão diferente em páginas irmãs.
4. **Conteúdo** — typo, texto desatualizado, lorem ipsum, texto truncado sem
   reticências, label errado, empty state ausente ou inútil.
5. **Performance** — carga >3 s, scroll travando, layout que pula depois de
   carregar, >50 requests numa página, imagem sem otimizar, JS que bloqueia.
6. **Console** — exceção não tratada, 4xx/5xx, warning de depreciação, CORS,
   mixed content, violação de CSP. Rode `read_console_messages` depois de cada
   interação, não só no fim.
7. **Acessibilidade** — imagem sem alt, input sem label, tab que não chega,
   foco preso em modal, ARIA errado, contraste insuficiente.

## Por página

Pra cada página que o QA visita, nesta ordem:

1. Varredura visual (uma screenshot; o resto é `read_page`).
2. Todo elemento interativo: clica e confere se fez o que o rótulo diz.
3. Formulários: vazio, inválido, texto longo, caractere especial.
4. Navegação: entra e sai por todos os caminhos, inclusive o botão voltar e o
   deep link.
5. Estados: vazio, carregando, erro, cheio.
6. Console: erros novos depois das interações.
7. Viewport: mobile e tablet, se a tela é pública.
8. Fronteira de auth: deslogado, e cada papel que existe.

## Formato do relatório

```
QA <página ou fluxo> — <n> achados (<c> críticos, <a> altos, <m> médios, <b> baixos)

[crítico] [funcional] <página> — <o que aconteceu>. Passos: <1, 2, 3>. Esperado: <x>.
[médio]   [visual]    <página> — ...
```

Sem achado: `QA <alvo>: nenhum achado em <n> páginas, <m> interações.` A
contagem é obrigatória. "Nenhum achado" sem dizer o que foi coberto é o mesmo
relatório vazio que a baseline proíbe.

Origem: `qa/references/issue-taxonomy.md` do gstack (garrytan/gstack, MIT).
