# whatsapp-inbox-stack — Meta Cloud API direta (Tech Provider) vs. NotificaMe

Lido no passo 6 do SKILL.md, antes de decidir sair do NotificaMe para a Cloud API direta, montar o Embedded Signup, preparar o App Review ou explicar ao cliente cobrança e limite da Meta.

**Fonte e data:** docs da Meta lidas em 2026-11-25 (URL em cada seção). A Meta muda preço, limite e versão do Embedded Signup com frequência: releia a página antes de passar número ou prazo para cliente. O que não foi confirmado está marcado **não verificado**.

## Quem é quem na Meta

| | Solution Partner (BSP) | Tech Provider | Tech Partner |
|---|---|---|---|
| Linha de crédito | Tem, e pode estender ao cliente | **Não tem** | Não tem |
| Quem paga a Meta | O parceiro, que fatura o cliente | **O cliente**, com a própria forma de pagamento cadastrada depois do onboarding | O cliente |
| O que você cobra | Uso da API + serviço | Só o seu software e serviço | Só o seu software e serviço |
| Token | Business token + system user (para compartilhar a linha de crédito) | **Só business token** | Só business token |

Fonte: [Partners overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/overview) · [Become a Tech Provider](https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/get-started-for-tech-providers/).

## NotificaMe hoje vs. Tech Provider direto

