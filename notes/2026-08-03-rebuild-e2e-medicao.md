# Rebuild do lift E2E — o experimento discriminador do passo 0

**Data:** 2026-08-03 · **Máquina:** Apple Silicon (macOS/arm64)
**Objecto:** o passo 0 de [`2026-08-03-seis-patches-que-nao-reaplicam.md`](2026-08-03-seis-patches-que-nao-reaplicam.md) §8 —
rebuild do `recomp_macos_v3_e2e` **que já estava em disco**, para medir o efeito real dos três
patches que a 2.ª passagem aplicou e que o binário testado no E2E nunca teve.
**Zero código de produto escrito.** Nenhum patch corrigido, nenhum script editado, nenhuma promoção.
**Binário novo:** `boot_gow2_v3e2e_r2` (não versionado) · **Logs:** `/tmp/*` (G6)

---

## Veredicto directo

> **O elo moveu-se. De 2 para 4. Os dois elos perdidos foram recuperados na íntegra —
> e num elo informativo o lift fresco passa à frente da produção.**

Em **6 de 6** corridas que sobreviveram ao flake da intro, o binário reconstruído pára
exactamente onde a produção pára (`AUTO_LOAD (nunca criada)`, elo 4), com `r_perma=1`
(o `R_PermA` abre — era `0` no E2E) e `setflip_after_rperm=10` contra **`0`** da produção
medida na mesma sessão.

**A hipótese explícita da §8 da análise — «a correspondência é forte, mas é uma hipótese» —
está confirmada por medição.** Os três patches `ORDEM` são, sozinhos, os dois elos.

E o que não se moveu diz-se com a mesma clareza: **o gate continua `rc=1`**. A thread
`AUTO_LOAD` não é criada em nenhuma das 9 corridas, tal como não é criada na produção.
Essa parede não era do re-lift e continua de pé.

---

## 1. Estado confirmado ANTES de qualquer build

A premissa foi verificada antes de gastar um segundo de compilação.

| Verificação | Resultado |
|---|---|
| `recomp_macos_v3_e2e/` existe? | **sim** — mtime `2 ago 23:19` |
| `AREAD-HLE` no texto do lift | **presente 1×** (`ppu_recomp_001.cpp`) |
| `FIOS-HOST-POP` no texto do lift | **presente 1×** (`ppu_recomp_001.cpp`) |
| `FIOS-DONE-YIELD` no texto do lift | **presente 1×** (`ppu_recomp_001.cpp`) |
| Contagem igual à produção? | **sim** — `1 / 1 / 1` nos dois lifts |
| A 2.ª passagem aplicou o quê, exactamente? | `accept_..._status.tsv`: **5 `APPLIED`** — os 3 acima (`FUNCIONAL`) + `flip_path_enter_probe` e `menu_present_schedule_probe` (`PROBE`) |
| Os 2 `PROBE` re-aplicados duplicaram blocos? | **não** — `FLIPPATH-PROBE` 12 e `MENUPRESENT-PROBE` 18, **idênticos à produção** |

**Chunks stale (é o que torna o rebuild barato e honesto):**

```
ppu_recomp_000.cpp  cpp=23:35:22  o=23:18:51  -> STALE (recompila)
ppu_recomp_001.cpp  cpp=23:35:39  o=23:18:50  -> STALE (recompila)
ppu_recomp_002.cpp  cpp=23:11:12  o=23:18:48  -> ok
ppu_recomp_003.cpp  cpp=23:33:19  o=23:18:49  -> STALE (recompila)
ppu_recomp_004/005/006                        -> ok
```

Confirma-se a mecânica que o defeito D1 descreve: o binário de 23:16 foi linkado com `.o` de
23:18 (a compilação corre antes do link, ambos anteriores à 2.ª passagem das 23:33–23:35),
e os três chunks que a 2.ª passagem tocou ficaram **por recompilar**.

---

## 2. O build — `rc=0`

**Forma separada, sem `RELIFT=1`** (é precisamente o defeito D1: `RELIFT=1` regeneraria o lift
do zero e deitaria fora os patches que queremos medir):

```
PS3_ENGINE_ROOT=/…/ps3recomp OUT=./boot_gow2_v3e2e_r2 ./build_macos.sh ./recomp_macos_v3_e2e
```

