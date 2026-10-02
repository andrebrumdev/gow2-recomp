# A perna 3 ficou honesta, e o lift foi promovido

**Data:** 2026-08-03 · **Máquina:** Apple Silicon (macOS/arm64)
**Objecto:** corrigir o defeito **D2** da perna 3 do `accept_relift.sh`, reclassificar o
`patch_24e3d0_null_product_gate.py`, correr o aceite e decidir a promoção.
**Lift candidato:** `recomp_macos_v6promo` (não versionado) · **Logs:** `/tmp/promo2/*` (G6)
**Promoção: FEITA** — ver §5.

---

## Veredicto directo

> **A perna 3 ficou honesta, com prova de mutação nos dois sentidos.**
> **Os quatro critérios passaram. PROMOVI.**
>
> O `accept_relift.sh` deu **`rc=0`** — as quatro pernas e os contadores bloqueantes. O
> `promote_lift.sh` correu o seu próprio gate **outra vez**, passou outra vez, e promoveu:
> `recomp_macos_v6promo → recomp_macos_v2`, com backup por rename, rebuild e confirmação
> pós-build. `PROMOTE-OK` está no `PROMOTION_LOG.tsv`.
>
> **A produção passa a ser** o lift fresco de hoje: `recomp_macos_v2` = `recomp_macos_v6promo`
> byte a byte nos chunks, e `boot_gow2` de **3 ago 10:38**, 121 684 568 B. A produção antiga
> (2 ago 17:37) está preservada em `recomp_macos_v2.pre_20260803_103715` /
> `boot_gow2.pre_20260803_103715`, confirmada por hash.

E o argumento inteiro da leva cabe numa linha do log **desta mesma corrida**: a 2.ª passagem
continua a dizer `patch_1856a8_stream_opd.py FAILED` — e o gate já não lhe liga, porque
mediu a árvore certa e provou que reaplicar não muda um byte.

---

## 1. Task 1 — a perna 3

### 1.1 O que estava errado

`accept_relift.sh` re-corria o `apply_all_patches.sh` **por cima da árvore que a etapa 4 já
tinha patchado** e usava o resultado dessa **segunda** passagem como veredicto. Três
consequências, todas medidas antes e reproduzidas hoje:

| # | Efeito | Prova |
|---|---|---|
| 1 | **Mascara** falhas de ordem | um patch que só aplica à 2.ª passagem aparece `APPLIED` no gate sem nunca ter entrado no binário que o gate acabou de testar |
| 2 | **Fabrica** falhas | `patch_1856a8_stream_opd.py` e `patch_icg_ctor_opd.py` dão `APPLIED` na etapa 4 e `FAILED` na perna 3 — *"no `ps3_indirect_call` decl"* — porque procuram a declaração que **eles próprios converteram** |
| 3 | **Apaga** o `FAILED-PARTIAL` | o sinal de árvore meio escrita, o mais grave dos seis estados, degrada para `FAILED` limpo (já não há nada para escrever) |

### 1.2 A correcção: verificar convergência, não repetir a aplicação

Novo `games/gow2/lib_patch_convergence.sh`, consumido pela perna 3:

- **A.** as **contagens** vêm do TSV da **etapa 4** (`--patch-status` / `ACCEPT_PATCH_STATUS`)
  — a corrida que produziu o binário que as pernas 1 e 4 testam.
- **B.** a **convergência** é provada por `sha256` do conteúdo dos `ppu_recomp_*.cpp` antes e
  depois de reaplicar. Se reaplicar mudar um byte, a árvore não estava convergida → **FAIL**.
  O `rc` e o TSV da reaplicação passam a **informativos** — era deles que vinham as falhas
  fabricadas.
- **Sem o TSV da etapa 4 a perna FALHA**, e o script aborta **cedo** (antes do build e dos 12
  boots): um gate sem medição nunca passa. É a mesma política que o `check_boot_health.py` já
  usava para os logs de boot.
- **`FAILED-PARTIAL` continua a bloquear** *e* passa a ser **contado à parte** no relatório —
  deixou de poder desaparecer sem ninguém dar por isso.

