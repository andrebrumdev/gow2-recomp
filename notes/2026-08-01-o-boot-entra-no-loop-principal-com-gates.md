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

---

# O registry FUNCIONA. A medição que eu não esperava.

Sonda no despacho do walker (`PS3_TRACE_TYPETAG`), o sítio `0x0024E2D4`:

```
[TYPETAG] obj=0x4077AC10 objvt=0x40030001 tag=1 idx=0x00004
          tab=0x00868D48 fab=0x400C5048 fabvt=0x00515AA0 code=0x0039D428
```

Ponto por ponto:

- **`tab = 0x00868D48`** — é exactamente a tabela do registry de tipos que o
  CLAUDE.md documenta. Confirmada no caminho natural.
- **`tag = 1` → `idx = 0x4`** — o índice bate com a fórmula `(tipo<<2)&0x3FFFC`.
- **`fab = 0x400C5048`, `fabvt = 0x00515AA0`, `code = 0x0039D428`** — fábrica
  real, vtable viva, método real.

**O registry de tipos funciona neste sítio.** Não está vazio, não devolve lixo,
não devolve a fábrica errada. Isto contraria a suposição de longa data de que a
Parede D é "o registry não populado" — pelo menos neste caminho, ele responde
correctamente.

## E o `objvt` não é uma vtable

`0x40030001` decompõe-se em `0x4003` / `0x0001`, e o `0x0001` é **o mesmo valor**
que o `tag` lido de `+0x2`. Não é um ponteiro de vtable: é um **cabeçalho de
registo WAD** (tamanho/tipo). O `0x4077AC10` não é um objecto de heap — é um
**registo dentro dos dados do WAD**.

### Hipótese minha, refutada na mesma corrida

Vi `0x4077AC10` e o prefixo `0x4077` e pensei: está dentro do ring de stream, é
outro stomp como o do pump que corrigi de manhã. **Não é.** O ring mede-se no
mesmo log:

```
F2B-STREAM-FILL stream=0x4007FCD0 base=0x40083D40
```

`0x40083D40` está a mais de 7 MB de `0x4077AC10`. A hipótese cai.

## O que fica, e o que muda

A cadeia é toda coerente e, até este ponto, **correcta**: o walker lê o tag de um
registo WAD, o registry devolve a fábrica certa, a fábrica é chamada com o
registo. O defeito está **a jusante** — algures entre `func_0039D428` e
`func_002545B0`, alguém pega no registo e trata-o como um contentor com lista
intrusiva em `+0x7C`.

E há um facto por explicar que só a medição revelou: a mesma morada
`0x4077AC10` recebeu, do guest, uma matriz identidade
(`func_0024CADC`/`func_0024C1F8`, escrita única vista pela vigia) e contém agora
um cabeçalho de registo WAD escrito **sem passar por `vm_write32`** — uma escrita
host em bloco, invisível à vigia. Memória reutilizada para dois tipos, ou uma
cópia em bloco por cima de um objecto vivo. Distinguir os dois é a próxima
medição, e faz-se com `ps3_watch_store_bulk` no caminho de cópia do WAD.

## Estado final honesto

Não há menu. O boot só entra no loop principal com três gates de diagnóstico,
e o primeiro handler de estado não retorna.

O que esta última ronda entregou não foi um passo em frente — foi **eliminar
uma suspeita cara**. O registry de tipos estava sob suspeita desde Julho como
"não populado"; neste caminho, está medido a funcionar. Quem continuar não
precisa de o reconstruir: precisa de perceber quem, a jusante de
`func_0039D428`, decide que um registo WAD é um contentor.

---

# CORRECÇÃO (18.ª): o objecto NÃO é uma matriz alheia — é o seu próprio tipo

Escrevi acima, e com ênfase, que `0x4077AC10` "é um struct simples,
não-polimórfico — uma matriz", que "nunca foi um contentor", e que o defeito
estava em quem lhe passava o ponteiro. **Está errado**, e o erro veio de comparar
duas corridas diferentes em vez de uma.

Vigia e sonda na **mesma** corrida:

