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
