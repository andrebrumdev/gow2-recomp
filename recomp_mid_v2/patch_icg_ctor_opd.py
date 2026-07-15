#!/usr/bin/env python3
"""
Fix remaining OPD vcall sites in ICG component ctor/init that still use
ps3_indirect_call (code-from-OPD manual sequence). These run once at boot
(ICG-CTOR/ICG-INIT fire) but may return 0 / skip registration if OPD resolve
or TOC is wrong — blocking later type-map dispatch (171244 → ICGLdr).

Also fix residual indirect in 329490 (ICG-PATH-A) which is on the only
static call chain that reaches 32E200 vt+0x8 → OPD 0x522E70 → 171244.
"""
from pathlib import Path
import re
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent

# Generic OPD block: gpr[OPD] holds OPD EA; code loaded to gpr[0]/ctr; toc to r2
OPD_BLOCK = re.compile(
    r"(        ctx->gpr\[(\d+)\] = vm_read32\(ctx->gpr\[\d+\] \+ 0x[0-9A-Fa-f]+\);\n)"
    r"        ctx->gpr\[(\d+)\] = vm_read32\(ctx->gpr\[\2\] \+ 0x0\);\n"
    r"        vm_write64\(ctx->gpr\[1\] \+ 0x28, ctx->gpr\[2\]\);\n"
    r"        ctx->ctr = \(uint32_t\)ctx->gpr\[\3\];\n"
    r"        ctx->gpr\[2\] = vm_read32\(ctx->gpr\[\2\] \+ 0x4\);\n"
    r"        ps3_indirect_call\(ctx\); DRAIN_TRAMPOLINE\(ctx\);\n"
    r"        ctx->gpr\[2\] = vm_read64\(ctx->gpr\[1\] \+ 0x28\);"
)

OPD_BLOCK2 = re.compile(
    r"(        ctx->gpr\[(\d+)\] = vm_read32\(ctx->gpr\[\d+\] \+ 0x[0-9A-Fa-f]+\);\n)"
    r"        ctx->gpr\[(\d+)\] = vm_read32\(ctx->gpr\[\2\] \+ 0x0\);\n"
    r"        vm_write64\(ctx->gpr\[1\] \+ 0x28, ctx->gpr\[2\]\);\n"
    r"        ctx->gpr\[2\] = vm_read32\(ctx->gpr\[\2\] \+ 0x4\);\n"
    r"        ctx->ctr = \(uint32_t\)ctx->gpr\[\3\];\n"
    r"        ps3_indirect_call\(ctx\); DRAIN_TRAMPOLINE\(ctx\);\n"
    r"        ctx->gpr\[2\] = vm_read64\(ctx->gpr\[1\] \+ 0x28\);"
)

# 329490 residual: OPD in gpr[11], code loaded to gpr[0]
OPD_BLOCK3 = re.compile(
    r"        ctx->gpr\[0\] = vm_read32\(ctx->gpr\[11\] \+ 0x0\);\n"
    r"        ctx->gpr\[4\] = ctx->gpr\[3\] \| ctx->gpr\[3\];\n"
    r"        vm_write64\(ctx->gpr\[1\] \+ 0x28, ctx->gpr\[2\]\);\n"
    r"        ctx->ctr = \(uint32_t\)ctx->gpr\[0\];\n"
    r"        ctx->gpr\[2\] = vm_read32\(ctx->gpr\[11\] \+ 0x4\);\n"
    r"        ps3_indirect_call\(ctx\); DRAIN_TRAMPOLINE\(ctx\);\n"
    r"        ctx->gpr\[2\] = vm_read64\(ctx->gpr\[1\] \+ 0x28\);"
)