O `promote_lift.sh` reencaminha o `--patch-status` ao gate; não o interpreta.

### 1.3 A prova de mutação — os dois sentidos

`games/gow2/test_patch_convergence.sh`, **11 testes herméticos** (zero builds, zero boots,
zero lifts reais), commitados **VERMELHOS** antes do fix (`38b6166`).

| # | Cenário | Esperado | Porque importa |
|---|---|---|---|
| T1 | árvore converge + TSV limpo | **VERDE** | o caso bom |
| **T2** | **a reaplicação muda um byte** | **VERMELHO** (`convergencia=FALHOU`) | **o segundo sentido**: sem ele o gate era decorativo. É exactamente a classe «ordem» |
| T3 | `FAILED-PARTIAL` fora de `PROBE` | VERMELHO, e `failed_partial_nao_probe=1` | o sinal mais grave continua a contar **e** aparece sozinho |
| T4 | `FAILED`/`FAILED-PARTIAL` de classe `PROBE` | VERDE | `PROBE` fica fora do gate, por desenho |
| T5 | `NO-MATCH` fora de `PROBE` | VERMELHO | critério D-5.1 intacto |
| T6 | sem TSV da etapa 4 | VERMELHO | um gate sem medição nunca passa |
| T7 | TSV só com cabeçalho | VERMELHO | zero patches medidos ≠ zero falhas |
| **T8** | **a 2.ª passagem devolve `FAILED` sem mudar a árvore** | **VERDE** | **o D2 fechado**: o veredicto vem da etapa 4, não da repetição |
| T9 | a reaplicação foi mesmo executada (sentinela) | VERDE | a convergência é **provada**, não assumida |
| T10 | lift sem `ppu_recomp_*.cpp` | VERMELHO | sem árvore não há medição |
| T11 | `lift_chunks_sha` estável e sensível a 1 byte | VERDE | o instrumento antes do gate |

**E a prova viva, na corrida real de hoje** (`/tmp/promo2/accept_recomp_macos_v6promo_*`):

| | 2.ª passagem (informativa) | etapa 4 (autoritativa) |
|---|---|---|
| `patch_1856a8_stream_opd.py` | **`FAILED` `FUNCIONAL`** | `APPLIED` |
| `patch_icg_ctor_opd.py` | **`FAILED` `FUNCIONAL`** | `APPLIED` |
| `FAILED` fora de `PROBE` | **2** | **0** |

E o mesmo log, na linha 173-178: `[PASS] 1856A8 stream OPD (SHADERSRC N>0)`,
`[PASS] decl ps3_call_opd em 000`, `CHECKS: todos passaram`.
**Com a perna antiga, esta corrida teria dado `rc=1`.** Com a nova dá `rc=0`, e a diferença
não é indulgência: é ter medido a árvore que produziu o binário e ter **provado** que
reaplicar não muda nada —
`sha_antes = sha_depois = 0868196f2dd32664abd6b272520eacd96cc142386b4171692cdf71111c52e52a`.

**Nenhuma falha real apareceu quando a 2.ª passagem deixou de as esconder.** A etapa 4 desta
corrida deu **zero** `NO-MATCH` e **zero** `FAILED`/`FAILED-PARTIAL` fora de `PROBE` — logo o
critério não foi relaxado para passar; foi apontado ao sítio certo e o sítio certo estava
limpo. Se não estivesse, a promoção esperava.

---

## 2. Task 2 — o `patch_24e3d0_null_product_gate.py`

**Reclassificado para `PROBE`. Não foi corrigido nem apagado** — só a classificação estava
errada.

### 2.1 A medição, escrita onde fica rastreável

| Lift | ocorrências da agulha `vm_write16(ctx->gpr[9] + 0x6, ctx->gpr[0]);` | o patch exige | marcador |
|---|---:|---:|---|
| `recomp_macos_v6promo` (candidato) | **38** | 1 por chunk | ausente |
| `recomp_macos_v4ord` | **38** | 1 | ausente |
| **`recomp_macos_v2` (PRODUÇÃO)** | **38** | 1 | ausente |

