# A cadeia completa: do menu que não aparece até ao alocador que falha

**Data:** 2026-08-01 · Cada elo medido, e cada leitura de código verificada contra o PPC
original do `EBOOT.ELF`.

## A cadeia, de cima para baixo

```
o menu não aparece
  └─ thr_auto_load nunca termina (gate 0/6, elo AUTO_LOAD)
      └─ FATAL: stuck calling 0x00514E80 — laço infinito em func_002545D4
          └─ o nó da lista tem payload 0  →  lê o "tipo" do endereço guest 2
              └─ o objecto que lhe entregam nunca foi alocado
                  └─ func_00220284 corre com this=0
                      └─ func_002182A4 passa sem verificar o retorno
                          └─ func_00227788 devolve 0
                              └─ func_00263554 (pop da free-list) devolve 0
                                  └─ func_002635A4 (crescer o pool) devolve 0
                                      └─ func_00263040 (ALLOC do heap) FALHA
```

## As duas medições que fecharam os dois últimos elos

**1. O pool não é "mal configurado".** A sonda `PS3_TRACE_POOLGROW` apanhou 40 passagens
pelo caminho de crescimento, e **zero** com `grow=0`:

```
[POOLGROW] #1 pool=0x40331608 grow=32  elem=80  hdr=16 heap=0x40004020 head=0
[POOLGROW] #2 pool=0x42F85B50 grow=16  elem=216 hdr=16 heap=0x42F83D48 head=0
[POOLGROW] #8 pool=0x4007F8B0 grow=128 elem=8   hdr=4  heap=0x40004020 head=0
```

`head=0` é o **estado normal** de um pool com preenchimento preguiçoso — acontece 40 vezes
e resolve-se 40 vezes. Não é anomalia.

**2. Logo o NULL vem da outra saída de `func_002635A4`:**

```c
if (grow == 0) { return NULL; }               // <- MEDIDO: nunca acontece
r3 = *(pool + 0xC);                           // o heap
func_00263040(r3, hdr + grow*elem, 8);        // ALLOC
if (r3 == 0) { return NULL; }                 // <- é ESTE
```

**`func_00263040` não consegue alocar.**

E foi confirmado pelo outro lado, na mesma corrida: 237 alocações passam bem
(`alloc=0x406387E0`, índices 0..10, slots válidos) e a 238.ª — de outro alocador,
`0x400C6B50` — devolve zero, com o `this=0` a aparecer **na linha seguinte do log**.

## Porque isto importa

`func_00263040` é o alocador de boundary-tags — **exactamente o que este projecto persegue
desde os seis `FREELIST-TAG-GUARD`**. A cadeia de hoje liga, pela primeira vez e elo a
elo, o sintoma visível (o menu não aparece) ao problema que já era conhecido.

Também explica porque nenhum dos quatro sintomas era corrupção de memória: o
`PS3_WATCH_STORE` mostrou quatro vezes que ninguém estraga bytes. Não estragam — **falta
memória**, e o código do jogo não verifica nenhum dos quatro retornos pelo caminho. Num
PS3 real cada um deles rebentaria na página nula, o que quer dizer que no console **a
alocação nunca falha** — logo o defeito é do nosso lado do heap, não do jogo.

## O que foi eliminado, por medição e não por argumento

- **Não é o lifter.** Cada passo desta cadeia foi desmontado do `EBOOT.ELF` e comparado:
  o `beq` do `func_002545D4`, o prólogo do `func_002210BC` com `rldicl r26,r3`, o `bl` em
  `0x00218394` com `mr r3,r29`, a entrada real `0x002545B0`. Todos fiéis.
- **Não é corrupção de memória.** Quatro watches, quatro vezes limpo.
- **Não é o índice de classe de tamanho.** 237 passagens com índices 0..10 e slots válidos.
- **Não é o pool mal configurado.** 40 passagens de crescimento, zero com `grow=0`.
- **Não é o `F2B-STREAM-PUMP`** (esse era real e foi corrigido hoje, mas é outro defeito).

