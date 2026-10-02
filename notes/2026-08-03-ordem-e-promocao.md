# A ordem, o D3, e a decisão de promover

**Data:** 2026-08-03 · **Máquina:** Apple Silicon (macOS/arm64)
**Objecto:** os passos 1, 3 e 6 de [`2026-08-03-seis-patches-que-nao-reaplicam.md`](2026-08-03-seis-patches-que-nao-reaplicam.md) §8 —
tornar a ordem de aplicação **declarativa**, fechar o defeito **D3** do gate do `MANIFEST`, e
correr a sequência canónica 1→8 **inteira, numa passagem**, para decidir a promoção.
**Lift candidato:** `recomp_macos_v4ord` (não versionado) · **Binário:** `boot_gow2_v4ord`
**Logs:** `/tmp/ord/*` (G6) · **Promoção: NÃO FEITA** — ver §5.

---

## Veredicto directo

> **A ordem ficou declarativa e a primeira passagem converge — 118 `APPLIED`, `1` `FAILED`
> fora de `PROBE` contra os 6 de antes, e a 2.ª passagem não muda um único byte.**
> **O D3 fechou, com prova de mutação nos dois sentidos.**
> **O gate NÃO deu verde. NÃO promovi.** Três dos quatro critérios falham, e um deles falha
> por dívida **real**: o `g_trampoline_fn` (−318), que nenhuma destas correcções toca.

O que se moveu mede-se: o lift fresco chega ao **elo 4 em 6 de 6** corridas (contra 6/9 do
rebuild de ontem e 2/3 da produção medida na mesma sessão), sem uma única corrida perdida
para o flake da intro, com `OOB` **1** contra **19** da produção. E o défice de grupo
`opd-dispatch` — 36 unidades, dívida declarada desde a Fase 3 — **desapareceu por inteiro**.

O que não se moveu diz-se com a mesma clareza: a `AUTO_LOAD` continua a nunca ser criada,
exactamente como na produção. Essa parede não era do re-lift e continua de pé.

---

## 1. Task 1 — a ordem ficou declarativa

### 1.1 O mecanismo

| Peça | Onde | O quê |
|---|---|---|
| **Declaração** | `games/gow2/lift_baseline/PATCH_DEPS.tsv` | `patch <TAB> depende_de <TAB> razao`. Uma linha por relação, com a razão e a proveniência (`patch:linha` da agulha + a posição no glob que falhava). |
| **Resolução** | `games/gow2/lift_baseline/order_patches.py` | Kahn com desempate pelo **índice original** — topo-sort *estável*. |
| **Consumo** | `apply_all_patches.sh` (as duas cópias, idênticas) | `--print-order` inspecciona a ordem efectiva sem tocar no lift. |
| **Teste** | `games/gow2/lift_baseline/test_order_patches.py` | 10 testes; o VERMELHO foi commitado antes do fix (`acd1ade`). |

**Porque estável e não um topo-sort qualquer:** sem relações declaradas a saída é **byte a byte
a ordem do glob**. Uma reordenação gratuita seria uma mudança de comportamento não medida em
140 patches. Cada relação move o mínimo:

```
b71_cb56c_reuse_block   #47 -> #44   (antes dos dois que o contaminavam)
2b3d1c_movie_io         #33 -> #62   (logo a seguir ao preâmbulo F2B)
fios_host_pop/open_probe  #83/#84 trocam
fios_done_yield         #74 -> #87   (depois do fios_sticky)
```

Propriedades garantidas e exercitadas: ponto fixo (reordenar duas vezes dá o mesmo),
permutação exacta (nenhum patch desaparece nem duplica), nome ausente = **AVISO** (nunca
aborta o corpus), **ciclo = falha ALTA** (`rc≠0`, com o ciclo nomeado — nunca se escolhe um
lado em silêncio).

### 1.2 Efeito na 1.ª passagem, medido

