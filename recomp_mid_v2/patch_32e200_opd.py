#!/usr/bin/env python3
"""
Fix OPD calls in func_0032E200 — candidate path that vcalls method +0x8.

If this-object vtable is 0x5130B8, method +0x8 is OPD 0x522E70 → func_00171244
(the only stream dispatcher that can reach ICGLdr via type-map lookup).
"""
from pathlib import Path
import re
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
p = ROOT / "ppu_recomp_003.cpp"
s = p.read_text(encoding="utf-8", errors="replace")

if 'void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);' not in s[:30000]:
    old = 'extern "C" void ps3_indirect_call(ppu_context* ctx);'
    if old not in s[:30000]:
        raise SystemExit("no ps3_indirect_call decl in 003")
    s = s.replace(old, old + '\nextern "C" void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);', 1)
    print("003: declared ps3_call_opd")

i = s.find("void func_0032E200")
if i < 0:
    raise SystemExit("32E200 missing")
# next function after this one
j = s.find("\nvoid func_", i + 20)
if j < 0:
    j = i + 20000
else:
    j += 1  # keep at start of next void? actually find returns \nvoid - we want from i to j
    # s[i:j] where j points to \n before next - need next void start
    j = s.find("void func_", i + 20)

region = s[i:j]
n_before = region.count("ps3_indirect_call")

pat = re.compile(
    r"(        ctx->gpr\[(\d+)\] = vm_read32\(ctx->gpr\[\d+\] \+ 0x[0-9A-Fa-f]+\);\n)"
    r"        ctx->gpr\[0\] = vm_read32\(ctx->gpr\[\2\] \+ 0x0\);\n"
    r"        vm_write64\(ctx->gpr\[1\] \+ 0x28, ctx->gpr\[2\]\);\n"
    r"        ctx->ctr = \(uint32_t\)ctx->gpr\[0\];\n"
    r"        ctx->gpr\[2\] = vm_read32\(ctx->gpr\[\2\] \+ 0x4\);\n"
    r"        ps3_indirect_call\(ctx\); DRAIN_TRAMPOLINE\(ctx\);\n"
    r"        ctx->gpr\[2\] = vm_read64\(ctx->gpr\[1\] \+ 0x28\);"
)
pat2 = re.compile(
    r"(        ctx->gpr\[(\d+)\] = vm_read32\(ctx->gpr\[\d+\] \+ 0x[0-9A-Fa-f]+\);\n)"
    r"        ctx->gpr\[0\] = vm_read32\(ctx->gpr\[\2\] \+ 0x0\);\n"
    r"        vm_write64\(ctx->gpr\[1\] \+ 0x28, ctx->gpr\[2\]\);\n"
    r"        ctx->gpr\[2\] = vm_read32\(ctx->gpr\[\2\] \+ 0x4\);\n"
    r"        ctx->ctr = \(uint32_t\)ctx->gpr\[0\];\n"
    r"        ps3_indirect_call\(ctx\); DRAIN_TRAMPOLINE\(ctx\);\n"
    r"        ctx->gpr\[2\] = vm_read64\(ctx->gpr\[1\] \+ 0x28\);"
)

n = 0
def repl(m):
    global n
    n += 1
    reg = m.group(2)
    probe = ""
    if n <= 16:
        probe = (
            f"        {{ static int on=-1; if(on<0){{extern char* getenv(const char*); "
            f"on=(getenv(\"PS3_TRACE_TYMAP\")||getenv(\"PS3_TRACE_LDRSH\"))?1:0;}}\n"
            f"          if(on){{ static int k=0; if(k++<48)\n"
            f"            fprintf(stderr,\"[CMP-VCALL] #%d opd=0x%08X code=0x%08X\\n\",\n"
            f"              k,(uint32_t)ctx->gpr[{reg}], "
            f"ctx->gpr[{reg}]?vm_read32(ctx->gpr[{reg}]+0x0):0); fflush(stderr);}} }}\n"
        )
    return (
        m.group(1)
        + probe
        + f"        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);\n"
        + f"        ps3_call_opd(ctx, (uint32_t)ctx->gpr[{reg}]); DRAIN_TRAMPOLINE(ctx);\n"
        + f"        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);"
    )

region, c1 = pat.subn(repl, region)
region, c2 = pat2.subn(repl, region)
print(f"32E200: fixed {n} OPD sites (pat1={c1} pat2={c2}), remaining indirect={region.count('ps3_indirect_call')}")

if "CMP-ENTER" not in region:
    needle = "void func_0032E200(ppu_context* ctx) {\n"
    probe = (
        "void func_0032E200(ppu_context* ctx) {\n"
        "        { static int on=-1; if(on<0){extern char* getenv(const char*); "
        "on=(getenv(\"PS3_TRACE_TYMAP\")||getenv(\"PS3_TRACE_LDRSH\"))?1:0;}\n"
        "          if(on){ static int n=0; if(n++<16)\n"
        "            fprintf(stderr,\"[CMP-ENTER] #%d r3=0x%08X r4=0x%08X\\n\",\n"
        "              n,(uint32_t)ctx->gpr[3],(uint32_t)ctx->gpr[4]); fflush(stderr);} }\n"
    )
    if needle in region:
        region = region.replace(needle, probe, 1)
        print("added CMP-ENTER probe")

s = s[:i] + region + s[j:]
p.write_text(s, encoding="utf-8", newline="\n")
print("OK patch_32e200_opd")
