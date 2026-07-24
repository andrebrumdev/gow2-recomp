#!/usr/bin/env python3
"""Idempotent TYPE15 CB56C product fixes:
1) type 0x15 -> 0x80000015 (match WAD construct encoding)
2) if construct returns 0, reuse factory+0x48 linked product
"""
from pathlib import Path
import sys
from lift_paths import resolve_lift_paths

def patch_highbit(t: str) -> str:
    marker = "[TYPE15] CB56C type high-bit"
    if marker in t:
        return t
    needle = '''        { static int _n=0; if(_n++<8)
            fprintf(stderr,"[POSTINTRO] CB56C after 2A49BC r3obj=0x%08X stack+0=0x%08X +2=0x%04X\\n",
              (unsigned)(uint32_t)ctx->gpr[31],
              (unsigned)vm_read32((uint32_t)ctx->gpr[1]+0x70),
              (unsigned)vm_read16((uint32_t)ctx->gpr[1]+0x72)); }
        ctx->gpr[9] = vm_read16(ctx->gpr[1] + 0x72);
'''
    insert = '''        { static int _n=0; if(_n++<8)
            fprintf(stderr,"[POSTINTRO] CB56C after 2A49BC r3obj=0x%08X stack+0=0x%08X +2=0x%04X\\n",
              (unsigned)(uint32_t)ctx->gpr[31],
              (unsigned)vm_read32((uint32_t)ctx->gpr[1]+0x70),
              (unsigned)vm_read16((uint32_t)ctx->gpr[1]+0x72)); }
        /* TYPE15: match WAD path encoding 0x80000015. */
        { uint32_t _d = (uint32_t)ctx->gpr[1] + 0x70u;
          uint32_t _t = vm_read32(_d);
          if (_t == 0x15u) {
            vm_write32(_d, _t | 0x80000000u);
            { static int _n=0; if(_n++<8)
                fprintf(stderr,"[TYPE15] CB56C type high-bit 0x15 -> 0x%08X (match WAD path)\\n",
                  vm_read32(_d)); }
          }
        }
        ctx->gpr[9] = vm_read16(ctx->gpr[1] + 0x72);
'''
    if needle not in t:
        raise SystemExit("highbit needle missing")
    return t.replace(needle, insert, 1)

def patch_reuse(t: str) -> str:
    marker = "[TYPE15] CB56C reuse product"
    if marker in t:
        return t
    needle = '''        { static int _n=0; if(_n++<8)
            fprintf(stderr,"[POSTINTRO] CB56C after icall1 r3=0x%08X\\n", (unsigned)(uint32_t)ctx->gpr[3]); }
        ctx->gpr[29] = ppc_rldicl(ctx->gpr[3], 0, 32);
        ctx->gpr[28] = ctx->gpr[3] | ctx->gpr[3];
        /* Product must be a plausible guest heap/data ptr (not 0x27xxxxxx junk). */
'''
    insert = '''        { static int _n=0; if(_n++<8)
            fprintf(stderr,"[POSTINTRO] CB56C after icall1 r3=0x%08X\\n", (unsigned)(uint32_t)ctx->gpr[3]); }
        /* TYPE15: reuse existing product at factory+0x48 when construct returns 0. */
        if ((uint32_t)ctx->gpr[3] == 0u) {
          uint32_t _ent = 0x47D00000u;
          uint32_t _vt = vm_read32(_ent);
          if (_vt == 0x00516D70u) {
            uint32_t _hdr = vm_read32(_ent + 0x48u);
            if (_hdr >= 0x10000u && _hdr < 0x4F000000u) {
              uint32_t _prod = _hdr + 4u;
              if (_prod >= 0x10000u && _prod < 0x4F000000u) {
                ctx->gpr[3] = _prod;
                { static int _n=0; if(_n++<8)
                    fprintf(stderr,"[TYPE15] CB56C reuse product hdr=0x%08X prod=0x%08X\\n",
                      _hdr, _prod); }
              }
            }
          }
        }
        ctx->gpr[29] = ppc_rldicl(ctx->gpr[3], 0, 32);
        ctx->gpr[28] = ctx->gpr[3] | ctx->gpr[3];
        /* Product must be a plausible guest heap/data ptr (not 0x27xxxxxx junk). */
'''
    if needle not in t:
        raise SystemExit("reuse needle missing")
    return t.replace(needle, insert, 1)

def main():
    paths = resolve_lift_paths(sys.argv[1:], "recomp_macos_v2/ppu_recomp_000.cpp")
    for ps in paths:
        p = Path(ps)
        if not p.exists():
            print(f"skip {p}")
            continue
        t = p.read_text()
        t = patch_highbit(t)
        t = patch_reuse(t)
        p.write_text(t)
        print(f"ok {p}")

if __name__ == "__main__":
    main()