| | E2E 2026-08-02 (1.ª passagem, ordem do glob) | **v4ord (1.ª passagem, ordem declarada)** |
|---|---:|---:|
| `APPLIED` | 114 | **118** |
| `FAILED`/`FAILED-PARTIAL` fora de `PROBE` | **6** | **1** |
| Quais | `2b3d1c_movie_io`, `fios_done_yield`, `fios_host_pop`, `b71_cb56c_reuse_block`, `b71_skip_icallb_reuse`, `24e3d0_null_product_gate` | **só** `24e3d0_null_product_gate` |
| `NO-MATCH` | 0 | **0** |

Os cinco que caíram:

| Patch | Estado agora | Nota |
|---|---|---|
| `patch_2b3d1c_movie_io.py` | **APPLIED** | |
| `patch_fios_done_yield.py` | **APPLIED** | |
| `patch_fios_host_pop.py` | **APPLIED** | |
| `patch_b71_cb56c_reuse_block.py` | **APPLIED** | fecha 4 das 5 dívidas reais do `MANIFEST` |
| `patch_b71_skip_icallb_reuse.py` | `UNVERIFIED` | é um **verificador puro**: os 4 marcadores que exige estão agora presentes. `UNVERIFIED` só porque não tem contrato em `CONTRACTS.tsv` — dívida à parte, já identificada |

**Prova no binário** (`nm`/`strings`, os três binários da mesma família):

| Assinatura | `boot_gow2_v4ord` | `boot_gow2_v3e2e_r2` (ontem) | `boot_gow2` (produção) |
|---|---:|---:|---:|
| `AREAD-HLE` | 2 | 2 | 2 |
| `PS3_FIOS_HOST_POP` | 1 | 1 | 1 |
| `ps3_fios_aread_hle` | 1 | 1 | 1 |
| **`g_b71_product_reused`** | **1** | **0** | 1 |

O `_r2` de ontem não tinha o patch #4. Este tem — é o primeiro binário saído de um lift fresco
com os cinco.

Não se tocou em nenhum dos 6 patches. O que faltava era ordem, e era só ordem.

### 1.3 A prova de convergência — e o defeito D4 que ela apanhou

O critério: **correr `apply_all_patches.sh` duas vezes seguidas sobre uma árvore fresca tem de
dar o mesmo `sha256` na segunda.** (É o que a perna 3 do `accept_relift.sh` *devia* verificar —
defeito D2, diagnosticado, **não corrigido aqui**, só corrido.)

**Primeira tentativa: FALHOU.**

```
lift virgem : 4dab9ff8220caf735a9576dac13b340508e8ddc551eca28a01ca8c3efc3bb346
após 1ª pass: 7e0f53adb9da1c0ca7a83178d9afcc76a0a58ac811d4e5f3e5dfda2d11efa815
após 2ª pass: 57ffbe1978a118a4485f8fd551206909897e177f69d1fbf4a1b4cb0d4ba0b16f   <-- diferente
```

A 2.ª passagem acrescentava **3 blocos de probe duplicados**, e o `diff` nomeia-os:

```
ppu_recomp_000.cpp  +  /* FLIPPATH-PROBE id=2 */    (func_000B71B8)
ppu_recomp_001.cpp  +  /* FLIPPATH-PROBE id=3 */    (func_002B2E74)
ppu_recomp_001.cpp  +  /* MENUPRESENT-PROBE id=9 */ (func_002C0508)
```

**Causa medida, não suposta.** `patch_flip_path_enter_probe.py:273`:

```python
ahead = t[region_start : region_start + 160]
if probe_line in ahead or f"ps3_flipp_on_enter({site_id}," in ahead:
```

