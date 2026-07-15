#!/usr/bin/env python3
"""
GroupEnd expand path OPD fix (func_002B0AA8).

Evidence:
- Type-1 SHGX factory creates objects (VT28R nonzero) but never reaches ICGLdr.
- GroupEnd handler 0x2B0AA8 runs once per group and calls member vtable+0x2C
  via ps3_indirect_call (treats OPD as raw code) — same broken class as prior
  OPD bugs that blocked type loaders.
- Also fix 0x2B0DB0 (two OPD sites) used by another stream type.
"""
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
p = ROOT / "ppu_recomp_001.cpp"
s = p.read_text(encoding="utf-8", errors="replace")

if 'void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);' not in s[:30000]:
    old = 'extern "C" void ps3_indirect_call(ppu_context* ctx);'
    if old not in s[:30000]:
        raise SystemExit("no ps3_indirect_call decl")
    s = s.replace(old, old + '\nextern "C" void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);', 1)
    print("declared ps3_call_opd")

# --- GroupEnd 2B0AA8 ---
i = s.find("void func_002B0AA8")
if i < 0:
    raise SystemExit("2B0AA8 missing")
j = s.find("void func_", i + 10)
region = s[i:j]

old = """        ctx->gpr[10] = vm_read32(ctx->gpr[9] + 0x2C);
        ctx->gpr[0] = vm_read32(ctx->gpr[10] + 0x0);
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ctx->ctr = (uint32_t)ctx->gpr[0];
        ctx->gpr[2] = vm_read32(ctx->gpr[10] + 0x4);
        ps3_indirect_call(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        ctx->gpr[9] = vm_read32(ctx->gpr[29] + 0x0);"""

new = """        ctx->gpr[10] = vm_read32(ctx->gpr[9] + 0x2C);
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<48)
            fprintf(stderr,"[WADLD-GEND] #%d self=0x%08X member=0x%08X opd=0x%08X code=0x%08X\\n",
              n,(uint32_t)ctx->gpr[11],(uint32_t)ctx->gpr[5],(uint32_t)ctx->gpr[10],
              ctx->gpr[10]?vm_read32(ctx->gpr[10]+0x0):0); fflush(stderr);} }
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ps3_call_opd(ctx, (uint32_t)ctx->gpr[10]); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<48)
            fprintf(stderr,"[WADLD-GENDR] #%d r3=0x%08X\\n", n,(uint32_t)ctx->gpr[3]); fflush(stderr);} }
        ctx->gpr[9] = vm_read32(ctx->gpr[29] + 0x0);"""

if "WADLD-GEND" in region:
    print("2B0AA8 already patched")
elif old not in region:
    raise SystemExit("2B0AA8 OPD pattern missing")
else:
    region = region.replace(old, new, 1)
    s = s[:i] + region + s[j:]
    print("patched 2B0AA8 GroupEnd OPD")

# --- 2B0DB0 two OPD sites ---
i = s.find("void func_002B0DB0")
if i < 0:
    raise SystemExit("2B0DB0 missing")
j = s.find("void func_", i + 10)
region = s[i:j]

# generic OPD block appears twice - replace both with call_opd
old_opd = """        ctx->gpr[0] = vm_read32(ctx->gpr[10] + 0x0);
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ctx->ctr = (uint32_t)ctx->gpr[0];
        ctx->gpr[2] = vm_read32(ctx->gpr[10] + 0x4);
        ps3_indirect_call(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);"""

new_opd = """        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ps3_call_opd(ctx, (uint32_t)ctx->gpr[10]); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);"""

if region.count(old_opd) >= 1:
    n = region.count(old_opd)
    region = region.replace(old_opd, new_opd)
    s = s[:i] + region + s[j:]
    print(f"patched 2B0DB0 OPD sites x{n}")
elif "ps3_call_opd" in region:
    print("2B0DB0 already uses call_opd")
else:
    print("WARNING: 2B0DB0 OPD pattern not found")

p.write_text(s, encoding="utf-8", newline="\n")
print("OK patch_groupend_opd")
