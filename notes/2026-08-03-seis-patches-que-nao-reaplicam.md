# Os 6 patches que não reaplicam a um lift fresco — análise offline

**Data:** 2026-08-03 · **Modo:** só leitura, **zero builds, zero boots**, zero promoções
**Objecto:** os 6 `FAILED`/`FAILED-PARTIAL` fora de `PROBE` da etapa 4 do E2E de 2026-08-02
**Fontes medidas:** `../gow2-recomp/recomp_macos_v3_e2e/` (lift do E2E, ainda em disco),
`../gow2-recomp/recomp_macos_v2/` (produção, só lida), `/tmp/e2e/*.log` + `*.tsv` (logs do E2E,
ainda em disco), `recomp_mid_v2/patch_*.py`, `games/gow2/lift_baseline/*`
**Nada foi corrigido.** Nem patches, nem scripts, nem baselines. Isto é um diagnóstico.

Continuação directa de [`2026-08-02-e2e-relift-completo.md`](2026-08-02-e2e-relift-completo.md).

---

## Veredicto directo

> **Nenhum dos 6 falha por deriva de forma do lifter. Zero. O lifter não mudou.**
> 4 falham por **ordem** (dependem de texto que outro patch escreve mais tarde no glob),
> 1 falha por **contaminação da âncora** (dois patches injectam *dentro* da função-alvo
> **antes** dele), 1 é **cascata**. E um sexto — o `24e3d0` — **falha exactamente igual
> contra a produção**: nunca esteve no lift de produção, logo não é regressão nenhuma.

A categorização da §4 do E2E (*«4 por deriva de forma do lifter»*) foi transcrita das
**mensagens de erro dos próprios patches**. Essas mensagens são a *hipótese* que o autor do
patch escreveu — não uma medição. Medido agora, a hipótese é **falsa** nos 4 casos.

**Consequência prática, e é a mais importante deste documento:** **3 dos 6 curam-se
sozinhos com uma segunda passagem do `apply_all_patches.sh`** — e a segunda passagem
**já correu** (a perna 3 do aceite). O lift `recomp_macos_v3_e2e` que está em disco **já
tem** o `AREAD-HLE`, o `FIOS-HOST-POP` e o `FIOS-DONE-YIELD` aplicados. O binário
`boot_gow2_v3e2e` foi linkado às 23:16, **19 minutos antes** disso, e é por isso um binário
que **nunca** exercitou esses três fixes. O elo 2 medido no E2E foi medido sobre um binário
a que faltava toda a cadeia FIOS/movie-io.

---

## 1. A tabela dos 6

Ledger: `games/gow2/lift_baseline/PATCH_MIGRATION.tsv` (colunas na linha 86).
`classe` tem **dois eixos** e o E2E citou o do catálogo: no `PATCH_MIGRATION.tsv` os seis são
`CORRECTNESS`; no `PATCH_CATALOG.tsv` (que é o que o gate lê) são `FUNCIONAL`. Não há
contradição — são taxonomias diferentes do mesmo ficheiro. Ambas aqui.

| # | Patch | Ledger | `ea` | `alvo`/`prio` | `estado` | Categoria **medida** | Cura na 2ª passagem? |
|---|---|---|---|---|---|---|---|
| 1 | `patch_2b3d1c_movie_io.py` | L119 · `CORRECTNESS` / `FUNCIONAL:misc` | `0x002B3D1C` | — / — | `todo` | **ORDEM** | **SIM** (`APPLIED`) |
| 2 | `patch_fios_done_yield.py` | L160 · `CORRECTNESS` / `FUNCIONAL:fios` | `0x00306534` | — / — | `todo` | **ORDEM** | **SIM** (`APPLIED`) |
| 3 | `patch_fios_host_pop.py` | L169 · `CORRECTNESS` / `FUNCIONAL:fios` | `-` | — / — | `todo` | **ORDEM** | **SIM** (`APPLIED`) |
| 4 | `patch_b71_cb56c_reuse_block.py` | L133 · `CORRECTNESS` / `FUNCIONAL:misc` | `0x000CB56C` | — / — | `todo` | **CONTAMINAÇÃO DA ÂNCORA** | **NÃO** |
| 5 | `patch_b71_skip_icallb_reuse.py` | L134 · `CORRECTNESS` / `FUNCIONAL:misc` | `-` | — / — | `todo` | **CASCATA de #4** | **NÃO** |
| 6 | `patch_24e3d0_null_product_gate.py` | L102 · `CORRECTNESS` / `FUNCIONAL:misc` | `0x0024E3D0` | — / — | `todo` | **AGULHA NÃO-ÚNICA — falha também contra produção** | **NÃO** (e não precisa) |

Nenhum dos seis tem `alvo`, `prioridade` ou `aceite` preenchidos, e **nenhum tem contrato
declarado** em `CONTRACTS.tsv` (grep dos 6 → vazio). É por isso que caem para `UNVERIFIED`
quando não falham, e é uma dívida à parte.

---

## 2. Patch a patch — porque falha, com prova

### #1 `patch_2b3d1c_movie_io.py` — ORDEM

**Agulha.** Não é a agulha que falha: é a **pré-condição**. O patch exige
`static unsigned f2b_fo_mfd_get` no **mesmo chunk** de `func_002B3D1C`
(`patch_2b3d1c_movie_io.py:146-147`, `:160-161`), senão recusa com `rc=2` (`:198-203`).