A verificação «já injectei aqui?» usa uma **janela FIXA de 160 caracteres** a seguir à
assinatura da função (o `menu_present` usa 200, o `postthr` 320). Nas três funções afectadas,
outros probes que correm **depois** injectam na mesma entrada e empurram o marcador para fora
da janela — na passagem seguinte o patch já não se vê a si próprio e injecta outra vez.
A entrada de `func_002B2E74` mostra-o à letra: `POSTTHR` (63 ch) + `MENUPRESENT` (66 ch) e o
`FLIPPATH` já começa em 129, com o marcador a acabar depois de 160.

**Fix aplicado: 4 relações novas** (`menu_present` depois de `postthr` e de `smpd_probe`;
`flip_path` depois de `menu_present` e de `introseq`), pondo os dois frágeis em último, com o
marcador deles no topo da função.

**Segunda medição: OK.**

```
lift virgem : 4dab9ff8220caf735a9576dac13b340508e8ddc551eca28a01ca8c3efc3bb346
após 1ª pass: e01108b5aac58d2294d5b785f5fd5aa8e6e11bc007f3de70048fcf8cf066de73
após 2ª pass: e01108b5aac58d2294d5b785f5fd5aa8e6e11bc007f3de70048fcf8cf066de73   <-- idêntico
APPLIED na 2ª passagem: 0
```

**Honestidade sobre este fix (regra 4):** a ordem **contorna**; a causa raiz é a janela fixa.
Está escrito no `PATCH_DEPS.tsv`, não escondido: *qualquer probe novo que injecte na entrada
destas funções volta a partir isto*. O fix estrutural — janela por função em vez de por bytes —
fica para outra leva; nesta não se toca em patches.

---

## 2. Task 2 — o D3 fechou

### 2.1 O que mudou

`gen_manifest.py --verify` passa a contar as `TAG` **também** em `games/gow2/hooks/*.cpp`
(por *default*, porque o `verify_lift.sh` — o caminho de aceite — invoca sem flags nenhumas),
e imprime a repartição:

```
host (TAGs migradas, código versionado): 2 ficheiro(s) -- gow2_func_overrides.cpp, gow2_midasm_hooks.cpp
  MIGRADO  [INTROSEQ]: 10 no lift + 8 em host = 18
  MIGRADO  [B71]:     492 no lift + 2 em host = 494
```

Contar a migração **em silêncio** trocaria uma dívida falsa por um verde opaco — pior negócio.

**Alcance deliberado: só tipo `TAG`.** Não é timidez, é semântica: um marcador `SYM`/`GLOBAL`
do `MANIFEST` significa *«definido no preâmbulo injectado do lift»*, e a mesma string num hook
é um **call site**, não uma definição. Medido: contar `SYM` nos hooks somava `ps3_indirect_call`
e `ps3_call_opd` e **mascarava dívida real** (partiu 2 testes do `test_manifest_delta_gate.py`,
que foi como se descobriu). **Dívida que fica escrita no código:** migrar um patch com
marcadores `SYM` para weak override — o #4 é o próximo candidato — vai gerar a mesma dívida
falsa e precisa de uma nota `MIGRADO:` no `MANIFEST.tsv`, do mesmo feitio das `OBSOLETO:`/`GRUPO:`
que já existem. **Não está fechada.**

### 2.2 A prova por mutação, nos dois sentidos

Sobre o corpus **real** (lift fresco `recomp_macos_v3_e2e`, `MANIFEST.tsv` e
`MANIFEST_DEBT_BASELINE.json` reais), comparando os ids `NOVO` do gate por delta:

| Condição | ids `NOVO` |
|---|---|
| **pós-D3, hooks intactos** (migração legítima) | `g_trampoline_fn`, `ps3_factory_freelist_replenish`, `ps3_factory_repair_vt`, `ps3_factory_reuse_product`, `[POSTINTRO]` — **5, todos dívida REAL** |
| **MUTAÇÃO: 1 marcador apagado do hook** | os mesmos 5 **+ `AMENOS:TAG:[INTROSEQ]`** |
| **pré-D3** (`--no-host-sources`) | **idêntico ao mutado** |

