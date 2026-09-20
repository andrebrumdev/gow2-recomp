#!/usr/bin/env python3
"""Promote the observed spu0 indirect target without replacing its stable lift.

The full spu0_v3 lift contains 0x391C but regresses gameplay when used as a
whole. Import only that entry into spu0_v2, preserving every established v2
function. The shared importer also follows missing direct dependencies and is
idempotent, so this survives a re-lift of the production directory.
"""
from __future__ import annotations

import pathlib
import subprocess
import sys


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
ENGINE = ROOT.parent / "ps3recomp"
DEFAULT = ROOT / "spu_lifted" / "spu0_v2"
FRESH = ROOT / "spu_lifted" / "spu0_v3" / "spu_recomp.c"


def main() -> int:
    target = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else DEFAULT
    if not FRESH.is_file():
        print(f"missing reference lift with 0x391C: {FRESH}", file=sys.stderr)
        return 2
    return subprocess.run([
        sys.executable, str(ENGINE / "tools" / "patch_spu_add_entries.py"),
        str(target), str(FRESH), "spu0_", "391C",
    ], check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
