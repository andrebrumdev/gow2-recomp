# Veredito Gate A — Track M (M0–M5) — 2026-07-23

**Fecho honesto:** Gate **B GREEN**, Gate **A RED**. Menu UI **NO**. Playable **NO**.

Track M (TYPE15 / CC9D0 / frame loop pós-B71) **fecha o diagnóstico** com
medição e um fix estrutural (M2 CLOSE-PRESERVE). **Não** fecha o wall de menu:
o guest ainda não reentra em present/pad após open de WAD.

Índices:
- `ps3recomp/docs/superpowers/plans/2026-07-23-00-gow2-playable-master-INDEX.md`
- `ps3recomp/docs/superpowers/plans/2026-07-20-00-wall-chain-INDEX.md`
- Plano tasks: `ps3recomp/docs/superpowers/plans/2026-07-23-menu-type15-frame-loop.md`

Recipe canónico: `./rodar_gow2_menu_fast.sh` (ou env equivalente) +
`python3 count_menu_gate.py <log>`; kill por PID; `PS3_NO_RSX=1` suficiente
para métricas de SetFlip/pad (printf guest).

---

## Tabela final de gates (medida nesta track)

| Gate | Status | Evidence |
|------|--------|----------|
| **B** | **GREEN** | thr_end≥1, R_Perm full **20169344**, StartSeq real (≥2 async path / FORCE+REPLAY-NOPIC), **PARK=0**, **FATAL=0**; smokes M0–M4 |
| **A** | **RED** | **SetFlip_after_R_Perm=0**, **Pad_after_R_Perm=0** após linha R_Perm full / B71 |
| **Menu UI** | **NO** | sem FSM de menu / NewGame / Press Start pós thr; st620 só `0→0` com `overlay_done=1` |
| **Playable** | **NO** | explícito — não claim |

### Contagens representativas (pós-M2 product list; M3 baseline NO_RSX)

| Métrica | Valor |
|---------|-------|
| thr_end | 1 |
| R_Perm full 20169344 | 1 |
| PARK / FATAL | 0 / 0 |
| CLOSE-PRESERVE / attach=full | 2 / 2 |
| SetFlip_total (intro pré-WAD) | milhares (ex. 3815–26k) |
| **SetFlip_after_R_Perm** | **0** |
| **Pad_after_R_Perm** (`cellPadGetData`) | **0** |
| Pad_total | **0** (guest nunca chama GetData neste boot) |
| ICALL-BAD after R_Perm | **12×** `ctr=0x40637488` |
| CC9D0 live this | só **2** EAs (`0x4066D798`, `0x4066D804`), f4=f54=**0** |

Timeline crítica: último `SetFlipCommand` **antes** de `movieio open` de
`R_LglScA` / stream `R_PermA` — zero flip/pad até timeout após R_Perm full.

---

## Progresso shipped (commits gow2-recomp)

| Task | SHA | Mensagem / outcome |
|------|-----|--------------------|
| **M0** | `5920aff` | `docs(gow2): baseline M0 menu-fast Gate B green / A red` — freeze counts + md5 |
| **M1** | `967525e` | `diag(gow2): discriminador CC9D0/TYPE15 pós-attach (M1)` — H1 primary (+ H3) |
| **M1 I1** | `b87e6a3` | `fix(gow2): alinhar env_on C/Python do disc TYPE15 (M1 I1)` |
| **M2** | `1f5d61c` | `fix(gow2): TYPE15 product/list preserve pós-sanitize (M2 — H1)` — CLOSE-PRESERVE nodes=12; f4 still 0 |
| **M3** | `90829b6` | `diag(gow2): M3 post-B71 flip still blocked — guest abandona present pós-WAD` — metrics + root class |
| **M4** | `e7cf689` | `diag(gow2): M4 pad/menu still blocked pós-WAD` — pad never polled post-WAD |
| **M5** | *(este commit)* | `docs(gow2): veredito Gate A RED Track M (M0–M4)` — fecho honesto |

Notas por task (mesmo repo):

| Task | Nota |
|------|------|
| M0 | `notes/2026-07-23-m0-baseline-counts.md` |
| M1 | `notes/2026-07-23-m1-cc9d0-discriminator.md` |
| M2 | `notes/2026-07-23-m2-product-fix.md` |
| M3 | `notes/2026-07-23-m3-postb71-flip.md` |
| M4 | `notes/2026-07-23-m4-pad-menu.md` |
| M5 | `notes/2026-07-23-gate-a-verdict.md` (este ficheiro) |