> A última linha é o defeito na sua formulação mais forte: **o gate antigo era indistinguível
> de um gate a olhar para hooks com um marcador apagado.** Lia um sucesso e um estrago da
> mesma maneira.

`diff` verde→vermelho: exactamente `+ AMENOS:TAG:[INTROSEQ]`. Nada mais se moveu.

No candidato desta corrida (`recomp_macos_v4ord`) a dívida falsa **não aparece**:
`MIGRADO [INTROSEQ]: 10 no lift + 8 em host = 18`.

Cobertura em teste: `test_gen_manifest_hooks.py` (8 testes, mutação nos dois sentidos ao nível
do `gen_manifest.py` e do `manifest_delta_gate.py`, mais um teste que exige que o *default*
aponte para os hooks reais — senão o fix não chegava ao caminho de aceite). Suite completa do
`lift_baseline`: **10 ficheiros de teste, todos `rc=0`**.

---

## 3. Task 3 — a sequência 1→8, numa passagem

Corrida a partir de `../gow2-recomp`, `PS3_ENGINE_ROOT` explícito.

| Etapa | Comando | Resultado |
|---|---|---|
| 1 | `functions.json` | **saltada** — fronteiras não mudaram (`functions.json` de 19 jul) |
| 2 | `ppu_lifter.py --config` → `recomp_macos_v4ord` | `rc=0`, **12 s**, 51 991 funções, 7 chunks, 0 stubs |
| 3 | não reaplicar migrados | nada a correr |
| 4 | `apply_all_patches.sh --status` (**1 passagem**) | 118 `APPLIED`, 1 `FAILED` fora de `PROBE`, 0 `NO-MATCH` |
| — | **convergência** (2.ª passagem) | `sha256` **idêntico**, 0 `APPLIED` |
| 5 | `verify_lift.sh` | **`rc=1`** — ver §4 |
| 6 | `build_macos.sh` | `rc=0`, **73 s**, 7/7 chunks, 0 erros, binário 121 684 576 B |
| 7 | smoke da intro 30 s | `st620` `0→1→3→3→11`, **máx 11**; `OOB`/`0xFFFF`/`FATAL`/`ICALL-BAD` = **0** |
| 8 | `accept_relift.sh v4ord 6 /tmp/ord` | **`rc=1` — REJEITADO** |

**Forma da etapa 2, declarada:** usei a *«forma explícita equivalente»* que o próprio
`RELIFT_CANONICAL.md` §2 dá (lift separado do build), **não** o `RELIFT=1`. Motivo: o `RELIFT=1`
compila antes da etapa 4 (defeito D1, confirmado na análise) e produziria um binário a partir
de um lift sem patches — exactamente o erro que esta corrida existe para não repetir.

### 3.1 As corridas do gate da cadeia — 6 do candidato + 3 de controlo

`smoke_chain_gate.sh`, `timeout` 90 s, kill por **PID** via `measure_one()`.

**Candidato `boot_gow2_v4ord` (perna 4 do aceite, 6 corridas):**

| # | `st620` | `startseq` | `nopic` | `thr_created` | `r_perma` | `setflip_after_rperm` | **`elo_stopped`** | OOB | `0xFFFF` | `ICALL-BAD` | `FATAL` |
|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|
| 1 | 11 | 2 | 4 | 0 | 1 | 9 | `AUTO_LOAD (nunca criada)` | 1 | 1 | 12 | 1 |
| 2 | 11 | 2 | 4 | 0 | 1 | 8 | `AUTO_LOAD (nunca criada)` | 1 | 1 | 12 | 1 |
| 3 | 11 | 2 | 4 | 0 | 1 | 10 | `AUTO_LOAD (nunca criada)` | 1 | 1 | 12 | 1 |
| 4 | 11 | 2 | 4 | 0 | 1 | 9 | `AUTO_LOAD (nunca criada)` | 1 | 1 | 12 | 1 |
| 5 | 11 | 2 | 4 | 0 | 1 | 9 | `AUTO_LOAD (nunca criada)` | 1 | 1 | 12 | 1 |
| 6 | 11 | 2 | 4 | 0 | 1 | 10 | `AUTO_LOAD (nunca criada)` | 1 | 1 | 12 | 1 |

