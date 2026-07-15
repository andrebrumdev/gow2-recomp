#!/usr/bin/env python3
"""Log type-1 name lookup result (r3 after 2B2BA0) for SHGX path."""
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
p = ROOT / "ppu_recomp_001.cpp"
s = p.read_text(encoding="utf-8", errors="replace")
if "WADLD-T1R" in s:
    print("already")
    raise SystemExit(0)

old = """        func_002B2BA0(ctx); DRAIN_TRAMPOLINE(ctx);
        /* nop */;
        ctx->gpr[25] = vm_read32(ctx->gpr[28] + 0x4);
        ctx->gpr[31] = ctx->gpr[3] | ctx->gpr[3];
        { int64_t a = (int32_t)ctx->gpr[25]; int64_t b = (int64_t)0; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }
        ctx->gpr[4] = ppc_rldicl(ctx->gpr[28], 0, 32);
        ctx->gpr[29] = ctx->gpr[3] | ctx->gpr[3];
        if ((!((ctx->cr >> 0) & 2))) { g_trampoline_fn = (void(*)(void*))func_002B0FB4; return; }
        { int64_t a = (int32_t)ctx->gpr[3]; int64_t b = (int64_t)0; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }
        if (((ctx->cr >> 0) & 2)) goto loc_002B0F2C;"""

new = """        func_002B2BA0(ctx); DRAIN_TRAMPOLINE(ctx);
        /* nop */;
        ctx->gpr[25] = vm_read32(ctx->gpr[28] + 0x4);
        ctx->gpr[31] = ctx->gpr[3] | ctx->gpr[3];
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<80){
            uint32_t np=(uint32_t)ctx->gpr[26], res=(uint32_t)ctx->gpr[3], sz=(uint32_t)ctx->gpr[25], buf=(uint32_t)ctx->gpr[30];
            char nm[24]; int i; for(i=0;i<20;i++){ uint8_t c=vm_read8(np+i); if(!c){nm[i]=0; break;} nm[i]=(c>=32&&c<127)?(char)c:'.'; }
            nm[20]=0;
            fprintf(stderr,"[WADLD-T1R] #%d name='%s' result=0x%08X size=%u buf=0x%08X hit=%d\\n",
              n, nm, res, sz, buf, res!=0); fflush(stderr);} } }
        { int64_t a = (int32_t)ctx->gpr[25]; int64_t b = (int64_t)0; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }
        ctx->gpr[4] = ppc_rldicl(ctx->gpr[28], 0, 32);
        ctx->gpr[29] = ctx->gpr[3] | ctx->gpr[3];
        if ((!((ctx->cr >> 0) & 2))) { g_trampoline_fn = (void(*)(void*))func_002B0FB4; return; }
        { int64_t a = (int32_t)ctx->gpr[3]; int64_t b = (int64_t)0; uint32_t cr_val = (a < b) ? 8 : (a > b) ? 4 : 2; ctx->cr = (ctx->cr & ~(0xFu << 0)) | (cr_val << 0); }
        if (((ctx->cr >> 0) & 2)) goto loc_002B0F2C;"""

if old not in s:
    raise SystemExit("needle missing")
p.write_text(s.replace(old, new, 1), encoding="utf-8", newline="\n")
print("OK T1R probe")
