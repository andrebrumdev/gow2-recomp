#!/usr/bin/env python3
"""Extra probes: richer TYDISP descriptor dump + 171244/GroupStart entry."""
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
C0 = ROOT / "ppu_recomp_000.cpp"
C1 = ROOT / "ppu_recomp_001.cpp"

s1 = C1.read_text(encoding="utf-8", errors="replace")
old = """          { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYDISP")?1:0;}
            if(on){ static int n=0; if(n++<40)
              fprintf(stderr,"[TYDISP] type=%u -> 0x%08X\\n", ty, tgt); } }"""
new = """          { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYDISP")?1:0;}
            if(on){ static int n=0; if(n++<40){
              uint32_t raw=vm_read32(ctx->gpr[4]+0x0);
              uint32_t w1=vm_read32(ctx->gpr[4]+0x4);
              uint32_t w2=vm_read32(ctx->gpr[4]+0x8);
              fprintf(stderr,"[TYDISP] type=%u -> 0x%08X desc=0x%08X raw=0x%08X w1=0x%08X w2=0x%08X r3=0x%08X\\n",
                ty, tgt, (uint32_t)ctx->gpr[4], raw, w1, w2, (uint32_t)ctx->gpr[3]); } } }"""
if "desc=0x%08X raw=" in s1:
    print("TYDISP already enhanced")
elif old not in s1:
    raise SystemExit("TYDISP needle missing")
else:
    C1.write_text(s1.replace(old, new, 1), encoding="utf-8", newline="\n")
    print("TYDISP enhanced")

s0 = C0.read_text(encoding="utf-8", errors="replace")
if "TYMAP-171" in s0:
    print("171 already")
else:
    old2 = """void func_00171244(ppu_context* ctx) {
        vm_write64(ctx->gpr[1] + -0xC0, ctx->gpr[1]); ctx->gpr[1] += -0xC0;"""
    new2 = """void func_00171244(ppu_context* ctx) {
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<32)
            fprintf(stderr,"[TYMAP-171] #%d r3=0x%08X r4=0x%08X\\n", n,(uint32_t)ctx->gpr[3],(uint32_t)ctx->gpr[4]); fflush(stderr);} }
        vm_write64(ctx->gpr[1] + -0xC0, ctx->gpr[1]); ctx->gpr[1] += -0xC0;"""
    if old2 not in s0:
        raise SystemExit("171 entry needle missing")
    s0 = s0.replace(old2, new2, 1)
    print("171 entry probe")

if "TYMAP-GS" in s0:
    print("GS already")
else:
    i = s0.find("void func_00294004")
    if i < 0:
        raise SystemExit("294004 missing")
    # insert after opening brace line
    j = s0.find("{", i)
    nl = s0.find("\n", j) + 1
    probe = (
        '        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}\n'
        '          if(on){ static int n=0; if(n++<32)\n'
        '            fprintf(stderr,"[TYMAP-GS] #%d GroupStartCtor r3=0x%08X r4=0x%08X\\n",\n'
        '              n,(uint32_t)ctx->gpr[3],(uint32_t)ctx->gpr[4]); fflush(stderr);} }\n'
    )
    s0 = s0[:nl] + probe + s0[nl:]
    print("GS ctor probe")

C0.write_text(s0, encoding="utf-8", newline="\n")
print("OK probes2")