## O próximo passo, e é uma pergunta só

**Porque falha `func_00263040`?** Heap esgotado, ou free-list/boundary-tags num estado em
que o walk não encontra bloco? O projecto já tem seis guards nessa família e o
`PS3_TRACE_POOLCNT` para distinguir leak de refill — a instrumentação existe, é aplicá-la
a esta alocação concreta (`heap=0x40004020`, o tamanho pedido é `hdr + grow*elem`).

---

# CORRECÇÃO: `func_00263040` **não** falha. O que é nulo é o ponteiro do pool.

A conclusão acima — *"`func_00263040` não consegue alocar"* — era **inferência**, não
medição: eu tinha provado que o `grow=0` nunca acontece e concluí, por eliminação, que a
outra saída NULL de `func_002635A4` era a culpada. **Errado.** A sonda directa mede:

```
[POOLALLOC] ok pool=0x40331608 heap=0x40004020 pedido=2576 r3=0x40331830 (ok=1 falhas=0)
[POOLALLOC] ok pool=0x42F85B50 heap=0x42F83D48 pedido=3472 r3=0x42F85BA8 (ok=2 falhas=0)
...
[POOLALLOC] ok pool=0x4007F8B0 heap=0x40004020 pedido=1028 r3=0x40680A58 (ok=8 falhas=0)

falhas = 0
```

**Oito alocações, oito sucessos.** O heap está bem e o alocador de boundary-tags faz o
seu trabalho.

## Onde está o zero, então

Relendo `func_00263554` com o valor medido:

```c
r31 = r3;                 // <- o POOL, que vem de *(alloc + (idx<<2) + 0x8C)
r3  = *(r31 + 4);         // head da free-list
```

E o `[SZCLASS] #238` diz `slot=0x00000000`. Esse `slot` **é o `r3` que entra**, ou seja o
**ponteiro do pool**, não a cabeça da free-list. Com `r31 = 0`, a função lê `*(0+4)` e
segue com lixo — e por isso o `[FLHEAD]` apanhou `pool=0x00000005` noutra corrida: são
leituras da base da memória guest, não de nenhuma lista.

Ou seja:

| | 237 primeiras | a 238.ª |
|---|---|---|
| alocador | `0x406387E0` | **`0x400C6B50`** |
| `*(alloc + (idx<<2) + 0x8C)` | ponteiro de pool válido | **`0`** |

E o `PS3_WATCH_STORE` já tinha dito o resto: **uma única escrita** em `0x400C6BDC`, a
escrever `0`, vinda de `func_0022E6A4` (construtor, chamado de `func_002B11B8`).

**O alocador `0x400C6B50` é construído com a tabela de pools a zero e ninguém a preenche.**

## O que isto muda na pergunta

Não é "porque falha o heap" — o heap não falha. É **"quem devia criar os pools de
`0x400C6B50`, e porque não corre"**. É uma pergunta de inicialização, não de memória.

## A lição, outra vez

Provei que uma das duas saídas NULL não acontecia e **concluí por eliminação** qual era a
outra, sem a medir. A medição custou uma corrida e desfez a conclusão. Numa cadeia com dez
elos, "só pode ser a outra" não é um elo medido — é um palpite com boa reputação.

---

# O fim: dois construtores, um faz metade do trabalho

`PS3_WATCH_STORE` nas duas entradas de índice 0 — a do alocador que funciona e a do que
não — na mesma corrida:

```
alocador SÃO   (0x406387E0), entrada 0x4063886C:
  w32 [0x4063886C]=0x00000000   ra0=func_00228368+0x15C  ra1=func_00411A5C+0x1D8   <- zera
  w32 [0x4063886C]=0x407719A8   ra0=func_0022851C+0x2FC  ra1=func_00411A5C+0x1D8   <- POPULA

alocador PARTIDO (0x400C6B50), entrada 0x400C6BDC:
  w32 [0x400C6BDC]=0x00000000   ra0=func_0022E6A4+0x8C0  ra1=func_002B11B8+0x6FB8  <- zera
                                                                                   <- e mais nada
```

