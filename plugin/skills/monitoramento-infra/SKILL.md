---
name: monitoramento-infra
description: >-
  Monitorar o que está no ar e ser avisado no celular antes do cliente: sondas
  (pg_cron, n8n, VPS, WhatsApp), antiflap, confirmação de queda, recovery que
  não mente, lembrete, quem vigia o vigia, ntfy como canal; e os cuidados de VPS
  com Docker/Traefik (404 do Docker 29, netdata a 1s, reboot em Swarm, firewall,
  backup). Só dispara quando você chama. Erro de app e log ficam no pilar 06 da
  /kit-vamoo:baseline.
disable-model-invocation: true
---

# Monitoramento e infra

Para quem tem sistema no ar — app, n8n, agente de WhatsApp, VPS — e quer saber
que caiu **antes** do cliente mandar mensagem. Tudo aqui saiu de um monitor e de
uma frota de VPS em produção: cada regra corrigiu um alarme falso, uma queda que
passou calada ou um monitor que derrubou o próprio banco.

Este arquivo é o roteador. **Leia só a referência do tema da tarefa.**

| A tarefa envolve... | Leia |
|---|---|
| Começar do zero: "quero ser avisado quando meu site/n8n cair" | o passo a passo abaixo + [assets/sonda-http.sh](assets/sonda-http.sh) |
| Alerta no celular, tópico, prioridade, formato da mensagem | [references/ntfy.md](references/ntfy.md) |
| Desenhar ou consertar um monitor: alarme falso, alerta que não chega, "RECUPERADO" que mente, barulho demais | [references/arquitetura-monitor.md](references/arquitetura-monitor.md) |
| Sonda rodando no Supabase (pg_cron + pg_net + edge function) | [references/supabase-cron.md](references/supabase-cron.md) |
| O que sondar em n8n, VPS/Portainer, WhatsApp, Vercel, job agendado | [references/sondas.md](references/sondas.md) |
| VPS caiu, 404 em todas as rotas, CPU alta do Docker, reboot, firewall, backup, SSH | [references/vps.md](references/vps.md) + [assets/fix-vps-hardening.sh](assets/fix-vps-hardening.sh) |

Erro de front, Sentry, log estruturado, custo de IA e trilha de auditoria são o
**lado do app**: pilar 06 (observabilidade) da `/kit-vamoo:baseline`.
Esta skill é o lado da operação.

## Três regras que valem para tudo

1. **O alerta sai por fora do que ele vigia.** Sonda na mesma VPS do sistema morre
   junto com ele. Aviso de "WhatsApp caiu" pelo mesmo WhatsApp não chega. Alerta
   gravado numa tabela que só o app mostra some quando o app cai.
2. **Alerta que ninguém lê não é alerta.** Monitor barulhento treina a pessoa a
   ignorar o canal; a queda real vira mais uma notificação. Confirme antes de
   avisar (2 falhas seguidas), avise uma vez, lembre de vez em quando, e só diga
   "voltou" com evidência.
3. **Monitore o silêncio, não o status.** "Está ativo" mente. Lista vazia é
   sucesso. O monitor que parou não avisa que parou — por isso existe o
   heartbeat externo.

## Começar em 15 minutos (sem Supabase)

1. **Tópico ntfy com nome aleatório** e o app no celular — [ntfy.md](references/ntfy.md#em-5-minutos).
   O tópico é a senha: fora do git.
2. **Uma máquina que não seja a vigiada**: outra VPS, um Raspberry, o servidor de
   um amigo. Copie `assets/sonda-http.sh` para lá **por arquivo** (`scp`, `curl`),
   não colando no terminal.
3. **`alvos.txt`**, uma linha por alvo: `nome url [status,aceitos]`.
4. **Teste com um alvo que vai falhar** (`quebrado http://127.0.0.1:9/`): rode
   três vezes e confira que o celular tocou **uma** vez (na segunda). Depois
   aponte um alvo para um servidor que você pode desligar e religar, e veja a
   queda **e** a volta chegarem. Apague o alvo de teste e a pasta de estado dele.
5. **Cron** a cada 5 min com `flock` (a linha está no cabeçalho do script).
6. **Heartbeat**: crie um check gratuito num serviço de dead man's switch
   (healthchecks.io, por exemplo), ponha a URL em `HEARTBEAT_URL` e configure o
   aviso dele para o mesmo celular. Agora, se a máquina da sonda morrer, você
   também fica sabendo.

Daí para cima — lanes, dedup, múltiplos canais, lembrete por criticidade — é
[arquitetura-monitor.md](references/arquitetura-monitor.md).

## Antes de mexer em produção

- **VPS:** rode o diagnóstico de [vps.md](references/vps.md#diagnóstico-sempre-primeiro)
  antes de qualquer receita. Toda receita mexe no que está no ar: backup do
  arquivo, janela combinada com quem usa o sistema e o rollback escrito antes. O
  Claude **propõe** cada comando que muda estado e espera o seu OK.
- **Alerta novo:** rode um ciclo real e leia o payload cru do que deu `down`
  antes de ligar o aviso. Metade dos alarmes falsos que este monitor teve era
  campo mal interpretado.
- **Teste de alerta não dispara para cliente.** Use um tópico ntfy descartável e
  um destino de teste; nunca o grupo do cliente. E confira se o seu "dry-run" é
  mesmo dry-run ([supabase-cron.md](references/supabase-cron.md#testando-sem-disparar-mensagem-de-verdade)).
- **Medida, não impressão.** CPU, latência e "voltou" se provam com número e
  janela suficiente — 10 segundos de amostra já produziram "está corrigido" duas
  vezes quando não estava.

## Pronto é

- [ ] Provoquei uma queda de verdade e o aviso chegou no celular — uma vez.
- [ ] A volta chegou, e só para o que tinha sido avisado.
- [ ] O aviso sai de uma máquina que não é a vigiada.
- [ ] O heartbeat avisa se a própria sonda parar.
- [ ] O tópico (e qualquer token) está fora do git.
