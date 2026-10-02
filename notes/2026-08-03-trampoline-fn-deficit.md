# O défice de `g_trampoline_fn` (−318): regressão do lift ou baseline obsoleto?

**Data:** 2026-08-03 · **Máquina:** Apple Silicon (macOS/arm64) · **Repo motor:** `ps3recomp` @ `42d1e3d`
**Natureza desta sessão:** **só leitura e análise.** Zero builds, zero boots, zero lifts gerados.
O baseline **não foi tocado** — a entrega é a prova; a execução é decisão do utilizador.
**Artefactos lidos** (não versionados): `../gow2-recomp/recomp_macos_{v2,v3,v3_midasm,v3_jt18,v3_ovr19,v3_mig19,v3_mig19b,v3_mig19c,v3_e2e,v4ord}`

---

## Veredicto directo

> ## BASELINE OBSOLETO. Não é regressão.
>
> O `MANIFEST.tsv` congelou `g_trampoline_fn >= 168753` a **2026-07-26 04:37** (`dd7170a`),
> contra um lift carimbado **`lifter-rev 0852305`** (2026-07-26). A **2026-07-30 12:39** o
> commit **`0585636`** corrigiu um bug de descoberta de jump tables — *"o registo-base é o que
> VALIDA ALVOS, não o primeiro que decodifica"* — cuja própria mensagem mede
> **`funcoes emitidas 51917 -> 51991`**. O baseline defende um número produzido por um lifter
> que **já não existe**, e que tinha um defeito **documentado, corrigido e testado**.
>
> **O `+74 funções` e o `−318 trampolins` são o mesmo fenómeno visto de dois ângulos** — e o
> ângulo certo é o do commit: o lift fresco resolve **22 dispatchers de switch a mais**, com
> **204 alvos a mais**, e **não perde um único** dos 125 que a produção já resolvia.

Decomposição exacta, medida em 5 lifts distintos, sem "aproximadamente":

| Origem | Δ `g_trampoline_fn` |
|---|---:|
| **`0585636`** — fix da jump table (2026-07-30) | **−317** |
| **Fase 17** — `patch_ce03c_introseq_block` migrado para `[[midasm_hook]]` (`func_000CE03C` 3→1) | **−2** |
| **Fase 19** — weak override de `func_002C0498` (0→1) | **+1** |
| **TOTAL** | **−318** |

**Duas das três parcelas são marcos que este projecto entregou de propósito.** A terceira é uma
correcção de correctness do lifter que a produção nunca recebeu.

---

## 1. Sonda de controlo — antes de acreditar em qualquer coisa

Regra da casa: reproduzir um número conhecido antes de confiar no instrumento. Três sondas,
todas verdes, **antes** de qualquer conclusão.

**Sonda 1 — contagem crua reproduz os dois números do relatório de ontem:**

```
recomp_macos_v2     TOTAL=168753     <- produção
recomp_macos_v4ord  TOTAL=168435     <- candidato fresco
```

**Sonda 2 — o inventário por função soma exactamente o mesmo** (é a ferramenta desta análise;
se somasse outra coisa, tudo o que vem a seguir era lixo):

```
recomp_macos_v2:    funcs=51924  total_tramp=168753
recomp_macos_v4ord: funcs=52002  total_tramp=168435
```

(51924 = 51917 funções + 7 preâmbulos; 52002 = 51991 + 7 preâmbulos + 4 wrappers fracos.)

**Sonda 3 — o gate REAL, corrido nos dois lifts, diz exactamente o que ontem disse:**

```
$ gen_manifest.py ../gow2-recomp/recomp_macos_v4ord --verify .../MANIFEST.tsv
A MENOS  PREAMBLE g_trampoline_fn  (esperado >=168753, encontrado 168435)
A MENOS  SYM    ps3_mp_on_enter    (esperado >=17,     encontrado 16)

$ gen_manifest.py ../gow2-recomp/recomp_macos_v2 --verify .../MANIFEST.tsv
(nenhum achado)
```

A segunda linha é a confirmação da tese pelo lado de trás: **o baseline é satisfeito, byte a
byte, por um único artefacto — `recomp_macos_v2`.** Contra qualquer outra coisa acusa.

---

## 2. O que o número conta (verificado em `tools/ppu_lifter.py`, não assumido)

`g_trampoline_fn` é o ponteiro TLS de trampolim para saltos cross-fragment
(`tools/ppu_lifter.py:405-428`, o preâmbulo `SOURCE_PREAMBLE`). O lifter emite-o em quatro
sítios, todos com `return` a seguir:

