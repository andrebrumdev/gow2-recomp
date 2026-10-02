# Root files of gow2-recomp — documentation map (nothing moved)

This page only **describes** the ~150 files at the root of this repository: what each group is, who
cites it, and where it could go in a later clean-up. **No file was moved.** Moving any of them is a
separate, planned change (plan G2 of the monorepo's
[reorganisation plan](https://github.com/andrebrumdev/ps3recomp/blob/spurs-bringup/docs/superpowers/plans/2026-10-02-reorganizacao-do-repositorio.md)):
launchers, the kit, `claude_runs/`, tests, the CLAUDE.md files, memory notes and many session logs call
these files by name, and `games/gow2/` in the monorepo is a copy of this repository.

Columns (counted on 2026-10-02 with `git grep -l -F <name>`; counts are a floor and a short name can
also match a longer one):

- **here**: files in this repository that mention the name, excluding `notes/` and the file itself;
- **docs/skills**: files under the monorepo's `docs/` (without `docs/re_sessions/`) and `.agents/skills/`;
- **logs**: files under the monorepo's `docs/re_sessions/` (immutable history: a move would leave them stale).

A file is a safe candidate to move only when **here** and **docs/skills** are both 0.

## Entry points and project files (stay at the root)

Proposed destination: stay at the root.

| File | here | docs/skills | logs |
|---|---|---|---|
| `.gitignore` | 3 | 13 | 1 |
| `.recomp.json` | 0 | 0 | 0 |
| `CLAUDE.md` | 57 | 54 | 23 |
| `PROMOTION_LOG.tsv` | 1 | 0 | 0 |
| `README.md` | 4 | 23 | 2 |
| `abrir_launcher.sh` | 0 | 1 | 0 |
| `build_macos.sh` | 44 | 74 | 15 |
| `env_gow2.sh` | 46 | 56 | 12 |
| `functions.json` | 24 | 18 | 5 |
| `gow2_launcher.py` | 6 | 6 | 0 |
| `jogar_g2.sh` | 11 | 16 | 1 |
| `jogar_gow2.sh` | 1 | 2 | 0 |
| `make_app_bundle.sh` | 0 | 1 | 0 |
| `rodar_gow2.sh` | 6 | 6 | 0 |
| `rodar_gow2_intro_skip.sh` | 0 | 3 | 0 |
| `rodar_gow2_menu_fast.sh` | 2 | 4 | 0 |

## Sources compiled by the build (stay at the root: build_macos.sh and the iOS/Android builds name them)

Proposed destination: stay at the root.

| File | here | docs/skills | logs |
|---|---|---|---|
| `boot_macos.cpp` | 9 | 24 | 2 |
| `gow2_boot.h` | 8 | 7 | 1 |
| `gow2_overlay_provider.c` | 1 | 3 | 0 |
| `gow2_overlay_provider.h` | 3 | 0 | 0 |
| `host_gow2_f2b.c` | 6 | 1 | 0 |
| `host_gow2_factory.cpp` | 11 | 6 | 0 |
| `movie_eos_arm.c` | 12 | 10 | 3 |
| `movie_eos_arm.h` | 4 | 2 | 0 |

## Lift pipeline helpers

Proposed destination: keep at the root while cited (apply_all_patches.sh, verify_lift.sh, accept_relift.sh are referenced by many scripts and docs); the rest → `scripts/lift/`.

| File | here | docs/skills | logs |
|---|---|---|---|
| `accept_relift.sh` | 10 | 8 | 0 |
| `analyze_eboot_ghidra.sh` | 1 | 4 | 1 |
| `apply_all_patches.sh` | 63 | 18 | 10 |
| `capped_build.sh` | 0 | 0 | 0 |
| `cas.pl` | 1 | 0 | 0 |
| `count_menu_gate.py` | 2 | 4 | 0 |
| `decrypt_self.py` | 3 | 3 | 0 |
| `extract_pkg.py` | 1 | 1 | 0 |
| `inventory_lift_markers.py` | 2 | 0 | 0 |
| `lib_boot_chain_metrics.sh` | 7 | 2 | 4 |
| `lib_patch_convergence.sh` | 2 | 0 | 0 |
| `patch_e401_fios_done_yield_gate.py` | 0 | 0 | 1 |
| `promote_lift.sh` | 0 | 1 | 0 |
| `rebuild_and_test.sh` | 0 | 0 | 0 |
| `recomp_ra0.sh` | 0 | 0 | 0 |
| `verify_lift.sh` | 15 | 6 | 3 |
| `verify_lift_baseline.sh` | 3 | 4 | 0 |

## Legacy Windows / MinGW build scripts

Proposed destination: `scripts/legacy-windows/` (they hard-code the original machine's paths).

| File | here | docs/skills | logs |
|---|---|---|---|
| `build3.sh` | 0 | 0 | 0 |
| `build_boot_gow.sh` | 0 | 1 | 0 |
| `build_boot_hle.sh` | 4 | 2 | 2 |
| `build_gow_mid.sh` | 0 | 0 | 0 |

## Smoke tests (`smoke_*.sh`)

Proposed destination: `scripts/smoke/`.

| File | here | docs/skills | logs |
|---|---|---|---|
| `smoke_asset_pipeline.sh` | 1 | 4 | 0 |
| `smoke_bctr_tail.sh` | 0 | 0 | 0 |
| `smoke_boot_mac.sh` | 3 | 10 | 0 |
| `smoke_chain_gate.sh` | 7 | 2 | 3 |
| `smoke_fios_open_probe.sh` | 1 | 0 | 0 |
| `smoke_intro_macos.sh` | 2 | 3 | 1 |
| `smoke_intro_open_wall.sh` | 0 | 1 | 0 |
| `smoke_intro_to_rsx.sh` | 1 | 3 | 0 |
| `smoke_intro_vdec_wad.sh` | 0 | 3 | 0 |
| `smoke_m0_baseline.sh` | 4 | 0 | 0 |
| `smoke_metal_draw_mac.sh` | 1 | 1 | 0 |
| `smoke_metal_matrix_mac.sh` | 1 | 2 | 0 |
| `smoke_metalfx_mac.sh` | 0 | 0 | 0 |
| `smoke_movie_eos_mac.sh` | 0 | 1 | 0 |
| `smoke_moviefsm_mac.sh` | 1 | 2 | 0 |
| `smoke_perf_macos.sh` | 1 | 1 | 0 |
| `smoke_relift_equiv.sh` | 6 | 3 | 0 |
| `smoke_rsx_spu.sh` | 0 | 3 | 0 |

## Tests, A/B and bisect helpers

Proposed destination: `scripts/dev/`.

| File | here | docs/skills | logs |
|---|---|---|---|
| `bisect_regression.sh` | 2 | 0 | 0 |
| `bisect_verdict.sh` | 0 | 0 | 0 |
| `patch_ab_sandbox.sh` | 0 | 0 | 0 |
| `patch_build_test.sh` | 0 | 0 | 0 |
| `patch_diag06_147038_revert_test.py` | 1 | 0 | 0 |
| `patch_diag08_committed_range_revert_test.py` | 0 | 0 | 0 |
| `test_patch_convergence.sh` | 2 | 0 | 0 |
| `test_relift_build.sh` | 2 | 0 | 0 |
| `test_relift_prepatch_link.sh` | 0 | 0 | 0 |
| `testar_fix.sh` | 1 | 0 | 0 |

## Diagnostics: attach / sample / watch / dump / probe / oracle / gdb

Proposed destination: `scripts/diag/`.

| File | here | docs/skills | logs |
|---|---|---|---|
| `attach_mem.sh` | 1 | 2 | 0 |
| `attach_mem_mac.sh` | 0 | 2 | 0 |
| `attach_oob.sh` | 0 | 1 | 0 |
| `attach_threads.sh` | 0 | 1 | 0 |
| `diag_hang.sh` | 0 | 0 | 0 |
| `diag_sample.sh` | 0 | 0 | 0 |
| `dump_alloc.sh` | 0 | 1 | 0 |
| `dump_ctrl_be.sh` | 0 | 0 | 0 |
| `hang_cmds.gdb` | 1 | 0 | 0 |
| `oob_bp.sh` | 0 | 1 | 0 |
| `probe_flag.sh` | 0 | 1 | 0 |
| `sample_m2.sh` | 1 | 1 | 0 |
| `sample_mem.sh` | 1 | 0 | 0 |
| `sample_multi.sh` | 1 | 0 | 0 |
| `trace_list.sh` | 0 | 0 | 0 |
| `trace_obj.sh` | 0 | 0 | 0 |
| `watch_ctrl.sh` | 0 | 0 | 0 |
| `watch_flag.sh` | 1 | 0 | 0 |
| `watch_obj.gdb` | 0 | 0 | 0 |
| `watch_run.sh` | 0 | 0 | 0 |
| `oracle_intro_checklist.sh` | 0 | 4 | 0 |

## One-off trace scripts (`tr*.sh`)

Proposed destination: `scripts/diag/trace/` (most have no reference at all; candidates for deletion after a check).

| File | here | docs/skills | logs |
|---|---|---|---|
| `tr040.sh` | 0 | 0 | 0 |
| `tr042.sh` | 0 | 0 | 0 |
| `trallo.sh` | 0 | 0 | 0 |
| `trallocaller.sh` | 0 | 0 | 0 |
| `trbridge.sh` | 0 | 1 | 0 |
| `trbridge2.sh` | 0 | 1 | 0 |
| `trbs.sh` | 0 | 0 | 0 |
| `trbuild.sh` | 0 | 0 | 0 |
| `trcas_all.sh` | 0 | 0 | 0 |
| `trcb.sh` | 0 | 0 | 0 |
| `trcbcaller.sh` | 0 | 0 | 0 |
| `trchar.sh` | 0 | 0 | 0 |
| `trcrash.sh` | 0 | 0 | 0 |
| `trdl.sh` | 0 | 1 | 0 |
| `trf2.sh` | 0 | 1 | 0 |
| `trfence.sh` | 0 | 1 | 0 |
| `trfifo.sh` | 0 | 0 | 0 |
| `trfix.sh` | 0 | 0 | 0 |
| `trflip.sh` | 0 | 1 | 0 |
| `trforce.sh` | 0 | 0 | 0 |
| `trfp.sh` | 0 | 1 | 0 |
| `trgcm.sh` | 0 | 0 | 0 |
| `trgcm2.sh` | 0 | 0 | 0 |
| `trgcm3.sh` | 0 | 0 | 0 |
| `trgcm_cfg.sh` | 0 | 0 | 0 |
| `trgpu.sh` | 0 | 0 | 0 |
| `trheap.sh` | 0 | 0 | 0 |
| `trinit.sh` | 0 | 0 | 0 |
| `trlv2.sh` | 0 | 0 | 0 |
| `troobra.sh` | 0 | 0 | 0 |
| `trpad.sh` | 0 | 0 | 0 |
| `trra0.sh` | 0 | 0 | 0 |
| `trra0_run.sh` | 0 | 0 | 0 |
| `trreorder.sh` | 0 | 0 | 0 |
| `trrsv.sh` | 0 | 0 | 0 |
| `trrsx.sh` | 0 | 0 | 0 |
| `trrsx2.sh` | 0 | 0 | 0 |
| `trsc.sh` | 0 | 0 | 0 |
| `trsem.sh` | 0 | 0 | 0 |
| `trskip.sh` | 0 | 0 | 0 |
| `trspin.sh` | 0 | 0 | 0 |
| `trspin2.sh` | 0 | 0 | 0 |
| `trspursready.sh` | 0 | 0 | 0 |
| `trtid.sh` | 0 | 0 | 0 |
| `trtrophy.sh` | 0 | 0 | 0 |
| `trwatch.sh` | 0 | 0 | 0 |

## Design notes, data and stray artefacts

Proposed destination: `notes/` (or delete when dead).

| File | here | docs/skills | logs |
|---|---|---|---|
| `SPURS_M2_FINDINGS.md` | 1 | 4 | 0 |
| `SPURS_TRACE_M1.md` | 0 | 1 | 0 |
| `_stopn_test.c` | 0 | 1 | 0 |
| `boot_fixed.stdout` | 0 | 1 | 0 |
| `elf_loader_design.json` | 0 | 0 | 0 |
| `items123_design.json` | 0 | 0 | 0 |
| `override_test.json` | 0 | 0 | 0 |
| `research_result.json` | 0 | 1 | 0 |
| `spu_interp_design.json` | 0 | 0 | 0 |
| `tasks_design.json` | 0 | 0 | 0 |

Files added on 2026-10-02 and not counted above: `LICENSE`, `NOTICE.md`, `README.pt-BR.md` and this
page (all stay where they are).
