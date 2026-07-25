#!/usr/bin/env python3
"""FIOS/asset: fix func_0042A1D4 empty-count mid-function jump (R_PermA wall).

Measured 2026-07-21 (Mac arm64 GoW2):
  After R_LglScA F2B open+DONE, guest hits func_0042A0C8 with count byte
  at obj+0x80 signed-negative (empty table). Lifter branch goes to
  func_0042A1D4 which zeros r28 and trampolines into the MID of
  func_0042A118 (list walk at r28+0x38). With r28=0 that walks absolute
  EA 0x38 → garbage → UNCOMMITTED read32 0x676C7367 ("glsg" path/TOC
  bytes interpreted as pointer). Guest never reaches open of R_PermA.

  Same class as fallthrough-to-wrong-target (fix 2550C8): empty-count
  path must take the epilogue of 0042A0C8/0042A118 (r28=0 → ret r3=4),
  not the list-walk body.

In-boot after fix (/tmp/vdec_emptyfix.log ~55s):
  42A1D4-EMPTY skip → 002B4340 nome='R_PermA' → F2B-MOVIEIO 20169344
  → DONE #3. R_LglScA still GREEN. UNCOMMITTED 0x676C7367 gone.
  Follow-up (not this patch): bulk aread of R_PermA (20MB stream).

Markers: FIOS-42A1D4-EMPTY
Idempotent. Lift is gitignored — re-run after re-lift.

Usage:
  python3 recomp_mid_v2/patch_fios_42a1d4_empty.py [recomp_macos_v2]
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "recomp_macos_v2"
MARKER = "FIOS-42A1D4-EMPTY"

OLD = """void func_0042A1D4(ppu_context* ctx) {
        ctx->gpr[0] = (int64_t)(int32_t)(ctx->gpr[9] + -1);
        ctx->gpr[28] = (int64_t)(int32_t)(0);
        vm_write8(ctx->gpr[3] + 0x80, ctx->gpr[0]);
        { g_trampoline_fn = (void(*)(void*))func_0042A118; return; }
        { g_trampoline_fn = (void(*)(void*))func_0042A1E4; return; }
}"""

NEW = """void func_0042A1D4(ppu_context* ctx) {
        /* FIOS-42A1D4-EMPTY: count byte at obj+0x80 is signed-negative
         * (empty table). Original intent = skip list walk and take the
         * epilogue of 0042A0C8/0042A118 with r28=0 (ret r3=r28+4=4).
         * Lifter sent us to mid-function 0042A118 which walks r28+0x38
         * with r28=0 → absolute EA 0x38 → garbage → UNCOMMITTED 0x676C7367.
         * Always-on correctness fix; log when PS3_TRACE_FIOSOPEN=1. */
        ctx->gpr[0] = (int64_t)(int32_t)(ctx->gpr[9] + -1);
        ctx->gpr[28] = (int64_t)(int32_t)(0);
        vm_write8(ctx->gpr[3] + 0x80, ctx->gpr[0]);
        { static int _on=-1; if(_on<0){const char* e=getenv("PS3_TRACE_FIOSOPEN");
            _on=(e&&*e&&*e!='0')?1:0;}
          if(_on){ static int _n=0; if(_n++<4){
            fprintf(stderr,"[FIOSOPEN] 42A1D4-EMPTY skip list walk r3=0x%08X count_was=%d\\n",
              (uint32_t)ctx->gpr[3], (int)(int8_t)(uint8_t)ctx->gpr[9]);
            fflush(stderr); } } }
        /* Epilogue of 0042A118 (loc_0042A198) — guest frame already live
         * from 0042A0C8 entry before the trampoline. */
        func_002AAB84(ctx); DRAIN_TRAMPOLINE(ctx);
        func_00262C8C(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0xB0);
        ctx->gpr[27] = vm_read64(ctx->gpr[1] + 0x78);
        ctx->gpr[3] = (int64_t)(int32_t)(ctx->gpr[28] + 4);
        ctx->gpr[29] = vm_read64(ctx->gpr[1] + 0x88);
        ctx->gpr[28] = vm_read64(ctx->gpr[1] + 0x80);
        ctx->lr = ctx->gpr[0];
        ctx->gpr[3] = ppc_rldicl(ctx->gpr[3], 0, 32);
        ctx->gpr[30] = vm_read64(ctx->gpr[1] + 0x90);
        ctx->gpr[31] = vm_read64(ctx->gpr[1] + 0x98);
        ctx->gpr[1] = (int64_t)(int32_t)(ctx->gpr[1] + 0xA0);
        return;
}"""


def main() -> int:
    target = None
    for name in ("ppu_recomp_003.cpp", "ppu_recomp_001.cpp", "ppu_recomp_005.cpp"):
        cand = ROOT / name
        if cand.is_file() and "void func_0042A1D4" in cand.read_text(errors="replace"):
            target = cand
            break
    if not target:
        print(f"func_0042A1D4 not found under {ROOT}")
        return 1
    text = target.read_text()
    if MARKER in text:
        print(f"{target.name}: {MARKER} already applied")
        return 0
    if OLD not in text:
        print(f"{target.name}: expected 0042A1D4 body not found (lift drifted?)")
        return 2
    target.write_text(text.replace(OLD, NEW, 1))
    print(f"{target.name}: applied {MARKER}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
