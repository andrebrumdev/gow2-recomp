# gdb attach / sample / watch / dump scripts from the Windows bring-up (July 2026)

They start `boot_hle.exe`, attach gdb (`ps -W` for the Windows PID) and dump memory, threads or watchpoints. Superseded on the Mac by `scripts/diag/` and `claude_runs/`.

**Archive. Do not extend.** Every shell script here starts with `cd /c/Users/softlive/Documents/self-projects/gow2_work/...` (the original Windows machine), so it behaves exactly as before wherever it is stored, and does nothing useful on any other machine. Kept for the record: dated session notes in `notes/` and in the monorepo (`docs/GOW2_BOOT_STATE.md`, `docs/BASELINE_FASE0.md`, `docs/superpowers/plans/2026-09-29-env-provadas-viram-padrao.md`) cite them by their old root path; `scripts/README.md` maps old to new.

| File | What it did |
|---|---|
| `attach_mem.sh` | start boot_hle.exe, attach gdb after 13 s and read guest memory |
| `attach_oob.sh` | start boot_hle.exe, attach gdb after 13 s at the out-of-bounds access |
| `attach_threads.sh` | start boot_hle.exe, attach gdb after 13 s and dump every thread |
| `diag_hang.sh` | first step: threads + backtraces |
| `diag_sample.sh` | first step: [cellSysutil] RegisterCallback no stdout? |
| `dump_alloc.sh` | objeto da flag (0x86E118) e o ponteiro global em 0x53FD40 (status do Marco 2) |
| `dump_ctrl_be.sh` | start boot_hle.exe, attach gdb and dump the GCM control register (big-endian) |
| `hang_cmds.gdb` | gdb batch file used by diag_hang.sh (`../hang_cmds.gdb`): threads + backtraces, then detach |
| `oob_bp.sh` | gpr[26] deve ser ~0xFD86Cxxx aqui; ler [gpr2+0x18C0] (global usado por func_00379D00) |
| `probe_flag.sh` | first step: avançou além do loop? linhas NOVAS no stderr (sem OOB) |
| `sample_m2.sh` | first step: THREADS + FUNÇÕES NO TOPO (filtrado) |
| `sample_mem.sh` | helper: read guest u32 (big-endian) at guest addr -> $rd |
| `sample_multi.sh` | boot with PS3_SPURS_STATUS_PTR and sample several threads |
| `trace_list.sh` | seguir a lista a partir de gpr[26], lendo next em +0xC (big-endian) |
| `trace_obj.sh` | first step: recompila loader + relink no-ASLR |
| `watch_ctrl.sh` | watchpoint de hardware no campo limite (+0x20) e no campo count (+0) |
| `watch_flag.sh` | Run gdb with a hard wall-clock cap; if the watchpoint never fires, gdb runs |
| `watch_obj.gdb` | gdb batch file: break at ppu_run, watch guest 0x6FF480 and print each write |
