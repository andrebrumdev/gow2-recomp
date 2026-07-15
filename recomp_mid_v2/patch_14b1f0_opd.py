#!/usr/bin/env python3
"""
Fix all OPD indirect calls in func_0014B1F0 (asset/component batch dispatcher).

Evidence:
- Loads TOC-0x3D9C → OPD 0x5227F0 → func_00162150 (SHADERSRC type loader)
- 12× ps3_indirect_call on vtable OPDs — same broken class as factory/GroupEnd
- SHADERSRC already runs somehow, but nested OPDs in this dispatcher may skip
  the path that would reach type-map / ICGLdr (0xF85F9B1E via 171244).
"""
from pathlib import Path
import re
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
p = ROOT / "ppu_recomp_000.cpp"
s = p.read_text(encoding="utf-8", errors="replace")

i = s.find("void func_0014B1F0")
if i < 0:
    raise SystemExit("func_0014B1F0 missing")
j = s.find("void func_0014BEAC", i)  # next known func
if j < 0:
    j = s.find("void func_", i + 20)
region = s[i:j]

# Generic OPD block: load opd into gpr[N], code into gpr[0], set ctr/toc, indirect
pat = re.compile(
    r"(        ctx->gpr\[(\d+)\] = vm_read32\(ctx->gpr\[\d+\] \+ 0x[0-9A-Fa-f]+\);\n)"
    r"        ctx->gpr\[0\] = vm_read32\(ctx->gpr\[\2\] \+ 0x0\);\n"
    r"        vm_write64\(ctx->gpr\[1\] \+ 0x28, ctx->gpr\[2\]\);\n"
    r"        ctx->ctr = \(uint32_t\)ctx->gpr\[0\];\n"
    r"        ctx->gpr\[2\] = vm_read32\(ctx->gpr\[\2\] \+ 0x4\);\n"
    r"        ps3_indirect_call\(ctx\); DRAIN_TRAMPOLINE\(ctx\);\n"
    r"        ctx->gpr\[2\] = vm_read64\(ctx->gpr\[1\] \+ 0x28\);"
)

# Alternate order: ctr after toc
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
    return (
        m.group(1)
        + f"        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);\n"
        + f"        ps3_call_opd(ctx, (uint32_t)ctx->gpr[{reg}]); DRAIN_TRAMPOLINE(ctx);\n"
        + f"        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);"
    )

region2, c1 = pat.subn(repl, region)
region3, c2 = pat2.subn(repl, region2)
print(f"replaced pat1={c1} pat2={c2} total_opd_sites={n}")
print(f"remaining indirect in region: {region3.count('ps3_indirect_call')}")

# Add entry probe once
if "WADLD-BATCH" not in region3:
    needle = "void func_0014B1F0(ppu_context* ctx) {\n"
    probe = (
        "void func_0014B1F0(ppu_context* ctx) {\n"
        "        { static int on=-1; if(on<0){extern char* getenv(const char*); "
        "on=(getenv(\"PS3_TRACE_TYMAP\")||getenv(\"PS3_TRACE_LDRSH\"))?1:0;}\n"
        "          if(on){ static int n=0; if(n++<8)\n"
        "            fprintf(stderr,\"[WADLD-BATCH] #%d enter r3=0x%08X r4=0x%08X\\n\",\n"
        "              n,(uint32_t)ctx->gpr[3],(uint32_t)ctx->gpr[4]); fflush(stderr);} }\n"
    )
    if needle in region3:
        region3 = region3.replace(needle, probe, 1)
        print("added BATCH entry probe")

s = s[:i] + region3 + s[j:]
p.write_text(s, encoding="utf-8", newline="\n")
print("OK patch_14b1f0_opd")
