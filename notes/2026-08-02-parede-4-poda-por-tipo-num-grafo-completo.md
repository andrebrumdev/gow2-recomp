# Parede 4 — a poda é por TIPO, e o grafo de tipos é completo

Data: 2026-08-02. Atacada como plano isolado (Fase 11, parede 4 de 4 — promovida
a primeira porque as paredes 1 e 3 são o mesmo defeito visto do lado do consumo).

## O sintoma

`func_0041F700` domina o rasto: **27 539 083 de 27 549 345 linhas (99,96%)**. O
chamador nem aparece no topo — a função é recursiva.

## O que já estava eliminado por medição

- o laço de irmãos **avança** (`r31 = r9`) — 4ª suspeita de bug do lifter, refutada
- as listas de irmãos **estão bem formadas**: `head == sentinela` quando vazias,
  12 nós, terminam
- o walk exterior `func_0041FF70` **termina** (2 entradas, acaba em NULL)
- o walk de `func_002547AC` **nem corre** com o gate (sonda deu zero)

## A estrutura, medida em bruto

Palavra `+4` dos filhos:

```
0xC0120012  tag 0x12 = 18        0xC0110011  tag 17
0xC0190019  tag 0x19 = 25        0xC00F000F  tag 15
0xC0200020  tag 0x20 = 32        0xC0140014  tag 20
0xC0100010  tag 0x10 = 16        0xC0040004  tag 4
0xE0150015  tag 0x15 = 21  ←     0xC0030003  tag 3
0xC0170017  tag 0x17 = 23        0xC0090009  tag 9
```

Formato **`0xFFTT00TT`**: o tag aparece nas duas metades. A metade baixa alimenta
o índice do registry (`(v<<2)&0x3FFFC`); a metade alta alimenta a poda
(`(v>>16)&0xFFF`). **A estrutura é coerente** — não há campo corrompido.

Nota: `0xE0150015` (tag 21) é o único com flags `0xE0` em vez de `0xC0`. Um bit
extra, num só filho. Fica registado; não foi investigado.

## A causa

A poda é:

```c
r29 = (*(arg   + 4) >> 16) & 0xFFF     // tag do objecto que está a ser percorrido
r0  = (*(filho + 4) >> 16) & 0xFFF     // tag do filho
if (r0 == r29) goto salta;             // ← só salta filhos DO MESMO TIPO
```

**É uma poda por tipo, não um guarda de ciclo.** E não existe conjunto de
visitados: varri todos os stores de `func_0041F700` e são apenas dois —
`vm_write8(fab+0xC8, cursor)` e `vm_write32(fab+0x48+cursor*4, nó)`. **Nenhuma
escrita a `*(nó+4)`**, portanto não há carimbo de visita.

O objecto percorrido é do tipo 1; os 12 filhos são dos tipos 3, 4, 9, 15, 16, 17,
18, 20, 21, 23, 25 e 32. Nenhum é 1 → **nada é podado**. E cada um desses desce
para todos os tipos diferentes do seu — incluindo o 1 outra vez.

**O grafo de tipos é completo.** Percorrê-lo em profundidade com uma poda que só
impede a auto-recursão imediata dá 12⁷ ≈ 35 M — exactamente a ordem de grandeza
medida.

## O que isto liga à parede 1

A lista de filhos de cada tipo é o que a parede 1 consome, e **mistura as duas
famílias** (medido no walk exterior: `0x40638594` w0=`0xC0010001` lista +
`0x4077AD28` w0=`0x40030001` registo WAD). Quem popula essa lista é o `push`
desta função.

Ou seja: **a mesma lista que a parede 4 percorre em excesso é a que a parede 1
consome com o layout errado.** São dois sintomas de uma estrutura mal populada.

## A pergunta que fecha a parede 4

> **A lista em `objecto+0x7C` deve conter todos os outros tipos, ou só os
> subtipos directos?**

Se for "todos" (uma lista global de tipos registados partilhada por todos os
objectos), então percorrê-la recursivamente por tipo é errado por construção — e
o defeito está em quem chama `func_0041F700` como se fosse um walk de árvore.

Se for "subtipos directos", a lista está mal populada — e quem a popula é o
`push` desta mesma função.

