# Lift pipeline helpers

Everything that supports the lift pipeline but is not one of its entry points. The entry points stay
at the repository root because the kit, `build_macos.sh`, `lift_baseline/` and the monorepo call them
by path: `apply_all_patches.sh`, `verify_lift.sh`, `verify_lift_baseline.sh`, `accept_relift.sh` and
the sourced library `lib_boot_chain_metrics.sh`.

These scripts resolve the repository root from their own location (`$(dirname "$0")/../..`), so they
can be started from any directory; `test_patch_convergence.sh` sources its sibling
`lib_patch_convergence.sh`. Until 2026-12-31 the old root paths still work through thin wrappers
(see [`scripts/README.md`](../README.md)).

## Relift acceptance and promotion

`accept_relift.sh` (root) runs four legs; legs 1, 3 and 4 live here.

| Script | Role |
|---|---|
| `smoke_relift_equiv.sh` | leg 1: boots a lift (or `--bin`) N times, st620 max >= 3 in >= 2/3 of the runs |
| `lib_patch_convergence.sh` | leg 3 core, sourced: re-applying the patches must converge |
| `test_patch_convergence.sh` | offline golden test of leg 3 (11 hermetic cases, no game data) |
| `smoke_chain_gate.sh` | leg 4: measures the whole boot chain (intro → 2nd movie → re-Play → AUTO_LOAD → WAD); uses `count_menu_gate.py` and the root `lib_boot_chain_metrics.sh` |
| `count_menu_gate.py` | counts the menu gate signals (SetFlip / cellPadGetData after the last R_Perm line) in a boot log; also used by `rodar_gow2_menu_fast.sh` |
| `smoke_m0_baseline.sh` | the original M0 smoke (6 × 25 s) that `smoke_relift_equiv.sh` is based on; it `cd`s to the main checkout by absolute path |
| `promote_lift.sh` | promotes a regenerated lift to production after `accept_relift.sh`, with a post-build confirmation and `--revert`; appends to the root `PROMOTION_LOG.tsv` |

## Regression bisect

| Script | Role |
|---|---|
| `bisect_regression.sh` | runs the menu-fast recipe against saved `boot_gow2*` binaries and tabulates the chain |
| `bisect_verdict.sh` | `git bisect run` oracle over ps3recomp commits (inherit / relink / full rebuild, then `smoke_chain_gate.sh`) |
| `patch_ab_sandbox.sh` | extracts the `recomp_mid_v2/patch_*.py` of a git ref into a sandbox for A/B |

## Lift inspection and one-off patches

| Script | Role |
|---|---|
| `analyze_eboot_ghidra.sh` | headless Ghidra analysis of `EBOOT.ELF` → JSON (`ghidra_out/`) for `verify_lift.sh VERIFY_ORACLE=1` |
| `inventory_lift_markers.py` | inventory of lift markers lost by a relift, patches without a writer, NO-MATCH/UNVERIFIED patches |
| `test_relift_build.sh` | golden test of `RELIFT=1 ./build_macos.sh` (content hash of a fresh lift) |
| `test_relift_prepatch_link.sh` | `nm` proof on a fresh, unpatched lift (follows `test_relift_build.sh`) |
| `patch_e401_fios_done_yield_gate.py` | gates the FIOS-42B4-CANCEL-YIELD block behind `PS3_FIOS_DONE_YIELD` (E401); `python3 scripts/lift/patch_e401_fios_done_yield_gate.py <lift_dir>` |
| `patch_diag06_147038_revert_test.py` | diagnostic only (phase 06): surgical revert inside `func_00147038` on a `*.diag06_test` copy |
| `patch_diag08_committed_range_revert_test.py` | diagnostic only (phase 08): reverts commit f6708cb of `ppu_loader.cpp` in `/tmp/ps3recomp_diag08_rt` |