**A construção do alocador tem dois passos: zerar a tabela de pools e depois populá-la.**

| | zera | popula | chamados de |
|---|---|---|---|
| `0x406387E0` (são) | `func_00228368` | **`func_0022851C`** | `func_00411A5C` |
| `0x400C6B50` (partido) | `func_0022E6A4` | **nunca** | `func_002B11B8` |

O caminho que passa por `func_002B11B8` faz o primeiro passo e não faz o segundo. E
`func_00227788` lê `*(alloc + (idx<<2) + 0x8C)` e passa-o directo ao pop **sem verificar** —
porque no desenho do jogo essa entrada nunca pode ser nula.

## A cadeia inteira, agora com o primeiro elo

```
func_002B11B8 constrói o alocador 0x400C6B50 e não popula a tabela de pools
  └─ *(0x400C6B50 + 0x8C) fica a 0
      └─ func_00227788 passa esse 0 ao func_00263554 como se fosse um pool
          └─ o pop lê *(0+4) e devolve lixo/0
              └─ func_002182A4 não verifica o retorno
                  └─ func_002210BC põe-no em r26
                      └─ func_00220284 corre com this=0 e escreve por ponteiros lidos
                         da base da memória guest
                      └─ e o objecto que devia ter sido alocado nunca existe
                          └─ o nó da lista fica com payload 0
                              └─ func_002545D4 lê o "tipo" do endereço 2 e despacha
                                 por tab[lixo]=0
                                  └─ FATAL: stuck calling 0x00514E80
                                      └─ thr_auto_load nunca termina
                                          └─ o menu não aparece
```

**Onze elos, todos medidos, nenhum inferido.**

## A pergunta que fica, e é uma só

Porque é que o caminho de `func_002B11B8` não corre o passo de popular? Duas hipóteses,
ambas baratas de testar:

1. **Falta uma chamada** — o construtor equivalente ao `func_0022851C` existe e não é
   invocado neste caminho. Comparar `func_00411A5C` (que chama os dois) com o troço de
   `func_002B11B8` que chama o `func_0022E6A4`.
2. **A chamada existe e sai cedo** — algum argumento (contagem de classes, tamanho) chega
   a zero e o laço de populagem não itera.

A (1) resolve-se lendo `func_00411A5C` e o sítio de `func_002B11B8+0x6FB8`; a (2) com uma
sonda na entrada do popular. Nenhuma das duas precisa de adivinhar.

---

# E fecha o círculo: `0x400C6B50` não é um alocador de pools

`func_0022E6A4` — a única função que escreve na tabela do objecto partido — **nunca cria
pools**. As suas chamadas, todas:

```
func_002637D8 (×4)   func_00252564   func_0025BE3C
```

Nenhuma é `func_002BB1B0` (o criador de pool), nem `func_0022851C`, nem `func_00228368`.
E carimba `0xDEADBEEF` no início — um magic de sentinela, coisa de quem inicializa memória
que ainda não tem dono.

Compare-se com o construtor a sério, `func_00228368`, que zera as **três** tabelas do
objecto (`+0x48`, `+0x8C`, `+0xD0`, 17 entradas cada) e depois **ou** cria os pools de raiz
(`func_0022851C`, quando `r3==0`) **ou** copia os ponteiros de um template.

**Logo `0x400C6B50` não é um objecto desta família.** A escrita de `0` em `0x400C6BDC` que
o watch apanhou não é "a tabela de pools inicializada e nunca preenchida" — é outra
estrutura, de outra classe, que calha ocupar aquela memória.

## O que isto quer dizer

