# Marco v1.3 «Xenon tooling e RE-IA» — resultados medidos

**Data:** 2026-08-02 · **Fase:** 21 (endurecimento, métricas e fecho) · **Requisito:** `LEDG-02`
**Máquina:** Apple Silicon (macOS/arm64) · **Repo motor:** `ps3recomp` · **Repo de build:** `../gow2-recomp`

Este ficheiro é **o sítio único** de onde um auditor re-corre a suite do marco. Não repete os
`SUMMARY` das Fases 16–20: regista **comandos exactos e `rc` observados**.

## O que «marco fechado» quer dizer aqui — leia isto antes do 11/11

> **«Inteiro» refere-se aos requisitos e critérios medidos — não a «o lift está limpo».**

O marco fecha **11/11 requisitos** e **4/4 critérios**. Isso é verdade e está medido. Mas o
número que descreve o estado do *port* é outro, e é este:

| | |
|---|---|
| `patch_*.py` de classe `CORRECTNESS` ainda activos | **72** (eram 78 no início do marco) |
| Reduzidos pelo marco | **6** (−7,7 %) |
| Destes 6, quantos foram migração real | **4** — os outros 2 eram `redundant`, nunca foram precisos |
| Fixes re-lift-safe entregues | **4 linhas / 3 mecanismos** (o mínimo exacto do `XEN-05`, sem folga) |
| O mid-asm corre no jogo? | **Não.** O lift de produção não tem uma única chamada — ver ressalva 1 |

Ou seja: o marco entregou **o mecanismo, provado**, e migrou **4 linhas em 78**. Quem ler
«11/11» sem ler esta tabela sai com a impressão errada. As 10 ressalvas estão na secção
«Ressalvas do marco», e a primeira é a que mais limita o que se pode afirmar.

## A regra que governa este documento (G5)

> **O `rc` é o entregável.** Cada linha traz o `rc` **realmente observado**, incluindo os que
> falharem. Uma linha que não foi corrida fica **`não-exercitado`** com a razão escrita —
> **nunca presumida `0`**. Uma tabela de dez zeros que ninguém correu é pior que uma tabela
> com dois vermelhos honestos. (Regra 4 do `CLAUDE.md`: nunca forjar resultados.)

**Níveis de evidência** usados nas tabelas abaixo:

| Nível | Significado |
|---|---|
| `offline-unit` | corrido fora do boot (suite Python, script de verificação, `grep`/`nm`/`objdump`) |
| `in-boot` | observado num boot real do `boot_gow2` |
| `não-exercitado` | **não** foi corrido nesta fase; a razão está escrita na linha |

## Ambiente e proveniência da corrida (medido)

| Item | Valor |
|---|---|
| Interpretador T1–T7 | `.venv/bin/python3` → **Python 3.14.6** (o `python3` do sistema é **3.9.6**, sem `tomllib` — não serve) |
| `HEAD` do motor | `58481ec` (branch `macos-arm64-port-f0-f2`) |
| `LIFT` de produção (T8) | `../gow2-recomp/recomp_macos_v2` — default do `build_macos.sh`/`apply_all_patches.sh` |
| `LIFT_PROD_SHA256` | `73c8abd21abb17e829fc4186b55a5b2395a3d0e4b4f8019bf6bd8e8cc901ae7f` (`cat ppu_recomp_*.cpp \| shasum -a 256`) |
| `LIFT` do piloto midasm (T10) | `../gow2-recomp/recomp_macos_v3_midasm` |
| `LIFT_MIDASM_SHA256` | `5a5d9c9697f8d861c39300356e7f41c6d9fc126a1e8040e98be0aa4facfff23e` |
| Binário do smoke (T9) | `../gow2-recomp/boot_gow2` (mtime **2026-08-02 17:37**) |
| Logs | todos em `/tmp/m21_*` — **fora dos dois repos** (G6), **não versionados** |

**Proveniência que vale a pena dizer:** o `LIFT_PROD_SHA256` medido hoje é **byte-a-byte o
mesmo** que a Fase 16 registou no cabeçalho de `lift_baseline/PATCH_MIGRATION.tsv`
(`73c8abd2…`). O lift de produção **não mudou** durante o marco inteiro — o que é coerente
com o marco não ter promovido nada (a promoção tem gate próprio, e não era desta fase).

## Suite T1–T10 — `rc` observado

