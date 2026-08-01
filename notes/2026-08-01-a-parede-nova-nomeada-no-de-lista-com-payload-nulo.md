# A parede pós-fix, nomeada ao endereço: um nó de lista com payload NULO

**Data:** 2026-08-01 · Tudo abaixo é **MEDIDO**, 3/3 corridas salvo onde se diz o contrário.

## O caminho até aqui, e um erro meu corrigido por medição

Depois de o fix do `F2B-STREAM-PUMP` parar de destruir os objectos de tipo, o boot passou
a abortar sempre em:

```
[ppu] FATAL: stuck calling 0x00514E80 (2000 times) -- aborting run
```

O `lr=0x0024E2D4` apontava para o walker `func_0024D5BC`. **Mentiu.** O lift só escreve
`ctx->lr` antes dos `bl`; num `bctrl` fica preso no último salto directo. Duas medições
desfizeram a atribuição errada:

1. A sonda `PS3_TRACE_D5BC` mostrou o walker **saudável** — 758 nós, todos com vtable,
   OPD e código válidos (`vt=0x00517B48 opd=0x00530920 code=0x002CEC34`), 3/3 corridas.
2. Simbolizando o `ICALL-BAD` e o rbp frame walk com `dladdr` (ps3recomp `338706e`), a
   cadeia real apareceu de uma vez:

```
ppu_run → func_00010354 → func_0025C838 → func_002B2E74 → func_000B71B8
        → func_0010F5E8 → func_0024F028 → func_0024E270      (walker de registos do WAD)
        → icall → func_0039D428 → icall → func_0039D764      (fábrica de tipos)
        → icall → func_002545D4+0x5AC                        ← o sítio real
```

**Esse `dladdr` é agora permanente** — qualquer `ICALL-BAD` futuro nomeia a cadeia
inteira em vez de dar ponteiros host inúteis entre corridas.

## O defeito, lido e depois confirmado

`func_002545D4` percorre uma lista circular (sentinela em `r28-4+0x80`) e, por nó:

```c
loc_00254628:
    r10 = *(no + 0x8);        // payload
    r31 = *(no + 0x0);        // next
    r11 = 0;
    if (r10 == 0) goto usa;   // <- r11 FICA A ZERO e despacha na mesma
    r11 = r10 + 4;            // registo = payload + 4
usa:
    r4  = r11;
    tipo = *(uint16*)(r11 + 2);
    idx  = (tipo << 2) & 0x3FFFC;
    obj  = *(r29 + idx);      // tab[idx], r29 = *(TOC-0x225C)
    vt   = *(obj + 0);
    opd  = *(vt + 0x18);
    ctr  = *(opd); bctrl
```

A sonda `PS3_TRACE_TYPESLOT` mediu, **idêntico em 4/4 corridas**:

```
[TYPESLOT] NULO idx=0x25F7C tipo=0x97DF tab=0x00868D48 slot=0x00000000 rec=0x00000000
```

- **`rec=0x00000000`** — o payload do nó é nulo, exactamente como o código estático
  sugeria. Não é um tipo mal lido de um registo válido: **não há registo.**
- `tipo=0x97DF` é então `*(uint16*)(0x2)` — memória da base do espaço guest lida como se
  fosse um campo de tipo. Daí ser idêntico em todas as corridas.
- `idx = 0x25F7C` cai muito fora da tabela (os índices válidos observados vão até `0x6C`),
  `tab[idx]` lê 0, e o despacho segue por ponteiro nulo → `ctr = 0x00514E80`.

Os tipos válidos observados no mesmo boot são todos `< 0x40`: `0x03, 0x05, 0x0F, 0x11,
0x15, 0x16, 0x19, 0x20`.

## O pump não é o culpado disto — discriminado

Como o fix passou o pump a escrever **dentro** do ring real do guest (antes escrevia numa
janela hard-coded que nem era a do guest), era preciso excluir que fosse eu a desalinhar o
stream. O `PS3_F2B_PUMP_BYTES` foi acrescentado só para isso, e a matriz é limpa:

| `PS3_F2B_PUMP_BYTES` | `R_PermA` completo | `TYPESLOT` NULO | `FATAL` |
|---|---:|---:|---:|
| `0` (3 corridas) | **0** | 0 | 0 |
| `262144` (3 corridas) | **1** | 40 | 1 |

Com o pump a escrever zero, o WAD de 20 MB **nunca chega a ser lido inteiro** — logo o
pré-enchimento de um ring é o que segura a leitura, e o despacho nulo só aparece no
caminho que corre **depois** disso. O pump habilita o código que bate na parede; não a
cria.

(O gate cego `PS3_FIOS_STREAM_PUMP=0` não servia para isto: desliga o bloco inteiro,
levando atrás o rebind de limit/cursor e o arranque do `f2b_stream_fill` — medido:
`st620` 11→3, `StartSeq` 2→0, `R_PermA` 1→0, filme 0.)

## O que fica por decidir, e é a próxima medição

Duas leituras possíveis, e **nenhuma está provada**:

1. **A lista tem um nó com payload nulo** — dados montados a partir do WAD com um campo
   por preencher. Nesse caso a correcção é a montante, onde o nó é criado.
2. **O ramo está mal liftado** — no PPC original o `beq` saltaria para *continuar o laço*
   (`loc_00254628`) e não para o corpo que usa `r11`. Num PS3 real, desreferenciar `r11=0`
   faria fault na página nula, portanto o jogo nunca pode ter tomado este caminho com
   payload nulo. Isso torna a hipótese do lift **plausível e barata de verificar**.

A verificação é directa: desmontar o PPC original em torno de `0x00254628`–`0x00254644` no
`EBOOT.ELF` e comparar o alvo do `beq` com o que o lift gerou. Se o alvo real for
`loc_00254628`, é um bug do lifter da mesma família do `fallthrough cross-fragment` de
`func_002550C8` — e vira `patch_*.py` idempotente, como esse.

## O estado do objectivo, sem rodeios

**O menu continua por alcançar.** O gate oficial dá 0/6, elo `AUTO_LOAD (thr_end)`. Os
cinco elos anteriores passam em 6/6 e o `setflip_after_rperm` estabilizou em 8–10 (a Fase
7 tinha registado 0 mesmo no binário de referência). A parede está agora nomeada ao
endereço e à instrução, o que não acontecia esta manhã.
