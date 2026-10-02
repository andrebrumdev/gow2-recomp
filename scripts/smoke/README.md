# Smoke runs

Short, scripted runs of the real game that print a PASS/FAIL or a metric table. They need the game data
next to the repository root (`EBOOT.ELF`, `extracted/`, `movie_cache/`) and a built binary
(`./build_macos.sh` → `boot_gow2`; the three Windows ones need `recomp_mid_v2/boot_v2_new.exe`).
Every script resolves the repository root from its own location and `cd`s there (the Windows ones into
`recomp_mid_v2/`), so it can be started from any directory: `scripts/smoke/smoke_boot_mac.sh 30`. Run them muted (`PS3_MUTE=1`) and never while
someone is playing (they open windows and steal focus).

Until 2026-12-31 the old root paths (`./smoke_boot_mac.sh`, ...) still work through thin wrappers; see
[`scripts/README.md`](../README.md).

| Script | Platform | What it checks |
|---|---|---|
| `smoke_boot_mac.sh` | Mac | baseline boot of the native build (SPURS init, GCM calls, distinct NIDs, CPU) |
| `smoke_intro_macos.sh` | Mac | multi-run start of the intro (movie FSM reaches its states) |
| `smoke_intro_vdec_wad.sh` | Mac | intro acceptance: vdec Open/StartSeq/FORCE, then the WAD opens |
| `smoke_intro_open_wall.sh` | Mac | intro audio/FIOS open wall, multi-run with probe modes |
| `smoke_fios_open_probe.sh` | Mac | A/B matrix of the intro FIOS open probe |
| `smoke_movie_eos_mac.sh` | Mac | natural end-of-stream channel of the intro movie |
| `smoke_moviefsm_mac.sh` | Mac | samples the movie-player object (also builds `tests/test_movie_eos_policy.c`) |
| `smoke_bctr_tail.sh` | Mac | A/B matrix of the "bctr is a jump, not a call" lifter fix |
| `smoke_perf_macos.sh` | Mac | 30 s profile; `MODE=ab` rebuilds and compares `-O0` vs `-O1` |
| `smoke_metal_draw_mac.sh` | Mac | Metal draw path is not clear-only (demo triangle + guest draws) |
| `smoke_metal_matrix_mac.sh` | Mac | M10 matrix of short Metal sub-smokes |
| `smoke_metalfx_mac.sh` | Mac | the MetalFX upscaler runs in the real present path |
| `smoke_intro_to_rsx.sh` | Windows | end-to-end intro FSM → WADs → RSX (`boot_v2_new.exe`) |
| `smoke_asset_pipeline.sh` | Windows | root metrics of the primary asset pipeline (`PS3_TRACE_ASSET=1`) |
| `smoke_rsx_spu.sh` | Windows | RSX (D3D12 shaders) + SPU integration run |

The relift gates that are also called "smoke" (`smoke_chain_gate.sh`, `smoke_relift_equiv.sh`,
`smoke_m0_baseline.sh`) live in [`scripts/lift/`](../lift/README.md) next to `accept_relift.sh`'s
other helpers.