**Elo 4 em 6 de 6. Elo 1/2/3 em 0 de 6.** TSV: `/tmp/ord/accept_recomp_macos_v4ord_chain.tsv`.

**Controlo `boot_gow2` (produção, só executada), mesma sessão, 3 corridas:**

| # | `st620` | `startseq` | `nopic` | `r_perma` | `setflip` | `elo_stopped` | OOB | `0xFFFF` | `ICALL-BAD` | `FATAL` |
|---|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|
| 1 | 11 | 2 | 4 | 1 | **0** | `AUTO_LOAD (nunca criada)` | **19** | **16** | 12 | 1 |
| 2 | 11 | 2 | 4 | 1 | **0** | `AUTO_LOAD (nunca criada)` | **19** | **16** | 12 | 1 |
| 3 | 11 | 2 | 4 | 1 | **0** | `AUTO_LOAD (nunca criada)` | **19** | **16** | 12 | 1 |

**Perna 1 do aceite (`smoke_relift_equiv.sh`, mais 6 corridas):** `st620_max=11` em **6/6**,
`lifted=52142`, `modules=13`, `imports=151`, `alloc=0` — `rc=0`.

**O flake da intro não apareceu.** 0 de 6 no candidato (ontem: 3 de 9 no `_r2`, 1 de 3 nos dois
controlos). Com 6 corridas isto é uma observação, **não** uma prova de que o flake acabou.

**Receita, declarada (G6):** a etapa 7 correu com `PS3_NO_RSX=1 PS3_RSX_BACKEND=trace`
`PS3_PERF_FSM=1 PS3_MOVIE_EOS=0` (a receita da canónica). As 6+3 corridas do gate correram com
a **receita fixada pelo instrumento** — `arm_menu_fast_recipe()` em `lib_boot_chain_metrics.sh`
exporta `PS3_RSX_BACKEND=metal` e editar scripts de medição não estava em causa. É a mesma
receita dos dois pontos de referência (E2E e a medição de ontem), e o controlo de produção
**da mesma sessão** garante que a comparação é entre iguais.

**Higiene:** 16 boots, todos mortos por **PID** (`TERM` → `-9`); **0 órfãos** antes e depois
(verificado); logs todos em `/tmp/ord` e `/tmp/chain_gate_*`; produção nunca escrita.

---

## 4. Os quatro critérios, um a um

### Critério 1 — `verify_lift.sh` `rc=0` · **FALHOU**

```
lift_parity          PASS    (current=76 baseline=77 -> 0 novos, 1 RESOLVIDO)
MANIFEST             FAIL    (current=2 baseline=36 -> 2 novos, 36 RESOLVIDOS)
audit_boundaries     PASS    (current=180 baseline=180 -> 0 novos)
```

A dívida falsa do D3 **desapareceu** (`[INTROSEQ]` já não aparece). O défice de grupo
`opd-dispatch`, 36 unidades declaradas desde a Fase 3, **resolveu-se por inteiro** — é o patch
#4 a aplicar-se. Sobram **dois** achados novos:

| Achado | Medido | Natureza |
|---|---|---|
| `AMENOS:PREAMBLE:g_trampoline_fn` | `168 435` no v4ord · `168 435` no lift fresco de ontem · `168 753` na produção · `MANIFEST` exige `168 753` | **DÍVIDA REAL.** −318, idêntico em **qualquer** lift fresco. Não é causado por nada desta leva — é a mesma dívida que o E2E deixou por explicar (§4 da análise: *«NÃO ATRIBUÍVEL aos 6… fica por explicar»*). **Continua por explicar.** |
| `AMENOS:SYM:ps3_mp_on_enter` | `16` no v4ord · `17` na produção e no lift de ontem | **ARTEFACTO DO BASELINE.** Sítios **únicos**: 12 no v4ord, 12 na produção, 12 no lift de ontem. O `17` da produção é satisfeito por um **bloco DUPLICADO** (`MENUPRESENT-PROBE id=9` aparece 2×) — precisamente o duplicado que a janela de 200 caracteres produz numa 2.ª passagem. O D4 removeu-o e o gate acusou a remoção. **Zero sítios reais perdidos.** |