O círculo fecha no padrão do dia: **`func_00227788` recebeu, da sua primeira chamada
virtual, um objecto que não é o alocador que ela assume.** É o mesmo mecanismo do
`func_002545B0` a receber um objecto-matriz, e do `func_002545D4` a ler um "tipo" do
endereço 2.

Não é memória corrompida (quatro watches limpos), não é o heap (8 alocações, 8 sucessos),
não é o lifter (cada passo desmontado e comparado). É **despacho**: métodos a correr sobre
objectos da classe errada, e o candidato natural continua a ser a resolução de tipos
`tab[(tipo<<2)]` — a mesma tabela `0x00868D48` que atravessa esta investigação toda.

## O que fica por fazer, em ordem

1. Sondar a **primeira chamada virtual** dentro de `func_00227788` (`*(vt+0x50)` do
   singleton `*(TOC-0x2A78)+0xC`): que objecto devolve, e qual é o seu tipo. Se devolver
   `0x400C6B50` quando devia devolver um `0x406387E0`-like, o defeito está no que essa
   vtable resolve.
2. Cruzar com o registo de tipos: `0x400C6B50` está registado como que tipo, e por quem.

Ambas são medições com a instrumentação que já existe (`PS3_TRACE_ICALL_TO`,
`PS3_TRACE_TYPESLOT`, sonda na entrada). Nenhuma precisa de código novo.

---

# A resposta: o singleton devolve um alocador de OUTRA CLASSE

Sondando o resultado da primeira chamada virtual dentro de `func_00227788` — a que produz
o "alocador" que ela depois indexa — a corrida inteira tem **dois** resultados distintos:

```
[ALLOCSRC] #1 alloc=0x406387E0 vt=0x00514F28 tab8C[0]=0x407719A8   <- são
[ALLOCSRC] #2 alloc=0x400C6B50 vt=0x00515008 tab8C[0]=0x00000000   <- partido
```

**As vtables são diferentes.** `0x00514F28` e `0x00515008` são duas classes distintas, e só
a primeira tem a tabela de pools em `+0x8C`.

E o `PS3_WATCH_STORE` no `0x400C6B50` já tinha mostrado a construção completa desse
objecto — a cadeia de vptr da herança, todas escritas por `func_00411AC8`:

```
[0x400C6B50]=0x511628   func_00411AC8+0x55C
[0x400C6B50]=0x5115B0   func_00411AC8+0x630
[0x400C6B50]=0x511538   func_00411AC8+0x74C
[0x400C6B50]=0x515008   func_00411AC8+0x870   <- classe final
```

**O objecto está bem construído.** Não falta inicialização nenhuma: é um objecto completo
de uma classe que simplesmente não é um alocador de pools.

## O que isto estabelece, e é o fim desta linha

`func_00227788` faz `this->singleton->vt[0x50]()` e usa o resultado como alocador. Numa
das passagens o singleton devolve um objecto de classe `0x00515008` em vez de
`0x00514F28`, e a partir daí tudo o que se segue — o `pool=0`, o `this=0`, o nó com
payload nulo, o `tab[lixo]`, o `FATAL` — é consequência mecânica.

Fecha o padrão do dia com o mesmo veredicto que os outros quatro sítios: **não é memória,
não é o heap, não é o lifter, não é inicialização em falta. É despacho** — um método
virtual a devolver um objecto da classe errada.

## A pergunta seguinte, e é só uma

O que distingue as duas invocações do `*(vt+0x50)`? O singleton é o mesmo
(`*(TOC-0x2A78)+0xC`); o que muda é o contexto. Medir `this`, `r4` (que vem de
`*(obj+0x24)+0x14`) e o `code` resolvido em cada uma das duas passagens diz se o singleton
está a escolher mal, ou se lhe estão a pedir a coisa errada.

É uma sonda no mesmo sítio, com dois campos a mais. Nenhum código novo no motor.
