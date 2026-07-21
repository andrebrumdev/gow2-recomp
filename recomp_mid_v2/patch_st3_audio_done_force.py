#!/usr/bin/env python3
"""HLE A3b: force the state-3 audio gate when host marks stream complete.

WHY
---
Task 3b class A3b: st620 parks at 3 because func_002C0FA0 calls
func_0045B2A8(obj+0x720) and only advances when the return is non-zero
(literal 0 parks; -1 advances). The return is *(session+0x1B8) after
generational resolve. On Mac the guest service loop never sets +0x1B8.

movie_eos_arm.c marks stream-complete after the real .wav duration
(produtor MOVIEDONE) by either writing session+0x1B8 or setting
g_movie_audio_gate_force=1. This patch makes the live site honour that
flag so the FSM advances 3->4 without forging st620 or +0x744.

PLACEMENT
---------
Only the live body of func_002C0FA0 (same dead-code trap as
patch_st3_audio_gate.py: 14 dead copies of the 0045B2A8 call). Anchor on
the function signature.

Gated by the host variable (always linked); host sets it only when
movie_audio_should_mark_done allows (done producer + st==3 + h720).
Idempotent marker AUDDONE-FORCE.
"""
from pathlib import Path
import sys

MARKER = "AUDDONE-FORCE"

ROOT = (Path(sys.argv[1]) if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent / "recomp_macos_v2")

NEEDLE = (
    "void func_002C0FA0(ppu_context* ctx) {\n"
    "        ctx->gpr[3] = vm_read32(ctx->gpr[30] + 0x720);\n"
    "        func_0045B2A8(ctx); DRAIN_TRAMPOLINE(ctx);\n"
)

# Insert after 0045B2A8 (+ optional AUDGATE probe if already present is OK:
# we match the three lines above which precede any probe insert).
INSERT = (
    "void func_002C0FA0(ppu_context* ctx) {\n"
    "        ctx->gpr[3] = vm_read32(ctx->gpr[30] + 0x720);\n"
    "        func_0045B2A8(ctx); DRAIN_TRAMPOLINE(ctx);\n"
    "        /* " + MARKER + ": A3b HLE -- se host marcou stream-complete, "
    "forca rc!=0 (equiv. sess+0x1B8) */\n"
    "        { extern int g_movie_audio_gate_force;\n"
    "          if (g_movie_audio_gate_force) ctx->gpr[3] = 1; }\n"
)


def patch_file(p: Path) -> str:
    t = p.read_text(encoding="utf-8", errors="replace")
    if MARKER in t:
        return "ALREADY"
    if NEEDLE not in t:
        return "SKIP"
    t = t.replace(NEEDLE, INSERT, 1)
    p.write_text(t, encoding="utf-8")
    return "APPLIED"


def main() -> int:
    files = sorted(ROOT.glob("ppu_recomp_*.cpp"))
    if not files:
        print("nenhum ppu_recomp_*.cpp em %s" % ROOT)
        return 1
    any_hit = False
    for p in files:
        r = patch_file(p)
        if r != "SKIP":
            any_hit = True
            print("%s: %s" % (p.name, r))
    if not any_hit:
        print("SKIP: needle not found (func_002C0FA0)")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
