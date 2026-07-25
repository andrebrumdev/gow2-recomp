#!/usr/bin/env python3
"""When Play is re-entered with st620!=0, keep the in-flight FIOS open.

WHY
---
Guest EBOOT at 0x002C0498 does:
  bl  0x002BFF88   # teardown container (cancel + clear +8)
  b   0x002C0124   # re-enter full Play body -> re-open m2v

On the recompiler the teardown/re-open races the FIOS op pool:
  open#1 succeeds and writes container+8
  Play#2 teardowns, open#2 hits SEM OP LIVRE, writes 0
  state-1 poll sees io=0 forever

Hardware can free the cancelled op between teardown and re-open; under the
giant lock that window often does not exist.

FIX
---
Replace 002C0498 with Play's epilogue (same stack layout as 0x002C03FC):
return to the caller without teardown/re-open, preserving the in-flight
open for the state-1 poller.

Marker: FIOS-PLAY-ALREADY-ACTIVE. Idempotent.
"""
from pathlib import Path
import re
import sys

MARKER = "FIOS-PLAY-ALREADY-ACTIVE"

ROOT = (Path(sys.argv[1]) if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent / "recomp_macos_v2")

NEW = '''/* %s:
 * Guest re-enters Play while st620!=0. Skip teardown+re-open so the
 * in-flight FIOS open (container+8) survives for state-1 poll. */
void func_002C0498(ppu_context* ctx) {
        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0x2D0);
        ctx->gpr[25] = vm_read64(ctx->gpr[1] + 0x288);
        ctx->gpr[26] = vm_read64(ctx->gpr[1] + 0x290);
        ctx->lr = ctx->gpr[0];
        ctx->gpr[27] = vm_read64(ctx->gpr[1] + 0x298);
        ctx->gpr[28] = vm_read64(ctx->gpr[1] + 0x2A0);
        ctx->gpr[29] = vm_read64(ctx->gpr[1] + 0x2A8);
        ctx->gpr[30] = vm_read64(ctx->gpr[1] + 0x2B0);
        ctx->gpr[31] = vm_read64(ctx->gpr[1] + 0x2B8);
        ctx->gpr[1] = (int64_t)(int32_t)(ctx->gpr[1] + 0x2C0);
        ctx->gpr[3] = (int64_t)(int32_t)(0);
        return;
}
''' % MARKER


def patch_file(p: Path) -> str:
    t = p.read_text(encoding="utf-8", errors="replace")
    if MARKER in t:
        return "ALREADY"
    if "void func_002C0498" not in t:
        return "SKIP"
    # Match original or any previously patched body of 002C0498.
    pat = re.compile(
        r'(?:/\*[^*]*FIOS[^*]*\*/\n'
        r'(?:extern "C" void [^\n]+\n)*\n)?'
        r'void func_002C0498\(ppu_context\* ctx\) \{.*?\n\}',
        re.S,
    )
    m = pat.search(t)
    if not m:
        return "SKIP"
    t = t[:m.start()] + NEW + t[m.end():]
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
        print("SKIP: func_002C0498 not found")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
