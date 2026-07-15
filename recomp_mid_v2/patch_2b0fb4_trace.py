#!/usr/bin/env python3
"""Deep-trace func_002B0FB4 (type-1 size!=0 path) for SHGX expand + OPD fix."""
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
p = ROOT / "ppu_recomp_003.cpp"
s = p.read_text(encoding="utf-8", errors="replace")

if 'void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);' not in s:
    old = 'extern "C" void ps3_indirect_call(ppu_context* ctx);'
    if old not in s:
        raise SystemExit("no ps3_indirect_call decl in 003")
    s = s.replace(old, old + '\nextern "C" void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);', 1)
    print("declared ps3_call_opd")

# Replace the entry probe + table lookup + first OPD with richer probe and ps3_call_opd
old = """void func_002B0FB4(ppu_context* ctx) {
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<40){
            uint32_t buf=(uint32_t)ctx->gpr[30], hdr=(uint32_t)ctx->gpr[28], res=(uint32_t)ctx->gpr[29];
            uint32_t np=(uint32_t)ctx->gpr[26];
            char nm[24]; int i; for(i=0;i<20&&np;i++){ uint8_t c=vm_read8(np+i); if(!c){nm[i]=0; break;} nm[i]=(c>=32&&c<127)?(char)c:'.'; }
            nm[20]=0;
            fprintf(stderr,"[WADLD-T1SZ] #%d name='%s' res=0x%08X buf=0x%08X u16_2=%u\\n",
              n, nm, res, buf, (unsigned)vm_read16(buf+0x2)); fflush(stderr);} } }
        ctx->gpr[0] = vm_read16(ctx->gpr[30] + 0x2);
        ctx->gpr[5] = ppc_rldicl(ctx->gpr[30], 0, 32);
        ctx->gpr[28] = vm_read32(ctx->gpr[2] + -0x1568);
        ctx->gpr[0] = (uint32_t)ppc_rlwinm((uint32_t)ctx->gpr[0], 2, 14, 29);
        ctx->gpr[11] = vm_read32((ctx->gpr[28] + ctx->gpr[0]));
        ctx->gpr[3] = ctx->gpr[11] | ctx->gpr[11];
        ctx->gpr[9] = vm_read32(ctx->gpr[11] + 0x0);
        ctx->gpr[10] = vm_read32(ctx->gpr[9] + 0x28);
        ctx->gpr[0] = vm_read32(ctx->gpr[10] + 0x0);
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ctx->ctr = (uint32_t)ctx->gpr[0];
        ctx->gpr[2] = vm_read32(ctx->gpr[10] + 0x4);
        ps3_indirect_call(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        { int64_t a = (int32_t)ctx->gpr[3]; int64_t b = (int64_t)0; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }
        ctx->gpr[24] = ctx->gpr[3] | ctx->gpr[3];
        if (((ctx->cr >> 0) & 2)) { g_trampoline_fn = (void(*)(void*))func_002B0EF4; return; }"""

