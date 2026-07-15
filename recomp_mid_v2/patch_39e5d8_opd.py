#!/usr/bin/env python3
"""Fix nested OPDs in GroupEnd finalize chain (0039E5D8 and sibling 0039E* helpers)."""
from pathlib import Path
import re
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
p = ROOT / "ppu_recomp_001.cpp"
s = p.read_text(encoding="utf-8", errors="replace")

TARGETS = [
    "func_0039E5D8",  # GroupEnd nested finalize (hot)
    "func_0039E794",  # sibling factory-like
    "func_0039E18C",
    "func_0039EE64",
    "func_0039E6B4",  # already patched but re-check
]

def patch_region(region: str, name: str) -> str:
    n = 0
    # vt+0x4C via gpr[11]
    old4c = """        ctx->gpr[11] = vm_read32(ctx->gpr[9] + 0x4C);
        ctx->gpr[0] = vm_read32(ctx->gpr[11] + 0x0);
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ctx->ctr = (uint32_t)ctx->gpr[0];
        ctx->gpr[2] = vm_read32(ctx->gpr[11] + 0x4);
        ps3_indirect_call(ctx); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);"""
    new4c = """        ctx->gpr[11] = vm_read32(ctx->gpr[9] + 0x4C);
        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);
        ps3_call_opd(ctx, (uint32_t)ctx->gpr[11]); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);"""
    while old4c in region:
        region = region.replace(old4c, new4c, 1)
        n += 1

    # generic: gpr[10] = vt+imm; load code; indirect
    old10 = re.compile(
        r"(        ctx->gpr\[10\] = vm_read32\(ctx->gpr\[9\] \+ 0x[0-9A-Fa-f]+\);\n)"
        r"        ctx->gpr\[0\] = vm_read32\(ctx->gpr\[10\] \+ 0x0\);\n"
        r"        vm_write64\(ctx->gpr\[1\] \+ 0x28, ctx->gpr\[2\]\);\n"
        r"        ctx->ctr = \(uint32_t\)ctx->gpr\[0\];\n"
        r"        ctx->gpr\[2\] = vm_read32\(ctx->gpr\[10\] \+ 0x4\);\n"
        r"        ps3_indirect_call\(ctx\); DRAIN_TRAMPOLINE\(ctx\);\n"
        r"        ctx->gpr\[2\] = vm_read64\(ctx->gpr\[1\] \+ 0x28\);"
    )
    def repl10(m):
        nonlocal n
        n += 1
        return (
            m.group(1)
            + "        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);\n"
            + "        ps3_call_opd(ctx, (uint32_t)ctx->gpr[10]); DRAIN_TRAMPOLINE(ctx);\n"
            + "        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);"
        )
    region2, k = old10.subn(repl10, region)
    region = region2
    # probe on 39E5D8 second call result
    if name == "func_0039E5D8" and "WADLD-FIN" not in region:
        # after second call_opd near end, before restore
        needle = """        ps3_call_opd(ctx, (uint32_t)ctx->gpr[10]); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0xA0);
        ctx->gpr[28] = vm_read64(ctx->gpr[1] + 0x70);"""
        probe = """        ps3_call_opd(ctx, (uint32_t)ctx->gpr[10]); DRAIN_TRAMPOLINE(ctx);
        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);
        { static int on=-1; if(on<0){extern char* getenv(const char*); on=getenv("PS3_TRACE_TYMAP")?1:0;}
          if(on){ static int n=0; if(n++<32)
            fprintf(stderr,"[WADLD-FIN] #%d r3=0x%08X opd=0x%08X\\n",
              n,(uint32_t)ctx->gpr[3],(uint32_t)ctx->gpr[10]); fflush(stderr);} }
        ctx->gpr[0] = vm_read64(ctx->gpr[1] + 0xA0);
        ctx->gpr[28] = vm_read64(ctx->gpr[1] + 0x70);"""
        if needle in region:
            region = region.replace(needle, probe, 1)
            print(f"  {name}: FIN probe")
    print(f"  {name}: fixed {n} OPD sites")
    return region

total = 0
for name in TARGETS:
    i = s.find(f"void {name}")
    if i < 0:
        print(f"skip missing {name}")
        continue
    j = s.find("void func_", i + 10)
    if j < 0:
        j = i + 8000
    region = s[i:j]
    if "ps3_indirect_call" not in region and "WADLD-FIN" in region:
        print(f"{name}: already clean")
        continue
    new_region = patch_region(region, name)
    if new_region != region:
        s = s[:i] + new_region + s[j:]
        total += 1

p.write_text(s, encoding="utf-8", newline="\n")
print(f"OK patched {total} functions")
