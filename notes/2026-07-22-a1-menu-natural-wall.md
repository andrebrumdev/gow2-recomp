# A1 / bind-draw natural — parede pós-logos (2026-07-22)

## Objectivo

Destravar **bind/draw natural** de assets WAD/UI **ou** o caller do typemap walk
(A1) — caminho do **menu**, não a fila HOSTRES de logos.

## Medições (boot natural, R_Perm full, ~50–55 s)

| Sinal | Sem SPU1 | Com `PS3_SPU1=1` (agora default) |
|-------|----------|----------------------------------|
| spu1 MISS `0x2A5C4E67…` | >0 | **0** |
| spu1 HIT | 0 | **≥2**, SPUJOB clean |
| `[A1-468C3C]` / CMP-ENTER / TYMAP-171 / LDRSH | **0** | **0** |
| `[TYMAP-DUMP]` vt+8=walk OPD | vivo | vivo (H3) |
| SHADERSRC ΣN | 889 | 889 |
| bind EA distintos (TL) | 1–3 × 1280×720 DXT1 | idem |
| `[TEX-PX]` guest VRAM | **nonzero_bytes=0** | **0** (vazio) |
| WADLD GFXX/TXRX/CXT size | 48 B stubs | 48 B stubs |
| `[WADTEX]` `~tex` packages | 0 | 0 (nenhum name `~*`) |

Logs: `/tmp/vdec_spu1_a1.log`, `/tmp/vdec_texpx.log`, `/tmp/vdec_wadtex.log`.

## Vereditos

### 1) Walk A1 — **continua fechado (built, never walked)**

- Typemap instalado: `comp=0x4306ADF0 tm=0x4306B160 vt=0x5130B8 vt+8=0x522E70`.
- Cadeia `00329490 → 00468C3C → 00330D54 → 0032DF98 → 0032E200 → walk`
  **nunca entra** (probes no binário).
- Censo offline: **único** despachante do walk é `func_0032E200` (hashmap
  replace); micro-ctors de cena **não correm**.
- `PS3_GATE_FORCE` (stream sintético) **não** é aceite.

### 2) Bind/draw natural — **VRAM guest vazia**

- Binds HD `fmt=0x86` (DXT1) em `0xC0FB0980` / `0xC1021180` / `0xC0F40180`.
- Amostra de bytes DXT1: **max=0, nonzero=0** → o jogo **não preenche**
  a memória RSX local da textura.
- Legal/SCEA/Bluepoint que se vê na tela vêm do **content-hold HOSTRES**, não
  do path guest bind+draw.
- Corrigir só o PSO Metal **não basta** enquanto o buffer guest for zero.

### 3) WAD “texturas” no TOC — **stubs**

- `GFXX_R_Perm` / `TXRX_*` / `CXT_*` → **size=48** (catálogo), não corpos.
- Patch `~tex` capture reactivado no Mac, mas **zero** packages `name[0]=='~'`
  nesta janela → `[WADTEX]=0`.
- Conteúdo real de shaders continua no HOSTRES EBOOT (já em SHADERSRC).

### 4) SPU1 — **infra desbloqueada**

- dearch/EDGE-zlib agora **default** (`env_gow2.sh`: `PS3_SPU1=1`).
- Jobs limpos; **não** desbloqueia sozinho o walk nem enche VRAM UI nesta janela
  (upstream: loader de asset / fase de cena).

## Mudanças desta leva

| Onde | O quê |
|------|--------|
| `gow2-recomp/env_gow2.sh` | `PS3_SPU1=1` default |
| `gow2-recomp/build_macos.sh` | link `host_wad_tex.o` |
| `gow2-recomp/apply_all_patches.sh` | deixa de SKIP `patch_wad_tex_capture` no Darwin |
| `ps3recomp/.../rsx_metal_backend.m` | `PS3_TRACE_TEX_PIXELS` (amostra DXT1/raw) |

## Próximo (ordenado)

1. **Quem deveria preencher RSX local** (`C0FBxxxx`) a partir de HOSTRES/WAD
   decode — DMA GCM / copy guest / SPU PUT. Probe: writes em `0xC0000000+`
   pós-R_Perm vs pós-pad.
2. **Agendar micro-ctor** (`00329490` family) — FSM de cena/menu após logos;
   correlacionar com input / `GFX_SCREEN_00` / load de level.
3. Só depois: esperar `[CMP-ENTER]` / `[TYMAP-171]` natural; **não** promover
   GATE-FORCE.

## Aceite menu

**Não alcançado.** Pipeline natural de UI ainda não materializa pixels em VRAM
nem invoca o walk. Logos HOSTRES + intro HLE continuam o path visual de boot.