O segundo é um achado de valor: **o baseline do `MANIFEST` estava a ser satisfeito por um
acidente de não-idempotência.** Não o rebaselinei — rebaselinar para tapar o próprio fix seria
o oposto do que este gate existe para fazer.

Mas o critério é `rc=0`, e a instrução era clara: **vermelho por dívida real ⇒ não promover.**
O `g_trampoline_fn` é dívida real. **Critério 1 falha.**

### Critério 2 — elo 4 em ≥4 de 6 corridas · **PASSOU**

**6 de 6.** Sem uma única corrida perdida para o flake. Melhor do que os 6/9 do rebuild de
ontem e do que os 2/3 e 3/3 da produção.

### Critério 3 — `st620_max ≥ 3`, `OOB`/`0xFFFF` não pior, `ICALL-BAD=0`, `FATAL` não novo · **FALHOU**

| Sub-critério | Candidato | Produção (mesma sessão) | Veredicto |
|---|---:|---:|---|
| `st620_max ≥ 3` | **11** em 6/6 (e 11 em 6/6 na perna 1) | 11 | **PASSA** |
| `OOB` não pior | **1** | 19 | **PASSA** (muito melhor) |
| `0xFFFF` não pior | **1** | 16 | **PASSA** (muito melhor) |
| `ICALL-BAD = 0` | **12** | **12** | **FALHA** como escrito. Idêntico à produção — **não é regressão**, mas também não é zero, e escrever «passa» seria forjar. |
| `FATAL` não novo | 1 — `stuck calling 0x00514E80` | 1 — `stuck calling 0x000B9354` | **FALHA/indeterminado**: há um `FATAL` num **endereço diferente** do da produção. |

**Um resultado a registar sobre o `FATAL`:** a hipótese da §4.4 de ontem — que o `stuck` em
`0x00514E80` se explicaria pela ausência do patch #4 no `_r2` — fica **REFUTADA**. Nesta
corrida o #4 **está aplicado** (`g_b71_product_reused` presente no binário) e o `stuck`
continua exactamente em `0x00514E80`, em 6/6 corridas. A causa é outra e **não foi
investigada** aqui.

### Critério 4 — `accept_relift.sh` `rc=0` · **FALHOU** (`rc=1`, REJEITADO)

```
PERNA 1 (smoke)          PASS   (OK=6/6)
PERNA 2 (verify_lift)    FAIL   (rc=1)
PERNA 3 (apply_patches)  FAIL   (NO-MATCH=0  FAILED-fora-PROBE=3)
PERNA 4 (chain gate)     FAIL   (OK=0/6)
CONTADORES (D-5.2)       PASS   (imp_modules 13=13, imp_imports 151=151, órfãos 0)
```

- **Perna 2** = critério 1.
- **Perna 3: `3` — e dois deles são inventados pelo próprio gate.** A 1.ª passagem tem **1**
  (`24e3d0_null_product_gate`). A perna 3 corre o `apply_all_patches.sh` **outra vez** por cima
  da árvore já patchada e produz mais dois: `patch_1856a8_stream_opd.py` e
  `patch_icg_ctor_opd.py` — os **mesmos dois** que a análise §7 previu, agora **confirmados ao
  vivo**. É o defeito **D2**, diagnosticado e por corrigir noutra leva (aqui só corrido, como
  mandado). Com a perna 3 a verificar convergência em vez de repetir a aplicação, esta perna
  daria `FAILED-fora-PROBE=1`.