| Sítio no lifter | Quando |
|---|---|
| `ppu_lifter.py:1737` | `b` para o prólogo de uma função **dentro** do range fundido — tail call |
| `ppu_lifter.py:1749` | `b` cross-fragment (fora do range da função) |
| `ppu_lifter.py:1816` / `:1829` | as mesmas duas, na forma **condicional** |
| `ppu_lifter.py:3654` | fallthrough no fim da função para a continuação registada |

O marcador do `MANIFEST` é de tipo `PREAMBLE`, e o `gen_manifest.py:285-292` diz o que ele
existe para verificar:

> *"confirma que o preambulo puro (nao-injectado) **SOBREVIVE** no chunk alvo (…) conta contra
> o `text` do ficheiro **INTEIRO** (…) porque o objectivo aqui nao e' detectar injeccao, e'
> confirmar **sobrevivencia**."*

**E aí está a raiz de tudo.** O propósito declarado é *sobrevivência do preâmbulo*; a
implementação conta o **ficheiro inteiro**. Medido:

| | ocorrências **no preâmbulo** | ocorrências **no corpo** | total |
|---|---:|---:|---:|
| `recomp_macos_v2` (produção) | **56** | 168 697 | 168 753 |
| `recomp_macos_v4ord` (fresco) | **56** | 168 379 | 168 435 |

**A sobrevivência do preâmbulo é 56 = 56, idêntica.** 99,97 % do limiar de 168 753 não mede
sobrevivência nenhuma: mede **quantos saltos cross-fragment o lifter decidiu emitir como
trampolim** — uma métrica da **forma** do lifter. Qualquer melhoria de fronteiras mexe-lhe.

Prova de que é forma e não perda: os trampolins que desaparecem reaparecem como saltos directos.

```
                    goto loc_XXXX;   g_trampoline_fn = func_XXXX
recomp_macos_v2        185 601            168 696
recomp_macos_v4ord     185 726  (+125)    168 379  (−317)
```

O marcador irmão, na mesma família `PREAMBLE`, move-se no **sentido oposto** pela mesma razão —
e ninguém lhe chamou regressão: `ps3_indirect_call` 15 759 → **15 913 (+154)**, que é o grupo
`opd-dispatch` cujo défice de 36 unidades "resolveu" na corrida de ontem.

---

## 3. A decomposição por chunk — e porque é a pergunta errada

| chunk | produção | fresco | Δ |
|---|---:|---:|---:|
| `ppu_recomp_000.cpp` | 15 544 | 15 562 | **+18** |
| `ppu_recomp_001.cpp` | 21 259 | 21 294 | **+35** |
| `ppu_recomp_002.cpp` | 29 988 | 29 748 | **−240** |
| `ppu_recomp_003.cpp` | 27 604 | 27 688 | **+84** |
| `ppu_recomp_004.cpp` | 23 264 | 23 391 | **+127** |
| `ppu_recomp_005.cpp` | 34 424 | 33 945 | **−479** |
| `ppu_recomp_006.cpp` | 16 670 | 16 807 | **+137** |
| **soma** | **168 753** | **168 435** | **−318** |

Confirma-se o que a pergunta desta sessão dizia: 5 chunks com mais, 2 com menos, e o total
negativo. **Mas este quadro não explica nada** — o chunking é por volume de saída e o lift
fresco tem **+74 funções**, portanto a atribuição função→chunk **mudou**. `func_0013AB9C` está
no chunk 003 na produção e no chunk **002** no lift fresco. Comparar chunks é comparar
recipientes, não conteúdo. **A decomposição válida é por função.**

---

## 4. A decomposição por função — três baldes que fecham a soma

| Balde | funções | Δ trampolins |
|---|---:|---:|
| Existem **só na produção** (desapareceram) | 29 | **−62** |
| Existem **só no lift fresco** (apareceram) | 103 (+4 wrappers fracos) | **+378** |
| Existem **nos dois**, com contagem diferente | 78 | **−634** |
| Existem nos dois, contagem **idêntica** | 51 817 | 0 |
| **TOTAL** | | **−318** |

E o `+74` fecha no mesmo sítio: **103 − 29 = 74**. **É literalmente a mesma população.** A
pergunta desta sessão perguntava se o `+74 funções` e o `−318 trampolins` eram a mesma família:
**são a mesma linha do mesmo `diff`.**

**O mecanismo, medido numa função concreta.** `func_0013AB9C` é o caso extremo (−55):