**Falha idêntica contra a produção.** Não é dívida de re-lift nem regressão de candidato
nenhum: é um patch que nunca aplicou a esta geração de lift. O marcador
`24E3D0-NULLPROD-GATE` tem contagem **0** no `MANIFEST.tsv` e não há contrato para ele em
`CONTRACTS.tsv`.

E o ficheiro declara-se: abre com *"GATE DE DIAGNOSTICO (nao e' um fix)"* e injecta código
atrás de `PS3_24E3D0_KEEP_TYPE_ON_NULL` — sem a env var é um `else vm_write16(...)`, no-op
comportamental.

### 2.2 Uma regra, não um caso especial

`gen_catalog.py` ganha o **ramo 2b**, gémeo do ramo 2 (`"Diagnostic only"`) na língua em que o
corpus está escrito: auto-declaração literal **E** gate de ambiente `getenv("PS3_...")`.

**A conjunção é deliberada e medida:** 95 dos 140 patches têm gate de ambiente sem serem
diagnósticos, portanto o mecanismo sozinho não classifica; e uma declaração sem mecanismo
seria uma frase a comprar saída do gate. Dois testes de mutação provam os dois lados
(`t_declaracao_sem_env_gate_continua_funcional`, `t_env_gate_sem_declaracao_continua_funcional`).

### 2.3 O raio, e o custo declarado

| Patch | env var | estado na etapa 4 |
|---|---|---|
| `patch_218364_pool_null_gate.py` | `PS3_POOL_NULL_IF_BAD` | `APPLIED` |
| **`patch_24e3d0_null_product_gate.py`** | `PS3_24E3D0_KEEP_TYPE_ON_NULL` | `FAILED` |
| `patch_254610_empty_list_gate.py` | `PS3_LIST254_EMPTY_IF_NULL` | `APPLIED` |
| `patch_2547f8_empty_list_gate.py` | `PS3_LIST547_EMPTY_IF_BAD` | `APPLIED` |

Catálogo: **140 = 84 `FUNCIONAL` + 56 `PROBE`** (era 88/52).

> **Custo assumido e escrito:** três destes estavam `APPLIED`. Saem do gate por **classe**,
> não por falharem — é uma **perda de cobertura real**. Aceitei-a porque a alternativa era
> pior: reclassificar só o que falha, e deixar os três iguais dentro do gate, seria
> exactamente «relaxar a regra para o caso que incomoda». A classe é propriedade do
> comportamento.

A razão e a medição ficam em **três** sítios rastreáveis: na `razao` da própria linha do
`PATCH_CATALOG.tsv`, num bloco `RECLASSIFICACAO 2026-08-03` no cabeçalho do mesmo ficheiro
(gerado, nunca escrito à mão), e num bloco equivalente no `PATCH_MIGRATION.tsv`.

**10 testes novos** (`test_gen_catalog_diag_gate.py`), commitados vermelhos (`9556301`: 5
vermelhos / 5 verdes). As **13** suites do `lift_baseline` continuam `rc=0`.

### 2.4 Achado lateral (defeito de processo, registado)

O regen do `PATCH_MIGRATION.tsv` com `--merge` **apaga blocos de cabeçalho escritos à mão** —
34 linhas das Fases 17/18/19 (contagem congelada do XEN-05, porque os P0 `OPD` não migraram,
`alvo=midasm+weak`). Foram repostas linha a linha e confirmado que **nenhuma nota humana se
perdeu**: só mudaram as 3 linhas derivadas (data, contagens, piloto). O defeito fica escrito;
o fix não é desta leva.

---

## 3. A corrida

Sequência canónica a partir de `../gow2-recomp`, `PS3_ENGINE_ROOT` explícito, forma explícita
na etapa 2 (**não** `RELIFT=1`, que compila antes da etapa 4 — defeito D1).

