#!/usr/bin/env python3
"""Idempotent markers: CE03C wait-idle + F2B movie re-open (2nd Play wall).

Survives re-lift only as a *check* script — apply edits live in
recomp_macos_v2/ppu_recomp_001.cpp (gitignored). Re-apply by re-running
the bring-up edit if markers go missing after lift.
"""
from pathlib import Path
import sys
from lift_paths import resolve_lift_paths

MARKERS = [
    "CE03C wait-idle 1st movie",
    "CE03C idle ok → Play#2",
    "CE03C skip Play#2",
    "const uint64_t _sv_r30 = ctx->gpr[30]",
    'strstr(_pt,"movies")',
    'strstr(_pt,".m2v")',
    "PS3_CE03C_PLAY2",
]

def main():
    paths = resolve_lift_paths(sys.argv[1:], "recomp_macos_v2/ppu_recomp_001.cpp")
    rc = 0
    for p in paths:
        t = p.read_text(errors="replace") if p.exists() else ""
        missing = [m for m in MARKERS if m not in t]
        if missing:
            print(f"MISSING ({p}): {missing}")
            rc = 1
        else:
            print(f"ok: {p} ({len(MARKERS)} markers)")
    return rc

if __name__ == "__main__":
    raise SystemExit(main())