| | linhas de corpo | trampolins |
|---|---:|---:|
| produção | **1 098** | **56** |
| fresco | **13** | **1** |

As primeiras 11 linhas são **idênticas** nos dois — e a 11.ª é
`{ g_trampoline_fn = ...func_0013A888; return; }`, um terminador. **Na produção seguem-se mais
1 087 linhas depois de um `return` incondicional.** Não é código a mais: é a *cauda* que o
passe mid-function liftou de `target` até ao fim do **contentor**, e na produção o contentor
ia até 0x0013BA58+ porque o dispatcher daquela região **nunca foi descoberto**. Cada uma das
dezenas de entradas mid-function daquele bloco reemitia a mesma cauda gigante — e cada cópia
trazia os seus trampolins.

A correlação é quase perfeita nas 78 funções do 3.º balde:

- as **55 com Δ negativo**: 17 780 → 6 057 linhas de corpo
- as **23 com Δ positivo**: 1 919 → 7 340 linhas de corpo

**O trampolim segue a linha; a linha segue a fronteira; a fronteira segue o dispatcher.**

Prova directa da duplicação, num cluster inteiro — o **mesmo** dispatcher (`00382FD4..00382FF4`),
alvo a alvo idêntico:

| | quantas vezes é emitido | em que funções |
|---|---:|---|
| produção | **9×** | `0038297C`, `00382B0C`, `00382B20`, `00382C04`, `00382C80`, `00382CB0`, `00382D4C`, `00382C7C`, `00382D1C` |
| fresco | **3×** | `0038297C`, `00382B0C`, `00382B20` |

O dispatcher de 10 braços da mesma região (`00382AFC..00382F5C`) está **idêntico** nos dois.
Nada se perdeu: seis cópias redundantes deixaram de existir.

---

## 5. A proveniência do baseline — a prova decisiva

O lift carrega carimbo de proveniência (`ppu_lifter.py:120-135,3446`, introduzido em `bc3707d`
precisamente para apanhar lifts velhos). Lido nos artefactos:

| Lift | `lifter-rev` | data do rev | funções | `g_trampoline_fn` |
|---|---|---|---:|---:|
| **`recomp_macos_v2` (PRODUÇÃO)** | **`0852305`** | **2026-07-26** | 51 917 | **168 753** |
| `recomp_macos_v3` (o lift de referência do baseline) | `0852305` | 2026-07-26 | 51 917 | **168 753** |
| `recomp_macos_v3_midasm` | `ab9e99c` | 2026-08-02 | 51 991 | 168 434 |
| `recomp_macos_v3_jt18` | — | 2026-08-02 | 51 991 | 168 434 |
| `recomp_macos_v3_ovr19` | — | 2026-08-02 | 51 991 | 168 434 |
| `recomp_macos_v3_mig19` / `_mig19b` | — | 2026-08-02 | 51 991 | 168 434 |
| `recomp_macos_v3_mig19c` | — | 2026-08-02 | 51 991 | **168 435** |
| `recomp_macos_v3_e2e` | — | 2026-08-02 | 51 991 | **168 435** |
| `recomp_macos_v4ord` | `113fda2` | 2026-08-03 | 51 991 | **168 435** |

**Cronologia, sem interpretação:**

| Data | Evento |
|---|---|
| 2026-07-26 | lift de produção gerado — `lifter-rev 0852305` |
| **2026-07-26 04:37** | **`dd7170a` congela `g_trampoline_fn PREAMBLE 168753`** no `MANIFEST.tsv` |
| 2026-07-26 16:56 | `91646a9` — *"MANIFEST.tsv reformulado (…) contra `recomp_macos_v3`"* (o mesmo rev) |
| **2026-07-30 12:39** | **`0585636` — fix da jump table.** Nunca chegou a nenhum lift de produção |
| 2026-08-02 17:23 → 2026-08-03 | Fases 17/18/19/20; todos os lifts pós-fix dão 51 991 / 168 43x |

O `MANIFEST.tsv` **nunca foi regenerado** depois de 2026-07-29 (`0e49c92`, e essa recalibração
tocou só o grupo `opd-dispatch`). **A linha 217 é de 26 de Julho e o lifter mudou a 30.**

---

## 6. A causa, número a número

O commit `0585636` mediu-se a si próprio contra o **mesmo EBOOT**:

