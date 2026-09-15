#!/usr/bin/env python3
"""Relift GoW2 SPU6 with observed indirect-branch entry points.

The SCREAM policy module is a raw LS image, so automatic ELF function
detection is unavailable.  Preserve the established function boundaries and
add the two targets observed in a real mixer dispatch (0x391C, 0x51F0).
Game bytes remain local: the input dump is deliberately not versioned.
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
INPUT = ROOT / "spu_miss_cedb9a67a0c3a305.bin"
OUTPUT = ROOT / "spu_lifted" / "spu6_v2"
LIFTER = ROOT.parent / "ps3recomp" / "tools" / "spu_lifter.py"
BASE = 0x3000
END = 0x5D00
EXTRA = (0x391C, 0x51F0)


def existing_starts(source: pathlib.Path) -> list[int]:
    starts: list[int] = []
    in_table = False
    for line in source.read_text().splitlines():
        if "static const spu_func_entry spu_function_table[]" in line:
            in_table = True
            continue
        if in_table and line.strip().startswith("{ 0,"):
            break
        if in_table and line.lstrip().startswith("{ 0x"):
            value = line.split("x", 1)[1].split("u", 1)[0]
            start = int(value, 16)
            if BASE <= start < END:
                starts.append(start)
    return sorted(set(starts).union(EXTRA))


def main() -> int:
    if not INPUT.is_file():
        print(f"missing local SPU6 image: {INPUT}", file=sys.stderr)
        return 1
    if not LIFTER.is_file():
        print(f"missing lifter: {LIFTER}", file=sys.stderr)
        return 1

    starts = existing_starts(OUTPUT / "spu_recomp.c")
    bounds = [{"start": hex(a), "end": hex(b)}
              for a, b in zip(starts, starts[1:] + [END])]
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(bounds, f)
        f.write("\n")
        bounds_path = pathlib.Path(f.name)
    try:
        subprocess.run([
            sys.executable, str(LIFTER), str(INPUT), "--base", hex(BASE),
            "--functions", str(bounds_path), "--symbol-prefix", "spu6_",
            "--output", str(OUTPUT),
        ], check=True)
    finally:
        bounds_path.unlink(missing_ok=True)

    source_path = OUTPUT / "spu_recomp.c"
    source = source_path.read_text()
    # 0x3FEC0 is a known no-op helper outside the raw image range.  The
    # previous lift intentionally emitted an empty direct-call target; keep
    # that behavior instead of turning it into an unregistered indirect stub.
    source = source.replace(
        "void spu6_spu_func_0003FEC0(spu_context* ctx) {\n"
        "    ctx->pc = 0x3FEC0u; spu_indirect_branch(ctx);\n"
        "}\n",
        "void spu6_spu_func_0003FEC0(spu_context* ctx) { (void)ctx; }\n",
    )
    source_path.write_text(source)
    for address in EXTRA:
        symbol = f"spu6_spu_func_{address:08X}"
        if f"void {symbol}(spu_context* ctx) {{\n    ctx->pc" in source:
            print(f"unlifted stub remains for {symbol}", file=sys.stderr)
            return 1
    print("SPU6 relift contains observed mixer branch targets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
