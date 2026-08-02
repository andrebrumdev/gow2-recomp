# A parede tem nome: `func_000B71B8` (B71) entra e nunca retorna

Data: 2026-08-01, depois de provar que o elo AUTO_LOAD não pertence à cadeia.

## Método: bissecção por sonda de entrada, com controlo obrigatório

31 funções instrumentadas na entrada (`PS3_TRACE_ALCHAIN`), mais uma sonda de
**CONTROLO** numa função que sei correr. Sem controlo não se lê um zero — foi a
lição das quatro sondas que mentiram nesta sessão. Três rondas:

**Ronda 1** — `main()` (`func_0025C838`) é uma sequência recta de nove chamadas,
sem condicionais:

```
func_002B37D4 ✅  func_00242700 ✅  func_002B4F04 ✅  func_0025C680 ✅
func_002B76EC ✅  func_002B2EEC ✅  func_002B2E74 ✅  func_002B2E04 ❌
```

**Ronda 2** — `func_002B2E74`, também recta, onze chamadas:

```
func_0024A7CC ✅  func_002AAC84 ✅  func_002AC328 ✅  func_002AB2F8 ✅
func_002B5C94 ✅  func_002B5508 ✅  func_002D2978 ✅  func_002287AC ✅
func_000B71B8 ✅  func_0023B654 ❌
```

**A última que imprime é a que não retorna: `func_000B71B8` — o B71.**

## O que isto corrige

O loop principal do jogo (`func_00242C94`) é a **oitava** chamada do `main()`,
imediatamente a seguir a `func_002B2E74`. Como esta nunca retorna, **o jogo
nunca entra no seu loop principal.**

Portanto:

- Os 2619 `SetFlipCommand` por corrida **não são** o loop principal. Vêm de
  outro sítio (movie/intro path).
- O despacho de estado `*(r30+0x460C)` — o mecanismo que faz o jogo avançar de
  estado — **nunca corre uma única vez** (`PS3_TRACE_STATE` = 0).