```
                      antes    depois   delta
  dispatchers           137       157     +20
  case targets         1537      1745    +208
  kept internal        1299      1436    +137
  case funcs            237       309     +72
  funcoes emitidas    51917     51991     +74      <-- EXACTAMENTE o delta medido
```

**Reproduzido hoje, nos artefactos, sem correr nada:** `function_table_count` **51 917** na
produção e **51 991** em todos os lifts pós-fix. Coincidência exacta com a medição do commit.

E a assinatura do fix vista no código emitido — conjuntos de `case` distintos por dispatcher:

| | conjuntos distintos | emissões |
|---|---:|---:|
| produção | 125 | 219 |
| fresco | **147** | 249 |

- **conjuntos só na produção (dispatchers PERDIDOS): `0`.**
- conjuntos só no fresco (dispatchers **recuperados**): **22**, com **204 alvos**.

Ou seja: **o lift fresco é um superconjunto estrito da resolução de switches da produção.**
(22 / 204 contra os +20 / +208 do commit — a diferença são 3 variantes do mesmo dispatcher
`000EA…` entradas em offsets diferentes, contadas como conjuntos distintos na vista emitida.)

### Localização: quanto do défice cai onde um dispatcher foi recuperado

As 210 funções afectadas (29 + 103 + 78) agrupam-se em **20 clusters** de endereço. Δ por
cluster, e se a região ganhou algum dos 22 dispatchers novos:

| cluster | funcs | Δ | dispatcher novo? |
|---|---:|---:|---|
| `00014F34–00015230` | 4 | −9 | **SIM** (`00015060`, 7 alvos) |
| `0001C418–0001C980` | 11 | −26 | **SIM** (`0001C5F0`, 6 alvos) |
| `00030828` | 1 | −1 | não |
| `00032A78–00032B18` | 4 | 0 | não |
| `00044978–00044A2C` | 2 | −2 | **SIM** (`000449CC`, 9 alvos) |
| `000738C8–0007390C` | 2 | −2 | **SIM** (`00073CAC`, 4 alvos) |
| `000B9298–000B9504` | 22 | +3 | **SIM** (`000B9298`) |
| `000CE03C` | 1 | **−2** | **Fase 17** (mecanismo declarado) |
| `000E3D14–000E3E94` | 9 | 0 | **SIM** (`000E3D14`) |
| `000E6DAC` | 1 | −3 | **SIM** (`000E714C`, 4 alvos) |
| `001007D8–00100A8C` | 12 | −25 | **SIM** (`00100848`, 5 alvos) |
| `00106380–001067E8` | 10 | +64 | **SIM** (`00106A58`, 4 alvos) |
| **`0013A890–0013BB88`** | **59** | **−322** | **SIM** (`0013A890`) |
| `0026ECC0–0026F8AC` | 10 | −27 | não |
| `002C0498` | 1 | **+1** | **Fase 19** (mecanismo declarado) |
| `00311F1C` | 1 | −1 | não |
| `0035EDB0–0035F704` | 29 | +60 | **SIM** (`0035EE3C` e `00360188`) |
| `00369478–00369C70` | 9 | +22 | não |
| `0037EA3C` | 1 | −16 | não |
| `00382C04–003831DC` | 21 | −32 | não — **duplicação removida** (§4) |
| **TOTAL** | **210** | **−318** | |

```
  −262   em clusters COM dispatcher recuperado
  −  1   nos dois clusters de mecanismo declarado (Fase 17 −2, Fase 19 +1)
  −  55   em 6 clusters SEM dispatcher recuperado
------
  −318
```

**Os −55 não estão localizados a um dispatcher, e diz-se assim.** Nesses 6 clusters os
conjuntos de `case` são **idênticos** nos dois lifts — o único que muda é o `00382C04`, e aí a
mudança é o **número de cópias** do mesmo dispatcher (9× → 3×, §4), não o dispatcher. Nos
outros cinco a mudança é de **extensão de span**: `func_0037EA3C`, por exemplo, passa de 251
para 5 linhas com os arranques vizinhos **exactamente iguais** (`0037EA24 / 0037EA3C / 0037EA40
/ 0037EA50 …` nos dois lifts) — é a cauda mid-function que encurtou, não a fronteira que se
moveu.

**Atribuição do resíduo, por exclusão — e é uma exclusão fechada, não uma suposição:**

