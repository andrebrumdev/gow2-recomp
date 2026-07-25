# O que é o `f4` — enum de estado, e uma correcção ao verdicto do 2b2e04

**Data:** 2026-07-25 · **Método:** Ghidra headless sobre o EBOOT (13.143 funções,
13.096 com C decompilado) + disassembly cru do EBOOT. Nada corrido no boot.

## 1. `f4` é o campo em `+0x4`, e é um enum inteiro

Da própria probe (`recomp_mid_v2/patch_type15_cc9d0_disc.py:228`):

```c
f4  = vm_read32(th + 0x4u);      /* 32 bits */
f54 = (uint8_t)...;              /* byte em +0x54 */
```

Portanto **`f4` = offset `+0x4`**, não `0xF4`. `f54` = byte em `+0x54`.

No decompilado, `_opd_FUN_000cc9d0` recebe `float *param_1` (o objecto é quase
todo floats), por isso o Ghidra **imprime o enum como denormais**. A conversão é
directa — `1.4013e-45` é o padrão de bits `0x00000001`:

| decompilado | bits | estado |
|---|---:|---:|
| `1.4013e-45`  | 0x1 | 1 |
| `2.8026e-45`  | 0x2 | 2 |
| `7.00649e-45` | 0x5 | 5 |
| `8.40779e-45` | 0x6 | 6 |
| `9.80909e-45` | 0x7 | 7 |
| `1.12104e-44` | 0x8 | 8 |
| `1.26117e-44` | 0x9 | 9 |

Confirma o que a R12 já dizia em prosa (*"enum f4∈{1,5,6,…}"*), agora com os
valores exactos.

## 2. `CC9D0` é o tick da máquina de estados do `f4`

Transições, todas dentro do bloco gated em `_opd_FUN_000cc9d0` (linhas 121-148
do decompilado):

```
6 -> 1     (chama 2A459C)
5 -> 8
7 -> 2
8 -> 0     (chama 2A466C, copia bloco de 0x18, limpa param_1[0x16])
0 -> nada  <-- nenhum case casa
```

Mais o ramo de saída em `f4 ∉ {0, 9}` e `prod[0xCE] < 1`, que faz `f4 = 0`.

O bloco inteiro está gated por **`f54 == 0`** (`*(char*)(param_1+0x15)`, que é o
byte `+0x54`) e por dois flags derivados de produtos de floats serem 0. E no topo
da função, `f54 != 0` desvia para `FUN_000cc824` e salta tudo.

**Consequência: `f4 = 0` é estado terminal.** Com `f4=0` nenhum case casa, nada
escreve `f4`, e o tick não faz progresso. Não é "campo por escrever" — é uma
máquina de estados parada no estado inicial porque **ninguém a arrancou**.

## 3. Correcção: `CB56C` NÃO toca em `+0x4`

`notes/2026-07-23-2b2e04-typewrites-diagnostic.md:131` afirma, como *"provado, não
só inferido"*, que `func_000CB56C` zera incondicionalmente `this+0x4` **e**
`this+0x54` no prólogo. Metade disso não se confirma.

Disassembly do EBOOT em `0x000CB56C` (r3 = objecto, r31 = cópia de r3):

```
0x000CB5A4  stw   r0, 0x8(r3)      <- +0x8
0x000CB5A8  stw   r0, 0x0(r3)      <- +0x0        (salta o +0x4)
0x000CB5AC..0x000CB5C0  loop x4: stw a +0x0/+0x4/+0x8 de r9, r9 = r3+12,+24,+36,+48
                                 -> cobre +0x0C..+0x38
0x000CB604  stb   r11, 0x54(r31)   <- +0x54 = 0   (f54: CONFIRMA)
```

O decompilado concorda: no corpo inteiro (51 linhas) há `*param_1 = 0` e
`param_1[2] = 0`, e **zero** ocorrências de `param_1[1]`.

Logo:
- **f54**: sim, `CB56C` zera-o de cada vez que corre. O verdicto vale.
- **f4**: não. `CB56C` salta deliberadamente o `+0x4`. O mecanismo
  "escrito uma vez certo, depois apagado por um reset incondicional"
  **não explica o `f4=0`**.