| Métrica | Valor |
|---|---|
| **`rc`** | **0** |
| Duração total | **~64 s** (`00:50:30 → 00:51:34`); passo 1 `dur=17s`, `errors=0` |
| Chunks recompilados | **3 / 7** — `000`, `001`, `003` a `00:50:47–49`; `002/004/005/006` intactos em `23:18` |
| Avisos de duplicate-symbol / override | **nenhum** — os 4 `functions_override` compilaram nomeados |
| Binário | `boot_gow2_v3e2e_r2`, 121 684 128 B (**+16 720 B** face ao de 23:16) |

**Prova de que os fixes entraram mesmo no binário** — e é a parte que fecha a premissa:

| Assinatura | `boot_gow2_v3e2e_r2` | `boot_gow2_v3e2e` (23:16) | `boot_gow2` (produção) |
|---|---:|---:|---:|
| string `AREAD-HLE` | **2** | **0** | 2 |
| string `PS3_FIOS_HOST_POP` | **1** | **0** | 1 |
| símbolo `ps3_fios_aread_hle` (`nm`) | **1** | **0** | 1 |
| `md5` | `9f7ab513…` | `1b19fc05…` | — |

O binário do E2E **não tinha** nenhum dos três. O reconstruído tem os três, com a **mesma
contagem da produção**. `FIOS-DONE-YIELD` não emite string própria (é um
`release / yield_sleep1 / acquire` puro, sem `printf`) — vive no chunk `001`, que foi recompilado.

---

## 3. As corridas — `smoke_chain_gate.sh --bin`, 9 corridas + 6 de controlo

Instrumento: `./smoke_chain_gate.sh --bin <BIN> 3 <TSV>`, três lotes. **Sem rebuild** (modo
`--bin`), kill por PID via `measure_one()`, timeout 90 s.

### 3.1 Candidato — `boot_gow2_v3e2e_r2` (9 corridas)

| # | hora | `st620` | `startseq` | `nopic` | `thr_created` | `r_perma` | `setflip_after_rperm` | **`elo_stopped`** | OOB | `0xFFFF` | `ICALL-BAD` | `FATAL` |
|---|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|
| 1 | 00:52:25 | 1 | 0 | 0 | 0 | 0 | 0 | `intro (st620)` | 0 | 0 | 0 | 0 |
| 2 | 00:53:58 | 1 | 0 | 0 | 0 | 0 | 0 | `intro (st620)` | 0 | 0 | 0 | 0 |
| 3 | 00:55:30 | **11** | **2** | **4** | 0 | **1** | **10** | **`AUTO_LOAD (nunca criada)`** | 1 | 1 | 12 | 1 |
| 4 | 00:56:23 | **11** | **2** | **4** | 0 | **1** | **10** | **`AUTO_LOAD (nunca criada)`** | 1 | 1 | 12 | 1 |
| 5 | 00:56:57 | 1 | 0 | 0 | 0 | 0 | 0 | `intro (st620)` | 0 | 0 | 0 | 0 |
| 6 | 00:58:30 | **11** | **2** | **4** | 0 | **1** | **10** | **`AUTO_LOAD (nunca criada)`** | 1 | 1 | 12 | 1 |
| 7 | 00:59:22 | **11** | **2** | **4** | 0 | **1** | **10** | **`AUTO_LOAD (nunca criada)`** | 1 | 1 | 12 | 1 |
| 8 | 00:59:57 | 1 | 0 | 0 | 0 | 0 | 0 | `intro (st620)` | 0 | 0 | 0 | 0 |
| 9 | 01:01:29 | **11** | **2** | **4** | 0 | **1** | **10** | **`AUTO_LOAD (nunca criada)`** | 1 | 1 | 12 | 1 |

**`elo_stopped` = elo 4 em 6/9. Elo 2 em 0/9. Elo 3 em 0/9.** As 3 corridas restantes morrem no
elo 1 (`st620≤1`) — o flake conhecido, que existe nos três binários (ver §4.3). `rc` do gate: **1**
nos três lotes (`elo_stopped=nenhum` em 0 de 3, limiar 2) — o gate continua a rejeitar, e com
razão: a `AUTO_LOAD` nunca é criada.

TSVs: `/tmp/r2_chain_{a,b,c}.tsv`.

### 3.2 Controlo A — `boot_gow2_v3e2e` (o binário de 23:16), mesma sessão