| Etapa | Comando | Resultado |
|---|---|---|
| 1 | `functions.json` | **saltada** — fronteiras não mudaram |
| 2 | `ppu_lifter.py --config` → `recomp_macos_v6promo` | `rc=0`, **16,9 s**, **51 991** funções, 7 chunks, **0 stubs** |
| 3 | não reaplicar migrados | nada a correr |
| 4 | `apply_all_patches.sh --status` (**1.ª passagem**, 3m24) | **118 `APPLIED`**, 5 `ALREADY`, 14 `UNVERIFIED`, **3 `FAILED` — os três de classe `PROBE`**, **0 `NO-MATCH`**, **0 fora de `PROBE`** |
| 5 | `verify_lift.sh` | **`rc=0`** ✅ |
| 6+7 | build + smoke | **feitos dentro da perna 1** (`FORCE_REBUILD_LIFT=1`) — um build explícito à parte seria deitado fora pelo rebuild forçado da perna 1 |
| 8 | `accept_relift.sh v6promo 6 /tmp/promo2 --patch-status …/p1_status.tsv` | **`rc=0`** ✅ |
| 9 | `promote_lift.sh … --yes --patch-status …` | gate `rc=0` **outra vez**, **PROMOVIDO** |

**Reprodutibilidade:** o `--status` da 1.ª passagem é **idêntico** ao da leva anterior
(`diff /tmp/promo/p1_status.tsv /tmp/promo2/p1_status.tsv`) **excepto nas 4 células de classe
que esta leva reclassificou**. Nenhum estado de patch mudou.

**Os três `FAILED` da etapa 4**, todos `PROBE` e todos já conhecidos:
`patch_24e3d0_null_product_gate.py` (reclassificado hoje),
`patch_ce03c_pre_play_stop.py` e `patch_ce03c_wait_idle_f2b_movie.py` — os dois últimos
**também falham contra a produção** (marcadores com contagem 0 nos dois lifts), e o segundo
declara-o ele próprio.

### 3.1 As 6 corridas do gate da cadeia (perna 4)

| # | `st620` | `startseq` | `nopic` | `r_perma` | `setflip_after_rperm` | `elo_stopped` | elo |
|---|---:|---:|---:|---:|---:|---|---:|
| 1 | 11 | 2 | 4 | 1 | 9 | `AUTO_LOAD (nunca criada)` | **4** |
| 2 | 11 | 2 | 4 | 1 | 9 | `AUTO_LOAD (nunca criada)` | **4** |
| 3 | 11 | 2 | 4 | 1 | 9 | `AUTO_LOAD (nunca criada)` | **4** |
| 4 | 11 | 2 | 4 | 1 | 9 | `AUTO_LOAD (nunca criada)` | **4** |
| 5 | 11 | 2 | 4 | 1 | 10 | `AUTO_LOAD (nunca criada)` | **4** |
| 6 | 11 | 2 | 4 | 1 | 10 | `AUTO_LOAD (nunca criada)` | **4** |

**Elo 4 em 6 de 6.** «`AUTO_LOAD` nunca criada» é o comportamento **correcto** de um jogo que
ainda está a correr (`lib_boot_chain_metrics.sh:94-118`, medido a 2026-08-01).

**Perna 1:** `st620_max=11` em **5/6** (limiar 4) — a corrida 4 caiu no flake conhecido da
intro. `lifted=52142`, `modules=13`, `imports=151`, `orfaos=0`.

**Receita, declarada (G6):** as 6+6 corridas do aceite correram com a receita fixada pelo
instrumento (`arm_menu_fast_recipe()`, que exporta `PS3_RSX_BACKEND=metal`) — a mesma dos
pontos de referência com que se compara. A confirmação pós-build do `promote_lift.sh` corre a
receita do `smoke_relift_equiv.sh`: `PS3_NO_RSX=1 PS3_RSX_BACKEND=trace PS3_PERF_FSM=1
PS3_MOVIE_EOS=0`. **Editar scripts de medição não estava em causa.**

---

## 4. Os quatro critérios, um a um

### Critério 1 — `verify_lift.sh rc=0` · **PASSOU** ✅

```
[lift_parity]      current=76  baseline=77  novos=0  resolvidos=1
[MANIFEST_DEBT]    current=0   baseline=36  novos=0  resolvidos=36
[audit_boundaries] current=180 baseline=180 novos=0  resolvidos=0
AMBITO  PREAMBLE g_trampoline_fn: medido no PREAMBULO = 56 (esperado >=56)
```