def fix_region(region: str, tag: str) -> tuple[str, int]:
    n = 0

    def repl(m):
        nonlocal n
        n += 1
        opd_reg = m.group(2)
        probe = (
            f"        {{ static int on=-1; if(on<0){{extern char* getenv(const char*); "
            f"on=(getenv(\"PS3_TRACE_TYMAP\")||getenv(\"PS3_TRACE_LDRSH\"))?1:0;}}\n"
            f"          if(on){{ static int k=0; if(k++<48)\n"
            f"            fprintf(stderr,\"[{tag}] #%d opd=0x%08X code=0x%08X\\n\",\n"
            f"              k,(uint32_t)ctx->gpr[{opd_reg}], "
            f"ctx->gpr[{opd_reg}]?vm_read32(ctx->gpr[{opd_reg}]+0x0):0); fflush(stderr);}} }}\n"
        )
        return (
            m.group(1)
            + probe
            + "        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);\n"
            + f"        ps3_call_opd(ctx, (uint32_t)ctx->gpr[{opd_reg}]); DRAIN_TRAMPOLINE(ctx);\n"
            + "        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);"
        )

    region, c1 = OPD_BLOCK.subn(repl, region)
    region, c2 = OPD_BLOCK2.subn(repl, region)
    return region, n


def ensure_decl(s: str) -> str:
    if 'void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);' in s[:40000]:
        return s
    old = 'extern "C" void ps3_indirect_call(ppu_context* ctx);'
    if old not in s[:40000]:
        raise SystemExit("no ps3_indirect_call decl")
    return s.replace(old, old + '\nextern "C" void ps3_call_opd(ppu_context* ctx, uint32_t opd_ea);', 1)


def patch_funcs(path: Path, names: list[str], tag: str) -> None:
    s = path.read_text(encoding="utf-8", errors="replace")
    s = ensure_decl(s)
    total = 0
    for name in names:
        i = s.find(f"void {name}")
        if i < 0:
            print(f"  {name}: MISSING")
            continue
        j = s.find("\nvoid func_", i + 20)
        if j < 0:
            j = len(s)
        region = s[i:j]
        before = region.count("ps3_indirect_call")
        region2, n = fix_region(region, tag)
        # 329490 residual pattern
        if name == "func_00329490" and OPD_BLOCK3.search(region2):
            region2 = OPD_BLOCK3.sub(
                "        ctx->gpr[4] = ctx->gpr[3] | ctx->gpr[3];\n"
                "        { static int on=-1; if(on<0){extern char* getenv(const char*); "
                "on=(getenv(\"PS3_TRACE_TYMAP\")||getenv(\"PS3_TRACE_LDRSH\"))?1:0;}\n"
                "          if(on){ static int k=0; if(k++<24)\n"
                "            fprintf(stderr,\"[ICG-PATH-A-OPD] #%d opd=0x%08X code=0x%08X\\n\",\n"
                "              k,(uint32_t)ctx->gpr[11], "
                "ctx->gpr[11]?vm_read32(ctx->gpr[11]+0x0):0); fflush(stderr);} }\n"
                "        vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);\n"
                "        ps3_call_opd(ctx, (uint32_t)ctx->gpr[11]); DRAIN_TRAMPOLINE(ctx);\n"
                "        ctx->gpr[2] = vm_read64(ctx->gpr[1] + 0x28);",
                region2,
                count=1,
            )
            n += 1
        after = region2.count("ps3_indirect_call")
        print(f"  {name}: fixed~{n} indirect {before}->{after} call_opd={region2.count('ps3_call_opd')}")
        total += n
        s = s[:i] + region2 + s[j:]
    path.write_text(s, encoding="utf-8", newline="\n")
    print(f"OK {path.name} total_fixes~{total}")


def main():
    p0 = ROOT / "ppu_recomp_000.cpp"
    p1 = ROOT / "ppu_recomp_001.cpp"
    print("=== 000 ctor/init ===")
    patch_funcs(p0, ["func_0014A01C", "func_0014AD94", "func_00151248"], "ICG-VCALL")
    print("=== 001 path ===")
    patch_funcs(p1, ["func_00329490", "func_0032854C", "func_00328B18"], "ICG-PATH-OPD")


if __name__ == "__main__":
    main()