new = """void func_002B0FB4(ppu_context* ctx) {
        ctx->gpr[0] = vm_read16(ctx->gpr[30] + 0x2);
        ctx->gpr[5] = ppc_rldicl(ctx->gpr[30], 0, 32);
        ctx->gpr[28] = vm_read32(ctx->gpr[2] + -0x1568);
        ctx->gpr[0] = (uint32_t)ppc_rlwinm((uint32_t)ctx->gpr[0], 2, 14, 29);
        ctx->gpr[11] = vm_read32((ctx->gpr[28] + ctx->gpr[0]));
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<64){
            uint32_t buf=(uint32_t)ctx->gpr[30], np=(uint32_t)ctx->gpr[26];
            uint32_t idx=(uint32_t)ctx->gpr[0], tab=(uint32_t)ctx->gpr[28], obj=(uint32_t)ctx->gpr[11];
            uint16_t u0=vm_read16(buf+0x0), u2=vm_read16(buf+0x2);
            uint32_t w0=vm_read32(buf+0x0), w1=vm_read32(buf+0x4), w2=vm_read32(buf+0x8);
            char nm[24]; int i; for(i=0;i<20&&np;i++){ uint8_t c=vm_read8(np+i); if(!c){nm[i]=0; break;} nm[i]=(c>=32&&c<127)?(char)c:'.'; }
            nm[20]=0;
            fprintf(stderr,"[WADLD-T1SZ] #%d name='%s' u0=%u u2=%u w0=0x%08X w1=0x%08X w2=0x%08X idx=0x%X tab=0x%08X obj=0x%08X\\n",
              n, nm, (unsigned)u0, (unsigned)u2, w0, w1, w2, idx, tab, obj); fflush(stderr);} } }
        ctx->gpr[3] = ctx->gpr[11] | ctx->gpr[11];
        ctx->gpr[9] = vm_read32(ctx->gpr[11] + 0x0);
        ctx->gpr[10] = vm_read32(ctx->gpr[9] + 0x28);
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<64)
            fprintf(stderr,"[WADLD-VT28] #%d obj=0x%08X vt=0x%08X opd=0x%08X code=0x%08X\\n",
              n,(uint32_t)ctx->gpr[11],(uint32_t)ctx->gpr[9],(uint32_t)ctx->gpr[10],
              ctx->gpr[10]?vm_read32(ctx->gpr[10]+0x0):0); fflush(stderr);} }
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ps3_call_opd(ctx, (uint32_t)ctx->gpr[10]); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<64)
            fprintf(stderr,"[WADLD-VT28R] #%d r3=0x%08X\\n", n, (uint32_t)ctx->gpr[3]); fflush(stderr);} }
        { int64_t a = (int32_t)ctx->gpr[3]; int64_t b = (int64_t)0; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }
        ctx->gpr[24] = ctx->gpr[3] | ctx->gpr[3];
        if (((ctx->cr >> 0) & 2)) { g_trampoline_fn = (void(*)(void*))func_002B0EF4; return; }"""

if old not in s:
    # try without previous probe (if re-run on clean-ish)
    if "WADLD-VT28" in s:
        print("already has VT28")
        raise SystemExit(0)
    raise SystemExit("needle missing - check 2B0FB4 current content")

s = s.replace(old, new, 1)

# Also fix second OPD (vtable+0x48) in same function
old2 = """        ctx->gpr[10] = vm_read32(ctx->gpr[9] + 0x48);
        ctx->gpr[0] = vm_read32(ctx->gpr[10] + 0x0);
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ctx->ctr = (uint32_t)ctx->gpr[0];
        ctx->gpr[2] = vm_read32(ctx->gpr[10] + 0x4);
        ps3_indirect_call(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        ctx->gpr[4] = ctx->gpr[31] | ctx->gpr[31];
        ctx->gpr[3] = ppc_rldicl(ctx->gpr[3], 0, 32);
        func_002BB064(ctx); DRAIN_TRAMPOLINE(ctx);"""
new2 = """        ctx->gpr[10] = vm_read32(ctx->gpr[9] + 0x48);
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<32)
            fprintf(stderr,"[WADLD-VT48] #%d opd=0x%08X code=0x%08X arg=0x%08X\\n",
              n,(uint32_t)ctx->gpr[10], ctx->gpr[10]?vm_read32(ctx->gpr[10]+0x0):0, (uint32_t)ctx->gpr[31]); fflush(stderr);} }
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ps3_call_opd(ctx, (uint32_t)ctx->gpr[10]); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        ctx->gpr[4] = ctx->gpr[31] | ctx->gpr[31];
        ctx->gpr[3] = ppc_rldicl(ctx->gpr[3], 0, 32);
        func_002BB064(ctx); DRAIN_TRAMPOLINE(ctx);"""

# Only replace within 2B0FB4 if present
i = s.find("void func_002B0FB4")
j = s.find("void func_002B2468", i)  # next function we saw earlier
if i < 0:
    raise SystemExit("2B0FB4 gone")
if j < 0:
    j = i + 8000
region = s[i:j]
if old2 in region:
    region = region.replace(old2, new2, 1)
    s = s[:i] + region + s[j:]
    print("fixed VT48 OPD")
else:
    print("VT48 pattern not found or already fixed")

p.write_text(s, encoding="utf-8", newline="\n")
print("OK patch_2b0fb4_trace")