| ID | Comando exacto | `rc` | Evidência | Log |
|---|---|---|---|---|
| **T1** | `.venv/bin/python3 tools/test_recomp_config.py` | **0** | `offline-unit` | `/tmp/m21_test_recomp_config.log` |
| **T2** | `.venv/bin/python3 tools/test_midasm_emit.py` | **0** | `offline-unit` | `/tmp/m21_test_midasm_emit.log` |
| **T3** | `.venv/bin/python3 tools/test_invalid_instructions.py` | **0** | `offline-unit` | `/tmp/m21_test_invalid_instructions.log` |
| **T4** | `.venv/bin/python3 tools/test_ps3_analyse_jtables.py` | **0** | `offline-unit` | `/tmp/m21_test_ps3_analyse_jtables.log` |
| **T5** | `.venv/bin/python3 tools/test_weak_override_symbols.py` | **0** | `offline-unit` | `/tmp/m21_test_weak_override_symbols.log` |
| **T6a** | `.venv/bin/python3 tools/test_switch_tables.py` | **0** | `offline-unit` | `/tmp/m21_test_switch_tables.log` |
| **T6b** | `.venv/bin/python3 tools/test_lift_parity.py` | **0** | `offline-unit` (dur ≈ 0 s — não é pesado) | `/tmp/m21_test_lift_parity.log` |
| **T7** | 8 suites de `games/gow2/lift_baseline/test_*.py` | **0 nas 8** | `offline-unit` | `/tmp/m21_test_<nome>.log` |
| **T8** | `PS3_ENGINE_ROOT=$(pwd) ./games/gow2/verify_lift.sh ../gow2-recomp/recomp_macos_v2` | **0** | `offline-unit` (59 s) | `/tmp/m21_T8_verify_lift.log` |
| **T8b** | idem **com** `VERIFY_ORACLE=1` (opt-in, não exigido pelo `LEDG-02`) | **0** | `offline-unit` (56 s) | `/tmp/m21_T8b_verify_lift_oracle.log` |
| **T9** | smoke de intro 30 s, `boot_gow2 EBOOT.ELF`, kill por PID | **rc do kill = 143 (SIGTERM, esperado)** — critérios: `st620_max=11`, `OOB=0` | `in-boot` | `/tmp/m21_T9_smoke.log` |
| **T10** | prova de re-lift do piloto midasm (`grep`/`nm` sobre `recomp_macos_v3_midasm`) | **0** | `offline-unit` (re-exercitado hoje, **não** citado das Fases 17/19) | `/tmp/m21_T10_grep_midasm.log` |

**Contagem honesta: 12 linhas corridas de facto (T1–T10 + T6b + T8b), 0 declaradas
`não-exercitado`.** Nenhum `rc` desta tabela foi presumido.

**Bónus corrido (não substitui nenhuma linha T):** `tools/test_oracle_manifest.py` → **rc=0**
(`10/10 testes [PASS]`, `/tmp/m21_test_oracle_manifest.log`).

## Detalhe por linha

### T1–T6 — as suites de `tools/`

Corridas em bloco, cada uma com o `rc` capturado imediatamente a seguir. Uma linha de
saída de cada:

```
test_recomp_config        rc=0  ok: recomp_config TOML parser (main/optimizations/midasm_hook/overrides
                                + emit_weak_wrappers default-false + validation + Task B2 switch_table schema/loader)
test_midasm_emit          rc=0  ok: emissao de [[midasm_hook]] (antes/depois/return, ordem multi-hook, label,
                                terminador), golden sem --config por diff, recusa de jump_address e de EA orfao
test_invalid_instructions rc=0  ok: invalid_instructions consumer (5 call sites cobertos por 6 guards)
test_ps3_analyse_jtables  rc=0  [an] todos os casos passaram
test_weak_override_symbols rc=0 ok: ppc_hooks.h, forma __imp_/wrapper fraco, LINK REAL medido com clang++/nm
test_switch_tables        rc=0  ok: config-declared switch tables (config-wins merge, dedup, warnings, CLI wiring)
test_lift_parity          rc=0  [test_lift_parity] OK
```

**T6 tinha duas leituras possíveis** no plano de origem (`test_switch_tables` e/ou
`test_lift_parity`). Corri **as duas**, como T6a e T6b, para não haver ambiguidade sobre o
que foi medido. `test_lift_parity` acabou em **menos de 1 s** — a ressalva do plano («se for
pesado, corre um subconjunto documentado») **não se aplicou**.

### T7 — a suite de `lift_baseline/`

As **8** existentes, todas corridas, todas `rc=0`:

| Suite | `rc` | Saída final |
|---|---|---|
| `test_baseline_delta.py` | 0 | `5/5 testes [PASS]` |
| `test_check_contracts.py` | 0 | `8/8 testes [PASS]` |
| `test_gen_catalog.py` | 0 | `[PASS]` — 80/140 linhas do catálogo com marcador não-vazio |
| `test_gen_contracts_candidates.py` | 0 | `4/4 testes [PASS]` |
| `test_gen_manifest.py` | 0 | `[PASS]` — grupo abaixo do limiar combinado faz `verify()` devolver 1 |
| `test_gen_migration_ledger.py` | 0 | `[PASS]` — contagem derivada, P0=2 / P1=1, nomeia os pilotos |
| `test_manifest_delta_gate.py` | 0 | `6/6 testes [PASS]` |
| `test_oracle_step.py` | 0 | `5/5 testes [PASS]` |

### T8 — `verify_lift.sh` contra o lift de produção

```
$ PS3_ENGINE_ROOT=$(pwd) ./games/gow2/verify_lift.sh ../gow2-recomp/recomp_macos_v2
[lift_parity]       current=77  baseline=77   novos=0  resolvidos=0   PASS
[MANIFEST_DEBT]     current=0   baseline=36   novos=0  resolvidos=36  PASS
[audit_boundaries]  current=180 baseline=180  novos=0  resolvidos=0   PASS
== rodape ==
lift_parity          PASS
MANIFEST             PASS
audit_boundaries     PASS
rc=0   (59 s)
```

Com o passo de oráculo opt-in da Fase 20 (**T8b**, `VERIFY_ORACLE=1`):

```
[oracle] I4=137  I5 extende-seguro=2422  encurta=114  extende-funde=2618 (fora do gate)
[oracle_i4_i5] current=2673 baseline=2673 novos=0 resolvidos=0   DELTA OK
oracle_ghidra        PASS
rc=0   (56 s)
```

