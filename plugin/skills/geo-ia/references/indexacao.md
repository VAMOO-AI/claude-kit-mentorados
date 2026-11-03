# Indexação no Google e no Bing

Os dois painéis estão na conta do mentorado. Abra no navegador onde ele já está logado (Claude
in Chrome). Pedir indexação e enviar sitemap são envios: confirme antes de clicar.

## Google Search Console

1. **Propriedade de domínio** (`sc-domain:<dominio>`), verificada por TXT no DNS. Ela cobre
   `www`, apex e subdomínios de uma vez.
2. **Sitemaps**: envie `https://<dominio>/sitemap.xml`. O status esperado é "Processado", com
   o número de páginas do sitemap.
3. **Conferir página por página**: use a inspeção de URL, não o relatório de cobertura, que
   tem dias de atraso.
   - Na barra do topo ("Inspecionar qualquer URL"), cole a URL e dê Enter. Em janela estreita
     a barra vira um ícone de lupa.
   - "O URL está no Google" quer dizer indexada. Confira também o último rastreamento.
4. **Solicitar indexação**: o botão na mesma tela. O teste ao vivo leva de 1 a 2 minutos e
   termina em "Indexação solicitada". Há cota diária, de cerca de 10 URLs.
5. **Página por página no relatório**: Indexação > Páginas > "Ver dados sobre páginas
   indexadas" lista as URLs com a data do último rastreamento.

Motivos de não indexação que aparecem e o que querem dizer:

| Motivo | Leitura |
|---|---|
| Página com redirecionamento | normal para `http://` e `www` |
| Página alternativa com tag canônica adequada | normal: a canônica é outra URL |
| Rastreada, mas não indexada no momento | o Google viu e não quis ainda; se for página comercial, melhore o conteúdo e peça de novo |
| Descoberta, mas não rastreada | ainda não visitou; peça indexação |

## Bing Webmaster Tools

1. **Adicionar o site**: a importação do Search Console não lista propriedade de domínio.
   Adicione `https://<dominio>/` à mão e verifique pela meta tag
   `<meta name="msvalidate.01" content="...">` no `<head>` de todas as rotas. O valor da meta
   é público.
2. **Sitemaps**: envie o mesmo `sitemap.xml`.
3. **Inspeção de URL**: `https://www.bing.com/webmasters/urlinspection?siteUrl=https://<dominio>/`.
   Depois da primeira inspeção, a URL da página aceita
   `&urlToInspect=<url codificada duas vezes>` para ir direto.
   - "Indexed successfully": a URL pode aparecer no Bing.
   - "Discovered but not crawled": conhecida e fora do índice. Clique em "Request indexing" e
     confirme em "Submit". A cota é de cerca de 100 URLs por dia.
4. **IndexNow** (menu lateral) mostra as URLs avisadas a cada deploy, se o script estiver
   ligado.

## Quando a fase está fechada

Todas as páginas comerciais aparecem como indexadas **nos dois** índices, e o último
rastreamento do Google é posterior ao último deploy que mudou título ou texto. Registre no
`.context/docs/geo.md` a data e o estado de cada página nos dois painéis.

O processamento leva de dias a duas semanas. Não refaça o pedido todo dia: a cota é por dia,
e o pedido repetido não acelera.
