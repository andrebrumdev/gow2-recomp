#!/usr/bin/env python3
"""Idempotent TYPE15 CB56C product experiments (gated PS3_TYPE15_CB56C=1)."""
from pathlib import Path
import sys
from lift_paths import resolve_lift_paths

MARKER = "PS3_TYPE15_CB56C"
# Prefer applying via already-patched tree; this script is for re-lift.

def main():
    paths = resolve_lift_paths(sys.argv[1:], "recomp_macos_v2/ppu_recomp_000.cpp")
    for ps in paths:
        t = Path(ps).read_text()
        if MARKER in t:
            print(f"already: {ps}")
        else:
            print(f"NOT present (apply from gow2-recomp session notes): {ps}")
            sys.exit(1)

if __name__ == "__main__":
    main()