Dívida do `MANIFEST` a **zero**, nenhum achado novo. E **re-corrido contra a produção nova**
depois da promoção: `rc=0`, os mesmos números.

### Critério 2 — elo 4 em ≥4 de 6 · **PASSOU** ✅

**6 de 6.** `elo_atingido PASS [BLOQUEANTE] elo >= 4 em 6/6; elos medidos: [4,4,4,4,4,4]`.

### Critério 3 — `ICALL-BAD ≤ 12`, `st620 ≥ 3`, `OOB` não pior, sem `FATAL` novo · **PASSOU** ✅

| Sub-critério | Candidato (pior corrida) | Produção declarada | Veredicto |
|---|---:|---:|---|
| `st620_max ≥ 3` | **11** em 6/6 | 11 | **PASSA** |
| `ICALL-BAD ≤ 12` | **12** | 12 | **PASSA** (idêntico) |
| `OOB` não pior | **1** | 19 | **PASSA** |
| `0xFFFF` não pior | **2** | 16 | **PASSA** |
| `FATAL` não novo | **1** (`0x00514E80`) | 1 | **PASSA** — o critério é a **contagem**, não o endereço (proveniência escrita na `PRODUCTION_REFERENCE.tsv`) |

### Critério 4 — `accept_relift.sh rc=0` · **PASSOU** ✅ — o que esta leva desbloqueou

```
PERNA 1 (smoke)          PASS   (OK=5/6)
PERNA 2 (verify_lift)    PASS   (rc=0)
PERNA 3 (convergencia)   PASS   (etapa 4: NO-MATCH=0 FAILED-fora-PROBE=0 dos quais
                                 FAILED-PARTIAL=0 | convergencia=OK | UNVERIFIED=14 informativo)
PERNA 4 (chain+saude)    PASS   (nao pior que a producao declarada)
CONTADORES (D-5.2)       PASS   (imp_modules 13=13, imp_imports 151=151, orfaos 0)
ACEITE: rc=0
```

**Correu duas vezes**, com 20 minutos de intervalo e binários reconstruídos do zero: uma como
etapa 8, outra como gate obrigatório dentro do `promote_lift.sh`. **`rc=0` nas duas.**

---

## 5. A decisão

> ## PROMOVIDO.

```
promovido : recomp_macos_v6promo -> recomp_macos_v2 (suffix=20260803_103715)
backups   : recomp_macos_v2.pre_20260803_103715 / boot_gow2.pre_20260803_103715
reversao  : ./promote_lift.sh --revert 20260803_103715
```

`PROMOTION_LOG.tsv`, os três estados por promoção:

| timestamp | acção | lift | sufixo |
|---|---|---|---|
| `2026-08-03T14:37:16Z` | `PROMOTE-BEGIN` | `recomp_macos_v6promo` | `20260803_103715` |
| `2026-08-03T14:41:34Z` | `PROMOTE-OK` | `recomp_macos_v6promo` | `20260803_103715` |

### 5.1 A produção antiga está intacta — confirmado por hash

| | medido | esperado |
|---|---|---|
| `md5(boot_gow2.pre_20260803_103715)` | `2d8a63ad46d0dfe9ba232705a84ef830` | **igual** ao `boot_gow2` de 2 ago 17:37 que medi antes de tocar em nada, e ao `hash_boot_antes` do `PROMOTE-BEGIN` |

**Ressalva honesta, medida:** o `hash_dir` do directório de backup dá hoje `cec7a7d8…`, e o
`PROMOTE-BEGIN` registou `1940adb7…`. **Não é conteúdo diferente** — o `hash_dir` passa os
caminhos pelo `tar`, logo muda só por o directório ter sido renomeado. Provado por
experimento discriminador (mesmo conteúdo, nomes `a` e `b` → dois md5 diferentes). O
`--revert` renomeia **de volta** para `recomp_macos_v2` **antes** de comparar, por isso a
confirmação por hash continua a funcionar.

