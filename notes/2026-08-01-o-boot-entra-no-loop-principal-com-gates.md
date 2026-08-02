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

---

# A raiz unificada: memória de matriz percorrida como lista intrusiva

## Quatro paredes, um só defeito

| # | função | forma |
|---|---|---|
| 1 | `func_002545B0` | lista intrusiva, sentinela em `arg+0x7C` |
| 2 | `func_002182A4` | tabela de pools em `obj+0x14` |
| 3 | `func_002547AC` | lista intrusiva, sentinela em `arg+0x7C` |
| 4 | `func_004244C0` | lista intrusiva, sentinela em `this+0x24` |

Três das quatro são caminhamentos de lista circular intrusiva com sentinela. E
todos os `head` medidos são **zero**, nunca lixo:

```
[LIST254-GATE] head=0 em sent=0x4077AC8C
[LIST254-GATE] head=0 em sent=0x4077AD9C
[LIST547-GATE] head=0x00000000 em sent=0x4077AC8C
```

Repare-se: **a mesma sentinela `0x4077AC8C` falha em dois walkers diferentes.**

## Quem escreve lá: um único escritor

`PS3_WATCH_STORE` nas duas sentinelas, corrida inteira, sem cap — **duas
escritas, ambas do mesmo sítio**:

```
[0x4077AC8C]=0x0   ra0=func_0024C1F8+0x218   ra1=func_0024CADC+0x25C
[0x4077AD9C]=0x0   ra0=func_0024C1F8+0x218   ra1=func_0024CADC+0x25C
```

`func_0024C1F8` é o **inicializador de matriz identidade** — a mesma função que
Julho já tinha apanhado a escrever `0.0` em `0x4077914C` (`patch_2545b0_entry_probe.py`
regista-o). Escreve zeros porque é isso que uma matriz identidade tem fora da
diagonal. **A escrita é legítima; o que está errado é quem depois lê aquilo.**

## A conclusão

Numa lista circular intrusiva bem construída, o `head` de uma lista vazia aponta
para **si próprio** (a sentinela), nunca para zero. Um `head` a zero não é uma
lista vazia nem uma lista corrompida: **não é uma lista.** É a linha de uma
matriz.

Portanto as quatro paredes não são quatro bugs. São quatro consumidores a
descobrir, cada um à sua maneira, que **recebem um objecto que é uma matriz e
tratam-no como um contentor**. Já não é inferência: há um único escritor, é o
inicializador de matrizes, e a mesma morada falha em dois walkers distintos.

## O que isto muda para a próxima sessão

**Parar de pôr um gate por walker.** Não converge — há um walker por classe, e
já se encontraram quatro. A pergunta é uma só, e é a Parede D:

> porque é que o despacho entrega um objecto-matriz a métodos de contentor?

A suspeita mais directa, e barata de testar: a **vtable** desses objectos. Se
`*(obj)` apontar para a vtable da classe errada, todos os sintomas seguem — o
objecto é uma matriz, mas os seus métodos virtuais são de um contentor. O
`func_0039E40C` faz literalmente `r11 = *(r3); call *(r11+0x60)`, e foi assim
que se chegou a `func_00254788`.

Medição sugerida (uma corrida, sem reconstrução): `PS3_WATCH_STORE` na word 0
dos objectos `0x400C61C8` e `0x400C3D48`, para ver quem lhes escreve a vtable e
se essa vtable é a da classe que os walkers assumem.

---

# O diagnóstico fecha: o objecto não tem vtable nenhuma

`PS3_WATCH_STORE` na word 0 (a vtable) dos três objectos-chave, corrida inteira,
sem cap:

**Os dois objectos de fábrica estão sãos** — cadeia de construtores C++ normal:

```
[0x400C3D48]=0x40004020 -> 0x511628 -> 0x516618 -> 0x516F70   (func_002B28BC)
[0x400C61C8]=0x40004020 -> 0x511628 -> 0x5115B0 -> 0x515D60 -> 0x515B08
                                                    (func_0041EDE4)
```

**O objecto cuja lista é percorrida recebe UMA escrita, e é zero:**

```
[0x4077AC10]=0x0   ra0=func_0024CADC+0x338   ra1=func_00252A48+0x208
```

E é o mesmo `func_0024CADC` que chama o inicializador de matriz
(`func_0024C1F8+0x218 ← func_0024CADC+0x25C`).

## O que isto resolve

Eu tinha suspeitado de **vtable errada**. Não é: **não há vtable nenhuma.**
`func_0024CADC` zera a word 0 e escreve uma matriz identidade. `0x4077AC10` é um
**struct simples, não-polimórfico** — uma matriz. Não é um contentor mal
inicializado; nunca foi um contentor.

Portanto o defeito não está no objecto nem na sua construção, que é correcta e
completa para o que ele é. Está em **quem passa um ponteiro para esse struct a
um método que espera um contentor**.

E esse sítio já está nomeado desde Julho, agora confirmado:

```
[E545B0] #2 this=0x400C61C8 arg=<o struct> lr=0x0024E2D4
```

`0x0024E2D4` cai em `func_0024E1E8`/`func_0024E270` — **o walker de registos do
WAD**. É ele que produz o argumento errado.

## Estado final desta sessão

A pergunta passou de *"porque é que o boot não avança"* — sem sujeito, sem
endereço — para:

> **porque é que o walker de registos do WAD (`func_0024E270`, sítio
> `0x0024E2D4`) entrega a `func_002545B0` um ponteiro para um struct de matriz
> em vez de um contentor?**

Uma função, um sítio, um argumento. E com quatro consumidores independentes a
testemunhar o mesmo erro a jusante.

Não há menu, e não haverá enquanto isto não cair pela raiz — mas já não é uma
caça: é uma leitura de `func_0024E270` com um `arg` conhecido.