**Prova.** `f2b_fo_mfd_get` **não é código do lifter** — é preâmbulo host injectado por
`patch_f2b_multimb_install.py` (`grep -l` nos 140 patches devolve só instaladores, nunca o
lifter). E a ordem do glob põe-nos ao contrário:

```
glob #33  patch_2b3d1c_movie_io.py         <- corre AQUI  (step4_patches.log:144)
glob #62  patch_f2b_multimb_install.py     <- instala a dependência (step4_patches.log:289)
```

O log é literal: `ERRO: preambulo F2B (f2b_fo_mfd_get) ausente de ppu_recomp_001.cpp --
o bloco AREAD-HLE chamaria simbolos indefinidos. Corre patch_f2b_multimb_install.py primeiro`.

**Estado do lift hoje** (medido, pós-2ª passagem): `func_002B3D1C` e o preâmbulo F2B estão
**ambos** em `ppu_recomp_001.cpp`, âncora `AREAD-PROBE` presente **1×**, marcador `AREAD-HLE`
**presente**. Ou seja: a 2ª passagem aplicou-o (`accept_..._patches.log:42 APPLIED`).
**A forma do lifter está exactamente onde o patch a espera.**

| Opção | Custo | Veredicto |
|---|---|---|
| (a) reancorar | não se aplica — a âncora está boa | — |
| (b) mid-asm | mau encaixe: o bloco faz `return` antecipado com `gpr[3]=got`; um hook mid-asm corre **ao lado**, não pode saltar o corpo natural | não |
| (c) weak override | possível (é um early-out no topo de uma função inteira, o padrão do `func_000CE03C`) mas puxa `movie_io_is`/`f2b_fo_mfd_get`/`ps3_fios_aread_hle` para host — trabalho médio | futuro |
| **(d) ordem** | **1 linha de declaração de ordem**; o patch já diz o que falta na mensagem de erro | **RECOMENDADO** |

**Recomendação: (d).** É a falha mais barata das seis e a mensagem de erro já é a receita.
A migração para weak override (c) é o destino certo a prazo — `func_002B3D1C` é uma função
inteira com early-out —, mas não é isto que bloqueia o re-lift hoje.

---

### #2 `patch_fios_done_yield.py` — ORDEM

**Agulha.** Uma regex sobre o `if`+publish do done-word (`patch_fios_done_yield.py:44-47`):

```
if (((uint32_t)ctx->gpr[11]) != 0u)
    ps3_fios_sticky_publish((uint32_t)ctx->gpr[31]);
```

**Prova.** `ps3_fios_sticky_publish` **não é emitido pelo lifter** — é injectado em
`func_00306534` por `patch_fios_sticky.py`. E a ordem está ao contrário:

```
glob #74  patch_fios_done_yield.py     <- corre AQUI  (step4_patches.log:348, SKIP nos 7 chunks)
glob #87  patch_fios_sticky.py         <- escreve a âncora  (step4_patches.log:404, APPLIED)
```

O docstring do patch afirma que a âncora *«já está presente no lift actual»* — verdade em
`recomp_macos_v2`, onde o `patch_fios_sticky.py` já correu numa vida anterior. Num lift
fresco não está, e nunca estará no slot 74.

**Estado do lift hoje:** âncora presente **1×**, marcador `FIOS-DONE-YIELD` **presente**
(aplicado na 2ª passagem, `accept_..._patches.log:105 APPLIED`).

| Opção | Custo | Veredicto |
|---|---|---|
| (a) reancorar | inútil: reancorar contra o quê? A âncora é texto de outro patch | não |
| (b) mid-asm | **bom encaixe conceptual** — é literalmente um bloco que corre *ao lado* de uma instrução (release/yield/acquire logo após o publish). Mas o sítio é definido pela injecção do `fios_sticky`, não por um EA de instrução; exigiria migrar **os dois** juntos | a prazo |
| (c) weak override | mau: não substitui a função, insere no meio dela | não |
| **(d) ordem** | **1 linha** | **RECOMENDADO** |

**Recomendação: (d)** agora; **(b) para os dois juntos** (`fios_sticky` + `fios_done_yield`)
quando houver plano de migração FIOS. Migrar só um deles não resolve — o par é indivisível.

---

### #3 `patch_fios_host_pop.py` — ORDEM

**Agulha.** Regex sobre o fecho do bloco de trace `FIOS-OPEN-PROBE(op_alloc)`
(`patch_fios_host_pop.py:62-65`), cuja assinatura é a string `<-- SEM OP LIVRE (F2a)`.

**Prova.** Essa string é injectada por `patch_fios_open_probe.py` — que corre **uma posição
depois**:

```
glob #83  patch_fios_host_pop.py     <- corre AQUI  (step4_patches.log:380, SKIP nos 7 chunks)
glob #84  patch_fios_open_probe.py   <- escreve a âncora  (step4_patches.log:389, APPLIED)
```

**Uma posição.** O comentário do próprio patch (`:58-61`) diz que a âncora é *«suficientemente
específica mesmo sem exigir o nome da função»* — e é; o problema nunca foi especificidade.

**Estado do lift hoje:** âncora presente **1×**, marcador `FIOS-HOST-POP` **presente**
(2ª passagem, `accept_..._patches.log:121 APPLIED`).