1. Todas as funções residuais já têm o valor **final** no **primeiro** lift pós-fix
   (`recomp_macos_v3_midasm`) — não há passo intermédio onde alguma delas se mova:

   | | prod | `v3_midasm` | `v4ord` |
   |---|---:|---:|---:|
   | `func_0037EA3C` | 18 | **2** | 2 |
   | `func_00382C7C` | 16 | **1** | 1 |
   | `func_0026ECC0` | 13 | **10** | 10 |
   | `func_00369478` | 1 | **11** | 11 |
   | `func_00030828` | 7 | **6** | 6 |
   | `func_00311F1C` | 1 | **0** | 0 |

2. Nessa janela (`0852305..ab9e99c`) existem **exactamente dois** commits a tocar
   `tools/ppu_lifter.py`:

   ```
   a800471 2026-08-02 17:23 feat(17-01): ppu_lifter emite [[midasm_hook]] atras de --config
   0585636 2026-07-30 12:39 fix(lifter): o registo-base da jump table (…)
   ```

3. O `a800471` está confinado a **um EA** (`func_000CE03C`), com teste-ouro a exigir output
   byte-a-byte idêntico sem `--config`.

**Logo não há terceiro candidato: o resíduo é do `0585636`.** O que fica por provar não é a
autoria — é o *caminho* interno pelo qual +72 `case funcs` novas alteram o cálculo de cauda em
regiões cujo dispatcher não mudou. **Isso não foi rastreado no código do lifter.**

### A aritmética final, parcela a parcela

O salto acontece **de uma vez** entre o último lift pré-fix e o primeiro pós-fix, e as duas
correcções por mecanismo isolam-se por função:

| | `func_000CE03C` | `func_002C0498` | TOTAL |
|---|---:|---:|---:|
| `recomp_macos_v2` (pré-fix) | 3 | 0 | **168 753** |
| `recomp_macos_v3_midasm` (1.º pós-fix) | **1** | 0 | **168 434** |
| `recomp_macos_v3_mig19b` | 1 | 0 | 168 434 |
| `recomp_macos_v3_mig19c` (weak wrappers ON) | 1 | **1** | **168 435** |
| `recomp_macos_v4ord` | 1 | 1 | **168 435** |

```
168753                                       produção (lifter-rev 0852305)
  −317   fix da jump table 0585636
  −  2   Fase 17: func_000CE03C  3 -> 1
------
168434   v3_midasm / v3_jt18 / v3_ovr19 / v3_mig19 / v3_mig19b
  +  1   Fase 19: func_002C0498  0 -> 1  (weak override)
------
168435   v3_mig19c / v3_e2e / v4ord                              soma = −318  ✔
```

Os `−2` do `func_000CE03C` são as 116 linhas do `patch_ce03c_introseq_block.py` a saírem do
lift: **−1** do `g_trampoline_fn = 0;` do pad de `setjmp/longjmp` injectado, **−1** de um
trampolim de cauda para `func_000CE0A0`. Confirmado à parte pela contagem de ocorrências que
**não** são atribuições a uma função: 57 na produção → 56 no fresco.

O `+1` do `func_002C0498` é o par forte/fraco da Fase 19 — a mesma função cujo
`CALL_MISMATCH` o `lift_parity` reportou como **RESOLVIDO** na corrida de ontem.

---

## 7. Duas hipóteses refutadas com números

A pergunta desta sessão pedia para testar primeiro as **switch tables declaradas** (Fase 18) e
os **weak wrappers** (Fase 19). Ambas se medem, e ambas caem.

**Switch tables declaradas — contribuição: ZERO.** O `gow2_switch_tables.toml` declara 2
tabelas (`dispatch = 0x002A2130` e `0x002B1224`), 76 alvos ao todo (54 + 22 — o número da
hipótese está certo). Braços emitidos nessas regiões:

| | `case 0x002A2…` | `case 0x002B1…` |
|---|---:|---:|
| produção | 119 | 21 |
| fresco | **119** | **21** |

**Idênticos.** É o que o próprio ficheiro de config já documentava, e que agora está medido no
código emitido: as 143 tabelas `high` do `ps3_analyse.py` são alvo-a-alvo iguais às da
descoberta automática, logo declarar duas delas é, hoje, um **no-op**. A intuição — *"uma
`switch` real substitui um trampolim por `goto` directo"* — está **certa no mecanismo e errada
no agente**: quem recuperou dispatchers não foi a declaração da Fase 18, foi a **descoberta**
corrigida a 30 de Julho.

**Weak wrappers — contribuição: +1, e é de sinal contrário ao défice.** Dos 4 pares
forte/fraco emitidos, só `func_002C0498` mexe na contagem, e mexe para **cima**. Os 4 wrappers
`PPC_FUNC(func_…)` têm 0 trampolins cada.