- **Perna 4: exige o elo `nenhum`, não o elo 4.** O gate quer a cadeia inteira até ao WAD, e a
  `AUTO_LOAD` nunca é criada — **também na produção** (0/3 nesta sessão). O critério 2 (elo 4)
  e o critério 4 (`accept rc=0`) são, hoje, **mutuamente inatingíveis**: um pede o elo 4, o
  outro o elo 5.
- **Contadores:** `function_table_count` +74 e `boot_lifted_functions` +74 face à produção —
  informativos, e a **mesma** dívida herdada do E2E, ainda **não explicada**.

### O que sobra do `24e3d0_null_product_gate`

É o único `FAILED` real da 1.ª passagem, e a análise já o tinha arrumado: falha **igual** contra
a produção, o marcador nunca entrou no `MANIFEST.tsv`, e é um gate de diagnóstico `OFF` por
default (`PS3_24E3D0_KEEP_TYPE_ON_NULL=1`). O passo 2 da §8 — reclassificá-lo para `PROBE`, uma
linha na heurística do `gen_catalog.py` — **não foi feito aqui**: não estava nas três tasks
desta leva. É o desbloqueio mais barato que resta para a perna 3.

---

## 5. A decisão

> ## NÃO PROMOVIDO.
> `promote_lift.sh` **não foi invocado**. `recomp_macos_v2` e `boot_gow2` não foram escritos —
> a produção só foi **executada**, como controlo.

| # | Critério | Veredicto | Porquê |
|---|---|---|---|
| 1 | `verify_lift.sh rc=0` | **FALHOU** | `AMENOS:PREAMBLE:g_trampoline_fn` — dívida **real** (−318), presente em qualquer lift fresco, **por explicar** desde o E2E. (O segundo achado, `ps3_mp_on_enter`, é artefacto do baseline.) |
| 2 | elo 4 em ≥4 de 6 | **PASSOU** | 6 de 6 |
| 3 | `st620≥3`, OOB/`0xFFFF` não pior, `ICALL-BAD=0`, `FATAL` não novo | **FALHOU** | `ICALL-BAD=12` (igual à produção, mas não é 0); `FATAL` em `0x00514E80`, endereço **diferente** do de produção |
| 4 | `accept_relift.sh rc=0` | **FALHOU** | Rejeitado: perna 2 (=crit. 1), perna 3 (3 `FAILED`, 2 deles fabricados pelo D2), perna 4 (exige elo `nenhum`) |

**Um «quase» não se promove.** Um dos quatro passou. E o critério 4 é, por construção, ainda
mais exigente do que o critério 2 — enquanto a `AUTO_LOAD` não for criada, **nenhum** lift, nem
o de produção, passa o `accept_relift.sh`.

---

## 6. Higiene (G6)

| Regra | Estado |
|---|---|
| Produção intacta | **cumprido** — `recomp_macos_v2`/`boot_gow2` não escritos; `boot_gow2` só **executado** |
| Promoção | **NÃO FEITA** — `promote_lift.sh` não invocado |
| Kill por **PID** (`TERM` → `-9`) | **cumprido** — 16 boots; nenhum `pkill -f` |
| Órfãos no fim | **0** (verificado antes e depois de cada lote) |
| `timeout(1)` | **não usado** (não existe no macOS) |
| `sticky_pub>=1` como critério | **não usado** |
| Logs fora dos dois repos | **cumprido** — `/tmp/ord/*`, `/tmp/chain_gate_*` |
| `accept_relift.sh` perna 3 (D2) | **não tocada** — só corrida, como mandado |
| Os 6 patches | **não tocados** |
| Ficheiros de outra sessão | `recomp_mid_v2/patch_41f78c_prune_probe.py` (`M`) e os `.planning/*`/`CLAUDE.md` ficam **fora** destes commits |

---

## 7. O que ficou por exercitar