**Medição que decide, e é pequena:** listar a lista de `+0x7C` de dois tipos
diferentes (o 1 e, digamos, o 3). Se forem idênticas, é a lista global e a
resposta é a primeira. Se diferirem, são subtipos e a resposta é a segunda.

---

# A medição que decide: as listas são POR OBJECTO, e o push não tem pop

## As listas são distintas

Sonda de irmãos com cap 200, agrupada por sentinela (a sentinela identifica o
objecto):

```
sent=0x42F853B0  →  12 nós em 0x40007D0C..0x40007DE4
sent=0x40638608  →  12 nós em 0x40007E5C..0x40007F34
sent=0x4073DBF8  →  12 nós em 0x40008738..0x400087BC
```

**Três objectos, três listas próprias, em blocos de memória distintos.** Não é
uma lista global partilhada: cada tipo tem os seus 12 filhos. Logo são subtipos,
e o grafo de tipos é genuinamente completo — 12 tipos, cada um a apontar para os
outros.

## O push não tem pop

Varrimento das escritas ao cursor (`fab+0x48+0x80` = `fab+0xC8`) na família:

| função | escreve o cursor | decrementa |
|---|---|---|
| `func_0041F700` (o walk) | sim | **não** |
| `func_0041F7F8` | sim | não |
| **`func_0041F924`** | sim | **sim** ← o POP |
| `func_0041FF70` | não | não |

E `func_0041F924` opera no mesmo campo:

```c
r3 = fab + 0x48
r9 = *(uint8*)(r3 + 0x80)       // = *(fab + 0xC8), o MESMO cursor
r0 = (int8)r9
if (r0 < 0) -> vazio
r9 = r9 - 1                      // cursor--
```

No rasto: **27 539 083 passagens pelo walk contra 2 088 pops.**

## A cadeia causal, agora completa

O cursor é um **byte com sinal** (`vm_read8` seguido de `(int8_t)`), logo satura
aos 127 e passa a negativo. E:

1. o grafo de tipos é completo (12 tipos, 12 filhos cada)
2. a poda só salta filhos **do mesmo tipo** e não há conjunto de visitados
   → travessia exponencial, 12⁷ ≈ 35 M
3. cada visita faz `cursor++` e empurra, **sem pop no mesmo walk**
4. o cursor transborda os 127 e fica **negativo**
5. `func_0039E5A8` devolve **NULL** quando `cursor < 0`:
   ```c
   cursor = *(int8_t*)(fab + 0xC8);
   if (cursor < 0) return NULL;
   return *(uint32_t*)(fab + 0x48 + cursor*4);
   ```

E o passo 5 é **exactamente o sintoma que Julho registou** — *"o walker pede à
fábrica o produto corrente e não há push"*. Havia push: havia push a mais, e o
cursor tinha transbordado para negativo.

## O que isto explica de uma vez

| observação | explicação |
|---|---|
| Julho: "produto corrente é NULL, nunca houve push" | cursor negativo por transbordo |
| hoje: 253 consultas sãs em 20 fábricas | as outras fábricas não sofrem o walk exponencial |
| parede 1: lista mistura as duas famílias | o push empurra cada nó visitado, sem discriminar |
| parede 4: 27,5 M de iterações | a travessia exponencial em si |

## A pergunta que fecha a parede 4

> **O walk devia parar antes — e o que o devia parar?**

Duas hipóteses concretas, ambas mediáveis:

1. **Falta um pop.** Se `func_0041F700` devia desempilhar ao sair, a ausência é um
   defeito de tradução — e verifica-se desmontando o epílogo dela contra o EBOOT.
   *(Aviso: quatro suspeitas de bug do lifter nesta sessão, quatro refutadas.
   Verificar ANTES de afirmar.)*
2. **A poda devia ser por nó visitado, não por tipo.** Se o jogo carimba os nós
   noutro sítio, esse carimbo não está a ser escrito — e nesse caso o defeito
   está a montante, em quem devia carimbar.

A #1 é a mais barata e decide-se sem correr nada: desmontar o epílogo de
`func_0041F700` em `0x0041F7D8` e ver se há um `stb` no cursor.