```
[0x4077AC10]=0x4077AD20  ra0=func_002635A4+0xDA8  ra1=func_00252A48+0x170
[0x4077AC10]=0x40030001  ra0=func_0024BC78+0x1F4  ra1=func_0024C1F8+0xD4
[TYPETAG] obj=0x4077AC10 objvt=0x40030001 tag=1 ...
```

Duas escritas, ambas **legítimas e do guest**:

1. `0x4077AD20` — um **elo de lista**: aponta para o outro objecto do mesmo tipo
   que aparece na sonda. Vem de `func_002635A4` (alocador/pool), via
   `func_00252A48`.
2. `0x40030001` — o **cabeçalho**, escrito por `func_0024BC78`, chamado de
   **dentro de `func_0024C1F8`**.

Portanto `func_0024C1F8` não é um "inicializador de matriz identidade alheio"
que calhou escrever ali — é o **construtor deste tipo**. Escreve o cabeçalho
(`0x4003` / tag `0x0001`) e depois inicializa a matriz embutida em `+0x70`.

O `objvt = 0x40030001` também não é uma vtable ausente: é o cabeçalho, e o seu
half baixo é exactamente o `tag` que o registry usa. A classe não guarda vtable
em `+0`.

## O que cai e o que fica

**Cai:** "o objecto é uma matriz", "nunca foi um contentor", "o defeito é quem
lhe passa o ponteiro". E cai a generalização de que as quatro paredes são
"objecto do tipo errado" — pelo menos esta não é: o objecto é do tipo certo,
construído pelo seu próprio construtor, e o registry escolhe-lhe a fábrica
certa.

**Fica, e é sólido:**

- O registry de tipos funciona (`tab=0x00868D48`, tag=1, fábrica com vtable viva).
- O objecto é de tipo 1, correctamente construído, e está **encadeado numa
  lista** (`+0x0` aponta para o irmão).
- A sentinela lida em `+0x7C` recebe **uma única escrita em toda a corrida**:
  `0`, do próprio construtor (`func_0024C1F8+0x218`).

## A pergunta certa, finalmente

O construtor deixa `+0x7C` a zero. Os walkers testam vazio com
`head == sentinela` — um teste que um zero nunca satisfaz. Ou seja:

> **ou o construtor devia auto-ligar `*(obj+0x7C) = obj+0x7C` e não o faz, ou
> aquele campo não é uma lista e os walkers não deviam lá tocar.**

São duas hipóteses concretas, mutuamente exclusivas, e distinguem-se lendo o
construtor `func_0024C1F8` inteiro contra o EBOOT — se ele escrever a
auto-ligação nalgum ramo que o boot não toma, é a primeira; se nunca a
escrever, é a segunda.

## Lição, outra vez a mesma

Comparei o `objvt` de uma corrida com a vigia de outra e construí uma teoria
inteira — "matriz percorrida como lista" — sobre a diferença. **Duas corridas
não são uma medição.** Bastou pôr as duas sondas juntas para a teoria cair em
dois minutos.

---

# As duas hipóteses resolvidas — e uma sobre-correcção minha (19.ª)

`func_0024C1F8` desmontado inteiro do EBOOT, 33 instruções, sem ramos:

```
0x0024C210  bl    0x0024BC78        escreve o cabecalho (0x40030001)
0x0024C218  lfs   f13, ...          1.0
0x0024C220  lfs   f0,  ...          0.0
0x0024C224  stfsu f13,0x70(r9)      r9 += 0x70 ;  *(r9)   = 1.0
0x0024C228  stfs  f0,12(r9)                       *(+0x7C) = 0.0
0x0024C22C  stfs  f0,4(r9)                        *(+0x74) = 0.0
0x0024C230  stfs  f0,8(r9)                        *(+0x78) = 0.0
0x0024C238  stfsu f0,0x80(r11)      linha 2:  0,1,0,0
0x0024C248  stfsu f0,0x90(r9)       linha 3
0x0024C258  stfsu f0,0xA0(...)      linha 4
0x0024C278  blr
```

**Matriz identidade 4×4 em `+0x70/+0x80/+0x90/+0xA0`.** O `+0x7C` é
`matriz[0][3]`, legitimamente `0.0`.

## Resposta às duas hipóteses