| | NotificaMe | Tech Provider direto |
|---|---|---|
| Para começar | Nada: o canal já existe | App Meta + Business Verification + App Review + Access Verification |
| Cobrança da Meta | Tipo de parceiro e repasse do NotificaMe: **não verificado** (confira na [lista oficial de parceiros](https://developers.facebook.com/docs/whatsapp/cloud-api/get-started/whatsapp-business-platform-partners) e peça por escrito) | Cada cliente cadastra cartão na Meta e paga por mensagem |
| Coexistência | Oferece por padrão (relato de uso em 2026-11-25, sem doc pública lida) | Pelo Embedded Signup, com as limitações abaixo |
| Clientes novos | Sem teto seu | 10 contas por 7 dias; 200 com o processo completo |
| Mídia inbound | Proxy `/media` do NotificaMe (#5) | Graph API com o token do cliente |
| n8n | Node NotificaMe (só outbound) + HTTP cru | HTTP direto na Graph API |

**Quando compensa sair:** volume de clientes em que a mensalidade por canal pesa mais que o custo de manter App Review, Embedded Signup e token por cliente; ou onboarding com a sua marca dentro do app. **Quando não compensa:** PME que não quer cadastrar cartão na Meta. Tech Provider não tem como bancar a cobrança dela.

## Virar Tech Provider: o caminho

1. App Meta com o caso de uso WhatsApp e um portfólio de negócio ligado.
2. **Business Verification** do portfólio. Sem ela o App Review não abre.
3. App Settings → Basic: ícone, categoria, URL de privacidade e de exclusão de dados. Abra as páginas deslogado: elas têm de dizer quem opera, o contato de privacidade e como pedir exclusão.
4. Prove a integração no número de teste (API Setup): o envio chega no WhatsApp, o webhook inbound responde na mesma conversa e a criação de template funciona.
5. Demo para o revisor: login de teste com o papel mínimo, dados fictícios, URL e passos exatos com o resultado esperado. Para conversa fora da janela, deixe um template aprovado.
6. **Data Handling:** respostas verdadeiras sobre controlador e país, fornecedores com acesso a dado da Meta e IA (qual dado vai para o modelo, se há handoff humano).
7. **App Review:** Advanced Access para as duas permissões, um texto e **um vídeo por permissão**:

   | Permissão | O vídeo mostra |
   |---|---|
   | `whatsapp_business_management` | Criar um template pelo produto e o item aparecendo na lista. `PENDING` no vídeo serve: aprovar o template é outra decisão |
   | `whatsapp_business_messaging` | Escrever e enviar pelo inbox e a mesma mensagem chegando no WhatsApp (celular ou web) |

   Sem Advanced Access de `whatsapp_business_management`, chamada em conta que não é sua volta erro `200`.
8. Antes de submeter, reabra o rascunho e toque os dois vídeos no player da Meta; confira que instruções, credencial no campo privado e declarações ficaram salvas. Guarde o ID da submissão.
9. Aprovação do App Review ≠ app publicado ≠ cliente conectado. Cada um é um passo. A Access Verification é o que sobe o teto de onboarding.

Prazo de referência: um caso público levou cerca de 18 dias corridos da submissão à aprovação ([Sinapta-Solutions/meta-tech-provider](https://github.com/Sinapta-Solutions/meta-tech-provider)). Não prometa prazo ao cliente.

Fonte: [Become a Tech Provider](https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/get-started-for-tech-providers/) · [App Review](https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/app-review).

## Embedded Signup: conectar o número do cliente

1. O JS SDK (`FB.login`) devolve `authResponse.code`, `waba_id` e `phone_number_id`.
2. O **servidor** troca o `code` por business token (server-to-server; nunca no front).
3. Registre o número na Cloud API (exceto em coexistência: já vem registrado).
4. Assine o app nos webhooks da conta do cliente (`waba_id`). Todos os clientes caem na callback do app; dá para sobrescrever por conta ou por número. Endpoint exato da assinatura: **não verificado** aqui, leia a doc ao implementar.
5. O token do cliente autoriza envio pelo número dele: guarde só no servidor e tire de qualquer payload gravado (mesma lógica do #23).

- **Teto de onboarding:** 10 contas novas em 7 dias móveis; 200 depois de Business Verification + App Review + Access Verification; acima disso, Meta Business Partner.
- **Versão:** a doc avisava v2 e v3 descontinuadas em 2026-10-15. Use a versão que a doc indicar no dia (v4/v5) e confira antes de codar.

Fonte: [Embedded Signup](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/overview/).

## Coexistência (app WhatsApp Business + Cloud API no mesmo número)

- Ativa com `featureType: "whatsapp_business_app_onboarding"` (na v5 vem ligado). O cliente precisa do app Business 2.24.17 ou superior.
- **Não funciona na API:** grupos (não sincronizam), ligações, catálogo, status, listas de transmissão (ficam só leitura), mensagem temporária, visualização única e localização ao vivo nos 1:1.
- Dispositivos vinculados caem no onboarding (até 4 companions depois). Throughput fixo de 20 msg/s no número.
- Histórico: até ~6 meses, e você tem **24h** depois do onboarding para sincronizar contatos e histórico, senão o cliente refaz o fluxo. Ver #28 para importar sem acionar nada.
- O que o cliente manda pelo app continua grátis e não mexe na janela da API.
- Desligar é no app do cliente (Settings → Account → Business Platform). O Deregister da API não vale.
- Brasil: a doc não cita país. **Não verificado.**

Fonte: [Onboarding de usuários do app Business](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users).

## Preço: por mensagem entregue (desde 2025-07-01)

- Categorias: marketing, utility, authentication, service e Meta Business Agent. Preço por categoria e por país; o Brasil (55) tem tabela em BRL desde 2026-07-01. Os valores ficam no CSV/PDF da Meta: não passe número sem abrir.
- **A janela de 24h só abre e renova com mensagem ou ligação do usuário.** Envio da empresa não renova.
- **Desde 2026-10-01:** utility dentro da janela passou a ser cobrada; service tem 1.000 grátis por número por mês, cobrança a partir da 1.001ª, sem acumular.
- Entrada por anúncio click-to-WhatsApp (Android/iOS): janela gratuita de até **7 dias** a partir da sua resposta.
- Consequência: keep-alive não estende a janela; ver `n8n-workflow-agent/references/messaging-patterns.md` § Keep-Alive.

Fonte: [Pricing](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing).

## Limite de envio

- **Por portfólio de negócio**, não por número: os números do portfólio dividem o teto. Conta números únicos fora da janela em 24h móveis.
- Faixas: 250 (portfólio novo), 2.000, 10.000, 100.000 e ilimitado. Sobe para 2.000 com Business Verification (sua ou do parceiro) ou 2.000 entregues fora da janela em 30 dias com qualidade alta; depois sobe sozinho com qualidade alta e uso de metade do teto em 7 dias.
- Campo atual: `whatsapp_business_manager_messaging_limit`. O `messaging_limit_tier` foi descontinuado.

Fonte: [Messaging limits](https://developers.facebook.com/documentation/business-messaging/whatsapp/messaging-limits).

## O que muda no inbox ao sair do NotificaMe

- **Envio:** `POST /<phone_number_id>/messages` na Graph API com o token do cliente. O node NotificaMe sai do n8n.
- **Mídia inbound:** o webhook traz o id da mídia, não a lookaside do NotificaMe. A busca da URL e o download exigem o token do cliente e a URL expira: baixe na hora do webhook, como no #5. Confira o fluxo na doc de mídia da Cloud API antes de codar (**não verificado** aqui).
- **Status:** chega no webhook da Cloud API, não no callback do NotificaMe. O lookup duplo de id (`n8n-workflow-agent/references/notificame.md`) continua valendo.
- **Continua igual:** a armadilha do `header_handle` de template com imagem (`notificame.md`), o áudio de saída em mp3 (#20) e as regras de canal #13 e #14. São comportamento da Meta ou do seu inbox, não do NotificaMe.
