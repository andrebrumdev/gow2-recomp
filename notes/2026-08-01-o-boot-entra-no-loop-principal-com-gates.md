# O boot entra no loop principal — com três gates de diagnóstico

Data: 2026-08-01.

> **Isto é progresso OBTIDO COM GATE, não natural.** Os três interruptores abaixo
> são diagnóstico, OFF por default, e nenhum é um fix. Servem para responder a
> "quantas paredes há?", não para declarar nada resolvido (CLAUDE.md regras 4 e 5).

## As três paredes, todas da mesma família

| # | onde | sintoma | gate |
|---|---|---|---|
| 1 | `func_002545B0` | lista circular em `arg+0x7C` com `head=0` | `PS3_LIST254_EMPTY_IF_NULL` |
| 2 | `func_002182A4` | `base[0]` é a contagem de um cabeçalho, lida como pool | `PS3_POOL_NULL_IF_BAD` |
| 3 | `func_002547AC` | lista circular em `arg+0x7C` com `head` implausível | `PS3_LIST547_EMPTY_IF_BAD` |

A #3 estava escondida: `func_00254788` **não tem uma única chamada**, por isso o
rasto de call-sites não a instrumentava e o silêncio parecia começar antes dela.
É um laço puro que trampolina para `func_002547AC`.

## O resultado

Com os três ligados, o B71 **retorna** e a cadeia continua:

```
degrau 19  func_0023B654     ← a chamada DEPOIS do B71
degrau 20  func_002B7188
degrau 21  func_002B2E04
degrau 22  func_00242C94     ← O LOOP PRINCIPAL DO JOGO
[STATE] frame=1  0xFFFFFFFF -> 0x0052F3F0  (code 0x002B2DD0)  app=0x00730DF8
```

**O despacho de estado do loop principal disparou pela primeira vez.** Sem
`FATAL`, 2704 flips na corrida.

## CORRECÇÃO (a 17.ª): o elo AUTO_LOAD não é código de encerramento

Escrevi hoje, com medições, que a thread `AUTO_LOAD` só é criada por código que
corre **depois** do loop principal, e daí que o elo do gate era irrelevante para
o menu. Escrevi mesmo: *"quem vier a seguir NÃO deve perseguir este elo"*.

**Está errado.** O handler do primeiro estado do loop principal é
`code 0x002B2DD0` — medido pela sonda `[STATE]`. E `func_002B2DD0` é
exactamente a cabeça da cadeia que leva à criação da `AUTO_LOAD`.

O que falhou no meu raciocínio: o meu caminhador estático segue só arestas `bl`.
Viu `func_002B2E04 → func_002B2DD0` (que existe, e é pós-loop) e concluiu que
era o **único** caminho. Não podia ver que `func_002B2DD0` é **também**
despachado de dentro do loop por `*(r30+0x460C)` — um despacho indirecto,
invisível a um xref de `bl`.

Portanto:

- **Continua certo:** o marcador `thr_auto_load() end` nunca existiu, e o elo
  media uma string impossível. A correcção do instrumento mantém-se válida.
- **Estava errado:** dizer que o elo não pertence à cadeia. **Pertence** — é o
  primeiro estado do jogo. A ordem do gate estava certa; só o marcador é que
  estava partido.

Lição: um caminhador de `bl` não vê despachos indirectos, e num jogo C++ a
maior parte do fluxo é indirecta. Concluir "só há este caminho" a partir de um
xref estático é a mesma classe de erro de confiar no `lr` — o instrumento não
cobre o mecanismo dominante.

## Onde está agora

`func_002B2DD0` corre (degrau 23) e `func_000B951C` (degrau 24) não. O primeiro
handler de estado entra e não retorna. É a quarta parede, e a primeira que está
**dentro** do loop principal em vez de antes dele.

## Estado honesto

Não há menu. E este progresso é **com gates**: três saltos declarados por cima
de três defeitos de tipo por resolver. O valor real do resultado é outro — agora
sabe-se que entre o WAD e o loop principal há exactamente **três** paredes, que
são todas a mesma doença (objecto errado num método que assume outro tipo), e
que atrás delas o jogo tem um loop principal funcional que despacha o seu
primeiro estado.
