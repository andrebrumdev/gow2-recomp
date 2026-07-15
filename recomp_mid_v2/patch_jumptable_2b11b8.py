#!/usr/bin/env python3
"""Task 4: materialize PPC switch jump-table in func_002B11B8 (chunk 001).

The lifter left the switch table as /* TODO: .word */ comments and dispatched
via TOC-0x151C + bctr. After R_PermA fully streams, that path yields
ICALL-BAD ctr=0x27182818 and type loaders (ICGLdrShader) never run.

Faithful fix: use the original 28 offsets with guest table base 0x2B1228
(all targets are registered case funcs). Idempotent.
"""
from __future__ import annotations
import sys
from pathlib import Path

MARKER = "Task4 FIX: PPC switch jump-table"

OLD = """        if (((ctx->cr >> 0) & 4)) goto loc_002B12C4;
        ctx->gpr[11] = vm_read32(ctx->gpr[2] + -0x151C);
        ctx->gpr[9] = (uint32_t)ppc_rlwinm((uint32_t)ctx->gpr[0], 2, 18, 29);
        ctx->gpr[0] = vm_read32((ctx->gpr[9] + ctx->gpr[11]));
        ctx->gpr[0] = (int64_t)(int32_t)ctx->gpr[0];
        ctx->gpr[0] = ctx->gpr[0] + ctx->gpr[11];
        ctx->ctr = (uint32_t)ctx->gpr[0];
        ps3_indirect_call(ctx); return;
        /* TODO: .word 0x0000009C */;
        /* TODO: .word 0x000000E4 */;
        /* TODO: .word 0x00000114 */;
        /* TODO: .word 0x00000144 */;
        /* TODO: .word 0x00000354 */;
        /* TODO: .word 0x00000384 */;
        /* TODO: .word 0x00000434 */;
        /* TODO: .word 0x00000638 */;
        /* TODO: .word 0x0000083C */;
        /* TODO: .word 0x0000086C */;
        /* TODO: .word 0x00000A7C */;
        /* TODO: .word 0x00000B1C */;
        /* TODO: .word 0x00000BC8 */;
        /* TODO: .word 0x00000BF8 */;
        /* TODO: .word 0x0000009C */;
        /* TODO: .word 0x0000009C */;
        /* TODO: .word 0x00000C28 */;
        /* TODO: .word 0x0000009C */;
        /* TODO: .word 0x00000C58 */;
        /* TODO: .word 0x00000C88 */;
        /* TODO: .word 0x00000CB8 */;
        /* TODO: .word 0x00000CE8 */;
        /* TODO: .word 0x00000D18 */;
        /* TODO: .word 0x0000009C */;
        /* TODO: .word 0x0000009C */;
        /* TODO: .word 0x00000F48 */;
        /* TODO: .word 0x0000009C */;
        /* TODO: .word 0x00000070 */;
        ctx->gpr[3] = (int64_t)(int32_t)(0xD8);"""

NEW = """        if (((ctx->cr >> 0) & 4)) goto loc_002B12C4;
        /* Task4 FIX: PPC switch jump-table was left as TODO .word comments by the
         * lifter; guest dispatch via TOC-0x151C then bctr often yields garbage CTR
         * (ICALL-BAD 0x27182818 right after R_PermA). Materialize the original
         * table (base guest 0x2B1228 = first .word) and dispatch by known case
         * labels — all targets are registered funcs. Types 0..0x1B inclusive. */
        {
          static const uint32_t k_jt[0x1C] = {
            0x0000009C, 0x000000E4, 0x00000114, 0x00000144,
            0x00000354, 0x00000384, 0x00000434, 0x00000638,
            0x0000083C, 0x0000086C, 0x00000A7C, 0x00000B1C,
            0x00000BC8, 0x00000BF8, 0x0000009C, 0x0000009C,
            0x00000C28, 0x0000009C, 0x00000C58, 0x00000C88,
            0x00000CB8, 0x00000CE8, 0x00000D18, 0x0000009C,
            0x0000009C, 0x00000F48, 0x0000009C, 0x00000070
          };
          const uint32_t ty = (uint32_t)ctx->gpr[0];
          const uint32_t base = 0x002B1228u;
          uint32_t tgt = base + k_jt[ty < 0x1Cu ? ty : 0];
          { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYDISP")?1:0;}
            if(on){ static int n=0; if(n++<40)
              fprintf(stderr,"[TYDISP] type=%u -> 0x%08X\\n", ty, tgt); } }
          ctx->ctr = tgt;
          ps3_indirect_call(ctx); DRAIN_TRAMPOLINE(ctx);
          return;
        }
        ctx->gpr[3] = (int64_t)(int32_t)(0xD8);"""


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
    path = root / "ppu_recomp_001.cpp"
    if not path.is_file():
        print(f"FAIL: {path} missing", file=sys.stderr)
        return 1
    src = path.read_text(encoding="utf-8", errors="replace")
    if MARKER in src:
        print("OK: already patched")
        return 0
    if OLD not in src:
        print("FAIL: needle not found", file=sys.stderr)
        return 2
    path.write_text(src.replace(OLD, NEW, 1), encoding="utf-8", newline="\n")
    print(f"OK: patched {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
