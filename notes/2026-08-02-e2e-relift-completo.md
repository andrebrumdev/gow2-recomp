# E2E — a sequência canónica de re-lift 1→8 corrida de ponta a ponta

**Data:** 2026-08-02 · **Máquina:** Apple Silicon (macOS/arm64) · **Repo motor:** `ps3recomp` @ `6d2ce8d` (`macos-arm64-port-f0-f2`)
**Repo de build:** `../gow2-recomp` · **Lift novo:** `recomp_macos_v3_e2e` · **Binário:** `boot_gow2_v3e2e` / `boot_gow2_v3_e2e`
**Duração total:** ~31 min de relógio (23:11 → 23:42), 1471 s de comando cronometrado
**Logs:** todos em `/tmp/e2e/` — **fora dos dois repositórios** (G6), **não versionados**
**Promoção:** **NÃO FEITA.** `promote_lift.sh` não foi invocado. Produção (`recomp_macos_v2` / `boot_gow2`) **intacta**.

Isto **não é um plano GSD**: é uma medição. Fecha de caminho a **ressalva 2** do marco v1.3
(`WINDOWS` #16) — «a sequência canónica 1→8 nunca foi corrida numa só passagem». Agora foi.

---

## Veredicto directo (sem eufemismo em nenhuma direcção)

> **O lift regenera 100%. O build compila 100%. E não há avanço no boot — há regressão.**

Três frases, cada uma com número atrás:

1. **O lifter regenera 100%** — `rc=0`, 51 991 funções, **0 fallback stubs**, 32 s. E — a pergunta
   que nunca tinha sido feita — os **três mecanismos do marco v1.3 correm juntos sem colidir**:
   1 `[[midasm_hook]]` + 4 `[[functions_override]]` (weak ON) + 2 `[[switch_table]]` na mesma
   invocação, todos emitidos, zero avisos. **Primeira vez medido.**
2. **O build compila 100%** — `rc=0`, 7 chunks, **0 erros**, `boot_gow2_v3e2e` (116 MB) produzido
   em 75 s. E é o **primeiro binário do projecto** em que o mid-asm hook está simultaneamente
   *definido* e *chamado* — em produção há **0 call sites**.
3. **Mas a cadeia de aceite é REJEITADA (`rc=1`)** e o boot vai **menos longe** que produção:
   pára no elo **2 (2.º movie / StartSeq)**, contra o elo **4 (AUTO_LOAD)** da produção. **Menos
   dois elos.** Causa medida: **6 patches de classe `FUNCIONAL` não reaplicam** a um lift fresco.

**A camada que falha não é a que o marco v1.3 entregou.** O que o v1.3 construiu — o mecanismo
que faz correcções sobreviverem a um re-lift — funcionou **perfeitamente**, e isso está provado
abaixo com dupla injecção = 0 e o hook a disparar in-boot. O que falha é a camada **antiga**, os
`patch_*.py` que o marco explicitamente **não** migrou (as 72 linhas `CORRECTNESS/todo` + as
`FUNCIONAL` do catálogo). A sequência 1→8 tornou isso visível pela primeira vez.

**Resposta à pergunta do utilizador — «o GoW2 vai recompilar 100%?»:** o *pipeline* de
recompilação já recompila 100% (lift + build). O que ainda não reproduz 100% é o **corpus de
patches** por cima dele. **«Vamos ter avanço com estas melhorias?»** — não neste marco, e o marco
v1.3 nunca prometeu avanço no boot. As quatro paredes da Fase 11 (`func_002545B0`,
`func_002182A4`, `func_002547AC`, `func_0041F700`) **continuam por resolver**; nenhuma foi
atacada. Isto é o **resultado esperado**, e diz-se assim.

---

## As 8 etapas — comando, `rc` e duração

| # | Etapa | Comando | `rc` | dur | Veredicto |
|---|---|---|---:|---:|---|
| 1 | `functions.json` (condicional) | *não corrida* — fronteiras inalteradas | — | 0 s | **saltada, por desenho** |
| 2 | `ppu_lifter --config` → lift NOVO | `python3 tools/ppu_lifter.py EBOOT.ELF --functions functions.json --config games/gow2/config/gow2_recomp.toml -o ./recomp_macos_v3_e2e -j 4` | **0** | 32 s | **PASS** |
| 3 | **não** reaplicar os patches migrados | *nada a correr* (verificado por medição, ver §3) | — | 0 s | **PASS** |
| 4 | `apply_all_patches.sh` | `./apply_all_patches.sh ./recomp_macos_v3_e2e --status /tmp/e2e/relift_status.tsv` | **1** | 217 s | **FAIL** |
| 5 | `verify_lift.sh` | `games/gow2/verify_lift.sh ./recomp_macos_v3_e2e` | **1** | 37 s | **FAIL** (`MANIFEST`) |
| 6 | build | `OUT=./boot_gow2_v3e2e FORCE_REBUILD_LIFT=1 ./build_macos.sh ./recomp_macos_v3_e2e` | **0** | 75 s | **PASS** |
| 7 | smoke da intro 30 s | `./boot_gow2_v3e2e EBOOT.ELF`, kill por PID | **143** (SIGTERM, esperado) | 32 s | **PASS** nos critérios do `CLAUDE.md` |
| 8 | aceite (4 pernas) — **sem promoção** | `./accept_relift.sh ./recomp_macos_v3_e2e 6 /tmp/e2e` | **1** | 1078 s | **REJEITADO** |

**Etapa 1 — porque foi saltada, e não por preguiça.** `functions.json` (sha256
`90ad64dd…`, mtime 19/jul) **não mudou** desde o baseline da Fase 16, e o `functions.json` do
GoW2 tem adições curadas à mão que a canónica manda **não regenerar por reflexo**. A regressão de
fronteiras é medida à mesma, por delta, no passo 3 do `verify_lift` — e deu
`audit_boundaries current=180 baseline=180 novos=0 **PASS**`. A etapa foi saltada **e verificada**.

**Etapa 2 — forma explícita, não `RELIFT=1`.** Usei a *«forma explícita equivalente»* que o
`RELIFT_CANONICAL.md` documenta na própria etapa 2, mais o comando literal da etapa 6.
**Razão medida, e é um defeito do documento — ver §7:** `RELIFT=1` funde as etapas 2 e 6, ou
seja **compila e linka ANTES da etapa 4**. O binário sairia sem os 114 patches `APPLIED`.

---

## As três perguntas, com número

### 1. O lift regenera 100%? — **SIM**

```
$ python3 tools/ppu_lifter.py EBOOT.ELF --functions functions.json \
      --config games/gow2/config/gow2_recomp.toml -o ./recomp_macos_v3_e2e -j 4
  Config: 0 invalid_instructions pattern(s) loaded
  Config: 1 midasm_hook(s) loaded
  Config: 4 functions_override entry(ies) loaded (weak wrapper emission ON)
  Config: 2 switch_table(s) declared em gow2_switch_tables.toml
  switch tables: 157 from discovery, 2 from config, 2 overridden by config, 157 total
  Generated 30929 mid-function tail-entry wrappers total
  Wrote 7 source chunks: ppu_recomp_000.cpp .. ppu_recomp_006.cpp
  0 fallback stubs (every referenced target is defined)
  51991 functions lifted
  5691 unique call targets
rc=0   dur=32s
```

| Métrica | Valor | Nota |
|---|---:|---|
| `rc` | **0** | — |
| Funções liftadas | **51 991** | contra 51 917 da produção — delta **+74**, `INFORMATIVO` no gate D-5.2 |
| Fallback stubs | **0** | «every referenced target is defined» — nenhum alvo ficou por resolver |
| Erros / avisos do `--config` | **0** | nenhum `Warning:` na saída |
| Chunks | 7 (≈600 000 linhas cada) | 399 MB |
| Duração | **32 s** | — |

**O `--config` sobrevive — os três mecanismos na MESMA corrida, medidos no output:**

```
$ grep -hoE 'PPC_FUNC_IMPL\(func_[0-9A-Fa-f]{8}\)' recomp_macos_v3_e2e/ppu_recomp_*.cpp | sort -u
PPC_FUNC_IMPL(func_00010230)   PPC_FUNC_IMPL(func_0002F3F0)
PPC_FUNC_IMPL(func_000CE03C)   PPC_FUNC_IMPL(func_002C0498)      # 4/4 símbolos FORTES

$ grep -hoE '^PPC_FUNC\(func_[0-9A-Fa-f]{8}\)' recomp_macos_v3_e2e/ppu_recomp_*.cpp | sort -u
PPC_FUNC(func_00010230)  PPC_FUNC(func_0002F3F0)
PPC_FUNC(func_000CE03C)  PPC_FUNC(func_002C0498)                 # 4/4 wrappers FRACOS

$ grep -c 'gow2_midasm_Ce03cWaitIdle(ctx);' recomp_macos_v3_e2e/ppu_recomp_*.cpp
ppu_recomp_000.cpp:1   ppu_recomp_002.cpp:1                      # 2 call sites do mid-asm
```

**Isto é a primeira vez que `[[midasm_hook]]`, `[[functions_override]]`+weak e `[[switch_table]]`
correm juntos numa só invocação do lifter. Nenhum colidiu.** Era a pergunta em aberto do marco, e
a resposta é limpa: 1 hook emitido em 2 sítios, 4 pares forte/fraco completos, 2 switch tables do
config a substituir as descobertas (`2 overridden by config`) sem partir as outras 155.

### 2. O build compila 100%? — **SIM**

```
$ OUT=./boot_gow2_v3e2e FORCE_REBUILD_LIFT=1 ./build_macos.sh ./recomp_macos_v3_e2e
=== 1. lifted chunks -> .o   dur=19s objs=7 errors=0
  host_gow2_factory: definicoes ja' no lift -- nao compilar (evita duplicate symbol)
  host_gow2_f2b:     definicao ja' no lift -- nao compilar
  gow2_midasm_hooks: compilado
  gow2_func_overrides: compilado (overrides: func_00010230 func_0002F3F0 func_000CE03C func_002C0498)
  imagens SPU: 7 objecto(s)
=== 5. link ===
-rwxr-xr-x  116M boot_gow2_v3e2e
rc=0   dur=75s
```

| Métrica | Valor |
|---|---:|
| `rc` | **0** |
| Ficheiros compilados (chunks liftados) | **7 / 7** |
| Erros de compilação | **0** (`grep -c 'error:' *.cclog` = 0 nos 7) |
| `boot_gow2` produzido? | **sim** — `boot_gow2_v3e2e`, 121 667 408 B (produção: 120 675 480 B) |
| Duração | **75 s** |

**O guard anti-duplicate-symbol dos overrides não deu aviso nenhum** — nem `DEFINICAO FORTE ja'
no lift` (que desligaria os overrides em silêncio), nem `o lift nao tem wrapper fraco` (o NO-OP
silencioso). Compilou com os 4 nomeados. Confirmado no binário:

```
$ nm boot_gow2_v3e2e | grep -E 'midasm|__imp_func_(00010230|0002F3F0|000CE03C|002C0498)'
T _gow2_midasm_Ce03cWaitIdle
T __Z19__imp_func_00010230P11ppu_context     T __Z19__imp_func_0002F3F0P11ppu_context
T __Z19__imp_func_000CE03CP11ppu_context     T __Z19__imp_func_002C0498P11ppu_context

$ grep -rl 'gow2_midasm' recomp_macos_v2/       # CONTROLO: lift de PRODUCAO
(zero ficheiros)
```

### 3. Há avanço face ao baseline? — **NÃO. Há regressão de dois elos.**

**Smoke da intro (etapa 7), contra o baseline T9 do marco:**

| Métrica | Baseline (Fase 16/21) | Este lift | Veredicto |
|---|---:|---:|---|
| `st620_max` | **11** (`0→1→3→3→3→11→11→11`) | **11** (`0 1 3 3 3 11 11 11`) | **igual** |
| `OOB` / `0xFFFF` | 0 | **0** | **igual** |
| `FATAL` | 0 | **0** | **igual** |
| `ICALL-BAD` | 0 | **0** | **igual** |
| `ppu_thread_create` (total) | 14 | **14** | **igual** |
| `sys_ppu_thread_create("AUTO_LOAD")` | **0** | **0** | **igual — não acontece em nenhum dos dois** |
| `func_00242C94` (loop principal) | **0** | **0** | **igual — o boot não lá chega** |
| `boot lifted functions` | 52 068 | **52 142** | delta +74, `INFORMATIVO` |
| órfãos pós-run | 0 | **0** | limpo |
| famílias de tag `[X]` no log | — | **nenhuma perdida** (`comm -3` vazio) | — |

**Nos critérios do `CLAUDE.md` o smoke passa** (`st620_max ≥ 3`, `OOB=0`). E é aí que o smoke
sozinho engana — a lição que criou o `accept_relift.sh`. O elo que interessa está **depois**:

**Cadeia de 5 elos (`smoke_chain_gate.sh`) — candidato vs controlo de produção:**

| | Este lift (`boot_gow2_v3_e2e`, 6 corridas) | **Produção** (`boot_gow2`, 3 corridas, controlo) |
|---|---|---|
| `st620` | 11 em 6/6 | 11 em 2/3 (1 flake a 1) |
| `startseq` (2.º movie) | **1** | **2** |
| `nopic` | **0** | **4** |
| `r_perma` (WAD) | **0** | **1** |
| `thr_created` (AUTO_LOAD) | **0** | **0** |
| **`elo_stopped`** | **`2o movie (StartSeq)` — elo 2, em 6/6** | **`AUTO_LOAD (nunca criada)` — elo 4, em 2/3** |

> **Onde o boot pára, e se é o mesmo sítio de antes: NÃO é o mesmo sítio. É DOIS ELOS ANTES.**
> A produção chega ao elo 4 e morre por a thread `AUTO_LOAD` nunca ser criada. Este lift morre
> no elo 2 — nem sequer arranca o 2.º movie em condições, e o `R_PermA` nunca abre (`r_perma=0`
> contra `1`).

**A resposta directa à pergunta do utilizador sobre a `AUTO_LOAD`: não, `sys_ppu_thread_create("AUTO_LOAD")`
não acontece — nem neste lift nem na produção** (`thr_created=0` em 6/6 e em 3/3). E o loop
principal `func_00242C94` tem **0** ocorrências em ambos os logs. Isto **não** é regressão deste
re-lift: é a parede que já lá estava.

---

## 4. Etapa 4 — o ponto exacto onde a sequência falha

`rc=1`, 217 s. **140 patches**, todos corridos (`SKIP_LIST` vazio):

| Estado | N |
|---|---:|
| `APPLIED` | 114 |
| `ALREADY-APPLIED` | 5 |
| `UNVERIFIED` | 13 |
| `FAILED` | 7 |
| `FAILED-PARTIAL` | 1 |
| **`NO-MATCH`** | **0** |

**O critério da canónica é «zero `NO-MATCH` e zero `FAILED`/`FAILED-PARTIAL` fora de `PROBE`».**
`NO-MATCH` está a zero. Os `FAILED` **não** estão:

| Patch | Estado | Classe | Causa medida |
|---|---|---|---|
| `patch_2b3d1c_movie_io.py` | `FAILED` | `FUNCIONAL` | **ORDEM.** *«preambulo F2B (`f2b_fo_mfd_get`) ausente de `ppu_recomp_001.cpp` — Corre `patch_f2b_multimb_install.py` primeiro»*. Correu na **linha 144** do log; o instalador de que depende correu na **linha 289**, e `APPLIED` com sucesso. Ordem alfabética (`2b3d1c` < `f2b`), dependência não honrada |
| `patch_b71_cb56c_reuse_block.py` | `FAILED-PARTIAL` | `FUNCIONAL` | **DERIVA DE FORMA.** *«`func_000B71B8` existe mas o corpo/âncora gerado NÃO é o esperado. O lifter mudou de forma. Não substituo às cegas»*. Escreveu `func_000CB56C` (31 linhas) e só depois falhou |
| `patch_b71_skip_icallb_reuse.py` | `FAILED` | `FUNCIONAL` | **CASCATA** do anterior — `MISSING: g_b71_product_reused` (ausente nos 7 chunks) |
| `patch_24e3d0_null_product_gate.py` | `FAILED` | `FUNCIONAL` | **DERIVA DE FORMA** — `MISSING agulha da escrita do tipo em func_0024E3D0` |
| `patch_fios_done_yield.py` | `FAILED` | `FUNCIONAL` | **DERIVA DE FORMA** — needle não encontrada, `SKIP` nos 7 chunks |
| `patch_fios_host_pop.py` | `FAILED` | `FUNCIONAL` | **DERIVA DE FORMA** — `needle not found (func_0030D5CC op_alloc probe close)` |
| `patch_ce03c_pre_play_stop.py` | `FAILED` | **`PROBE`** | fora do gate, por desenho |
| `patch_ce03c_wait_idle_f2b_movie.py` | `FAILED` | **`PROBE`** | fora do gate, por desenho |

**6 falhas fora de `PROBE`, com 3 causas-raiz distintas:** 1 de ordem, 4 de deriva de forma do
lifter, 1 de cascata. **Nenhuma foi forçada** — a canónica diz *«um `FAILED` não se força»*, e não
se forçou.

**Porque é que produção não vê isto:** `recomp_macos_v2` tem estes fixes injectados de corridas
antigas, quando o lifter ainda emitia a forma que as needles esperam. Os patches são idempotentes
e dizem `ALREADY-APPLIED`; ninguém volta a testá-los contra um lift fresco. **Foi preciso correr a
sequência inteira para os apanhar.** É exactamente o valor de ter corrido 1→8 de ponta a ponta.

---

## 5. Etapa 5 — `verify_lift.sh` apanhou a mesma perda, antes do boot

`rc=1`, 37 s. Dos 3 passos, 2 verdes:

```
lift_parity          PASS   current=76 baseline=77  novos=0  resolvidos=1
                            RESOLVIDO 0x002C0498/CALL_MISMATCH   <- o weak override a funcionar
MANIFEST             FAIL   current=7  baseline=36  novos=7  resolvidos=36
audit_boundaries     PASS   current=180 baseline=180 novos=0 resolvidos=0
```

As 7 dívidas novas do `MANIFEST` são, **uma a uma**, a assinatura dos 6 patches falhados:

```
A MENOS  PREAMBLE g_trampoline_fn                (esperado >=168753, encontrado 168435)
A MENOS  SYM      ps3_factory_freelist_replenish (esperado >=3,      encontrado 1)
A MENOS  SYM      ps3_factory_repair_vt          (esperado >=5,      encontrado 3)
A MENOS  SYM      ps3_factory_reuse_product      (esperado >=3,      encontrado 1)
A MENOS  SYM      ps3_mp_on_enter                (esperado >=17,     encontrado 16)
A MENOS  TAG      [INTROSEQ]                     (esperado >=18,     encontrado 10)
A MENOS  TAG      [POSTINTRO]                    (esperado >=20,     encontrado 5)
```

**O gate funcionou como desenhado.** Detectou estaticamente, em 37 s e antes de qualquer boot,
exactamente a perda que a perna 4 viria a confirmar in-boot 15 minutos depois. Isto é a lição de
2026-07-26 a pagar-se: nessa altura um lift passou o smoke com `st620=11` em 6/6 e foi promovido
com 36 conversões OPD e 9 famílias de marcador em falta. Hoje o mesmo tipo de perda foi apanhado
**antes** da promoção, e a promoção **não** aconteceu.

Também vale registar as **melhorias**, que o gate por delta não pune: `resolvidos=36` no
`MANIFEST` (o grupo `opd-dispatch` inteiro), `resolvidos=31` nos `UNVERIFIED`, e o
`0x002C0498/CALL_MISMATCH` do `lift_parity` — este último é o `[[functions_override]]` weak da
Fase 19 a resolver, no lift novo, uma divergência que o baseline tinha congelada.

---

## 6. Etapa 3 — a prova de que o marco v1.3 **funcionou**

Esta é a parte boa, e é medida, não narrada. A etapa 3 manda **não** reaplicar à mão os 4 patches
`migrated`. O teste é se a dupla injecção acontece na mesma.

**Antes da etapa 4** (lift acabado de sair do lifter):

| Marcador do patch | Ocorrências |
|---|---:|
| `CE03C wait-idle 1st movie` | **0** |
| `CE03C movie_done reset` | **0** |
| `B71 2F3F0 guard` | **0** |
| `FIOS play already active` | **0** |

**Depois da etapa 4** (`apply_all_patches.sh` correu os 140, incluindo estes 4):

| Patch | Estado reportado | Marcador no lift, **depois** | Marcador em **produção** |
|---|---|---:|---:|
| `patch_ce03c_introseq_block.py` | `ALREADY-APPLIED` | **0** | 1 |
| `patch_ce03c_movie_done_reset.py` | `ALREADY-APPLIED` | **0** | 0 |
| `patch_b71_2f3f0_guard.py` | `ALREADY-APPLIED` | **0** | 0 |
| `patch_fios_play_already_active.py` | `ALREADY-APPLIED` | **0** | 0 |

**Zero dupla injecção, confirmado em lift completo.** `ALREADY-APPLIED` significa, pela definição
do próprio script, *«`rc=0`, conteúdo não mudou, E a pós-condição É VERDADE»* — a pós-condição é
satisfeita **pelo mecanismo**, não pelo texto do patch. A escada A/B/C da Fase 19 tinha medido
isto sobre re-lifts; aqui repete-se dentro da sequência canónica completa.

**E — o que o marco v1.3 tinha declarado NÃO-PROVADO — o mid-asm disparou in-boot:**

```
$ grep -inE 'INTROSEQ' /tmp/e2e/step7_smoke.log
3785:[INTROSEQ] CE03C wait-idle 1st movie st620=1
3794:[INTROSEQ] CE03C wait tick st620=3 i=0
3799:[INTROSEQ] CE03C wait tick st620=3 i=40
...
3820:[INTROSEQ] CE03C arm +0x714 st=10
```

Estas 7 linhas vêm do **corpo host** `hooks/gow2_midasm_hooks.cpp:169,175,189` — **não** do patch,
cujo marcador está a **0** neste lift. O baseline T9 do marco imprime **as mesmas 7 linhas**, mas
vindas do texto injectado pelo `patch_ce03c_introseq_block.py`. **Mesmo comportamento observável,
origem diferente** — que é a definição exacta de «migrado com sucesso».

A ressalva 1 do marco v1.3 dizia: *«o smoke T9 corre o binário de produção, logo prova
não-regressão da intro e **não** o mid-asm em execução»*. **Essa metade fecha aqui:** o mid-asm
foi observado a correr num boot real. A outra metade — **estar em produção** — continua aberta,
porque não houve promoção (e não devia ter havido, com o aceite a `rc=1`).

---

## 7. Etapa 8 — o aceite, e a discrepância que ele revelou

```
PERNA 1 (smoke)          PASS   (OK=5/6, limiar >=4)   run2 flake st620_max=0
PERNA 2 (verify_lift)    FAIL   (rc=1, MANIFEST)
PERNA 3 (apply_patches)  FAIL   (NO-MATCH=0  FAILED-fora-PROBE=5  UNVERIFIED=102 informativo)
PERNA 4 (chain gate)     FAIL   (OK=0/6, elo_stopped: 2o movie (StartSeq))
CONTADORES (D-5.2)       PASS   (imp_modules=13 imp_imports=151 orfaos=0, delta 0 nos três)
REJEITADO: rc=1
```

**Perna 1 verde é a armadilha, e o script sobreviveu a ela.** 5/6 acima do limiar — melhor do que
o critério exige — e mesmo assim o aceite rejeita, porque as pernas 2/3/4 mediram a perda que o
smoke não vê. É a lição de 2026-07-26 a funcionar em produção.

**Contadores bloqueantes todos a delta 0.** `imp_modules` 13→13, `imp_imports` 151→151, `orfaos`
0→0. Os informativos: `function_table_count` 51 917→51 991 e `boot_lifted_functions`
52 068→52 142, ambos **+74**. Esse +74 fica **por explicar** — é dívida desta corrida (§9).

### Dois defeitos do processo, encontrados por ter corrido a sequência

**D1 — `RELIFT=1` compila antes de a etapa 4 correr.** A etapa 2 da canónica diz *«`RELIFT=1`
regenera o lift **e** compila/linka a seguir (funde as etapas 2 e 6)»*, e a etapa 6 diz *«já feita
pelo `RELIFT=1`»*. Mas a etapa 4 (`apply_all_patches.sh`) vem **entre** as duas. Seguir a forma
fundida à letra produz um binário **sem os 114 patches `APPLIED`** — e o `build_macos.sh` só
recompila chunks com `.o` obsoleto, por isso quem não voltasse a correr o build ficaria com um
binário silenciosamente errado. **Usei a forma separada, que o próprio documento oferece.** A
canónica deve deixar de apresentar a forma fundida como o caminho principal, ou dizer
explicitamente que obriga a um segundo `build_macos.sh` depois da etapa 4.

**D2 — o `accept_relift.sh` não conta `FAILED-PARTIAL`.** A canónica define o critério da perna 3
como *«zero `NO-MATCH` e zero `FAILED`/`FAILED-PARTIAL` fora da classe `PROBE`»*. O script
reportou `FAILED-fora-de-PROBE=5`; o TSV tem **6** (5 `FAILED` + 1 `FAILED-PARTIAL`, o
`patch_b71_cb56c_reuse_block.py`, classe `FUNCIONAL`). Um `FAILED-PARTIAL` é **pior** que um
`FAILED` — deixou a árvore meio escrita (`func_000CB56C` aplicado, `func_000B71B8` não) — e
escapa à contagem do gate. Aqui não alterou o veredicto (a perna já falhava por outros 5), mas um
lift em que a **única** falha fosse um `FAILED-PARTIAL` **passaria a perna 3 indevidamente**.

**Nota lateral, sem consequência:** a perna 3 correu o `apply_all_patches.sh` uma **segunda** vez
sobre o mesmo lift e reportou `UNVERIFIED=102` (contra 13 na etapa 4). Não é regressão — é a
assinatura da idempotência: na 2.ª passagem quase tudo é `ALREADY-APPLIED` sem mudança de
conteúdo, e os patches sem contrato declarado caem para `UNVERIFIED`. **`NO-MATCH` continuou a 0
nas duas passagens** — a árvore não foi corrompida pela reaplicação.

---

## 8. Higiene (G6) — cumprida

| Regra | Estado |
|---|---|
| Directório de lift **novo**, nunca por cima de `recomp_macos_v2` | **cumprido** — `recomp_macos_v3_e2e`, criado do zero |
| Produção intacta | **cumprido** — `recomp_macos_v2` e `boot_gow2` não tocados; produção só foi **lida** (controlo da §3) |
| Kill por **PID** (`TERM` → `-9`) | **cumprido** — 16 boots: 1 (etapa 7) + 6 (perna 1) + 6 (perna 4) + 3 (controlo de produção) |
| **Nunca** `pkill -f boot_gow2` | **cumprido** — nenhuma invocação |
| Órfãos no fim | **0** (`pgrep -f boot_gow2` = 0) |
| Logs fora dos dois repos | **cumprido** — `/tmp/e2e/*` e `/tmp/chain_gate_*` |
| Promoção | **NÃO FEITA** — `promote_lift.sh` não invocado; é gate humano à parte |
| Nada de dados de jogo, lifts ou binários commitados | **cumprido** — só este `.md` |
| `sticky_pub>=1` como critério | **não usado** — não é observável neste build (ressalva 5 do marco) |

---

## 9. O que ficou por exercitar

Escrito para não ser lido como se estivesse coberto:

| # | Item | Porquê ficou de fora |
|---|---|---|
| 1 | **`VERIFY_ORACLE=1`** (4.º passo, opt-in da Fase 20) | Não corrido. O `verify_lift` já falhava no passo 2; o oráculo mede fronteiras I4/I5, que o passo 3 já deu `novos=0`. Fica **não-exercitado**, não presumido verde |
| 2 | **A causa do delta `+74` funções** | `INFORMATIVO` no gate D-5.2, portanto não bloqueou — e não a investiguei. Candidato natural: os 6 patches falhados injectam/reescrevem corpos. **Por explicar** |
| 3 | **`RELIFT=1 ./build_macos.sh` na forma fundida** | Deliberadamente **não** corrida, pela razão D1 da §7. Logo o caminho fundido continua **não-exercitado de ponta a ponta** |
| 4 | **`bytes_read=20169344`** (`patch_fallthrough_2550c8.py`) | Continua por correr — exige `PS3_MOVIE_EOS=1` até ao `R_PermA`. E este lift nem chega lá (`r_perma=0`) |
| 5 | **`analyze_eboot_ghidra.sh`** headless | Não corrido (etapa 1 saltada, fronteiras inalteradas) |
| 6 | **Fix das 6 falhas da etapa 4** | Diagnosticadas, **não corrigidas**. Corrigi-las é trabalho de outro plano — esta corrida é uma medição, e forçar um `FAILED` é exactamente o que a canónica proíbe |
| 7 | **As 4 paredes da Fase 11** | **Nenhuma foi tocada.** `func_002545B0`, `func_002182A4`, `func_002547AC`, `func_0041F700` continuam abertas. Nada nesta corrida é uma afirmação sobre pixels, shaders ou `SHADERSRC` |

---

## 10. O que fazer a seguir, por ordem de valor

| # | Trabalho | Fecha |
|---|---|---|
| 1 | **Corrigir a ordem de dependência do `apply_all_patches.sh`** — `patch_f2b_multimb_install.py` antes de `patch_2b3d1c_movie_io.py`. É a falha mais barata das 6, e o próprio patch diz o que falta | 1 das 6 |
| 2 | **Regenerar as 4 needles com deriva de forma** contra este lift (`b71_cb56c`, `24e3d0`, `fios_done_yield`, `fios_host_pop`) — a mensagem de erro do `b71_cb56c` já manda fazê-lo | 4 das 6 (+1 em cascata) |
| 3 | **Contar `FAILED-PARTIAL` na perna 3 do `accept_relift.sh`** (defeito D2) | buraco de gate |
| 4 | **Corrigir a etapa 2/6 do `RELIFT_CANONICAL.md`** (defeito D1) | documento enganador |
| 5 | **Re-correr 1→8** depois de 1+2 e ver se o `elo_stopped` volta a `AUTO_LOAD` — se voltar, o corpus de patches passa a ser reproduzível a partir do EBOOT | o objectivo real |
| 6 | Explicar o delta `+74` de funções | dívida da §9 |

**Só depois destes é que faz sentido falar de promoção.** E a promoção continua a ser decisão
humana, com gate próprio, fora desta sequência.

---

## 11. Nível de evidência (regra 4 do `CLAUDE.md`)

| Item | Nível |
|---|---|
| Etapas 2, 4, 5, 6 — `rc` e durações | **medido** nesta corrida |
| Emissão dos 3 mecanismos no mesmo lift (`grep`/`nm`) | **medido offline** nesta corrida |
| Dupla injecção = 0 nos 4 patches `migrated` | **medido offline** nesta corrida |
| Mid-asm a disparar (7 linhas `[INTROSEQ]` do hook host) | **medido in-boot** nesta corrida |
| Smoke da intro (`st620_max=11`, `OOB=0`, `AUTO_LOAD=0`) | **medido in-boot** nesta corrida |
| `elo_stopped` do candidato (`2o movie`, 6/6) | **medido in-boot** nesta corrida |
| `elo_stopped` da produção (`AUTO_LOAD`, 2/3) | **medido in-boot** nesta corrida (controlo, 3 corridas) |
| Baseline T9 (`st620_max=11`, 14 threads, `AUTO_LOAD=0`) | **relido** de `/tmp/m21_T9_smoke.log` (Fase 21), não re-corrido |
| `VERIFY_ORACLE=1` | **não-exercitado** — razão na §9 |
| Causa do delta `+74` | **não-exercitado** — razão na §9 |
| Correcção das 6 falhas | **não-exercitado** — fora de âmbito desta medição |

---

## Referências

- `docs/RELIFT_CANONICAL.md` — a sequência de 8 etapas (§7 pode agora passar de **NÃO-EXERCITADA** a medida)
- `games/gow2/notes/milestone-2026-08-xenon-re-results.md` — baseline e as 10 ressalvas (a 2 fecha aqui; a 1 fecha a metade in-boot)
- `games/gow2/accept_relift.sh` — as 4 pernas + contadores
- `games/gow2/verify_lift.sh` — os 3 passos + oráculo opt-in
- `games/gow2/lift_baseline/PATCH_MIGRATION.tsv` — ledger patch→mecanismo
- Logs desta corrida (não versionados): `/tmp/e2e/step{2,4,5,6,7,8}_*.log`, `/tmp/e2e/relift_status.tsv`, `/tmp/e2e/accept_recomp_macos_v3_e2e_chain.tsv`, `/tmp/e2e/chain_producao.tsv`
