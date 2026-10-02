# Legacy MinGW build scripts from the Windows bring-up (July 2026)

They lifted and linked `boot_hle.exe` / `boot_gow.exe` in the old `gow2_work/recomp_mid` folder. The current Windows recipe lives in `recomp_mid_v2/` (`rodar_gow2.cmd`, `bt_*.sh`); the Mac build is `build_macos.sh`.

**Archive. Do not extend.** Every shell script here starts with `cd /c/Users/softlive/Documents/self-projects/gow2_work/...` (the original Windows machine), so it behaves exactly as before wherever it is stored, and does nothing useful on any other machine. Kept for the record: dated session notes in `notes/` and in the monorepo (`docs/GOW2_BOOT_STATE.md`, `docs/BASELINE_FASE0.md`, `docs/superpowers/plans/2026-09-29-env-provadas-viram-padrao.md`) cite them by their old root path; `scripts/README.md` maps old to new.

| File | What it did |
|---|---|
| `build3.sh` | first step: 1. LIFT --max-mid-passes 3 --chunk-lines 13000 (cabe RAM + chunks pequenos) |
| `build_boot_gow.sh` | first step: compila pecas de runtime + boot_main () |
| `build_boot_hle.sh` | A prior run that segfaulted can leave a zombie holding the exe -> link fails |
| `build_gow_mid.sh` | first step: 1. regen mid-passes lift (lifter atualizado p/ Codex; emite ppu_stubs) |
| `capped_build.sh` | first step: 1. LIFT --max-mid-passes 1 (cabe na RAM) + fixes |
| `patch_build_test.sh` | first step: 1. copiar recomp_full -> recomp_mid + patch rlwinm/rlwimi (zero-extend) |
| `rebuild_and_test.sh` | first step: 1. RE-LIFT (rlwinm zero-ext + dangling-goto fixup) -j4 |
| `recomp_ra0.sh` | first step: recompilando $N chunks RA=0-fixed (-P 3) |