Os três (quatro com o oráculo) passam **por delta contra baseline congelado**, nunca por
limiar absoluto. Os números absolutos continuam altos por desenho (2689 lacunas I2
informativas, 180 I3, 5154 I5 históricos) — o gate mede **achados novos**, e hoje são **0**.

**`verify_lift.sh` já estava no caminho de aceitação antes deste marco**
(`games/gow2/accept_relift.sh:73`, perna 2). Esta linha da tabela **confirma** que continua
verde; não é uma entrega nova da Fase 21, e apresentá-la como tal seria desonesto.

### T9 — smoke de intro (in-boot, UMA corrida de 30 s)

```bash
# /tmp/m21_t9_smoke.sh  (fora dos repos, G6)
cd ../gow2-recomp
set -a; . ./env_gow2.sh; set +a
unset $(env | awk -F= '/^PS3_TRACE_/ {print $1}')          # probes OFF
export PS3_NO_RSX=1 PS3_RSX_BACKEND=trace PS3_PERF_FSM=1 PS3_MOVIE_EOS=0
unset PS3_MOVIE_DONE_MS PS3_VDEC_FORCE_SEQDONE_MS
./boot_gow2 EBOOT.ELF > /tmp/m21_T9_smoke.log 2>&1 &
BPID=$!; sleep 30; kill -TERM $BPID; sleep 1; kill -9 $BPID   # kill por PID; NUNCA pkill -f
```

| Métrica | Medido hoje | Baseline da Fase 16 | Veredicto |
|---|---|---|---|
| `st620_max` | **11** (sequência `0 → 1 → 3 → 3 → 3 → 11 → 11 → 11`) | 11 | **igual** — acima do gate `>=3` do `CLAUDE.md` |
| `OOB` / `0xFFFF` | **0** em 3481 linhas | 0 | **igual** (ausência real, não grep vazio por engano) |
| `lifted functions` | **52068** | 52068 | **igual** |
| `overlay_done` | 9 ocorrências, última linha `overlay_done=1` | (idem) | consistente |
| órfãos pós-run | **0** | 0 | limpo |
| `rc` do processo | **143** = `128+15` (SIGTERM) | — | **esperado**: o boot é um loop de render, morre por kill, não por `exit 0` |

**Ressalvas medidas, que ficam escritas:**

1. **O binário é o de produção (`recomp_macos_v2`), não o do piloto midasm.** `boot_gow2`
   (mtime 17:37) foi ligado contra os `.o` de `recomp_macos_v2` (mtime 17:37). O
   `nm boot_gow2` mostra `T _gow2_midasm_Ce03cWaitIdle` — o **corpo host** está lá, ligado —,
   mas o lift de produção **não tem nenhuma chamada** a esse símbolo (medido em T10). Ou
   seja: este smoke prova **não-regressão da intro**, e **não** prova o midasm em execução.
   Quem quiser o midasm in-boot tem de usar `boot_gow2_f17_midasm` / `boot_gow2_f19_mig*`.
2. **`sticky` continua NÃO-OBSERVÁVEL** (achado da Fase 16, **re-medido hoje**):

   ```
   $ grep -rn 'ps3_fios_sticky' runtime/ libs/
   runtime/ppu/ppu_loader.cpp:1370:  ps3_fios_sticky_publish(uint32_t op)    # sem fprintf
   runtime/ppu/ppu_loader.cpp:1383:  ps3_fios_sticky_peek(uint32_t op)       # sem fprintf
   runtime/ppu/ppu_loader.cpp:1393:  ps3_fios_sticky_consume(uint32_t op)    # sem fprintf
   $ grep -rn 'fprintf.*sticky' runtime/ libs/
   libs/video/movie_vt_metal.m:446: "[movie-vt] overlay_done already sticky"  # <- overlay VT, NAO e' o FIOS
   $ grep -ci sticky /tmp/m21_T9_smoke.log
   0
   ```

   **Precisão face à Fase 16:** existe **um** `fprintf` com a palavra `sticky` em
   `runtime/`+`libs/`, mas é do overlay VideoToolbox, **não** do FIOS. Os três
   `ps3_fios_sticky_*` continuam **mudos**, e no log de hoje há **0** ocorrências. Logo um
   grep por `sticky` daria sempre 0 e **0 não significaria «sticky morto»**. Por isso **não**
   usei `sticky_pub>=1` como critério — apesar de o `CLAUDE.md` o prescrever no checklist de
   não-regressão pós-merge. **Esse critério do `CLAUDE.md` não é verificável neste build**, e
   isso é um achado do marco que afecta a documentação do projecto.
3. **`bytes_read` continua não-exercitado** (medido no log de hoje): `grep -c bytes_read` = **0**,
   e há **1** único `[movieio] open`, o `gow2.psarc`. Com `PS3_MOVIE_EOS=0` e 30 s o `R_PermA`
   não chega a ser lido. O aceite `smoke:` do `patch_fallthrough_2550c8.py` continua por
   correr, tal como na Fase 16.
4. **UMA corrida, sem retry.** Não houve falha de `vm commit`; não repeti para «melhorar» o
   número.

### T10 — prova de re-lift do piloto midasm (**re-exercitada hoje**, não citada)

O plano permitia citar a evidência das Fases 17/19 identificando-a como reutilizada. **Não
foi preciso: re-corri a prova offline agora.** Os comandos e a saída literal:

