#!/usr/bin/env python3
"""Promote observed spu1 indirect targets into the stable spu1_v2 lift."""
from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
ENGINE = ROOT.parent / "ps3recomp"
INPUT = ROOT / "spu_hit_2a5c4e67a14505b8.bin"
DEFAULT = ROOT / "spu_lifted" / "spu1_v2"


def main() -> int:
    target = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else DEFAULT
    if not INPUT.is_file():
        print(f"missing captured spu1 image: {INPUT}", file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix="spu1-observed-") as fresh:
        fresh_c = pathlib.Path(fresh) / "spu_recomp.c"
        lift = subprocess.run([
            sys.executable, str(ENGINE / "tools" / "spu_lifter.py"),
            "--auto-functions", str(INPUT), "--extra-funcs", "0x391C",
            "--symbol-prefix", "spu1_", "-o", fresh,
        ], check=False)
        if lift.returncode:
            return lift.returncode
        return subprocess.run([
            sys.executable, str(ENGINE / "tools" / "patch_spu_add_entries.py"),
            str(target), str(fresh_c), "spu1_", "391C",
        ], check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