| # | `st620` | `startseq` | `nopic` | `r_perma` | `setflip` | `elo_stopped` | OOB | `ICALL-BAD` | `FATAL` |
|---|---:|---:|---:|---:|---:|---|---:|---:|---:|
| 1 | 11 | **1** | 0 | **0** | 0 | **`2o movie (StartSeq)`** | 0 | 0 | 0 |
| 2 | 11 | **1** | 0 | **0** | 0 | **`2o movie (StartSeq)`** | 0 | 0 | 0 |
| 3 | 0 | 0 | 0 | 0 | 0 | `intro (st620)` | 0 | 0 | 0 |

**Reproduz o elo 2 do E2E.** É o controlo que fecha o argumento: o mesmo lift, a mesma máquina,
a mesma receita — só muda o rebuild dos 3 chunks. TSV: `/tmp/ctl_e2e_old.tsv`.

### 3.3 Controlo B — `boot_gow2` (produção, **só lida**), mesma sessão

| # | `st620` | `startseq` | `nopic` | `r_perma` | `setflip` | `elo_stopped` | OOB | `0xFFFF` | `ICALL-BAD` | `FATAL` |
|---|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|
| 1 | 11 | 2 | 4 | 1 | **0** | `AUTO_LOAD (nunca criada)` | **19** | **16** | 12 | 1 |
| 2 | 1 | 0 | 0 | 0 | 0 | `intro (st620)` | 0 | 0 | 0 | 0 |
| 3 | 11 | 2 | 4 | 1 | **0** | `AUTO_LOAD (nunca criada)` | **19** | **16** | 12 | 1 |

Reproduz o 2/3 documentado no E2E. TSV: `/tmp/ctl_prod.tsv`.

---

## 4. Comparação com os dois pontos de referência

### 4.1 A resposta à pergunta

| | E2E (`boot_gow2_v3e2e`, 23:16) | **Rebuild (`_r2`)** | Produção (`boot_gow2`) |
|---|---|---|---|
| `st620` | 11 em 6/6 | 11 em **6/9** | 11 em 2/3 |
| `startseq` (2.º movie) | **1** | **2** | **2** |
| `nopic` (re-Play) | **0** | **4** | **4** |
| `r_perma` (WAD) | **0** | **1** | **1** |
| `setflip_after_rperm` | 0 | **10** | **0** |
| `thr_created` (AUTO_LOAD) | 0 | **0** | **0** |
| **`elo_stopped`** | **elo 2** — `2o movie (StartSeq)` | **elo 4** — `AUTO_LOAD (nunca criada)` | **elo 4** — `AUTO_LOAD (nunca criada)` |
| `rc` do gate | 1 | **1** | 1 |

> **Chega ao elo 4, como a produção. Não fica no 2, nem pára a meio.**
> Elo 2 → elo 4: **+2 elos**, exactamente os dois que o E2E tinha perdido.

Os três elos intermédios movem-se todos juntos e todos para o valor da produção:
`startseq` 1→2, `nopic` 0→4, `r_perma` 0→1. Não é um elo a passar por sorte — é a cadeia
FIOS/movie-io inteira a voltar a funcionar, que é precisamente o que os três patches fazem
(`op_alloc` devolve a op, o read assíncrono devolve bytes ao `.m2v`, o poller do done-word
recebe o lock).

### 4.2 Onde o rebuild passa à frente da produção

`setflip_after_rperm` = **10** no `_r2` (6/6 das corridas de elo 4) contra **0** na produção
(0/2 das corridas de elo 4, medido nesta mesma sessão). É um elo **informativo** — não decide
`elo_stopped` nem o `rc` — mas é um `SetFlip` observado **depois** do `R_Perm`, que na produção
não acontece de todo. **Medido, não explicado.** Candidato natural: o corpus de patches do lift
fresco tem 114 `APPLIED` da 1.ª passagem que a produção acumulou em gerações diferentes; não
investiguei qual.

E o lift fresco é **mais limpo** no ruído de memória: `OOB` **1** contra 19, `0xFFFF` **1**
contra 16, com o mesmo `ICALL-BAD=12` e o mesmo `FATAL=1`.

### 4.3 O flake da intro não é novo

| Binário | corridas | `st620 ≤ 1` |
|---|---:|---:|
| `_r2` (rebuild) | 9 | **3** (33 %) |
| `boot_gow2_v3e2e` (23:16) | 3 | **1** (33 %) |
| `boot_gow2` (produção) | 3 | **1** (33 %) |
| produção no E2E (23:40) | 3 | 1 (33 %) |