- A leitura que eu tinha escrito uma hora antes ("o loop corre e nunca
  retorna") estava errada na primeira metade. Zero linhas depois da chamada é
  igualmente compatível com "a chamada nunca aconteceu" — e é esse o caso. O
  que me faltava era medir a entrada, não só a saída.

## Porque é que o B71 não retorna

```
[ICALL-BAD] ctr=0x00514E80 lr=0x0024E2D4 r3=0x00000000 r11=0x00000000   (x2000)
[ppu] FATAL: stuck calling 0x00514E80 (2000 times) -- aborting run
[ppu] rbp frame walk:  #0 ret=func_002545D4+0xAD0
```

É a parede documentada em Julho (`patch_2545b0_entry_probe.py`): o walker de
registos do WAD (`lr=0x0024E2D4`) entrega a `func_002545B0` um objecto cuja
lista circular tem `head = 0`; o teste de vazio do jogo é `head == sentinela`,
que um 0 nunca satisfaz; o walk entra com um nó nulo e despacha em ciclo sobre
NULL até o breaker dos 2000 chamar `exit(3)`.

**O `exit(3)` é o que impede o B71 de retornar.** O boot não fica pendurado —
morre.

## O re-teste que tinha de ser feito

Em Julho concluiu-se que saltar esta parede (`PS3_LIST254_EMPTY_IF_NULL=1`)
**não desbloqueia**, porque `thr_auto_load` continuava a 0. Mas essa métrica
media uma string que não existe em binário nenhum — não podia disparar. A
conclusão tinha de ser refeita com o instrumento corrigido.

Refeita hoje, com as sondas de entrada:

| | gate OFF | gate ON |
|---|---:|---:|
| `FATAL` | 1 | **0** |
| `LIST254-GATE` (saltos) | 0 | 1 |
| último degrau | B71 | **B71** |
| `STATE` (despacho de estado) | 0 | 0 |

**A conclusão de Julho estava certa** — mas por uma razão diferente da que se
registou. Com o gate, o `FATAL` desaparece e o processo deixa de morrer; passa
a **pendurar** dentro do B71, num ciclo de stream FIOS:

```
85  [SPUJOB] spu job returned cleanly
82  [FIOSOPEN] F2B-STREAM-ENSURE ...
46  [cellGcmSys] SetFlipCommand(bufferId=0/1/2)
37  [FIOSOPEN] F2B-STREAM-FILL ...
16  [vm] UNCOMMITTED write32 ... ra=func_00220284+...
```

Ou seja: há um **segundo** bloqueador dentro do B71, logo a seguir ao primeiro.
Morrer e pendurar são estados diferentes; a métrica antiga dava o mesmo número
para os dois.

## Onde continuar

O B71 é longo (é a sequência de boot que chama a intro). A bissecção por
entrada não chega lá dentro sem instrumentar dezenas de chamadas. O próximo
passo é localizar o ciclo dentro do B71 — e as pistas já medidas são o walker
do WAD (`0x0024E2D4`), o `func_00220284` a escrever 16 words através de um
ponteiro não-comprometido, e o ciclo de stream FIOS.

## Contabilidade

Não cheguei ao menu. Mas a parede deixou de ser "o boot não chega ao AUTO_LOAD"
(um elo que se provou ser código de encerramento) e passou a ser **uma função
nomeada, com a cadeia inteira desde o `main()` medida degrau a degrau**.

---

# A cadeia fecha: do `main()` até ao objecto de Julho

Rasto de cada chamada dentro do B71 (`PS3_TRACE_B71`, 147 pontos de passagem,
uma reconstrução). O último número impresso é a chamada que não voltou:

```
[B71] func_000B71B8 #041 -> func_0010F5E8
[B71] func_0010F5E8 #001 -> func_0024F24C      ✅ volta
[B71] func_0010F5E8 #002 -> func_0024C878      ✅ volta
[B71] func_0010F5E8 #003 -> ps3_indirect_call  this=0x400C5048  ctr=0x0039D51C
[B71] func_0039D51C #001 -> ps3_indirect_call  this=0x400C5048  ctr=0x0039D3C4  ✅ volta
[B71] func_0039D51C #002 -> ps3_indirect_call  this=0x400C61C8  ctr=0x0039E40C
                                                     ^^^^^^^^^^ (silêncio a partir daqui)
```

`func_0010F5E8` é um **lookup no registry de tipos**:

```c
r0  = rlwinm(*(uint16*)(obj+2), 2, 14, 29);   // (tipo << 2) & 0x3FFFC
r11 = *(TOC-0x4D94 + r0);                      // fabrica = tab[idx]  -> 0x400C5048
ps3_indirect_call(*(vt+0x20));                 // -> func_0039D51C
```

`idx = (tipo<<2) & 0x3FFFC` é a fórmula do registry de tipos que o CLAUDE.md
documenta. É a Parede D, alcançada pelo caminho natural.

E `this = 0x400C61C8` no último salto é **o mesmo objecto** das sondas de
Julho:

```
[E545B0] #1 this=0x400C61C8 arg=0x4063858C sent=0x40638608 head=0x40007F34  <- lista válida
[E545B0] #2 this=0x400C61C8 arg=0x407790D0 sent=0x4077914C head=0x00000000  <- laço infinito
```

## A cadeia inteira, medida ponta a ponta

```
main() func_0025C838
  └─ func_002B2E74                       (7ª de 9 chamadas)
       └─ func_000B71B8  = B71           (9ª de 11)
            └─ #41 func_0010F5E8         lookup no registry de tipos
                 └─ #03 → func_0039D51C  this=0x400C5048 (fábrica)
                      └─ #02 → func_0039E40C  this=0x400C61C8
                           └─ … → func_002545B0 com head=0
                                └─ despacho virtual sobre NULL, em ciclo
                                     └─ breaker aos 2000 → exit(3)
  ✗ func_002B2E04  (8ª) — NUNCA ALCANÇADA
       └─ func_00242C94 — O LOOP PRINCIPAL DO JOGO, nunca corre
```

Cada seta desta cadeia foi **medida**, não inferida. As duas hipóteses de bug
do lifter que levantei pelo caminho foram ambas refutadas contra o binário.

## O que isto vale

O trabalho de Julho tinha nomeado o objecto (`0x400C61C8`) e o sintoma
(`head=0`), mas não sabia **onde na execução** isso acontecia nem **o que
bloqueava**. Agora sabe-se as duas coisas: bloqueia o `main()` na sétima
chamada, e por isso o jogo nunca entra no loop principal.

A pergunta operacional deixa de ser "porque é que o boot não avança" e passa a
ser uma pergunta com sujeito: **porque é que `func_0039E40C`, chamada sobre
`0x400C61C8`, entrega a `func_002545B0` um objecto cuja lista tem `head=0`.**
