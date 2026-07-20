#!/usr/bin/env python3
"""Fix OPD sites in constructors that install vtable with 171244 at +0x8."""
from pathlib import Path
import re
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
p = ROOT / "ppu_recomp_000.cpp"
s = p.read_text(encoding="utf-8", errors="replace")

pat = re.compile(
    r"(        ctx->gpr\[(\d+)\] = vm_read32\(ctx->gpr\[\d+\] \+ 0x[0-9A-Fa-f]+\);\n)"
    r"        ctx->gpr\[0\] = vm_read32\(ctx->gpr\[\2\] \+ 0x0\);\n"
    r"        vm_write64\(ctx->gpr\[1\] \+ 0x28, ctx->gpr\[2\]\);\n"
    r"        ctx->ctr = \(uint32_t\)ctx->gpr\[0\];\n"
    r"        ctx->gpr\[2\] = vm_read32\(ctx->gpr\[\2\] \+ 0x4\);\n"
    r"        ps3_indirect_call\(ctx\); DRAIN_TRAMPOLINE\(ctx\);\n"
    r"        ctx->gpr\[2\] = vm_read64\(ctx->gpr\[1\] \+ 0x28\);"
)

total = 0
for name in ["func_0014A01C", "func_0014AD94"]:
    i = s.find(f"void {name}")
    if i < 0:
        print(name, "missing")
        continue
    j = s.find("void func_", i + 20)
    region = s[i:j]
    state = {"n": 0}

    def repl(m):
        state["n"] += 1
        reg = m.group(2)
        return (
            m.group(1)
            + "        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);\n"
            + f"        ps3_call_opd(ctx, (uint32_t)ctx->gpr[{reg}]); DRAIN_TRAMPOLINE(ctx);\n"
            + "        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);"
        )

    region2, c = pat.subn(repl, region)
    print(f"{name}: fixed {state['n']} remain_indirect={region2.count('ps3_indirect_call')}")
    total += state["n"]
    s = s[:i] + region2 + s[j:]

p.write_text(s, encoding="utf-8", newline="\n")
print("OK total", total)
