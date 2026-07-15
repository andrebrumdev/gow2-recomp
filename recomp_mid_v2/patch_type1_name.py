#!/usr/bin/env python3
"""Log type-1 stream member names (path that should hit SHGX_*)."""
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
p = ROOT / "ppu_recomp_001.cpp"
s = p.read_text(encoding="utf-8", errors="replace")
if "WADLD-T1" in s:
    print("already")
    raise SystemExit(0)

old = """void func_002B0E78(ppu_context* ctx) {
        vm_write64(ctx->gpr[1] + -0xB0, ctx->gpr[1]); ctx->gpr[1] += -0xB0;
        ctx->gpr[0] = ctx->lr;
        vm_write64(ctx->gpr[1] + 0x88, ctx->gpr[27]);
        ctx->gpr[27] = (int64_t)(int32_t)(ctx->gpr[3] + 8);
        vm_write64(ctx->gpr[1] + 0x90, ctx->gpr[28]);
        ctx->gpr[28] = ctx->gpr[3] | ctx->gpr[3];
        vm_write64(ctx->gpr[1] + 0x80, ctx->gpr[26]);
        ctx->gpr[26] = ppc_rldicl(ctx->gpr[27], 0, 32);
        vm_write64(ctx->gpr[1] + 0x78, ctx->gpr[25]);
        ctx->gpr[3] = ctx->gpr[26] | ctx->gpr[26];
        vm_write64(ctx->gpr[1] + 0x98, ctx->gpr[29]);
        vm_write64(ctx->gpr[1] + 0xA0, ctx->gpr[30]);
        vm_write64(ctx->gpr[1] + 0xA8, ctx->gpr[31]);
        ctx->gpr[30] = ctx->gpr[4] | ctx->gpr[4];
        vm_write64(ctx->gpr[1] + 0x70, ctx->gpr[24]);
        vm_write64(ctx->gpr[1] + 0xC0, ctx->gpr[0]);
        func_002B2BA0(ctx); DRAIN_TRAMPOLINE(ctx);"""

new = """void func_002B0E78(ppu_context* ctx) {
        vm_write64(ctx->gpr[1] + -0xB0, ctx->gpr[1]); ctx->gpr[1] += -0xB0;
        ctx->gpr[0] = ctx->lr;
        vm_write64(ctx->gpr[1] + 0x88, ctx->gpr[27]);
        ctx->gpr[27] = (int64_t)(int32_t)(ctx->gpr[3] + 8);
        vm_write64(ctx->gpr[1] + 0x90, ctx->gpr[28]);
        ctx->gpr[28] = ctx->gpr[3] | ctx->gpr[3];
        vm_write64(ctx->gpr[1] + 0x80, ctx->gpr[26]);
        ctx->gpr[26] = ppc_rldicl(ctx->gpr[27], 0, 32);
        vm_write64(ctx->gpr[1] + 0x78, ctx->gpr[25]);
        ctx->gpr[3] = ctx->gpr[26] | ctx->gpr[26];
        vm_write64(ctx->gpr[1] + 0x98, ctx->gpr[29]);
        vm_write64(ctx->gpr[1] + 0xA0, ctx->gpr[30]);
        vm_write64(ctx->gpr[1] + 0xA8, ctx->gpr[31]);
        ctx->gpr[30] = ctx->gpr[4] | ctx->gpr[4];
        vm_write64(ctx->gpr[1] + 0x70, ctx->gpr[24]);
        vm_write64(ctx->gpr[1] + 0xC0, ctx->gpr[0]);
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<80){
            uint32_t np=(uint32_t)ctx->gpr[3], bp=(uint32_t)ctx->gpr[30];
            char nm[24]; int i; for(i=0;i<20;i++){ uint8_t c=vm_read8(np+i); if(!c){nm[i]=0; break;} nm[i]=(c>=32&&c<127)?(char)c:'.'; }
            nm[20]=0;
            fprintf(stderr,"[WADLD-T1] #%d name='%s' namep=0x%08X buf=0x%08X\\n", n, nm, np, bp); fflush(stderr);} } }
        func_002B2BA0(ctx); DRAIN_TRAMPOLINE(ctx);"""

if old not in s:
    raise SystemExit("needle missing")
p.write_text(s.replace(old, new, 1), encoding="utf-8", newline="\n")
print("OK type1 name probe")