> ou o construtor devia auto-ligar `*(obj+0x7C) = obj+0x7C` e não o faz, ou
> aquele campo não é uma lista e os walkers não deviam lá tocar.

**É a segunda.** O construtor não está incompleto — está correcto e completo
para o que constrói. `+0x7C` **não é** uma cabeça de lista neste tipo.

## Sobre-correcção minha, e retiro-a

Na correcção 18 escrevi que "cai a generalização de que as quatro paredes são
objecto do tipo errado". **Fui longe de mais.** O que caiu foi a caracterização
do objecto ("é uma matriz", "não-polimórfico", "nunca foi um contentor") — isso
estava mesmo errado: é um objecto de tipo 1, com cabeçalho e matriz embutida,
correctamente construído e encadeado numa lista pelo `+0x0`.

Mas a generalização **não** caiu; ficou **provada**. Antes era inferência; agora
há prova estática: o `+0x7C` deste objecto é um elemento de matriz escrito pelo
construtor. Um walker que leia `+0x7C` como sentinela de lista está,
demonstravelmente, a olhar para o objecto errado.

O erro da 18.ª foi retirar a mais por ter retirado de menos antes — reagi à
descoberta de que `func_0024C1F8` era o construtor (e não um inicializador
alheio) descartando também a conclusão que essa descoberta não tocava.

## Estado final

Não há menu. Mas a pergunta que fica é a mais estreita de toda a sessão, e está
provada e não inferida:

> `func_002545B0` recebe em `arg` um objecto cujo `+0x7C` é `matriz[0][3]`.
> Quem lhe passa esse `arg` é `func_0024E270`, no sítio `0x0024E2D4`.
> **Porquê esse objecto?**

E há um caminho barato para a resposta: o objecto está encadeado (`+0x0` aponta
para o irmão `0x4077AD20`) e o walker percorre registos por tag. Ou o walker
apanha o nó errado da cadeia, ou o `arg` que ele passa devia ser outro campo do
nó — e isso lê-se em `func_0024E270` com o `arg` já conhecido.

---

# A cadeia fecha em círculo: o `arg` é o produto corrente da fábrica

Entrada real do walker: `func_0024E198` (achada por xref de alvos de `bl`; os
`func_0024E1E8`/`func_0024E270` são fragmentos). O prólogo guarda `r21` mas não
o define, e em `0x0024E268` só o trunca (`clrldi r21,r21,32`). Portanto `r21`
nasce num dos fragmentos trampolinados do laço — e o rasto identifica-o:

```
[B71] func_0024E3D0 #001 -> ps3_indirect_call r3=0x400C6210 ctr=0x0039E5A8
[B71] func_0024E3D0 #001 -> ps3_indirect_call r3=0x403008E8 ctr=0x0039E5A8
```

`func_0039E5A8` é a primeira função que decodifiquei nesta sessão:

```c
cursor = *(int8_t*)(fab + 0xC8);
if (cursor < 0) return NULL;
return *(uint32_t*)(fab + 0x48 + cursor*4);      // "dá-me o produto corrente"
```

**O `arg` que chega a `func_002545B0` é o produto corrente de uma fábrica.**

## O que isto amarra

A sessão fecha exactamente no item que estava aberto quando começou — *"o walker
do WAD pede à fábrica o produto corrente sem nunca ter feito push"* — mas agora
com tudo o que estava por medir, medido:

| elo | estado |
|---|---|
| o registry de tipos | **funciona** (`tab=0x00868D48`, tag→fábrica com vtable viva) |
| o objecto entregue | **bem construído** (cabeçalho + matriz identidade em `+0x70`) |
| o `+0x7C` que o walker lê | **`matriz[0][3]`**, provado por desmontagem do construtor |
| quem o entrega | `func_0039E5A8`, o "produto corrente" da fábrica |
| o consumidor | `func_002545B0`, que o trata como contentor com lista em `+0x7C` |

Logo o defeito está entre o **cursor da fábrica** (`fab+0xC8`) e o **array de
produtos** (`fab+0x48`): ou o cursor aponta para uma ranhura errada, ou o array
tem lá um produto de outro tipo.

E isso é medível com uma sonda em `func_0039E5A8` — cursor, ranhura, produto
devolvido, e o tag do produto — cruzada com o tipo que o consumidor assume.