**Detalhe que agrava:** um patch de classe `FUNCIONAL` e no gate depende de um patch de classe
**`PROBE`**, que está **fora** do gate por desenho. Se alguém desligar as probes, o
`fios_host_pop` deixa de aplicar e o gate não sabe porquê.

| Opção | Custo | Veredicto |
|---|---|---|
| (a) reancorar | **vale a pena além da ordem**: reancorar em código do **lifter** dentro de `func_0030D5CC` em vez do texto de uma probe. Custo médio, remove a dependência `FUNCIONAL→PROBE` | **sim, a seguir** |
| (b) mid-asm | encaixe razoável (bloco ao lado, logo após o `op_alloc`), mas precisa do EA da instrução — o ledger tem `ea=-` para este patch | a prazo |
| (c) weak override | não: insere no meio de `func_0030D5CC` | não |
| **(d) ordem** | **1 linha** | **RECOMENDADO já** |

**Recomendação: (d) agora + (a) a seguir.** A dependência `FUNCIONAL → PROBE` é frágil por
construção e devia desaparecer, mesmo com a ordem certa.

---

### #4 `patch_b71_cb56c_reuse_block.py` — CONTAMINAÇÃO DA ÂNCORA (**não** é deriva do lifter)

Este é o único dos seis que **bloqueia mesmo** a reprodução da produção. E é o que estava pior
diagnosticado.

**O que o patch faz.** Substitui o **corpo inteiro** de `func_000B71B8` (253 linhas geradas →
~300 com o bloco) e insere um bloco em `func_000CB56C`. Antes de substituir, exige
`CLEAN_BODY_B71 in t` — uma comparação de **string exacta e contígua** de 253 linhas
(`patch_b71_cb56c_reuse_block.py:97`, teste em `:140-141`). Se não casar, recusa com
`rc=2` e a mensagem *«O lifter mudou de forma»* (`:186-190`).

**A mensagem está errada. Medido:**

```
corpo actual (recomp_macos_v3_e2e/ppu_recomp_000.cpp, func_000B71B8): 843 linhas
CLEAN_BODY_B71 esperado:                                              252 linhas
CLEAN_BODY_B71 exacto presente no chunk?                              False
linhas do corpo ESPERADO ausentes (em ordem) do corpo actual:         0 de 253   <-- ZERO
linhas do corpo ACTUAL estranhas ao esperado:                         590
   destas, com aparência de código LIFTADO (não-scaffolding):         0
```

**As 253 linhas que o patch espera estão lá, todas, na ordem certa.** O codegen do lifter é
idêntico ao de 2026-07-25: os temporários callee-save `_cs_28`…`_cs_31`, o
`vm_write64(ctx->gpr[1] + -0x110, ...)`, o `ctx->lr = 0x000B71D8; func_002BA4B4(ctx);` — tudo
verbatim. **O lifter não derivou.**

O que quebra a contiguidade são **590 linhas injectadas por outros patches dentro da função**:

| Injecção | Blocos | Quem | Glob | Classe |
|---|---:|---|---:|---|
| `B71-CALLSITE-TRACE` | **63** | `patch_b71_callsite_trace.py` | **#46** | `PROBE` |
| `ALCHAIN-PROBE` | 1 | `patch_autoload_chain_probes.py` | **#44** | `FUNCIONAL` |
| `FLIPPATH-PROBE` | 2 | `patch_flip_path_enter_probe.py` | #91 | `PROBE` |
| `INTROSEQ-PROBE` | 1 | `patch_introseq_probe.py` | #96 | `PROBE` |
| `MENUPRESENT-PROBE` | 1 | `patch_menu_present_schedule_probe.py` | #101 | `PROBE` |
| `POSTTHR-PROBE` | 1 | `patch_postthr_pc_probe.py` | #104 | `PROBE` |

