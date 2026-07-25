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

---

# Adenda 2: as classes do instalador nunca são construídas

18 sítios, mesmo binário, mesma corrida (pós-load: `rperma_full=1`, R_PermA
completo).

```
CD7B4 CD498 CD9DC 1D7FCC 1A9D24 ............................ tot=0
C96014 C96FF0 C9DCF4 C9FBE0 CA3AB0 CA3B68 ................... tot=0
CAD870 CADA28 CADBD4 CCAE1C CCAE90 CDAFB4 ................... tot=0
CC9D0 (controlo) ............................ tot=7737370  post=7737370  pre=0
```

## Como se chegou aos 12 construtores

`1D7FCC` e `1A9D24` não têm chamador estático — mas, ao contrário do `CD9DC`,
**têm o OPD referenciado**: em `0x513F48` e `0x513528`. A zona repete o padrão
`00 FFFFFFFFF 000 FFFFFFFFF 00` — vtables Itanium com RTTI removido
(offset-to-top e typeinfo a zero) e 9 métodos virtuais cada. Nas duas, o nosso é
o **slot 2** (`+8`): são o mesmo método virtual de duas classes irmãs.

Procurar quem despacha o slot `+8` dá 538 sítios — inútil. Inverteu-se a
pergunta: cada vptr (`0x513F40`, `0x513520`) é referenciado **uma vez**, em
entradas de TOC (`TOC-13600` e `TOC-13380`, `TOC=0x541178` lido do OPD). Doze
sítios do `.text` carregam essas entradas, todos à entrada da função — padrão de
construtor. **Nenhum dos doze corre.**

## O lead era válido: o layout confere

`0x001D83B4  lwz r3, 0x8(r25)` e `0x001D840C  stw r0, 0x4(r25)`.

Isso é exactamente a forma do objecto TYPE15 que a probe do `CC9D0` lê:
`f4 = vm_read32(th+0x4)`, `prod = vm_read32(th+0x8)`. Somado a escrever
precisamente os estados de arranque `{5,6,7,9}` que o tick consome, o caso é
forte — ainda que não seja prova de identidade de tipo.

## Conclusão

O enquadramento muda outra vez, e para mais fundo:

> Não é "um campo não é escrito". É **um subsistema inteiro que nunca é
> instanciado**. As duas classes que detêm o método instalador de estado nunca
> têm um construtor executado neste boot, enquanto o tick que consumiria esse
> estado gira 7,7 milhões de vezes.

## O que isto exclui, e o que reabre

Exclui: qualquer explicação do `f4=0` baseada em "quem escreve foi apagado" ou
"o escritor corre mas falha" — os seis únicos sítios do binário capazes de
escrever um estado de arranque nunca são atingidos, e as classes que os detêm
nunca existem.

Reabre a hipótese que a nota de 22-07 já tinha levantado e que ficou por
testar (`2026-07-22-type15-cb56c-attach-diagnostic.md:105`):

> *"`f4=0` may be the correct idle value for an object waiting on that"*

Se o objecto vivo em `0x4066D798` é de uma classe **diferente** daquelas duas, o
`f4=0` pode ser legítimo e o wall não está aqui — está em quem devia ter criado
os objectos das classes instaladoras.

## Próximo discriminador proposto

Ler o vptr do objecto vivo (`vm_read32(0x4066D798)`) durante o boot e compará-lo
com `0x513F40` / `0x513520`. Uma leitura, resposta binária:

- **igual** → é a mesma classe, e a pergunta é porque não passou pelo construtor
  instrumentado (construção por outro caminho? placement? cópia?);
- **diferente** → o `f4` daquele objecto não é o mesmo campo semântico, o lead
  inteiro cai, e o wall está noutro sítio.

---

# Adenda 3: o discriminador refuta o meu próprio lead

```
[CD498] VPTR obj=0x4066D798 vptr=0x00000000  DIFERENTE das duas
[CD498] VPTR obj=0x4066D804 vptr=0x00000000  DIFERENTE das duas   (x3 cada)
[CD498] SUMMARY fn=CC9D0(ctrl) tot=7620252 post=7620252 pre=0
```

`vptr = 0` não é "outra classe". É **nenhuma vtable** — e a premissa da comparação
estava errada. O `+0x0` deste objecto não é um ponteiro:

```c
_opd_FUN_000cc9d0:  if (*param_1 == 1.4013e-45)      /* +0x0 == 1 */
                    if (*param_1 != 2.8026e-45)      /* +0x0 == 2 */
_opd_FUN_000cb56c:  *param_1 = 0;                    /* zera +0x0 */
```

É **outro enum pequeno** ∈ {0,1,2}, adjacente ao `f4`. O objecto vivo é uma
struct simples, não um objecto polimórfico.

## Consequência: o lead `1D7FCC` está morto

`1D7FCC`/`1A9D24` só são alcançáveis pelo slot 2 de vtables de classes
polimórficas. O objecto que o `CC9D0` tica não tem vtable, logo **não pode ser
instância dessas classes**. A coincidência de layout que me convenceu
(`stw ...,0x4(r25)` + `lwz ...,0x8(r25)`) era mesmo coincidência: dois enums
adjacentes seguidos de um ponteiro é um shape comum.

Confirmação independente: os 12 construtores dessas classes dão `tot=0` — nunca
são instanciadas de todo. Coerente, e agora explicado.

## O que sobra provado, depois de três rondas

1. `f4` = campo em `+0x4`, enum ∈ {0,1,2,5,6,7,8,9}; `f54` = byte em `+0x54`.
2. `CC9D0` é o tick; `f4=0` é estado terminal; gira ~7,6-7,8M vezes pós-load,
   zero antes.
3. `CB56C` zera `+0x54` mas **não** toca `+0x4` (corrige o verdicto do 2b2e04).
4. Nenhum dos 6 sítios que escrevem um literal `{5,6,7,9}` a um `+0x4` é
   alcançado — e nenhum pertence a este tipo de objecto.
5. O objecto vivo não é polimórfico (`+0x0` é enum, não vptr).

## Porque é que o varrimento não encontrou o escritor certo

O varrimento procurou `li rX,{5,6,7,9}` seguido de `stw rX, 0x4(rY)`. Não
apanha: valor vindo de outro registo/campo, offset calculado, `stmw`, `memcpy`
de um template, ou escrita pelo host (HLE/patch). O escritor legítimo do `f4`
deste objecto pode estar em qualquer dessas formas — ou não existir, e `f4=0`
ser o idle correcto, como a nota de 22-07 suspeitava.

## Próximo experimento: watchpoint de escrita, não mais busca estática

Parar de procurar o escritor no binário e **apanhá-lo em flagrante**. O runtime
já tem o gancho: `ps3_type15_block_stomp()` é chamado de dentro do `vm_write32`
(`runtime/ppu/ppu_loader.cpp:1114-1116`). Um watchpoint gated no mesmo sítio,
a vigiar `0x4066D79C` (= `this+0x4`) e `0x4066D808`, responde de vez:

- **alguém escreve** → temos o culpado, com o valor e o momento;
- **ninguém escreve em 7,6M ticks** → o `f4` nunca é tocado depois da
  construção, e a pergunta passa a ser se isso é o comportamento correcto
  (hipótese de 22-07) ou se falta um subsistema inteiro a montante.

Nota: os endereços `0x4066D798`/`0x4066D804` repetiram-se em todas as corridas
desta sessão e nas notas de 22-07 e 23-07, portanto são estáveis o suficiente
para servirem de alvo; mesmo assim o watchpoint deve aceitar o endereço por env
var em vez de o fixar.