## Estado final da sessão

Não há menu. O boot só entra no loop principal com três gates de diagnóstico.

O que fica é a cadeia inteira, do `main()` ao campo, medida degrau a degrau, com
a pergunta reduzida a duas palavras: **cursor ou array.**

---

# CORRECÇÃO (20.ª): o `arg` NÃO vem de `func_0039E5A8`

Escrevi na secção anterior, com confiança, que *"o `arg` que chega a
`func_002545B0` é o produto corrente de uma fábrica"*. **Está errado.**

Sonda em `func_0039E5A8` (`PS3_TRACE_PRODUCT`), 253 consultas numa corrida,
todas sãs:

```
179  fab=0x40300E80 cursor=0 ranhura=0x40300EC8 produto=0x40638B70 hdr=0x00516AA8
 45  fab=0x40300E80 cursor=1 ranhura=0x40300ECC produto=0x40638B70 hdr=0x00516AA8
 12  fab=0x403008E8 cursor=0 ranhura=0x40300930 produto=0x40638AD8 hdr=0x005168C8
 ... 20 fábricas distintas, cursores 0/1/2, todos os produtos válidos
```

Os `hdr` são todos `0x0051xxxx` — **vtables reais**. Estes produtos são objectos
polimórficos bem formados. (O campo que a sonda imprime como `tag` é, nestes,
o half baixo do ponteiro de vtable — não um tag de tipo, porque estes objectos
*têm* vtable.)

E **nenhum** produto devolvido é `0x4077ACxx` — o objecto que o walker de facto
despacha:

```
[TYPETAG] obj=0x4077AC20 objvt=0x40030001 tag=1 ...
```

## O erro, e é o mesmo de sempre

Vi no rasto `func_0024E3D0 #001 -> ps3_indirect_call ctr=0x0039E5A8`, vi que
`r21` não era definido no fragmento que eu tinha lido, e **inferi** que vinha
dali. Não medi. A medição custou uma corrida e refutou-o.

É a mesma classe de erro que já cometi hoje com o `lr` do guest, com o `ra1` do
host, e com o xref de `bl` que não vê despachos indirectos: **usar a estrutura
para adivinhar o dado, em vez de medir o dado.**

## O que fica de pé

- O registry funciona (medido).
- O objecto entregue está bem construído e o seu `+0x7C` é `matriz[0][3]`
  (provado por desmontagem).
- O consumidor lê `+0x7C` como sentinela de lista.
- **A origem do `arg` continua por medir.** `func_0039E5A8` está excluída.

O caminho certo para a próxima sessão é sondar `r21` em cada fragmento de
`func_0024E198` (a entrada real do walker: `func_0024E1E8`, `func_0024E270`,
`func_0024E354`, `func_0024E3D0`, `func_0024E414`, `func_0024E430`) e ver em
qual ele passa a valer `0x4077ACxx`. É o mesmo padrão da bissecção que
funcionou hoje — e desta vez com o dado medido, não inferido.

---

# A origem do `arg`, medida — e a 21.ª correcção (o bug era do meu descodificador)

## O que a sonda deu

`PS3_TRACE_R21` em 19 fragmentos do walker. O mais cedo no fluxo onde `r21` já
vale `0x4077ACxx` é `func_0024E26C` — antes do laço.

## O que eu concluí, e estava errado

Varri o binário à procura de escritas em `r21` e li três:

```
0x0024E268  .long 0x7AD50020    ← li como "clrldi r21,r21,32" (só trunca)
0x0024E318  ld r21,136(r1)      ← restauro do slot do prólogo
0x0024E434  .long 0x7AD50020    ← idem
```

e concluí que **`r21` vinha do chamador** — uma função a usar um registo
callee-saved sem o inicializar.

**Está errado, e o erro era do meu descodificador.** Em `rldicl` o destino é
**rA**, não rS. Listando os campos em vez de confiar na minha impressão:

```
0x0024E268  op=30  rT/rS=22  rA=21   →  clrldi r21, r22, 32   →  r21 = r22
```

## A origem, correcta