```
$ grep -n 'gow2_midasm_Ce03cWaitIdle(ctx);' ../gow2-recomp/recomp_macos_v3_midasm/ppu_recomp_*.cpp
../gow2-recomp/recomp_macos_v3_midasm/ppu_recomp_000.cpp:169783:        gow2_midasm_Ce03cWaitIdle(ctx);
../gow2-recomp/recomp_macos_v3_midasm/ppu_recomp_002.cpp:19700:        gow2_midasm_Ce03cWaitIdle(ctx);
rc=0

$ grep -c 'CE03C wait-idle 1st movie' ../gow2-recomp/recomp_macos_v3_midasm/ppu_recomp_*.cpp
0          # <- o MARKER de patch_ce03c_introseq_block.py: 0 == o patch de correctness NAO correu

$ nm -u ../gow2-recomp/recomp_macos_v3_midasm/ppu_recomp_002.cpp.o | grep -i midasm
_gow2_midasm_Ce03cWaitIdle          # indefinido no .o do lift -> resolvido pelo hook host no link
```

**O que isto prova, exactamente:** o `[[midasm_hook]] Ce03cWaitIdle @ 0x000CE03C` declarado em
`games/gow2/config/gow2_recomp.toml:66` faz o lifter emitir a chamada **a partir do config**,
e o `MARKER` do patch tem **0 ocorrências** — logo a porção **wait-idle** do CE03C **não
precisa** de re-aplicar `../gow2-recomp/recomp_mid_v2/patch_ce03c_introseq_block.py` depois de
um re-lift. Esse pedaço é **re-lift-safe**.

**O que isto NÃO prova (precisão exigida pelo plano):** o patch original fazia **duas** coisas
— o wait-idle **e** envolver o corpo natural num `setjmp` com ramo de abort. **Só o wait-idle
foi migrado para mid-asm.** O pad de `setjmp`/`longjmp` é um **mecanismo diferente**, o
`[[functions_override]]` weak da Fase 19 (o mid-asm corre *ao lado* de uma instrução, não
envolve nada). Os dois compõem-se na mesma função. Dizer «o CE03C está migrado» sem esta
distinção seria uma meia-verdade.

**Diferenças face à Fase 17, medidas e não escondidas:**

- As linhas mudaram (`ppu_recomp_002.cpp:19537 → 19700`, `ppu_recomp_000.cpp:167034 → 169783`)
  porque o directório foi **re-liftado depois**, nas Fases 18–19 (mtime `2026-08-02 17:59`).
  A prova continua a valer; a âncora `arquivo:linha` da Fase 17 já **não** vale — é exactamente
  a razão pela qual o `CLAUDE.md` manda re-verificar âncoras antes de as usar.
- **Não** corri um `ppu_lifter` completo de raiz nesta fase. O plano marca isso como
  **opcional se a prova offline for completa**, e é: o lift em causa **é** o produto de um
  re-lift com `--config` (Fases 17→19) e o `MARKER=0` mostra que nenhum patch de correctness
  lhe tocou. **Declarado, não escondido.**

**Achado que só apareceu por ter corrido isto hoje** (e que vale mais do que um verde):

```
$ grep -rn 'gow2_midasm' ../gow2-recomp/recomp_macos_v2/          # LIFT DE PRODUCAO
rc=1   (0 linhas)
```

O lift de **produção** não tem uma única chamada de mid-asm. Varridos os 21 directórios de
lift do repo de build: `recomp_macos_v3_midasm`, `_jt18`, `_mig19`, `_mig19b`, `_mig19c`,
`_ovr19` têm **7 ficheiros** com o símbolo; **todos** os `recomp_macos_v2*` e `recomp_macos`,
`recomp_macos_v3`, `recomp_pre` têm **0**. Isto é coerente e **não é uma regressão** — o marco
não promoveu nada de propósito —, mas significa que **o mid-asm ainda não está no caminho que
o jogador corre**. Promover é decisão humana com gate próprio (`promote_lift.sh`), e fica
**fora** desta fase.

## Métricas antes/depois

Todos os números desta secção foram **recontados hoje** (plano 21-03) a partir do disco e
do `git`, não copiados dos `SUMMARY` nem do `21-CONTEXT.md`. O comando de recontagem é
reproduzível numa linha:

```bash
$ awk -F'\t' '/^#/ || $1=="patch" {next} {n[$2"/"$7]++; tot++} END {for (k in n) print k, n[k]; print "TOTAL", tot}' \
    games/gow2/lift_baseline/PATCH_MIGRATION.tsv | sort
CORRECTNESS/migrated 4
CORRECTNESS/redundant 2
CORRECTNESS/todo 72
OBSOLETE/todo 2
OPD/todo 10
PROBE/todo 50
TOTAL 140
```

O "antes" não é uma lembrança: é o **mesmo ficheiro no commit da Fase 16**, lido com
`git show`. Cada célula da coluna «Antes» tem um commit por trás.

### A tabela