Isto mata a hipótese A do 2b2e04 (*"CB56C deveria preservar +0x4 no caminho de
reuse"*) enquanto explicação do `f4` — não há nada a preservar, ele não é tocado.

## 4. Quem poderia arrancar a máquina

O construtor `_opd_FUN_002a64f4` (chamado por `2A6608`) põe `param_1[1] = 0`, ou
seja `f4` **nasce 0**.

Varrendo os 13.096 corpos decompilados por escritas de `{1,2,5,6,7,8,9}` a um
offset `+4`:

- `CC9D0` escreve 1, 2 e 8 — mas só como transições a partir de 5/6/7.
- **Ninguém escreve 5, 6 ou 7.**
- O único candidato a instalar um estado de arranque é
  **`_opd_FUN_000cd498`** (`+4 = 9`), chamado por **`_opd_FUN_000cd7b4`**.

## 5. Pergunta seguinte, agora com endereço

Não é mais *"quem escreve o f4"* em abstracto. É:

> **`CD7B4 → CD498` chega a correr no boot? Se não, o que o devia ter chamado?**

`f4 = 9` é também o valor que o ramo de reset em `CC9D0` trata como excepção
(`f4 != 9` é condição para limpar), o que é coerente com 9 ser "trabalho
instalado, em curso".

## Ressalvas

- A varredura cobre as formas que o Ghidra emitiu (`[1] =`, `+ 4) =`,
  `+ 0x4) =`). Uma escrita por `memcpy`/cópia de struct não aparece.
- `0x00266130` também escreve 7 e 9 a um `+4`, mas não está provado que seja o
  mesmo tipo de objecto.
- Nada disto foi observado em execução — é análise estática do binário original.
  O passo in-boot é instrumentar `CD7B4`/`CD498`.

---

# Adenda in-boot (2026-07-25): medido, com controlo positivo

Probe `recomp_mid_v2/patch_cd498_enter_probe.py` (gated `PS3_TRACE_CD498=1`,
OFF por omissão). Recipe menu-fast headless, `TIMEOUT=90`, corrida que chegou ao
pós-load: `rperma_full=1`, `thr_auto_load() end`, `bytes_read=20169344 == size`.

```
[CD498] SUMMARY fn=CD7B4       tot=0
[CD498] SUMMARY fn=CD498       tot=0
[CD498] SUMMARY fn=CD9DC       tot=0
[CD498] SUMMARY fn=1D7FCC      tot=0
[CD498] SUMMARY fn=1A9D24      tot=0
[CD498] SUMMARY fn=CC9D0(ctrl) tot=7840456  post=7840456  pre=0
```

**Controlo positivo**: `CC9D0` correu **7.840.456 vezes**, todas depois do
R_PermA, nenhuma antes — e com `r3` a alternar entre `0x4066D798` e
`0x4066D804`, exactamente os dois `this` que as notas de 22-07 documentam. A
instrumentação dispara, conta e lê o registo certo; portanto os cinco zeros
significam mesmo *não são alcançados*.

## Os cinco sítios que sabem instalar um estado de arranque

Varrimento de instruções sobre as 957k palavras do `.text` (`li rX,{5,6,7,9}`
seguido de `stw rX, 0x4(rY)` — independente do que o decompilador rendeu):

| endereço | escreve | função contentora |
|---|---:|---|
| `0x001D8408` | 6 | `func_001D7FCC` |
| `0x001D8414` | 9 | `func_001D7FCC` |
| `0x001D8438` | 7 | `func_001D7FCC` |
| `0x001D845C` | 5 | `func_001D7FCC` |
| `0x001AA124` | 5 | `func_001A9D24` |
| `0x000CD62C` | 9 | `func_000CD498` |

**Nenhum é atingido.**

## Estado do wall, agora preciso

Não é "campo por escrever" nem "campo apagado por um reset" (esse mecanismo foi
refutado para o `+0x4` — ver secção 3). É:

> uma máquina de estados a girar **7,8 milhões de vezes** sobre um estado que
> **ninguém instala**.

O tick é armado pelo load (`pre=0`, `post=7840456`); o *trabalho* é que nunca é
instalado.

## Pergunta seguinte

1. O que deveria chamar `func_001D7FCC`? (é quem detém os quatro estados)
2. Porque está a cadeia `CD9DC → CD7B4 → CD498` inerte — sem chamador estático
   **e** sem uma única referência ao seu OPD (`0x51E028/30/38`) em toda a
   imagem carregada? Vtable construída em runtime, ou código morto neste build?

## Ressalva

Binário compilado com WIP não-committado de outra sessão em `movie_eos_arm.c`
(fonte do `st620`). Não invalida um resultado binário sobre funções guest, mas
é a primeira variável a eliminar se algo aqui for contestado.