---

## 8. Nada ficou órfão — o teste que faz o rebaseline ser legítimo

Um rebaseline sem esta secção seria tapar o problema. Três verificações independentes:

**(a) As 29 funções que desapareceram continuam com o código emitido, e ninguém as chama.**
Cada um dos 29 endereços é **interior** a uma função do lift fresco — nenhum ficou num buraco:

```
0x00015064, 0x000150A4, 0x00015230        -> dentro de func_00014F34 (próxima fresca: 0x00015278)
0x0001C5F0 … 0x0001C980  (10 endereços)   -> dentro de func_0001C418 (próxima fresca: 0x0001C9A0)
0x00044A2C                                -> dentro de func_000449A8
0x000738C8                                -> dentro de func_000738B4
0x00100870 … 0x00100A8C  (11 endereços)   -> dentro de func_001007D8
0x0013A9E8                                -> dentro de func_0013A9BC
0x0035EFEC, 0x0035F07C                    -> dentro de func_0035EFDC
```

E o teste de referência pendente: **`func_<addr>` das 29 aparece 0 (zero) vezes no lift
fresco.** Nenhuma referência dangling — consistente com o `0 fallback stubs (every referenced
target is defined)` que o próprio lifter imprimiu.

**(b) As 103 funções novas não são invenção: são alvos de `case` promovidos.** Cada um dos 103
endereços é **interior** a uma função da produção — código que já lá estava, agora com entrada
própria. É o `case funcs 237 → 309 (+72)` do commit.

**(c) Cobertura global: o lift fresco emite MAIS, não menos.**

| | produção | fresco | Δ |
|---|---:|---:|---:|
| funções na `function_table` | 51 917 | 51 991 | **+74** |
| linhas em corpos de função | 4 040 733 | 4 046 419 | **+5 686** |
| labels `loc_` distintos (endereços guest cobertos) | 47 473 | 47 656 | **+183** |
| conjuntos de `case` distintos | 125 | 147 | **+22** |
| conjuntos de `case` **perdidos** | — | — | **0** |

---

## 9. Um achado de bónus: o `FATAL` que a corrida de ontem deixou "indeterminado"

Ontem o critério 3 ficou vermelho em parte porque o candidato tinha
`FATAL: stuck calling 0x00514E80` e a produção `stuck calling 0x000B9354` — endereços
diferentes, e escreveu-se *"FALHA/indeterminado"*. Medido agora:

| | define `func_000B9354`? | define `func_00514E80`? |
|---|---|---|
| produção | **NÃO** | não |
| lift fresco | **SIM** | não |

`0x000B9354` está na lista dos **103 endereços que o fix da jump table promoveu a função**
(cluster `000B9298–000B9504`, dispatcher `000B9298` recuperado). **A produção fica presa a
chamar um endereço que o próprio lift não define — e o lift fresco define-o.** O `FATAL` da
produção é uma consequência directa do bug de 26 de Julho.

O `0x00514E80` do candidato não é definido por **nenhum** dos dois lifts: é o **próximo** alvo
indirecto por resolver, que a produção nunca chegou a alcançar porque morria antes. Não é
regressão — é o poste seguinte, agora visível. **Não foi investigado aqui.**

---

## 10. Porque isto volta a acontecer se o rebaseline for só "bumpar o número"

`168753 → 168435` re-arma exactamente a mesma armadilha: o próximo fix de fronteiras do lifter
volta a mover o número e o gate volta a acusar uma melhoria como perda. O defeito não é o valor,
é o **contrato do marcador**:

- **propósito declarado** (`gen_manifest.py:285-288`): *sobrevivência do preâmbulo puro*
- **implementação**: `counts[("PREAMBLE", sym)] += text.count(sym)` sobre o ficheiro **inteiro**
- **consequência medida**: 56 de 168 753 (**0,03 %**) medem o propósito; os outros 99,97 % medem
  a forma do lifter

