# Repository layout and script map

The root of this repository holds only what a player, the build or another repository calls by path
(launchers, the Mac build, the env recipe, the lift pipeline entry points and the sources the build
compiles). Everything else lives in a folder with one purpose, listed below. `scripts/check_layout.sh`
fails when a new loose file appears at the root, when a compatibility wrapper loses its target, or when
a folder is missing from this page.

The reorganisation followed the plan in the monorepo
([`docs/superpowers/plans/2026-10-02-reorganizacao-do-repositorio.md`](https://github.com/andrebrumdev/ps3recomp/blob/spurs-bringup/docs/superpowers/plans/2026-10-02-reorganizacao-do-repositorio.md), item G2):
moves are `git mv` (`git log --follow <new path>` keeps the history), done in batches, and every moved
file that something outside its batch still cites by its old path keeps a thin wrapper there.

## Folders

| Folder | Purpose |
|---|---|
| `scripts/` | helper scripts that are not entry points; this page is its map |
| [`scripts/smoke/`](smoke/README.md) | boot / intro / Metal smoke runs of the Mac build (and three Windows-only smokes); each needs the game data and a built `boot_gow2` |
| [`scripts/lift/`](lift/README.md) | relift acceptance gates, chain gate, bisect and one-off lift helpers called by `accept_relift.sh` / `promote_lift.sh` |
| `scripts/diag/` | Mac diagnostics: lldb memory attach, run-until-marker watcher, RPCS3 oracle checklist |
| `scripts/archive/` | history only: nothing current calls these files |
| [`scripts/archive/windows/`](archive/windows/README.md) | scripts of the July 2026 Windows bring-up, bound to that machine's paths |
| [`scripts/archive/windows/trace/`](archive/windows/trace/README.md) | the 46 one-off `tr*.sh` trace runs (+ `cas.pl`) |
| [`scripts/archive/windows/diag/`](archive/windows/diag/README.md) | Windows gdb attach / sample / watch / dump scripts and gdb command files |
| [`scripts/archive/windows/build/`](archive/windows/build/README.md) | legacy MinGW lift-and-link scripts (`boot_hle.exe`) |
| `tools/` | standalone tools: PKG extraction, SELF decryption, RPCS3 source index/grep |
| [`notes/artifacts/`](../notes/artifacts/README.md) | stray design JSONs, a captured stdout and a scratch C file from early sessions |
| `claude_runs/`, `tests/`, `kit/`, `ios/`, `android/`, `launcher/`, `lift_baseline/`, `recomp_mid_v2/`, `hooks/`, `config/`, `docs/`, `notes/`, `mods/` | unchanged by this reorganisation (see `README.md`, "Repository layout") |

## What stays at the root, and why

| Group | Files | Why at the root |
|---|---|---|
| Project files | `README.md`, `README.pt-BR.md`, `LICENSE`, `NOTICE.md`, `CLAUDE.md`, `.gitignore`, `.recomp.json` | GitHub and agents read them there; `README.md` and `README.pt-BR.md` are in the monorepo Android terms check (`tools/android/terms_inventory.txt`) |
| Launchers | `jogar_g2.sh`, `jogar_gow2.sh`, `abrir_launcher.sh`, `rodar_gow2.sh`, `rodar_gow2_intro_skip.sh`, `rodar_gow2_menu_fast.sh`, `testar_fix.sh`, `gow2_launcher.py`, `make_app_bundle.sh` | what a player or a session runs directly; `README.md`, `CLAUDE.md` and the notes give these commands (`testar_fix.sh` execs `jogar_g2.sh`) |
| Mac build and env | `build_macos.sh`, `env_gow2.sh`, `functions.json` | the Android and iOS builds (`$GOW2_WORK/build_macos.sh`, `$GOW2_WORK/env_gow2.sh`), the kit, and the monorepo gates (`scripts/upstream_block_gate.sh`, `scripts/baseline_run.sh`) use these paths |
| Sources the build compiles | `boot_macos.cpp`, `gow2_boot.h`, `gow2_overlay_provider.c`, `gow2_overlay_provider.h`, `host_gow2_f2b.c`, `host_gow2_factory.cpp`, `movie_eos_arm.c`, `movie_eos_arm.h` | `build_macos.sh`, the iOS/Android builds (`cmp` against `games/gow2`) and the monorepo CMake name them at the root |
| Lift pipeline entry points | `apply_all_patches.sh`, `verify_lift.sh`, `verify_lift_baseline.sh`, `accept_relift.sh`, `lib_boot_chain_metrics.sh`, `PROMOTION_LOG.tsv` | the kit, `build_macos.sh`, `lift_baseline/` and the monorepo (`scripts/upstream_block_gate.sh` sources `$GAME_ROOT/lib_boot_chain_metrics.sh`) use these paths |

## Moved files (old path -> new path)

"wrapper" = a thin script left at the old path that runs the new one with the same arguments,
environment, working directory and exit code (`exec`); "stub" = a short note pointing to the new place.
Wrappers and stubs are deprecated paths: **remove after 2026-12-31**, once the monorepo copy
(`games/gow2/`), the dated notes and other sessions have moved to the new paths. "none" = nothing
current cites the old path (or the file is archive-only: it was bound to the old Windows machine).

| Batch | Old path | New path | At the old path |
|---|---|---|---|
| 1 | `tr040.sh` | [`scripts/archive/windows/trace/tr040.sh`](archive/windows/trace/tr040.sh) | none |
| 1 | `tr042.sh` | [`scripts/archive/windows/trace/tr042.sh`](archive/windows/trace/tr042.sh) | none |
| 1 | `trallo.sh` | [`scripts/archive/windows/trace/trallo.sh`](archive/windows/trace/trallo.sh) | none |
| 1 | `trallocaller.sh` | [`scripts/archive/windows/trace/trallocaller.sh`](archive/windows/trace/trallocaller.sh) | none |
| 1 | `trbridge.sh` | [`scripts/archive/windows/trace/trbridge.sh`](archive/windows/trace/trbridge.sh) | none |
| 1 | `trbridge2.sh` | [`scripts/archive/windows/trace/trbridge2.sh`](archive/windows/trace/trbridge2.sh) | none |
| 1 | `trbs.sh` | [`scripts/archive/windows/trace/trbs.sh`](archive/windows/trace/trbs.sh) | none |
| 1 | `trbuild.sh` | [`scripts/archive/windows/trace/trbuild.sh`](archive/windows/trace/trbuild.sh) | none |
| 1 | `trcas_all.sh` | [`scripts/archive/windows/trace/trcas_all.sh`](archive/windows/trace/trcas_all.sh) | none |
| 1 | `trcb.sh` | [`scripts/archive/windows/trace/trcb.sh`](archive/windows/trace/trcb.sh) | none |
| 1 | `trcbcaller.sh` | [`scripts/archive/windows/trace/trcbcaller.sh`](archive/windows/trace/trcbcaller.sh) | none |
| 1 | `trchar.sh` | [`scripts/archive/windows/trace/trchar.sh`](archive/windows/trace/trchar.sh) | none |
| 1 | `trcrash.sh` | [`scripts/archive/windows/trace/trcrash.sh`](archive/windows/trace/trcrash.sh) | none |
| 1 | `trdl.sh` | [`scripts/archive/windows/trace/trdl.sh`](archive/windows/trace/trdl.sh) | none |
| 1 | `trf2.sh` | [`scripts/archive/windows/trace/trf2.sh`](archive/windows/trace/trf2.sh) | none |
| 1 | `trfence.sh` | [`scripts/archive/windows/trace/trfence.sh`](archive/windows/trace/trfence.sh) | none |
| 1 | `trfifo.sh` | [`scripts/archive/windows/trace/trfifo.sh`](archive/windows/trace/trfifo.sh) | none |
| 1 | `trfix.sh` | [`scripts/archive/windows/trace/trfix.sh`](archive/windows/trace/trfix.sh) | none |
| 1 | `trflip.sh` | [`scripts/archive/windows/trace/trflip.sh`](archive/windows/trace/trflip.sh) | none |
| 1 | `trforce.sh` | [`scripts/archive/windows/trace/trforce.sh`](archive/windows/trace/trforce.sh) | none |
| 1 | `trfp.sh` | [`scripts/archive/windows/trace/trfp.sh`](archive/windows/trace/trfp.sh) | none |
| 1 | `trgcm.sh` | [`scripts/archive/windows/trace/trgcm.sh`](archive/windows/trace/trgcm.sh) | none |
| 1 | `trgcm2.sh` | [`scripts/archive/windows/trace/trgcm2.sh`](archive/windows/trace/trgcm2.sh) | none |
| 1 | `trgcm3.sh` | [`scripts/archive/windows/trace/trgcm3.sh`](archive/windows/trace/trgcm3.sh) | none |
| 1 | `trgcm_cfg.sh` | [`scripts/archive/windows/trace/trgcm_cfg.sh`](archive/windows/trace/trgcm_cfg.sh) | none |
| 1 | `trgpu.sh` | [`scripts/archive/windows/trace/trgpu.sh`](archive/windows/trace/trgpu.sh) | none |
| 1 | `trheap.sh` | [`scripts/archive/windows/trace/trheap.sh`](archive/windows/trace/trheap.sh) | none |
| 1 | `trinit.sh` | [`scripts/archive/windows/trace/trinit.sh`](archive/windows/trace/trinit.sh) | none |
| 1 | `trlv2.sh` | [`scripts/archive/windows/trace/trlv2.sh`](archive/windows/trace/trlv2.sh) | none |
| 1 | `troobra.sh` | [`scripts/archive/windows/trace/troobra.sh`](archive/windows/trace/troobra.sh) | none |
| 1 | `trpad.sh` | [`scripts/archive/windows/trace/trpad.sh`](archive/windows/trace/trpad.sh) | none |
| 1 | `trra0.sh` | [`scripts/archive/windows/trace/trra0.sh`](archive/windows/trace/trra0.sh) | none |
| 1 | `trra0_run.sh` | [`scripts/archive/windows/trace/trra0_run.sh`](archive/windows/trace/trra0_run.sh) | none |
| 1 | `trreorder.sh` | [`scripts/archive/windows/trace/trreorder.sh`](archive/windows/trace/trreorder.sh) | none |
| 1 | `trrsv.sh` | [`scripts/archive/windows/trace/trrsv.sh`](archive/windows/trace/trrsv.sh) | none |
| 1 | `trrsx.sh` | [`scripts/archive/windows/trace/trrsx.sh`](archive/windows/trace/trrsx.sh) | none |
| 1 | `trrsx2.sh` | [`scripts/archive/windows/trace/trrsx2.sh`](archive/windows/trace/trrsx2.sh) | none |
| 1 | `trsc.sh` | [`scripts/archive/windows/trace/trsc.sh`](archive/windows/trace/trsc.sh) | none |
| 1 | `trsem.sh` | [`scripts/archive/windows/trace/trsem.sh`](archive/windows/trace/trsem.sh) | none |
| 1 | `trskip.sh` | [`scripts/archive/windows/trace/trskip.sh`](archive/windows/trace/trskip.sh) | none |
| 1 | `trspin.sh` | [`scripts/archive/windows/trace/trspin.sh`](archive/windows/trace/trspin.sh) | none |
| 1 | `trspin2.sh` | [`scripts/archive/windows/trace/trspin2.sh`](archive/windows/trace/trspin2.sh) | none |
| 1 | `trspursready.sh` | [`scripts/archive/windows/trace/trspursready.sh`](archive/windows/trace/trspursready.sh) | none |
| 1 | `trtid.sh` | [`scripts/archive/windows/trace/trtid.sh`](archive/windows/trace/trtid.sh) | none |
| 1 | `trtrophy.sh` | [`scripts/archive/windows/trace/trtrophy.sh`](archive/windows/trace/trtrophy.sh) | none |
| 1 | `trwatch.sh` | [`scripts/archive/windows/trace/trwatch.sh`](archive/windows/trace/trwatch.sh) | none |
| 1 | `cas.pl` | [`scripts/archive/windows/trace/cas.pl`](archive/windows/trace/cas.pl) | none |
| 1 | `attach_mem.sh` | [`scripts/archive/windows/diag/attach_mem.sh`](archive/windows/diag/attach_mem.sh) | none |
| 1 | `attach_oob.sh` | [`scripts/archive/windows/diag/attach_oob.sh`](archive/windows/diag/attach_oob.sh) | none |
| 1 | `attach_threads.sh` | [`scripts/archive/windows/diag/attach_threads.sh`](archive/windows/diag/attach_threads.sh) | none |
| 1 | `diag_hang.sh` | [`scripts/archive/windows/diag/diag_hang.sh`](archive/windows/diag/diag_hang.sh) | none |
| 1 | `diag_sample.sh` | [`scripts/archive/windows/diag/diag_sample.sh`](archive/windows/diag/diag_sample.sh) | none |
| 1 | `dump_alloc.sh` | [`scripts/archive/windows/diag/dump_alloc.sh`](archive/windows/diag/dump_alloc.sh) | none |
| 1 | `dump_ctrl_be.sh` | [`scripts/archive/windows/diag/dump_ctrl_be.sh`](archive/windows/diag/dump_ctrl_be.sh) | none |
| 1 | `oob_bp.sh` | [`scripts/archive/windows/diag/oob_bp.sh`](archive/windows/diag/oob_bp.sh) | none |
| 1 | `probe_flag.sh` | [`scripts/archive/windows/diag/probe_flag.sh`](archive/windows/diag/probe_flag.sh) | none |
| 1 | `sample_m2.sh` | [`scripts/archive/windows/diag/sample_m2.sh`](archive/windows/diag/sample_m2.sh) | none |
| 1 | `sample_mem.sh` | [`scripts/archive/windows/diag/sample_mem.sh`](archive/windows/diag/sample_mem.sh) | none |
| 1 | `sample_multi.sh` | [`scripts/archive/windows/diag/sample_multi.sh`](archive/windows/diag/sample_multi.sh) | none |
| 1 | `trace_list.sh` | [`scripts/archive/windows/diag/trace_list.sh`](archive/windows/diag/trace_list.sh) | none |
| 1 | `trace_obj.sh` | [`scripts/archive/windows/diag/trace_obj.sh`](archive/windows/diag/trace_obj.sh) | none |
| 1 | `watch_ctrl.sh` | [`scripts/archive/windows/diag/watch_ctrl.sh`](archive/windows/diag/watch_ctrl.sh) | none |
| 1 | `watch_flag.sh` | [`scripts/archive/windows/diag/watch_flag.sh`](archive/windows/diag/watch_flag.sh) | none |
| 1 | `hang_cmds.gdb` | [`scripts/archive/windows/diag/hang_cmds.gdb`](archive/windows/diag/hang_cmds.gdb) | none |
| 1 | `watch_obj.gdb` | [`scripts/archive/windows/diag/watch_obj.gdb`](archive/windows/diag/watch_obj.gdb) | none |
| 1 | `build3.sh` | [`scripts/archive/windows/build/build3.sh`](archive/windows/build/build3.sh) | none |
| 1 | `build_boot_gow.sh` | [`scripts/archive/windows/build/build_boot_gow.sh`](archive/windows/build/build_boot_gow.sh) | none |
| 1 | `build_boot_hle.sh` | [`scripts/archive/windows/build/build_boot_hle.sh`](archive/windows/build/build_boot_hle.sh) | none |
| 1 | `build_gow_mid.sh` | [`scripts/archive/windows/build/build_gow_mid.sh`](archive/windows/build/build_gow_mid.sh) | none |
| 1 | `capped_build.sh` | [`scripts/archive/windows/build/capped_build.sh`](archive/windows/build/capped_build.sh) | none |
| 1 | `patch_build_test.sh` | [`scripts/archive/windows/build/patch_build_test.sh`](archive/windows/build/patch_build_test.sh) | none |
| 1 | `rebuild_and_test.sh` | [`scripts/archive/windows/build/rebuild_and_test.sh`](archive/windows/build/rebuild_and_test.sh) | none |
| 1 | `recomp_ra0.sh` | [`scripts/archive/windows/build/recomp_ra0.sh`](archive/windows/build/recomp_ra0.sh) | none |
| 2 | `SPURS_M2_FINDINGS.md` | [`notes/SPURS_M2_FINDINGS.md`](../notes/SPURS_M2_FINDINGS.md) | stub |
| 2 | `SPURS_TRACE_M1.md` | [`notes/SPURS_TRACE_M1.md`](../notes/SPURS_TRACE_M1.md) | stub |
| 2 | `elf_loader_design.json` | [`notes/artifacts/elf_loader_design.json`](../notes/artifacts/elf_loader_design.json) | none |
| 2 | `items123_design.json` | [`notes/artifacts/items123_design.json`](../notes/artifacts/items123_design.json) | none |
| 2 | `override_test.json` | [`notes/artifacts/override_test.json`](../notes/artifacts/override_test.json) | none |
| 2 | `research_result.json` | [`notes/artifacts/research_result.json`](../notes/artifacts/research_result.json) | none |
| 2 | `spu_interp_design.json` | [`notes/artifacts/spu_interp_design.json`](../notes/artifacts/spu_interp_design.json) | none |
| 2 | `tasks_design.json` | [`notes/artifacts/tasks_design.json`](../notes/artifacts/tasks_design.json) | none |
| 2 | `boot_fixed.stdout` | [`notes/artifacts/boot_fixed.stdout`](../notes/artifacts/boot_fixed.stdout) | none |
| 2 | `_stopn_test.c` | [`notes/artifacts/_stopn_test.c`](../notes/artifacts/_stopn_test.c) | none |
| 3 | `smoke_bctr_tail.sh` | [`scripts/smoke/smoke_bctr_tail.sh`](smoke/smoke_bctr_tail.sh) | none |
| 3 | `smoke_boot_mac.sh` | [`scripts/smoke/smoke_boot_mac.sh`](smoke/smoke_boot_mac.sh) | wrapper |
| 3 | `smoke_fios_open_probe.sh` | [`scripts/smoke/smoke_fios_open_probe.sh`](smoke/smoke_fios_open_probe.sh) | wrapper |
| 3 | `smoke_intro_macos.sh` | [`scripts/smoke/smoke_intro_macos.sh`](smoke/smoke_intro_macos.sh) | wrapper |
| 3 | `smoke_intro_open_wall.sh` | [`scripts/smoke/smoke_intro_open_wall.sh`](smoke/smoke_intro_open_wall.sh) | wrapper |
| 3 | `smoke_intro_vdec_wad.sh` | [`scripts/smoke/smoke_intro_vdec_wad.sh`](smoke/smoke_intro_vdec_wad.sh) | wrapper |
| 3 | `smoke_metal_draw_mac.sh` | [`scripts/smoke/smoke_metal_draw_mac.sh`](smoke/smoke_metal_draw_mac.sh) | wrapper |
| 3 | `smoke_metal_matrix_mac.sh` | [`scripts/smoke/smoke_metal_matrix_mac.sh`](smoke/smoke_metal_matrix_mac.sh) | wrapper |
| 3 | `smoke_metalfx_mac.sh` | [`scripts/smoke/smoke_metalfx_mac.sh`](smoke/smoke_metalfx_mac.sh) | none |
| 3 | `smoke_movie_eos_mac.sh` | [`scripts/smoke/smoke_movie_eos_mac.sh`](smoke/smoke_movie_eos_mac.sh) | wrapper |
| 3 | `smoke_moviefsm_mac.sh` | [`scripts/smoke/smoke_moviefsm_mac.sh`](smoke/smoke_moviefsm_mac.sh) | wrapper |
| 3 | `smoke_perf_macos.sh` | [`scripts/smoke/smoke_perf_macos.sh`](smoke/smoke_perf_macos.sh) | wrapper |
| 3 | `smoke_asset_pipeline.sh` | [`scripts/smoke/smoke_asset_pipeline.sh`](smoke/smoke_asset_pipeline.sh) | wrapper |
| 3 | `smoke_intro_to_rsx.sh` | [`scripts/smoke/smoke_intro_to_rsx.sh`](smoke/smoke_intro_to_rsx.sh) | wrapper |
| 3 | `smoke_rsx_spu.sh` | [`scripts/smoke/smoke_rsx_spu.sh`](smoke/smoke_rsx_spu.sh) | wrapper |
| 4 | `promote_lift.sh` | [`scripts/lift/promote_lift.sh`](lift/promote_lift.sh) | wrapper |
| 4 | `lib_patch_convergence.sh` | [`scripts/lift/lib_patch_convergence.sh`](lift/lib_patch_convergence.sh) | sourced stub |
| 4 | `test_patch_convergence.sh` | [`scripts/lift/test_patch_convergence.sh`](lift/test_patch_convergence.sh) | wrapper |
| 4 | `smoke_relift_equiv.sh` | [`scripts/lift/smoke_relift_equiv.sh`](lift/smoke_relift_equiv.sh) | wrapper |
| 4 | `smoke_chain_gate.sh` | [`scripts/lift/smoke_chain_gate.sh`](lift/smoke_chain_gate.sh) | wrapper |
| 4 | `smoke_m0_baseline.sh` | [`scripts/lift/smoke_m0_baseline.sh`](lift/smoke_m0_baseline.sh) | wrapper |
| 4 | `bisect_regression.sh` | [`scripts/lift/bisect_regression.sh`](lift/bisect_regression.sh) | wrapper |
| 4 | `bisect_verdict.sh` | [`scripts/lift/bisect_verdict.sh`](lift/bisect_verdict.sh) | wrapper |
| 4 | `patch_ab_sandbox.sh` | [`scripts/lift/patch_ab_sandbox.sh`](lift/patch_ab_sandbox.sh) | wrapper |
| 4 | `test_relift_build.sh` | [`scripts/lift/test_relift_build.sh`](lift/test_relift_build.sh) | wrapper |
| 4 | `test_relift_prepatch_link.sh` | [`scripts/lift/test_relift_prepatch_link.sh`](lift/test_relift_prepatch_link.sh) | wrapper |
| 4 | `analyze_eboot_ghidra.sh` | [`scripts/lift/analyze_eboot_ghidra.sh`](lift/analyze_eboot_ghidra.sh) | wrapper |
| 4 | `inventory_lift_markers.py` | [`scripts/lift/inventory_lift_markers.py`](lift/inventory_lift_markers.py) | wrapper (python) |
| 4 | `count_menu_gate.py` | [`scripts/lift/count_menu_gate.py`](lift/count_menu_gate.py) | wrapper (python) |
| 4 | `patch_e401_fios_done_yield_gate.py` | [`scripts/lift/patch_e401_fios_done_yield_gate.py`](lift/patch_e401_fios_done_yield_gate.py) | wrapper (python) |
| 4 | `patch_diag06_147038_revert_test.py` | [`scripts/lift/patch_diag06_147038_revert_test.py`](lift/patch_diag06_147038_revert_test.py) | wrapper (python) |
| 4 | `patch_diag08_committed_range_revert_test.py` | [`scripts/lift/patch_diag08_committed_range_revert_test.py`](lift/patch_diag08_committed_range_revert_test.py) | wrapper (python) |
| 5 | `attach_mem_mac.sh` | [`scripts/diag/attach_mem_mac.sh`](diag/attach_mem_mac.sh) | wrapper |
| 5 | `watch_run.sh` | [`scripts/diag/watch_run.sh`](diag/watch_run.sh) | wrapper |
| 5 | `oracle_intro_checklist.sh` | [`scripts/diag/oracle_intro_checklist.sh`](diag/oracle_intro_checklist.sh) | wrapper |
| 5 | `decrypt_self.py` | [`tools/decrypt_self.py`](../tools/decrypt_self.py) | wrapper (python) |
| 5 | `extract_pkg.py` | [`tools/extract_pkg.py`](../tools/extract_pkg.py) | wrapper (python) |

## Compatibility wrappers (37, deprecated, remove after 2026-12-31)

Each carries the marker `gow2-recomp:moved-to <new path>`, which `scripts/check_layout.sh` checks.

- `SPURS_M2_FINDINGS.md` -> `notes/SPURS_M2_FINDINGS.md`
- `SPURS_TRACE_M1.md` -> `notes/SPURS_TRACE_M1.md`
- `smoke_boot_mac.sh` -> `scripts/smoke/smoke_boot_mac.sh`
- `smoke_fios_open_probe.sh` -> `scripts/smoke/smoke_fios_open_probe.sh`
- `smoke_intro_macos.sh` -> `scripts/smoke/smoke_intro_macos.sh`
- `smoke_intro_open_wall.sh` -> `scripts/smoke/smoke_intro_open_wall.sh`
- `smoke_intro_vdec_wad.sh` -> `scripts/smoke/smoke_intro_vdec_wad.sh`
- `smoke_metal_draw_mac.sh` -> `scripts/smoke/smoke_metal_draw_mac.sh`
- `smoke_metal_matrix_mac.sh` -> `scripts/smoke/smoke_metal_matrix_mac.sh`
- `smoke_movie_eos_mac.sh` -> `scripts/smoke/smoke_movie_eos_mac.sh`
- `smoke_moviefsm_mac.sh` -> `scripts/smoke/smoke_moviefsm_mac.sh`
- `smoke_perf_macos.sh` -> `scripts/smoke/smoke_perf_macos.sh`
- `smoke_asset_pipeline.sh` -> `scripts/smoke/smoke_asset_pipeline.sh`
- `smoke_intro_to_rsx.sh` -> `scripts/smoke/smoke_intro_to_rsx.sh`
- `smoke_rsx_spu.sh` -> `scripts/smoke/smoke_rsx_spu.sh`
- `promote_lift.sh` -> `scripts/lift/promote_lift.sh`
- `lib_patch_convergence.sh` -> `scripts/lift/lib_patch_convergence.sh`
- `test_patch_convergence.sh` -> `scripts/lift/test_patch_convergence.sh`
- `smoke_relift_equiv.sh` -> `scripts/lift/smoke_relift_equiv.sh`
- `smoke_chain_gate.sh` -> `scripts/lift/smoke_chain_gate.sh`
- `smoke_m0_baseline.sh` -> `scripts/lift/smoke_m0_baseline.sh`
- `bisect_regression.sh` -> `scripts/lift/bisect_regression.sh`
- `bisect_verdict.sh` -> `scripts/lift/bisect_verdict.sh`
- `patch_ab_sandbox.sh` -> `scripts/lift/patch_ab_sandbox.sh`
- `test_relift_build.sh` -> `scripts/lift/test_relift_build.sh`
- `test_relift_prepatch_link.sh` -> `scripts/lift/test_relift_prepatch_link.sh`
- `analyze_eboot_ghidra.sh` -> `scripts/lift/analyze_eboot_ghidra.sh`
- `inventory_lift_markers.py` -> `scripts/lift/inventory_lift_markers.py`
- `count_menu_gate.py` -> `scripts/lift/count_menu_gate.py`
- `patch_e401_fios_done_yield_gate.py` -> `scripts/lift/patch_e401_fios_done_yield_gate.py`
- `patch_diag06_147038_revert_test.py` -> `scripts/lift/patch_diag06_147038_revert_test.py`
- `patch_diag08_committed_range_revert_test.py` -> `scripts/lift/patch_diag08_committed_range_revert_test.py`
- `attach_mem_mac.sh` -> `scripts/diag/attach_mem_mac.sh`
- `watch_run.sh` -> `scripts/diag/watch_run.sh`
- `oracle_intro_checklist.sh` -> `scripts/diag/oracle_intro_checklist.sh`
- `decrypt_self.py` -> `tools/decrypt_self.py`
- `extract_pkg.py` -> `tools/extract_pkg.py`

## Checking the layout

```bash
scripts/check_layout.sh              # root allowlist, wrapper targets, folders documented here
scripts/check_layout.sh --self-test  # proves each check can fail
```

To add a file at the root, add it to `ROOT_KEEP` in `scripts/check_layout.sh` and to the table above
with the reason. To move another file: `git mv`, fix its self-location (`HERE`/`REPO` must still be the
repository root), update the callers, leave a wrapper if anything outside the change cites the old path,
and add the row here.