| Métrica | Antes (Fase 16, baseline congelado) | Depois (2026-08-02, recontado) | Fonte / como se refaz |
|---|---|---|---|
| Linhas de dados do ledger | **140** | **140** | `PATCH_MIGRATION.tsv` (universo inalterado — nenhum patch novo entrou no marco) |
| `patch_*.py` de classe `CORRECTNESS` **ainda activos** (`estado=todo`) | **78** | **72** | `git show ee17e2c:games/gow2/lift_baseline/PATCH_MIGRATION.tsv` vs `HEAD`, mesmo `awk` |
| Fixes re-lift-safe — **leitura por linhas** (`CORRECTNESS` + `estado=migrated`) | **0** | **4** | ledger, coluna `estado` |
| Fixes re-lift-safe — **leitura conservadora por mecanismo** (uma função = um mecanismo) | **0** | **3** | `19-03-SUMMARY.md` §1, recontado abaixo |
| Mecanismos por declaração no TOML (leitura mais generosa) | **0** | **4** | `gow2_recomp.toml`: 1 `[[midasm_hook]]` (`:66`) + 3 `[[functions_override]]` que carregam fixes migrados (`:126` CE03C, `:148` 2F3F0, `:172` 2C0498). O 4.º `[[functions_override]]` (`:96`, EA `0x00010230`) é o piloto trivial de identidade da Fase 19 e **não** conta |
| `estado=redundant` — **não conta** para o `XEN-05` | **0** | **2** | ledger, Fase 18 |
| `verify_lift.sh` no caminho de aceite do re-lift | **já estava** (pré-v1.3) | **sim** — confirmado a correr `rc=0` | `games/gow2/accept_relift.sh:73` (`VERIFY_LIFT=…`), perna 2; corrida T8 acima |
| Passo de oráculo estático no `verify_lift` | **não existia** | **opt-in** `VERIFY_ORACLE=1`, `rc=0`, **por delta** (`I4/I5 current=2673 baseline=2673 novos=0`) | Fase 20 (`RE-01`); corrida T8b acima |
| Regressões de intro depois de mid-asm + weak | — (baseline: `st620_max=11`, `OOB=0`) | **0 regressões**: `st620_max=11`, `OOB=0`, `lifted=52068`, órfãos=0 | T9 acima; baseline no cabeçalho do ledger (Fase 16) |
| Achar os callers de um EA | **manual** (ler o lift / `nm` / grep à mão) | `tools/ghidra_lookup.py <ghidra_out> <EA> --callers` (+ `--grep`, `--writes`) | Fase 20; usado de facto na sessão de RE (T1–T7 de `docs/re_sessions/2026-08-02-wall-4-walk-de-tipos.md`) |
| Chamadas `gow2_midasm_*` no lift de **PRODUÇÃO** | 0 | **0** (inalterado) | `grep -rl 'gow2_midasm' ../gow2-recomp/recomp_macos_v2/` → **zero ficheiros**, re-medido hoje |

### A trajectória, commit a commit (medida, não narrada)

O ledger é versionado, portanto o «antes/depois» pode ser lido por fase em vez de só nas
duas pontas. Cada linha é `git show <commit>:games/gow2/lift_baseline/PATCH_MIGRATION.tsv`
passado pelo mesmo `awk`:

| Momento | Commit | `CORRECTNESS/todo` | `migrated` | `redundant` |
|---|---|---:|---:|---:|
| Fase 16 — baseline congelado | `ee17e2c` | **78** | 0 | 0 |
| Fase 17 — CE03C (mid-asm) | `b6f0c79` | 76 | 2 | 0 |
| Fase 18 — jump tables | `94f25ef` | 74 | 2 | **2** |
| Fase 19 — `2F3F0` + `2C0498` (weak) | `304610b` | **72** | **4** | 2 |

**A delta honesta:** o corpus de `CORRECTNESS` activos desceu **78 → 72**, isto é **−6
linhas, 7,7 %** — e dessas 6, **duas nunca foram precisas** (`redundant`). O trabalho útil
de migração são **4 linhas em 78**. O que o marco entrega não é um corpus limpo: é o
**mecanismo** que permite limpá-lo, provado em quatro linhas reais. Escrever "os patches
foram eliminados" seria falso; ficam 72, mais 50 `PROBE`, 10 `OPD` e 2 `OBSOLETE`, todos
ainda reaplicados pelo `apply_all_patches.sh` (cujo `SKIP_LIST` está vazio — medido no
21-01).

### As 4 linhas migradas, e o mecanismo de cada uma

Nomeadas aqui para que ninguém tenha de re-grepar o ledger:

| Patch | EA | `alvo` no ledger | Mecanismo que passa a carregar o fix | Fase |
|---|---|---|---|---|
| `patch_ce03c_introseq_block.py` | `0x000CE03C` | `midasm+weak` | `[[midasm_hook]] Ce03cWaitIdle` (wait-idle) **+** pad `setjmp`/`longjmp` no `[[functions_override]]` weak | 17 + 19 |
| `patch_ce03c_movie_done_reset.py` | `0x000CE03C` | `midasm` | subsumido pelo **mesmo** hook `Ce03cWaitIdle` | 17 |
| `patch_b71_2f3f0_guard.py` | `0x0002F3F0` | `weak` | `[[functions_override]]` host que envolve o corpo com saída antecipada | 19 |
| `patch_fios_play_already_active.py` | `0x002C0498` | `weak` | `[[functions_override]]` host que **substitui** o corpo (o corpo natural **é** o defeito) | 19 |

E as 2 `redundant` (Fase 18), que **não** entram na conta: `patch_jumptable_2a209c.py` e
`patch_jumptable_2b11b8.py` — medido que o lifter já emitia os alvos certos, logo os
patches nunca foram necessários. Um `redundant` documenta um patch inútil; **não**
documenta uma correcção que passou a ser re-lift-safe.

### `XEN-05` — as duas leituras, e qual decide

