#!/usr/bin/env python3
"""F2B stream: freelist tag guard + host STREAM-PUMP after WAD open DONE.

Measured 2026-07-21 Mac arm64:
  - Guest never submits 002B3D1C for R_PermA (freelist desync first).
  - FREELIST-TAG-GUARD in func_00263178: [node+4] with bit31 → abort r3=0
    (stops UNCOMMITTED-HI flood 0x840000xx).
  - ALLOC-NULL-GUARD in 2550C8/2550E8: sub-alloc r3=0 → no stamp@EA0.
  - F2B-STREAM-PUMP after 4274 DONE: rebind container limit/cursor per FO,
    loop ps3_fios_aread_hle into 0x40080000 until size.
  - In-boot: R_PermA bytes_read=20169344 preads=154 GATE-FORCE full.

Markers: FREELIST-TAG-GUARD, ALLOC-NULL-GUARD, F2B-STREAM-PUMP
Lift gitignored — re-apply after re-lift from session / G4 §22.

Usage: python3 recomp_mid_v2/patch_fios_stream_pump.py [recomp_macos_v2]
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "recomp_macos_v2"


def main() -> int:
    ok = 0
    for name, marker in (
        ("ppu_recomp_000.cpp", "FREELIST-TAG-GUARD"),
        ("ppu_recomp_000.cpp", "ALLOC-NULL-GUARD"),
        ("ppu_recomp_002.cpp", "ALLOC-NULL-GUARD"),
        ("ppu_recomp_001.cpp", "F2B-STREAM-PUMP"),
    ):
        path = ROOT / name
        if not path.is_file():
            print(f"missing {path}")
            return 1
        text = path.read_text(errors="replace")
        if marker in text:
            print(f"{name}: {marker} present")
            ok += 1
        else:
            print(f"{name}: {marker} MISSING")
    return 0 if ok >= 3 else 2


if __name__ == "__main__":
    raise SystemExit(main())