```
0x0024E1F0  bl    0x003A6740        r30 = resultado
0x0024E214  lwz   r9,12(r30)        r9  = *(r30 + 0xC)
0x0024E22C  lwz   r22,8(r9)         r22 = *(r9 + 8)
0x0024E268  clrldi r21,r22,32       r21 = r22        <- o arg
0x0024E2C8  mr    r3,r21            e' usado aqui
0x0024E2D8  lhz   r0,2(r21)         e o tag sai de +0x2
```

**`arg = *( *(func_003A6740() + 0xC) + 8 )`.**

Três indirecções, todas mediveis, e uma chamada nomeada no início da cadeia.

## A lição, e é nova

As vinte correcções anteriores foram sobre **dados** — instrumentos que
mentiram, amostras truncadas, inferências não medidas. **Esta foi uma ferramenta
minha com um bug**: o descodificador de `rldicl` trocava origem e destino, e eu
li o output como se fosse verdade porque o tinha escrito.

O que a apanhou foi despejar os **campos brutos** (`op`, `rT/rS`, `rA`) em vez
da minha própria formatação. Regra que fica: quando um desassemblador caseiro
diz algo estrutural surpreendente ("esta função usa um registo sem o
inicializar"), imprimir os campos brutos antes de acreditar. O custo foi uma
corrida; o benefício foi não escrever na próxima sessão que o jogo tem um bug de
convenção de chamada.

## Onde isto deixa a investigação

`func_003A6740` é o primeiro elo da cadeia que produz o `arg`. Sondá-la — o que
devolve, e o que está em `+0xC` e `+8` do resultado — é o próximo passo, e é do
mesmo tamanho dos que fiz hoje.

---

# A cadeia do `arg` está sã — e é aí que a investigação encosta

Sonda nas três indirecções (`PS3_TRACE_ARGCHAIN`), as duas linhas do walker:

```
r30=0x407806F0  +0xC=0x40008AF8  arg=0x4077AC10  w0=0x40030001  tag=1
r30=0x40780720  +0xC=0x40008B04  arg=0x4077AD20  w0=0x40030001  tag=1
```

**Todos os três ponteiros são válidos.** Não há indirecção partida: nem
`func_003A6740` devolve lixo, nem `+0xC` aponta para fora, nem o slot `+8` tem
um número em vez de um ponteiro.

> Ressalva de instrumento: a agulha `ctx->gpr[22] = vm_read32(ctx->gpr[9] + 0x8)`
> é genérica e casou **20 sítios** no lift. Das 12 linhas da corrida, só as duas
> acima são do walker (as outras têm `r30=1`/`r30=2` e vêm de fragmentos de
> funções não relacionadas). Mesma classe de ressalva do `REGLOOKUP` de manhã:
> agulha larga produz linhas verdadeiras sobre coisas erradas.

## O impasse, formulado com precisão

Tudo o que se mede está coerente:

| | |
|---|---|
| `func_003A6740` | devolve ponteiro válido |
| `*(r30+0xC)`, `*(+8)` | ponteiros válidos |
| o `arg` | objecto com cabeçalho `0x40030001`, tag **1** |
| o registry | tag 1 → fábrica `0x400C5048`, vtable viva, método `func_0039D428` |
| o construtor do `arg` | `func_0024C1F8`, completo, matriz identidade em `+0x70` |
| o consumidor | lê `+0x7C` como sentinela de lista |

E `+0x7C` está **dentro** da matriz (`matriz[0][3]`).

Portanto: ou **o cabeçalho mente** (o objecto diz ser tipo 1 e não é), ou **o
método do tipo 1 não devia ler `+0x7C` como lista**. Não há terceira hipótese, e
nenhuma das duas se decide com mais sondas de ponteiros — decide-se
identificando as duas classes C++ envolvidas e comparando os seus layouts.

## Onde isto fica

Esta sessão levou o problema de *"o boot não chega ao menu"* — sem sujeito — até
um conflito de layout entre duas classes, com endereços para as duas e com todos
os elos intermédios medidos e excluídos. O que falta não é mais uma medição do
mesmo tipo: é análise estrutural das classes, que é trabalho de outra natureza.

**Não há menu, e não haverá enquanto este conflito não for resolvido pela raiz.**