### Resumo de outcomes

| Task | Resultado honesto |
|------|-------------------|
| M0 | Baseline: B green / A red |
| M1 | Survivor **H1** (lista esvaziada pelo RESET over-aggressive); H3 co-sinal (só 2 this) |
| M2 | **PASS estrutural** CLOSE-PRESERVE (`child_head` real, nodes=12); **f4 residual 0**; flip ainda 0 |
| M3 | Infra `count_menu_gate.py`; YIELD/LIVE_SKIP **não** desbloqueiam flip → root class: guest abandona present no open WAD |
| M4 | Pad Init cedo; **zero** GetData/GetInfo2; autostart HLE pronto mas não exercitado; sem menu strings reais |
| M5 | Docs/INDEX; **Gate A permanece RED** |

---

## Root class (após M0–M4)

**Primária:** o guest **abandona** o path de present/frame flip ao sair de
movie/logo para load de WADs e **não reentra** em `cellGcmSetFlip*` até timeout.

**Não é (sozinho):** backend silencioso; giant-lock sem yield no tick TYPE15;
lista TYPE15 vazia (M2 resolveu nodes=12 — necessário, **não suficiente**).

**Co-sinais abertos:**

| Sinal | Nota |
|-------|------|
| CC9D0 f4=f54=0 nos 2 objs TYPE15 | writer de avanço (enum 1/5/6/…) não corre |
| parent scene list não cresce | só 2 `this` pós-B71 |
| ICALL-BAD `0x40637488` ×12 | vtable/heap cookie `r12=0x40004024` — candidato UI/render partido |
| st620 0→0 pós thr | title / 2nd-movie FSM idle |
| pad poll zero | vive no frame path que não reentra |

---

## Wall seguinte (não “Track S first” às cegas)

**Wall activo = post-WAD present / frame arm** — não empty-list alone, não pad HLE.

Prioridade de RE/diag:

1. Quem **deveria** chamar `cellGcmSetFlip*` no frame loop **após** open WAD
   (caller do último flip pré-WAD; path pós `R_LglScA` / thr / B71).
2. Origem de **ICALL-BAD `0x40637488`** (ctr / freelist / TOC).
3. Quem escreve **f4 ∈ {1,5,6,7,8,9}** no fluxo natural (não forjar UNSTICK).
4. Só depois: esperar pad poll / menu FSM (M4 provou autostart inútil sem GetData).

**Não** promover `PS3_CC9D0_LIVE_SKIP` / YIELD a default — medidos inúteis para flip.

---

## Follow-ups Track S / G / M3+ (entrada)

### Track S (shaders naturais) — **entry bloqueada** até flip/present ou entry forçada sem theater

| Item | Aceite alvo | Nota |
|------|-------------|------|
| Nested typemap walk natural pós-R_Perm | ICGLdrShader / `[LDRSH]` N>0 sem stream sintético | historicamente gated em frame/movie mode |
| SHADERSRC non-empty + set_shader hash ≠ demo | Track S + pixels | **não** CRC bypass |
| Planos | `2026-07-21-shader-registry-typemap-walk.md`, `2026-07-20-05-rsx-shaders-pixels.md` | P1 **após** reentrada present **ou** prova de que walk é independente de flip |

### Track G (Metal) — paralelo

- Metal stack M0/M1 overlay+draw path já GREEN no eixo GPU.
- M2+ MSL/tex/state não contam como menu; pixels de jogo exigem draws guest (S/M).

### Track M residual / M3+

| Item | Acção |
|------|--------|
| Present arm pós-WAD | RE + probes gated; critério SetFlip_after_R_Perm≥1 |
| ICALL-BAD 0x40637488 | classificar corrupt vs path morto |
| f4 writers | RE estática + store probe se necessário |
| Pad/menu | re-smoke só **depois** de flip≥1 pós-R_Perm |

### Theater blacklist (ainda em vigor)

- Sem PARK como StartSeq; sem soft-park CE03C; sem claim menu por FlashUI sparse;
  sem CC9D0-SKIP como menu; sem “playable” com Gate A red.

---

## Constraints honrados nesta track

- Kill por PID; probes OFF default; sem dados de jogo nos commits.
- Commits PT, sem Co-Authored-By.
- Aceites distinguem in-boot vs offline; **playable não claimado**.
