# Quebrar arquivo grande por costura

<!-- ideia de soumatheusgomes/vibe-coding-toolkit (MIT), reescrita para o nosso fluxo -->

O teto de 300 linhas por arquivo é **aviso**: diz onde olhar, não reprova build nem lint.
Este é o roteiro de quando o aviso vira trabalho.

## Onde cortar

Corte por responsabilidade, nunca por número de linha. Um arquivo grande costuma ter uma
destas costuras:

| Costura | Sinal no código | Vai para |
|---|---|---|
| Tipos e contratos | `type`/`interface`/schema usados por mais de um módulo | `<dominio>.types.ts` |
| Lógica pura × I/O | função que só calcula ao lado de função que chama banco, fetch ou fila | a pura sai; a de I/O fica e importa |
| Estado × apresentação | componente com `useEffect`/fetch e 200 linhas de JSX | hook `use<Coisa>.ts` + componente |
| Pedaço que outro módulo quer | alguém já copiou o trecho ou importa o arquivo inteiro por uma função | módulo próprio, com nome do que faz |

Sobra que não se encaixa em nenhuma vira `utils.ts`/`helpers.ts`: isso é falha, não
costura. **Sem costura natural, pare e reporte.** Um arquivo grande e coeso é melhor que
três pequenos acoplados.

Não vale "compactar" para caber no teto (juntar linhas, tirar quebra, encurtar nome).
Isso burla a métrica e piora o diff.

## Como cortar sem quebrar quem importa

1. Dead code primeiro, em commit separado.
2. Extraia o trecho para o arquivo novo e deixe o original como **re-export fino**
   (`export { calcularTotal } from './precos.calculo'`). Os call sites não mudam no mesmo
   PR; migrar os imports é passo seguinte, opcional.
3. Um arquivo por commit, na branch do trabalho. Lote de três arquivos e pare: reporte o
   que saiu antes de seguir.

## As duas pegadinhas que só o check pega

**O tipo inferido alarga na extração.** Uma função que retornava
`{ status: 'erro' } | { status: 'ok'; dados: Pedido }`, inferido, vira
`{ status: string; dados?: Pedido }` quando a extração a passa por uma variável sem
anotação ou por um `.map`. O narrowing (`if (r.status === 'ok') r.dados`) quebra em call
sites que você nem abriu. Remédio: anote o tipo de retorno antes de mover, e rode o `tsc`
do **projeto inteiro**, não só do arquivo.

**O arquivo de destino estoura o teto.** Mover 120 linhas para um módulo que já tinha 220
troca um aviso por outro. Rode o lint de novo depois da extração, e nunca conte linha
na mão.

## Antes de dizer "pronto"

- `tsc` do projeto inteiro e lint, output colado.
- Os testes que cobrem o arquivo original rodam sem mudança: se precisou mudar teste,
  mudou comportamento, e isso não é refactor.