### 5.2 O `boot_gow2` novo corre — medido in-boot

Confirmação pós-build do próprio `promote_lift.sh`, **6 corridas sobre o binário
reconstruído** (não sobre o do aceite):

| run | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---:|---:|---:|---:|---:|---:|
| `st620_max` | 11 | 11 | 11 | 11 | 11 | 1 |

`st620>=3 em 5 de 6` (limiar 4), `lifted=52142`, `modules=13`, `imports=151`,
`orfaos_pos_run: 0`. A corrida 6 é o flake conhecido da intro (~33 %, medido nos três
binários a 2026-08-03).

### 5.3 O que a produção passa a ser

| | antes | **agora** |
|---|---|---|
| `recomp_macos_v2` | lift de 26 Jul, promovido a 29 Jul | **`recomp_macos_v6promo`**, byte a byte nos 7 chunks |
| `boot_gow2` | 2 ago 17:37, 120 675 480 B | **3 ago 10:38, 121 684 568 B** |
| `function_table_count` | 51 917 | **51 991** (+74) |
| `boot_lifted_functions` | 52 068 | **52 142** (+74) |
| `imp_modules` / `imp_imports` | 13 / 151 | **13 / 151** (bloqueantes, delta 0) |
| `OOB` (pior corrida) | 19 | **1** |
| `0xFFFF` (pior corrida) | 16 | **2** |
| `ICALL-BAD` | 12 | **12** |

Assinaturas confirmadas no binário novo, contra o antigo: `AREAD-HLE` 2/2,
`PS3_FIOS_HOST_POP` 1/1, `ps3_fios_aread_hle` 1/1, `STREAM-OPD` 1/1, `ICG-PATH-A-OPD` 1/1
(`strings`), `g_b71_product_reused` 1/1 (`nm` — é símbolo, não string literal; medi primeiro
com `strings` e deu 0 nos dois, o que era a **ferramenta** errada, não uma perda).

**O delta `+74` funções continua por explicar** — está por explicar desde o E2E, é idêntico
nos dois contadores, e os contadores que o gate bloqueia (`imp_modules`, `imp_imports`,
`orfaos`) têm delta zero. Fica na lista, agora **em produção**.

---

## 6. Higiene (G6)

| Regra | Estado |
|---|---|
| Kill por **PID** (`TERM` → `-9`) | **cumprido** — 24 boots (6 perna 1 + 6 perna 4, duas vezes) + 6 da confirmação; nenhum `pkill -f` |
| Órfãos | **0** antes, durante (`orfaos_pos_run: 0`) e depois (verificado) |
| `timeout(1)` | **não usado** (não existe no macOS) |
| Logs fora dos dois repos | **cumprido** — `/tmp/promo2/*`, `/tmp/accept_*`, `/tmp/promote_confirm_*` |
| Produção escrita | **SIM, e de propósito** — pelo `promote_lift.sh`, com gate próprio, backup por rename e confirmação pós-build |
| `--freeze` do `MANIFEST` | **não usado** |
| `ps3_indirect_call` (mesmo defeito de contrato do `g_trampoline_fn`) | **não tocado** — decisão à parte, com prova à parte |
| Patches corrigidos ou apagados | **nenhum** — o `24e3d0` só mudou de classe |
| Ficheiros de outra sessão | `recomp_mid_v2/patch_41f78c_prune_probe.py` (`M`) fica **fora** destes commits |
| Ficheiros interditos | `.planning/ROADMAP.md`, `PROJECT.md`, `MILESTONES.md`, os dois `CLAUDE.md`, `config.json`, `scripts/gsd_plan*.sh`, `.planning/milestones/v1.2-*` — **intactos e fora dos commits** |

---

## 7. O que ficou por exercitar

