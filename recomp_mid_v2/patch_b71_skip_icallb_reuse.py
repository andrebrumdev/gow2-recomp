#!/usr/bin/env python3
"""Idempotent B71 skip-icallB when product was reuse-salvaged + CB56C prefer real product.

Markers in ppu_recomp_000.cpp (gitignored lift).
"""
from pathlib import Path
import sys
from lift_paths import resolve_lift_paths

MARKERS = [
    "g_b71_product_reused",
    "B71 skip icallB (reuse product",
    "was_shell=%d",
    "PS3_TYPE15_CB56C",
]


def main() -> int:
    paths = resolve_lift_paths(sys.argv[1:], "recomp_macos_v2/ppu_recomp_000.cpp")
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
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
