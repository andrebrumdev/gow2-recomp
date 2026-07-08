# gow2-recomp — work artifacts

Curated artifacts for the God of War II HD (NPUA80491) static recompilation,
built on top of [ps3recomp](https://github.com/andrebrumdev/ps3recomp) (branch
`spurs-bringup`). This repo holds the **hard-to-regenerate, non-copyrighted**
pieces only.

## What's here

- `functions.json` — PPU function boundaries (with hand-curated additions,
  e.g. truncated-bounds repair, mid-function targets).
- `recomp_mid_v2/spu{0..3}_funcs.json` — SPU function boundaries, including
  manually added function-pointer-only targets (e.g. 0x9300 / 0x96F8 attach
  callbacks, 0x4070 / 0x5C00).
- `recomp_mid_v2/rodar_gow2.cmd` — one-click launcher with the correct env vars.
- `spu_lifted/spu{0..3}_v2/spu_recomp.{c,h}` — SPU lift sources (regenerable
  from the funcs.json + the fixed lifter, but kept for convenience; contain the
  RE trace scaffolding).
- `*.py` — helper scripts (SELF decrypt, psarc/read correlation, lift fixes).
- `*.md`, `*_design.json`, `research_result.json` — findings / design notes.

## What's intentionally excluded (see `.gitignore`)

- **Game data** (copyright): `extracted/`, `EBOOT.ELF`, `*.psarc`, the extracted
  SPU ELFs (`spu_images/`). Keep these in a private local/offline backup, never
  on GitHub.
- **Build artifacts** (regenerable): `*.o`, `*.exe`, and the generated PPU lift
  chunk dirs (`recomp*/*.cpp`, ~1.3 GB — regenerate with the lifter).

## How to rebuild

1. Decrypt + extract the game (own copy) → `EBOOT.ELF`, `extracted/`.
2. Lift PPU: `ppu_lifter.py EBOOT.ELF --functions functions.json` → chunks.
3. Lift SPU: `spu_lifter.py --auto-functions spu_images/gow2_spuN.elf
   --functions recomp_mid_v2/spuN_funcs.json --base 0x3000|0x4000
   --symbol-prefix spuN_` → `spu_lifted/spuN_v2/`.
4. Compile + link against the ps3recomp runtime (`-O0`), then `rodar_gow2.cmd`.

Full technical history lives in the Claude project memory (`ps3recomp-feasibility`,
levas 13-17) and in `ps3recomp/docs/`.
