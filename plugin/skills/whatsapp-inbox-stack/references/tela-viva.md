# whatsapp-inbox-stack — tela que se move sem refazer a página (#15 a #19)

Lido no passo 7 do SKILL.md, antes de mexer em Realtime, aviso, lista ou URL assinada de mídia.

Tudo aqui foi medido num CRM em produção (Next 16 + Supabase, 23 e 24/11/2026), em duas telas de inbox: uma que espelha o Chatwoot e uma página própria sobre NotificaMe. O ponto de partida era o caminho óbvio, `postgres_changes` (#6) e `router.refresh()` a cada aviso. Cada gotcha abaixo é uma etapa de sair dele sem perder dado na tela.

### #15 — Broadcast do Realtime é canal aberto
Broadcast não passa por RLS. A chave `publishable` que assina o canal vai no bundle, então qualquer um assina e publica nele sem sessão, de qualquer lugar.
- **Payload só com identificadores** (`conversa_id`, `ids` de mensagem, tipo do aviso). Acrescentar nome, telefone ou texto publica conversa de cliente na internet.
- **Quem recebe desconfia:** confere o formato (uuid) de cada id antes de buscar e busca no banco, onde a RLS decide o que volta. Um aviso forjado vira, no máximo, uma releitura a mais.
- **Um canal por caixa ou inbox**, com o nome derivado da mesma chave nas duas pontas (`inbox:<id>` no servidor e na tela). Divergir não dá erro: a tela só nunca mais atualiza. Monte o nome numa função compartilhada, não em dois literais.
- **`supabase.channel(nome)` devolve o canal que já existe** com o mesmo topic (o cliente compara `c.topic === 'realtime:'+nome`, conferido no `realtime-js` 2.112), e `.on()` num canal já subscrito **lança** (`cannot add postgres_changes callbacks for … after subscribe()`). A árvore React cai inteira ("Application error: a client-side exception has occurred") e o motivo só aparece no console.
  - Gatilhos: dois componentes montados juntos (Drawer `keepMounted`) e o refresh de token re-rodando o efeito enquanto o `removeChannel` anterior espera o ack.
  - **Não resolva com sufixo no nome** (`useId` é estável por instância, e um sufixo por assinatura muda o topic): a entrega do broadcast é por topic, então o canal com sufixo deixa de receber o que o servidor publica no nome-base (conclusão pelo desenho do Realtime, não testada contra o servidor; teste antes de adotar sufixo).
  - **Conserto que respeita "mesmo nome nas duas pontas":** **um** canal por topic no cliente, compartilhado entre os consumidores por um registro de módulo com contagem de referências. O último consumidor a sair faz o `removeChannel`; quem entra com o canal já subscrito só registra o seu handler no registro (nunca chama `.on()` depois do `subscribe()`).
- Precisa de payload com dado de verdade? O caminho é Realtime Authorization (canal privado, com policy em `realtime.messages`), não esconder o nome do canal.

### #16 — `router.refresh()` por aviso é o custo dominante
**Bug real:** com uma aba parada, cada aviso refazia a página inteira: 4,1 requests RSC por aviso, 123 em 5 min. O aviso diz o que mudou, e cada parte busca a sua:
- a lista pede as linhas citadas a um GET com os filtros da tela e recebe só as que ainda passam neles; quem não voltou saiu do filtro e some;
- o painel relê a conversa aberta, se o aviso cita ela;
- recibo (entrega/leitura) não toca a lista;
- coalescência de ~300 ms junta a rajada num pedido só;
- a aba que fez a ação ignora o eco: o aviso leva um id curto da aba de origem, validado como `[A-Za-z0-9-]{8,64}` porque o canal é aberto (#15).

Só dois casos refazem a página: a reconciliação periódica, que não sabe o que mudou, e a aba que volta depois de mais de 60 s escondida. Resultado medido: 0 RSC por aviso.
- **Leitura por GET (Route Handler), não por Server Action:** o Next despacha actions uma de cada vez no cliente, e a releitura entraria na mesma fila das ações da tela.

### #17 — Aviso incremental só funciona se toda mudança avisar
**Bug real, escondido pelo refresh:** enquanto cada aviso refazia a página, o próximo aviso corrigia tudo. Com a lista relendo só as linhas citadas, apareceu o que não avisava: leitura (zerar não lidas), atribuição feita pela própria app e resolução. O webhook que volta do provider depois da atribuição é eco, não muda nada, e por isso também não avisa. Resultado: 4 selos de não lidas velhos em 1 h numa tela (dois deploys lado a lado, parados, conferidos contra o banco).
- **Conserto completo:** cada mutação avisa.
- **Atalho em uso:** a cada aviso, a lista pede as citadas e completa até o teto da rota (50) com o topo da lista, na mesma consulta; as citadas nunca perdem lugar. Da linha 51 em diante, só corrige ao recarregar.
- **Regra:** ao trocar refresh por aviso incremental, liste todas as mutações (as da app e as do provider) e confira quais avisam.

### #18 — URL assinada nova é arquivo novo para o navegador
**Bug real:** cada refresh assinava a mídia de novo, e o token novo na URL fazia o navegador baixar a conversa inteira outra vez: 61 arquivos, 11 MB por refresh com a conversa aberta.
- O cliente guarda a URL em uso por path e só troca quando o arquivo é outro, quando ela venceu e o player está parado (trocar o `src` de um `<audio>` tocando o interrompe), ou quando o carregamento falha.
- Renova uns 10 min antes de expirar, para a aba aberta o dia inteiro, onde mídia de URL de 1 h morria.
- A validade não muda: é ela que impede o link de circular.
- `loading="lazy"` em imagem levou a abertura de 61 para ~25 arquivos (11 MB para ~2 MB), com a conversa ainda rolada até o fim.
- `preload="metadata"` em áudio não deu ganho medido: o áudio de ~70 KB desce inteiro mesmo assim.

### #19 — Nada lento no caminho da abertura
- **Backfill fora do render:** o backfill do histórico do provider rodava dentro do render e atrasava a 1ª abertura em +580 ms (mediana; máx 1,15 s). Ele roda depois de abrir, disparado pelo cliente e guardado por um carimbo (`backfill_em`).
- **A conversa abre no cliente** (`pushState` + cache) e lê por GET (#16).
- **Revalidação igual não redesenha:** quando a releitura volta com o mesmo conteúdo, o painel não renderiza de novo. De 298 para 13 ms com 300 balões.
- **Retorno visual antes do "pronto":** balão "enviando" otimista no Enter (de nada em 1,8 s para ~2 ms) e o estado pendente no clique da lista (de ~400 ms para 1 ms).
- **O otimista casa um a um com a linha real.** A linha real pode chegar pelo aviso antes de a action voltar; sem o casamento, o balão aparece duplicado.

## Como medir
- **A/B intercalado entre as URLs de deploy de produção**, uma por versão. Não use o alias nem horários diferentes: tráfego e cache mudam com a hora.
- **Dois navegadores parados na mesma sessão**, um por deploy. No fim, compare a lista de cada um com o banco (foi assim que o #17 apareceu).
- Cuidados:
  - o preview pode não assinar mídia (sem a chave de serviço), e a medição de mídia sai falsa;
  - aviso sintético publicado no canal de produção chega às abas do time;
  - duas abas num só navegador headless deixam a de trás `hidden`, e a regra dos 60 s do #16 entra no meio.
