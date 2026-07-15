#!/usr/bin/env python3
"""
Fix group factory OPDs (0039E6B4) + probe 2B0FB4 post-create gate that skips VT48.

Root cause candidates:
1. func_0039E6B4 uses ps3_indirect_call on nested OPDs (broken same class as prior OPD bugs)
2. After create, VT48 only runs if *(obj) low16==3 and field==1; need evidence of actual header
"""
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent

# ---------------------------------------------------------------------------
# 1) Fix factory OPD calls in ppu_recomp_001.cpp
# ---------------------------------------------------------------------------
p1 = ROOT / "ppu_recomp_001.cpp"
s1 = p1.read_text(encoding="utf-8", errors="replace")

if 'void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);' not in s1[:30000]:
    old = 'extern "C" void ps3_indirect_call(ppu_context* ctx);'
    if old not in s1[:30000]:
        raise SystemExit("no ps3_indirect_call decl in 001")
    s1 = s1.replace(old, old + '\nextern "C" void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);', 1)
    print("001: declared ps3_call_opd")

i = s1.find("void func_0039E6B4")
if i < 0:
    raise SystemExit("func_0039E6B4 not found")
j = s1.find("void func_", i + 10)
region = s1[i:j]

# First OPD: vt+0x4C alloc/size helper
old_a = """        ctx->gpr[11] = vm_read32(ctx->gpr[9] + 0x4C);
        ctx->gpr[0] = vm_read32(ctx->gpr[11] + 0x0);
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ctx->ctr = (uint32_t)ctx->gpr[0];
        ctx->gpr[2] = vm_read32(ctx->gpr[11] + 0x4);
        ps3_indirect_call(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);"""

new_a = """        ctx->gpr[11] = vm_read32(ctx->gpr[9] + 0x4C);
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<16)
            fprintf(stderr,"[WADLD-FACT] #A n=%d self=0x%08X opd=0x%08X code=0x%08X\\n",
              n,(uint32_t)ctx->gpr[29],(uint32_t)ctx->gpr[11],
              ctx->gpr[11]?vm_read32(ctx->gpr[11]+0x0):0); fflush(stderr);} }
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ps3_call_opd(ctx, (uint32_t)ctx->gpr[11]); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);"""

# Second OPD: vt+0x28 ctor
old_b = """        ctx->gpr[10] = vm_read32(ctx->gpr[9] + 0x28);
        ctx->gpr[0] = vm_read32(ctx->gpr[10] + 0x0);
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ctx->ctr = (uint32_t)ctx->gpr[0];
        ctx->gpr[2] = vm_read32(ctx->gpr[10] + 0x4);
        ps3_indirect_call(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0xA0);
        ctx->gpr[3] = ppc_rldicl(ctx->gpr[3], 0, 32);"""

new_b = """        ctx->gpr[10] = vm_read32(ctx->gpr[9] + 0x28);
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<16)
            fprintf(stderr,"[WADLD-FACT] #B n=%d obj=0x%08X opd=0x%08X code=0x%08X\\n",
              n,(uint32_t)ctx->gpr[11],(uint32_t)ctx->gpr[10],
              ctx->gpr[10]?vm_read32(ctx->gpr[10]+0x0):0); fflush(stderr);} }
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ps3_call_opd(ctx, (uint32_t)ctx->gpr[10]); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<16)
            fprintf(stderr,"[WADLD-FACT] #BR n=%d r3=0x%08X hdr=0x%08X\\n",
              n,(uint32_t)ctx->gpr[3],
              ctx->gpr[3]?vm_read32(ctx->gpr[3]+0x0):0); fflush(stderr);} }
        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0xA0);
        ctx->gpr[3] = ppc_rldicl(ctx->gpr[3], 0, 32);"""

changed = 0
if "WADLD-FACT" in region:
    print("001: factory already patched")
else:
    if old_a not in region:
        raise SystemExit("factory OPD-A pattern missing")
    if old_b not in region:
        raise SystemExit("factory OPD-B pattern missing")
    region = region.replace(old_a, new_a, 1).replace(old_b, new_b, 1)
    s1 = s1[:i] + region + s1[j:]
    changed = 1
    print("001: factory OPDs -> ps3_call_opd + FACT probes")

if changed:
    p1.write_text(s1, encoding="utf-8", newline="\n")
    print("001: written")

# ---------------------------------------------------------------------------
# 2) Gate probe in func_002B0FB4 (ppu_recomp_003.cpp)
# ---------------------------------------------------------------------------
p3 = ROOT / "ppu_recomp_003.cpp"
s3 = p3.read_text(encoding="utf-8", errors="replace")
i3 = s3.find("void func_002B0FB4")
if i3 < 0:
    raise SystemExit("2B0FB4 not found in 003")
