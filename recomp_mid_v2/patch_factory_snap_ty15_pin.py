#!/usr/bin/env python3
"""Idempotent factory/TYPE15 pin fixes for post-AUTO_LOAD product path.

1) PS3_FACT_SNAP_MAX 32 → 128 + LRU (B71 factory 0x400D6808 was dropped)
2) ty15_force_pin_freelist + call after TYPE15 construct
3) Markers for detection after re-lift

Source of truth lives in recomp_macos_v2 (gitignored). Re-apply after lift.
"""
from pathlib import Path
import sys
from lift_paths import resolve_lift_paths

MARKERS = [
    "PS3_FACT_SNAP_MAX 128",
    "ty15_force_pin_freelist",
    "FORCE freelist pin",
]


def main() -> int:
    paths = resolve_lift_paths(sys.argv[1:], "recomp_macos_v2/ppu_recomp_001.cpp")
    rc = 0
    for p in paths:
        if not p.exists():
            print(f"missing {p}")
            rc = 1
            continue
        t = p.read_text(errors="replace")
        ok = all(m in t for m in MARKERS)
        print(f"{'ok' if ok else 'MISSING'}: {p} markers={sum(1 for m in MARKERS if m in t)}/{len(MARKERS)}")
        if not ok:
            rc = 1
            print("  re-apply from session: factory snap LRU + ty15_force_pin_freelist")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