| # | Item | Porquê |
|---|---|---|
| 1 | `ps3_indirect_call` — mesmo defeito de contrato do `g_trampoline_fn` (preâmbulo=7 vs limiar 15 759) | decisão à parte; mexe no grupo `opd-dispatch` |
| 2 | Nota `MIGRADO:` no `MANIFEST.tsv` para marcadores `SYM` | dívida que o D3 não fecha |
| 3 | Janela de idempotência por função (causa raiz do D4) | a ordem declarativa contorna |
| 4 | Causa do `stuck 0x00514E80` (o `FATAL`) | **não investigada** — alvo indirecto por resolver, agora **em produção** |
| 5 | `+74` funções / `g_trampoline_fn` −318 | **não explicado**, herdado do E2E |
| 6 | O regen `--merge` do ledger apagar cabeçalho humano | achado desta leva, fix noutra |
| 7 | Flake da intro (1 de 6 nas duas medições) | pré-existente, ~33 % |
| 8 | Cobertura de gate perdida nos 3 `PROBE` novos | custo declarado da regra (§2.3) |
| 9 | As 4 paredes da Fase 11 | **não tocadas** |

---

## 8. Nível de evidência (regra 4 do `CLAUDE.md`)

| Item | Nível |
|---|---|
| Perna 3: 11 testes, prova nos dois sentidos | **medido offline** nesta sessão (hermético) |
| As 2 falhas fabricadas aparecerem na 2.ª passagem **desta** corrida e não contaminarem o veredicto | **medido** nesta sessão, nos TSV e no log |
| Convergência `sha_antes == sha_depois` | **medido** nesta sessão |
| Ramo 2b: raio de 4, conjunção necessária (95/140 têm env gate) | **medido offline** contra os 140 patches reais |
| Agulha do `24e3d0` = 38 nos três lifts, 1 exigida | **medido offline** por leitura pura |
| Etapa 4 idêntica à leva anterior excepto as 4 classes | **medido** (`diff`) |
| `verify_lift.sh rc=0` no candidato **e** na produção nova | **medido** nesta sessão |
| Elo 4 em 6/6; `ICALL-BAD=12`, `OOB=1`, `0xFFFF=2`, `FATAL=1` | **medido in-boot**, 6 corridas (×2, gate corrido duas vezes) |
| `boot_gow2` novo corre: `st620=11` em 5/6 | **medido in-boot**, 6 corridas sobre o binário reconstruído |
| Backup da produção antiga íntegro (`md5` do binário) | **medido** nesta sessão |
| `hash_dir` mudar só por renome | **medido** por experimento discriminador |
| Métricas de referência da produção antiga | **medidas in-boot a 2026-08-03** (leva anterior); **não re-medidas** aqui — a produção antiga não foi executada nesta sessão |
| Efeito in-boot dos 22 dispatchers recuperados | **NÃO-EXERCITADO** |
| Promoção | **FEITA**, `PROMOTE-OK` registado |

---

## Referências

- `games/gow2/notes/2026-08-03-promocao.md` — a corrida de ontem (3 de 4 critérios)
- `games/gow2/notes/2026-08-03-seis-patches-que-nao-reaplicam.md` §6-§7 — o diagnóstico do D1/D2
- `games/gow2/lib_patch_convergence.sh` · `games/gow2/test_patch_convergence.sh` (11 testes)
- `games/gow2/accept_relift.sh` (perna 3) · `games/gow2/promote_lift.sh` (`--patch-status`)
- `games/gow2/lift_baseline/gen_catalog.py` (ramo 2b) · `test_gen_catalog_diag_gate.py` (10 testes)
- `games/gow2/lift_baseline/PATCH_CATALOG.tsv` · `PATCH_MIGRATION.tsv` (blocos `RECLASSIFICACAO 2026-08-03`)
- `games/gow2/lift_baseline/PRODUCTION_REFERENCE.tsv` · `check_boot_health.py`
- `../gow2-recomp/PROMOTION_LOG.tsv` — `PROMOTE-BEGIN` / `PROMOTE-OK` de `20260803_103715`
- `docs/RELIFT_CANONICAL.md` — a sequência 1→8
- Logs não versionados (G6): `/tmp/promo2/step{2,4,5,8,9,10}_*.log`, `/tmp/promo2/p1_status.tsv`,
  `/tmp/promo2/accept_recomp_macos_v6promo_*`, `/tmp/promote_confirm_20260803_103715.tsv`