O `XEN-05` pede **≥3** correcções `CORRECTNESS` re-lift-safe. As duas leituras que as
Fases 18–19 estabeleceram, recontadas hoje:

| Leitura | Contagem | `XEN-05` (≥3) |
|---|---:|---|
| **Linhas** (`classe=CORRECTNESS` + `estado=migrated`) | **4** | ✅ |
| **Mecanismos, leitura CONSERVADORA** (uma função = um mecanismo) | **3** — `func_000CE03C`, `func_0002F3F0`, `func_002C0498` | ✅ |
| Mecanismos por declaração no TOML | 4 | ✅ |
| `estado=redundant` (Fase 18) | 2 | **não conta** |
| `classe=OPD` + `migrated` | 0 | não conta |

**A leitura conservadora é a que decide, e dá 3.** Duas das quatro linhas (`ce03c_*`)
partilham a **mesma** função e o **mesmo** hook — contá-las como dois mecanismos
independentes seria inflacionar. Com a regra conservadora aplicada, `XEN-05` fecha com o
mínimo exacto do critério: **3 de 3**, sem folga. Se a terceira migração (`0x002C0498`,
19-03) não tivesse sido feita, este documento diria **PARCIAL 2/3** com o número escrito —
e foi essa a razão declarada para a fazer.

A `18-VERIFICATION.md` avisou, a meio do marco, que o numerador defensável era **2 (ou 1
por mecanismo)** e que o marco **não podia** fechar por aí. Fica registado que o aviso foi
respeitado: o que fechou o `XEN-05` foi a Fase 19, não a reclassificação dos jumptables.

## Ressalvas do marco (o que NÃO é vitória)

Um marco que fecha com estas dez ressalvas escritas vale mais do que um que as omite
(regra 4 do `CLAUDE.md`: nunca forjar resultados). Estão por ordem de **importância para
quem retomar**, não por ordem de descoberta.

### 1. O mid-asm **não está no caminho que o jogador corre** — a ressalva maior do marco

Medido hoje, e re-medido no 21-03:

```
$ grep -rl 'gow2_midasm' ../gow2-recomp/recomp_macos_v2/     # LIFT DE PRODUCAO
(zero ficheiros)
```

Dos 21 directórios de lift do repo de build, só 6 (`recomp_macos_v3_midasm`, `_jt18`,
`_mig19`, `_mig19b`, `_mig19c`, `_ovr19`) contêm o símbolo. **Todos** os `recomp_macos_v2*`
têm zero. Isto **não é uma regressão** — o marco não promoveu nada de propósito, e a
promoção tem gate próprio (`promote_lift.sh`) e é decisão humana. Mas as consequências têm
de ser ditas sem rodeios:

- o mecanismo está **provado**, e **não está em produção**;
- o smoke T9 corre o binário de produção, logo prova **não-regressão da intro** e **não**
  o mid-asm em execução;
- os 4 fixes "re-lift-safe" são re-lift-safe **no lift onde foram provados**, não no lift
  que hoje se distribui.

Fechar esta ressalva é o **primeiro P1** da lista de handoff.

### 2. A sequência canónica 1→8 nunca foi corrida numa só passagem