j3 = s3.find("void func_002B2468", i3)
if j3 < 0:
    j3 = i3 + 12000
region3 = s3[i3:j3]

# Insert probe right after VT28R / before flag checks — after the line that stores r24
needle = """        ctx->gpr[24] = ctx->gpr[3] | ctx->gpr[3];
        if (((ctx->cr >> 0) & 2)) { g_trampoline_fn = (void(*)(void*))func_002B0EF4; return; }
        ctx->gpr[0] = vm_read8(ctx->gpr[27] + 0x0);"""

probe = """        ctx->gpr[24] = ctx->gpr[3] | ctx->gpr[3];
        if (((ctx->cr >> 0) & 2)) { g_trampoline_fn = (void(*)(void*))func_002B0EF4; return; }
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<80){
            uint32_t obj=(uint32_t)ctx->gpr[3], flg_ea=(uint32_t)ctx->gpr[27], r29=(uint32_t)ctx->gpr[29];
            uint8_t fb = flg_ea ? vm_read8(flg_ea+0x0) : 0;
            uint32_t oh = obj ? vm_read32(obj+0x0) : 0;
            uint16_t lo = (uint16_t)(oh & 0xFFFF);
            uint32_t mid = (uint32_t)((oh >> 16) & 0xFFF); /* approx of rldicl(,48,52) field interest */
            fprintf(stderr,"[WADLD-GATE] #%d obj=0x%08X hdr=0x%08X lo16=%u mid=%u flagb=0x%02X r29=0x%08X\\n",
              n, obj, oh, (unsigned)lo, mid, fb, r29); fflush(stderr);} } }
        ctx->gpr[0] = vm_read8(ctx->gpr[27] + 0x0);"""

if "WADLD-GATE" in region3:
    print("003: GATE probe already present")
elif needle not in region3:
    raise SystemExit("2B0FB4 gate needle missing")
else:
    region3 = region3.replace(needle, probe, 1)
    # Also probe at VT48 skip conditions near low16==3 check
    needle2 = """        ctx->gpr[9] = vm_read32(ctx->gpr[31] + 0x0);
        ctx->gpr[0] = (uint32_t)ppc_rlwinm((uint32_t)ctx->gpr[9], 0, 16, 31);
        { int64_t a = (int32_t)ctx->gpr[0]; int64_t b = (int64_t)3; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }
        if ((!((ctx->cr >> 0) & 2))) goto loc_002B10B8;
        ctx->gpr[0] = ppc_rldicl(ctx->gpr[9], 48, 52);
        { int64_t a = (int32_t)ctx->gpr[0]; int64_t b = (int64_t)1; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }
        if ((!((ctx->cr >> 0) & 2))) goto loc_002B10B8;"""
    probe2 = """        ctx->gpr[9] = vm_read32(ctx->gpr[31] + 0x0);
        ctx->gpr[0] = (uint32_t)ppc_rlwinm((uint32_t)ctx->gpr[9], 0, 16, 31);
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<40){
            uint32_t w=(uint32_t)ctx->gpr[9], lo=(uint32_t)ctx->gpr[0];
            uint32_t fld=(uint32_t)ppc_rldicl(w, 48, 52);
            fprintf(stderr,"[WADLD-VT48CHK] #%d w=0x%08X lo16=%u fld=%u pass=%d\\n",
              n, w, lo, fld, (lo==3 && fld==1)); fflush(stderr);} } }
        { int64_t a = (int32_t)ctx->gpr[0]; int64_t b = (int64_t)3; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }
        if ((!((ctx->cr >> 0) & 2))) goto loc_002B10B8;
        ctx->gpr[0] = ppc_rldicl(ctx->gpr[9], 48, 52);
        { int64_t a = (int32_t)ctx->gpr[0]; int64_t b = (int64_t)1; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }
        if ((!((ctx->cr >> 0) & 2))) goto loc_002B10B8;"""
    if "WADLD-VT48CHK" not in region3:
        if needle2 not in region3:
            print("WARNING: VT48CHK needle missing (partial patch)")
        else:
            region3 = region3.replace(needle2, probe2, 1)
            print("003: VT48CHK probe added")
    s3 = s3[:i3] + region3 + s3[j3:]
    p3.write_text(s3, encoding="utf-8", newline="\n")
    print("003: GATE probe written")

print("OK patch_factory_opd_gate")