O docstring do próprio patch declara a premissa (`:38-45`): *«O que NÃO instala (tem escritor
próprio): POSTTHR-PROBE, MENUPRESENT-PROBE, FLIPPATH-PROBE, INTROSEQ-PROBE … **Todos correm
DEPOIS deste script e reinserem-se sozinhos.**»* — e a premissa é verdadeira para esses quatro
(#91, #96, #101, #104, todos > #47). **Falha para dois que o docstring nem menciona**, e são
precisamente os dois que correm antes:

```
glob #44  patch_autoload_chain_probes.py    APPLIED  (step4_patches.log:197)
glob #46  patch_b71_callsite_trace.py       APPLIED  (step4_patches.log:202)
glob #47  patch_b71_cb56c_reuse_block.py    FAILED-PARTIAL (step4_patches.log:211)
```

O `patch_b71_callsite_trace.py` marca **cada chamada dentro do B71** — 63 blocos espalhados
por todo o corpo. Nenhuma comparação contígua sobrevive a isso.

**A metade parcial.** Escreveu `func_000CB56C` (31 linhas, marcadores `PS3_TYPE15_CB56C` e
`was_shell=%d` presentes no lift) e só depois falhou no B71. É o `FAILED-PARTIAL`. Na 2ª
passagem degrada para `FAILED` limpo (nada mais a escrever) — o sinal de árvore meio escrita
**perde-se**.

**Custo real desta falha** (é praticamente toda a dívida do `MANIFEST`, §4):

| Opção | Custo | Veredicto |
|---|---|---|
| **(d) ordem** | mover `patch_autoload_chain_probes.py` e `patch_b71_callsite_trace.py` para **depois** do `b71_cb56c` — restaura exactamente a premissa que o docstring já declara. **2 entradas numa tabela de ordem.** Risco: continua refém de *qualquer* patch futuro que escreva dentro do B71 | **RECOMENDADO já** — é o desbloqueio mais barato |
| (a) reancorar | reescrever o patch para não usar comparação de corpo inteiro (âncoras pequenas + edições dirigidas). Trabalho alto (o bloco altera ~8 sítios distintos, incluindo os dois `ps3_indirect_call`) e volta a partir | não |
| (b) mid-asm | **não encaixa.** O bloco *substitui* despacho: salta o `icallB`, troca o `ps3_indirect_call` do `icallA` por uma versão guardada, e mete um gate opt-in à volta do `func_000393E0`. Um hook mid-asm corre **ao lado** de uma instrução — não pode saltar nem substituir | não |
| **(c) weak override** | **encaixe canónico.** É a substituição do corpo de **uma função inteira** — o caso do `func_000CE03C` da Fase 19. `PATCHED_BODY_B71` já é C++ compilável: passa para `games/gow2/hooks/gow2_func_overrides.cpp` como `GOW2_FUNC_OVERRIDE(func_000B71B8)` + `ea = 0x000B71B8` em `[[functions_override]]`. **Custo:** ~300 linhas movidas + 1 entrada no TOML. **Preço:** o corpo liftado fica congelado em host — futuras correcções do lifter para esta função deixam de chegar, e isso tem de ficar escrito | **RECOMENDADO como destino** |

**Recomendação: (d) para desbloquear já, (c) como destino.** Nota para quem executar (c):
o ledger tem `ea=0x000CB56C` nesta linha — a heurística confirmou o EA da **metade errada**.
O EA do weak override é `0x000B71B8`. O patch é, na verdade, **dois patches num ficheiro**;
separá-los é pré-requisito de qualquer migração limpa (`func_000CB56C` fica em patch/mid-asm,
`func_000B71B8` vai a weak).

---

### #5 `patch_b71_skip_icallb_reuse.py` — CASCATA

**É um verificador puro, zero escritas** (`:56-79`). Exige 4 marcadores na união dos chunks.
No E2E (`step4_patches.log:217-222`):

```
MISSING: g_b71_product_reused                 <- do B71,   instalado por #4
MISSING: B71 skip icallB (reuse product       <- do B71,   instalado por #4
ok:      was_shell=%d          -> ppu_recomp_000.cpp   <- do CB56C, a metade que #4 escreveu
ok:      PS3_TYPE15_CB56C      -> ppu_recomp_000.cpp   <- idem
```

**2 de 4 presentes** — a assinatura exacta do `FAILED-PARTIAL` do #4. Confirmado hoje no lift:
`g_b71_product_reused` e `B71 skip icallB` ausentes dos 7 chunks; `PS3_TYPE15_CB56C` e
`was_shell=%d` em `ppu_recomp_000.cpp`.

| Opção | Custo | Veredicto |
|---|---|---|
| corrigir #4 | zero trabalho próprio | **RECOMENDADO** |
| (b)/(c) migrar | não se aplica — não escreve nada; é um gate | não |

**Recomendação: nada a fazer neste ficheiro.** Fecha com #4. Vale, isso sim, **promovê-lo a
contrato** em `CONTRACTS.tsv` — é literalmente uma pós-condição escrita como script, e o
mecanismo de contratos já existe.

---

### #6 `patch_24e3d0_null_product_gate.py` — AGULHA NÃO-ÚNICA, e **não é regressão**

**Agulha.** `vm_write16(ctx->gpr[9] + 0x6, ctx->gpr[0]);` com **exigência de unicidade por
chunk** (`:88`: `if src.count(NEEDLE) != 1: continue`). A agulha **não** é limitada à região de
`func_0024E3D0` — é contada no **chunk inteiro**.

**Prova.** Contagem por chunk, medida nos dois lifts:

| Lift | 000 | 001 | 002 | 003 | 004 | 005 | 006 | Marcador `24E3D0-NULLPROD-GATE` |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `recomp_macos_v3_e2e` (fresco) | 9 | 14 | 5 | 2 | 5 | 0 | 3 | **ausente** |
| `recomp_macos_v2` (**produção**) | 9 | 14 | 5 | 2 | 5 | 0 | 3 | **ausente** |

**Idênticas.** Não há um único chunk com contagem 1, nos dois lifts. O patch dá `MISSING` e
`rc=2` contra a produção **exactamente como contra o lift fresco** — e o marcador
`24E3D0-NULLPROD-GATE` **nunca** entrou no `MANIFEST.tsv` (grep = 0). Isto **não é dívida de
re-lift**: é um patch que nunca aplicou a esta geração de lift, e ninguém reparou porque
`recomp_macos_v2` nunca é re-testado.

**E, mesmo aplicado, não faria diferença nenhuma no boot.** O próprio docstring (`:1-7`):
*«GATE DE DIAGNOSTICO (não é um fix) … OFF por default … nunca deve ser apresentado como
correcção (CLAUDE.md regras 4 e 5)»*. Gate: `PS3_24E3D0_KEEP_TYPE_ON_NULL=1`. Sem a env var
é um `else vm_write16(...)` — no-op comportamental.

| Opção | Custo | Veredicto |
|---|---|---|
| **reclassificar para `PROBE`** | 1 linha na heurística do `gen_catalog.py` (hoje classifica por sufixo `_probe`/`_trace`; este chama-se `_gate` e o corpo é 100% diagnóstico) | **RECOMENDADO** |
| (a) reancorar (tornar a agulha única) | limitar a contagem à região de `func_0024E3D0`, como o `2b3d1c` já faz com `func_span`. ~10 linhas. Só vale se o gate for para usar | opcional |
| (b)/(c) migrar | **não.** Migrar um diagnóstico OFF-por-default para mecanismo permanente é o oposto do que o `CLAUDE.md` (regra 6) manda | não |

**Recomendação: reclassificar para `PROBE`.** Sai do gate, deixa de contaminar a contagem, e a
verdade fica escrita: é um instrumento de diagnóstico, não uma correcção. **Não** contar este
como «patch que falha o re-lift» — a contagem honesta dos que bloqueiam é **5**, não 6, e
depois da ordem passa a **2** (#4 e #5, que são um só).

---

## 3. As 3 categorias, revistas

| Categoria do E2E | Contagem E2E | Contagem **medida** | Correcção |
|---|---:|---:|---|
| ordem de dependência | 1 | **3** | `fios_done_yield` e `fios_host_pop` também são ordem — as agulhas deles são texto de `patch_fios_sticky.py` (#87) e `patch_fios_open_probe.py` (#84) |
| deriva de forma do lifter | 4 | **0** | nenhuma. O `B71` é contaminação da âncora por patches anteriores (prova: 253/253 linhas presentes em ordem); o `24e3d0` é agulha não-única que falha igual em produção |
| cascata | 1 | **1** | confirmado |
| *(novo)* contaminação da âncora | — | **1** | `b71_cb56c` |
| *(novo)* falha também em produção | — | **1** | `24e3d0` |

---

## 4. A que corresponde cada dívida do `MANIFEST` (as 7 do E2E)

Medido hoje, `recomp_macos_v3_e2e` vs `recomp_macos_v2`:

| Dívida do gate | Delta medido | Atribuição **medida** |
|---|---:|---|
| `TAG [POSTINTRO]` (5 vs 20) | **−15** | **#4**, exacto: `PATCHED_BODY_B71` contém **15** ocorrências de `[POSTINTRO]` |
| `SYM ps3_factory_repair_vt` (3 vs 5) | **−2** | **#4**: o call site em `func_000B71B8` + a declaração no chunk 000, que o `patch_zz_host_api_decls.py` só emite se o chunk **usar** o símbolo (`:188 if sym not in text: continue`) |
| `SYM ps3_factory_reuse_product` (1 vs 3) | **−2** | **#4**, mesma mecânica |
| `SYM ps3_factory_freelist_replenish` (1 vs 3) | **−2** | **#4**, mesma mecânica |
| `SYM ps3_mp_on_enter` (16 vs 17) | **0 hoje** | **transitório de ordem** — a 2ª passagem repôs; hoje 17 = 17 |
| `TAG [INTROSEQ]` (10 vs 18) | −8 | **FALSA DÍVIDA — 100 % por desenho.** Ver §5 |
| `PREAMBLE g_trampoline_fn` (168 435 vs 168 753) | −318 | **NÃO ATRIBUÍVEL aos 6.** Distribui-se pelos 7 chunks e **5 deles têm MAIS** que a produção (só o 002 e o 005 têm menos). É a mesma família do delta `+74` funções — dívida do lifter/fronteiras, não do corpus de patches. **Fica por explicar**, como no E2E |

**Leitura:** tirando a falsa dívida e a não-atribuível, **4 das 5 dívidas reais são o patch #4
sozinho.** Corrigir #4 fecha o `MANIFEST` quase todo.

---

## 5. Defeito de processo **#3** (encontrado nesta análise): o baseline do `MANIFEST` não foi
   rebaselinado depois da migração v1.3

A dívida `TAG [INTROSEQ]` (−8) **não é perda de nada**. O `patch_ce03c_introseq_block.py` está
`migrated` no ledger, e os seus 8 marcadores mudaram de casa — do texto do lift para os dois
ficheiros host versionados:

| Marcador `[INTROSEQ]` | Onde vive hoje |
|---|---|
| `CE03C wait-idle 1st movie` | `games/gow2/hooks/gow2_midasm_hooks.cpp` |
| `CE03C wait tick` | `gow2_midasm_hooks.cpp` |
| `CE03C wait-idle exit` | `gow2_midasm_hooks.cpp` |
| `CE03C arm +0x714` | `gow2_midasm_hooks.cpp` |
| `CE03C clear sticky EOS hook` | `gow2_midasm_hooks.cpp` |
| `CE03C Play aborted (FO residual after StartSeq#2)` | `games/gow2/hooks/gow2_func_overrides.cpp:236` |
| `CE03C post-abort freelist rebuild` | `gow2_func_overrides.cpp:279` |
| `CE03C post-abort freelist SKIP` | `gow2_func_overrides.cpp:283` |

**8 de 8 contabilizados. Zero perdidos.** O gate do `MANIFEST` conta marcadores **no texto do
lift** e o baseline foi congelado **antes** das Fases 17/19 — por isso lê uma migração
bem-sucedida como regressão.

**Consequência sistémica:** cada patch que for migrado para mecanismo vai gerar uma dívida
falsa no `MANIFEST`. O mecanismo v1.3 **produz** falsos negativos no gate que devia protegê-lo.

**Fix mínimo:** o `manifest_delta_gate.py` já lê o lift; passar a contar também os ficheiros
host versionados (`games/gow2/hooks/*.cpp`) para as `TAG`, **ou** rebaselinar
`MANIFEST_DEBT_BASELINE.json` a cada migração e registar o rebaseline no ledger. A primeira
opção é a correcta — o baseline por delta não devia depender de disciplina humana.

**Nota lateral, para não ficar por dizer:** os 2 `FAILED` de classe `PROBE` fora do gate
(`patch_ce03c_pre_play_stop.py`, `patch_ce03c_wait_idle_f2b_movie.py`) **também falham contra a
produção** — os seus marcadores próprios têm contagem 0 em `recomp_macos_v2`
(`CE03C pre-Play stop`, `CE03C idle ok`, `CE03C skip Play#2`, `PS3_CE03C_PLAY2`: 0 nos dois
lifts). O segundo declara-o ele próprio: *«sem escritor conhecido no repo (comportamento
ausente, não é bug de agulha)»*. Não são candidatos à regressão do elo 2.

---

## 6. Defeito de processo **D1** — `RELIFT=1` compila antes da etapa 4: **CONFIRMADO**

**Prova estática** (`../gow2-recomp/build_macos.sh`):

- `:49` — `if [ "${RELIFT:-0}" = "1" ]; then`
- `:91-92` — `=== 0. RELIFT=1: regenerando lift ===` → `python3 .../ppu_lifter.py …`
- `:96-98` — se `rc != 0`, `exit`. **Se `rc == 0`, cai a fundo** para `:146 === 1. lifted chunks -> .o` e daí até `:420 === 5. link ===`.

Não há nenhum ponto entre o passo 0 e o passo 1 onde os patches sejam aplicados. **Uma
invocação de `RELIFT=1 ./build_macos.sh LIFT_NEW` produz sempre um binário a partir de um lift
virgem** — sem os 114 `APPLIED` da etapa 4. E como `:156` só recompila chunks com `.o` obsoleto
(`[ "$f" -nt "$o" ]`), quem correr o `apply_all_patches.sh` **depois** e não voltar a chamar o
build fica com um binário silenciosamente errado. Foi por isto que o E2E usou a forma separada.

### Fix mínimo — três níveis, escolher um

| Nível | Mudança | Custo | Risco |
|---|---|---|---|
| **1 — documento (mínimo real)** | `RELIFT_CANONICAL.md` etapa 2 deixa de apresentar a forma fundida como caminho principal: etapa 2 = **só lift** (a «forma explícita equivalente» que já lá está passa a ser a única), e a etapa 6 deixa de dizer *«já feita pelo `RELIFT=1`»* | ~10 linhas de doc, **zero código** | nenhum |
| **2 — guarda no script** | `RELIFT_ONLY=1`: no fim do bloco `:96-98`, `if [ "${RELIFT_ONLY:-0}" = "1" ]; then exit 0; fi`. A canónica passa a ter um comando único para a etapa 2 | **3 linhas** | nenhum (opt-in) |
| 3 — `RELIFT_APPLY=1` | correr `apply_all_patches.sh` entre o passo 0 e o passo 1, opt-in | ~6 linhas | acopla o build ao corpus de patches e faz um script de *build* mutar o lift — a etapa 4 é gate próprio. **Não recomendo como default**, só como opt-in explícito |

**Recomendação: nível 1 + nível 2.** O documento é o que engana; as 3 linhas fecham a armadilha
para quem não o ler. O nível 3 fica de fora — misturar build com aplicação de patches apaga a
fronteira entre «produzir» e «gate», que é justamente o que o `accept_relift.sh` protege.

---

## 7. Defeito de processo **D2** — «`accept_relift.sh` ignora `FAILED-PARTIAL`»: **REFUTADO
   como enunciado. O defeito real é outro, e é pior**

### O que a hipótese dizia

Que o `accept_relift.sh` conta 5 quando o TSV tem 6, por não considerar `FAILED-PARTIAL`.

### O que está no código

`games/gow2/accept_relift.sh:144` (idêntico nas duas cópias — `diff` dá `rc=0`, não há
divergência monorepo/build aqui):

```sh
n_failed_nao_probe=$(awk -F'\t' 'NR>1 && ($2=="FAILED" || $2=="FAILED-PARTIAL") && $3!="PROBE"{n++} END{print n+0}' "$TSV3")
```

**`FAILED-PARTIAL` está lá.** E o `apply_all_patches.sh` escreve-o correctamente no TSV
(`:346`) e conta-o no gate interno (`:376`).

### Porque deu 5 e não 6 — medido

**São dois TSV diferentes, de duas corridas diferentes.** A etapa 4 escreve
`/tmp/e2e/relift_status.tsv`; a perna 3 corre o `apply_all_patches.sh` **outra vez** e escreve
`/tmp/e2e/accept_recomp_macos_v3_e2e_status.tsv`. O mesmo `awk` da linha 144, aplicado a cada
um:

| TSV | `APPLIED` | `ALREADY` | `UNVERIFIED` | `FAILED` | `FAILED-PARTIAL` | **`awk` da :144** |
|---|---:|---:|---:|---:|---:|---:|
| etapa 4 (`relift_status.tsv`) | 114 | 5 | 13 | 7 | 1 | **6** |
| perna 3 (`accept_..._status.tsv`) | 5 | 26 | 102 | 7 | 0 | **5** |

O gate leu **o seu próprio TSV** e contou-o **certo**. O «6» é do TSV da etapa 4, que o gate
nunca vê. A §7 do E2E comparou grandezas de corridas diferentes.

### O defeito real: **a perna 3 muta o artefacto que está a julgar**

`accept_relift.sh:140` corre `apply_all_patches.sh` **por cima de uma árvore que a etapa 4 já
patchou**. Consequências, todas medidas nos dois TSV:

1. **Mascara falhas de ordem.** Os três `ORDEM` (#1, #2, #3) aparecem como **`APPLIED`** na
   perna 3 (`accept_..._patches.log:42, 105, 121`). Se alguém corresse só o aceite, os três
   ficavam invisíveis — sem nunca terem entrado no binário testado.
2. **Inventa falhas novas.** Dois patches que deram `APPLIED` na etapa 4 dão `FAILED` na
   perna 3, por já terem feito o trabalho:
   - `patch_1856a8_stream_opd.py` → `no ps3_indirect_call decl in 000` (era `APPLIED`, `step4:38`)
   - `patch_icg_ctor_opd.py` → `no ps3_indirect_call decl` (era `APPLIED`, `step4:446`)
3. **Apaga o sinal `FAILED-PARTIAL`.** O #4 degrada de `FAILED-PARTIAL` para `FAILED` limpo
   (já escreveu o CB56C na 1.ª passagem, não há mais nada para escrever). **O estado que o
   gate quer apanhar — árvore meio escrita — desaparece precisamente na medição do gate.**
4. **Faz explodir os `UNVERIFIED`** (13 → 102), como o E2E já tinha notado.

Um lift em que a única falha fosse um `FAILED-PARTIAL` **passaria a perna 3** — mas não pela
razão da hipótese: passaria porque a 2ª passagem o converte em `FAILED`… que também é contado.
O que passa mesmo indevidamente é **qualquer falha de ordem**: a 2ª passagem cura-a e o gate
declara verde uma árvore que a 1.ª passagem — a que produziu o binário — não tinha.

### Fix

| Opção | Mudança | Custo | Veredicto |
|---|---|---|---|
| **A — consumir o TSV da etapa 4** | `accept_relift.sh` aceita `--patch-status <TSV>` e, se der, **não corre** o `apply_all_patches.sh`: lê o TSV da corrida que produziu o binário | ~8 linhas | **RECOMENDADO** — o gate passa a julgar o artefacto real |
| B — falhar se a 2ª passagem mudar alguma coisa | comparar `sha256` dos chunks antes/depois da perna 3; qualquer `APPLIED` = FAIL («a árvore não estava convergida») | ~6 linhas | **RECOMENDADO em conjunto com A** — apanha exactamente a classe «ordem» |
| C — não mexer | — | 0 | não: o buraco é real, só não é o que se pensava |

**Recomendação: A + B.** A perna 3 deve verificar **convergência** («aplicar outra vez não muda
nada»), não repetir a aplicação e reportar o resultado da repetição.

**Ressalva honesta:** a hipótese D2 tal como enunciada está refutada, mas a conclusão prática
não muda de sinal — **há um buraco de gate na perna 3, e é maior**. O critério da canónica
(*«zero NO-MATCH e zero FAILED/FAILED-PARTIAL fora de PROBE»*) está bem escrito e bem
implementado; o que está errado é **sobre que árvore** ele é avaliado.

---

## 8. O caminho mais curto para um lift fresco chegar ao elo da produção

Por ordem de custo crescente. **Nenhum destes passos foi executado nesta sessão.**

| # | Passo | Fecha | Custo | Nota |
|---|---|---|---|---|
| **0** | **Rebuild do `recomp_macos_v3_e2e` que já está em disco** e re-correr o `smoke_chain_gate.sh` | mede o efeito real de #1+#2+#3 **sem escrever uma linha de código** | 1 build (~75 s) + 6 boots | A árvore **já tem** `AREAD-HLE`, `FIOS-HOST-POP` e `FIOS-DONE-YIELD` (aplicados pela 2.ª passagem às 23:35); o binário testado é de 23:16 e **não os tem**. É o experimento discriminador mais barato que existe aqui |
| 1 | **Ordem explícita no `apply_all_patches.sh`** — 5 relações: `2b3d1c` depois de `f2b_multimb_install`; `fios_done_yield` depois de `fios_sticky`; `fios_host_pop` depois de `fios_open_probe`; `autoload_chain_probes` e `b71_callsite_trace` **depois** de `b71_cb56c_reuse_block` | **4 das 6** (#1,#2,#3,#4) + #5 em cascata | pequeno | as 3 primeiras curam-se sozinhas na 2.ª passagem, o que confirma o diagnóstico; as 2 últimas restauram a premissa que o docstring do #4 já declara |
| 2 | **Reclassificar `patch_24e3d0_null_product_gate.py` para `PROBE`** | **#6** | 1 linha | é um diagnóstico OFF-por-default que falha igual em produção |
| 3 | Re-correr 1→8 e ver se o `elo_stopped` volta a `AUTO_LOAD` | o objectivo real | 1 sequência | só depois de 1+2 |
| 4 | Perna 3 = **verificação de convergência** (§7, A+B) | buraco de gate | ~14 linhas | sem isto, o passo 3 pode dar verde por má razão |
| 5 | `RELIFT_CANONICAL.md` etapa 2/6 + `RELIFT_ONLY=1` (§6) | documento enganador | ~13 linhas | |
| 6 | `MANIFEST` a contar também `games/gow2/hooks/*.cpp` (§5) | falsa dívida `[INTROSEQ]`, e todas as futuras | médio | |
| 7 | **Migrar #4 para weak override** (`ea = 0x000B71B8`), separando antes o ficheiro em dois | torna a única falha estrutural re-lift-safe | médio-alto | destino, não desbloqueio |
| 8 | Explicar `+74` funções e `g_trampoline_fn` −318 | dívida herdada do E2E | ? | não é dos 6 |

**Hipótese explícita, por medir:** dos 4 fixes ausentes do binário testado, três (`AREAD-HLE`,
`FIOS-HOST-POP`, `FIOS-DONE-YIELD`) são exactamente a cadeia FIOS/movie-io — o `op_alloc` que
devolve a op, o read assíncrono que devolve bytes ao `.m2v`, e a entrega do lock ao poller do
done-word. O E2E parou no **elo 2 (2.º movie / StartSeq)** com `r_perma=0` e `nopic=0`. **A
correspondência é forte, mas é uma hipótese** — só o passo 0 a confirma ou refuta. Não a
escrever como facto.

---

## 9. Nível de evidência (regra 4 do `CLAUDE.md`)

| Item | Nível |
|---|---|
| Ordem do glob dos 140 patches e posições #33/#44/#46/#47/#62/#74/#83/#84/#87 | **medido offline** nesta sessão (`ls patch_*.py`) |
| Quem injecta cada âncora (`f2b_fo_mfd_get`, `ps3_fios_sticky_publish`, `SEM OP LIVRE (F2a)`, `B71-CALLSITE-TRACE`, `ALCHAIN-PROBE`) | **medido offline** (`grep -l` nos 140 patches) |
| 253/253 linhas de `CLEAN_BODY_B71` presentes e em ordem no lift fresco; 0 linhas estranhas com código liftado | **medido offline** (script de subsequência sobre `recomp_macos_v3_e2e/ppu_recomp_000.cpp`) |
| Contagens da agulha do `24e3d0` idênticas em lift fresco e produção; marcador ausente nos dois | **medido offline** |
| `24E3D0-NULLPROD-GATE` ausente de `MANIFEST.tsv` | **medido offline** |
| Estados dos dois TSV (etapa 4 vs perna 3) e o `awk` da `:144` a dar 6 e 5 | **medido offline** sobre `/tmp/e2e/*.tsv` (logs do E2E, não regerados) |
| `APPLIED` dos três `ORDEM` na 2.ª passagem | **relido** de `/tmp/e2e/accept_..._patches.log:42,105,121` |
| `RELIFT=1` cai a fundo para a compilação sem passar pela etapa 4 | **medido offline** (leitura de `build_macos.sh:49-98,146,156`) |
| `accept_relift.sh:144` inclui `FAILED-PARTIAL`; cópias monorepo/build idênticas | **medido offline** (`grep`, `diff`) |
| 8/8 marcadores `[INTROSEQ]` do patch migrado presentes nos ficheiros host | **medido offline** |
| Atribuição de `[POSTINTRO]` −15 e `ps3_factory_*` −2 ao patch #4 | **medido offline** (contagem no `PATCHED_BODY_B71` + `patch_zz_host_api_decls.py:188`) |
| `g_trampoline_fn` −318 e `+74` funções | **NÃO EXPLICADO** — medido, não atribuído |
| Efeito de qualquer destas correcções no `elo_stopped` | **NÃO-EXERCITADO** — zero builds e zero boots nesta sessão, por desenho |
| As 4 paredes da Fase 11 | **não tocadas** |

---

## Referências

- `games/gow2/notes/2026-08-02-e2e-relift-completo.md` — a corrida que encontrou os 6 (§4 corrigida aqui)
- `docs/RELIFT_CANONICAL.md` — a sequência 1→8 (etapas 2/6 a corrigir, §6)
- `games/gow2/lift_baseline/PATCH_MIGRATION.tsv` — ledger, linhas 102/119/133/134/160/169
- `games/gow2/lift_baseline/PATCH_CATALOG.tsv` — classe `FUNCIONAL`/`PROBE` que o gate lê
- `games/gow2/lift_baseline/CONTRACTS.tsv` — sem contrato para nenhum dos 6
- `games/gow2/accept_relift.sh` — `:140` (a re-corrida que muta), `:144` (o `awk`, correcto)
- `../gow2-recomp/build_macos.sh` — `:49-98` (bloco `RELIFT`), `:146,156` (compilação)
- `../gow2-recomp/apply_all_patches.sh` — `:329` (glob), `:346` (`FAILED-PARTIAL`), `:376` (gate)
- `games/gow2/hooks/gow2_midasm_hooks.cpp`, `games/gow2/hooks/gow2_func_overrides.cpp` — casa nova dos 8 `[INTROSEQ]`
- Logs do E2E (não versionados, G6): `/tmp/e2e/step4_patches.log`, `/tmp/e2e/relift_status.tsv`, `/tmp/e2e/accept_recomp_macos_v3_e2e_{status.tsv,patches.log}`
