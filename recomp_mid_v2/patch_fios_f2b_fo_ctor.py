#!/usr/bin/env python3
"""F2B FO via natural guest ctor (0031F1A4 + 00307774) — path hash +0x34.

Replaces hand-stamped FO after movie_io open of /wad/*.wad_ps3.

Natural file_new sequence (func_0030D29C):
  alloc FO → func_0031F1A4(FO) → FO+8=media FO+50=flags
  → func_003044EC(path) → func_00307774(FO+0x30, path)
  → FO+0x30=pathptr FO+0x34=hash → media list link

In-boot 2026-07-21: +34=BBCA40F5 (Lgl) / 8C9CF26A (Perm). Layout matches
natural FO-DUMP. Freelist 0x840000xx after R_Perm DONE still blocks stream
(see notes G4 §20–§21) — FO layout alone is not the remaining wall.

Markers: F2B-FO-CTOR, hash=+34=
Idempotent note: lift is gitignored; re-apply by re-running session edit or
restoring recomp_macos_v2 after re-lift + this note.

Usage: python3 recomp_mid_v2/patch_fios_f2b_fo_ctor.py [recomp_macos_v2]
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "recomp_macos_v2"
MARKER = "F2B-FO-CTOR"


def main() -> int:
    target = ROOT / "ppu_recomp_001.cpp"
    if not target.is_file():
        print(f"missing {target}")
        return 1
    text = target.read_text(errors="replace")
    if MARKER in text or "func_0031F1A4(ctx); DRAIN_TRAMPOLINE(ctx);" in text and "F2B-MOVIEIO" in text:
        # Detect live lift: ctor call inside F2B block
        if "func_00307774(ctx)" in text and "F2B-MOVIEIO" in text:
            print(f"{target.name}: F2B guest ctor already present")
            return 0
    print(f"{target.name}: F2B FO ctor not found — re-apply from session or G4 §21")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
