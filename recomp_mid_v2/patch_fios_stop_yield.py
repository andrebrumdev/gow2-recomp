#!/usr/bin/env python3
"""Yield after MovieStop SMPD epilogue so FIOS can free ops before WAD open.

WHY
---
After SEQDONE + EOS arm, MovieStop (st=11 path func_002BFFE0/FFF4/C0048 in
chunk 002, and loc_002C0048 in 001) cancels media and broadcasts SMPD, then
returns to a caller that immediately opens R_LglScA. Under the giant lock the
FIOS scheduler rarely drains cancel before that open -> SEM OP LIVRE (F2a).

Measured 2026-07-21 Task 4b: yield alone is NOT sufficient when the movie op
was already cancelled without free at DONE (see patch_fios_done_cancel_yield).
Still useful when cancel is pending at Stop time.

Marker: FIOS-STOP-YIELD. Idempotent. Gated by PS3_FIOS_STOP_YIELD_MS (default 50;
0 disables).
"""
from pathlib import Path
import sys

MARKER = "FIOS-STOP-YIELD"
ROOT = (Path(sys.argv[1]) if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent / "recomp_macos_v2")

NEEDLE = (
    "        vm_write32(ctx->gpr[31] + 0x620, ctx->gpr[0]);\n"
    "        func_0043FF30(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    "        /* nop */;\n"
    "        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0x90);\n"
)

INSERT = (
    "        vm_write32(ctx->gpr[31] + 0x620, ctx->gpr[0]);\n"
    "        func_0043FF30(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    "        /* nop */;\n"
    "        /* " + MARKER + ": free FIOS ops before caller opens R_LglScA (F2a).\n"
    "         * Default 50ms; PS3_FIOS_STOP_YIELD_MS=0 disables. */\n"
    "        { static int _ms=-1; if(_ms<0){const char* e=getenv(\"PS3_FIOS_STOP_YIELD_MS\");\n"
    "            _ms = (e&&*e) ? atoi(e) : 50;}\n"
    "          if(_ms>0){ ppu_giant_lock_release();\n"
    "            usleep((useconds_t)_ms * 1000u);\n"
    "            ppu_giant_lock_acquire();\n"
    "            fprintf(stderr,\"[FIOSOPEN] STOP-YIELD %d ms after MovieStop\\n\", _ms);\n"
    "            fflush(stderr); } }\n"
    "        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0x90);\n"
)

DECL = (
    "/* " + MARKER + " decls */\n"
    'extern "C" void ppu_giant_lock_release(void);\n'
    'extern "C" void ppu_giant_lock_acquire(void);\n'
    "#include <unistd.h>\n"
    "#include <stdlib.h>\n"
    "\n"
)


def patch_file(p: Path) -> str:
    t = p.read_text(encoding="utf-8", errors="replace")
    if NEEDLE not in t:
        if MARKER in t:
            return "ALREADY"
        return "SKIP"
    n = 0
    while NEEDLE in t:
        t = t.replace(NEEDLE, INSERT, 1)
        n += 1
    if MARKER + " decls" not in t:
        if "#include <math.h>\n" in t:
            t = t.replace("#include <math.h>\n", "#include <math.h>\n" + DECL, 1)
        else:
            t = DECL + t
    p.write_text(t, encoding="utf-8")
    return "APPLIED x%d" % n


def main() -> int:
    files = sorted(ROOT.glob("ppu_recomp_*.cpp"))
    if not files:
        print("nenhum ppu_recomp_*.cpp em %s" % ROOT)
        return 1
    for f in files:
        print("%s: %s" % (f.name, patch_file(f)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
