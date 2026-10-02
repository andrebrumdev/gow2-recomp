# One-off trace/run scripts (`tr*.sh`) from the Windows bring-up (July 2026)

Each one rebuilt a piece of the old MinGW build (`boot_hle.exe`) and ran it with one trace switch, then grepped the log. They were the root's `tr*.sh` files until 2026-10-02.

**Archive. Do not extend.** Every shell script here starts with `cd /c/Users/softlive/Documents/self-projects/gow2_work/...` (the original Windows machine), so it behaves exactly as before wherever it is stored, and does nothing useful on any other machine. Kept for the record: dated session notes in `notes/` and in the monorepo (`docs/GOW2_BOOT_STATE.md`, `docs/BASELINE_FASE0.md`, `docs/superpowers/plans/2026-09-29-env-provadas-viram-padrao.md`) cite them by their old root path; `scripts/README.md` maps old to new.

| File | What it did |
|---|---|
| `cas.pl` | perl substitutions that turn lifted lwarx/stwcx/ldarx/stdcx blocks into ppu_* helper calls; used by trcas_all.sh as `../cas.pl` (the gow2_work root on the old machine) |
| `tr040.sh` | first step: recompila loader + chunk040 |
| `tr042.sh` | first step: recompila chunk 042 |
| `trallo.sh` | first step: recompila chunk 024 (trace ALLOC) |
| `trallocaller.sh` | first step: recompila chunk 024 |
| `trbridge.sh` | first step: compile cellGcmSys (com bridge) + rsx_commands + backends |
| `trbridge2.sh` | first step: melhor run (mais [rsx] m=) — amostra do dump FIFO |
| `trbs.sh` | run 2..4: PS3_BUILD_SINGLETON boot, counts FIX-b / sceNp / cellGcm lines |
| `trbuild.sh` | first step: recompila chunk 048 |
| `trcas_all.sh` | first step: 1. recompila ppu_loader.cpp (helpers value-CAS) |
| `trcb.sh` | first step: run SÓ PS3_SYSUTIL_BOOT=1 (limpo, sem force) (12s) |
| `trcbcaller.sh` | pega a 2a linha de frames (r3=0x0, loop estável), mapeia cada addr |
| `trchar.sh` | first step: recompila lib_cellVideoOut (fix raw-ptr) |
| `trcrash.sh` | first step: recompila boot_main (com SEH crash handler) |
| `trdl.sh` | first step: run: FIX_DISPLAYLIST + tudo |
| `trf2.sh` | first step: run: fence completion |
| `trfence.sh` | first step: run: FIFO drenado no poll do label |
| `trfifo.sh` | first step: run: dump FIFO real (FORCE_GCMINIT) |
| `trfix.sh` | first step: recompila runtime/syscalls/*.c |
| `trflip.sh` | first step: run: flip signature fix |
| `trforce.sh` | first step: recompila chunk 042 |
| `trfp.sh` | first step: run: RSX FIFO processor + trace |
| `trgcm.sh` | first step: recompila lib_cellGcmSys |
| `trgcm2.sh` | first step: recompile chunk 048 (14:23:28) |
| `trgcm3.sh` | first step: run: FORCE_GCMINIT + singleton + spin-break |
| `trgcm_cfg.sh` | first step: recompila lib_cellGcmSys (fixes raw-ptr) |
| `trgpu.sh` | first step: run (10s) GPU mínimo |
| `trheap.sh` | first step: recompila ppu_loader.cpp (trace HEAP) |
| `trinit.sh` | first step: run: _cellGcmInitBody chamado? GCM inicializa? |
| `trlv2.sh` | first step: compile boot_main.o |
| `troobra.sh` | first step: recompile ppu_loader.o |
| `trpad.sh` | first step: recompila cellSysutil + ppu_hle_nids |
| `trra0.sh` | RA=0 (literal 0) em lwarx/stwcx: 'ea = gpr[0] + gpr[N]' deve virar 'ea = gpr[N]'. |
| `trra0_run.sh` | first step: relink (todos .o RA=0-fixed) |
| `trreorder.sh` | first step: recompila aggregator chunk (ppu_recomp_042 com reorder) |
| `trrsv.sh` | first step: recompila ppu_loader.cpp (tabela de reservas cross-thread) |
| `trrsx.sh` | first step: run: dump FIFO RSX |
| `trrsx2.sh` | first step: run: dump FIFO (2 bases) + GCM trace |
| `trsc.sh` | first step: recompila loader |
| `trsem.sh` | first step: run PS3_BUILD_SINGLETON=1 PS3_FAKE_SEM=1 PS3_TRACE_SPURS=all (10s) |
| `trskip.sh` | first step: recompila chunk 048 |
| `trspin.sh` | first step: run (6s) |
| `trspin2.sh` | first step: compile 2 libs alteradas |
| `trspursready.sh` | first step: recompila chunk com o shim (ppu_recomp_054) |
| `trtid.sh` | first step: recompila loader |
| `trtrophy.sh` | first step: recompila lib_sceNpTrophy (fix ponteiros guest) |
| `trwatch.sh` | first step: recompila boot_main (com watchdog) |
