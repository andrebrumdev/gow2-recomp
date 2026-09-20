#!/usr/bin/env python3
"""Promote observed spu1 indirect targets into the stable spu1_v2 lift."""
from __future__ import annotations

import pathlib
import re
import os
import subprocess
import sys
import tempfile


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
ENGINE = ROOT.parent / "ps3recomp"
INPUT = ROOT / "spu_hit_2a5c4e67a14505b8.bin"
DEFAULT = ROOT / "spu_lifted" / "spu1_v2"
OBSERVED = HERE / "spu1_observed_indirect_targets.lst"


def observed_paths() -> list[pathlib.Path]:
    paths = [OBSERVED]
    runtime_log = os.environ.get("SPU1_OBSERVED_LOG")
    if runtime_log:
        paths.append(pathlib.Path(runtime_log).resolve())
    return paths


def observed_targets(paths: list[pathlib.Path]) -> list[str]:
    """Return manifest and runtime-log destinations in lift input format."""
    targets: set[int] = set()
    for path in paths:
        text = path.read_text(encoding="utf-8", errors="replace")
        targets.update(int(value, 16) & ~0x3 for value in re.findall(
            r"(?:^\s*target\s+|unknown LS address\s+)0x([0-9a-fA-F]+)\b",
            text, re.MULTILINE | re.IGNORECASE))
    if not targets:
        raise ValueError(f"no observed targets in {', '.join(map(str, paths))}")
    return [f"{target:X}" for target in targets]


def main() -> int:
    target = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else DEFAULT
    if not INPUT.is_file():
        print(f"missing captured spu1 image: {INPUT}", file=sys.stderr)
        return 2
    try:
        paths = observed_paths()
        targets = observed_targets(paths)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix="spu1-observed-") as fresh:
        fresh_c = pathlib.Path(fresh) / "spu_recomp.c"
        lift = subprocess.run([
            sys.executable, str(ENGINE / "tools" / "spu_lifter.py"),
            "--auto-functions", str(INPUT),
            *sum((["--observed-indirect-targets", str(path)] for path in paths), []),
            "--symbol-prefix", "spu1_", "-o", fresh,
        ], check=False)
        if lift.returncode:
            return lift.returncode
        return subprocess.run([
            sys.executable, str(ENGINE / "tools" / "patch_spu_add_entries.py"),
            str(target), str(fresh_c), "spu1_", ",".join(targets),
        ], check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