`docs/RELIFT_CANONICAL.md` §7 declara-o, e está no ledger de defeitos (`WINDOWS` #16).
Cada uma das 8 etapas tem evidência isolada das Fases 16–20 (`verify_lift` `rc=0`, escada
A/B/C, `st620_max=11`), mas **a cadeia inteira como unidade continua NÃO-EXERCITADA** —
custa um lift completo + build + 6 smokes. Um documento de sequência que ninguém correu de
ponta a ponta é uma hipótese bem escrita, não um procedimento provado.

### 3. Dois patches `redundant` — nunca foram precisos, e **não** contam

`patch_jumptable_2a209c.py` e `patch_jumptable_2b11b8.py` (Fase 18). Medido que o lifter já
emitia os alvos certos. Um `redundant` documenta um patch inútil; não documenta uma
correcção que passou a sobreviver ao re-lift. Ficam **fora** do numerador do `XEN-05`, como
a `18-VERIFICATION.md` exigiu.

### 4. `RE-03` fecha só na metade soft — o MCP ficou `wont`, com bloqueios medidos

O lado CLI está feito e escrito (`docs/GHIDRA_MCP_SETUP.md` §9.2, duas âncoras:
`0x0041F700` → vazio; `0x00420A44` → `{0x00254C40}`). A sessão de **paridade pelo MCP** não
foi corrida, declarada `wont` com quatro bloqueios re-medidos na verificação da Fase 20:
GhidraMCP 1.4 declara `ghidraVersion=11.3.2` contra o Ghidra **12.1.2** instalado (o
`ExtensionInstaller` recusa); a instalação é só por GUI; reconstruir exigiria Maven, que
**não está** na máquina; e não há projecto Ghidra persistido, logo seria precisa
auto-análise nova do EBOOT. O requisito é **soft por desenho** e fecha na mesma — mas fecha
**pela metade que foi feita**, não pela que ficou por fazer.

### 5. `sticky` é NÃO-OBSERVÁVEL — e isso invalida um critério do próprio `CLAUDE.md`

Re-medido nesta fase (ver T9, ressalva 2):

```
runtime/ppu/ppu_loader.cpp:1370  ps3_fios_sticky_publish()   # sem fprintf
runtime/ppu/ppu_loader.cpp:1383  ps3_fios_sticky_peek()      # sem fprintf
runtime/ppu/ppu_loader.cpp:1393  ps3_fios_sticky_consume()   # sem fprintf
libs/video/movie_vt_metal.m:446  "...overlay_done already sticky"   # <- overlay VT, outra coisa
$ grep -ci sticky /tmp/m21_T9_smoke.log  ->  0
```

**O checklist de não-regressão pós-merge do `CLAUDE.md` prescreve `sticky_pub>=1`. Esse
critério não é verificável neste build**: um grep por `sticky` dá sempre 0, e 0 **não**
significa "sticky morto". Qualquer corrida que o tenha usado como gate mediu o nada — a
mesma classe de erro que cegou as Fases 7–10 com `thr_auto_load() end`. Isto é **dívida de
documentação do projecto**, e fica registada aqui porque é um achado do marco, não uma
falha de uma fase. O `CLAUDE.md` **não foi editado** neste marco (fora do escopo declarado
do 21-03); instrumentar os três `ps3_fios_sticky_*` está na lista P1.

### 6. O aceite `bytes_read` continua **não-exercitado**

`grep -c bytes_read` no log do T9 = **0**, com um único `[movieio] open` (o `gow2.psarc`).
Com `PS3_MOVIE_EOS=0` e 30 s, o `R_PermA` não chega a ser lido. O aceite
`smoke:bytes_read=20169344` do `patch_fallthrough_2550c8.py` continua por correr — igual à
Fase 16 (`WINDOWS` #3). Fechá-lo exige um boot com `PS3_MOVIE_EOS=1` até ao `R_PermA`, que
nenhuma fase deste marco tinha razão para gastar.

### 7. Os P0 `classe=OPD` **não são migráveis por weak** — medido, não desistido

A conversão OPD é **cirurgia no interior** da função (12 sítios em `0x0014B1F0`, 7 em
`0x0032E200`); um weak override substitui a função **inteira** e não vê o interior. Migrar
`0x0014B1F0` por weak obrigaria a reescrever **783 instruções** em código host — isso não é
migração, é reescrita, e congelaria o corpo do jogo contra o próprio re-lift que este marco
existe para tornar seguro. Consequência no ledger, medida hoje: **10 linhas com
`alvo=weak` continuam `todo`** — 3 P0 (todas `OPD`) e 7 P1 (6 `OPD` + 1 `CORRECTNESS`,
`patch_wad_state_machine.py`). O `alvo=weak` das linhas OPD fica **por rever**, com o
candidato natural anotado: uma opção do **lifter** que converta OPD por declaração, não um
hook host.

### 8. `analyze_eboot_ghidra.sh` não correu de ponta a ponta neste marco

A sessão de RE da Fase 20 usou o `ghidra_out/` **existente** (25/jul, 13 143 funções,
13 096 decompiladas), com proveniência verificada (`elf_sha256` bate com o EBOOT). Nada
nessa sessão dependia de análise nova — mas fica dito que **a re-análise headless não foi
exercitada** neste marco (custa dezenas de minutos a horas). O script existe em
`games/gow2/analyze_eboot_ghidra.sh` e no espelho.

### 9. `patch_fallthrough_2550c8.py` foi **reclassificado**, não migrado

`alvo=lifter` (Fase 17). O fix do fallthrough cross-fragment pertence ao **lifter**, não a
um hook host — e por isso continua a ser um `patch_*.py` reaplicado. A auditoria sistemática
do padrão (alvo de trampolim com EA guest **menor** que o site) que o `CLAUDE.md` manda
fazer continua **P1 e por começar**.

### 10. A cópia do `verify_lift.sh` no checkout de build está desactualizada

`../gow2-recomp/verify_lift.sh` é a versão **anterior à Fase 20** (`grep -c VERIFY_ORACLE`
→ **0**, contra **10** na cópia do motor). O caminho de aceite **nunca** a usa — o
`accept_relift.sh` resolve sempre pela cópia do motor via `PS3_ENGINE_ROOT` — mas quem
correr `./verify_lift.sh` à mão dentro do checkout de build apanha a versão antiga, sem o
passo de oráculo. Sincronizar o espelho é dívida do v1.0, **explicitamente diferida** no
`21-CONTEXT.md`; fica aqui para não ser uma surpresa.

## Handoff

### A. O que este marco desbloqueia para a wall D (e para a Fase 11)

O material accionável **não** veio da wall D directamente: veio da sessão de RE da Fase 20
sobre a **parede 4**, corrida com o playbook novo e registada em
`docs/re_sessions/2026-08-02-wall-4-walk-de-tipos.md`. O achado, medido estaticamente:

- a tabela de tipos `PTR_DAT_0053ef1c` é escrita por **uma única** função, `0x0041FA90`,
  que indexa por `((w0 >> 16) & 0xFFF) * 4` — isto é, **pelo `subtag`**;
- mas **12 dos 18 consumidores** indexam pelo campo **baixo**, `w0 & 0xFFFF` — e entre eles
  está a **parede 1**, `func_002545B0`, e o próprio push do walk, `func_0041F700`;
- os dois campos **coincidem** em `0xC0010001` (família *listas*: 1 == 1) e **divergem** em
  `0x40030001` (família *registo WAD*: **1 ≠ 3**);
- consequência prevista: um nó com `low16 != subtag` é **empurrado** para o gestor 1 e
  **retirado** do gestor 3 ⇒ o cursor do gestor 1 nunca desce e o walk nunca desenrola.

**Porque isto importa para a Fase 11:** o critério 1 da Fase 11 listava **duas** hipóteses
exclusivas para a parede 1 ("ou o tag do objecto está errado, ou `tab[1]` despacha para a
fábrica errada"). Existe uma **terceira**, consistente com toda a medição: o objecto tem
**dois** campos de tag, e o caminho de push escolhe o **baixo** enquanto a tabela é
registada pelo **alto**. O critério tem de ser reformulado para a acomodar antes de
qualquer bissecção.

**O próximo experimento já está desenhado** (`E1` da sessão, o discriminador): sonda
`PS3_TYPEWALK_TRACE=1`, **OFF por default**, no push `0x0041F700`, a despejar `w0`,
`low16`, `subtag`, `tab[low16]`, `tab[subtag]` e o cursor `*(char*)(mgr+0xC8)`, limitada a
~200 linhas. Duas previsões **opostas**, escritas antes da corrida:

| se o mecanismo for real | se for falso |
|---|---|
| aparecem nós com `low16 != subtag`; para esses `tab[subtag]` é não-nulo e ≠ `tab[low16]`; o cursor do gestor `tab[1]` sobe monotonicamente e passa de 32 | todos os nós têm `low16 == subtag`; o cursor sobe e desce ⇒ a explosão é combinatória e H4 fica de pé |

**O que este marco NÃO afirma:** a wall D **não foi tocada**, as quatro paredes da Fase 11
continuam **abertas**, e nada aqui é uma afirmação sobre pixels, shaders ou `SHADERSRC`. A
sessão de RE fechou com veredicto **ABERTO** — e "ainda aberto" é resultado válido.

**O que muda para quem retomar a Fase 11:** as correcções que essa fase produzir passam a
ter caminho para sobreviver a um re-lift (mid-asm, weak override, switch table declarada),
que era exactamente a razão de o v1.3 vir primeiro.

### B. A lista P1 seguinte (dentro do próximo marco)

Por ordem de valor, com a ressalva que cada item fecha:

| # | Trabalho | Fecha a ressalva |
|---|---|---|
| 1 | **Promover a produção um lift com mid-asm** (gate próprio, `promote_lift.sh`, decisão humana) — pôr o mecanismo no caminho do jogador | **1** |
| 2 | **Correr a sequência canónica 1→8 numa só passagem** e promover a §7 do `RELIFT_CANONICAL.md` de NÃO-EXERCITADA a medida | **2** (`WINDOWS` #16) |
| 3 | **Auditoria sistemática do fallthrough cross-fragment** (alvo de trampolim com EA guest menor que o site — o padrão do fix `2550C8`) no lift inteiro | **9** |
| 4 | **Rever o `alvo` das 10 linhas `weak`+`todo`** — em especial as OPD, cujo candidato é uma opção do **lifter**, não um hook host | **7** |
| 5 | **Instrumentar `ps3_fios_sticky_publish/_peek/_consume`** e só então decidir se `sticky_pub>=1` volta a ser critério de aceite | **5** |
| 6 | **Correr o aceite `smoke:bytes_read=20169344`** do `patch_fallthrough_2550c8.py` num boot com `PS3_MOVIE_EOS=1` | **6** |
| 7 | Mais migrações mid-asm/weak a partir das 72 linhas `CORRECTNESS` ainda `todo` | — (baixa o numerador da métrica) |
| 8 | Sincronizar `../gow2-recomp/verify_lift.sh` com a cópia do motor (dívida do v1.0) | **10** |

### C. Explicitamente **FORA** do próximo marco

Escrito aqui para que o próximo marco **não herde scope creep por omissão** — cada um
destes precisa de plano próprio e de gate próprio:

| Item | Porquê fica fora |
|---|---|
| **Opts de ABI** (`*_as_local`, `skip_lr`) | Optimização, não correctness. Gate duro herdado: não começar antes de A+B completos e smoke `thr` verde em chunks re-liftados (`REQ-xenon-abi-local-opts`) |
| **SIMDe** para VMX + expansão do corpus `lift_selftest` | Plano próprio (`REQ-xenon-simde-and-opcode-suite`); não bloqueia nada aqui |
| **Shader recomp** | `REQ-xenon-shader-recomp-design` é **só** a nota de design; nenhum código antes de entender o caminho LDRSH natural. Depende da wall D, que este marco não tocou |
| Promover `spu2`/`spu3` a default | Dívida do v1.0, sem relação com o lift PPU |
| Reconciliar o espelho subtree | Dívida do v1.0, diferida no `21-CONTEXT.md` |

### D. Onde continuar a ler

| Documento | O que tem |
|---|---|
| `docs/RELIFT_CANONICAL.md` | As **8 etapas** canónicas do re-lift, com comandos, critério por etapa e nível de evidência declarado (§7) |
| `games/gow2/accept_relift.sh` | O aceite de 4 pernas; a perna 2 (`verify_lift.sh`) está em `:73` |
| `games/gow2/lift_baseline/PATCH_MIGRATION.tsv` | O ledger patch→mecanismo, com o baseline da Fase 16 congelado no cabeçalho |
| `docs/re_sessions/2026-08-02-wall-4-walk-de-tipos.md` | A sessão de RE que produziu o handoff da secção A |
| `docs/RE_PLAYBOOK_GOW2.md` | O método usado nessa sessão (6 secções, incluindo os anti-padrões) |
| **A suite T1–T10 deste ficheiro** | O `rc` de cada linha, o comando exacto e o log |

