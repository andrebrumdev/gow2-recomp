#!/usr/bin/env python3
"""Idempotent: CE03C MovieStop before 2nd Play when st620!=0."""
from pathlib import Path
import sys
from lift_paths import resolve_lift_paths
MARKER = "CE03C pre-Play MovieStop"
def main():
    paths = resolve_lift_paths(sys.argv[1:], "recomp_macos_v2/ppu_recomp_001.cpp")
    rc = 0
    for p in paths:
        t = p.read_text(errors="replace") if p.exists() else ""
        ok = MARKER in t
        print(f"{'ok' if ok else 'MISSING'}: {p}")
        if not ok: rc = 1
    return rc
if __name__ == "__main__":
    raise SystemExit(main())
