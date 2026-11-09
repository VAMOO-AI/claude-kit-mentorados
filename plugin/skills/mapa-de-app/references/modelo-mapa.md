# Mapa do [app] ([plataforma])

Recorte: [a fatia mapeada]
Para: [quem vai usar a versão própria]
Data: [dd/mm/aaaa]

## Fontes

| # | Fonte | Link | Observação |
|---|---|---|---|
| 1 | Central de ajuda | | |

## Fluxo principal

[uma frase: o que o usuário paga para fazer]

## Telas

| ID | Tela | Rota ou como chega | Para que serve | Componentes | Estados vistos |
|---|---|---|---|---|---|
| T01 | | | | | vazio, preenchido, erro |

## Fluxos

```
F01 [objetivo]
    T01 -> T02 -> T03
    cliques: [n]
    desvios: [casos]
```

## Componentes

| Componente | Variações | Estados | Onde aparece |
|---|---|---|---|
| Botão | principal, secundário, perigo | normal, foco, desabilitado, carregando | todas |

## Modelo de dados inferido

```
[Entidade]  [campos]
            evidência: [IDs de tela, artigos de ajuda]
            confiança: alta | média | palpite
```

Relações: [Usuário 1-n Tipo, Tipo 1-n Agendamento, ...]

## Matriz de funcionalidades

Ver `funcionalidades.csv`. Deve: [n], deveria: [n], poderia: [n], fora: [n].

## Fora do escopo

- [conteúdo licenciado, rede de usuários, parceria, ...]

## Tamanho

Telas [n], fluxos [n], entidades [n]. Partes difíceis: [lista]. Tamanho: [P | M | G | GG].
