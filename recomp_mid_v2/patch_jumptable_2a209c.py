#!/usr/bin/env python3
"""Materialize PPC switch jump-table in func_002A209C (chunk 001).

Same class of lifter bug as Task4 func_002B11B8: table left as TODO .word,
dispatch via TOC-0x1694 + bctr. Byte opcode switch 0..0x39 (58 cases).
Guest table base 0x2A2134 (matches TOC-0x1694 and ELF).

This is on the stream byte-walker path (reads u8, advances cursor) — likely
the WAD/group content dispatcher that never reaches ICGLdr.
"""
from __future__ import annotations
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
C1 = ROOT / "ppu_recomp_001.cpp"
MARKER = "Task5 FIX: PPC switch jump-table 2A209C"

OLD = """        if (((ctx->cr >> 0) & 4)) goto loc_002A2238;
        ctx->gpr[11] = vm_read32(ctx->gpr[2] + -0x1694);
        ctx->gpr[9] = (uint32_t)ppc_rlwinm((uint32_t)ctx->gpr[9], 2, 22, 29);
        ctx->gpr[0] = vm_read32((ctx->gpr[9] + ctx->gpr[11]));
        ctx->gpr[0] = (int64_t)(int32_t)ctx->gpr[0];
        ctx->gpr[0] = ctx->gpr[0] + ctx->gpr[11];
        ctx->ctr = (uint32_t)ctx->gpr[0];
        ps3_indirect_call(ctx); return;
        /* TODO: .word 0x00000688 */;
        /* TODO: .word 0x00000524 */;
        /* TODO: .word 0x000000E8 */;
        /* TODO: .word 0x000012C8 */;
        /* TODO: .word 0x000012E8 */;
        /* TODO: .word 0x000011B8 */;
        /* TODO: .word 0x000011D8 */;
        /* TODO: .word 0x000011D8 */;
        /* TODO: .word 0x000011D8 */;
        /* TODO: .word 0x000011D8 */;
        /* TODO: .word 0x00001214 */;
        /* TODO: .word 0x0000126C */;
        /* TODO: .word 0x000008DC */;
        /* TODO: .word 0x00000938 */;
        /* TODO: .word 0x00000994 */;
        /* TODO: .word 0x000009F4 */;
        /* TODO: .word 0x00000A4C */;
        /* TODO: .word 0x00000A74 */;
        /* TODO: .word 0x0000112C */;
        /* TODO: .word 0x00001168 */;
        /* TODO: .word 0x00000AB0 */;
        /* TODO: .word 0x00000B08 */;
        /* TODO: .word 0x00000320 */;
        /* TODO: .word 0x00000394 */;
        /* TODO: .word 0x00000400 */;
        /* TODO: .word 0x0000045C */;
        /* TODO: .word 0x000004C8 */;
        /* TODO: .word 0x00001514 */;
        /* TODO: .word 0x00000DFC */;
        /* TODO: .word 0x00000E74 */;
        /* TODO: .word 0x00000EE4 */;
        /* TODO: .word 0x00000F48 */;
        /* TODO: .word 0x00000FA4 */;
        /* TODO: .word 0x0000100C */;
        /* TODO: .word 0x00001068 */;
        /* TODO: .word 0x000010C4 */;
        /* TODO: .word 0x00000C10 */;
        /* TODO: .word 0x00000C70 */;
        /* TODO: .word 0x00000CF8 */;
        /* TODO: .word 0x00000D74 */;
        /* TODO: .word 0x00000B74 */;
        /* TODO: .word 0x00000BC4 */;
        /* TODO: .word 0x000002A8 */;
        /* TODO: .word 0x00000818 */;
        /* TODO: .word 0x0000088C */;
        /* TODO: .word 0x00001308 */;
        /* TODO: .word 0x00001374 */;
        /* TODO: .word 0x000013C0 */;
        /* TODO: .word 0x0000140C */;
        /* TODO: .word 0x00001478 */;
        /* TODO: .word 0x000014C4 */;
        /* TODO: .word 0x0000060C */;
        /* TODO: .word 0x00000228 */;
        /* TODO: .word 0x00000594 */;
        /* TODO: .word 0x00000228 */;
        /* TODO: .word 0x000006F8 */;
        /* TODO: .word 0x00000780 */;
        /* TODO: .word 0x000007B4 */;
        ctx->gpr[31] = (int64_t)(int32_t)(ctx->gpr[1] + 0x70);"""

NEW = """        if (((ctx->cr >> 0) & 4)) goto loc_002A2238;
        /* Task5 FIX: PPC switch jump-table 2A209C was left as TODO .word by the
         * lifter; TOC-0x1694 + bctr never hits real case labels. Materialize the
         * original 58 offsets (base guest 0x2A2134 = first .word = TOC-0x1694).
         * Byte opcodes 0..0x39 inclusive. */
        {
          static const uint32_t k_jt[0x3A] = {
            0x00000688, 0x00000524, 0x000000E8, 0x000012C8,
            0x000012E8, 0x000011B8, 0x000011D8, 0x000011D8,
            0x000011D8, 0x000011D8, 0x00001214, 0x0000126C,
            0x000008DC, 0x00000938, 0x00000994, 0x000009F4,
            0x00000A4C, 0x00000A74, 0x0000112C, 0x00001168,
            0x00000AB0, 0x00000B08, 0x00000320, 0x00000394,
            0x00000400, 0x0000045C, 0x000004C8, 0x00001514,
            0x00000DFC, 0x00000E74, 0x00000EE4, 0x00000F48,
            0x00000FA4, 0x0000100C, 0x00001068, 0x000010C4,
            0x00000C10, 0x00000C70, 0x00000CF8, 0x00000D74,
            0x00000B74, 0x00000BC4, 0x000002A8, 0x00000818,
            0x0000088C, 0x00001308, 0x00001374, 0x000013C0,
            0x0000140C, 0x00001478, 0x000014C4, 0x0000060C,
            0x00000228, 0x00000594, 0x00000228, 0x000006F8,
            0x00000780, 0x000007B4
          };
          const uint32_t op = (uint32_t)ctx->gpr[9];
          const uint32_t base = 0x002A2134u;
          uint32_t tgt = base + k_jt[op < 0x3Au ? op : 0];
          { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
            if(on){ static int n=0; if(n++<80)
              fprintf(stderr,"[OPDISP] op=%u -> 0x%08X\\n", op, tgt); } }
          ctx->ctr = tgt;
          ps3_indirect_call(ctx); DRAIN_TRAMPOLINE(ctx);
          return;
        }
        ctx->gpr[31] = (int64_t)(int32_t)(ctx->gpr[1] + 0x70);"""

def main() -> None:
    s = C1.read_text(encoding="utf-8", errors="replace")
    if MARKER in s:
        print("OK: already patched")
        return
    if OLD not in s:
        raise SystemExit("needle missing for 2A209C")
    C1.write_text(s.replace(OLD, NEW, 1), encoding="utf-8", newline="\n")
    print("OK: patched func_002A209C jump table")

if __name__ == "__main__":
    main()