| # | Item | Porquê |
|---|---|---|
| 1 | `g_trampoline_fn` −318 e `+74` funções | **por explicar** — herdado do E2E, e é o que bloqueia o critério 1 |
| 2 | Causa do `stuck 0x00514E80` | hipótese anterior **refutada**; causa **não investigada** |
| 3 | Reclassificar `24e3d0_null_product_gate` para `PROBE` (§8 passo 2) | fora das três tasks desta leva |
| 4 | D2 — perna 3 = verificação de convergência (§8 passo 4) | **explicitamente interdito** nesta leva |
| 5 | D1 — `RELIFT_ONLY=1` + doc (§8 passo 5) | não pedido; contornado usando a forma explícita |
| 6 | Nota `MIGRADO:` no `MANIFEST.tsv` para marcadores `SYM` | dívida que o D3 **não** fecha, escrita no código |
| 7 | Janela de idempotência por função (causa raiz do D4) | a ordem contorna; o fix estrutural fica para outra leva |
| 8 | `AUTO_LOAD` nunca criada | **parede pré-existente**, igual na produção |
| 9 | As 4 paredes da Fase 11 | **não tocadas** |

---

## 8. Nível de evidência (regra 4 do `CLAUDE.md`)

| Item | Nível |
|---|---|
| Ordem efectiva com as 9 relações; permutação exacta do glob | **medido offline** (`--print-order`, 10 testes) |
| 118 `APPLIED` / 1 `FAILED` fora de `PROBE` na 1ª passagem | **medido** nesta sessão |
| Convergência: `sha256` idêntico à 2ª passagem, 0 `APPLIED` | **medido** nesta sessão |
| D4: janela de 160 chars como causa dos 3 duplicados | **medido** (`diff` dos chunks + leitura do patch:273) |
| D3: prova de mutação nos dois sentidos, corpus real | **medido offline** nesta sessão |
| `g_b71_product_reused` no binário v4ord e ausente do `_r2` | **medido offline** (`nm`) |
| `elo_stopped` = elo 4 em 6/6 | **medido in-boot**, 6 corridas |
| Produção em elo 4, `OOB=19`, `ICALL-BAD=12`, `FATAL 0x000B9354` | **medido in-boot**, controlo de 3 corridas na mesma sessão |
| `ps3_mp_on_enter` 17 da produção ser um duplicado | **medido offline** (ids únicos: 12 nos três lifts) |
| Ausência do flake da intro (0/6) | **medido**, amostra pequena — observação, não prova |
| Hipótese «#4 explica o `stuck 0x00514E80`» | **REFUTADA** por medição |
| Causa do `stuck 0x00514E80` | **NÃO INVESTIGADA** |
| `g_trampoline_fn` −318 | **medido, NÃO EXPLICADO** |

---

## Referências

- `games/gow2/notes/2026-08-03-seis-patches-que-nao-reaplicam.md` — a análise (§8 passos 1/3/6)
- `games/gow2/notes/2026-08-03-rebuild-e2e-medicao.md` — o rebuild que mediu os dois elos
- `docs/RELIFT_CANONICAL.md` — a sequência 1→8
- `games/gow2/lift_baseline/PATCH_DEPS.tsv` · `order_patches.py` · `test_order_patches.py`
- `games/gow2/lift_baseline/gen_manifest.py` · `manifest_delta_gate.py` · `test_gen_manifest_hooks.py`
- `games/gow2/apply_all_patches.sh` (`--print-order`) — e a cópia idêntica em `../gow2-recomp/`
- Logs não versionados (G6): `/tmp/ord/step{2,5,6,7,8}_*.log`, `/tmp/ord/p{1,2}_status.tsv`,
  `/tmp/ord/convergencia.txt`, `/tmp/ord/accept_recomp_macos_v4ord_*.{tsv,log}`,
  `/tmp/ord/ctl_prod.tsv`, `/tmp/chain_gate_boot_gow2*_run*.log`