O irmão `ps3_indirect_call` tem o **mesmo** defeito e já custou uma volta ao projecto: o grupo
`opd-dispatch` nasceu precisamente para tapar um défice de 36 unidades desta natureza
(`manifest_delta_gate.py`, cabeçalho: *"Um gate que nasce sempre vermelho e' um gate que
ninguem le"*). É o mesmo problema, tratado com um penso em vez de um contrato.

**Recomendação (não executada nesta sessão):** o limiar semanticamente correcto para um
marcador `PREAMBLE` é o número de ocorrências **no preâmbulo** — `56` para o `g_trampoline_fn`,
igual nos dois lifts e **imune** a futuras melhorias do lifter. É a única forma que mantém o
gate a detectar o que ele existe para detectar (um re-lift que perde o preâmbulo) sem o pôr a
gritar sempre que o lifter melhora.

---

## 11. O comando de rebaseline — para o utilizador decidir correr

**Não corri nenhum destes.** O baseline está intacto.

### Opção A — mínima e semanticamente correcta (recomendada)

Uma linha do `MANIFEST.tsv`. O 5.º campo (`nota`) já é suportado e retro-compatível
(`gen_manifest.py:109-124`):

```bash
cd /Users/andrebrumcortezferreira/Documents/PESSOAL/ps3recomp
# linha 217 de games/gow2/lift_baseline/MANIFEST.tsv
#   antes: g_trampoline_fn<TAB>PREAMBLE<TAB>168753<TAB>ppu_recomp_000.cpp,...
#   depois: 168753 -> 56   (ocorrências NO PREÂMBULO; 56 na produção e 56 no lift fresco)
# e acrescentar como 5.ª coluna, separada por TAB:
#   REBASE 2026-08-03: 168753 era a contagem do FICHEIRO INTEIRO num lift
#   lifter-rev 0852305 (2026-07-26). O fix 0585636 (2026-07-30, jump table)
#   mudou fronteiras e a contagem para 168435 sem perder um unico dispatcher
#   (125/125 conservados, +22 novos). 56 = ocorrencias no preambulo, que e' o
#   que este marcador PREAMBLE diz verificar. Ver notes/2026-08-03-trampoline-fn-deficit.md

# validação (tem de sair SEM a linha do g_trampoline_fn nos dois lifts):
python3 games/gow2/lift_baseline/gen_manifest.py ../gow2-recomp/recomp_macos_v4ord \
        --verify games/gow2/lift_baseline/MANIFEST.tsv
python3 games/gow2/lift_baseline/gen_manifest.py ../gow2-recomp/recomp_macos_v2 \
        --verify games/gow2/lift_baseline/MANIFEST.tsv   # não-regressão da produção
```

Aplicar o mesmo raciocínio a `ps3_indirect_call` (linha 218, `15759`, preâmbulo = **7**) fecha
a família toda e provavelmente torna o grupo `opd-dispatch` desnecessário — **mas isso é uma
decisão à parte, com prova à parte, e não está feita aqui.**

### Opção B — bump literal (funciona, mas re-arma a armadilha)

`168753 → 168435`. Verde hoje; vermelho outra vez ao próximo fix de fronteiras do lifter.

### Opção C — congelar como dívida (`--freeze`) — **NÃO recomendada**

```bash
# manifest_delta_gate.py <LIFT> --manifest MANIFEST.tsv --freeze MANIFEST_DEBT_BASELINE.json
```

O `--freeze` regenera o ficheiro **inteiro** a partir do lift alvo. Congelaria também o
`AMENOS:SYM:ps3_mp_on_enter` — o achado que a corrida de ontem **recusou** rebaselinar por ser
satisfeito, na produção, por um bloco `MENUPRESENT-PROBE id=9` **duplicado**. Usar o `--freeze`
aqui reintroduzia por acidente a decisão que ontem se tomou de propósito.

### O que o rebaseline **não** desbloqueia

Fechar o `g_trampoline_fn` põe o **critério 1** (`verify_lift.sh rc=0`) a verde **desde que**
o `ps3_mp_on_enter` seja tratado à parte. **Não toca** nos outros dois:

| Critério | Estado depois deste rebaseline |
|---|---|
| 1 — `verify_lift.sh rc=0` | verde **se** o `ps3_mp_on_enter` for resolvido (é artefacto de baseline, já diagnosticado) |
| 3 — `ICALL-BAD=0`, `FATAL` não novo | **continua vermelho como escrito.** `ICALL-BAD=12` é igual à produção; o critério pede 0. Critério mal escrito — a §9 mostra que o `FATAL` do candidato **não é regressão** |
| 4 — `accept_relift.sh rc=0` | **continua vermelho.** A perna 4 exige o elo `nenhum` (`AUTO_LOAD`), que **nem a produção** atinge; a perna 3 fabrica 2 `FAILED` pelo defeito **D2** |

---

## 12. O que ficou por exercitar

| # | Item | Porquê |
|---|---|---|
| 1 | Re-liftar com o `0585636` revertido | Seria o experimento discriminador definitivo. **Regra 1 desta sessão: zero builds/lifts.** A atribuição assenta em 5 lifts já existentes + a medição do próprio commit, não numa corrida nova |
| 2 | Correr `discover_jump_tables` isolado sobre o EBOOT nos dois revs | Mesma razão. Reproduziria os `137→157` / `1537→1745` do commit |
| 3 | Prova **in-boot** de que os 22 dispatchers recuperados mudam comportamento | Isto é análise **estática**. Nada aqui é uma afirmação sobre o boot |
| 4 | Causa do `stuck 0x00514E80` | Identificado como alvo indirecto por resolver em **ambos** os lifts; **não investigado** |
| 5 | `ps3_indirect_call` (mesmo defeito de contrato) | Diagnosticado na §10; **não corrigido, não rebaselinado** |
| 6 | `ps3_mp_on_enter` | Já diagnosticado ontem como artefacto de baseline; **fora do âmbito** desta sessão |
| 7 | Alterar o baseline | **Explicitamente interdito.** A entrega é a prova |
| 8 | Rastrear no lifter como +72 `case funcs` encurtam caudas em regiões cujo dispatcher não mudou (os −55 da §6) | Autoria fechada por exclusão; o **caminho interno** não foi lido no código |

---

## 13. Nível de evidência (regra 4 do `CLAUDE.md`)

| Item | Nível |
|---|---|
| `g_trampoline_fn` 168753 / 168435 nos 2 lifts | **medido offline** nesta sessão (3 sondas independentes) |
| A linha do gate reproduzida com o `gen_manifest.py` real | **medido offline** nesta sessão |
| Decomposição por chunk e por função (baldes 29 / 103 / 78, soma −318) | **medido offline** nesta sessão |
| `+74 = 103 − 29`, mesma população | **medido offline** nesta sessão |
| Carimbos `lifter-rev` (produção = `0852305`, 2026-07-26) | **medido offline** nesta sessão |
| `MANIFEST.tsv` congelado a 2026-07-26 04:37 (`dd7170a`) | **medido** (`git log -p`) |
| `funcoes emitidas 51917 → 51991` | **relido** da mensagem de `0585636` **e reproduzido** nos artefactos |
| 125 conjuntos de `case` conservados, +22 novos, **0 perdidos** | **medido offline** nesta sessão |
| Dispatcher `00382FD4` emitido 9× / 3× (duplicação de cauda) | **medido offline** nesta sessão |
| Switch tables declaradas contribuem 0 (119/119, 21/21) | **medido offline** nesta sessão |
| Weak wrappers contribuem +1 (`func_002C0498`) | **medido offline** nesta sessão |
| 29 endereços interiores a funções frescas, 0 referências pendentes | **medido offline** nesta sessão |
| `func_000B9354` indefinido na produção / definido no fresco | **medido offline** nesta sessão |
| −262 do défice localizado a clusters com dispatcher recuperado | **medido offline** nesta sessão |
| −55 do défice **não** localizado a um dispatcher | **medido**; atribuído ao mesmo fix **por exclusão** (janela de 2 commits, um deles confinado a 1 EA), não por rastreio no código |
| Caminho interno pelo qual +72 `case funcs` mudam caudas fora da sua região | **NÃO RASTREADO** |
| «o fix `0585636` é a causa do −317» | **inferido de 5 artefactos + a medição do commit.** Não re-liftado com o fix revertido (item 1 da §12) |
| Efeito in-boot de qualquer coisa desta nota | **NÃO-EXERCITADO** |

---

## Referências

- `games/gow2/notes/2026-08-03-ordem-e-promocao.md` — a corrida que isolou o défice
- `games/gow2/notes/2026-08-02-e2e-relift-completo.md` — onde apareceu primeiro (§5, §9 item 2)
- `tools/ppu_lifter.py:405-428` (preâmbulo), `:1737,1749,1816,1829,3654` (emissão), `:120-135,3446` (carimbo), `:3744` (`discover_jump_tables`)
- `games/gow2/lift_baseline/gen_manifest.py:285-292` (contrato do marcador `PREAMBLE`) · `MANIFEST.tsv:217-218`
- `games/gow2/config/gow2_switch_tables.toml` — as 2 tabelas declaradas e porque são no-op
- Commits: `dd7170a` (congela o baseline) · `91646a9` · `0e49c92` · **`0585636`** (o fix) · `a800471` (Fase 17) · `52a15de` (Fase 19)
