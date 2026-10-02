# Stray artefacts from early sessions

Files that used to sit at the repository root without a purpose there. Nothing in the build, the kit,
the launchers or the tests reads them; they are kept because dated notes may mention them. Moved here on
2026-10-02 (see [`scripts/README.md`](../../scripts/README.md)).

| File | What it is |
|---|---|
| `elf_loader_design.json` | agent review of an SPU ELF-loader design ("~90 % correct", one forward-reference bug) |
| `items123_design.json` | agent design notes for the SPU stop-code hook and the C11-atomic mailbox (written on the Windows machine) |
| `spu_interp_design.json` | agent review of the SPU interpreter architecture against the real code |
| `tasks_design.json` | agent task breakdown for loading a real SPU ELF image into local store |
| `research_result.json` | survey of other static recompilers (N64Recomp, XenonRecomp, ...) and what transfers to ps3recomp |
| `override_test.json` | one-entry function list (`["0x263040"]`) from an override experiment |
| `boot_fixed.stdout` | empty capture of a boot's stdout |
| `_stopn_test.c` | scratch C test of the SPU stop-code path (`spu_interp.h`, `spu_dma.h`); not built by anything |
