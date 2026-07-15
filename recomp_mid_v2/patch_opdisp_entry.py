#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
p = ROOT / "ppu_recomp_001.cpp"
s = p.read_text(encoding="utf-8", errors="replace")
if "OPDISP-ENT" in s:
    print("already")
    raise SystemExit(0)
old = "void func_002A209C(ppu_context* ctx) {\n        { int64_t a = (int64_t)ctx->gpr[4];"
new = """void func_002A209C(ppu_context* ctx) {
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<16)
            fprintf(stderr,"[OPDISP-ENT] #%d r3=0x%08X r4=0x%08X r5=0x%08X\\n",n,(uint32_t)ctx->gpr[3],(uint32_t)ctx->gpr[4],(uint32_t)ctx->gpr[5]); fflush(stderr);} }
        { int64_t a = (int64_t)ctx->gpr[4];"""
if old not in s:
    raise SystemExit("needle missing")
p.write_text(s.replace(old, new, 1), encoding="utf-8", newline="\n")
print("OK entry probe")