Mesma taxa nos três binários, na mesma sessão. **Não há evidência de que os 3 patches
tenham introduzido ou agravado o flake** — e o `FIOS-DONE-YIELD` mexe em timing de lock, por
isso a pergunta tinha de ser feita. Amostras pequenas (3–9); é um empate observado, não uma
prova de igualdade.

### 4.4 O `FATAL` é diferente do da produção — e isso é um lead

Ambos abortam por `stuck calling … (2000 times)`, mas em **sítios diferentes**:

```
_r2:       [ppu] FATAL: stuck calling 0x00514E80 (2000 times)
           [ICALL-BAD] ctr=0x00514E80 lr=0x0024E2D4 r3=0 r11=0 r12=0x88004044   (×12)
producao:  [ppu] FATAL: stuck calling 0x000B9354 (2000 times)
           [ICALL-BAD] ctr=0x40637408 lr=0x002BACE4 r3=0x400C3D88 …             (×12)
```

O stack do `_r2` no `FATAL` passa por `func_000B71B8`. **Hipótese, não facto:** é o patch #4
(`patch_b71_cb56c_reuse_block.py`), que continua `FAILED` e que a produção tem — o `_r2` não
tem o `g_b71_product_reused` nem o skip do `icallB`. O `lr=0x0024E2D4` cai na vizinhança de
`func_0024E3D0` (o patch #6), mas o #6 é um gate `OFF` por default e não escreve nada sem
`PS3_24E3D0_KEEP_TYPE_ON_NULL=1` — não explica o `stuck`. **Não investigado nesta sessão.**

---

## 5. O que isto diz sobre os 6 patches

| Patch | Categoria medida (análise 08-03) | **O que esta medição acrescenta** |
|---|---|---|
| #1 `2b3d1c_movie_io` (`AREAD-HLE`) | ORDEM | **vale elos.** Os três juntos = +2 elos, medido |
| #2 `fios_done_yield` | ORDEM | idem |
| #3 `fios_host_pop` | ORDEM | idem |
| #4 `b71_cb56c_reuse_block` | contaminação da âncora | **não bloqueia o elo.** Continua `FAILED` e o boot chega na mesma ao elo 4. Fica como dívida de `MANIFEST` (4 das 5 dívidas reais) e como suspeito do `stuck` divergente |
| #5 `b71_skip_icallb_reuse` | cascata de #4 | idem, fecha com #4 |
| #6 `24e3d0_null_product_gate` | falha também em produção | **confirmado irrelevante ao elo** — o `_r2` chega ao elo 4 sem ele, tal como a produção |

**Consequência para o caminho mais curto da §8:**

- O **passo 1** (ordem explícita no `apply_all_patches.sh`, 5 relações) deixa de ser uma aposta:
  as três primeiras relações valem, medidamente, **dois elos**. É a correcção com melhor
  relação custo/valor de toda a lista.
- O **passo 3** («re-correr 1→8 e ver se o `elo_stopped` volta a `AUTO_LOAD`») está, **de facto,
  antecipado e respondido: volta.** O que falta ao passo 3 é fazê-lo pela via limpa — uma
  1.ª passagem que já aplique tudo — em vez de depender de uma 2.ª passagem acidental.
- O **passo 7** (migrar #4 para weak override) continua a ser destino, não desbloqueio. Confirmado:
  o elo não depende dele.
- O defeito **D1** ganha uma medição a acompanhá-lo: o binário do E2E era, literalmente, dois
  elos pior do que a árvore de que saiu. **A janela entre «lift patchado» e «binário linkado»
  custa elos reais.**
- O defeito **D2/§7** ganha o mesmo: a 2.ª passagem que mascara falhas de ordem foi, aqui, o que
  produziu a árvore boa. O gate declarou verde uma coisa que o binário não tinha — e a diferença
  entre as duas coisas são dois elos.

---

## 6. Higiene (G6)

| Regra | Estado |
|---|---|
| Produção intacta | **cumprido** — `recomp_macos_v2` e `boot_gow2` não escritos; `boot_gow2` só **executado** como controlo |
| Promoção | **NÃO FEITA** — `promote_lift.sh` não invocado |
| Kill por **PID** (`TERM` → `-9`) | **cumprido** — 15 boots via `measure_one()`; nenhum `pkill -f` |
| Órfãos no fim | **0** (`pgrep -f boot_gow2` = 0, verificado antes e depois) |
| Logs fora dos dois repos | **cumprido** — `/tmp/r2_*`, `/tmp/ctl_*`, `/tmp/chain_gate_*` |
| `timeout(1)` | **não usado** (não existe no macOS) — o poll por segundo do `measure_one()` |
| `sticky_pub>=1` como critério | **não usado** |
| Código de produto escrito | **nenhum** — zero patches, zero scripts, zero baselines tocados |
| Sessão de RE paralela (`docs/re_sessions/`) | **não tocada**; `recomp_mid_v2/patch_41f78c_prune_probe.py` (`M` de outra sessão) fica fora deste commit |

**Divergência de protocolo, declarada:** o pedido especificava `PS3_NO_RSX=1` e
`PS3_RSX_BACKEND=trace`. O `smoke_chain_gate.sh` fixa a receita internamente
(`arm_menu_fast_recipe()` exporta `PS3_RSX_BACKEND=metal`) e **editar scripts estava
interdito**. Os dois pontos de referência — a perna 4 do E2E e o controlo de produção — foram
ambos medidos com essa receita; medir o candidato com outra tornaria a comparação inválida,
que é o único objectivo desta sessão. **Corri com a receita do instrumento**, e os dois
controlos da mesma sessão garantem que a comparação é entre iguais.

---

## 7. O que ficou por exercitar

| # | Item | Porquê |
|---|---|---|
| 1 | Ordem explícita no `apply_all_patches.sh` | **não implementada** — esta sessão é medição; o script não foi editado |
| 2 | Sequência 1→8 completa com a ordem corrigida | não corrida. Esta medição é o **atalho** ao passo 3, não o passo 3 |
| 3 | Causa do `setflip_after_rperm=10` vs `0` | **medido, não explicado** |
| 4 | Causa do `stuck 0x00514E80` (vs `0x000B9354` da produção) | **hipótese não testada** (§4.4) |
| 5 | `verify_lift.sh` / `accept_relift.sh` sobre o `_r2` | não corridos — nenhuma promoção em vista, e o gate da cadeia já respondeu à pergunta |
| 6 | `AUTO_LOAD` nunca criada | **parede pré-existente**, igual na produção. Nada aqui é uma afirmação sobre ela |
| 7 | As 4 paredes da Fase 11 | **não tocadas** |

---

## 8. Nível de evidência (regra 4 do `CLAUDE.md`)

| Item | Nível |
|---|---|
| 3 marcadores presentes no lift antes do build; chunks stale | **medido offline** nesta sessão |
| `rc=0` do build, 3/7 chunks recompilados, +16 720 B | **medido** nesta sessão |
| `AREAD-HLE`/`PS3_FIOS_HOST_POP`/`ps3_fios_aread_hle` no binário `_r2` e ausentes no de 23:16 | **medido offline** (`strings`, `nm`) nesta sessão |
| `elo_stopped` = elo 4 em 6/9 no `_r2` | **medido in-boot**, 9 corridas |
| `elo_stopped` = elo 2 no binário de 23:16 | **medido in-boot**, controlo de 3 corridas na mesma sessão |
| `elo_stopped` = elo 4 na produção, `setflip=0` | **medido in-boot**, controlo de 3 corridas na mesma sessão |
| Taxa do flake da intro igual nos três binários | **medido**, amostras pequenas (3–9) |
| `OOB` 1 vs 19 e `stuck` em sítios diferentes | **medido**, **não explicado** |
| #4 ser a causa do `stuck` divergente | **HIPÓTESE — não testada** |
| Efeito da ordem explícita no `apply_all_patches.sh` | **NÃO-EXERCITADO** — não foi implementada |

---

## Referências

- `games/gow2/notes/2026-08-03-seis-patches-que-nao-reaplicam.md` — a análise; §8 passo 0 é isto
- `games/gow2/notes/2026-08-02-e2e-relift-completo.md` — o E2E e os dois pontos de referência
- `games/gow2/smoke_chain_gate.sh` · `lib_boot_chain_metrics.sh` — o instrumento (não editado)
- `../gow2-recomp/build_macos.sh` — forma separada, sem `RELIFT=1` (defeito D1)
- Logs não versionados (G6): `/tmp/r2_build.log`, `/tmp/r2_chain_{a,b,c}.tsv`,
  `/tmp/ctl_e2e_old.tsv`, `/tmp/ctl_prod.tsv`, `/tmp/chain_gate_boot_gow2*_2026080*.log`
